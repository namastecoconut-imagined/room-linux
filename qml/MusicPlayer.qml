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

    // ---------------------------------------------------------------- background: the cover through a grille of dots
    CoverWash {
        id: wash
        anchors.fill: parent; visible: false
        source: music.art || ""; rgb: music.rgb || [80, 70, 60]; rgb2: music.rgb2 || [20, 18, 16]; strength: 1.0
    }
    ShaderEffectSource { id: washTex; sourceItem: wash; hideSource: true; live: true; textureSize: Qt.size(342, 228) }
    ShaderEffect {
        anchors.fill: parent
        visible: mp.visible
        property var src: washTex
        property real time: mp.t
        property real pitch: 14 * (width > 0 ? width / Theme.stageW : 1)
        property real beat: music.playing ? 0.35 : 0
        property real pad: 0
        property size res: Qt.size(width, height)
        vertexShader: shaderDir + "halftone.vert.qsb"
        fragmentShader: shaderDir + "halftone.frag.qsb"
        Behavior on beat { NumberAnimation { duration: 800 } }
    }
    property real t: 0
    NumberAnimation on t { running: mp.visible; from: 0; to: 100000; duration: 100000 * 1000; loops: Animation.Infinite }
    // darker towards the bottom so the title and controls always read
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.40) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.82) }
        }
    }

    // ---------------------------------------------------------------- top
    RoundBtn { x: 48; y: 44; size: 64; icon: "back"; iconSize: 24; onTapped: mp.back() }
    Cap {
        color: Qt.rgba(1, 1, 1, 0.65)
        x: 132; y: 67; width: 960
        text: !music.exists ? "Nothing playing"
              : (music.context ? "Playing from · " + music.context : (spotify ? "Spotify" : music.device))
    }

    // ---------------------------------------------------------------- the cover, with what's next trailing to the right
    Item {
        id: flow
        x: 0; y: 140; width: 1112; height: 450
        property real drag: 0
        // slot k: −1 has just left (off to the left), 0 is playing, 1… are next
        function px(k) { return k <= 0 ? 120 + k * 520 : k <= 1 ? 120 + k * 480 : k <= 2 ? 600 + (k - 1) * 270 : 870 + (k - 2) * 200 }
        function sz(k) { return k <= 0 ? 440 : k <= 1 ? 440 - k * 110 : k <= 2 ? 330 - (k - 1) * 110 : 220 - (k - 2) * 60 }
        function op(k) { return k < 0 ? Math.max(0, 1 + k) : k <= 1 ? 1 : k <= 2 ? 1 - (k - 1) * 0.55 : Math.max(0, 0.45 - (k - 2) * 0.45) }
        readonly property var slots: {
            var out = [{ k: 0, t: { art: music.art, title: music.title } }]
            for (var j = 1; j <= Math.min(3, nextUp.length); j++) out.push({ k: j, t: nextUp[j - 1] })
            return out
        }
        Repeater {
            model: flow.slots
            Press {
                readonly property real kk: modelData.k + flow.drag / 480
                width: flow.sz(kk); height: width
                x: flow.px(kk)
                y: (440 - width) / 2
                z: 10 - Math.abs(kk)
                opacity: flow.op(kk)
                pressScale: modelData.k === 0 ? 0.985 : 0.97
                Cover {
                    anchors.fill: parent
                    radius: modelData.k === 0 ? 26 : 18
                    source: modelData.t.art || ""
                    rgb: modelData.k === 0 ? (music.rgb || [200, 185, 163]) : [[110, 138, 138], [140, 94, 78], [122, 106, 140]][(modelData.k - 1) % 3]
                    rgb2: modelData.k === 0 ? (music.rgb2 || [44, 40, 34]) : [30, 28, 26]
                }
                // a hairline label under the next song
                T {
                    visible: modelData.k === 1 && flow.drag === 0
                    anchors.top: parent.bottom; anchors.topMargin: 14; width: parent.width
                    text: "Next  ·  " + (modelData.t.title || ""); font.pixelSize: 16; color: Qt.rgba(1, 1, 1, 0.55)
                }
                onTapped: if (modelData.k > 0) room.next()
            }
        }
        DragHandler {
            id: swipe
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            onTranslationChanged: flow.drag = Math.max(-480, Math.min(300, translation.x))
            onActiveChanged: if (!active) {
                if (flow.drag < -120) room.next()
                else if (flow.drag > 120) room.previous()
                flow.drag = 0
            }
        }
        Behavior on drag { enabled: !swipe.active; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    // ---------------------------------------------------------------- title, seek, controls — all on the cover's left edge
    Column {
        x: 120; y: 616; width: 960; spacing: 6
        T { width: parent.width; text: music.exists ? music.title : "Nothing playing"; font.pixelSize: 42; font.weight: Font.Medium }
        T { width: parent.width; text: music.exists ? music.artist : (music.error || "Play from Spotify, or AirPlay to Room"); font.pixelSize: 23; color: Qt.rgba(1, 1, 1, 0.65) }
    }
    Item {
        id: seek
        x: 120; y: 724; width: 960; height: 40
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
        x: 120; y: 788; spacing: 20
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "prev"; iconSize: 24; onTapped: room.previous() }
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 96; iconSize: 30; icon: music.playing ? "pause" : "play"; fill: Theme.tx; ink: "black"; onTapped: room.playPause() }
        RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 72; icon: "next"; iconSize: 24; onTapped: room.next() }
    }

    // the speaker — tap to move the music somewhere else (Spotify)
    Press {
        x: 1080 - width; y: 804; width: Math.min(420, spk.implicitWidth + 98); height: 64; pressScale: 0.97
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
