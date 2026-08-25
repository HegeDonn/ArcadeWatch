import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

// Arcade palette, straight off the original cabinet, plus the screen
// geometry derived in Layout.compute().
module Theme {
    const BG        = 0x000000;

    // Swipe cycles the maze colour. Arcade blue first; the rest are picked to
    // stay legible against peach dots on black.
    const WALLS = [0x2121DE, 0x00C853, 0xFF2D95, 0xFF7000,
                   0x00E0E0, 0xC0C0FF] as Array<Number>;
    var wallIdx as Number = 0;

    function wall() as Number { return WALLS[wallIdx]; }

    function cycleWall() as Number {
        wallIdx = (wallIdx + 1) % WALLS.size();
        saveChoice();
        return wallIdx;
    }

    // The kids' colour survives closing the app.
    function loadChoice() as Void {
        try {
            var v = Application.Storage.getValue("wall");
            if (v instanceof Lang.Number && v >= 0 && v < WALLS.size()) {
                wallIdx = v;
            }
        } catch (e) {}
    }

    function saveChoice() as Void {
        try { Application.Storage.setValue("wall", wallIdx); } catch (e) {}
    }
    const WALL_FLASH= 0xFFFFFF;   // level-complete flash
    const DOT       = 0xFFB8AE;   // pellet peach
    const PACMAN    = 0xFFFF00;
    const DOOR      = 0xFFB8FF;
    const TEXT      = 0xFFFFFF;
    const FRIGHT    = 0x2121DE;
    const FRIGHT_END= 0xFFFFFF;   // the last-seconds flash
    const EYE       = 0xFFFFFF;
    const PUPIL     = 0x2121DE;
    const FRUIT     = 0xFF0000;
    const HEART     = 0xFF3C3C;   // sensor icons keep their own meaning,
    const BODY      = 0x50DC78;   // so they don't follow the maze colour

    // Blinky, Pinky, Inky, Clyde
    const GHOST = [0xFF0000, 0xFFB8FF, 0x00FFFF, 0xFFB852] as Array<Number>;

    // Everything the offscreen buffer can contain. It must list *every* wall
    // colour, not just the current one: the palette is fixed when the buffer
    // is created, and a colour missing from it gets quantised to the nearest
    // entry the moment someone swipes.
    function bufferPalette() as Array<Number> {
        var p = [BG, DOT, DOOR, WALL_FLASH, HEART, BODY] as Array<Number>;
        return p.addAll(WALLS);
    }
}

// Everything positional lives here so the view, the sprites and the
// buffered maze all agree on where a tile is.
module Layout {
    var cell    as Number = 9;
    var originX as Number = 69;
    var originY as Number = 55;
    var half    as Number = 4;    // cell/2, precomputed
    var dotHalf as Number = 1;    // pellet half-size in px
    var pwrR    as Number = 4;    // power-pellet radius
    var inset   as Number = 2;    // wall-outline inset inside its tile
    var corner  as Number = 3;    // chamfer at convex wall corners
    var scoreY  as Number = 20;   // time-as-score baseline (top cap)
    var livesY  as Number = 348;

    // Sensor icons, in the margin either side of the maze.
    var iconScale as Number = 4;
    var iconLX  as Number = 4;
    var iconRX  as Number = 325;
    // The heart and the bust are different heights, so each is centred on
    // the screen's midline independently rather than padded to match.
    var iconHeartY as Number = 171;
    var iconBodyY  as Number = 163;

    // The maze is a 28:31 rectangle and the screen is a circle, so the
    // binding constraint is the maze's *diagonal*, not its width. Size the
    // cell from that and nothing ever falls off the bezel.
    function compute(w as Number, h as Number) as Void {
        var safe = (w < h ? w : h) / 2.0 - 2.0;
        var diag = Math.sqrt(
            (MazeData.COLS * MazeData.COLS + MazeData.ROWS * MazeData.ROWS).toFloat());
        cell = (2.0 * safe / diag).toNumber();
        if (cell < 4) { cell = 4; }

        originX = (w - MazeData.COLS * cell) / 2;
        originY = (h - MazeData.ROWS * cell) / 2;
        half    = cell / 2;
        inset   = (cell * 22) / 100;
        if (inset < 1) { inset = 1; }
        corner  = cell / 3;
        if (corner < 1) { corner = 1; }
        dotHalf = (cell * 16) / 100;
        if (dotHalf < 1) { dotHalf = 1; }
        pwrR    = (cell * 36) / 100;
        if (pwrR < 2) { pwrR = 2; }

        // Time-as-score sits in the cap above the maze, vertically centred
        // in whatever room the maze left us.
        scoreY = (originY - 28) / 2;
        if (scoreY < 2) { scoreY = 2; }
        livesY = originY + MazeData.ROWS * cell + 8;

        // The icons live in the margin the maze leaves at mid-height. Size
        // them from that margin so they can never collide with the maze.
        var margin = originX;
        iconScale = (margin - 8) / IconData.W;
        if (iconScale < 1) { iconScale = 1; }
        var iw = IconData.W * iconScale;
        iconLX = (margin - iw) / 2;
        var rightEdge = originX + MazeData.COLS * cell;
        iconRX = rightEdge + (w - rightEdge - iw) / 2;
        iconHeartY = (h - IconData.HEART_H * iconScale) / 2;
        iconBodyY = (h - IconData.BODY_H * iconScale) / 2;
    }

    // Top of the number that sits inside an icon, given the icon's clear rows.
    function iconTextY(baseY as Number, top as Number, bot as Number,
                       textH as Number) as Number {
        var band = (bot - top + 1) * iconScale;
        return baseY + top * iconScale + (band - textH) / 2;
    }

    function tileX(tx as Number) as Number { return originX + tx * cell + half; }
    function tileY(ty as Number) as Number { return originY + ty * cell + half; }
}
