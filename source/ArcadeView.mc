import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class ArcadeView extends WatchUi.View {

    // Walls + dots are static between bites, so they live in an offscreen
    // buffer and each frame is one blit plus the five sprites. Painting
    // them live would cost 412 draw calls a frame against a ~700-call
    // watchdog -- survivable, but not at 15 fps.
    private var _buf as Graphics.BufferedBitmap? = null;
    // Second buffer, holding the incoming colour during a swipe. If it can't
    // be allocated the recolour still works, it just snaps instead of sliding.
    private var _bufNext as Graphics.BufferedBitmap? = null;
    private var _flashOn as Boolean = false;
    private var _started as Boolean = false;

    // Draw offset, so an entire frame can be shifted for the swipe animation.
    // The colour the outgoing half of a slide was drawn in.
    private var _slideFrom as Number = Theme.WALLS[0];
    private var _ox as Number = 0;
    private var _oy as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        // Loaded here rather than in AppBase.onStart, which also runs for the
        // glance -- and a glance may not touch Application.Storage.
        Theme.loadChoice();
        Layout.compute(dc.getWidth(), dc.getHeight());
        makeBuffer(dc.getWidth(), dc.getHeight());
        if (!_started) {
            _started = true;
            // Whichever game is showing, not Pac-Man specifically -- booting
            // straight into another one otherwise left it never initialised.
            Shell.reset();
        }
    }

    private function makeBuffer(w as Number, h as Number) as Void {
        try {
            var ref = Graphics.createBufferedBitmap({
                :width => w, :height => h,
                :palette => Theme.bufferPalette()
            });
            _buf = (ref != null) ? ref.get() : null;
            var ref2 = Graphics.createBufferedBitmap({
                :width => w, :height => h, :palette => Theme.bufferPalette()
            });
            _bufNext = (ref2 != null) ? ref2.get() : null;
        } catch (e) {
            _buf = null;      // fall back to painting the maze live
            _bufNext = null;
        }
        if (Shell.TRACE) {
            System.println("BUF|" + ((_buf != null) ? "buffered" : "LIVE-FALLBACK")
                + "|free=" + System.getSystemStats().freeMemory
                + "|used=" + System.getSystemStats().usedMemory);
        }
    }

    // ---- the static layer -------------------------------------------------

    private function paintMaze(dc as Dc, wallColor as Number,
                               withDots as Boolean) as Void {
        var C = Layout.cell;
        var ox = Layout.originX;
        var oy = Layout.originY;
        var ins = Layout.inset;
        var x = 0;
        var y = 0;

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();
        dc.setPenWidth(1);
        dc.setColor(wallColor, Graphics.COLOR_TRANSPARENT);

        var seg = MazeWalls.SEG;
        var rad = Layout.corner;
        for (var i = 0; i < MazeWalls.N; i++) {
            var b = i * 6;
            var t = seg[b];
            var a = seg[b + 1];
            var e = seg[b + 2];
            var f = seg[b + 3];
            // Each end carries the sign of the inset to apply: pulled in at a
            // convex corner so it meets the perpendicular run exactly, pushed
            // out at a concave one so it reaches the run coming the other way.
            var lo = a * C + seg[b + 4] * ins;
            var hi = (e + 1) * C + seg[b + 5] * ins;
            // Leave room for the chamfer at whichever ends are convex.
            if (seg[b + 4] > 0) { lo += rad; }
            if (seg[b + 5] < 0) { hi -= rad; }
            if (hi < lo) { continue; }
            if (t == 0) {
                y = oy + f * C + ins;
                dc.drawLine(ox + lo, y, ox + hi, y);
            } else if (t == 1) {
                y = oy + (f + 1) * C - ins;
                dc.drawLine(ox + lo, y, ox + hi, y);
            } else if (t == 2) {
                x = ox + f * C + ins;
                dc.drawLine(x, oy + lo, x, oy + hi);
            } else {
                x = ox + (f + 1) * C - ins;
                dc.drawLine(x, oy + lo, x, oy + hi);
            }
        }

        // Rounded corners, arcade style. At a 1 px stroke there is no room for
        // a real arc -- dc.drawArc left stray disconnected pixels -- so each
        // convex corner is a single diagonal, which rasterises predictably.
        var cor = MazeWalls.CORNER;
        for (var i = 0; i < MazeWalls.CORNER_N; i++) {
            var b = i * 4;
            var sx = cor[b + 2];
            var sy = cor[b + 3];
            x = ox + cor[b] * C + sx * ins;
            y = oy + cor[b + 1] * C + sy * ins;
            dc.drawLine(x + sx * rad, y, x, y + sy * rad);
        }

        dc.setColor(Theme.DOOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var r = 0; r < MazeData.ROWS; r++) {
            var m = MazeData.DOOR[r];
            if (m == 0) { continue; }
            for (var c = 0; c < MazeData.COLS; c++) {
                if ((m & (1 << c)) == 0) { continue; }
                y = Layout.tileY(r);
                dc.drawLine(ox + c * C, y, ox + (c + 1) * C, y);
            }
        }
        dc.setPenWidth(1);

        if (withDots) {
            var d2 = Layout.dotHalf * 2 + 1;
            dc.setColor(Theme.DOT, Graphics.COLOR_TRANSPARENT);
            for (var r = 0; r < MazeData.ROWS; r++) {
                var m = Maze.dots[r];
                if (m == 0) { continue; }
                for (var c = 0; c < MazeData.COLS; c++) {
                    if ((m & (1 << c)) == 0) { continue; }
                    dc.fillRectangle(Layout.tileX(c) - Layout.dotHalf,
                                     Layout.tileY(r) - Layout.dotHalf, d2, d2);
                }
            }
        }
    }

    // Runs, not per-pixel rectangles: the heart is 33 calls instead of ~150.
    private function paintIcon(dc as Dc, runs as Array<Number>, n as Number,
                               x0 as Number, y0 as Number,
                               colour as Number) as Void {
        var s = Layout.iconScale;
        x0 += _ox;
        y0 += _oy;
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            var b = i * 3;
            dc.fillRectangle(x0 + runs[b + 1] * s, y0 + runs[b] * s,
                             (runs[b + 2] - runs[b + 1] + 1) * s, s);
        }
    }

    private function rebuild(wallColor as Number) as Void {
        var b = _buf;
        if (b == null) { return; }
        paintMaze(b.getDc(), wallColor, true);
    }

    // One bite = one small black rectangle punched out of the buffer, rather
    // than 412 calls to repaint everything.
    private function punch(c as Number, r as Number) as Void {
        var b = _buf;
        if (b == null) { return; }
        var s = Layout.dotHalf + 1;
        var bd = b.getDc();
        bd.setColor(Theme.BG, Theme.BG);
        bd.fillRectangle(Layout.tileX(c) - s, Layout.tileY(r) - s,
                         s * 2 + 1, s * 2 + 1);
    }

    // ---- sprites ----------------------------------------------------------

    // Explicit pixels, not fillCircle plus a black wedge. At a 9 px sprite the
    // rasteriser was deciding the shape for us: Garmin renders fillCircle(r=4)
    // as an 8 px diameter, so the body came out 9 wide by 8 tall and the back
    // tapered to a 3 px point -- visibly chopped on the watch.
    private function drawPac(dc as Dc) as Void {
        var p = PacGame.pac;
        var idx;
        if (PacGame.state == PacGame.DYING) {
            var f = (p.deathFrame * SpriteData.DEATH_COUNT) / PacGame.DEATH_FRAMES;
            if (f >= SpriteData.DEATH_COUNT) { return; }   // gone
            idx = SpriteData.DEATH_FIRST + f;
        } else {
            idx = p.dir * SpriteData.PHASES + p.mouthOpen();
        }
        drawSprite(dc, idx, p.pixX() + _ox, p.pixY() + _oy, Theme.PACMAN);
    }

    // One sprite, centred on (cx, cy), as ~8 one-pixel-tall runs.
    private function drawSprite(dc as Dc, idx as Number, cx as Number,
                                cy as Number, colour as Number) as Void {
        var half = SpriteData.S / 2;
        var x0 = cx - half;
        var y0 = cy - half;
        var off = SpriteData.OFF[idx];
        var n = SpriteData.CNT[idx];
        var runs = SpriteData.RUNS;
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            var b = (off + i) * 3;
            dc.fillRectangle(x0 + runs[b + 1], y0 + runs[b],
                             runs[b + 2] - runs[b + 1] + 1, 1);
        }
    }

    private function drawGhost(dc as Dc, g as Ghost) as Void {
        var px = g.pixX() + _ox;
        var py = g.pixY() + _oy;
        if (g.inHouse()) {
            // idle bob inside the house
            var b = g.bob / 8;
            py += (b == 0 || b == 3) ? -1 : 1;
        }
        var r = (Layout.cell * 11) / 20;
        var eyes = g.isEyes();

        if (!eyes) {
            var body = Theme.GHOST[g.who];
            if (g.mode == GhostMode.FRIGHT) {
                body = PacGame.frightFlashing() ? Theme.FRIGHT_END : Theme.FRIGHT;
            }
            dc.setColor(body, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(px, py - 1, r);
            dc.fillRectangle(px - r, py - 1, r * 2 + 1, r + 1);
            // two notches so the skirt reads as a skirt
            dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(px - r + 1, py + r - 1, 2, 2);
            dc.fillRectangle(px + r - 2, py + r - 1, 2, 2);
        }

        if (g.mode == GhostMode.FRIGHT && !eyes) {
            dc.setColor(Theme.EYE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(px - 3, py - 2, 2, 2);
            dc.fillRectangle(px + 2, py - 2, 2, 2);
            return;
        }

        // Deliberately small. At a 9 px cell the sprite is only 9 px wide, so
        // 3x4 eyes swallowed the body and every ghost read as a white blob --
        // the colour is the whole point of having four of them.
        var ex = (g.dir == Maze.RIGHT) ? 1 : 0;
        var ey = (g.dir == Maze.DOWN) ? 1 : ((g.dir == Maze.UP) ? -1 : 0);
        dc.setColor(Theme.EYE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(px - 3, py - 2, 2, 3);
        dc.fillRectangle(px + 1, py - 2, 2, 3);
        dc.setColor(Theme.PUPIL, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(px - 3 + ex, py - 1 + ey, 1, 1);
        dc.fillRectangle(px + 1 + ex, py - 1 + ey, 1, 1);
    }

    private function drawPellets(dc as Dc) as Void {
        if ((Shell.frame / 5) % 2 != 0) { return; }
        dc.setColor(Theme.DOT, Graphics.COLOR_TRANSPARENT);
        for (var r = 0; r < MazeData.ROWS; r++) {
            var m = Maze.power[r];
            if (m == 0) { continue; }
            for (var c = 0; c < MazeData.COLS; c++) {
                if ((m & (1 << c)) != 0) {
                    dc.fillCircle(Layout.tileX(c) + _ox,
                                  Layout.tileY(r) + _oy, Layout.pwrR);
                }
            }
        }
    }

    // ---- chrome -----------------------------------------------------------

    // Only drawn during a peek, so these 31 fill calls are not a per-frame
    // cost. They used to live in the maze buffer, which was free -- but the
    // buffer is the wrong home for something that is usually hidden.
    private function drawSensors(dc as Dc) as Void {
        paintIcon(dc, IconData.HEART, IconData.HEART_N,
                  Layout.iconLX, Layout.iconHeartY, Theme.HEART);
        paintIcon(dc, IconData.BODY, IconData.BODY_N,
                  Layout.iconRX, Layout.iconBodyY, Theme.BODY);

        var f = WatchUi.loadResource(Rez.Fonts.FontTiny) as FontResource;
        var th = dc.getFontHeight(f);
        var half = (IconData.W * Layout.iconScale) / 2;
        // Knocked out of the filled icon rather than drawn on top of it: at
        // this size a solid shape with a hole punched in it reads far better
        // than white digits inside a hairline outline.
        dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.iconLX + half + _ox,
                    Layout.iconTextY(Layout.iconHeartY, IconData.HEART_TEXT_TOP,
                                     IconData.HEART_TEXT_BOT, th) + _oy,
                    f, Sensors.hr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(Layout.iconRX + half + _ox,
                    Layout.iconTextY(Layout.iconBodyY, IconData.BODY_TEXT_TOP,
                                     IconData.BODY_TEXT_BOT, th) + _oy,
                    f, Sensors.bb, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawScoreTime(dc as Dc) as Void {
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2 + _ox, Layout.scoreY + _oy,
                    WatchUi.loadResource(Rez.Fonts.FontScore) as FontResource,
                    Clock.timeStr(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawStatus(dc as Dc) as Void {
        var w = dc.getWidth() + _ox * 2;
        var y = Layout.livesY + _oy;
        var r = (Layout.cell * 11) / 20;

        dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
        var n = Shell.lives() - 1;
        if (n > 3) { n = 3; }
        for (var i = 0; i < n; i++) {
            dc.fillCircle(w / 2 - 34 + i * (r * 2 + 4), y + r, r);
        }

        // level, shown the arcade way: one fruit per level, capped
        var lv = Shell.level();
        if (lv > 4) { lv = 4; }
        for (var i = 0; i < lv; i++) {
            var fx = w / 2 + 16 + i * (r * 2 + 3);
            dc.setColor(Theme.FRUIT, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(fx, y + r + 1, r - 1);
            dc.setColor(0x00A000, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(fx - 1, y + r - 4, 2, 3);
        }
    }

    // The bit that makes it a watch: where the arcade says READY!, we put
    // the time and date instead.
    private function drawClockPanel(dc as Dc) as Void {
        var big = WatchUi.loadResource(Rez.Fonts.FontBig) as FontResource;
        var small = WatchUi.loadResource(Rez.Fonts.FontSmall) as FontResource;
        var t = Clock.timeStr();
        var d = Clock.dateStr();
        var over = (PacGame.state == PacGame.GAME_OVER);

        var th = dc.getFontHeight(big);
        var sh = dc.getFontHeight(small);
        var tw = dc.getTextWidthInPixels(t, big);
        var dw = dc.getTextWidthInPixels(d, small);
        var bw = (tw > dw ? tw : dw) + 26;
        var bh = th + sh + 16 + (over ? sh + 6 : 0);

        var cx = dc.getWidth() / 2 + _ox;
        var cy = Layout.tileY(14) + _oy;
        var top = cy - bh / 2;

        // Framed in maze blue. Without the border the black panel just
        // truncates whatever wall runs behind it, which reads as a clipping
        // bug rather than as a deliberate overlay.
        dc.setColor(Theme.BG, Theme.BG);
        dc.fillRectangle(cx - bw / 2, top - 6, bw, bh + 12);
        dc.setColor(Theme.wall(), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(cx - bw / 2, top - 6, bw, bh + 12);

        if (over) {
            dc.setColor(Theme.FRUIT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, top, small, "GAME OVER", Graphics.TEXT_JUSTIFY_CENTER);
            top += sh + 6;
        }
        dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top, big, t, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top + th + 10, small, d, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- frame ------------------------------------------------------------

    // One complete frame, drawn at an arbitrary offset. The swipe animation
    // simply calls this twice: the outgoing screen on its way out and the
    // incoming one right behind it.
    // Pac-Man's maze is cached in a buffer; the other games are cheap enough
    // to draw outright, and are handed the offset so they slide with everything
    // else.
    private function drawPlayfield(dc as Dc, flashing as Boolean,
                                   colour as Number) as Void {
        if (Shell.game == Shell.PACMAN) {
            if (flashing) { return; }
            drawPellets(dc);
            if (PacGame.state != PacGame.DYING) {
                for (var i = 0; i < 4; i++) { drawGhost(dc, PacGame.ghosts[i]); }
            }
            if (PacGame.state != PacGame.GAME_OVER) { drawPac(dc); }
        } else if (Shell.game == Shell.INVADERS) {
            Invaders.draw(dc, _ox, _oy, colour);
        } else if (Shell.game == Shell.BRICKS) {
            Bricks.draw(dc, _ox, _oy, colour);
        } else {
            Rocks.draw(dc, _ox, _oy, colour);
        }
    }

    private function drawScene(dc as Dc, buf as Graphics.BufferedBitmap?,
                               ox as Number, oy as Number,
                               flashing as Boolean, colour as Number) as Void {
        _ox = ox;
        _oy = oy;
        if (Shell.game == Shell.PACMAN) {
            if (buf != null) {
                dc.drawBitmap(ox, oy, buf);
            } else {
                paintMaze(dc, _flashOn ? Theme.WALL_FLASH : colour, true);
            }
        }
        drawPlayfield(dc, flashing, colour);
        drawScoreTime(dc);
        drawStatus(dc);
        var peek = Shell.showingInfo();
        if (peek) { drawSensors(dc); }
        if (Shell.showingClock() || peek) { drawClockPanel(dc); }
        _ox = 0;
        _oy = 0;
    }

    function onUpdate(dc as Dc) as Void {
        var flashing = (Shell.game == Shell.PACMAN
                        && PacGame.state == PacGame.LEVEL_DONE);
        var w = dc.getWidth();
        var h = dc.getHeight();

        // A swipe has just landed. Remember the colour the outgoing half must
        // be drawn in; the change itself is applied mid-animation, below.
        if (Shell.slideArmed) {
            Shell.slideArmed = false;
            _slideFrom = Theme.wall();
            if (_bufNext == null && Shell.game == Shell.PACMAN) {
                Shell.slideStep = 0;          // no spare buffer: snap instead
                Shell.applyPending();
                PacGame.mazeDirty = true;
            }
        }

        var sliding = (Shell.slideStep > 0);

        if (!sliding && Shell.game == Shell.PACMAN) {
            if (flashing) {
                var on = ((PacGame.timer / 4) % 2) == 0;
                if (on != _flashOn || PacGame.mazeDirty) {
                    _flashOn = on;
                    PacGame.mazeDirty = false;
                    rebuild(on ? Theme.WALL_FLASH : Theme.wall());
                }
            } else if (PacGame.mazeDirty) {
                PacGame.mazeDirty = false;
                _flashOn = false;
                rebuild(Theme.wall());
            } else if (PacGame.lastEatC >= 0) {
                punch(PacGame.lastEatC, PacGame.lastEatR);
                PacGame.lastEatC = -1;
            }
        }

        dc.setColor(Theme.BG, Theme.BG);
        dc.clear();

        if (sliding) {
            var e = Shell.slideProgress();
            var d = Shell.slideDir;
            var span = (Shell.slideAxis == 0) ? w : h;
            var shift = -d * (e * span) / 100;
            var ox = (Shell.slideAxis == 0) ? shift : 0;
            var oy = (Shell.slideAxis == 0) ? 0 : shift;
            var nx = (Shell.slideAxis == 0) ? ox + d * w : 0;
            var ny = (Shell.slideAxis == 0) ? 0 : oy + d * h;

            drawScene(dc, _buf, ox, oy, flashing, _slideFrom);

            // The change lands *between* the two halves, so the outgoing
            // screen is the old state and the incoming one is the new.
            if (Shell.pendingChange >= 0) {
                Shell.applyPending();
                if (Shell.game == Shell.PACMAN && _bufNext != null) {
                    paintMaze((_bufNext as Graphics.BufferedBitmap).getDc(),
                              Theme.wall(), true);
                }
            }
            drawScene(dc, _bufNext, nx, ny, false, Theme.wall());

            if (Shell.slideStep <= 1) {
                var t = _buf;
                _buf = _bufNext;
                _bufNext = t;
                if (Shell.game == Shell.PACMAN) { PacGame.mazeDirty = false; }
            }
            return;
        }

        drawScene(dc, _buf, 0, 0, flashing, Theme.wall());
    }
}
