import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Pac-Man plays himself. One flood from his tile per tile-centre gives
// nearest dot, nearest pellet, and the true corridor distance to every
// ghost; a second flood -- only when something is actually chasing him --
// gives the escape map.
class Pac extends Actor {

    var mouth as Number = 0;         // animation phase
    // The dot he is currently heading for. Sticking to a choice until it is
    // gone is what stops the random pick below turning into dithering at
    // every junction.
    var goal as Number = -1;
    var dying as Boolean = false;
    var deathFrame as Number = 0;

    // How close a ghost must get before he stops thinking about dinner.
    const PANIC   = 7;
    const HUNT_R  = 12;
    const PELLET_R = 9;

    function initialize() {
        Actor.initialize();
        ghostRules = false;
    }

    function respawn() as Void {
        place(13, 23, Maze.LEFT);
        goal = -1;
        dying = false;
        deathFrame = 0;
        mouth = 0;
    }

    // Radius caps. Almost always there is a dot within a few tiles, so the
    // first flood is deliberately short; the expensive full-board sweep only
    // runs when the near one comes back empty, which is the tail end of a
    // level. The escape map only ever cares about what is breathing down his
    // neck, so it stays small always.
    const NEAR_R   = 16;
    const FOOD_R   = 44;
    const DANGER_R = 12;

    // Is a ghost bearing down the corridor we're already in? Pure tile
    // arithmetic -- no flood -- so it's safe to ask every arrival.
    function pressedFromAhead() as Boolean {
        var fx = Maze.DX[dir];
        var fy = Maze.DY[dir];
        var g = Game.ghosts;
        for (var i = 0; i < 4; i++) {
            if (!g[i].isDangerous()) { continue; }
            var dx = g[i].tx - tx;
            var dy = g[i].ty - ty;
            if (fx != 0) {
                if (dy != 0 || dx * fx <= 0 || dx * fx > 5) { continue; }
            } else {
                if (dx != 0 || dy * fy <= 0 || dy * fy > 5) { continue; }
            }
            return true;
        }
        return false;
    }

    function onArrive() as Void {
        // Most of a Pac-Man maze is corridor, not junction, and in a corridor
        // there is nothing to decide. Skipping the flood there cut the worst
        // frame from 62 ms to well inside the 66 ms budget -- and it's what
        // the arcade does anyway: actors only choose at intersections.
        var back = reverse();
        var only = -1;
        var n = 0;
        for (var d = 0; d < 4; d++) {
            if (d != back && canGo(d)) { only = d; n++; }
        }
        if (n == 0) { dir = back; return; }
        if (n == 1 && !pressedFromAhead()) { dir = only; return; }

        var t0 = System.getTimer();
        Nav.flood(tx, ty, MazeData.BLOCK_P, Nav.dist, Nav.firstDir, true, NEAR_R);
        if (Nav.nearDot < 0 && Nav.nearPower < 0) {
            Nav.flood(tx, ty, MazeData.BLOCK_P, Nav.dist, Nav.firstDir, true, FOOD_R);
        }

        var g = Game.ghosts;
        var threat = 9999;
        var threatC = -1;
        var threatR = -1;
        var hunt = -1;
        var huntD = 9999;

        for (var i = 0; i < 4; i++) {
            var idx = g[i].ty * MazeData.COLS + g[i].tx;
            if (!Nav.valid(idx)) { continue; }    // in the house, or out of range
            var d = Nav.dist[idx];
            if (g[i].isEdible()) {
                if (d < huntD) { huntD = d; hunt = idx; }
            } else if (g[i].isDangerous()) {
                if (d < threat) { threat = d; threatC = g[i].tx; threatR = g[i].ty; }
            }
        }

        // Pick something to walk at.
        var target = -1;
        if (hunt >= 0 && huntD <= HUNT_R) {
            target = hunt;                                    // dessert
        } else if (threat <= PANIC && Nav.nearPower >= 0
                   && Nav.dist[Nav.nearPower] <= PELLET_R) {
            target = Nav.nearPower;                           // cornered: arm up
        } else if (Nav.nearDot >= 0) {
            target = pickFood();
        } else if (Nav.nearPower >= 0) {
            target = Nav.nearPower;
        }

        var pref = dir;
        if (target >= 0 && Nav.firstDir[target] >= 0) {
            pref = Nav.firstDir[target];
        }

        // Nothing near enough to matter: just go eat.
        if (threat > PANIC || threatC < 0) {
            dir = canGo(pref) ? pref : firstLegal(pref);
            Nav.lastCost = System.getTimer() - t0;
            return;
        }

        // Something is on him. Map the danger and weigh each way out.
        Nav.flood(threatC, threatR, MazeData.BLOCK_G, Nav.gdist, null, false, DANGER_R);
        var best = -1;
        var bestScore = -999999;
        for (var d = 0; d < 4; d++) {
            if (!canGo(d)) { continue; }
            var ni = (ty + Maze.DY[d]) * MazeData.COLS
                   + Maze.wrapCol(tx + Maze.DX[d]);
            var away = Nav.valid(ni) ? Nav.gdist[ni] : 30;
            if (away <= 1) { continue; }          // that is its mouth
            var s = away * 10;
            if (d == pref) { s += 25; }           // still nudge toward food
            if (d == back) { s -= 12; }           // dithering looks stupid
            if (s > bestScore) { bestScore = s; best = d; }
        }
        dir = (best >= 0) ? best : firstLegal(pref);
        Nav.lastCost = System.getTimer() - t0;
    }

    // Keep walking at the same dot until it is eaten or drops out of range;
    // otherwise choose freshly at random from the near candidates. Without the
    // randomness every game replays identically, which is the whole point of
    // this; without the stickiness he oscillates between two dots.
    function pickFood() as Number {
        if (goal >= 0 && Nav.valid(goal)) {
            var gr = goal / MazeData.COLS;
            var gc = goal % MazeData.COLS;
            if ((Maze.dots[gr] & (1 << gc)) != 0) { return goal; }
        }
        goal = (Nav.candN > 0)
             ? Nav.cand[Math.rand() % Nav.candN]
             : Nav.nearDot;
        return goal;
    }

    function firstLegal(pref as Number) as Number {
        if (canGo(pref)) { return pref; }
        var back = reverse();
        for (var d = 0; d < 4; d++) {
            if (d != back && canGo(d)) { return d; }
        }
        return canGo(back) ? back : dir;
    }

    function update(spd as Number) as Void {
        advance(spd);
        mouth = (mouth + 1) % 12;
    }

    // 0 = shut, 1..3 = progressively wider
    function mouthOpen() as Number {
        var m = mouth / 3;
        return (m == 3) ? 1 : m;
    }
}
