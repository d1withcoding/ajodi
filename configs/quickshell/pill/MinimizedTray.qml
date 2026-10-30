pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

/**
 * Icons for windows parked on the "minimized" workspace; a click brings one back to the active workspace.
 */
Row {
    id: root

    property real s: 1
    property string screenName: ""
    spacing: 8 * s

    function restoreWorkspace() {
        return Niri.focusedWorkspaceId || 1;
    }

    readonly property var items: {
        var out = [];
        var wins = Niri.windows || [];
        var minWs = (Niri.workspaces || []).find(w => w.name === "minimized");
        var minId = minWs ? minWs.id : -999;
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (w && (w.workspace_id === minId || w.workspace_name === "minimized"))
                out.push(w);
        }
        return out;
    }
    readonly property int count: items.length

    function iconFor(t) {
        var cls = t && t.app_id ? t.app_id : "";
        if (!cls)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (e && e.id && e.id.toLowerCase() === cls.toLowerCase() && e.icon)
                return Quickshell.iconPath(e.icon, "application-x-executable");
        }
        return Quickshell.iconPath(cls, "application-x-executable");
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: chip
            required property var modelData
            width: 18 * root.s
            height: 18 * root.s

            readonly property string iconSrc: root.iconFor(chip.modelData)

            Image {
                anchors.fill: parent
                sourceSize.width: Math.round(36 * root.s)
                sourceSize.height: Math.round(36 * root.s)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: chip.iconSrc
                opacity: area.containsMouse ? 1 : 0.78
                scale: area.pressed && !Motion.calm ? 0.9 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var targetWs = root.restoreWorkspace();
                    Niri.action("focus-window --id " + chip.modelData.id);
                    Niri.action("move-window-to-workspace " + targetWs);
                }
            }

            Tooltip {
                s: root.s
                placement: "below"
                title: chip.modelData.title || ""
                show: area.containsMouse
            }
        }
    }
}
