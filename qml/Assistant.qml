import QtQuick

// Alexa — the phone's VoiceView, scaled up for the room: a soft warm "window" of light. While you talk your words
// sit centred on it and a bright orb inside swells with your voice; while it thinks the orb drifts; when it answers
// the window slides left with the answer on it, your question shrinks to one line, and a roomy card (if there is
// one) eases in on the right. Tap anywhere to stop.
Item {
    id: vv
    width: Theme.stageW; height: Theme.stageH
    property bool active: false
    property var v: room.voice
    signal close()

    // the phone's 568 × 320 canvas, scaled 2.4× and centred
    readonly property real s: 2.4
    function px(x) { return 2 + x * s }
    function py(y) { return 72 + y * s }

    readonly property string st: v.state || "off"
    readonly property string stage: !active ? "" : st === "off" ? "off" : (v.stage || "idle")
    readonly property string heard: v.heard || ""
    readonly property string answer: { var sp = v.reply || "", ln = v.line || ""; return sp.length > ln.length + 12 ? sp : ln }
    readonly property string card: mode === "done" && ["weather", "forecast", "air", "timer", "music", "schedule", "alarm"].indexOf(v.card) >= 0 ? v.card : ""
    // idle after an answer keeps the answer layout while the screen closes (no snapping back to the middle)
    readonly property string mode: stage === "wake" || stage === "follow" || stage === "heard" ? "listen"
                                 : stage === "think" ? "think" : stage === "done" ? "done"
                                 : stage === "idle" ? ((v.reply || v.line) ? "done" : "gone") : stage === "" ? "gone" : "miss"

    // the phone's "day" colours: warm yellow, sky blue, mint and coral
    readonly property var c0: [255, 200, 90]
    readonly property var c1: [90, 190, 255]
    readonly property var c2: [120, 230, 180]
    readonly property var c3: [255, 140, 120]
    function col(a, f) { return Qt.rgba(a[0] / 255 * f, a[1] / 255 * f, a[2] / 255 * f, 1) }
    readonly property color warm: Qt.rgba(1, 226 / 255, 196 / 255, 1)

    Rectangle { anchors.fill: parent; color: "black" }

    // ---------------------------------------------------------------- motion (the phone's display link)
    property real phase: 0
    property real cur: 0
    property real thinkMix: 0
    Timer {
        interval: 33; repeat: true; running: vv.active && vv.visible
        onTriggered: {
            var dt = 0.033
            vv.phase += dt
            var want = 0
            if (vv.mode === "listen") want = Math.min(1, room.level * 1.3)
            else if (vv.mode === "done") want = vv.st === "speaking" ? 0.25 + Math.min(0.6, room.level * 0.8) : 0.12 + 0.08 * Math.sin(vv.phase * 2.2)
            else if (vv.mode === "think") want = 0.2
            var k = want > vv.cur ? 0.25 : 0.08               // quick to rise, slower to fall — breathing, never jitter
            vv.cur += (want - vv.cur) * Math.min(1, k * dt * 60)
            vv.thinkMix += ((vv.mode === "think" ? 1 : 0) - vv.thinkMix) * Math.min(1, 0.05 * dt * 60)
        }
    }

    // ---------------------------------------------------------------- the window
    readonly property var centreR: [84, 34, 400, 252]
    readonly property var winR: mode === "done" ? (card ? [18, 24, 296, 272] : [18, 24, 532, 272]) : centreR
    ShaderEffect {
        id: win
        x: vv.px(vv.winR[0]); y: vv.py(vv.winR[1]); width: vv.winR[2] * vv.s; height: vv.winR[3] * vv.s
        opacity: vv.mode === "gone" ? 0 : vv.mode === "miss" ? 0.35 : 1
        Behavior on x { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } }
        Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } }
        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } }
        Behavior on height { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } }
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        property size res: Qt.size(width, height)
        property real radius: 60 * vv.s
        property real blur: 16 * vv.s
        property color gTop: vv.col(vv.c3, 0.3)
        property color gMid: vv.col(vv.c1, 0.75)
        property color gBot: vv.col(vv.c0, 0.95)
        property color hazeC: vv.col(vv.c2, 1)
        property color haze2C: vv.col(vv.c3, 1)
        property color orbC: Qt.rgba((255 - (255 - vv.c0[0]) * 0.45) / 255, (255 - (255 - vv.c0[1]) * 0.45) / 255, (255 - (255 - vv.c0[2]) * 0.45) / 255, 1)
        readonly property real t: vv.phase
        readonly property real ww: width
        readonly property real hh: height
        // calm: low in the window, rising and swelling with the voice; thinking: wandering round the window
        readonly property real calmX: ww / 2 + Math.sin(t * 0.7) * ww * 0.08
        readonly property real calmY: hh * 0.74 - vv.cur * hh * 0.12
        readonly property real wanX: ww / 2 + Math.sin(t * 1.7) * ww * 0.28
        readonly property real wanY: hh * 0.62 + Math.cos(t * 1.3) * hh * 0.12
        property vector3d orb: Qt.vector3d(calmX + (wanX - calmX) * vv.thinkMix, calmY + (wanY - calmY) * vv.thinkMix,
                                           ((50 + vv.cur * 80) * (1 - vv.thinkMix) + 70 * vv.thinkMix) * vv.s)
        property vector3d haze: Qt.vector3d(ww / 2 + Math.sin(t * 0.45 + 2) * ww * 0.3, hh * 0.35 + Math.cos(t * 0.5) * hh * 0.15, 150 * vv.s)
        property vector3d haze2: Qt.vector3d(ww / 2 + Math.sin(t * 0.33 + 5) * ww * 0.32, hh * 0.55 + Math.sin(t * 0.41 + 1) * hh * 0.2,
                                             130 * vv.s * (1 + vv.cur * 0.35))
        fragmentShader: shaderDir + "window.frag.qsb"
    }

    // ---------------------------------------------------------------- words
    // the small label over the words: LISTENING / GO ON / THINKING (beating) · DIDN'T CATCH THAT (grey)
    Text {
        id: lab
        x: 0; width: vv.width; y: vv.py(66)
        horizontalAlignment: Text.AlignHCenter
        text: (vv.mode === "listen" ? (vv.stage === "follow" ? "go on" : "listening") : vv.mode === "think" ? "thinking"
               : vv.stage === "off" ? "voice is off" : vv.mode === "miss" ? "didn’t catch that" : "").toUpperCase()
        color: vv.mode === "miss" || vv.stage === "off" ? Qt.rgba(200 / 255, 196 / 255, 192 / 255, 0.7) : Qt.rgba(1, 226 / 255, 196 / 255, 0.85)
        font.family: Theme.face; font.pixelSize: 24; font.weight: Font.Medium; font.letterSpacing: 5.3
        renderType: Text.QtRendering
        opacity: vv.mode === "done" ? 0 : beat
        property real beat: 1
        Behavior on opacity { NumberAnimation { duration: 350 } }
        SequentialAnimation on beat {
            running: vv.active && (vv.mode === "listen" || vv.mode === "think"); loops: Animation.Infinite
            onRunningChanged: if (!running) lab.beat = 1
            NumberAnimation { from: 1; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.45; to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }
    WordFlow {
        id: words
        x: vv.px(124); y: vv.py(98); width: 320 * vv.s; height: 160 * vv.s
        size: vv.heard.length > 48 ? 53 : 67
        color: vv.mode === "miss" ? Qt.rgba(1, 240 / 255, 225 / 255, 0.6) : Qt.rgba(1, 248 / 255, 240 / 255, 1)
        opacity: vv.mode === "done" || vv.mode === "gone" ? 0 : vv.mode === "think" ? 0.7 : 1
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    }
    // the phone's hint under the window, only when it has just woken
    Text {
        x: 0; width: vv.width; y: vv.py(296)
        horizontalAlignment: Text.AlignHCenter
        text: "“make it cosy”  ·  “what’s the weather tomorrow?”"
        color: Qt.rgba(1, 232 / 255, 210 / 255, 0.38)
        font.family: Theme.face; font.pixelSize: 29
        renderType: Text.QtRendering
        opacity: vv.stage === "wake" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    // ---------------------------------------------------------------- the answer, on the window
    Text {
        id: qSmall
        x: vv.px(vv.winR[0] + 32); y: vv.py(58); width: (vv.winR[2] - 64) * vv.s
        text: vv.heard
        color: Qt.rgba(1, 240 / 255, 225 / 255, 0.72)
        font.family: Theme.face; font.pixelSize: 31
        renderType: Text.QtRendering
        elide: Text.ElideRight
        opacity: vv.mode === "done" && vv.heard ? 1 : 0
        Behavior on x { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } }
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: qSmall.opacity < 0.5 ? 200 : 0 } NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } }
    }
    Text {
        id: res
        readonly property bool missing: vv.mode === "miss"
        x: missing ? vv.px(84) : vv.px(vv.winR[0] + 32)
        width: missing ? 400 * vv.s : (vv.winR[2] - 64) * vv.s
        y: missing ? vv.py(320 - 30) - height : vv.py(86) + shift
        height: Math.min(missing ? 40 * vv.s : (vv.winR[3] - 90) * vv.s, implicitHeight)
        text: missing ? (vv.v.line || "") : vv.answer
        horizontalAlignment: missing ? Text.AlignHCenter : Text.AlignLeft
        wrapMode: Text.WordWrap; elide: Text.ElideRight
        color: Qt.rgba(1, 248 / 255, 240 / 255, 1)
        font.family: Theme.face; font.pixelSize: missing ? 36 : vv.answer.length > 150 ? 43 : 50
        font.weight: missing ? Font.Normal : Font.Medium
        lineHeight: 1.08
        renderType: Text.QtRendering
        property real shift: vv.mode === "done" ? 0 : 24
        Behavior on shift { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        opacity: (vv.mode === "done" && vv.answer) || (missing && text) ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: res.opacity < 0.5 ? 200 : 0 } NumberAnimation { duration: 700; easing.type: Easing.OutCubic } } }
    }

    // ---------------------------------------------------------------- the card on the right
    AnswerCard {
        id: cardV
        kind: vv.card || last
        property string last: ""
        onKindChanged: if (vv.card) last = vv.card
        x: vv.px(344) + (vv.card ? 0 : 24 * vv.s)
        y: vv.py(Math.max(40, Math.min(86, (320 - implicitHeight / vv.s) / 2)))
        width: 192 * vv.s
        opacity: vv.card ? 1 : 0
        Behavior on x { SequentialAnimation { PauseAnimation { duration: vv.card ? 300 : 0 } NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] } } }
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: vv.card ? 300 : 0 } NumberAnimation { duration: vv.card ? 900 : 450; easing.type: Easing.OutCubic } } }
    }

    // ---------------------------------------------------------------- what's said, as it changes
    property string lastStage: ""
    function sync() {
        if (!active) return
        // a new turn starts clean: nothing left over from the last question
        if ((stage === "wake" || stage === "follow") && lastStage !== stage) words.clear()
        lastStage = stage
        if (mode === "listen" || mode === "think" || mode === "miss") {
            if (heard) words.say(heard)
            else {
                words.clear()
                words.placeholder = stage === "wake" ? "Go ahead…" : stage === "follow" ? "I’m listening…"
                                  : stage === "miss" ? "I didn’t hear anything." : stage === "off" ? (v.error || "Voice isn’t set up yet") : ""
            }
        }
    }
    onHeardChanged: sync()
    onStageChanged: sync()
    onActiveChanged: if (!active) { words.clear(); cur = 0; thinkMix = 0 } else sync()

    // tapping while it talks, listens or thinks: stop, and drop the answer on its way
    MouseArea { anchors.fill: parent; onClicked: { room.cancelVoice(); vv.close() } }
}
