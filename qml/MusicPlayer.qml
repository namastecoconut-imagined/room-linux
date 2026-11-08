import QtQuick
import QtQuick.Effects

// The music player: the cover with what's next trailing to the right (swipe left to skip, right to go back), the
// cover seen through a breathing grille of dots behind, a seek bar you can drag, big controls, a tall volume slider
// and your playlists on the right, and the speaker it's playing on (tap to move the music).
Item {
    id: mp
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var music: room.music
    readonly property bool spotify: music.source !== "airplay"
    readonly property var nextUp: music.nextUp || []
    signal back()
    property bool picking: false

    // ---------------------------------------------------------------- background: the cover's colours, blurred
    CoverWash { anchors.fill: parent; source: music.art || ""; rgb: music.rgb || [80, 70, 60]; rgb2: music.rgb2 || [20, 18, 16]; strength: 0.85 }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
        }
    }

    // ---------------------------------------------------------------- the beat (as on the phone)
    // The room's sound drives it when the mic is on; otherwise, while music plays, it sits at a steady 0.5 and the
    // equaliser's own wave keeps it alive. Quick to rise, slower to fall, eased every frame.
    property real beatTarget: music.playing ? (room.micOn ? beatFromLevel : 0.5) : 0
    property real beatNow: 0
    property real beatFloor: -1
    property real beatV: 0
    readonly property real beatFromLevel: beatV
    Connections {
        target: room
        enabled: room.micOn && mp.visible
        function onLevelChanged() {
            var l = room.level
            if (mp.beatFloor < 0) mp.beatFloor = l
            else mp.beatFloor += (l - mp.beatFloor) * (l < mp.beatFloor ? 0.2 : 0.02)
            var target = Math.max(0, Math.min(1, (l - mp.beatFloor) * 5))
            mp.beatV += (target - mp.beatV) * (target > mp.beatV ? 0.8 : 0.3)
        }
    }
    FrameAnimation {
        running: mp.visible && (music.playing || mp.beatNow > 0.002)
        onTriggered: {
            var k = mp.beatTarget > mp.beatNow ? 0.32 : 0.1
            mp.beatNow += (mp.beatTarget - mp.beatNow) * Math.min(1, k * Math.min(0.05, frameTime) * 60)
        }
    }

    // ---------------------------------------------------------------- layout: the same 40 px margin on every side,
    // a 24 px gutter before the rail; everything on the left lines up on one edge
    readonly property real m: 40
    readonly property real edge: 1132 - 24          // content's right edge (the rail starts at 1132)

    // ---------------------------------------------------------------- top
    RoundBtn { x: mp.m; y: mp.m; size: 64; icon: "back"; iconSize: 24; onTapped: mp.back() }
    Cap {
        color: Qt.rgba(1, 1, 1, 0.65)
        x: mp.m + 84; y: mp.m + 23; width: mp.edge - x
        text: !music.exists ? "Nothing playing"
              : (music.context ? "Playing from · " + music.context : (spotify ? "Spotify" : music.device))
    }

    // the cover's colour as a soft light behind it, swelling with the beat
    Glow {
        readonly property real sc: 0.94 + 0.3 * mp.beatNow
        width: 1000 * sc; height: width
        x: mp.m + 228 - width / 2; y: 136 + 228 - height / 2
        color: Theme.rgb(music.rgb || [200, 185, 163])
        strength: music.playing ? 0.55 * (0.62 + 0.38 * mp.beatNow) : 0
        Behavior on strength { NumberAnimation { duration: 600 } }
    }

    // ---------------------------------------------------------------- the cover, with what's next stacked behind it
    Item {
        id: flow
        x: mp.m; y: 136; width: mp.edge - mp.m; height: 456
        property real drag: 0
        // slot k: −1 has just left (off to the left), 0 is playing, 1… are next, stacked behind and to the right
        readonly property var xs: [-520, 0, 312, 556, 768, 920]
        readonly property var ss: [456, 456, 404, 352, 300, 248]
        readonly property var os: [0, 1, 1, 1, 0.85, 0]
        function lerp(arr, k) {
            var i = Math.max(-1, Math.min(4, Math.floor(k))), f = Math.max(0, Math.min(1, k - i))
            return arr[i + 1] + (arr[Math.min(5, i + 2)] - arr[i + 1]) * f
        }
        readonly property var slots: {
            var out = [{ k: 0, t: { art: music.art, title: music.title } }]
            for (var j = 1; j <= Math.min(3, nextUp.length); j++) out.push({ k: j, t: nextUp[j - 1] })
            return out
        }
        Repeater {
            model: flow.slots
            Press {
                readonly property real kk: modelData.k + flow.drag / 300
                width: flow.lerp(flow.ss, kk); height: width
                x: flow.lerp(flow.xs, kk)
                y: (456 - width) / 2
                z: 10 - kk
                opacity: flow.lerp(flow.os, kk)
                pressScale: modelData.k === 0 ? 0.985 : 0.97
                // a soft shadow so each cover sits on the one behind it
                Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 29; color: Qt.rgba(0, 0, 0, 0.35); visible: kk > 0.05 || modelData.k === 0 }
                Cover {
                    anchors.fill: parent
                    radius: 26
                    source: modelData.t.art || ""
                    rgb: modelData.k === 0 ? (music.rgb || [200, 185, 163]) : [[110, 138, 138], [140, 94, 78], [122, 106, 140]][(modelData.k - 1) % 3]
                    rgb2: modelData.k === 0 ? (music.rgb2 || [44, 40, 34]) : [30, 28, 26]
                }
                // the further back, the darker
                Rectangle { anchors.fill: parent; radius: 26; color: "black"; opacity: Math.max(0, Math.min(0.55, kk * 0.2)) }
                onTapped: if (modelData.k > 0) room.next()
            }
        }
        DragHandler {
            id: swipe
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            onTranslationChanged: flow.drag = Math.max(-300, Math.min(300, translation.x))
            onActiveChanged: if (!active) {
                if (flow.drag < -110) room.next()
                else if (flow.drag > 110) room.previous()
                flow.drag = 0
            }
        }
        Behavior on drag { enabled: !swipe.active; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    // ---------------------------------------------------------------- title, seek, controls — on the same left edge
    Column {
        x: mp.m; y: 618; width: mp.edge - mp.m - 300; spacing: 6
        T { width: parent.width; text: music.exists ? music.title : "Nothing playing"; font.pixelSize: 40; font.weight: Font.Medium }
        T { width: parent.width; text: music.exists ? music.artist : (music.error || "Play from Spotify, or AirPlay to Room"); font.pixelSize: 23; color: Qt.rgba(1, 1, 1, 0.65) }
    }
    // what's next, on the right edge, level with the title
    Column {
        visible: nextUp.length > 0
        anchors.right: parent.left; anchors.rightMargin: -mp.edge
        y: 628; spacing: 6
        T { anchors.right: parent.right; text: "NEXT"; font.pixelSize: 14; font.letterSpacing: 2.2; color: Qt.rgba(1, 1, 1, 0.5) }
        T { anchors.right: parent.right; width: Math.min(280, implicitWidth); horizontalAlignment: Text.AlignRight; text: nextUp.length ? nextUp[0].title : ""; font.pixelSize: 21; color: Qt.rgba(1, 1, 1, 0.8) }
    }
    Item {
        id: seek
        x: mp.m; y: 720; width: mp.edge - mp.m; height: 40
        visible: music.exists && music.duration > 0
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? mp.now - music.at : 0))
        property real dragF: 0
        readonly property real f: sma.pressed ? dragF : (music.duration > 0 ? pos / music.duration : 0)
        Rectangle { y: 6; width: parent.width; height: sma.pressed ? 8 : 4; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.18); Behavior on height { NumberAnimation { duration: 120 } } }
        Rectangle { y: 6; width: parent.width * seek.f; height: sma.pressed ? 8 : 4; radius: height / 2; color: Theme.tx }
        T { y: 20; text: Theme.mmss(sma.pressed ? seek.dragF * music.duration : seek.pos); font.pixelSize: 16; color: Qt.rgba(1, 1, 1, 0.55) }
        T { y: 20; anchors.right: parent.right; text: Theme.mmss(music.duration || 0); font.pixelSize: 16; color: Qt.rgba(1, 1, 1, 0.55) }
        MouseArea {
            id: sma
            anchors.fill: parent; anchors.topMargin: -16; preventStealing: true
            enabled: mp.spotify
            onPressed: (e) => seek.dragF = Math.max(0, Math.min(1, e.x / width))
            onPositionChanged: (e) => seek.dragF = Math.max(0, Math.min(1, e.x / width))
            onReleased: room.seek(seek.dragF * music.duration)
        }
    }
    Row {
        x: mp.m; y: 776; height: 96; spacing: 20
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "prev"; iconSize: 24; onTapped: room.previous() }
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 96; iconSize: 30; icon: music.playing ? "pause" : "play"; fill: Theme.tx; ink: "black"; onTapped: room.playPause() }
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "next"; iconSize: 24; onTapped: room.next() }
    }

    // the dot equaliser: 7 columns × 5 dots, about 12 steps a second, each column following the beat with a bit of
    // its own life, up to two dots per step; the top lit dot is amber
    Item {
        id: eq
        x: 477; y: 872 - height - 10; width: 6 * 33 + 14; height: 4 * 18 + 14
        property var levels: [0, 0, 0, 0, 0, 0, 0]
        Timer {
            interval: 83; repeat: true
            running: mp.visible && (music.playing || eq.levels.some(function (n) { return n > 0 }))
            onTriggered: {
                var t = Date.now() / 1000, v = music.playing ? mp.beatNow : 0, out = []
                for (var c = 0; c < 7; c++) {
                    var wave = 0.55 + 0.25 * Math.sin(t * (1.6 + c * 0.37) + c * 1.7) + 0.2 * Math.random()
                    var want = v <= 0 ? 0 : Math.max(1, Math.round(v * 5 * wave))
                    var cur = eq.levels[c]
                    out.push(want > cur ? Math.min(want, cur + 2) : want < cur ? Math.max(want, cur - 2) : cur)
                }
                eq.levels = out
            }
        }
        Repeater {
            model: 35
            Rectangle {
                readonly property int c: Math.floor(index / 5)
                readonly property int r: index % 5
                readonly property int n: eq.levels[c]
                x: c * 33; y: (4 - r) * 18
                width: 14; height: 14; radius: 7
                color: r < n ? (r === n - 1 ? Theme.accent : Theme.tx) : Qt.rgba(0.96, 0.95, 0.94, 0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }

    // the speaker — tap to move the music somewhere else (Spotify); on the right edge, level with the controls
    Press {
        x: mp.edge - width; y: 792; width: Math.min(420, spk.implicitWidth + 98); height: 64; pressScale: 0.97
        enabled: mp.spotify
        Rectangle { anchors.fill: parent; radius: 32; color: Qt.rgba(1, 1, 1, 0.09) }
        Icon { x: 24; anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 22 }
        T { id: spk; x: 62; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 86; text: music.device || "Choose a speaker"; font.pixelSize: 19 }
        onTapped: { room.refreshDevices(); mp.picking = true }
    }

    // ---------------------------------------------------------------- right rail: volume + playlists
    Glass {
        x: 1132; y: 40; width: 196; height: 832
        // volume: one solid tile that fills from the bottom, like a control-centre slider
        Item {
            id: vol
            x: 22; y: 22; width: 152
            height: (music.playlists || []).length > 0 ? 500 : 788
            enabled: music.canVolume !== false
            opacity: enabled ? 1 : 0.35
            property int local: music.volume || 0
            readonly property int shown: vma.pressed ? local : (music.volume || 0)
            readonly property real fillH: height * shown / 100
            Item {
                id: volBody
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: volMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.08) }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; height: vol.fillH
                    color: Qt.rgba(0.96, 0.95, 0.94, 0.92)
                    Behavior on height { enabled: !vma.pressed; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }
            Rectangle { id: volMask; anchors.fill: parent; radius: 36; visible: false; layer.enabled: true; layer.smooth: true }
            T {
                anchors.horizontalCenter: parent.horizontalCenter; y: 26
                text: vol.shown; font.pixelSize: 26; font.weight: Font.Medium
                color: vol.fillH > vol.height - 64 ? "black" : Theme.tx
            }
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                name: "speaker"; size: 30; color: vol.fillH > 70 ? "black" : Theme.tx
            }
            Timer { id: vThrottle; interval: 200; onTriggered: room.setVolume(vol.local) }
            MouseArea {
                id: vma
                anchors.fill: parent; preventStealing: true
                function at(y) { return Math.max(0, Math.min(100, Math.round((1 - y / vol.height) * 100))) }
                onPressed: (e) => vol.local = at(e.y)
                onPositionChanged: (e) => { vol.local = at(e.y); if (!vThrottle.running) vThrottle.start() }
                onReleased: { vThrottle.stop(); room.setVolume(vol.local) }
            }
        }
        Cap { color: Qt.rgba(1, 1, 1, 0.6); anchors.horizontalCenter: parent.horizontalCenter; y: 552; text: "Playlists"; visible: (music.playlists || []).length > 0 }
        GridView {
            x: 22; y: 586; width: 156; height: 236
            cellWidth: 78; cellHeight: 78
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: music.playlists || []
            delegate: Press {
                width: 70; height: 70; pressScale: 0.93
                Cover {
                    anchors.fill: parent; radius: 14; source: modelData.art || ""
                    rgb: [[140, 94, 78], [78, 110, 140], [110, 140, 94], [140, 122, 78], [122, 106, 140], [94, 140, 132]][index % 6]
                    rgb2: [21, 21, 21]
                }
                onTapped: room.playUri(modelData.uri)
            }
        }
    }

    // ---------------------------------------------------------------- speaker picker
    SpeakerPicker {
        anchors.fill: parent
        open: mp.picking
        devices: music.devices || []
        onClose: mp.picking = false
        onPick: (id) => { room.transfer(id); mp.picking = false }
    }
}
