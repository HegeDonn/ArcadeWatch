import Toybox.Lang;

// Integer sine and cosine on a 64-step circle, scaled by 256.
//
// Shared by the two games that need to rotate things. The vivoactive 5 has no
// vector rotation, so anything angled is worked out by hand -- and doing it
// with a table of Numbers keeps the per-frame maths off the floating-point
// path entirely.
module Trig {
    const TURN = 64;

    // sin(i/64 turn) * 256 for the first quarter; the rest is mirrored.
    const Q = [0, 25, 49, 74, 97, 120, 142, 162, 181, 198, 213, 226,
               237, 245, 251, 255, 256] as Array<Number>;

    function sin(a as Number) as Number {
        a = ((a % TURN) + TURN) % TURN;
        if (a <= 16) { return Q[a]; }
        if (a <= 32) { return Q[32 - a]; }
        if (a <= 48) { return -Q[a - 32]; }
        return -Q[64 - a];
    }

    function cos(a as Number) as Number { return sin(a + 16); }
}
