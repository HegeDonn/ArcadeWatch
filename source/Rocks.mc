import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Asteroids, playing itself.
//
// Two things differ from the cabinet, both because the screen is a circle.
// Wrapping is radial: anything that leaves the bezel re-enters diametrically
// opposite, which on a round face reads better than the rectangular wrap and
// costs nothing. And rotation is done by hand -- the vivoactive 5 has no
// vector rotation and no drawAngledText -- so every rock is a polygon whose
// points are rotated per frame from a fixed silhouette.
//
// Angles are in 1/64 turn (0..63) so the sine table is a small integer array
// and the hot loop never touches floating point.
module Rocks {

    const TURN = 64;
    const FINE = 256;             // rock spin, in 1/256 turn
    const SUB = 16;                       // 1/16 px positions

    const READY = 0; const PLAY = 1; const DYING = 2; const OVER = 3;
    const READY_FRAMES = 4 * Shell.FPS;
    const DIE_FRAMES   = 24;
    const OVER_FRAMES  = 5 * Shell.FPS;

    // sin(i / 64 turn) * 256, first quarter; the rest is mirrored.
    const SIN16 = [0, 25, 49, 74, 97, 120, 142, 162, 181, 198, 213, 226,
                   237, 245, 251, 255, 256] as Array<Number>;

    const MAXROCK = 9;
    const MAXSHOT = 4;

    var state as Number = 0;
    var timer as Number = 0;
    var lives as Number = 3;
    var level as Number = 1;

    var rx = new [MAXROCK];               // 1/16 px
    var ry = new [MAXROCK];
    var rvx = new [MAXROCK];
    var rvy = new [MAXROCK];
    var rsize = new [MAXROCK];            // 0 gone, 3 big, 2 mid, 1 small
    var rang = new [MAXROCK];
    var rspin = new [MAXROCK];
    var rockCount as Number = 0;

    var sx = new [MAXSHOT];
    var sy = new [MAXSHOT];
    var svx = new [MAXSHOT];
    var svy = new [MAXSHOT];
    var slife = new [MAXSHOT];

    var shipX as Number = 0;
    var shipY as Number = 0;
    var shipVX as Number = 0;
    var shipVY as Number = 0;
    var shipAng as Number = 0;
    var fireLock as Number = 0;

    var cx as Number = 195;
    var cy as Number = 195;
    var rad as Number = 180;
    var laidOut as Boolean = false;

    function layout() as Void {
        cx = Layout.screenW / 2;
        cy = Layout.screenH / 2;
        var m = (Layout.screenW < Layout.screenH) ? Layout.screenW : Layout.screenH;
        rad = m / 2 - 10;
        laidOut = true;
    }

    // sin/cos on 1/64 turn, scaled by 256.
    function sin(a as Number) as Number {
        a = ((a % TURN) + TURN) % TURN;
        if (a <= 16) { return SIN16[a]; }
        if (a <= 32) { return SIN16[32 - a]; }
        if (a <= 48) { return -SIN16[a - 32]; }
        return -SIN16[64 - a];
    }
    function cos(a as Number) as Number { return sin(a + 16); }

    function reset() as Void {
        if (!laidOut) { layout(); }
        level = 1;
        lives = 3;
        newWave();
    }

    function newWave() as Void {
        for (var i = 0; i < MAXROCK; i++) { rsize[i] = 0; }
        rockCount = 0;
        var n = 3 + level;
        if (n > 5) { n = 5; }
        for (var i = 0; i < n; i++) { spawnRock(3); }
        respawn();
        state = READY;
        timer = READY_FRAMES;
    }

    function respawn() as Void {
        shipX = cx * SUB;
        shipY = cy * SUB;
        shipVX = 0;
        shipVY = 0;
        shipAng = 0;
        for (var i = 0; i < MAXSHOT; i++) { slife[i] = 0; }
    }

    function spawnRock(size as Number) as Void {
        for (var i = 0; i < MAXROCK; i++) {
            if (rsize[i] != 0) { continue; }
            // Out at the rim, so nothing lands on top of the ship.
            var a = Math.rand() % TURN;
            rx[i] = (cx + (cos(a) * (rad - 12)) / 256) * SUB;
            ry[i] = (cy + (sin(a) * (rad - 12)) / 256) * SUB;
            var v = Math.rand() % TURN;
            var sp = 18 + (Math.rand() % 14) + level * 2;
            rvx[i] = (cos(v) * sp) / 256;
            rvy[i] = (sin(v) * sp) / 256;
            if (rvx[i] == 0 && rvy[i] == 0) { rvx[i] = 4; }
            rsize[i] = size;
            rang[i] = Math.rand() % FINE;
            rspin[i] = (Math.rand() % 5) - 2;
            rockCount++;
            return;
        }
    }

    function radiusOf(size as Number) as Number {
        if (size == 3) { return 22; }
        if (size == 2) { return 13; }
        return 7;
    }

    function showingClock() as Boolean { return state == READY || state == OVER; }
    function skipDwell() as Void { if (showingClock() && timer > 4) { timer = 4; } }

    // Radial wrap: leave the bezel one side, arrive opposite.
    //
    // It has to re-enter *on* the rim, not at the mirrored point. Mirroring
    // through the centre keeps the same distance, so anything outside stayed
    // outside and teleported again next frame -- which is what made rocks
    // flicker between two places.
    function wrap(px as Number, py as Number) as Array<Number> {
        var dx = px / SUB - cx;
        var dy = py / SUB - cy;
        var d2 = dx * dx + dy * dy;
        if (d2 <= rad * rad) { return [px, py] as Array<Number>; }
        var d = isqrt(d2);
        if (d == 0) { return [px, py] as Array<Number>; }
        var edge = rad - 2;
        return [(cx - (dx * edge) / d) * SUB,
                (cy - (dy * edge) / d) * SUB] as Array<Number>;
    }

    function isqrt(v as Number) as Number {
        if (v <= 0) { return 0; }
        return Math.sqrt(v.toFloat()).toNumber();
    }

    function update() as Void {
        if (!laidOut) { layout(); }
        if (state == READY || state == OVER) {
            timer--;
            if (timer <= 0) {
                if (state == OVER) { reset(); } else { state = PLAY; }
            }
            return;
        }
        if (state == DYING) {
            timer--;
            if (timer <= 0) {
                lives--;
                if (lives <= 0) { state = OVER; timer = OVER_FRAMES; }
                else { respawn(); state = READY; timer = READY_FRAMES; }
            }
            return;
        }

        moveRocks();
        flyShip();
        moveShots();

        if (rockCount <= 0) {
            level++;
            newWave();
        }
    }

    function moveRocks() as Void {
        for (var i = 0; i < MAXROCK; i++) {
            if (rsize[i] == 0) { continue; }
            rx[i] += rvx[i];
            ry[i] += rvy[i];
            var w = wrap(rx[i], ry[i]);
            rx[i] = w[0];
            ry[i] = w[1];
            rang[i] = (rang[i] + rspin[i] + FINE) % FINE;
        }
    }

    // Turn toward the nearest rock, thrust away if one is nearly on top,
    // and fire when roughly lined up.
    function flyShip() as Void {
        var px = shipX / SUB;
        var py = shipY / SUB;
        var best = -1;
        var bestD = 999999;
        for (var i = 0; i < MAXROCK; i++) {
            if (rsize[i] == 0) { continue; }
            var dx = rx[i] / SUB - px;
            var dy = ry[i] / SUB - py;
            var d = dx * dx + dy * dy;
            if (d < bestD) { bestD = d; best = i; }
            var hit = radiusOf(rsize[i]) + 6;
            if (d < hit * hit) {
                state = DYING;
                timer = DIE_FRAMES;
                return;
            }
        }

        if (best >= 0) {
            var want = angleTo(rx[best] / SUB - px, ry[best] / SUB - py);
            var diff = ((want - shipAng + TURN + TURN / 2) % TURN) - TURN / 2;
            if (diff > 1) { shipAng = (shipAng + 2) % TURN; }
            else if (diff < -1) { shipAng = (shipAng - 2 + TURN) % TURN; }

            if (diff.abs() <= 2 && fireLock <= 0) { fire(); }
            // Back off when something big is close.
            if (bestD < 70 * 70) {
                shipVX -= (cos(shipAng) * 3) / 256;
                shipVY -= (sin(shipAng) * 3) / 256;
            } else if (bestD > 130 * 130) {
                shipVX += (cos(shipAng) * 2) / 256;
                shipVY += (sin(shipAng) * 2) / 256;
            }
        }
        if (fireLock > 0) { fireLock--; }

        // drag, so it never runs away with itself
        shipVX = (shipVX * 15) / 16;
        shipVY = (shipVY * 15) / 16;
        var lim = 40;
        if (shipVX > lim) { shipVX = lim; }
        if (shipVX < -lim) { shipVX = -lim; }
        if (shipVY > lim) { shipVY = lim; }
        if (shipVY < -lim) { shipVY = -lim; }

        shipX += shipVX;
        shipY += shipVY;
        var w = wrap(shipX, shipY);
        shipX = w[0];
        shipY = w[1];
    }

    // Coarse atan2 on the 64-step circle: good enough to aim a gun.
    function angleTo(dx as Number, dy as Number) as Number {
        var best = 0;
        var bestDot = -999999;
        for (var a = 0; a < TURN; a += 1) {
            var d = cos(a) * dx + sin(a) * dy;
            if (d > bestDot) { bestDot = d; best = a; }
        }
        return best;
    }

    function fire() as Void {
        for (var i = 0; i < MAXSHOT; i++) {
            if (slife[i] > 0) { continue; }
            sx[i] = shipX;
            sy[i] = shipY;
            svx[i] = (cos(shipAng) * 130) / 256;   // ~8 px/frame
            svy[i] = (sin(shipAng) * 130) / 256;
            slife[i] = 26;
            fireLock = 5;
            return;
        }
    }

    function moveShots() as Void {
        for (var i = 0; i < MAXSHOT; i++) {
            if (slife[i] <= 0) { continue; }
            slife[i]--;
            sx[i] += svx[i];
            sy[i] += svy[i];
            var w = wrap(sx[i], sy[i]);
            sx[i] = w[0];
            sy[i] = w[1];
            var px = sx[i] / SUB;
            var py = sy[i] / SUB;
            for (var k = 0; k < MAXROCK; k++) {
                if (rsize[k] == 0) { continue; }
                var dx = rx[k] / SUB - px;
                var dy = ry[k] / SUB - py;
                var rr = radiusOf(rsize[k]);
                if (dx * dx + dy * dy > rr * rr) { continue; }
                slife[i] = 0;
                split(k);
                break;
            }
        }
    }

    function split(k as Number) as Void {
        var size = rsize[k];
        rsize[k] = 0;
        rockCount--;
        if (size <= 1) { return; }
        for (var n = 0; n < 2; n++) {
            for (var i = 0; i < MAXROCK; i++) {
                if (rsize[i] != 0) { continue; }
                rx[i] = rx[k];
                ry[i] = ry[k];
                var a = Math.rand() % TURN;
                var sp = 24 + (Math.rand() % 16) + level * 2;
                rvx[i] = (cos(a) * sp) / 256;
                rvy[i] = (sin(a) * sp) / 256;
                rsize[i] = size - 1;
                rang[i] = Math.rand() % FINE;
                rspin[i] = (Math.rand() % 5) - 2;
                rockCount++;
                break;
            }
        }
    }

    // A rock silhouette: eight radii, lumpy but closed.
    const LUMP = [10, 8, 10, 7, 10, 8, 9, 7] as Array<Number>;

    function draw(dc as Dc, ox as Number, oy as Number, colour as Number) as Void {
        if (!laidOut) { layout(); }

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var i = 0; i < MAXROCK; i++) {
            if (rsize[i] == 0) { continue; }
            var px = ox + rx[i] / SUB;
            var py = oy + ry[i] / SUB;
            var rr = radiusOf(rsize[i]);
            var prevX = 0;
            var prevY = 0;
            for (var k = 0; k <= 8; k++) {
                var idx = k % 8;
                var a = (rang[i] / 4 + idx * 8) % TURN;
                var len = (rr * LUMP[idx]) / 10;
                var qx = px + (cos(a) * len) / 256;
                var qy = py + (sin(a) * len) / 256;
                if (k > 0) { dc.drawLine(prevX, prevY, qx, qy); }
                prevX = qx;
                prevY = qy;
            }
        }

        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < MAXSHOT; i++) {
            if (slife[i] > 0) {
                dc.fillRectangle(ox + sx[i] / SUB, oy + sy[i] / SUB, 2, 2);
            }
        }

        if (state == DYING) { return; }
        var hx = ox + shipX / SUB;
        var hy = oy + shipY / SUB;
        dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
        var nose = 10;
        var tail = 7;
        var ax = hx + (cos(shipAng) * nose) / 256;
        var ay = hy + (sin(shipAng) * nose) / 256;
        var b = (shipAng + 26) % TURN;
        var c = (shipAng + TURN - 26) % TURN;
        dc.fillPolygon([
            [ax, ay],
            [hx + (cos(b) * tail) / 256, hy + (sin(b) * tail) / 256],
            [hx + (cos(c) * tail) / 256, hy + (sin(c) * tail) / 256]
        ]);
    }
}
