import Toybox.Lang;
import Toybox.System;
import Toybox.Activity;
import Toybox.ActivityMonitor;

// Heart rate and Body Battery, cached as ready-to-draw strings.
//
// Probed on the device profile before writing this: `Activity.currentHeartRate`
// is null outside a recorded activity, so the reliable source is the newest
// sample of ActivityMonitor's HR history. Body Battery is *not* listed in the
// vivoactive 5's sensorHistory profile (which advertises only heartrate and
// pulseox) yet getBodyBatteryHistory does answer -- so it is called behind
// `has` guards and degrades to "--" rather than assuming it works.
//
// Three characters max, always: that is what fits inside the icons, which is
// also why there is no "%" on the Body Battery figure.
module Sensors {
    const POLL_FRAMES = 30;      // 2 s at 15 fps; neither value moves faster

    var hr as String = "--";
    var bb as String = "--";
    var _next as Number = 0;

    function poll(frame as Number) as Void {
        if (frame < _next) { return; }
        _next = frame + POLL_FRAMES;
        hr = readHr();
        bb = readBodyBattery();
    }

    function reset() as Void { _next = 0; }

    // Read now, so the first frame of a peek shows live values rather than
    // whatever was cached when it was last on screen.
    function refresh(frame as Number) as Void {
        _next = 0;
        poll(frame);
    }

    function clamp3(v as Number) as String {
        if (v < 0) { return "--"; }
        if (v > 999) { return "999"; }
        return v.format("%d");
    }

    function readHr() as String {
        try {
            var a = Activity.getActivityInfo();
            if (a != null && a.currentHeartRate != null) {
                return clamp3(a.currentHeartRate as Number);
            }
        } catch (e) {}
        try {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            if (it != null) {
                var s = it.next();
                if (s != null && s.heartRate != null
                        && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return clamp3(s.heartRate as Number);
                }
            }
        } catch (e) {}
        return "--";
    }

    // Body Battery, with the reason it failed encoded in the read-out.
    //
    // The tiny font is digits and a minus only, so the codes are numeric:
    //   -1  this device has no SensorHistory module at all
    //   -2  it has one, but no getBodyBatteryHistory
    //   -4  the iterator ran dry, or every sample was empty
    //   -5  it threw
    // A bare "--" now means only "not polled yet". Worth keeping: the device
    // profile does not advertise Body Battery even though the call answers in
    // the simulator, so what a real watch does here is genuinely unknown.
    function readBodyBattery() as String {
        if (!(Toybox has :SensorHistory)) { return "-1"; }
        if (!(Toybox.SensorHistory has :getBodyBatteryHistory)) { return "-2"; }
        try {
            // Newest first, and scan past empty samples rather than giving up
            // on the first one -- the most recent slot is often still empty.
            var it = Toybox.SensorHistory.getBodyBatteryHistory({
                :period => 8,
                :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST
            });
            var s = it.next();
            var tries = 0;
            while (s != null && tries < 8) {
                if (s.data != null) {
                    return clamp3((s.data as Float).toNumber());
                }
                s = it.next();
                tries++;
            }
            return "-4";
        } catch (e) {
            return "-5";
        }
    }
}
