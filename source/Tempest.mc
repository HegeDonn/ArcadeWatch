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
// The web is 16 segments, which is 4 units of the 64-step trig table apiece,
// so every angle in here is exact integer arithmetic. Depth runs 0 at the far
// end to DEEP at the rim.
module Tempest {

    const SEG = 16;
    const STEP = Trig.TURN / SEG;         // 4 units of the circle per segment
    const DEEP = 256;                     // depth at the rim

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
    var outerR as Number = 170;
    var innerR as Number = 42;
    var laidOut as Boolean = false;

    function layout() as Void {
        cx = Layout.screenW / 2;
        cy = Layout.screenH / 2;
        var m = (Layout.screenW < Layout.screenH) ? Layout.screenW : Layout.screenH;
        outerR = m / 2 - 24;
        innerR = m / 9;
        laidOut = true;
    }

    function radiusAt(d as Number) as Number {
        return innerR + ((outerR - innerR) * d) / DEEP;
    }
    function px(a as Number, r as Number) as Number {
        return cx + (Trig.cos(a) * r) / 256;
    }
    function py(a as Number, r as Number) as Number {
        return cy + (Trig.sin(a) * r) / 256;
    }

    function reset() as Void {
        if (!laidOut) { layout(); }
        level = 1;
        lives = 3;
        newWave();
    }

    function newWave() as Void {
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
        playerSeg = 0;
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
            eSeg[i] = Math.rand() % SEG;
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
                eSeg[i] = (eSeg[i] + ((Math.rand() % 2 == 0) ? 1 : SEG - 1)) % SEG;
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
            var fwd = (target - playerSeg + SEG) % SEG;
            playerSeg = (fwd <= SEG / 2) ? (playerSeg + 1) % SEG
                                         : (playerSeg + SEG - 1) % SEG;
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
        dc.setPenWidth(1);
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        // The web: both rims as 16-gons, plus a spoke on every boundary.
        for (var s = 0; s < SEG; s++) {
            var a0 = s * STEP;
            var a1 = (s + 1) * STEP;
            dc.drawLine(ox + px(a0, outerR), oy + py(a0, outerR),
                        ox + px(a1, outerR), oy + py(a1, outerR));
            dc.drawLine(ox + px(a0, innerR), oy + py(a0, innerR),
                        ox + px(a1, innerR), oy + py(a1, innerR));
            dc.drawLine(ox + px(a0, innerR), oy + py(a0, innerR),
                        ox + px(a0, outerR), oy + py(a0, outerR));
        }

        // Enemies: a bowtie straddling their segment at their depth.
        dc.setColor(Theme.FRUIT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < MAXE; i++) {
            if (eLive[i] == 0) { continue; }
            var r = radiusAt(eDepth[i]);
            var a0 = eSeg[i] * STEP;
            var a1 = a0 + STEP;
            var x0 = ox + px(a0, r);
            var y0 = oy + py(a0, r);
            var x1 = ox + px(a1, r);
            var y1 = oy + py(a1, r);
            var mid = radiusAt(eDepth[i]) + 7;
            var xm = ox + px(a0 + STEP / 2, mid);
            var ym = oy + py(a0 + STEP / 2, mid);
            dc.drawLine(x0, y0, xm, ym);
            dc.drawLine(x1, y1, xm, ym);
            dc.drawLine(x0, y0, x1, y1);
        }

        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < MAXB; i++) {
            if (bLive[i] == 0) { continue; }
            var r = radiusAt(bDepth[i]);
            var a = bSeg[i] * STEP + STEP / 2;
            dc.fillRectangle(ox + px(a, r) - 1, oy + py(a, r) - 1, 3, 3);
        }

        if (state == DYING) { return; }
        // The blaster: a claw sitting astride its segment on the rim.
        dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
        var a0 = playerSeg * STEP;
        var a1 = a0 + STEP;
        var am = a0 + STEP / 2;
        var inR = outerR - 14;
        var x0 = ox + px(a0, outerR);
        var y0 = oy + py(a0, outerR);
        var x1 = ox + px(a1, outerR);
        var y1 = oy + py(a1, outerR);
        var xm = ox + px(am, inR);
        var ym = oy + py(am, inR);
        dc.drawLine(x0, y0, xm, ym);
        dc.drawLine(x1, y1, xm, ym);
        dc.drawLine(x0, y0, x1, y1);
        dc.fillRectangle(xm - 1, ym - 1, 3, 3);
    }
}
