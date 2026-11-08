import QtQuick
import QtQuick.Effects

// The music player: cover flow (swipe the covers, or tap one either side), a seek bar you can drag, big controls,
// a tall volume slider and your playlists on the right, and the speaker it's playing on (tap to move the music).
Item {
    id: mp
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var music: room.music
    readonly property bool spotify: music.source !== "airplay"
    readonly property var nextUp: music.nextUp || []
    readonly property var recent: music.recent || []
    signal back()
    property bool picking: false

    // ---------------------------------------------------------------- background: the cover, blurred
    CoverWash { anchors.fill: parent; source: music.art || ""; rgb: music.rgb || [80, 70, 60]; rgb2: music.rgb2 || [20, 18, 16]; strength: 0.85 }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
        }
    }

    // ---------------------------------------------------------------- top
    RoundBtn { x: 40; y: 40; size: 64; icon: "back"; iconSize: 24; onTapped: mp.back() }
    Cap { color: Qt.rgba(1, 1, 1, 0.6)
        x: 124; y: 63; width: 900
        text: music.exists ? (spotify ? (music.context ? "Playing from · " + music.context : "Spotify") : music.device) : "Nothing playing"
    }

    // ---------------------------------------------------------------- cover flow
    Item {
        id: flow
        x: 0; y: 110; width: 1112; height: 470
        readonly property real cx: 556
        property real drag: 0
        // left: what played before (nearest first); right: what's next
        readonly property var slots: {
            var out = []
            for (var i = Math.min(2, recent.length); i >= 1; i--) out.push({ k: -i, t: recent[i - 1] })
            out.push({ k: 0, t: { art: music.art, title: music.title } })
            for (var j = 1; j <= Math.min(2, nextUp.length); j++) out.push({ k: j, t: nextUp[j - 1] })
            return out
        }
        Repeater {
            model: flow.slots
            Press {
                readonly property real kk: modelData.k + flow.drag / 235
                readonly property real a: Math.abs(kk)
                readonly property real sz: a < 1 ? 440 - 100 * a : Math.max(180, 340 - 90 * (a - 1))
                width: sz; height: sz
                x: flow.cx + kk * 210 + (kk > 0 ? 1 : -1) * Math.min(a, 1) * 20 - sz / 2
                y: (440 - sz) / 2 + 10
                z: 10 - a
                opacity: a < 0.5 ? 1 : Math.max(0, 1 - 0.32 * a)
                pressScale: modelData.k === 0 ? 0.985 : 0.97
                Behavior on x { enabled: !swipe.active; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Cover {
                    anchors.fill: parent
                    radius: modelData.k === 0 ? 26 : 18
                    source: modelData.t.art || ""
                    // placeholder colours differ per cover so the flow reads even before art loads
                    rgb: modelData.k === 0 ? (music.rgb || [200, 185, 163]) : [[122, 106, 140], [154, 138, 110], [0, 0, 0], [110, 138, 138], [140, 94, 78]][modelData.k + 2]
                    rgb2: modelData.k === 0 ? (music.rgb2 || [44, 40, 34]) : [30, 28, 26]
                    opacity: modelData.k === 0 || modelData.t.art ? 1 : 0.7
                }
                onTapped: if (modelData.k > 0) room.next(); else if (modelData.k < 0) room.previous()
            }
        }
        DragHandler {
            id: swipe
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            onTranslationChanged: flow.drag = Math.max(-260, Math.min(260, translation.x))
            onActiveChanged: if (!active) {
                if (flow.drag < -110) room.next()
                else if (flow.drag > 110) room.previous()
                flow.drag = 0
            }
        }
        Behavior on drag { enabled: !swipe.active; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }

    // ---------------------------------------------------------------- title, seek, controls
    Column {
        x: 106; y: 600; width: 900; spacing: 6
        T { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: music.exists ? music.title : "Nothing playing"; font.pixelSize: 44; font.weight: Font.Medium }
        T { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: music.exists ? music.artist : (music.error || "Play from Spotify, or AirPlay to Room"); font.pixelSize: 24; color: Theme.mut }
    }
    Item {
        id: seek
        x: 250; y: 728; width: 700; height: 44
        visible: music.exists && music.duration > 0
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? mp.now - music.at : 0))
        property real dragF: 0
        readonly property real f: sma.pressed ? dragF : (music.duration > 0 ? pos / music.duration : 0)
        Rectangle { y: 8; width: parent.width; height: sma.pressed ? 8 : 4; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.16); Behavior on height { NumberAnimation { duration: 120 } } }
        Rectangle { y: 8; width: parent.width * seek.f; height: sma.pressed ? 8 : 4; radius: height / 2; color: Theme.tx }
        T { y: 24; color: Qt.rgba(1, 1, 1, 0.55); text: Theme.mmss(sma.pressed ? seek.dragF * music.duration : seek.pos); font.pixelSize: 16 }
        T { y: 24; anchors.right: parent.right; text: Theme.mmss(music.duration || 0); font.pixelSize: 16; color: Qt.rgba(1, 1, 1, 0.55) }
        MouseArea {
            id: sma
            anchors.fill: parent; anchors.topMargin: -16; preventStealing: true
            enabled: mp.spotify
            onPressed: (e) => seek.dragF = Math.max(0, Math.min(1, e.x / width))
            onPositionChanged: (e) => seek.dragF = Math.max(0, Math.min(1, e.x / width))
            onReleased: room.seek(seek.dragF * music.duration)
        }
    }
    Item {
        x: 390; y: 790; width: 420; height: 96
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "prev"; iconSize: 24; onTapped: room.previous() }
        RoundBtn { anchors.centerIn: parent; size: 96; iconSize: 30; icon: music.playing ? "pause" : "play"; fill: Theme.tx; ink: "black"; onTapped: room.playPause() }
        RoundBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "next"; iconSize: 24; onTapped: room.next() }
    }

    // the speaker — tap to move the music somewhere else
    Press {
        x: 40; y: 814; width: 330; height: 56; pressScale: 0.97
        enabled: mp.spotify
        Rectangle { width: 52; height: 52; radius: 26; color: Qt.rgba(1, 1, 1, 0.08) }
        Icon { x: 16; y: 16; name: "speaker"; size: 20 }
        T { x: 66; y: 14; width: 260; text: music.device || "Choose a speaker"; font.pixelSize: 19; color: Theme.mut }
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
