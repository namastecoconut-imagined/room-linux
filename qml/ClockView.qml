import QtQuick
import QtQuick.Effects

// The Clock screen (room-motion.html fillScreen('clock')). Up top, to read (the touch screen doesn't answer between
// y 118 and 500): the next alarm big on the left, a running timer's countdown big on the right with its progress.
// Below, everything you touch: the running timers' Pause / Resume · +1 min · Cancel and quick timers
// (1 · 5 · 10 · 15 · 25 · 45 min) on the left; every alarm on the right — tap one to change it, its switch to turn it
// on or off. "+ New alarm" is in the top bar (Scene). The editor rises as a sheet: hour and minute steppers (hold to
// run), am / pm, repeat days, Save · Delete · Cancel. Alarms and timers keep running whatever's on screen; when one
// goes off Room shows it full-size, even from standby.
Item {
    id: cv
    width: 1368; height: 912
    property bool shown: false
    property real now: Date.now() / 1000
    readonly property var things: room.things
    readonly property var timers: (things.timers || []).filter(function (t) { return !t.done })
    readonly property var alarms: things.alarms || []
    readonly property var na: things.nextAlarm || ({})
    readonly property var t0: timers.length ? timers[0] : null
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Component.onCompleted: if (startScreen === "clockedit") editor.edit(null)      // (checks)

    // each part rises into place a moment after the one before (the design's 35 ms stagger)
    component Rise: Item {
        id: rz
        property int order: 0
        opacity: cv.shown ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: cv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        transform: Translate {
            y: cv.shown ? 0 : 14
            Behavior on y { SequentialAnimation { PauseAnimation { duration: cv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        }
    }

    // ---------------------------------------------------------------- to read: the next alarm
    Rise {
        order: 0
        x: 44; y: 126; width: 600; height: 240
        Mono { id: naLbl; text: "Next alarm"; color: Theme.w62 }
        Row {
            y: 26
            Serif { id: naT; text: cv.na.h !== undefined ? Theme.hm(cv.na.h, cv.na.m, room.clock24) : "—"; font.pixelSize: 150 }
            Serif {
                visible: cv.na.h !== undefined && !room.clock24
                text: " " + Theme.ampm(cv.na.h, false); font.pixelSize: 52
                css: false; anchors.baseline: naT.baseline; transform: Translate { y: naT.shift }
            }
        }
        Mono { y: 26 + 150 + 10; color: Theme.w62; text: cv.na.h !== undefined ? (cv.na.in ? "In " + cv.na.in : "") : "No alarms on" }
    }

    // ---------------------------------------------------------------- to read: the running timer
    Rise {
        order: 1
        x: 1324 - 560; y: 126; width: 560; height: 240
        Mono {
            id: tLbl
            anchors.right: parent.right
            color: Theme.w62
            text: cv.t0 ? "Timer" + (cv.t0.label ? " · " + cv.t0.label : "") + (cv.t0.paused ? " · paused" : "") : "Timers"
        }
        Serif {
            id: tBig
            anchors.right: parent.right; y: 26
            text: cv.t0 ? Theme.countdown(cv.t0.left) : "00:00"
            font.pixelSize: 150
            color: cv.t0 ? Theme.timer2 : Qt.rgba(1, 1, 1, 0.35)
        }
        Item {
            y: 26 + 150 + 18; width: parent.width; height: 2
            opacity: cv.t0 ? 1 : 0
            readonly property real f: cv.t0 && cv.t0.total > 0 ? Math.max(0, Math.min(1, 1 - cv.t0.left / cv.t0.total)) : 0
            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.2) }
            RectangularShadow { width: parent.width * parent.f; height: 2; blur: 10; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.7); visible: width > 1 }
            Rectangle { width: parent.width * parent.f; height: 2; color: Theme.timer }
        }
    }

    // ---------------------------------------------------------------- timers (lower left)
    Rise {
        order: 2
        x: 44; y: 524; width: 620; height: 360
        Mono { text: "Timers"; color: Theme.w62 }
        Column {
            id: trows
            y: 32; spacing: 8
            Repeater {
                model: cv.timers.slice(0, 2)
                Row {
                    spacing: 10; height: 44
                    Mono {      // (the second timer says which it is; the first is named up top)
                        visible: index > 0
                        anchors.verticalCenter: parent.verticalCenter; rightPadding: 6
                        text: (modelData.label || "Timer") + " · " + Theme.countdown(modelData.left)
                        color: Theme.timer
                    }
                    Chip { text: modelData.paused ? "Resume" : "Pause"; onTapped: room.pauseTimer(modelData.id) }
                    Chip { text: "+1 min"; onTapped: room.addTime(modelData.id, 60) }
                    Chip { text: "Cancel"; onTapped: room.cancelTimer(modelData.id) }
                }
            }
            Mono { visible: cv.timers.length === 0; height: 44; verticalAlignment: Text.AlignVCenter; text: "No timer running"; color: Theme.w62 }
        }
        Mono { id: startCap; y: trows.y + trows.height + 50; text: "Start a timer"; color: Theme.w62 }
        Row {
            id: presets
            y: startCap.y + 32; spacing: 10
            Repeater {
                model: [1, 5, 10, 15, 25, 45]
                Chip { text: modelData + " min"; onTapped: room.startTimer(modelData * 60, "") }
            }
        }
        Mono {
            y: presets.y + 94; width: 600; color: Theme.w62
            visible: y + height < 360
            text: "Or say “Alexa, set a 10 minute timer for pasta”."
        }
    }

    // ---------------------------------------------------------------- alarms (lower right)
    Rise {
        order: 3
        x: 744; y: 524; width: 580; height: 352
        Mono { text: "Alarms"; color: Theme.w62 }
        Mono { anchors.right: parent.right; text: cv.alarms.length ? "Tap one to edit" : ""; color: Theme.w62 }
        Mono { y: 46; visible: cv.alarms.length === 0; text: "No alarms yet · + New alarm, up top"; color: Theme.w62 }
        ListView {
            id: alist
            // where the cats can be: each alarm's line, between its time and its switch
            function catSpots(sc, out) {
                for (var i = 0; i < count && i < 4; i++) {
                    var a = alist.mapToItem(sc, 230, (i + 1) * pitch - contentY)
                    if (a.y < alist.mapToItem(sc, 0, height).y) out.push({ id: "alarm" + i, x0: a.x, x1: a.x + width - 230 - 110, y: a.y })
                }
            }
            y: 32; width: parent.width; height: parent.height - 32
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: cv.alarms
            readonly property real pitch: Math.max(78, Math.min(92, height / Math.max(1, count)))
            delegate: Item {
                width: alist.width; height: alist.pitch
                opacity: modelData.on ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: 400 } }
                Press {
                    width: parent.width - 90; height: parent.height - 4; pressScale: 0.985
                    onTapped: editor.edit(modelData)
                    Row {
                        y: 8
                        Serif { id: at; text: Theme.hm(modelData.h, modelData.m, room.clock24); font.pixelSize: 48 }
                        Serif {
                            visible: !room.clock24
                            text: " " + Theme.ampm(modelData.h, false); font.pixelSize: 24
                            css: false; anchors.baseline: at.baseline; transform: Translate { y: at.shift }
                        }
                    }
                    Mono { y: 62; size: 12; color: Theme.w62; text: modelData.daysText || "" }
                }
                Toggle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    on: modelData.on
                    onTapped: room.toggleAlarm(modelData.id)
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
            }
        }
    }

    // ---------------------------------------------------------------- add / change an alarm
    // where the cats can be: the next alarm's and the timer's numbers (lying down: the top bar's just above), the
    // alarms' lines, the bottom edge on the left
    function catSpots(sc, out) {
        if (na.h !== undefined) sc.catDigits(naT, "alarmT", true, out, naLbl)
        sc.catDigits(tBig, "timerT", true, out, tLbl)
        alist.catSpots(sc, out)
        out.push({ id: "floor", x0: 100, x1: 680, floor: true })
    }
    readonly property bool sheetUp: editor.open            // (the cats: up onto its top edge)
    readonly property real sheetTop: editor.paneTop
    SheetFrame {
        id: editor
        paneY: 520
        onClose: open = false
        property var alarm: null
        property int h: 7
        property int m: 0
        property var days: []
        function edit(a) {
            alarm = a
            h = a ? a.h : 7; m = a ? a.m : 0
            days = a ? a.days.slice() : [0, 1, 2, 3, 4]
            open = true
        }
        function step(which, d) {
            if (which === "h") h = (h + d + 24) % 24
            else m = (m + d + 60) % 60
        }

        Mono { x: 36; y: 28; text: editor.alarm ? "Edit alarm" : "New alarm"; color: Theme.w62 }

        // a stepper: ▲ the number ▼ — tap for one, hold to run (minutes in fives)
        component Arrow: Chip {
            id: ar
            property string which: "h"
            property int dir: 1
            padX: 26; holdMs: 450
            text: dir > 0 ? "▲" : "▼"
            onTapped: editor.step(which, dir)
            onHeld: run.start()
            Timer {
                id: run
                interval: ar.which === "m" ? 140 : 200; repeat: true
                onTriggered: if (ar.pressed) editor.step(ar.which, ar.dir * (ar.which === "m" ? 5 : 1)); else stop()
            }
        }
        component Stepper: Column {
            id: st
            property string which: "h"
            property int value: 0
            spacing: 4
            Arrow { which: st.which; dir: 1; anchors.horizontalCenter: parent.horizontalCenter }
            Serif {
                width: 130; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 96
                text: st.which === "h" ? (room.clock24 ? Theme.two(st.value) : "" + ((st.value % 12) || 12)) : Theme.two(st.value)
            }
            Arrow { which: st.which; dir: -1; anchors.horizontalCenter: parent.horizontalCenter }
        }
        Row {
            x: 36; y: 62; spacing: 18
            Stepper { which: "h"; value: editor.h }
            Serif { text: ":"; font.pixelSize: 80; anchors.verticalCenter: parent.verticalCenter }
            Stepper { which: "m"; value: editor.m }
            Chip {
                visible: !room.clock24
                anchors.verticalCenter: parent.verticalCenter
                text: editor.h < 12 ? "am" : "pm"
                onTapped: editor.h = (editor.h + 12) % 24
            }
        }
        Item {
            x: 36 + 560; y: 62; width: 1280 - 36 - 560 - 36; height: 260
            Mono { text: "Repeat"; color: Theme.w62 }
            Row {
                y: 30; spacing: 8
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    Chip {
                        width: 52; text: modelData
                        warm: editor.days.indexOf(index) >= 0
                        onTapped: {
                            var d = editor.days.slice(), i = d.indexOf(index)
                            if (i >= 0) d.splice(i, 1); else { d.push(index); d.sort() }
                            editor.days = d
                        }
                    }
                }
            }
            Mono { y: 92; color: Theme.w62; text: editor.days.length ? "" : "No days picked: it rings once" }
            Row {
                y: 160; spacing: 10
                Chip {
                    solid: true; text: "Save"
                    onTapped: {
                        if (editor.alarm) room.setAlarm(editor.alarm.id, editor.h, editor.m, editor.days)
                        else room.addAlarm(editor.h, editor.m, editor.days)
                        editor.open = false
                    }
                }
                Chip { visible: editor.alarm !== null; text: "Delete"; onTapped: { room.deleteAlarm(editor.alarm.id); editor.open = false } }
                Chip { text: "Cancel"; onTapped: editor.open = false }
            }
        }
    }
    function newAlarm() { editor.edit(null) }
    readonly property bool sheetOpen: editor.open
}
