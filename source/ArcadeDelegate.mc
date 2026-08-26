import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Nobody plays Pac-Man here, so input is deliberately thin -- and
// deliberately hard to leave by accident, because small children swipe at
// this watch constantly.
//
// The awkward part is that a touchscreen Garmin does not deliver every swipe
// to onSwipe. Some directions are translated into *behaviours* first --
// swipe-right becomes BACK, and vertical swipes can become next/previous
// page -- and those never reach onSwipe at all. That is why a right-swipe
// used to quit. So every one of those behaviours is caught here, consumed,
// and turned into the same recolour-and-slide as a real swipe.
//
// Consuming BACK raises its own risk: if this device were ever to route its
// physical back button *only* through onBack, the app could not be quit. Two
// independent exits guard against that:
//   * onKey(KEY_ESC), which is how a physical press is documented to arrive; and
//   * a deliberate double-BACK inside DOUBLE_MS, which always exits.
// A child swiping repeatedly trips neither: the first BACK is swallowed, and
// a second one only counts if it lands within the window.
class ArcadeDelegate extends WatchUi.BehaviorDelegate {

    const DOUBLE_MS = 1200;

    private var _lastBack as Number = -100000;

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Sideways recolours the maze; up and down change game. startSlide ignores
    // re-entry while a slide is running, so it does not matter if a gesture
    // arrives twice (once as a swipe, once as a behaviour) -- the second call
    // is a no-op.
    private function recolour(dir as Number) as Boolean {
        Shell.startSlide(0, dir, Shell.CHANGE_COLOUR, 0);
        WatchUi.requestUpdate();
        return true;
    }

    private function switchGame(dir as Number) as Boolean {
        Shell.startSlide(1, dir, Shell.CHANGE_GAME, dir);
        WatchUi.requestUpdate();
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (Shell.TRACE) { System.println("IN|onSwipe dir=" + d); }
        // Content travels with the finger: swipe left and the old screen
        // leaves to the left with the new one following it in from the right.
        if (d == WatchUi.SWIPE_LEFT)  { return recolour(1); }
        if (d == WatchUi.SWIPE_RIGHT) { return recolour(-1); }
        if (d == WatchUi.SWIPE_UP)    { return switchGame(1); }
        return switchGame(-1);
    }

    // A physical key press arrives here before it becomes a behaviour, so this
    // is the one exit that a swipe can never reach.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (Shell.TRACE) { System.println("IN|onKey key=" + k); }
        if (k == WatchUi.KEY_ESC) {
            System.exit();   // does not return
        }
        return true;
    }

    // Swipe-right lands here rather than in onSwipe. Treat it as the swipe it
    // actually was; only a deliberate second BACK leaves.
    function onBack() as Boolean {
        var now = System.getTimer();
        if (Shell.TRACE) { System.println("IN|onBack dt=" + (now - _lastBack)); }
        if (now - _lastBack < DOUBLE_MS) {
            System.exit();   // does not return
        }
        _lastBack = now;
        return recolour(-1);
    }

    // Vertical swipes can arrive as page behaviours instead of onSwipe.
    // Vertical swipes can arrive as page behaviours instead of onSwipe.
    function onNextPage() as Boolean { return switchGame(1); }
    function onPreviousPage() as Boolean { return switchGame(-1); }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return skipDwell();
    }

    function onSelect() as Boolean {
        return skipDwell();
    }

    function onMenu() as Boolean { return true; }

    // While the clock panel is already up (READY / GAME OVER) a tap skips the
    // dwell, as before. Otherwise it peeks at the time and the sensors; a
    // second tap puts them away again rather than making you wait it out.
    private function skipDwell() as Boolean {
        if (Shell.showingClock()) {
            Shell.skipDwell();
        } else if (Shell.showingInfo()) {
            Shell.hideInfo();
        } else {
            Shell.showInfo();
        }
        WatchUi.requestUpdate();
        return true;
    }
}
