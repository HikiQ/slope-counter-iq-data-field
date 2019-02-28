using Toybox.FitContributor;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class SlopeCounterView extends WatchUi.SimpleDataField {

    // enums for states
    enum {
        DOWNHILL = 0,
        FLAT,
        UPHILL,
        STATE_COUNT
    }

    // shown in UI for given state
    // cannot return strings var state_marker = ["v ", "^ "];

    // enums for moving direction (observations for the model)
    enum {
        DOWN = 0,
        LEVEL,
        UP,
        OBSERVATION_COUNT
    }

    // set to true when timer is running, false on pause and stop
    protected var is_running = false;

    // warmup period to fill the filter
    protected var warmup = null;
    protected var warmup_iterations = null;

    // filter length
    protected var filter_length = 5;
    // truncation of the array when filtering with truncated mean
    protected var filter_mean_truncation = 0;
    // this must be odd size when a median filter is used. for truncated mean, can be anything
    protected var filter_array = null;
    // filter array is used as a circular buffer
    protected var filter_array_idx = -1;

    // vertical speed calculation needs the previous altitude
    protected var current_altitude = 0;

    // moving vertical speed limit (m/s)
    protected var vertical_speed_limit = null; // init in load settings  0.3;

    // Slopes can only start when uphill is found between them
    protected var uphill_encountered = null;

    // last slope end time to filter slopes starting too close to each other
    protected var previous_slope_end_time = null;

    // last slopes end altitude to compare if we have a really slow uphill between slopes
    protected var previous_slope_end_altitude = null;

    // minimum time from last slopes end to start a new run
    protected var minimum_time_from_last_slope_end = null; // init in load settings new Time.Duration(30);

    // minimum altitude difference between the end of the previous slope to the start of a new slope in meters
    // used if we have moved really slowly uphill and no uphill is encountered because of the speed
    protected var minimum_altitude_gain_from_slope_end = null; // init in load setting 100.0

    // Hidden markov model (see states and observations) -->
    protected var start_probability = [0.0, 1.0, 0.0];

    // transition probabilities
    //protected var a = 0.0001;
    protected var transition_probability = null; // init in load settings [[1-a, a, 0], [a/2.0, 1-a, a/2.0], [0, a, 1-a]];

    // emission probabilities for each observation given a state
    protected var emission_probability = [[0.6, 0.2, 0.2], [0.1, 0.8, 0.1], [0.2, 0.2, 0.6]];

    // the probability for the current state and previous state (forward algorithm)
    protected var alpha = null;
    protected var previous_alpha = null;

    // <-- model end

    // fit contributions -->
    // graph
    protected var slope_transition_graph_field = null;

    // slope count
    protected var slope_count_field = null;

    // <-- fit contributions

    // current state
    protected var current_state = null;

    // THE VALUE to show to the user
    protected var number_of_slopes = 0;

    /*
    Initializes the data field and model. Loads settings and sets the field label.
    */
    function initialize() {
        System.println("SlopeCounter::initialize");
        SimpleDataField.initialize();
        loadSettings();
        label = "Runs";

        init_altitude_filter();
        init_model();
        init_fit_contributor();
    }

    /*
    Called from the main app
    */
    function onSettingsChanged() {
        loadSettings();
    }

    /**
    All these settings can be changes on the fly.
    */
    protected function loadSettings() {
        System.println("SlopeCounter::loadSettings");
        var app = Application.getApp();

        var vertical_speed_threshold = app.getProperty("verticalSpeedThreshold");
        var min_delay_for_new_slope = app.getProperty("minDelayForNewSlope");
        var min_altitude_gain_for_new_slope = app.getProperty("minAltitudeGainForNewSlope");
        var negativeLogTransitionProbability = app.getProperty("negativeLogTransitionProbability");

        vertical_speed_limit = (vertical_speed_threshold != null && vertical_speed_threshold.toFloat() >= 0.2) ?
            vertical_speed_threshold.toFloat() : 0.2;
        //
        minimum_time_from_last_slope_end = (min_delay_for_new_slope != null && min_delay_for_new_slope.toNumber() >= 0) ?
            new Time.Duration(min_delay_for_new_slope.toNumber()) : new Time.Duration(30);
        //
        minimum_altitude_gain_from_slope_end = (min_altitude_gain_for_new_slope != null && min_altitude_gain_for_new_slope.toFloat() >= 10) ?
            min_altitude_gain_for_new_slope.toFloat() : 100.0;
        //
        var a = (negativeLogTransitionProbability != null && negativeLogTransitionProbability.toNumber() >= 1) ?
            negativeLogTransitionProbability.toNumber() : 4;

        a = Math.pow(10, -a);
        transition_probability = [[1-a, a, 0], [a/2.0, 1-a, a/2.0], [0, a, 1-a]];
    }

    /*
    Create filter array
    */
    protected function init_altitude_filter() {
        filter_array = [];
        for (var i = 0; i < filter_length; i++) {
           filter_array.add(0.0);
        }
    }

    /*
    Init HMM
    */
    protected function init_model() {
        // alpha values are always overwritten inside the forward algorithm
        alpha = [];
        for (var i = 0; i < STATE_COUNT; i++) {
            alpha.add(0.0);
        }

        previous_alpha = start_probability.slice(null, null);
        previous_slope_end_time = new Time.Moment(0);
        previous_slope_end_altitude = 0;
        current_state = FLAT;
        uphill_encountered = true;
    }

    /*
    Initialize the fit contributor data fields for writing
    the slope data to a fit file
    */
    protected function init_fit_contributor() {
        slope_transition_graph_field = createField(
            "slope_transition_graph",
            0,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>"#"}
            );

        slope_count_field = createField(
            "slope_count",
            1,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION, :units=>"#"}
            );
    }

    // Timer functions ---------------->
    function onTimerStart() {
        System.println("SlopeCounter::onTimerStart");
        warmup = true;
        warmup_iterations = filter_length-1;
        uphill_encountered = true;
        is_running = true;
    }

    function onTimerPause() {
        System.println("SlopeCounter::onTimerPause");
        is_running = false;
    }

    function onTimerResume() {
        System.println("SlopeCounter::onTimerResume");
        warmup = true;
        warmup_iterations = filter_length-1;
        uphill_encountered = true;
        is_running = true;
    }

    function onTimerStop() {
        System.println("SlopeCounter::onTimerStop");
        is_running = false;
        slope_count_field.setData(number_of_slopes);
    }

    function onTimerReset() {
        System.println("SlopeCounter::onTimerReset");
        is_running = false;
        number_of_slopes = 0;
    }

    // <----------------- Timer functions

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        if (!is_running) {
            //return Lang.format("-$1$-", [number_of_slopes]);
            return number_of_slopes;
        }

        // warmup for the first iterations
        if (warmup) {
            warmup_phase(info.altitude);
            //return "~";
            return number_of_slopes;
        }

        // calculate filtered speed and discretize it to DOWN, LEVEL, UP)
        var vertical_speed = get_filtered_vertical_speed(info.altitude);
        var moving_direction = discretize_vertical_speed(vertical_speed);

        // runs the hidden markov model for this iteration. does not update current state yet
        var previous_state = current_state;
        var most_probable_state = forward_algorithm(moving_direction);
        current_state = most_probable_state;

        // conditions for the minimum time between the last slope's end and a the proposed run
        // and that there is uphill between slopes
        check_if_slope_count_increases(previous_state, current_state);

        // update fit data
        slope_transition_graph_field.setData(number_of_slopes);

        // return the value to show
        //return Lang.format("$1$$2$", [state_marker[current_state], number_of_slopes]);

        if (current_state == UPHILL) {
            return -number_of_slopes;
        } else {
            return number_of_slopes;
        }
    }


    /*
    Wait untill we have n vertical speed estimates to fill the filter
    */
    protected function warmup_phase(altitude) {
        System.println("SlopeCounter::warmup_phase");
        if (get_filtered_vertical_speed(altitude) != null) {
            warmup_iterations -= 1;
            if (warmup_iterations <= 0) {
                warmup = false;
            }
        }
    }


    /*
    Calculates the vertical speed from current and the previous altitude
    altitude : altitude as found in the info struct
    */
    protected function get_filtered_vertical_speed(altitude) {
        if (altitude == null) {
            return null;
        }

        // add to the filter array
        filter_array_idx += 1;
        filter_array_idx %= filter_array.size();
        filter_array[filter_array_idx] = altitude;

        // use the mean of the altitude
        // discretization discards spikes from derivative
        // but large spikes stay in the filter array for the time of the filter's length
        altitude = mean(filter_array);

        // use the median of the altitude for speed estimate, reverse the arrays when going downhill for speedup in sorting
        // altitude = median(filter_array, current_state == DOWNHILL);

        // use the truncated mean of the altitude for speed estimate, reverse the arrays when going downhill for speedup in sorting
        //altitude = truncated_mean(filter_array, current_state == DOWNHILL, filter_mean_truncation);

        // calculate the difference to the previous altitude
        var altitude_delta = altitude - current_altitude;

        // update previous altitude
        current_altitude = altitude;

        //System.println(filter_array);
        //System.println(altitude);
        //System.println(altitude_delta);

        // value is in m/s
        return altitude_delta;
    }


    /**
    Discretize the moving direction to DOWN, LEVEL and UP based on the speed limit
    */
    protected function discretize_vertical_speed(vertical_speed) {
        if (vertical_speed <= -vertical_speed_limit) {
            return DOWN;
        } else if (vertical_speed >= vertical_speed_limit) {
            return UP;
        } else {
            return LEVEL;
        }
    }


    /*
    Calculates the most probable state of the hidden markov model using a forward algorithm
    observation : discretized observation (DOWN, LEVEL, UP) to prevent spike effects
    */
    protected function forward_algorithm(observation) {
        var p_observation_given_state = 0;
        var p_transition = 0;
        var path_probability = 0;

        // calculate the probability of all the possible states
        for (var state = 0; state < STATE_COUNT; state++) {
            p_observation_given_state = emission_probability[state][observation];

            // loop over all the possible previous states
            path_probability = 0;
            for (var previous_state = 0; previous_state < STATE_COUNT; previous_state++) {
                p_transition = transition_probability[previous_state][state];
                path_probability += p_transition * previous_alpha[previous_state]; // previous_alpha is a class member
            }
            alpha[state] = p_observation_given_state * path_probability;
        }

        // sum over the state probabilities alpha to normalize to sum to one
        var s = 0;
        for (var state = 0; state < STATE_COUNT; state++) {
            s += alpha[state];
        }

        // normalize and find the most probable state
        var p = null;
        var max_probability = -1;
        var most_probable_state = null;
        for (var state = 0; state < STATE_COUNT; state++) {
            alpha[state] /= s;
            p = alpha[state];
            previous_alpha[state] = p;

            if (p > max_probability) {
                max_probability = p;
                most_probable_state = state;
            }
        }

        return most_probable_state;
    }

    /*
    Do not completely trust the HMM but also check that enough time has passed since last transition to downhill
    for the number of runs calculation and there is an uphill between the slopes

    previous_state : the state we were in previous iteration
    new_state : new state from HMM
    */
    protected function check_if_slope_count_increases(previous_state, new_state) {

        // current state is still the previous state
        if (new_state != previous_state) {
            var now = Time.now();
            var hysteresis = previous_slope_end_time.add(minimum_time_from_last_slope_end);

            var enough_altitude_gain_from_last_slope_end = previous_slope_end_altitude + minimum_altitude_gain_from_slope_end < current_altitude;
            var uphill_between_slopes = uphill_encountered || enough_altitude_gain_from_last_slope_end;

            if (new_state == DOWNHILL && uphill_between_slopes && now.greaterThan(hysteresis)) {
                // new state is downhill
                // and there was an uphill since last downhill
                // and enough time has passed from the last change
                number_of_slopes += 1;
                uphill_encountered = false;
                slope_count_field.setData(number_of_slopes);

            } else if (previous_state == DOWNHILL) {
                // current state is downhill and we are moving to some other state
                previous_slope_end_time = now;
                previous_slope_end_altitude = current_altitude;

            } else if (new_state == UPHILL) {
                uphill_encountered = true;
            }
        }
    }


} // SlopeCounterView

