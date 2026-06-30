import Toybox.Application;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

class WatchFaceApp extends Application.AppBase {
    private var _view    as WatchFaceView? = null;
    private var _sleepId as Complications.Id? = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new WatchFaceView();
        return [_view];
    }

    function onStart(state as Dictionary?) as Void {
        if ((Toybox has :Complications) && (Complications has :COMPLICATION_TYPE_SLEEP_SCORE)) {
            _sleepId = new Complications.Id(Complications.COMPLICATION_TYPE_SLEEP_SCORE);
            Complications.registerComplicationChangeCallback(self.method(:onComplicationChanged));
            try { Complications.subscribeToUpdates(_sleepId); } catch (e) {}
        }
    }

    function onStop(state as Dictionary?) as Void {
        if (_sleepId != null) { Complications.unsubscribeFromAllUpdates(); }
    }

    function onComplicationChanged(id as Complications.Id) as Void {
        if (_sleepId != null && id.equals(_sleepId) && _view != null) {
            try {
                var c = Complications.getComplication(id);
                if (c.value instanceof Number) { (_view as WatchFaceView).setSleepScore(c.value as Number); }
            } catch (e instanceof Complications.ComplicationNotFoundException) {}
        }
    }
}
