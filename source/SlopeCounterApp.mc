using Toybox.Application;
using Toybox.System;

class SlopeCounterApp extends Application.AppBase {

    // the counter view
    protected var view = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    protected function getView() {
        if (view == null) {
            view = new SlopeCounterView();
        }
        return view;
    }

    // when settings are changes from connectIQ
    // This crashes the simulator. TODO debug later
    //function onSettingsChanged() {
    //    System.println("SlopeCounterApp::onSettingsChanged");
    //    var ui = getView();
    //    ui.onSettingsChanged();
    //}

    // Return the initial view of your application here
    function getInitialView() {
        return [ getView() ];
    }

}
