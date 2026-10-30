pragma Singleton
import QtQuick
import Quickshell
import "Singletons"

/**
 * Workspace to monitor map (stubbed for niri).
 */
Singleton {
    id: root

    property var byMonitor: ({})

    function refresh() {}
}
