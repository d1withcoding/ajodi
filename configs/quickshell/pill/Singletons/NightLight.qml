pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Night-light controller over wlsunset.
 */
Singleton {
    id: root

    function clampTemp(t) {
        return Math.max(2200, Math.min(6000, Math.round(t)));
    }

    function nowMin() {
        var d = clock.date;
        return d.getHours() * 60 + d.getMinutes();
    }

    function windowOpen() {
        var on = Flags.nightLightOnMin;
        var off = Flags.nightLightOffMin;
        var n = root.nowMin();
        return on <= off ? (n >= on && n < off) : (n >= on || n < off);
    }

    function pushLive() {
        var warm = Flags.nightLightMode === "on"
            || (Flags.nightLightMode === "scheduled" && root.windowOpen());
        if (warm) {
            applyProc.command = ["sh", "-c", "pkill -x wlsunset; setsid -f wlsunset -t " + root.clampTemp(Flags.nightLightTemp) + " >/dev/null 2>&1"];
        } else {
            applyProc.command = ["pkill", "-x", "wlsunset"];
        }
        applyProc.running = true;
    }

    function commit(restart) {
        root.pushLive();
    }

    function setMode(m) {
        Flags.nightLightMode = m;
        root.commit(true);
    }

    function setTemp(t) {
        Flags.nightLightTemp = root.clampTemp(t);
        root.commit(Flags.nightLightMode !== "off");
    }

    function setOnMin(v) {
        Flags.nightLightOnMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    function setOffMin(v) {
        Flags.nightLightOffMin = v;
        root.commit(Flags.nightLightMode === "scheduled");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: if (Flags.nightLightMode === "scheduled") root.pushLive()
    }

    Process {
        id: applyProc
    }

    Component.onCompleted: root.pushLive()
}
