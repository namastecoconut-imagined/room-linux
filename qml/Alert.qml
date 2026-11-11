import QtQuick
import QtQuick.Shapes

// When an alarm, a timer or a reminder goes off (room-motion.html ring()): full-screen, over everything (standby
// included), a warm glow that pulses slowly. Up top, to read: what it is (Good morning · Time's up · Reminder) and,
// big in the serif, the time, the timer's name or the reminder; a line under it. Below, where the screen answers:
// Alarm — Snooze 9 min · Stop. Timer — +1 min · Stop. Reminder — Done · Snooze (10 min). (The design's "or say
// Alexa, stop" isn't shown: the assistant can't stop an alarm or timer yet.)
Item {
    id: al
    width: Theme.stageW; height: Theme.stageH
    property var a: room.alert
    readonly property bool showing: a && a.kind !== undefined
    readonly property string kind: showing ? a.kind : ""
    // the last one shown stays while it fades out
    property var lastA: ({})
    onAChanged: if (showing) lastA = a
    readonly property var shownA: showing ? a : lastA
    visible: opacity > 0.002
    opacity: showing ? 1 : 0
    scale: showing ? 1 : 1.04
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    readonly property var timerOf: {
        var ts = room.things.timers || []
        for (var i = 0; i < ts.length; i++) if (ts[i].id === shownA.id) return ts[i]
        return null
    }
    readonly property var reminderOf: {
        var rs = room.things.reminders || []
        for (var i = 0; i < rs.length; i++) if (rs[i].id === shownA.id) return rs[i]
        return null
    }
    function greeting() {
        if ((shownA.sub || "").indexOf("snoozed") >= 0) return "Snoozed alarm"
        var h = new Date().getHours()
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    function dayLine() {
        var w = room.weather || {}
        var s = Qt.formatDate(new Date(), "dddd")
        if (w.ok === true) {
            s += " · " + w.t + "° and " + (w.d || "").toLowerCase()
            var r = Theme.rainAt(w.hours)
            if (r >= 0) s += ", rain " + (r === 0 ? "now" : "later")
        }
        return s
    }

    MouseArea { anchors.fill: parent }          // nothing underneath is pressed while it shows
    Rectangle { x: -60; y: -60; width: parent.width + 120; height: parent.height + 120; color: "#060505" }

    // the warm glow, pulsing (1.6 s each way)
    Shape {
        id: glow
        width: 1400; height: 1400
        x: (al.width - width) / 2; y: al.height * 0.4 - height / 2
        preferredRendererType: Shape.CurveRenderer
        property real k: 0
        SequentialAnimation on k {
            running: al.visible; loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 1600; easing.type: Easing.InOutSine }
        }
        scale: 0.92 + 0.14 * k
        opacity: 0.75 + 0.25 * k
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 700; centerY: 700; centerRadius: 700; focalX: 700; focalY: 700
                GradientStop { position: 0; color: Qt.rgba(1, 170 / 255, 90 / 255, 0.75) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 120 / 255, 60 / 255, 0.25) }
                GradientStop { position: 0.7; color: Qt.rgba(1, 120 / 255, 60 / 255, 0) }
            }
            PathRectangle { x: 0; y: 0; width: 1400; height: 1400; radius: 700 }
        }
    }

    // ---------------------------------------------------------------- to read
    Mono {
        anchors.horizontalCenter: parent.horizontalCenter; y: 150
        color: Theme.timer2
        text: al.shownA.kind === "alarm" ? al.greeting() : al.shownA.kind === "timer" ? "Time's up" : "Reminder"
    }
    Serif {
        anchors.horizontalCenter: parent.horizontalCenter; y: 190
        width: 1240; horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        height: implicitHeight
        font.pixelSize: al.shownA.kind === "reminder" ? 130 : 200
        lineHeight: 0.95
        text: al.shownA.kind === "timer" ? (al.shownA.sub || "Timer") : (al.shownA.title || "")
    }
    Mono {
        anchors.horizontalCenter: parent.horizontalCenter
        y: al.shownA.kind === "reminder" ? 360 : 420
        color: Theme.w62
        text: al.shownA.kind === "alarm" ? al.dayLine()
            : al.shownA.kind === "timer" ? (al.timerOf && al.timerOf.total ? "Your " + Math.round(al.timerOf.total / 60) + " minute timer" : "")
            : al.reminderOf && al.reminderOf.when ? "Due now · " + (al.reminderOf.when.split(" · ").pop()) : "Due now"
    }

    // ---------------------------------------------------------------- what to do
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: 600; spacing: 24
        Chip {
            height: 72; padX: 54; size: 18
            text: al.shownA.kind === "alarm" ? "Snooze 9 min" : al.shownA.kind === "timer" ? "+1 min" : "Done"
            onTapped: {
                if (al.shownA.kind === "alarm") room.snoozeAlert()
                else if (al.shownA.kind === "timer") { room.startTimer(60, al.shownA.sub || "Timer"); room.stopAlert() }
                else { room.toggleReminder(al.shownA.id); room.stopAlert() }
            }
        }
        Chip {
            height: 72; padX: 54; size: 18; solid: true
            text: al.shownA.kind === "reminder" ? "Snooze" : "Stop"
            onTapped: al.shownA.kind === "reminder" ? room.snoozeAlert() : room.stopAlert()
        }
    }
}
