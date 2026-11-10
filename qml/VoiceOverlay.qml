import QtQuick

// The voice assistant on screen (design: "Horizon fog" — Figma "Room — Assistant & Orb"): a band of glowing cloud
// across the upper middle with light falling from it in soft rays (shaders/fog.frag), in the panel's colours, changing
// with each state — cool blue and mint while it listens (light flowing up into the cloud), warm amber and coral while
// Room speaks (flowing down out of it), blue with a touch of coral thinking.
// The cloud follows your voice. Your words come in once it's sure of them, then the answer below them. Tap to stop.
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

    // ---------------------------------------------------------------- motion: the voice, smoothed
    property real phase: 0
    property real cur: 0            // 0…1: how loud the voice is right now (quick up, slow down)
    property real calm: 0           // the voice for the fog: heavily smoothed
    property real calm1: 0
    property real quick: 0          // the voice, quick (cores, rays, flow)
    property real flowDir: 1
    property real flowT: 0
    Timer {
        interval: 33; repeat: true; running: vo.active && vo.visible
        onTriggered: {
            vo.phase += 0.033
            var want = vo.mode === "listen" ? Math.min(1, room.voiceLevel * 1.3)
                     : vo.mode === "speak" ? 0.25 + Math.min(0.5, room.level * 0.6)
                     : vo.mode === "think" ? 0.18 + 0.08 * Math.sin(vo.phase * 3) : 0.1
            vo.cur += (want - vo.cur) * (want > vo.cur ? 0.35 : 0.08)
            // the fog follows the voice slowly but deeply — a swell, not a pulse (following every syllable made it pump like a
            // speaker cone): rises over about half a second, settles over a second and a half
            var f = vo.mode === "listen" ? Math.min(1, vo.cur * 0.85) : vo.mode === "speak" ? 0.12 + 0.12 * Math.min(1, room.level) : 0
            // two stages of smoothing: it eases in and out of each swell instead of jerking (deep but smooth)
            vo.calm1 += (f - vo.calm1) * (f > vo.calm1 ? 0.07 : 0.03)
            vo.calm += (vo.calm1 - vo.calm) * 0.06
            // …and a quick layer that follows every word without moving the cloud: the bright cores, the rays and the
            // light flowing through them (so it's plainly hearing you, without the pumping)
            var qk = vo.mode === "listen" ? Math.min(1, room.voiceLevel * 1.8) : vo.mode === "speak" ? 0.6 * Math.min(1, room.level * 1.2) : 0
            vo.quick += (qk - vo.quick) * (qk > vo.quick ? 0.3 : 0.1)
            // the flow in the rays: up into the cloud while it listens (taking your voice in), down out of it while Room
            // speaks, barely moving while it thinks; faster as you talk
            var dir = vo.mode === "listen" ? -1 : vo.mode === "think" ? 0.25 : 1
            vo.flowDir += (dir - vo.flowDir) * 0.05
            vo.flowT += 0.033 * vo.flowDir * (1 + 1.6 * vo.quick)
        }
    }

    // ---------------------------------------------------------------- the backdrop
    // (both a little past the screen's edges, so the burn-in drift never shows an edge)
    Rectangle { anchors.fill: parent; anchors.margins: -60; color: "#050608"; opacity: vo.mode === "gone" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 350 } } }
    // ---------------------------------------------------------------- the fog (shaders/fog.frag)
    readonly property color warm: Qt.rgba(1.0, 0.76, 0.38, 1)
    readonly property color blue: Qt.rgba(0.33, 0.72, 1.0, 1)
    readonly property color mint: Qt.rgba(0.45, 0.88, 0.70, 1)
    readonly property color coral: Qt.rgba(1.0, 0.56, 0.48, 1)
    // each state's colours (the three the cloud drifts between) and how much fog it has
    readonly property var look: mode === "listen" && stage === "follow" ? [mint, blue, mint, 0.7]
                              : mode === "listen" ? [blue, mint, blue, 0.7]
                              : mode === "think" ? [blue, coral, mint, 0.55]
                              : mode === "speak" && stage === "error" ? [coral, coral, blue, 0.4]
                              : mode === "speak" ? [warm, coral, warm, 0.75]
                              : mode === "done" && stage === "error" ? [coral, coral, blue, 0.32]
                              : mode === "done" ? [warm, coral, warm, 0.42]
                              : mode === "miss" ? [blue, blue, mint, 0.28] : [blue, mint, blue, 0.0]
    ShaderEffect {
        anchors.fill: parent; anchors.margins: -60
        opacity: vo.mode === "gone" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        visible: opacity > 0
        property size res: Qt.size(width, height)
        property real t: vo.phase
        property real level: vo.calm
        property real voice: vo.quick
        property real flow: vo.flowT
        property real amount: vo.look[3]
        Behavior on amount { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
        property color c1: vo.look[0]
        property color c2: vo.look[1]
        property color c3: vo.look[2]
        Behavior on c1 { ColorAnimation { duration: 1200 } }
        Behavior on c2 { ColorAnimation { duration: 1200 } }
        Behavior on c3 { ColorAnimation { duration: 1200 } }
        fragmentShader: shaderDir + "fog.frag.qsb"
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
