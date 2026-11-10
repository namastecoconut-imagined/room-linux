import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The voice assistant on screen (design B + D): the window of light in the middle, its orb swelling with your voice
// and sending out a ripple on each syllable, while the whole edge of the screen glows with it. Live words aren't
// shown (the recogniser's guesses are rough); your words come in, word by word, the moment it's sure of them, then
// the answer below them. Tap anywhere to stop.
Item {
    id: vo
    width: Theme.stageW; height: Theme.stageH
    property bool active: false
    signal close()

    readonly property var v: room.voice
    readonly property string st: v.state || "off"
    readonly property string stage: v.stage || "idle"
    readonly property string mode: !active ? "gone" : st === "listening" ? "listen" : st === "thinking" ? "think"
                                  : st === "speaking" ? "speak" : stage === "miss" ? "miss" : (v.reply || v.line) ? "done" : "gone"
    readonly property string heard: v.heard || ""
    readonly property string answer: v.reply || v.line || ""

    // the phone's "day" colours
    readonly property var c0: [255, 200, 90]
    readonly property var c1: [90, 190, 255]
    readonly property var c2: [120, 230, 180]
    readonly property var c3: [255, 140, 120]
    function col(a, f) { return Qt.rgba(a[0] / 255 * f, a[1] / 255 * f, a[2] / 255 * f, 1) }

    // ---------------------------------------------------------------- motion: the voice, smoothed
    property real phase: 0
    property real cur: 0            // 0…1: how loud the voice is right now (quick up, slow down)
    property real thinkMix: 0
    // the beat of your voice, the way the music screen follows the music: loudness over its own recent floor
    property real beatFloor: -1
    property real beat: 0
    Timer {
        interval: 33; repeat: true; running: vo.active && vo.visible
        onTriggered: {
            vo.phase += 0.033
            var want = vo.mode === "listen" ? Math.min(1, room.level * 1.4)
                     : vo.mode === "speak" ? 0.25 + Math.min(0.5, room.level * 0.6)
                     : vo.mode === "think" ? 0.18 + 0.08 * Math.sin(vo.phase * 3) : 0.1
            vo.cur += (want - vo.cur) * (want > vo.cur ? 0.35 : 0.08)
            vo.thinkMix += ((vo.mode === "think" ? 1 : 0) - vo.thinkMix) * 0.06
            var l = room.level
            if (vo.beatFloor < 0) vo.beatFloor = l
            else vo.beatFloor += (l - vo.beatFloor) * (l < vo.beatFloor ? 0.2 : 0.02)
            var b = vo.mode === "listen" || vo.mode === "speak" ? Math.max(0, Math.min(1, (l - vo.beatFloor) * 4)) : 0
            vo.beat += (b - vo.beat) * (b > vo.beat ? 0.5 : 0.12)
        }
    }

    // ---------------------------------------------------------------- the backdrop and the glowing edge (D)
    Rectangle { anchors.fill: parent; color: "#050608"; opacity: vo.mode === "gone" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 350 } } }
    ShaderEffect {
        anchors.fill: parent
        opacity: vo.mode === "gone" ? 0 : vo.mode === "miss" ? 0.35 : vo.mode === "done" ? 0.55 : 1
        Behavior on opacity { NumberAnimation { duration: 500 } }
        visible: opacity > 0
        property size res: Qt.size(width, height)
        property real t: vo.phase
        property real level: vo.mode === "listen" ? vo.cur : vo.cur * 0.5
        property real depth: 34
        property color c0: vo.col(vo.c0, 1)
        property color c1: vo.col(vo.c1, 1)
        property color c2: vo.col(vo.c2, 1)
        property color c3: vo.col(vo.c3, 1)
        fragmentShader: shaderDir + "edge.frag.qsb"
    }

    // ---------------------------------------------------------------- the glow behind the window, pulsing with your
    // voice the way the music screen's glow pulses with the song (its colours slowly turn: warm, blue, mint, coral)
    Shape {
        id: glow
        width: 1500; height: 1500
        x: (vo.width - width) / 2; y: 150 + vo.winH / 2 - height / 2
        scale: 0.85 + 0.35 * vo.beat + 0.05 * Math.sin(vo.phase * 0.8)
        opacity: vo.mode === "gone" ? 0 : vo.mode === "think" ? 0.45 + 0.1 * Math.sin(vo.phase * 3) : 0.4 + 0.5 * vo.beat
        preferredRendererType: Shape.CurveRenderer
        readonly property real k: (Math.sin(vo.phase * 0.35) + 1) / 2
        readonly property color c: Qt.rgba((vo.c0[0] * (1 - k) + vo.c1[0] * k) / 255, (vo.c0[1] * (1 - k) + vo.c1[1] * k) / 255,
                                           (vo.c0[2] * (1 - k) + vo.c1[2] * k) / 255, 1)
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glow.width / 2; centerY: glow.height / 2; centerRadius: glow.width / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0.42) }
                GradientStop { position: 0.4; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0.16) }
                GradientStop { position: 1; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0) }
            }
            PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height; radius: glow.width / 2 }
        }
    }

    // ---------------------------------------------------------------- the window of light (B), softer
    // (blurred further and dimmer than the phone's: a haze of light rather than a shape)
    readonly property real winW: 760
    readonly property real winH: 300
    Item {
        id: winBox
        x: (vo.width - vo.winW) / 2; y: 150; width: vo.winW; height: vo.winH
        opacity: vo.mode === "gone" ? 0 : vo.mode === "miss" ? 0.3 : 0.7
        scale: vo.mode === "gone" ? 0.94 : 1
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
        ShaderEffect {
            id: win
            anchors.fill: parent
            property size res: Qt.size(width, height)
            property real radius: 140
            property real blur: 70
            property color gTop: vo.col(vo.c3, 0.3)
            property color gMid: vo.col(vo.c1, 0.75)
            property color gBot: vo.col(vo.c0, 0.95)
            property color hazeC: vo.col(vo.c2, 1)
            property color haze2C: vo.col(vo.c3, 1)
            property color orbC: Qt.rgba(1, 0.95, 0.85, 1)
            readonly property real t: vo.phase
            readonly property real calmX: width / 2 + Math.sin(t * 0.7) * width * 0.06
            readonly property real calmY: height * 0.7 - vo.cur * height * 0.12
            readonly property real wanX: width / 2 + Math.sin(t * 1.7) * width * 0.28
            readonly property real wanY: height * 0.6 + Math.cos(t * 1.3) * height * 0.12
            property vector3d orb: Qt.vector3d(calmX + (wanX - calmX) * vo.thinkMix, calmY + (wanY - calmY) * vo.thinkMix,
                                               (110 + vo.cur * 190) * (1 - vo.thinkMix) + 160 * vo.thinkMix)
            property vector3d haze: Qt.vector3d(width / 2 + Math.sin(t * 0.45 + 2) * width * 0.3, height * 0.35 + Math.cos(t * 0.5) * height * 0.15, 340)
            property vector3d haze2: Qt.vector3d(width / 2 + Math.sin(t * 0.33 + 5) * width * 0.32,
                                                 height * 0.55 + Math.sin(t * 0.41 + 1) * height * 0.2, 300 * (1 + vo.cur * 0.35))
            fragmentShader: shaderDir + "window.frag.qsb"
        }
    }

    // ---------------------------------------------------------------- the label: LISTENING / GO ON / THINKING
    Text {
        id: lab
        width: vo.width; y: 96
        horizontalAlignment: Text.AlignHCenter
        text: (vo.mode === "listen" ? (vo.stage === "follow" ? "go on" : "listening") : vo.mode === "think" ? "thinking"
               : vo.mode === "miss" ? "didn’t catch that" : "").toUpperCase()
        color: vo.mode === "miss" ? Qt.rgba(0.8, 0.78, 0.76, 0.7) : Qt.rgba(1, 226 / 255, 196 / 255, 0.85)
        font.family: Theme.face; font.pixelSize: 20; font.weight: Font.Medium; font.letterSpacing: 5
        opacity: beat
        property real beat: 1
        SequentialAnimation on beat {
            running: vo.mode === "listen" || vo.mode === "think"; loops: Animation.Infinite
            onRunningChanged: if (!running) lab.beat = 1
            NumberAnimation { from: 1; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.45; to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }

    // ---------------------------------------------------------------- your words, then the answer
    Flow {
        id: said
        x: 120; width: vo.width - 240; y: vo.mode === "speak" || vo.mode === "done" ? 486 : 500
        spacing: 12
        layoutDirection: Qt.LeftToRight
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        opacity: vo.mode === "gone" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 300 } }
        readonly property bool small: vo.mode === "speak" || vo.mode === "done"
        Repeater {
            model: vo.heard ? vo.heard.split(" ") : []
            Text {
                id: wd
                text: modelData
                font.family: Theme.face; font.pixelSize: said.small ? 28 : 44
                color: said.small ? Qt.rgba(1, 0.95, 0.9, 0.5) : Qt.rgba(1, 0.98, 0.95, 1)
                opacity: 0
                Behavior on font.pixelSize { NumberAnimation { duration: 300 } }
                Component.onCompleted: fade.start()
                SequentialAnimation {
                    id: fade
                    PauseAnimation { duration: index * 55 }
                    NumberAnimation { target: wd; property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    Text {
        x: 120; width: vo.width - 240; y: 540
        text: vo.mode === "speak" || vo.mode === "done" ? vo.answer : ""
        wrapMode: Text.WordWrap; maximumLineCount: 5; elide: Text.ElideRight
        font.family: Theme.face; font.pixelSize: vo.answer.length > 140 ? 34 : 42; lineHeight: 1.15
        color: Theme.ink
        opacity: text ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }
    // a hint, only the moment it wakes
    Text {
        width: vo.width; y: 840
        horizontalAlignment: Text.AlignHCenter
        text: "“make it cozy”  ·  “what’s the weather tomorrow?”  ·  “play some Arijit Singh”"
        color: Qt.rgba(1, 232 / 255, 210 / 255, 0.35)
        font.family: Theme.face; font.pixelSize: 22
        opacity: vo.mode === "listen" && !vo.heard ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    MouseArea { anchors.fill: parent; enabled: vo.mode !== "gone"; onClicked: { room.cancelVoice(); vo.close() } }
}
