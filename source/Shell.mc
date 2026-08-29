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
    const TEMPEST = 4;
    const COUNT = 5;

    var game as Number = PACMAN;
    var frame as Number = 0;

    // ---- tap to peek -------------------------------------------------------
    const INFO_FRAMES = 5 * FPS;
    var infoTimer as Number = 0;

    function showInfo() as Void {
        Sensors.refresh(frame);       // read now, not next tick
        infoTimer = INFO_FRAMES;
    }
    function hideInfo() as Void { infoTimer = 0; }
    function showingInfo() as Boolean { return infoTimer > 0; }

    // ---- the drag ----------------------------------------------------------
    //
    // The screen follows your finger. A drag is not a gesture that triggers an
    // animation afterwards -- the offset below IS the finger, live, and on
    // release it either carries through to the next screen or springs back to
    // this one. Sideways changes colour, up and down changes game.
    //
    // The simulation freezes for the duration so both halves show one instant.
    const SETTLE_FRAMES = 5;
    const TAKE_FRACTION = 4;          // drag a quarter of the way to commit
    const AXIS_SLOP = 8;              // px before we decide which way you meant

    // Momentum. Let go with some speed and it keeps rolling, stepping to the
    // next game or colour each time a whole screen goes past, until friction
    // brings it down and it settles on whichever one it stopped nearest.
    const FLING_MIN = 6;              // px/frame worth carrying on with
    const FLING_STOP = 5;             // below this, settle
    const FRICTION_NUM = 30;          // velocity *= 30/32 ...
    const FRICTION_DEN = 32;
    const FRICTION_FLAT = 2;          // ... and then loses 2 px/frame outright

    // The flat term is what makes it brake rather than trail off. Pure
    // exponential decay never actually reaches zero, so the last stretch
    // crawls along at a few px a frame and the whole thing feels like a
    // perished elastic band. Taking a constant off as well brings it to a
    // definite stop, and cuts a throw from ~2.3 s to ~1.7 s without losing any
    // of the roll: a hard fling still carries three screens.

    const CHANGE_COLOUR = 0;
    const CHANGE_GAME = 1;

    var axis as Number = -1;          // -1 undecided, 0 horizontal, 1 vertical
    var offset as Number = 0;         // px the current screen has moved
    var dragging as Boolean = false;
    var velocity as Number = 0;
    var tweening as Boolean = false;
    var tweenTotal as Number = 0;
    var tweenDone as Number = 0;
    var tweenFrames as Number = 0;
    var tweenT as Number = 0;

    var _startX as Number = 0;
    var _startY as Number = 0;
    var _lastDrag as Number = -100000;

    function span() as Number {
        return (axis == 1) ? Layout.screenH : Layout.screenW;
    }

    // Which way the incoming screen lies: dragging content left (negative
    // offset) brings the next one in from the right.
    function delta() as Number { return (offset < 0) ? 1 : -1; }

    function sliding() as Boolean {
        return dragging || tweening || offset != 0;
    }

    function dragStart(x as Number, y as Number) as Void {
        dragging = true;
        tweening = false;
        velocity = 0;
        axis = -1;
        offset = 0;
        _startX = x;
        _startY = y;
        _lastDrag = System.getTimer();
    }

    function dragMove(x as Number, y as Number) as Void {
        if (!dragging) { return; }
        _lastDrag = System.getTimer();
        var dx = x - _startX;
        var dy = y - _startY;
        if (axis < 0) {
            if (dx.abs() < AXIS_SLOP && dy.abs() < AXIS_SLOP) { return; }
            axis = (dx.abs() >= dy.abs()) ? 0 : 1;
        }
        var d = (axis == 0) ? dx : dy;
        var lim = span();
        if (d > lim) { d = lim; }
        if (d < -lim) { d = -lim; }
        // Smoothed, because drag events do not arrive one per frame and a
        // single jittery sample should not decide the whole throw.
        velocity = (velocity + (d - offset) * 2) / 3;
        offset = d;
    }

    function dragEnd() as Void {
        if (!dragging) { return; }
        dragging = false;
        _lastDrag = System.getTimer();
        if (axis < 0) { offset = 0; axis = -1; return; }

        var lim = span() / 2;
        if (velocity > lim) { velocity = lim; }
        if (velocity < -lim) { velocity = -lim; }
        launch();
    }

    // How far a free coast would carry, given the release speed. Used to
    // decide the destination *before* moving, never to drive the motion.
    function coastDistance(v as Number) as Number {
        var d = 0;
        var guard = 0;
        while (v.abs() >= FLING_STOP && guard < 60) {
            d += v;
            v = (v * FRICTION_NUM) / FRICTION_DEN;
            if (v > 0) { v -= FRICTION_FLAT; }
            else if (v < 0) { v += FRICTION_FLAT; }
            guard++;
        }
        return d;
    }

    // Pick the screen this throw is going to land on, then drive straight
    // there.
    //
    // Coasting freely and snapping to whatever was nearest at the end meant a
    // throw that almost made it was still moving forward when it decided it
    // had not, and got yanked backwards. Choosing the destination up front and
    // easing into it means the motion never reverses: the only throws that
    // return are ones that never got a quarter of the way, where the move back
    // is small enough not to read as a reversal at all.
    function launch() as Void {
        var sp = span();
        var predicted = offset + coastDistance(velocity);
        var steps = (predicted.abs() + (sp * 3) / 4) / sp;
        var dir = (predicted < 0) ? -1 : 1;
        if (predicted == 0) { dir = (offset < 0) ? -1 : 1; }

        tweenTotal = dir * steps * sp - offset;
        if (tweenTotal == 0) {
            offset = 0;
            axis = -1;
            velocity = 0;
            Theme.flush();
            return;
        }
        tweenDone = 0;
        tweenT = 0;
        var n = tweenTotal.abs() / 24;
        if (n < 5) { n = 5; }
        if (n > 16) { n = 16; }
        tweenFrames = n;
        tweening = true;
    }

    // One game or colour per screen that goes past.
    function stepChange(d as Number) as Void {
        if (axis == 0) { Theme.cycleWall(d); }
        else { switchTo((game + d + COUNT) % COUNT); }
    }

    // Eased out over the whole distance, so it leaves quickly and arrives
    // gently, in one direction throughout.
    function tickTween() as Void {
        tweenT++;
        var n = tweenFrames;
        var inv = n - tweenT;
        var done = (tweenTotal * (n * n - inv * inv)) / (n * n);
        var moved = done - tweenDone;
        tweenDone = done;
        offset += moved;

        var sp = span();
        while (offset <= -sp) { offset += sp; stepChange(1); }
        while (offset >= sp) { offset -= sp; stepChange(-1); }

        if (tweenT < n) { return; }
        tweening = false;
        offset = 0;
        axis = -1;
        velocity = 0;
        Theme.flush();
    }

    // A swipe that arrived as a gesture or a behaviour rather than as drag
    // events. Ignored if a drag just handled the same movement.
    function flick(ax as Number, dir as Number) as Void {
        if (sliding() || System.getTimer() - _lastDrag < 400) { return; }
        axis = ax;
        offset = 0;
        velocity = (dir > 0) ? -40 : 40;
        launch();
    }

    // Games keep their state, so flicking between them resumes rather than
    // restarts. Only a game that has never been shown gets initialised.
    var started = [false, false, false, false, false] as Array<Boolean>;

    // Every game is initialised at boot, not on first visit. A drag shows the
    // neighbouring game live under your finger, so any of them can be drawn at
    // any moment -- and drawing one that had never been reset walked straight
    // into its empty arrays.
    function initAll() as Void {
        var keep = game;
        for (var i = 0; i < COUNT; i++) {
            if (started[i]) { continue; }
            game = i;
            reset();
        }
        game = keep;
    }

    function switchTo(idx as Number) as Void {
        game = idx;
        if (!started[idx]) {
            started[idx] = true;
            reset();
        }
    }

    // What the incoming half of a drag shows.
    function incomingGame() as Number {
        if (axis != 1) { return game; }
        return (game + delta() + COUNT) % COUNT;
    }

    // ---- dispatch ----------------------------------------------------------
    function reset() as Void {
        started[game] = true;
        if (game == PACMAN) { PacGame.newGame(); }
        else if (game == INVADERS) { Invaders.reset(); }
        else if (game == BRICKS) { Bricks.reset(); }
        else if (game == ROCKS) { Rocks.reset(); }
        else { Tempest.reset(); }
    }

    function update() as Void {
        frame++;
        if (infoTimer > 0) {
            infoTimer--;
            Sensors.poll(frame);
        }
        if (dragging) { return; }              // frozen under your finger
        if (tweening) {
            tickTween();
            return;
        }
        if (game == PACMAN) { PacGame.update(); }
        else if (game == INVADERS) { Invaders.update(); }
        else if (game == BRICKS) { Bricks.update(); }
        else if (game == ROCKS) { Rocks.update(); }
        else { Tempest.update(); }
    }

    // Is the big time-and-date panel up? Every game raises it between lives,
    // which is the whole conceit: the arcade's READY! is the clock.
    function showingClock() as Boolean {
        if (game == PACMAN) { return PacGame.showingClock(); }
        if (game == INVADERS) { return Invaders.showingClock(); }
        if (game == BRICKS) { return Bricks.showingClock(); }
        if (game == ROCKS) { return Rocks.showingClock(); }
        return Tempest.showingClock();
    }

    function skipDwell() as Void {
        if (game == PACMAN) { PacGame.skipDwell(); }
        else if (game == INVADERS) { Invaders.skipDwell(); }
        else if (game == BRICKS) { Bricks.skipDwell(); }
        else if (game == ROCKS) { Rocks.skipDwell(); }
        else { Tempest.skipDwell(); }
    }

    function lives() as Number {
        if (game == PACMAN) { return PacGame.lives; }
        if (game == INVADERS) { return Invaders.lives; }
        if (game == BRICKS) { return Bricks.lives; }
        if (game == ROCKS) { return Rocks.lives; }
        return Tempest.lives;
    }

    function level() as Number {
        if (game == PACMAN) { return PacGame.level; }
        if (game == INVADERS) { return Invaders.level; }
        if (game == BRICKS) { return Bricks.level; }
        if (game == ROCKS) { return Rocks.level; }
        return Tempest.level;
    }

    // Only Pac-Man streams a trace; the other games have not needed one.
    function trace() as Void {
        if (game == PACMAN) { PacGame.trace(); }
    }

    // Only Pac-Man keeps a static layer worth caching; the others are cheap
    // enough to draw outright every frame.
    function usesBuffer() as Boolean { return game == PACMAN; }
}
