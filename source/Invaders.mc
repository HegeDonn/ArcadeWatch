import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Space Invaders, playing itself.
//
// The formation is a rigid block that steps sideways and drops at the edges,
// exactly as the cabinet does, and speeds up as it thins out -- that
// acceleration is not a difficulty curve, it is the original running out of
// sprites to move and going faster for free. Kept here because it is the
// thing everyone remembers.
module Invaders {

    const COLS = 11;
    const ROWS = 5;
    const N = COLS * ROWS;

    const READY = 0; const PLAY = 1; const DYING = 2; const OVER = 3;
    const READY_FRAMES = 4 * Shell.FPS;
    const DIE_FRAMES   = 24;
    const OVER_FRAMES  = 5 * Shell.FPS;

    const RANK_COL = [0x00E0E0, 0xFFB8FF, 0xFFB8FF,
                      0xFFB852, 0xFFB852] as Array<Number>;

    var state as Number = 0;
    var timer as Number = 0;
    var lives as Number = 3;
    var level as Number = 1;

    var alive = new [N];
    var liveCount as Number = 0;

    var stepX as Number = 20;            // cell pitch
    var stepY as Number = 15;
    var originX as Number = 60;          // formation top-left when marchX = 0
    var originY as Number = 90;
    var marchX as Number = 0;
    var marchY as Number = 0;
    var dir as Number = 1;
    var animFrame as Number = 0;
    var stepTimer as Number = 0;

    var leftLimit as Number = 30;
    var rightLimit as Number = 360;
    var gunY as Number = 330;
    var shieldY as Number = 296;
    var gunX as Number = 195;
    var laidOut as Boolean = false;

    var shotX as Number = 0;             // the player's single shot
    var shotY as Number = -1;

    const BOMBS = 3;
    var bombX = new [BOMBS];
    var bombY = new [BOMBS];

    const SHIELDS = 4;
    const SHIELD_CELLS = 6;              // 3 wide x 2 tall
    var shield = new [SHIELDS * SHIELD_CELLS];
    var shieldX = new [SHIELDS];

    function layout() as Void {
        var w = Layout.screenW;
        var h = Layout.screenH;
        var cx = w / 2;
        var r = (w < h ? w : h) / 2 - 6;

        stepX = (w * 2) / (COLS + 2) / 2;
        stepY = h / 26;
        var span = (COLS - 1) * stepX + InvaderData.W * InvaderData.SCALE;
        originX = cx - span / 2 - stepX;
        originY = h / 4;
        // March within the chord at the formation's lowest useful row.
        var dy = (h * 6) / 10 - h / 2;
        var half = isqrt(r * r - dy * dy);
        leftLimit = cx - half + 4;
        rightLimit = cx + half - 4 - span;
        if (rightLimit < leftLimit) { rightLimit = leftLimit; }
        gunY = h / 2 + (r * 7) / 10;
        shieldY = gunY - h / 12;
        for (var i = 0; i < SHIELDS; i++) {
            shieldX[i] = cx - (w / 4) - 10 + i * (w / 6);
        }
        laidOut = true;
    }

    function isqrt(v as Number) as Number {
        if (v <= 0) { return 0; }
        return Math.sqrt(v.toFloat()).toNumber();
    }

    function reset() as Void {
        if (!laidOut) { layout(); }
        level = 1;
        lives = 3;
        newWave();
    }

    function newWave() as Void {
        for (var i = 0; i < N; i++) { alive[i] = 1; }
        liveCount = N;
        marchX = (rightLimit - leftLimit) / 2;
        marchY = 0;
        dir = 1;
        animFrame = 0;
        stepTimer = 0;
        for (var i = 0; i < SHIELDS * SHIELD_CELLS; i++) { shield[i] = 1; }
        respawn();
        state = READY;
        timer = READY_FRAMES;
    }

    function respawn() as Void {
        gunX = Layout.screenW / 2;
        shotY = -1;
        for (var i = 0; i < BOMBS; i++) { bombY[i] = -1; }
    }

    function showingClock() as Boolean { return state == READY || state == OVER; }
    function skipDwell() as Void { if (showingClock() && timer > 4) { timer = 4; } }

    function colX(c as Number) as Number { return originX + marchX + c * stepX; }
    function rowY(r as Number) as Number { return originY + marchY + r * stepY; }

    // How often the block steps. Emptier formation, faster march.
    function stepPeriod() as Number {
        var p = 2 + (liveCount * 16) / N;
        var q = p - (level - 1);
        return (q < 1) ? 1 : q;
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

        march();
        steerGun();
        moveShot();
        moveBombs();
        dropBomb();

        if (liveCount <= 0) {
            level++;
            newWave();
        }
    }

    function march() as Void {
        stepTimer++;
        if (stepTimer < stepPeriod()) { return; }
        stepTimer = 0;
        animFrame = 1 - animFrame;

        var w = spanOfLiving();
        marchX += dir * 4;
        if (marchX + w[0] < leftLimit || marchX + w[1] > rightLimit + (COLS - 1) * stepX) {
            dir = -dir;
            marchX += dir * 4;
            marchY += stepY / 2;
            if (originY + marchY + ROWS * stepY > shieldY) {
                state = DYING;              // they got to the bottom
                timer = DIE_FRAMES;
            }
        }
    }

    // Only the occupied columns matter for the turn-around, which is why a
    // thinning formation drifts wider before it reverses.
    function spanOfLiving() as Array<Number> {
        var lo = COLS;
        var hi = -1;
        for (var c = 0; c < COLS; c++) {
            for (var r = 0; r < ROWS; r++) {
                if (alive[r * COLS + c] == 1) {
                    if (c < lo) { lo = c; }
                    if (c > hi) { hi = c; }
                    break;
                }
            }
        }
        if (hi < 0) { return [0, 0] as Array<Number>; }
        return [originX + lo * stepX, originX + hi * stepX] as Array<Number>;
    }

    function lowestInColumn(c as Number) as Number {
        for (var r = ROWS - 1; r >= 0; r--) {
            if (alive[r * COLS + c] == 1) { return r; }
        }
        return -1;
    }

    function steerGun() as Void {
        // Dodge first: a bomb close above is worth more than a shot.
        for (var i = 0; i < BOMBS; i++) {
            if (bombY[i] < 0) { continue; }
            if (bombY[i] > gunY - 60 && (bombX[i] - gunX).abs() < 12) {
                gunX += (bombX[i] > gunX) ? -6 : 6;
                clampGun();
                return;
            }
        }
        // Otherwise line up under the nearest column that still has anyone.
        var best = -1;
        var bestD = 99999;
        for (var c = 0; c < COLS; c++) {
            if (lowestInColumn(c) < 0) { continue; }
            var x = colX(c) + InvaderData.W;
            var d = (x - gunX).abs();
            if (d < bestD) { bestD = d; best = x; }
        }
        if (best < 0) { return; }
        if (gunX < best - 2) { gunX += 4; }
        else if (gunX > best + 2) { gunX -= 4; }
        else if (shotY < 0) {
            shotY = gunY - 6;
            shotX = gunX;
        }
        clampGun();
    }

    function clampGun() as Void {
        var lo = leftLimit + 8;
        var hi = Layout.screenW - leftLimit - 8;
        if (gunX < lo) { gunX = lo; }
        if (gunX > hi) { gunX = hi; }
    }

    function moveShot() as Void {
        if (shotY < 0) { return; }
        shotY -= 12;
        if (shotY < originY + marchY - stepY) { shotY = -1; return; }
        if (hitShield(shotX, shotY)) { shotY = -1; return; }
        for (var r = 0; r < ROWS; r++) {
            var y = rowY(r);
            if (shotY < y || shotY > y + InvaderData.H * InvaderData.SCALE) { continue; }
            for (var c = 0; c < COLS; c++) {
                var i = r * COLS + c;
                if (alive[i] == 0) { continue; }
                var x = colX(c);
                if (shotX >= x && shotX <= x + InvaderData.W * InvaderData.SCALE) {
                    alive[i] = 0;
                    liveCount--;
                    shotY = -1;
                    return;
                }
            }
        }
    }

    function moveBombs() as Void {
        for (var i = 0; i < BOMBS; i++) {
            if (bombY[i] < 0) { continue; }
            bombY[i] += 5;
            if (hitShield(bombX[i], bombY[i])) { bombY[i] = -1; continue; }
            if (bombY[i] > gunY + 6) { bombY[i] = -1; continue; }
            if (bombY[i] > gunY - 6 && (bombX[i] - gunX).abs() < 8) {
                state = DYING;
                timer = DIE_FRAMES;
                bombY[i] = -1;
            }
        }
    }

    function dropBomb() as Void {
        if (Math.rand() % 24 != 0) { return; }
        var slot = -1;
        for (var i = 0; i < BOMBS; i++) { if (bombY[i] < 0) { slot = i; break; } }
        if (slot < 0) { return; }
        var c = Math.rand() % COLS;
        var r = lowestInColumn(c);
        if (r < 0) { return; }
        bombX[slot] = colX(c) + InvaderData.W;
        bombY[slot] = rowY(r) + InvaderData.H * InvaderData.SCALE;
    }

    function hitShield(px as Number, py as Number) as Boolean {
        if (py < shieldY || py > shieldY + 12) { return false; }
        for (var s = 0; s < SHIELDS; s++) {
            var dx = px - shieldX[s];
            if (dx < 0 || dx >= 30) { continue; }
            var cell = (py - shieldY < 6) ? 0 : 3;
            cell += dx / 10;
            var i = s * SHIELD_CELLS + cell;
            if (shield[i] == 1) { shield[i] = 0; return true; }
        }
        return false;
    }

    function draw(dc as Dc, ox as Number, oy as Number, colour as Number) as Void {
        if (!laidOut) { layout(); }
        var S = InvaderData.SCALE;
        var runs = InvaderData.RUNS;

        for (var r = 0; r < ROWS; r++) {
            var y = oy + rowY(r);
            var idx = r * 2 + animFrame;
            var off = InvaderData.OFF[idx];
            var n = InvaderData.CNT[idx];
            dc.setColor(RANK_COL[r], Graphics.COLOR_TRANSPARENT);
            for (var c = 0; c < COLS; c++) {
                if (alive[r * COLS + c] == 0) { continue; }
                var x = ox + colX(c);
                for (var k = 0; k < n; k++) {
                    var b = (off + k) * 3;
                    dc.fillRectangle(x + runs[b + 1] * S, y + runs[b] * S,
                                     (runs[b + 2] - runs[b + 1] + 1) * S, S);
                }
            }
        }

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var s = 0; s < SHIELDS; s++) {
            for (var k = 0; k < SHIELD_CELLS; k++) {
                if (shield[s * SHIELD_CELLS + k] == 0) { continue; }
                dc.fillRectangle(ox + shieldX[s] + (k % 3) * 10,
                                 oy + shieldY + (k / 3) * 6, 9, 5);
            }
        }

        if (shotY >= 0) {
            dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(ox + shotX, oy + shotY, 2, 6);
        }
        dc.setColor(Theme.DOT, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < BOMBS; i++) {
            if (bombY[i] >= 0) { dc.fillRectangle(ox + bombX[i], oy + bombY[i], 2, 5); }
        }

        if (state != DYING) {
            dc.setColor(0x00C853, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(ox + gunX - 9, oy + gunY, 19, 5);
            dc.fillRectangle(ox + gunX - 1, oy + gunY - 5, 3, 5);
        }
    }
}
