import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class ArcadeApp extends Application.AppBase {

    private var _timer as Timer.Timer?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {}

    function onStop(state as Dictionary?) as Void {
        // No saveChoice here: cycleWall() already persists on every change,
        // and onStop runs for the glance too, where Storage is off-limits.
        stopTimer();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var v = new ArcadeView();
        // 15 fps. A watchface would be stuck at 1 -- this is the whole
        // reason Pac-Man is a watch-app.
        var t = new Timer.Timer();
        t.start(method(:onTick), 1000 / Shell.FPS, true);
        _timer = t;
        return [v, new ArcadeDelegate()];
    }

    // Registering a glance puts the app in the swipe-up carousel on the watch
    // face, so it launches with a tap instead of being hunted down in the app
    // list. Keep this method free of anything the game owns.
    (:glance)
    function getGlanceView() as
            [WatchUi.GlanceView] or
            [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new ArcadeGlance()];
    }

    function onTick() as Void {
        Shell.update();
        // Trace before requestUpdate: the view consumes lastEat* when it draws.
        if (Shell.TRACE) { Shell.trace(); }
        WatchUi.requestUpdate();
    }

    private function stopTimer() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
    }
}

function getApp() as ArcadeApp {
    return Application.getApp() as ArcadeApp;
}
