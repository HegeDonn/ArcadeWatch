import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Tempest, playing itself.
//
// The only game here whose playfield is genuinely a circle. You ride the rim
// of a tube and things climb out of the middle towards you, so for once the
// bezel *is* the edge of the play area and nothing has to be cropped or
// fitted to fit -- every other game on this watch wastes the corners it does
// not have.
//
// A level is its rim, taken from TempestData: a circle, a square, a plus, a
// pinwheel, or an open trough with walls at each end. The far end of the tube
// is the same outline shrunk toward the centre, so one table of points
// decides the whole shape -- and segment counts differ per level, because
// corners are kept rather than resampled away.
//
// Depth runs 0 at the far end to DEEP at the rim.
module Tempest {

    const DEEP = 256;                     // depth at the rim
    const NEAR_PCT = 100;                 // rim, as a percentage of full size
    const FAR_PCT = 24;                   // far end of the tube

    const READY = 0; const PLAY = 1; const DYING = 2; const OVER = 3;
    const READY_FRAMES = 4 * Shell.FPS;
    const DIE_FRAMES   = 24;
    const OVER_FRAMES  = 5 * Shell.FPS;

    const MAXE = 8;
    const MAXB = 4;

    var state as Number = 0;
    var timer as Number = 0;
    var lives as Number = 3;
    var level as Number = 1;

    var eSeg = new [MAXE];
    var eDepth = new [MAXE];
    var eLive = new [MAXE];
    var eFlip = new [MAXE];               // frames until it flips a segment
    var enemies as Number = 0;
    var spawnLeft as Number = 0;
    var spawnTimer as Number = 0;

    var bSeg = new [MAXB];
    var bDepth = new [MAXB];
    var bLive = new [MAXB];

    var playerSeg as Number = 0;
    var fireLock as Number = 0;

    var cx as Number = 195;
    var cy as Number = 195;
    var scale as Number = 170;
    var shape as Number = 0;
    var laidOut as Boolean = false;

    function layout() as Void {
        cx = Layout.screenW / 2;
        cy = Layout.screenH / 2;
        var m = (Layout.screenW < Layout.screenH) ? Layout.screenW : Layout.screenH;
        scale = m / 2 - 22;
        laidOut = true;
    }

    function segCount() as Number { return TempestData.NSEG[shape]; }
    function isClosed() as Boolean { return TempestData.CLOSED[shape] == 1; }

    // Rim vertex i, projected to depth d. Points are normalised to 1000, so
    // this is (normalised * pixels * percent) / (1000 * 100).
    function pctAt(d as Number) as Number {
        return FAR_PCT + ((NEAR_PCT - FAR_PCT) * d) / DEEP;
    }
    function vx(i as Number, d as Number) as Number {
        var p = TempestData.OFF[shape] + i;
        return cx + (TempestData.PX[p] * scale * pctAt(d)) / 100000;
    }
    function vy(i as Number, d as Number) as Number {
        var p = TempestData.OFF[shape] + i;
        return cy + (TempestData.PY[p] * scale * pctAt(d)) / 100000;
    }
    // The far vertex of a segment wraps only on a closed rim.
    function nextV(i as Number) as Number {
        var n = segCount();
        return isClosed() ? (i + 1) % n : i + 1;
    }
    // Centre of a segment, for things that sit in the middle of one.
    function midX(s as Number, d as Number) as Number {
        return (vx(s, d) + vx(nextV(s), d)) / 2;
    }
    function midY(s as Number, d as Number) as Number {
        return (vy(s, d) + vy(nextV(s), d)) / 2;
    }

    function reset() as Void {
        if (!laidOut) { layout(); }
        level = 1;
        lives = 3;
        newWave();
    }

    function newWave() as Void {
        shape = (level - 1) % TempestData.LEVELS;
        for (var i = 0; i < MAXE; i++) { eLive[i] = 0; }
        enemies = 0;
        spawnLeft = 6 + level * 2;
        if (spawnLeft > 16) { spawnLeft = 16; }
        spawnTimer = 0;
        respawn();
        state = READY;
        timer = READY_FRAMES;
    }

    function respawn() as Void {
        playerSeg = segCount() / 2;
        fireLock = 0;
        for (var i = 0; i < MAXB; i++) { bLive[i] = 0; }
    }

    function showingClock() as Boolean { return state == READY || state == OVER; }
    function skipDwell() as Void { if (showingClock() && timer > 4) { timer = 4; } }

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

        spawn();
        climb();
        steer();
        moveShots();

        if (enemies <= 0 && spawnLeft <= 0) {
            level++;
            newWave();
        }
    }

    function spawn() as Void {
        if (spawnLeft <= 0) { return; }
        spawnTimer--;
        if (spawnTimer > 0) { return; }
        spawnTimer = 20 - level;
        if (spawnTimer < 6) { spawnTimer = 6; }
        for (var i = 0; i < MAXE; i++) {
            if (eLive[i] == 1) { continue; }
            eSeg[i] = Math.rand() % segCount();
            eDepth[i] = 0;
            eLive[i] = 1;
            eFlip[i] = 10 + (Math.rand() % 30);
            enemies++;
            spawnLeft--;
            return;
        }
    }

    function climb() as Void {
        var speed = 2 + level / 2;
        for (var i = 0; i < MAXE; i++) {
            if (eLive[i] == 0) { continue; }
            eDepth[i] += speed;

            // Flippers work their way around the web as they come up.
            eFlip[i]--;
            if (eFlip[i] <= 0) {
                eFlip[i] = 14 + (Math.rand() % 26);
                eSeg[i] = step(eSeg[i], (Math.rand() % 2 == 0) ? 1 : -1);
            }

            if (eDepth[i] >= DEEP) {
                eLive[i] = 0;
                enemies--;
                if (eSeg[i] == playerSeg) {      // it got to you
                    state = DYING;
                    timer = DIE_FRAMES;
                    return;
                }
            }
        }
    }

    // One segment along the rim. A closed rim wraps; an open one has ends and
    // simply stops, which is the whole point of the open levels.
    function step(s as Number, dir as Number) as Number {
        var n = segCount();
        if (isClosed()) { return (s + dir + n) % n; }
        var v = s + dir;
        if (v < 0) { return 0; }
        if (v >= n) { return n - 1; }
        return v;
    }

    // Track whichever enemy is nearest the rim, going the short way round.
    function steer() as Void {
        var best = -1;
        var bestDepth = -1;
        for (var i = 0; i < MAXE; i++) {
            if (eLive[i] == 1 && eDepth[i] > bestDepth) {
                bestDepth = eDepth[i];
                best = i;
            }
        }
        if (fireLock > 0) { fireLock--; }
        if (best < 0) { return; }

        var target = eSeg[best];
        if (target != playerSeg) {
            var n = segCount();
            var dir = (target > playerSeg) ? 1 : -1;
            if (isClosed()) {
                var fwd = (target - playerSeg + n) % n;
                dir = (fwd <= n / 2) ? 1 : -1;
            }
            playerSeg = step(playerSeg, dir);
        }
        if (fireLock <= 0) { fire(); }
    }

    function fire() as Void {
        for (var i = 0; i < MAXB; i++) {
            if (bLive[i] == 1) { continue; }
            bSeg[i] = playerSeg;
            bDepth[i] = DEEP;
            bLive[i] = 1;
            fireLock = 4;
            return;
        }
    }

    // Shots travel down the tube, away from the rim.
    function moveShots() as Void {
        for (var i = 0; i < MAXB; i++) {
            if (bLive[i] == 0) { continue; }
            bDepth[i] -= 22;
            if (bDepth[i] <= 0) { bLive[i] = 0; continue; }
            for (var k = 0; k < MAXE; k++) {
                if (eLive[k] == 0 || eSeg[k] != bSeg[i]) { continue; }
                if ((eDepth[k] - bDepth[i]).abs() > 18) { continue; }
                eLive[k] = 0;
                enemies--;
                bLive[i] = 0;
                break;
            }
        }
    }

    function draw(dc as Dc, ox as Number, oy as Number, colour as Number) as Void {
        if (!laidOut) { layout(); }
        var n = segCount();
        var closed = isClosed();
        dc.setPenWidth(1);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        // The web: a spoke at every vertex, then the near and far rim along
        // every segment.
        //
        // An open rim has one more vertex than it has segments. Walking these
        // together in a single loop dropped the last spoke and the last rim
        // edge, which left the open levels visibly unfinished at one end.
        var verts = closed ? n : n + 1;
        for (var i = 0; i < verts; i++) {
            dc.drawLine(ox + vx(i, DEEP), oy + vy(i, DEEP),
                        ox + vx(i, 0), oy + vy(i, 0));
        }
        for (var s = 0; s < n; s++) {
            var j = nextV(s);
            dc.drawLine(ox + vx(s, DEEP), oy + vy(s, DEEP),
                        ox + vx(j, DEEP), oy + vy(j, DEEP));
            dc.drawLine(ox + vx(s, 0), oy + vy(s, 0),
                        ox + vx(j, 0), oy + vy(j, 0));
        }

        // Enemies: a bowtie straddling their segment at their depth.
        dc.setColor(Theme.FRUIT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < MAXE; i++) {
            if (eLive[i] == 0) { continue; }
            var d = eDepth[i];
            var s = eSeg[i];
            var j = nextV(s);
            var x0 = ox + vx(s, d);
            var y0 = oy + vy(s, d);
            var x1 = ox + vx(j, d);
            var y1 = oy + vy(j, d);
            var dd = (d + 26 > DEEP) ? DEEP : d + 26;
            var xm = ox + midX(s, dd);
            var ym = oy + midY(s, dd);
            dc.drawLine(x0, y0, xm, ym);
            dc.drawLine(x1, y1, xm, ym);
            dc.drawLine(x0, y0, x1, y1);
        }

        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < MAXB; i++) {
            if (bLive[i] == 0) { continue; }
            dc.fillRectangle(ox + midX(bSeg[i], bDepth[i]) - 1,
                             oy + midY(bSeg[i], bDepth[i]) - 1, 3, 3);
        }

        if (state == DYING) { return; }
        // The blaster: a claw astride its segment on the rim.
        dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
        var s = playerSeg;
        var j = nextV(s);
        var x0 = ox + vx(s, DEEP);
        var y0 = oy + vy(s, DEEP);
        var x1 = ox + vx(j, DEEP);
        var y1 = oy + vy(j, DEEP);
        var xm = ox + midX(s, DEEP - 34);
        var ym = oy + midY(s, DEEP - 34);
        dc.drawLine(x0, y0, xm, ym);
        dc.drawLine(x1, y1, xm, ym);
        dc.drawLine(x0, y0, x1, y1);
        dc.fillRectangle(xm - 1, ym - 1, 3, 3);
    }
}
