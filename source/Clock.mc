import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The whole point of the watch part.
//
// NOTE: Gregorian.info(..., FORMAT_MEDIUM) hands back day_of_week and month
// as *localized Strings*; calling .format() on those threw "Not Enough
// Arguments" and crashed this app on launch. FORMAT_SHORT is
// all-numeric, so we index our own name tables instead.
module Clock {
    const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;
    const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"] as Array<String>;

    function timeStr() as String {
        var t = System.getClockTime();
        var h = t.hour;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return h.format("%02d") + ":" + t.min.format("%02d");
    }

    function dateStr() as String {
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dow = g.day_of_week;          // 1 = Sunday
        var mon = g.month;                // 1 = January
        var d = (dow instanceof Lang.Number && dow >= 1 && dow <= 7)
                ? DAYS[dow - 1] : "";
        var m = (mon instanceof Lang.Number && mon >= 1 && mon <= 12)
                ? MONTHS[mon - 1] : "";
        return d + " " + g.day.format("%d") + " " + m;
    }
}
