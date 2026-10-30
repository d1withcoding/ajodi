pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Niri IPC adapter and event stream listener for Quickshell.
 * Replaces Quickshell.Hyprland with a reactive, event-driven interface to niri.
 */
Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property var outputs: []
    property var focusedOutput: null
    property var focusedWorkspace: null
    property var focusedWindow: null
    property int focusedWorkspaceId: 1
    property string focusedOutputName: ""

    signal rawEvent(var event)

    function action(cmd: string) {
        if (!cmd || cmd.length === 0)
            return;
        Quickshell.execDetached(["sh", "-c", "niri msg action " + cmd]);
    }

    function dispatch(cmd: string) {
        action(cmd);
    }

    function refresh() {
        if (!queryOutputs.running)
            queryOutputs.running = true;
        if (!queryWorkspaces.running)
            queryWorkspaces.running = true;
        if (!queryWindows.running)
            queryWindows.running = true;
    }

    function outputForScreen(screen) {
        if (!screen)
            return null;
        for (var i = 0; i < root.outputs.length; i++) {
            if (root.outputs[i].name === screen.name)
                return root.outputs[i];
        }
        return null;
    }

    // Refresh outputs from niri
    Process {
        id: queryOutputs
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    var list = [];
                    if (Array.isArray(parsed)) {
                        list = parsed;
                    } else if (typeof parsed === "object" && parsed !== null) {
                        for (var k in parsed) {
                            var item = parsed[k];
                            item.name = k;
                            list.push(item);
                        }
                    }
                    root.outputs = list;
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].logical && list[i].logical.is_focused) {
                            root.focusedOutput = list[i];
                            root.focusedOutputName = list[i].name;
                            break;
                        }
                    }
                } catch (e) {}
            }
        }
    }

    // Refresh workspaces from niri
    Process {
        id: queryWorkspaces
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed)) {
                        root.workspaces = parsed;
                        for (var i = 0; i < parsed.length; i++) {
                            if (parsed[i].is_focused) {
                                root.focusedWorkspace = parsed[i];
                                root.focusedWorkspaceId = parsed[i].id || parsed[i].idx || 1;
                                break;
                            }
                        }
                    }
                } catch (e) {}
            }
        }
    }

    // Refresh windows from niri
    Process {
        id: queryWindows
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed)) {
                        root.windows = parsed;
                        for (var i = 0; i < parsed.length; i++) {
                            if (parsed[i].is_focused) {
                                root.focusedWindow = parsed[i];
                                break;
                            }
                        }
                    }
                } catch (e) {}
            }
        }
    }

    // Event stream process
    Process {
        id: eventStream
        command: ["niri", "msg", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim().length === 0)
                    return;
                try {
                    var ev = JSON.parse(line.trim());
                    root.rawEvent(ev);

                    if (ev.WorkspacesChanged) {
                        root.workspaces = ev.WorkspacesChanged.workspaces || [];
                    } else if (ev.WorkspaceActivated) {
                        root.focusedWorkspaceId = ev.WorkspaceActivated.id;
                        for (var i = 0; i < root.workspaces.length; i++) {
                            if (root.workspaces[i].id === ev.WorkspaceActivated.id) {
                                root.focusedWorkspace = root.workspaces[i];
                                break;
                            }
                        }
                    } else if (ev.WindowsChanged) {
                        root.windows = ev.WindowsChanged.windows || [];
                    } else if (ev.WindowFocusChanged) {
                        for (var j = 0; j < root.windows.length; j++) {
                            if (root.windows[j].id === ev.WindowFocusChanged.id) {
                                root.focusedWindow = root.windows[j];
                                break;
                            }
                        }
                    } else {
                        // Periodic debounce refresh on other events
                        refreshTimer.restart();
                    }
                } catch (e) {}
            }
        }
        onExited: restartTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 150
        onTriggered: root.refresh()
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: eventStream.running = true
    }

    Component.onCompleted: refresh()
}

