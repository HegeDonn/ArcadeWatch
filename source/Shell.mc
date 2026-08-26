import Toybox.Lang;
import Toybox.System;

// The cabinet the games sit in.
//
// Everything that is true of the watch rather than of any one game lives
// here: the frame clock, which game is showing, the swipe that recolours the
// maze, the swipe that changes game, and the tap that peeks at the sensors.
// A game only has to simulate itself and draw its own playfield.
//
// Dispatch is an if-chain rather than a base class with virtual methods. The
// games are modules, not objects -- Pac-Man's was already written that way and
// converting it would have meant touching every line of the AI for no gain --
// so this trades a little elegance for not rewriting working code.
module Shell {

    const FPS = 15;
    const TRACE = false;

    const PACMAN = 0; const INVADERS = 1; const BRICKS = 2; const ROCKS = 3;
    const COUNT = 4;

    var game as Number = PACMAN;
    var frame as Number = 0;

    // ---- tap to peek -------------------------------------------------------
    const INFO_FRAMES = 5 * FPS;
    var infoTimer as Number = 0;

    function showInfo() as Void {
        Sensors.reset();              // always a fresh reading on tap
        infoTimer = INFO_FRAMES;
    }
    function hideInfo() as Void { infoTimer = 0; }
    function showingInfo() as Boolean { return infoTimer > 0; }

    // ---- the swipe animation ----------------------------------------------
    // Sideways recolours, up/down changes game. Either way the whole screen
    // slides: the outgoing state leaves and the incoming one follows it in.
    // The simulation freezes for the duration so both halves show one instant.
    const SLIDE_FRAMES = 10;
    const CHANGE_COLOUR = 0;
    const CHANGE_GAME = 1;

    var slideStep as Number = 0;
    var slideDir as Number = 0;       // +1 new content enters from right/bottom
    var slideAxis as Number = 0;      // 0 horizontal, 1 vertical
    var slideArmed as Boolean = false;
    var pendingChange as Number = -1;
    var pendingDelta as Number = 0;

    function startSlide(axis as Number, dir as Number,
                        kind as Number, delta as Number) as Void {
        if (slideStep > 0) { return; }        // already mid-swipe
        slideAxis = axis;
        slideDir = dir;
        pendingChange = kind;
        pendingDelta = delta;
        slideStep = SLIDE_FRAMES;
        slideArmed = true;
    }

    // Applied by the view, between drawing the outgoing screen and the
    // incoming one -- so the change happens *inside* the animation.
    function applyPending() as Void {
        if (pendingChange == CHANGE_COLOUR) {
            Theme.cycleWall();
        } else if (pendingChange == CHANGE_GAME) {
            game = (game + pendingDelta + COUNT) % COUNT;
            reset();
        }
        pendingChange = -1;
    }

    // 0..100, eased out so it leaves fast and settles gently.
    function slideProgress() as Number {
        var t = SLIDE_FRAMES - slideStep;
        var p = (t * 100) / SLIDE_FRAMES;
        var inv = 100 - p;
        return 100 - (inv * inv) / 100;
    }

    // ---- dispatch ----------------------------------------------------------
    function reset() as Void {
        if (game == PACMAN) { PacGame.newGame(); }
        else if (game == INVADERS) { Invaders.reset(); }
        else if (game == BRICKS) { Bricks.reset(); }
        else { Rocks.reset(); }
    }

    function update() as Void {
        frame++;
        if (infoTimer > 0) {
            infoTimer--;
            Sensors.poll(frame);
        }
        if (slideStep > 0) {
            slideStep--;
            return;                            // frozen while the screen moves
        }
        if (game == PACMAN) { PacGame.update(); }
        else if (game == INVADERS) { Invaders.update(); }
        else if (game == BRICKS) { Bricks.update(); }
        else { Rocks.update(); }
    }

    // Is the big time-and-date panel up? Every game raises it between lives,
    // which is the whole conceit: the arcade's READY! is the clock.
    function showingClock() as Boolean {
        if (game == PACMAN) { return PacGame.showingClock(); }
        if (game == INVADERS) { return Invaders.showingClock(); }
        if (game == BRICKS) { return Bricks.showingClock(); }
        return Rocks.showingClock();
    }

    function skipDwell() as Void {
        if (game == PACMAN) { PacGame.skipDwell(); }
        else if (game == INVADERS) { Invaders.skipDwell(); }
        else if (game == BRICKS) { Bricks.skipDwell(); }
        else { Rocks.skipDwell(); }
    }

    function lives() as Number {
        if (game == PACMAN) { return PacGame.lives; }
        if (game == INVADERS) { return Invaders.lives; }
        if (game == BRICKS) { return Bricks.lives; }
        return Rocks.lives;
    }

    function level() as Number {
        if (game == PACMAN) { return PacGame.level; }
        if (game == INVADERS) { return Invaders.level; }
        if (game == BRICKS) { return Bricks.level; }
        return Rocks.level;
    }

    // Only Pac-Man streams a trace; the other games have not needed one.
    function trace() as Void {
        if (game == PACMAN) { PacGame.trace(); }
    }

    // Only Pac-Man keeps a static layer worth caching; the others are cheap
    // enough to draw outright every frame.
    function usesBuffer() as Boolean { return game == PACMAN; }
}
