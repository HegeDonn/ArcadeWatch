import Toybox.Lang;

// Runtime maze state: the static walls come straight from MazeData; the
// dots are a mutable copy so eating one is a single bit clear.
module Maze {
    const UP = 0; const LEFT = 1; const DOWN = 2; const RIGHT = 3;
    const DX = [0, -1, 0, 1] as Array<Number>;
    const DY = [-1, 0, 1, 0] as Array<Number>;

    // Untyped: new[N] is Array<Null>; reset() fills them with Numbers
    // before any read.
    var dots = new [MazeData.ROWS];
    var power = new [MazeData.ROWS];
    var dotsLeft as Number = 0;

    function reset() as Void {
        for (var r = 0; r < MazeData.ROWS; r++) {
            dots[r] = MazeData.DOT[r];
            power[r] = MazeData.POWER[r];
        }
        dotsLeft = MazeData.DOT_TOTAL;
    }

    // A tile a sprite may occupy. Off the top/bottom is solid; off the
    // sides is the wrap tunnel, which is open.
    function isOpen(c as Number, r as Number) as Boolean {
        if (r < 0 || r >= MazeData.ROWS) { return false; }
        if (c < 0 || c >= MazeData.COLS) { return true; }
        var bit = 1 << c;
        return ((MazeData.WALL[r] & bit) == 0)
            && ((MazeData.VOID[r] & bit) == 0);
    }

    // Ghosts may pass the house door; Pac-Man may not.
    function isOpenFor(c as Number, r as Number, ghost as Boolean) as Boolean {
        if (!isOpen(c, r)) { return false; }
        if (ghost) { return true; }
        if (r < 0 || r >= MazeData.ROWS || c < 0 || c >= MazeData.COLS) { return true; }
        return (MazeData.DOOR[r] & (1 << c)) == 0;
    }

    function wrapCol(c as Number) as Number {
        if (c < 0) { return MazeData.COLS - 1; }
        if (c >= MazeData.COLS) { return 0; }
        return c;
    }


    // -> 0 nothing, 1 dot, 2 power pellet
    function eat(c as Number, r as Number) as Number {
        if (r < 0 || r >= MazeData.ROWS || c < 0 || c >= MazeData.COLS) { return 0; }
        var bit = 1 << c;
        if ((dots[r] & bit) != 0) {
            dots[r] &= ~bit;
            dotsLeft--;
            return 1;
        }
        if ((power[r] & bit) != 0) {
            power[r] &= ~bit;
            dotsLeft--;
            return 2;
        }
        return 0;
    }

}
