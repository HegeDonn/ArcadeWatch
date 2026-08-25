import Toybox.Lang;
import Toybox.Math;

// The four personalities, targeted exactly the way the 1980 cabinet does
// it -- including Pinky's famous overflow bug.
// Class-level consts aren't addressable as Ghost.FOO from other files, so
// the enums live in modules.
module GhostMode { const SCATTER = 0; const CHASE = 1; const FRIGHT = 2; }
module GhostState {
    const HOUSE = 0; const EXIT = 1; const OUT = 2; const EYES = 3; const ENTER = 4;
}

class Ghost extends Actor {

    // Where each ghost sulks off to during scatter.
    static const CORNER_C = [25, 2, 27, 0] as Array<Number>;
    static const CORNER_R = [0, 0, 30, 30] as Array<Number>;
    // Start tiles: Blinky is already outside, above the door.
    static const HOME_C = [14, 14, 12, 16] as Array<Number>;
    static const HOME_R = [11, 14, 14, 14] as Array<Number>;

    // The tile directly above the ghost-house door.
    static const GATE_C = 14;
    static const GATE_R = 11;

    var who as Number = 0;
    var mode as Number = 0;
    var state as Number = 0;
    var releaseIn as Number = 0;   // frames until it may leave the house
    var bob as Number = 0;

    function initialize(index as Number) {
        Actor.initialize();
        who = index;
        ghostRules = true;
    }

    function respawn(mode0 as Number, releaseFrames as Number) as Void {
        place(HOME_C[who], HOME_R[who], (who == 0) ? Maze.LEFT : Maze.UP);
        mode = mode0;
        state = (who == 0) ? GhostState.OUT : GhostState.HOUSE;
        releaseIn = releaseFrames;
        bob = 0;
    }

    function isEdible() as Boolean { return mode == GhostMode.FRIGHT && state != GhostState.EYES && state != GhostState.ENTER; }
    function isDangerous() as Boolean {
        return mode != GhostMode.FRIGHT && (state == GhostState.OUT || state == GhostState.EXIT);
    }
    function isEyes() as Boolean { return state == GhostState.EYES || state == GhostState.ENTER; }
    function inHouse() as Boolean { return state == GhostState.HOUSE; }

    // Mode changes make every ghost turn on the spot.
    //
    // (tx, ty) is the tile being *left* and prog is progress toward the tile
    // ahead, so a mid-tile reversal has to hand the origin over to the tile
    // ahead as well. Flipping dir alone re-reads the leftover progress as
    // motion into whatever is in front -- which walked ghosts into the outer
    // wall whenever a power pellet was eaten next to one.
    function forceReverse() as Void {
        if (state != GhostState.OUT) { return; }
        var nd = reverse();
        if (prog > 0) {
            tx = Maze.wrapCol(tx + Maze.DX[dir]);
            ty += Maze.DY[dir];
            prog = STEP - prog;
        }
        dir = nd;
    }

    function setMode(m as Number) as Void {
        if (isEyes()) { return; }
        mode = m;
    }

    function getEaten() as Void {
        state = GhostState.EYES;
        mode = GhostMode.CHASE;
    }

    function targetTile() as Array<Number> {
        if (state == GhostState.EYES) { return [GATE_C, GATE_R]; }
        if (mode == GhostMode.SCATTER) { return [CORNER_C[who], CORNER_R[who]]; }

        var pac = Game.pac;
        var pc = pac.tx;
        var pr = pac.ty;
        var pd = pac.dir;

        if (who == 0) {                              // Blinky: straight at him
            return [pc, pr];
        }
        if (who == 1) {                              // Pinky: four ahead...
            var c = pc + Maze.DX[pd] * 4;
            var r = pr + Maze.DY[pd] * 4;
            if (pd == Maze.UP) { c -= 4; }           // ...and the overflow bug
            return [c, r];
        }
        if (who == 2) {                              // Inky: reflect Blinky
            var c = pc + Maze.DX[pd] * 2;
            var r = pr + Maze.DY[pd] * 2;
            if (pd == Maze.UP) { c -= 2; }
            var b = Game.ghosts[0];
            return [2 * c - b.tx, 2 * r - b.ty];
        }
        // Clyde: bold at range, shy up close
        var dc = pc - tx;
        var dr = pr - ty;
        if (dc * dc + dr * dr > 64) { return [pc, pr]; }
        return [CORNER_C[who], CORNER_R[who]];
    }

    function onArrive() as Void {
        if (state == GhostState.EXIT) {
            if (tx != GATE_C) { dir = (tx < GATE_C) ? Maze.RIGHT : Maze.LEFT; return; }
            if (ty > GATE_R) { dir = Maze.UP; return; }
            state = GhostState.OUT;
            dir = Maze.LEFT;
            return;
        }
        if (state == GhostState.ENTER) {
            if (ty < HOME_R[who]) { dir = Maze.DOWN; return; }
            state = GhostState.EXIT;                             // revived: straight back out
            mode = Game.modeNow();
            dir = Maze.UP;
            return;
        }
        if (state == GhostState.EYES && tx == GATE_C && ty == GATE_R) {
            state = GhostState.ENTER;
            dir = Maze.DOWN;
            return;
        }

        var back = reverse();

        if (mode == GhostMode.FRIGHT && state == GhostState.OUT) {
            // Frightened ghosts pick at random, but still never turn back.
            var opts = [0, 0, 0, 0] as Array<Number>;
            var n = 0;
            for (var d = 0; d < 4; d++) {
                if (d != back && canGo(d)) { opts[n] = d; n++; }
            }
            dir = (n > 0) ? opts[Math.rand() % n] : back;
            return;
        }

        var t = targetTile();
        var best = -1;
        var bestD = 0;
        // d ascends UP, LEFT, DOWN, RIGHT -- with a strict <, that IS the
        // arcade's tie-break order.
        for (var d = 0; d < 4; d++) {
            if (d == back || !canGo(d)) { continue; }
            var nc = tx + Maze.DX[d];
            var nr = ty + Maze.DY[d];
            var ddc = nc - t[0];
            var ddr = nr - t[1];
            var sq = ddc * ddc + ddr * ddr;
            if (best < 0 || sq < bestD) { bestD = sq; best = d; }
        }
        dir = (best >= 0) ? best : back;
    }

    function update(baseSpd as Number, frightSpd as Number,
                    eyeSpd as Number, tunnelSpd as Number) as Void {
        if (state == GhostState.HOUSE) {
            bob = (bob + 1) % 32;
            if (releaseIn > 0) { releaseIn--; }
            if (releaseIn <= 0) { state = GhostState.EXIT; dir = Maze.UP; prog = 0; }
            return;
        }
        var s = baseSpd;
        if (isEyes()) {
            s = eyeSpd;
        } else if (mode == GhostMode.FRIGHT) {
            s = frightSpd;
        } else if (ty == 14 && (tx < 6 || tx > 21)) {
            s = tunnelSpd;                            // the tunnel drags on them
        }
        advance(s);
    }
}
