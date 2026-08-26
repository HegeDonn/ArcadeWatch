import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Breakout, playing itself.
//
// The wall is fitted to the circle rather than to a rectangle: each row is
// only as wide as the bezel allows at that height, so the stack comes out
// barrel-shaped and nothing is clipped. Same reasoning as the maze.
//
// Positions are in 1/16 pixels so the ball can travel at fractional speeds
// without floating-point maths in the hot loop.
module Bricks {

    const SUB = 16;
    const ROWS = 6;
    const COLS = 11;

    const READY = 0; const PLAY = 1; const DYING = 2; const OVER = 3;
    const READY_FRAMES = 4 * Shell.FPS;
    const DIE_FRAMES   = 20;
    const OVER_FRAMES  = 5 * Shell.FPS;

    // Row colours, warm at the top like the arcade.
    const ROW_COL = [0xFF0000, 0xFF7000, 0xFFB852, 0xFFFF00,
                     0x00C853, 0x00E0E0] as Array<Number>;

    var state as Number = 0;
    var timer as Number = 0;
    var lives as Number = 3;
    var level as Number = 1;

    var brick = new [ROWS * COLS];       // 1 = still there
    var left as Number = 0;

    // geometry, filled by layout()
    var bx0 = new [ROWS];                // row left edge, px
    var bw as Number = 24;               // brick width
    var bh as Number = 9;                // brick height
    var top as Number = 80;
    var padY as Number = 320;
    var padW as Number = 46;
    var wallL as Number = 40;            // play area bounds
    var wallR as Number = 350;
    var wallT as Number = 60;
    var floorY as Number = 340;
    var laidOut as Boolean = false;

    var ballX as Number = 0;             // 1/16 px
    var ballY as Number = 0;
    var velX as Number = 0;
    var velY as Number = 0;
    var padX as Number = 0;              // paddle centre, px

    function layout() as Void {
        var w = Layout.screenW;
        var h = Layout.screenH;
        var cx = w / 2;
        var cy = h / 2;
        var r = (w < h ? w : h) / 2 - 6;

        bh = h / 40;
        bw = (w * 3) / 4 / COLS;
        top = cy - (r * 7) / 10;
        wallT = top - bh;
        floorY = cy + (r * 8) / 10;
        padY = floorY - h / 40;
        padW = w / 8;

        // Rails first: they are the play area, and the wall has to fit inside
        // them. Fitting each row to the bare chord instead left the outer
        // bricks hanging past the rails.
        var dyp = padY - cy;
        wallL = cx - isqrt(r * r - dyp * dyp) + 4;
        wallR = w - wallL;
        var railSpan = wallR - wallL - 8;

        // Each row is then the narrower of the rails and its own chord.
        for (var i = 0; i < ROWS; i++) {
            var y = top + i * (bh + 2) + bh / 2;
            var dy = y - cy;
            var chord = isqrt(r * r - dy * dy) * 2 - 8;
            var span = COLS * bw;
            if (span > chord) { span = chord; }
            if (span > railSpan) { span = railSpan; }
            bx0[i] = cx - span / 2;
        }
        laidOut = true;
    }

    function isqrt(v as Number) as Number {
        if (v <= 0) { return 0; }
        return Math.sqrt(v.toFloat()).toNumber();
    }

    function rowWidth(i as Number) as Number {
        return (Layout.screenW / 2 - bx0[i]) * 2;
    }

    function reset() as Void {
        if (!laidOut) { layout(); }
        level = 1;
        lives = 3;
        newWall();
    }

    function newWall() as Void {
        for (var i = 0; i < ROWS * COLS; i++) { brick[i] = 1; }
        left = ROWS * COLS;
        serve();
        state = READY;
        timer = READY_FRAMES;
    }

    function serve() as Void {
        padX = Layout.screenW / 2;
        ballX = padX * SUB;
        ballY = (padY - 10) * SUB;
        var speed = 5 + level;
        if (speed > 9) { speed = 9; }
        velX = (Math.rand() % 2 == 0) ? speed : -speed;
        velY = -speed;
    }

    function showingClock() as Boolean { return state == READY || state == OVER; }
    function skipDwell() as Void { if (showingClock() && timer > 4) { timer = 4; } }

    function brickAt(px as Number, py as Number) as Number {
        if (py < top) { return -1; }
        var row = (py - top) / (bh + 2);
        if (row < 0 || row >= ROWS) { return -1; }
        if (py > top + row * (bh + 2) + bh) { return -1; }   // in the gap
        var col = (px - bx0[row]) * COLS / rowWidth(row);
        if (col < 0 || col >= COLS) { return -1; }
        var i = row * COLS + col;
        return (brick[i] == 1) ? i : -1;
    }

    function update() as Void {
        if (!laidOut) { layout(); }
        if (state == READY || state == OVER) {
            timer--;
            if (timer <= 0) {
                if (state == OVER) { reset(); }
                else { state = PLAY; }
            }
            return;
        }
        if (state == DYING) {
            timer--;
            if (timer <= 0) {
                lives--;
                if (lives <= 0) { state = OVER; timer = OVER_FRAMES; }
                else { serve(); state = READY; timer = READY_FRAMES; }
            }
            return;
        }

        steerPaddle();

        // Step in whole pixels so a fast ball cannot tunnel through a brick.
        var steps = 3;
        for (var s = 0; s < steps; s++) {
            ballX += (velX * SUB) / steps;
            ballY += (velY * SUB) / steps;
            var px = ballX / SUB;
            var py = ballY / SUB;

            // Force the sign rather than negating, and nudge clear of the
            // rail. Negating alone stuck the ball in a corner: clamping put it
            // exactly on the rail, so the test passed again on the next step
            // and flipped it straight back, every step, for ever.
            if (px <= wallL) { ballX = (wallL + 1) * SUB; velX = velX.abs(); }
            if (px >= wallR) { ballX = (wallR - 1) * SUB; velX = -velX.abs(); }
            if (py <= wallT) { ballY = (wallT + 1) * SUB; velY = velY.abs(); }

            var hit = brickAt(px, py);
            if (hit >= 0) {
                brick[hit] = 0;
                left--;
                velY = -velY;
                if (left <= 0) {
                    level++;
                    newWall();
                }
                return;                          // one brick per frame
            }

            // paddle
            if (velY > 0 && py >= padY - 2 && py <= padY + 4) {
                if (px >= padX - padW / 2 && px <= padX + padW / 2) {
                    velY = -velY.abs();          // always upward, never re-flip
                    ballY = (padY - 3) * SUB;
                    // Where it lands on the paddle steers it, as it should.
                    var off = (px - padX) * 8 / (padW / 2);
                    velX += off / 2;
                    if (velX > 10) { velX = 10; }
                    if (velX < -10) { velX = -10; }
                    if (velX == 0) { velX = 1; }
                }
            }

            if (py > floorY) {
                state = DYING;
                timer = DIE_FRAMES;
                return;
            }
        }
    }

    // The paddle aims at where the ball will cross its line, but only once the
    // ball is coming down, and with a deliberate error that grows with level.
    // Without the error it never misses and the game never ends.
    function steerPaddle() as Void {
        var target = Layout.screenW / 2;
        if (velY > 0) {
            var dy = padY - ballY / SUB;
            var dx = (velY != 0) ? (velX * dy) / velY : 0;
            target = ballX / SUB + dx;
            while (target < wallL || target > wallR) {       // fold the bounces
                if (target < wallL) { target = 2 * wallL - target; }
                if (target > wallR) { target = 2 * wallR - target; }
            }
            var slop = 6 + level * 2;
            target += (Math.rand() % (slop * 2 + 1)) - slop;
        }
        var speed = 7;
        if (padX < target - 1) { padX += speed; }
        else if (padX > target + 1) { padX -= speed; }
        if (padX < wallL + padW / 2) { padX = wallL + padW / 2; }
        if (padX > wallR - padW / 2) { padX = wallR - padW / 2; }
    }

    function draw(dc as Dc, ox as Number, oy as Number, colour as Number) as Void {
        if (!laidOut) { layout(); }

        for (var r = 0; r < ROWS; r++) {
            var y = oy + top + r * (bh + 2);
            var w = rowWidth(r) / COLS;
            dc.setColor(ROW_COL[r], Graphics.COLOR_TRANSPARENT);
            for (var c = 0; c < COLS; c++) {
                if (brick[r * COLS + c] == 0) { continue; }
                dc.fillRectangle(ox + bx0[r] + c * w, y, w - 2, bh);
            }
        }

        // side rails, in the swipeable colour so the theme still reads
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(ox + wallL - 4, oy + wallT, 3, floorY - wallT);
        dc.fillRectangle(ox + wallR + 2, oy + wallT, 3, floorY - wallT);
        dc.fillRectangle(ox + wallL - 4, oy + wallT - 3, wallR - wallL + 9, 3);

        if (state != DYING) {
            dc.setColor(Theme.PACMAN, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(ox + ballX / SUB - 2, oy + ballY / SUB - 2, 5, 5);
        }
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(ox + padX - padW / 2, oy + padY, padW, 5);
    }
}
