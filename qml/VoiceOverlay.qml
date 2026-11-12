import QtQuick
import QtQuick.Effects

// The voice assistant on screen (room-motion.html askAlexa): it takes the top band — the part of the screen you only
// read — and leaves what's below it to touch. A dark veil settles over the top (fading out lower down) and a line of
// light runs across at y 516 with a soft glow under it (shaders/horizon.frag), in each state's colours: cool blue and
// mint while it listens (the glow follows your voice), violet and coral drifting sideways while it thinks, amber and
// coral while Room answers. Your words come in big and centred, one at a time; when Room answers they move up into
// the status line ("● Room   You · …") and the answer comes in word by word on the left, a card on the right for what
// it found or did (VoiceCard), and buttons for what to do next under the line (Open weather · Pause · Open the
// player …). It closes a while after Room's done — longer when there's something to do with the card — when you tap
// the veil, or with Done / Cancel (the touch screen doesn't answer between y 118 and 500, so the buttons sit under
// the line).
Item {
    id: vo
    width: Theme.stageW; height: Theme.stageH
    property bool active: false
    signal close()
    signal go(string where, string arg)     // open a screen (weather · clock · music · room)
    signal touched()                        // a button was used: stay a while longer

    readonly property var v: room.voice
    readonly property string st: v.state || "off"
    readonly property string stage: v.stage || "idle"
    readonly property string mode: st === "listening" ? "listen" : st === "thinking" ? "think"
                                  : st === "speaking" ? "speak" : stage === "miss" ? "miss" : (v.reply || v.line) ? "done" : "gone"
    readonly property string heard: v.heard || ""
    readonly property string answer: v.reply || v.line || ""
    readonly property bool answering: mode === "speak" || mode === "done"
    readonly property bool replying: answering && answer !== ""
    readonly property bool error: stage === "error"
    readonly property var lit: v.lit || []
    readonly property bool forReminder: v.about === "reminder"     // the Reminders screen's + Add a reminder
    readonly property string cardKind: replying && !error ? (v.reminded ? "reminder" : v.card || (lit.length ? "lights" : "")) : ""
    // how long it stays once Room's finished
    readonly property int holdMs: mode === "miss" ? 2600 : replying ? (cardKind !== "" ? 14000 : 8000) : 300

    // the timer the card shows (the newest): only what the buttons need, so they aren't rebuilt every second
    readonly property var timers: (room.things.timers || []).filter(function (t) { return !t.done })
    readonly property string tmrId: timers.length ? timers[timers.length - 1].id : ""
    readonly property bool tmrPaused: timers.length ? timers[timers.length - 1].paused === true : false

    // ---------------------------------------------------------------- the voice, smoothed (drives the light)
    property real phase: 0
    property real lv: 0             // 0…1
    property real drift: 0          // px sideways
    Timer {
        interval: 33; repeat: true; running: vo.active && vo.visible && vo.mode !== "gone"
        onTriggered: {
            vo.phase += 0.033
            var want = vo.mode === "listen" ? Math.min(1, room.voiceLevel * 1.3)
                     : vo.mode === "think" ? 0.35 + 0.25 * Math.sin(vo.phase * 5.5)
                     : vo.mode === "speak" ? 0.3 + 0.45 * Math.min(1, room.level * 1.2) + 0.06 * Math.sin(vo.phase * 3.8)
                     : vo.mode === "done" ? 0.3 + 0.05 * Math.sin(vo.phase * 1.6) : 0.12
            vo.lv += (want - vo.lv) * (want > vo.lv ? 0.3 : 0.08)
            var d = vo.mode === "think" ? Math.sin(vo.phase * 2.5) * 120 : 0
            vo.drift += (d - vo.drift) * 0.06
        }
    }

    // each state's light: [the light, its edge]
    readonly property var look: mode === "listen" && stage === "follow" ? [Qt.rgba(110 / 255, 232 / 255, 210 / 255, 0.92), Qt.rgba(130 / 255, 195 / 255, 1, 0.5)]
                              : mode === "listen" || mode === "miss" ? [Qt.rgba(130 / 255, 195 / 255, 1, 0.95), Qt.rgba(110 / 255, 232 / 255, 210 / 255, 0.55)]
                              : mode === "think" ? [Qt.rgba(165 / 255, 160 / 255, 1, 0.9), Qt.rgba(1, 150 / 255, 140 / 255, 0.45)]
                              : error ? [Qt.rgba(1, 140 / 255, 120 / 255, 0.9), Qt.rgba(1, 96 / 255, 88 / 255, 0.45)]
                              : [Qt.rgba(1, 192 / 255, 125 / 255, 0.95), Qt.rgba(1, 118 / 255, 92 / 255, 0.55)]
    readonly property color dot: Qt.rgba(look[0].r, look[0].g, look[0].b, 1)

    // ---------------------------------------------------------------- the veil over the top band (tap it to close)
    MouseArea {
        x: -60; y: -60; width: vo.width + 120; height: 540 + 60
        enabled: vo.mode !== "gone"
        onClicked: { room.cancelVoice(); vo.close() }
    }
    MouseArea {             // round the buttons: a near miss does nothing (rather than closing it, or pressing Home)
        x: -60; y: 540; width: vo.width + 120; height: 150
        enabled: vo.mode !== "gone"
    }
    Rectangle {
        x: -60; y: -60; width: vo.width + 120; height: 690 + 60
        opacity: vo.mode === "gone" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(6 / 255, 4 / 255, 3 / 255, 0.96) }
            GradientStop { position: 0.64; color: Qt.rgba(6 / 255, 4 / 255, 3 / 255, 0.93) }
            GradientStop { position: 0.8; color: Qt.rgba(6 / 255, 4 / 255, 3 / 255, 0.66) }
            GradientStop { position: 0.9; color: Qt.rgba(6 / 255, 4 / 255, 3 / 255, 0.28) }
            GradientStop { position: 1; color: Qt.rgba(6 / 255, 4 / 255, 3 / 255, 0) }
        }
    }

    // ---------------------------------------------------------------- the light: a line at y 516, a glow under it
    ShaderEffect {
        x: 0; y: 280; width: vo.width; height: 520
        opacity: vo.mode === "gone" ? 0 : vo.mode === "miss" ? 0.5 : 1
        Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        visible: opacity > 0.002
        property size res: Qt.size(width, height)
        property real lineY: 516 - y
        property real v: vo.lv
        property real shift: vo.drift
        property real lineOn: 0.9
        property color c0: vo.look[0]
        property color c1: vo.look[1]
        Behavior on c0 { ColorAnimation { duration: 1200 } }
        Behavior on c1 { ColorAnimation { duration: 1200 } }
        fragmentShader: shaderDir + "horizon.frag.qsb"
    }

    // ---------------------------------------------------------------- the status line: ● Listening · Thinking · Room
    Row {
        x: 44; y: 130; height: 22; spacing: 12
        opacity: vo.mode === "gone" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 500 } }
        Item {
            width: 10; height: 22
            RectangularShadow { anchors.centerIn: parent; width: 10; height: 10; radius: 5; blur: 12; color: vo.dot }
            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: vo.dot }
        }
        Mono {
            anchors.verticalCenter: parent.verticalCenter
            text: vo.mode === "listen" ? (vo.stage === "follow" ? "Go on" : "Listening") : vo.mode === "think" ? "Thinking" : "Room"
        }
        Mono {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 6; width: Math.min(implicitWidth, 1100)
            color: Theme.w62
            opacity: vo.answering && vo.heard ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
            text: "You · " + vo.heard
        }
    }

    // ---------------------------------------------------------------- your words: big and centred
    Serif {
        x: 44; y: 222; width: 1280; horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 40; color: Qt.rgba(1, 1, 1, 0.6)
        text: vo.mode === "miss" ? "Sorry, I didn’t catch that" : vo.stage === "follow" ? "Go on…"
              : vo.forReminder ? "What should I remind you about?" : "Listening…"
        opacity: (vo.mode === "listen" && !vo.heard) || vo.mode === "miss" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }
    Words {
        id: you
        x: 44; y: 214; width: 1280
        centre: true; size: 72; minSize: 44; leading: 1.08; maxHeight: 250; gap: 140
        text: vo.heard
        opacity: vo.mode === "listen" || vo.mode === "think" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: vo.answering ? 260 : 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        transform: Translate {
            y: vo.answering ? -14 : 0
            Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        }
    }

    // ---------------------------------------------------------------- Room's answer, and the card beside it
    // (the answer starts in the left column, as if a card were coming — it usually turns up a moment after Room starts
    // talking; once the whole answer's in without one, it widens)
    readonly property bool wide: replying && cardKind === "" && (v.line || "") !== ""
    Words {
        id: said
        x: 44; y: 186
        width: vo.wide ? 1100 : 720
        size: vo.wide ? 60 : 50; minSize: 30; leading: 1.14; maxHeight: 300; gap: 85
        text: vo.answering ? vo.answer : ""
        opacity: vo.answering ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }
    }
    property bool cardIn: false
    property string shownKind: ""
    onCardKindChanged: {
        if (cardKind !== "") { shownKind = cardKind; if (replying && !cardIn) cardWait.restart() }
        else cardIn = false
    }
    Timer { id: cardWait; interval: 380; onTriggered: vo.cardIn = vo.cardKind !== "" }
    VoiceCard {
        x: 812; y: 150
        kind: vo.shownKind
        lit: vo.lit
        reminded: vo.v.reminded || ""
        opacity: vo.cardIn ? 1 : 0
        visible: opacity > 0.002
        scale: vo.cardIn ? 1 : 0.98
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        Behavior on scale { NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        transform: Translate {
            y: vo.cardIn ? 0 : 16
            Behavior on y { NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        }
    }

    // ---------------------------------------------------------------- what to do next (under the line)
    property bool chipsIn: false
    onReplyingChanged: {
        chipsIn = false
        if (replying) { chipWait.restart(); if (cardKind !== "") cardWait.restart() }
        else cardIn = false
    }
    Timer { id: chipWait; interval: 700; onTriggered: vo.chipsIn = vo.replying }
    readonly property var acts: {
        if (!replying) return []
        if (error) return [["Try again", "listen"], ["Done", "done"]]
        switch (cardKind) {
        case "weather": case "forecast": case "air": return [["Open weather", "weather"], ["Done", "done"]]
        case "timer": return tmrId !== "" ? [[tmrPaused ? "Resume" : "Pause", "pause"], ["+1 min", "plus"], ["Cancel timer", "cancelT"]]
                                          : [["Open clock", "clock"], ["Done", "done"]]
        case "music": return [["Open the player", "player"], ["Skip", "skip"], ["Done", "done"]]
        case "alarm": return [["Open clock", "clock"], ["Done", "done"]]
        case "lights": return lit.length === 1 ? [["Open the room", "room"], ["Done", "done"]] : [["Done", "done"]]
        case "schedule": return [["Done", "done"]]
        case "reminder": return [["Open reminders", "reminders"], ["Done", "done"]]
        default: return [["Ask again", "listen"], ["Done", "done"]]
        }
    }
    function act(k) {
        touched()
        if (k === "done" || k === "cancel") { room.cancelVoice(); close() }
        else if (k === "listen") room.listen()
        else if (k === "weather" || k === "clock" || k === "reminders") { close(); go(k, "") }
        else if (k === "player") { close(); go("music", "") }
        else if (k === "room") { close(); go("room", lit[0]) }
        else if (k === "skip") room.next()
        else if (k === "pause") room.pauseTimer(tmrId)
        else if (k === "plus") room.addTime(tmrId, 60)
        else if (k === "cancelT") { room.cancelTimer(tmrId); close() }
    }
    // while it listens or thinks: Cancel, and (just woken) a few things to try
    Row {
        x: 44; y: 572; spacing: 18
        opacity: vo.mode === "listen" || vo.mode === "think" ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Chip { text: "Cancel"; glass: true; onTapped: vo.act("cancel") }
        Mono {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.w62; size: 13
            text: vo.forReminder ? "Say what, and when · “water the plants at six” · “call the bank tomorrow morning”"
                                 : "Try “make it cozy” · “what’s the weather tomorrow?” · “play some Arijit Singh”"
            opacity: vo.mode === "listen" && !vo.heard && vo.stage !== "follow" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }
    Row {
        x: 44; y: 572; spacing: 10
        opacity: vo.chipsIn ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        transform: Translate {
            y: vo.chipsIn ? 0 : 10
            Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        }
        Repeater {
            model: vo.acts
            Chip { text: modelData[0]; solid: index === 0; glass: index > 0; onTapped: vo.act(modelData[1]) }
        }
    }
}
