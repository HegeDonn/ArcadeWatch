import Toybox.Lang;

// Tile-to-tile movement, the way the arcade does it: an actor always sits
// on a tile plus a progress fraction toward the next one, and only ever
// changes its mind when it lands on a tile centre. STEP subunits per tile.
class Actor {
    const STEP = 16;

    var tx as Number = 0;
    var ty as Number = 0;
    var dir as Number = Maze.LEFT;
    var prog as Number = 0;
    var ghostRules as Boolean = false;   // may pass the ghost-house door

    function initialize() {}

    function place(c as Number, r as Number, d as Number) as Void {
        tx = c; ty = r; dir = d; prog = 0;
    }

    function canGo(d as Number) as Boolean {
        return Maze.isOpenFor(Maze.wrapCol(tx + Maze.DX[d]),
                              ty + Maze.DY[d], ghostRules);
    }

    function reverse() as Number { return (dir + 2) % 4; }

    // Called the instant we land on a new tile; subclasses set `dir` here.
    function onArrive() as Void {}

    function advance(spd as Number) as Void {
        // Never accumulate progress into a wall. Without this an actor that
        // is somehow facing a blocked tile drifts visually into it and then,
        // once prog passes STEP, commits the move.
        if (prog == 0 && !canGo(dir)) {
            onArrive();
            if (!canGo(dir)) { return; }
        }
        prog += spd;
        while (prog >= STEP) {
            prog -= STEP;
            tx = Maze.wrapCol(tx + Maze.DX[dir]);
            ty += Maze.DY[dir];
            onArrive();
            if (!canGo(dir)) { prog = 0; break; }
        }
    }

    function pixX() as Number {
        return Layout.tileX(tx) + (Maze.DX[dir] * prog * Layout.cell) / STEP;
    }

    function pixY() as Number {
        return Layout.tileY(ty) + (Maze.DY[dir] * prog * Layout.cell) / STEP;
    }
}
