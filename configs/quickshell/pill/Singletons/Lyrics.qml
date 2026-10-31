pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live synchronized lyrics tracker for the Quickshell Pill.
 * Interoperates with local .lrc files in ~/Music, ~/.cache/lyrics, and LRCLIB.
 * Exposes current line in real-time synced to playback position.
 */
Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.config/niri/scripts/lyrics.py"

    property var lines: []
    property bool hasLyrics: false
    property string currentLine: ""
    property string nextLine: ""
    property int currentIndex: -1

    readonly property bool active: Players.playing && (currentLine.length > 0 || (hasLyrics && Players.title.length > 0))

    // Watch active player and track changes
    readonly property string currentArtist: Players.artist
    readonly property string currentTitle: Players.title
    readonly property string currentUrl: Players.trackUrl
    readonly property string trackKey: Players.trackKey

    property int fetchSeq: 0
    property string loadingTrackKey: ""
    property string loadedTrackKey: ""

    // Track genuine track changes to detect stale MPRIS positions.
    property string previousTrackKey: ""
    property real trackChangeTimestamp: 0

    Component.onCompleted: queueReload()

    onTrackKeyChanged: queueReload()
    onCurrentTitleChanged: queueReload()
    onCurrentArtistChanged: queueReload()
    onCurrentUrlChanged: queueReload()

    Connections {
        target: Players
        function onAnnounce(p) {
            root.queueReload();
        }
    }

    Timer {
        id: reloadTimer
        interval: 150
        repeat: false
        onTriggered: root.reload()
    }

    // Slower tick enough for lyric lines, cheaper for UI.
    Timer {
        id: syncTimer
        interval: 250
        running: Players.playing
        repeat: true
        onTriggered: root.updatePosition()
    }

    function queueReload() {
        reloadTimer.restart();
    }

    function fallbackLine() {
        var isBrowser = currentArtist.toLowerCase() === "youtube" || currentArtist.toLowerCase() === "google chrome" || currentArtist.toLowerCase() === "brave";
        var cleanArt = (currentArtist.length > 0 && !isBrowser) ? currentArtist : "";
        return cleanArt.length > 0 ? (cleanArt + " - " + currentTitle) : currentTitle;
    }

    function setCurrent(idx, line, next) {
        if (currentIndex !== idx)
            currentIndex = idx;
        if (currentLine !== line)
            currentLine = line;
        if (nextLine !== next)
            nextLine = next;
    }

    function reload() {
        var seq = ++fetchSeq;
        lyricsProc.running = false;
        loadingTrackKey = "";
        lines = [];
        hasLyrics = false;

        var newKey = Players.has ? Players.trackKey : "";
        if (newKey.length > 0 && newKey !== previousTrackKey) {
            previousTrackKey = newKey;
            trackChangeTimestamp = Date.now();
            loadedTrackKey = "";
        }

        if (!Players.has || !Players.title || Players.title.length === 0) {
            setCurrent(-1, "", "");
            return;
        }

        // Immediately update text to new song so old lyrics never linger.
        setCurrent(-1, fallbackLine(), "");

        if (loadingTrackKey === trackKey)
            return;

        loadingTrackKey = trackKey;
        lyricsProc.command = [
            "python3",
            root.helper,
            root.currentArtist || "",
            root.currentTitle || "",
            "",
            root.currentUrl || ""
        ];
        lyricsProc.currentSeq = seq;
        lyricsProc.running = true;
    }

    Process {
        id: lyricsProc
        property int currentSeq: 0

        stdout: StdioCollector {
            onStreamFinished: {
                if (lyricsProc.currentSeq !== root.fetchSeq)
                    return;
                root.loadingTrackKey = "";
                root.loadedTrackKey = root.trackKey;
                try {
                    var res = JSON.parse(this.text);
                    if (res && res.lines && res.lines.length > 0) {
                        root.lines = res.lines;
                        root.hasLyrics = true;
                        root.updatePosition();
                    } else {
                        root.lines = [];
                        root.hasLyrics = false;
                        root.setCurrent(-1, root.fallbackLine(), "");
                    }
                } catch (e) {
                    root.lines = [];
                    root.hasLyrics = false;
                    root.setCurrent(-1, root.fallbackLine(), "");
                }
            }
        }
    }

    function updatePosition() {
        if (!Players.has || !Players.active) {
            setCurrent(-1, "", "");
            return;
        }

        var pos = Players.active.position;
        if (typeof pos !== "number" || isNaN(pos))
            pos = 0;

        // Guard against stale MPRIS positions from the previous track.
        if (trackChangeTimestamp > 0) {
            var msSinceChange = Date.now() - trackChangeTimestamp;
            if (msSinceChange < 3000 && pos > 5.0)
                pos = 0;
        }

        if (!hasLyrics || lines.length === 0) {
            if (Players.playing && currentTitle.length > 0)
                setCurrent(-1, fallbackLine(), "");
            else
                setCurrent(-1, "", "");
            return;
        }

        var lo = 0;
        var hi = lines.length - 1;
        var idx = -1;
        while (lo <= hi) {
            var mid = Math.floor((lo + hi) / 2);
            if (lines[mid].time <= pos) {
                idx = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        if (idx >= 0)
            setCurrent(idx, lines[idx].text, (idx + 1 < lines.length) ? lines[idx + 1].text : "");
        else
            setCurrent(-1, fallbackLine(), lines.length > 0 ? lines[0].text : "");
    }
}

