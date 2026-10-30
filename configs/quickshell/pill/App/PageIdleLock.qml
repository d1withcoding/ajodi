import QtQuick
import Quickshell
import Quickshell.Io
import "../Singletons"

AppPage {
    id: page
    pageId: "idlelock"

    readonly property string confPath: Quickshell.env("HOME") + "/.config/niri/swayidle.conf"
    readonly property string lockScript: Quickshell.env("HOME") + "/.config/niri/scripts/lock.sh"

    readonly property var lockOptions: [0, 1, 3, 5, 10, 15]
    readonly property var screenOptions: [0, 3, 5, 10, 15]
    readonly property var suspendOptions: [0, 15, 30, 60]

    function optionsFor(list, current) {
        const vals = list.indexOf(current) >= 0 || !(current > 0) ? list : list.concat([current]).sort((a, b) => a - b);
        return vals.map(v => ({ label: v === 0 ? "Off" : String(v), value: v }));
    }

    function buildConf() {
        let out = "# swayidle configuration for niri (Ajodi)\n"
            + "before-sleep 'loginctl lock-session'\n"
            + "after-resume 'niri msg action power-on-monitors'\n";

        if (Flags.idleLockMin > 0)
            out += "timeout " + (Flags.idleLockMin * 60) + " '" + page.lockScript + "'\n";

        if (Flags.idleScreenOffMin > 0)
            out += "timeout " + (Flags.idleScreenOffMin * 60) + " 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors'\n";

        if (Flags.idleSuspendMin > 0)
            out += "timeout " + (Flags.idleSuspendMin * 60) + " 'systemctl suspend'\n";

        return out;
    }

    function apply() {
        confWriter.setText(buildConf());
        restartProc.running = true;
    }

    function reset() {
        Flags.idleLockMin = 5;
        Flags.idleScreenOffMin = 6;
        Flags.idleSuspendMin = 0;
        Flags.lockUseFont = true;
        Flags.lockSeconds = false;
        apply();
    }

    FileView {
        id: confWriter
        path: page.confPath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: restartProc
        command: ["systemctl", "--user", "restart", "swayidle"]
    }

    AppGroup {
        title: "Screen lock"
        desc: "When the screen should lock and dim."

        SettingsSeg {
            label: "Lock after"
            desc: "Minutes before locking the desktop."
            options: page.optionsFor(page.lockOptions, Flags.idleLockMin)
            current: Flags.idleLockMin
            onChosen: v => { Flags.idleLockMin = v; page.apply(); }
        }

        SettingsSeg {
            label: "Turn off screen"
            desc: "Minutes before powering off the monitor."
            options: page.optionsFor(page.screenOptions, Flags.idleScreenOffMin)
            current: Flags.idleScreenOffMin
            onChosen: v => { Flags.idleScreenOffMin = v; page.apply(); }
        }

        SettingsSeg {
            label: "Suspend after"
            desc: "Minutes before system suspend."
            options: page.optionsFor(page.suspendOptions, Flags.idleSuspendMin)
            current: Flags.idleSuspendMin
            onChosen: v => { Flags.idleSuspendMin = v; page.apply(); }
        }
    }
}
