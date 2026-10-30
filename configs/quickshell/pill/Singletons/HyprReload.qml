pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Debounced reload for niri configuration.
 */
Singleton {
    id: root

    property bool failed: false

    function request() {
        timer.restart();
    }

    Timer {
        id: timer
        interval: 250
        onTriggered: {
            if (proc.running)
                restart();
            else
                proc.running = true;
        }
    }

    Process {
        id: proc
        command: ["niri", "msg", "action", "load-config-file"]
        onExited: function (exitCode) {
            root.failed = exitCode !== 0;
            if (GameMode.active)
                GameMode.run("on");
        }
    }
}
