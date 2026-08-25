import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// The whole simulation. Nobody plays: Pac-Man and the ghosts run
// themselves forever, and the clock rides along on top.
module Game {

    const READY = 0; const PLAY = 1; const DYING = 2;
    const LEVEL_DONE = 3; const GAME_OVER = 4;

    const FPS = 15;
    const READY_FRAMES     = 4 * FPS;    // the dwell we settled on
    const FIRST_READY      = 4 * FPS;
    const DEATH_FRAMES     = 26;
    const LEVEL_FRAMES     = 30;
    const GAME_OVER_FRAMES = 5 * FPS;
    const EAT_PAUSE        = 6;          // freeze-frame when a ghost is eaten
    const INFO_FRAMES      = 5 * FPS;    // how long a tap keeps the read-outs up

    // scatter / chase / scatter / chase / ... in frames, then chase forever
    const MODE_PLAN = [7 * FPS, 20 * FPS, 7 * FPS, 20 * FPS,
                       5 * FPS, 20 * FPS, 5 * FPS] as Array<Number>;

    var pac as Pac = new Pac();
    var ghosts as Array<Ghost> = [new Ghost(0), new Ghost(1),
                                  new Ghost(2), new Ghost(3)] as Array<Ghost>;

    var state as Number = 0;
    var timer as Number = 0;
    var level as Number = 1;
    var lives as Number = 3;
    var frame as Number = 0;

    var modeIndex as Number = 0;
    var modeTimer as Number = 0;
    var frightTimer as Number = 0;
    var eatPause as Number = 0;
    var mazeDirty as Boolean = true;     // view must rebuild its whole buffer

    // Tap-to-peek. The heart and Body Battery are hidden while the game runs,
    // so the face stays pure arcade; a tap brings them up along with the big
    // clock for five seconds and then gets out of the way again. The game
    // keeps running underneath -- there is nothing to freeze, and Pac-Man
    // carrying on around the panel is half the charm.
    var infoTimer as Number = 0;

    function showInfo() as Void {
        Sensors.reset();          // always a fresh reading on tap
        infoTimer = INFO_FRAMES;
    }
    function hideInfo() as Void { infoTimer = 0; }
    function showingInfo() as Boolean { return infoTimer > 0; }

    // Swipe-to-recolour slides the whole screen off and the new one on.
    // The simulation is frozen for the duration so both halves show the same
    // instant -- otherwise Pac-Man visibly teleports between the two copies.
    const SLIDE_FRAMES = 10;
    var slideStep as Number = 0;
    var slideDir  as Number = 0;         // +1 new content enters from right/bottom
    var slideAxis as Number = 0;         // 0 horizontal, 1 vertical
    var slideArmed as Boolean = false;   // view still has to paint the new buffer

    function startSlide(axis as Number, dir as Number) as Void {
        if (slideStep > 0) { return; }   // already mid-swipe; ignore
        Theme.cycleWall();
        slideAxis = axis;
        slideDir = dir;
        slideStep = SLIDE_FRAMES;
        slideArmed = true;
    }

    // 0..100, eased out so it leaves fast and settles gently.
    function slideProgress() as Number {
        var t = SLIDE_FRAMES - slideStep;
        var p = (t * 100) / SLIDE_FRAMES;
        var inv = 100 - p;
        return 100 - (inv * inv) / 100;
    }
    // A single eaten tile the view should punch out of its buffer. Pac-Man
    // can clear at most one tile per frame, so one slot is always enough.
    var lastEatC as Number = -1;
    var lastEatR as Number = -1;

    function modeNow() as Number {
        return (modeIndex % 2 == 0) ? GhostMode.SCATTER : GhostMode.CHASE;
    }

    function frightFrames() as Number {
        var f = 6 * FPS - (level - 1) * 12;
        return (f < FPS) ? FPS : f;
    }

    function ghostSpeed() as Number {
        var s = 5 + (level - 1);
        return (s > 7) ? 7 : s;
    }

    // Math.rand() starts from the same state every launch, so without this
    // the "random" bits below replay identically each time the app opens.
    function seedRandom() as Void {
        var t = Time.now().value();
        Math.srand(t + System.getTimer());
    }

    // +/- `spread` frames, so the ghost schedule never lands the same way twice.
    function jitter(base as Number, spread as Number) as Number {
        var v = base - spread + (Math.rand() % (2 * spread + 1));
        return (v < 1) ? 1 : v;
    }

    function newGame() as Void {
        seedRandom();
        Nav.init();
        level = 1;
        lives = 3;
        startLevel();
    }

    function startLevel() as Void {
        Maze.reset();
        mazeDirty = true;
        resetActors();
        state = READY;
        timer = FIRST_READY;
    }

    function resetActors() as Void {
        pac.respawn();
        modeIndex = 0;
        modeTimer = jitter(MODE_PLAN[0], FPS);
        frightTimer = 0;
        eatPause = 0;
        var m = modeNow();
        for (var i = 0; i < 4; i++) {
            // Staggered releases, jittered: which ghost is where when Pac-Man
            // reaches a junction is most of what makes a game feel different.
            var rel = (i < 2) ? 0 : jitter(i * 4 * FPS - 4 * FPS, FPS);
            ghosts[i].respawn(m, rel);
        }
    }

    // Flip on to stream the real simulation out of the simulator so it can
    // be replayed and rendered offline. Off for shipping builds.
    const TRACE = false;

    function trace() as Void {
        var s = "T|" + frame + "|" + state + "|" + pac.tx + "," + pac.ty + ","
                + pac.dir + "," + pac.prog + "," + pac.deathFrame;
        for (var i = 0; i < 4; i++) {
            var g = ghosts[i];
            s += "|" + g.tx + "," + g.ty + "," + g.dir + "," + g.prog + ","
                 + g.mode + "," + g.state;
        }
        s += "|" + lastEatC + "," + lastEatR + "|" + Nav.lastCost + "," + Nav.floods
             + "|" + frightTimer + "|" + lives + "|" + level;
        if (frame % 150 == 0) {
            s += "|mem=" + System.getSystemStats().usedMemory;
        }
        System.println(s);
    }

    function update() as Void {
        frame++;
        // Only worth reading the sensors while they are on screen.
        if (infoTimer > 0) {
            infoTimer--;
            Sensors.poll(frame);
        }

        if (slideStep > 0) {
            slideStep--;
            return;                      // frozen while the screen moves
        }

        if (state == READY) {
            timer--;
            if (timer <= 0) { state = PLAY; }
            return;
        }
        if (state == DYING) {
            timer--;
            pac.deathFrame++;
            if (timer <= 0) {
                lives--;
                if (lives <= 0) {
                    state = GAME_OVER;
                    timer = GAME_OVER_FRAMES;
                } else {
                    resetActors();
                    state = READY;
                    timer = READY_FRAMES;
                }
            }
            return;
        }
        if (state == LEVEL_DONE) {
            timer--;
            if (timer <= 0) {
                level++;
                startLevel();
            }
            return;
        }
        if (state == GAME_OVER) {
            timer--;
            if (timer <= 0) { newGame(); }
            return;
        }

        // ---- PLAY ----
        if (eatPause > 0) { eatPause--; return; }

        // Ghost mode schedule. Frightened time doesn't count against it.
        if (frightTimer > 0) {
            frightTimer--;
            if (frightTimer == 0) {
                for (var i = 0; i < 4; i++) { ghosts[i].setMode(modeNow()); }
            }
        } else if (modeIndex < MODE_PLAN.size()) {
            modeTimer--;
            if (modeTimer <= 0) {
                modeIndex++;
                if (modeIndex < MODE_PLAN.size()) {
                    modeTimer = jitter(MODE_PLAN[modeIndex], FPS);
                }
                var m = modeNow();
                for (var i = 0; i < 4; i++) {
                    ghosts[i].setMode(m);
                    ghosts[i].forceReverse();
                }
            }
        }

        pac.update(6);

        var got = Maze.eat(pac.tx, pac.ty);
        if (got == 2) {
            frightTimer = frightFrames();
            for (var i = 0; i < 4; i++) {
                ghosts[i].setMode(GhostMode.FRIGHT);
                ghosts[i].forceReverse();
            }
        }
        if (got != 0) { lastEatC = pac.tx; lastEatR = pac.ty; }

        var gs = ghostSpeed();
        for (var i = 0; i < 4; i++) {
            ghosts[i].update(gs, 3, 12, 3);
        }

        checkCollisions();

        if (Maze.dotsLeft <= 0) {
            state = LEVEL_DONE;
            timer = LEVEL_FRAMES;
        }
    }

    function checkCollisions() as Void {
        var px = pac.pixX();
        var py = pac.pixY();
        var hit = (Layout.cell * 6) / 10;
        hit = hit * hit;
        for (var i = 0; i < 4; i++) {
            var g = ghosts[i];
            if (g.inHouse() || g.isEyes()) { continue; }
            var dx = px - g.pixX();
            var dy = py - g.pixY();
            if (dx * dx + dy * dy > hit) { continue; }
            if (g.isEdible()) {
                g.getEaten();
                eatPause = EAT_PAUSE;
            } else if (g.isDangerous()) {
                pac.dying = true;
                pac.deathFrame = 0;
                state = DYING;
                timer = DEATH_FRAMES;
                return;
            }
        }
    }

    // The big centre panel is up whenever the game isn't actually running.
    function showingClock() as Boolean {
        return state == READY || state == GAME_OVER;
    }

    // Ghosts flash white for the last two seconds of a power pellet.
    function frightFlashing() as Boolean {
        return frightTimer > 0 && frightTimer < 2 * FPS && (frame / 3) % 2 == 0;
    }
}
