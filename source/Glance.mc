import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The glance card: swipe up or down from the watch face and this appears in
// the carousel; tapping it launches the full app. Much quicker than hunting
// through the app list.
//
// Deliberately self-contained -- no Theme, no Layout, no game state, and no
// font resources. The glance is compiled into its own scope with a 64 KB
// budget (against the watch-app's 768 KB), so it draws with primitives and
// a built-in font and pulls in nothing else -- not even a string resource.
(:glance)
class ArcadeGlance extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        // Label on the left, the chase scene filling whatever is left.
        dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
        // Literal, not Rez.Strings.AppName: a glance cannot reach Rez at all
        // ("Could not access symbol 'Rez'"), and the whole point of this view
        // is to depend on nothing.
        var label = "ARCADE";
        dc.drawText(2, h / 2, Graphics.FONT_TINY, label,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var textW = dc.getTextWidthInPixels(label, Graphics.FONT_TINY);
        var x = 2 + textW + 12;
        var cy = h / 2;
        var r = h / 5;
        if (r < 4) { r = 4; }
        if (x + r * 12 > w) { return; }        // no room: label only

        // a little row of pellets for him to be chasing
        dc.setColor(0xFFB8AE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 4; i++) {
            dc.fillRectangle(x + r * 3 + i * r * 2, cy - 1, 2, 2);
        }

        // Pac-Man, mouth open, facing the pellets
        dc.setColor(0xFFFF00, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r, cy, r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x + r, cy],
                        [x + r * 2 + 2, cy - r],
                        [x + r * 2 + 2, cy + r]]);

        // and one ghost on his tail
        var gx = x + r * 3 + 4 * r * 2 + r;
        if (gx + r <= w) {
            dc.setColor(0xFF0000, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx, cy - 1, r);
            dc.fillRectangle(gx - r, cy - 1, r * 2 + 1, r + 1);
        }
    }
}
