using Toybox.FitContributor;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class SlopeCounterView extends WatchUi.SimpleDataField {

    // enums for states
    enum {
        DOWNHILL = 0,
        UPHILL,
        STATE_COUNT
    }

    // shown in UI for given state
    var state_marker = ["v ", "^ "];

    // enums for moving direction (observations for the model)
    enum {
        DOWN = 0,
        FLAT,
        UP,
        OBSERVATION_COUNT
    }

    protected var is_running = false;

    // warmup period to fill the filter
    protected var warmup = null;
    protected var warmup_iterations = null;

    // filter length
    protected var filter_length = 3;
    // this must be odd size or the median is calculated wrong
    protected var filter_array = [0.0, 0.0, 0.0];
    // filter array is used as a circular buffer
    protected var filter_array_idx = -1;

    // vertical speed calculation needs the previous altitude
    protected var previous_altitude = 0;

    // moving vertical speed limit (m/s)
    protected var vertical_speed_limit = 0.5;

    // last slope end time to filter slopes starting too close to each other
    protected var previous_slope_end_time = null;

    // minimum time from last slopes end to start a new run
    protected var minimum_time_from_last_slope_end = new Time.Duration(30);

    // Hidden markov model (see states and observations) -->
    protected var start_probability = [0.0, 1.0];

    // transition probabilities
    protected var a = 0.0001;
    protected var transition_probability = [[1-a, a], [a, 1-a]];

    // emission probabilities for each observation given a state
    protected var emission_probability = [[0.5, 0.3, 0.2], [0.2, 0.3, 0.5]];

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

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();
        init_model();
        init_fit_contributor();
        label = "Runs";
    }

    /*
    Init HMM
    */
    function init_model() {
        alpha = [0, 0];
        previous_alpha = start_probability.slice(null, null);
        previous_slope_end_time = new Time.Moment(0);
        current_state = UPHILL;
    }

    /*
    Write slope data to the fit file
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
        warmup = true;
        warmup_iterations = filter_length-1;
        is_running = true;
    }

    function onTimerPause() {
        is_running = false;
    }

    function onTimerResume() {
        warmup = true;
        warmup_iterations = filter_length-1;
        is_running = true;
    }

    function onTimerStop() {
        is_running = false;
        slope_count_field.setData(number_of_slopes);
    }

    function onTimerReset() {
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

        // calculate filtered speed and discretize it to DOWN, FLAT, UP)
        var vertical_speed = get_filtered_vertical_speed(info.altitude);
        var moving_direction = discretize_vertical_speed(vertical_speed);

        // updates current state and hmm fields
        forward_algorithm(moving_direction);

        System.println(vertical_speed);
        System.println(moving_direction);

        // update fit data
        slope_transition_graph_field.setData(number_of_slopes);

        // return the value to show
        //return Lang.format("$1$$2$", [state_marker[current_state], number_of_slopes]);

        if (current_state == DOWNHILL) {
            return number_of_slopes;
        } else {
            return -number_of_slopes;
        }
    }

    /*
    Calculates the most probable state of the hidden markov model using a forward algorithm
    observation : discretized observation (DOWN, FLAT, UP) to prevent spike effects
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

        // do not completely trust the HMM but also check that enough time has passed since last transition to downhill
        // for the number of runs calculation
        if (most_probable_state != current_state) {
            var now = Time.now();
            var hysteresis = previous_slope_end_time.add(minimum_time_from_last_slope_end);

            if (most_probable_state == DOWNHILL && now.greaterThan(hysteresis)) {
                // current state is upphill and we are moving downhill (enough time has passed from the last change)
                number_of_slopes += 1;
                slope_count_field.setData(number_of_slopes);

            } else if (current_state == DOWNHILL) {
                // current state is downhill and we are moving to some other state
                previous_slope_end_time = now;
            }

        }

        // always set current state to most probable state
        current_state = most_probable_state;
    }

    /*
    Wait untill we have n vertical speed estimates to fill the filter
    */
    protected function warmup_phase(altitude) {
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

        // use the median of the altitude for speed estimate, reverse the arrays when going downhill for speedup in sorting
        altitude = median(filter_array, current_state == DOWNHILL);
        System.println(filter_array);
        System.println(altitude);

        // calculate the difference to the previous altitude
        var altitude_delta = altitude - previous_altitude;

        // update previous altitude
        previous_altitude = altitude;

        // value is in m/s
        return altitude_delta;
    }

    /**
    Discretize the moving direction to DOWN, FLAT and UP based on the speed limit
    */
    protected function discretize_vertical_speed(vertical_speed) {
        if (vertical_speed < -vertical_speed_limit) {
            return DOWN;
        } else if (vertical_speed > vertical_speed_limit) {
            return UP;
        } else {
            return FLAT;
        }
    }

}

