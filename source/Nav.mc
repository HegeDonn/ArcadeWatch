import Toybox.Lang;

// One breadth-first flood answers every question Pac-Man's AI has: where is
// the nearest pellet, and how far is each ghost *through the corridors*
// rather than as the crow flies.
//
// This is the hottest code in the app and the first version tripped the
// watchdog, so three things matter here:
//   * visited is a stamp compare, not a 868-entry array we clear each call;
//   * "can I step here" is one masked shift against a pre-OR'd row;
//   * the direction loop is unrolled, because DX[d]/DY[d] lookups aren't free.
module Nav {
    const N = MazeData.COLS * MazeData.ROWS;
    const C = MazeData.COLS;

    var dist     = new [N];
    var firstDir = new [N];
    var gdist    = new [N];
    var queue    = new [N];
    var seen     = new [N];
    var stamp as Number = 0;

    // A handful of near-dot candidates rather than only the closest, so
    // Pac-Man has something to choose between and every game routes
    // differently.
    const CAND_MAX  = 4;
    const CAND_SLOP = 3;          // tiles worse than the best we'll still take
    var cand = new [4];
    var candN as Number = 0;

    var nearDot   as Number = -1;
    var nearPower as Number = -1;
    var lastCost  as Number = 0;    // ms, for the on-watch budget check
    var floods    as Number = 0;    // trace-only: how often we actually think

    function init() as Void {
        for (var i = 0; i < N; i++) { seen[i] = 0; }
        stamp = 0;
    }

    function valid(i as Number) as Boolean { return seen[i] == stamp; }

    function flood(sc as Number, sr as Number, block, outDist, outFirst,
                   track as Boolean, maxD as Number) as Void {
        stamp++;
        floods++;
        var st = stamp;
        var sk = seen;
        var q = queue;
        var head = 0;
        var tail = 1;
        var start = sr * C + sc;

        sk[start] = st;
        outDist[start] = 0;
        if (outFirst != null) { outFirst[start] = -1; }
        q[0] = start;

        if (track) { nearDot = -1; nearPower = -1; candN = 0; }

        while (head < tail) {
            var idx = q[head];
            head++;
            var d0 = outDist[idx];
            var r = idx / C;
            var c = idx - r * C;

            if (track && d0 > 0) {
                var bit = 1 << c;
                if ((Maze.dots[r] & bit) != 0) {
                    // BFS order means the first one found is the nearest.
                    if (nearDot < 0) { nearDot = idx; }
                    if (candN < CAND_MAX && d0 <= outDist[nearDot] + CAND_SLOP) {
                        cand[candN] = idx;
                        candN++;
                    }
                }
                if (nearPower < 0 && (Maze.power[r] & bit) != 0) { nearPower = idx; }
            }
            if (d0 >= maxD) { continue; }

            var nd = d0 + 1;
            var fd = (outFirst != null) ? outFirst[idx] : 0;
            var ni;

            // UP
            if (r > 0 && ((block[r - 1] >> c) & 1) == 0) {
                ni = idx - C;
                if (sk[ni] != st) {
                    sk[ni] = st; outDist[ni] = nd;
                    if (outFirst != null) { outFirst[ni] = (d0 == 0) ? Maze.UP : fd; }
                    q[tail] = ni; tail++;
                }
            }
            // LEFT (wraps through the tunnel)
            var lc = (c == 0) ? C - 1 : c - 1;
            if (((block[r] >> lc) & 1) == 0) {
                ni = r * C + lc;
                if (sk[ni] != st) {
                    sk[ni] = st; outDist[ni] = nd;
                    if (outFirst != null) { outFirst[ni] = (d0 == 0) ? Maze.LEFT : fd; }
                    q[tail] = ni; tail++;
                }
            }
            // DOWN
            if (r < MazeData.ROWS - 1 && ((block[r + 1] >> c) & 1) == 0) {
                ni = idx + C;
                if (sk[ni] != st) {
                    sk[ni] = st; outDist[ni] = nd;
                    if (outFirst != null) { outFirst[ni] = (d0 == 0) ? Maze.DOWN : fd; }
                    q[tail] = ni; tail++;
                }
            }
            // RIGHT (wraps through the tunnel)
            var rc = (c == C - 1) ? 0 : c + 1;
            if (((block[r] >> rc) & 1) == 0) {
                ni = r * C + rc;
                if (sk[ni] != st) {
                    sk[ni] = st; outDist[ni] = nd;
                    if (outFirst != null) { outFirst[ni] = (d0 == 0) ? Maze.RIGHT : fd; }
                    q[tail] = ni; tail++;
                }
            }
        }
    }
}
