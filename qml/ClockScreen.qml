import QtQuick
import QtQuick.Controls.Basic

// Clock: the dot clock and date; timers (up to two shown, with quick +1 / 5 / 10 / 15 min); alarms on the right
// with switches. Tap an alarm to change or delete it, + to add one. Alarms and timers keep running whatever screen
// is showing — when one goes off Room shows it full-size, even from standby.
Item {
    id: cs
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var things: room.things
    readonly property var timers: things.timers || []
    readonly property var alarms: things.alarms || []
    signal back()
    Component.onCompleted: if (startScreen === "clockedit") editor.edit(null)      // (checks)

    Header { title: "Clock"; onBack: cs.back() }

    // (the touch screen doesn't respond in two strips — Theme.deadA*, deadB*: only things to read go there)

    // ---------------------------------------------------------------- left: the time (to read), quick timers, timers
    DotText { x: 96; y: Theme.deadA0 + 4; pitch: 22; text: Theme.clock(new Date(cs.now * 1000), room.clock24) }
    T { x: 96; y: Theme.deadA1 - 36; text: Qt.formatDate(new Date(cs.now * 1000), "dddd d MMMM"); font.pixelSize: 22; color: Theme.sub }

    Row {
        x: 96; y: Theme.liveMid - 34; spacing: 12
        Repeater {
            model: [["+1 min", 60], ["5 min", 300], ["10 min", 600], ["15 min", 900]]
            Pill {
                width: 120; height: 68; text: modelData[0]; fontSize: 18
                onTapped: index === 0 && cs.timers.length ? room.addTime(cs.timers[0].id, 60) : room.startTimer(modelData[1], "")
            }
        }
    }

    SectionCap { x: 96; y: Theme.deadB0 + 12; text: "Timers" }
    Column {
        x: 96; y: Theme.deadB1 + 8; spacing: 14
        Repeater {
            model: cs.timers.slice(0, 2)
            Item {
                width: 528; height: cs.timers.length > 1 ? 120 : 160
                readonly property real frac: modelData.total > 0 ? 1 - modelData.left / modelData.total : 0
                Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.07); border.color: Qt.rgba(1, 1, 1, 0.06) }
                Rectangle { x: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; height: 3; radius: 2; width: (parent.width - 48) * parent.frac; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.7) }
                T {
                    x: 28; y: cs.timers.length > 1 ? 16 : 26
                    text: Theme.countdown(modelData.left)
                    font.pixelSize: cs.timers.length > 1 ? 46 : 60; font.weight: Font.Light
                    color: modelData.paused ? Theme.sub : Theme.ink
                }
                T {
                    x: 30; anchors.bottom: parent.bottom; anchors.bottomMargin: cs.timers.length > 1 ? 20 : 28
                    text: (modelData.label || "Timer") + "  ·  of " + Theme.countdown(modelData.total) + (modelData.paused ? "  ·  paused" : "")
                    font.pixelSize: 17; color: Theme.sub
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                    RoundBtn { size: 68; icon: modelData.paused ? "play" : "pause"; iconSize: 22; onTapped: room.pauseTimer(modelData.id) }
                    RoundBtn { size: 68; icon: "close"; iconSize: 22; onTapped: room.cancelTimer(modelData.id) }
                }
            }
        }
        T { visible: cs.timers.length === 0; text: "No timers running"; font.pixelSize: 24; color: Theme.sub; topPadding: 8 }
        T { text: "Or say “Alexa, set a timer for 20 minutes”"; font.pixelSize: 18; color: Theme.sub; topPadding: 10 }
    }

    // ---------------------------------------------------------------- right: the next alarm (to read), new, the list
    Rectangle { x: 690; y: 150; width: 1; height: 720; color: Qt.rgba(1, 1, 1, 0.06) }
    readonly property var na: things.nextAlarm || ({})
    Column {
        x: 744; y: Theme.deadA0 + 26; width: 552; spacing: 10
        SectionCap { text: "Next alarm" }
        Row {
            visible: cs.na.h !== undefined
            T { id: naT; text: cs.na.h !== undefined ? Theme.hm(cs.na.h, cs.na.m, room.clock24) : ""; font.pixelSize: 64; font.weight: Font.Light }
            T { anchors.baseline: naT.baseline; leftPadding: 10; text: cs.na.h !== undefined ? Theme.ampm(cs.na.h, room.clock24) : ""; font.pixelSize: 26 }
        }
        T {
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 20; color: Theme.sub
            text: cs.na.h !== undefined ? "in " + cs.na.in + "  ·  lights fade up 10 min before" : "No alarms on"
        }
    }
    Pill {
        x: 744; y: Theme.liveMid - 34; width: 220; height: 68
        text: "New alarm"; icon: "plus"
        onTapped: editor.edit(null)
    }
    SectionCap { x: 744; y: Theme.deadB0 + 12; text: "Alarms" }
    ListView {
        id: alarmList
        x: 744; y: Theme.deadB1 + 4; width: 552; height: 896 - y
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: cs.alarms
        delegate: Press {
            width: alarmList.width; height: 104
            pressScale: 0.985
            onTapped: editor.edit(modelData)
            Row {
                y: 14
                T { id: at; text: Theme.hm(modelData.h, modelData.m, room.clock24); font.pixelSize: 46; font.weight: Font.Light; color: modelData.on ? Theme.ink : Theme.sub }
                T { anchors.baseline: at.baseline; leftPadding: 8; text: Theme.ampm(modelData.h, room.clock24); font.pixelSize: 20; color: modelData.on ? Theme.ink : Theme.sub }
            }
            T { y: 70; text: modelData.daysText; font.pixelSize: 17; color: Theme.sub }
            Press {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 96; height: 60
                onTapped: room.toggleAlarm(modelData.id)
                Rectangle { anchors.fill: parent; radius: 30; color: modelData.on ? Qt.rgba(1, 190 / 255, 122 / 255, 0.6) : Qt.rgba(1, 1, 1, 0.1) }
                Rectangle {
                    y: 6; x: modelData.on ? parent.width - width - 6 : 6
                    width: 48; height: 48; radius: 24; color: Theme.ink
                    Behavior on x { NumberAnimation { duration: 160 } }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
        }
    }
    T {
        visible: cs.alarms.length === 0
        x: 744; y: Theme.deadB1 + 24; text: "No alarms yet"; font.pixelSize: 24; color: Theme.sub
    }

    // ---------------------------------------------------------------- add / change an alarm
    Item {
        id: editor
        anchors.fill: parent
        property bool open: false
        property var alarm: null
        property var days: []
        property bool pm: false
        function edit(a) {
            alarm = a
            var h = a ? a.h : 7, m = a ? a.m : 0
            days = a ? a.days.slice() : [0, 1, 2, 3, 4]
            pm = h >= 12
            hourT.currentIndex = room.clock24 ? h : ((h % 12) || 12) - 1
            minT.currentIndex = m
            open = true
        }
        function hour() { return room.clock24 ? hourT.currentIndex : ((hourT.currentIndex + 1) % 12) + (pm ? 12 : 0) }
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: editor.open = false }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.9) }
        T {   // (to read, up in the strip that doesn't take touch)
            x: 96; y: Theme.deadA0 + 60; font.pixelSize: 44
            text: (editor.alarm ? "Change alarm" : "New alarm")
        }
        T { x: 96; y: Theme.deadA0 + 122; font.pixelSize: 20; color: Theme.sub; text: "Turn the wheels to set the time" }
        Rectangle {
            x: 64; y: Theme.deadB1 + 4; width: 1240; height: 900 - y; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            component Wheel: Tumbler {
                id: tw
                width: 150; height: 228
                visibleItemCount: 3
                delegate: T {
                    text: tw.fmt(modelData)
                    font.pixelSize: 56; font.weight: Font.Light
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / 2.6
                    color: Theme.ink
                }
                property var fmt: function (v) { return "" + v }
            }
            Rectangle { x: 50; y: 40 + 84; width: 350; height: 60; radius: 14; color: Qt.rgba(1, 1, 1, 0.05) }
            Row {
                x: 60; y: 40; spacing: 10
                Wheel { id: hourT; model: room.clock24 ? 24 : 12; fmt: function (v) { return room.clock24 ? Theme.two(v) : "" + (v + 1) } }
                T { text: ":"; font.pixelSize: 56; font.weight: Font.Light; anchors.verticalCenter: parent.verticalCenter }
                Wheel { id: minT; model: 60; fmt: function (v) { return Theme.two(v) } }
                Column {
                    visible: !room.clock24
                    anchors.verticalCenter: parent.verticalCenter; spacing: 12; leftPadding: 20
                    Pill { width: 96; height: 60; text: "am"; lit: !editor.pm; onTapped: editor.pm = false }
                    Pill { width: 96; height: 60; text: "pm"; lit: editor.pm; onTapped: editor.pm = true }
                }
            }
            SectionCap { x: 640; y: 40; text: "Repeat" }
            Grid {
                x: 640; y: 76; columns: 7; spacing: 8
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    Pill {
                        width: 74; height: 64; text: modelData; fontSize: 17
                        lit: editor.days.indexOf(index) >= 0
                        onTapped: {
                            var d = editor.days.slice(), i = d.indexOf(index)
                            if (i >= 0) d.splice(i, 1); else d.push(index)
                            editor.days = d
                        }
                    }
                }
            }
            T { x: 640; y: 156; width: 560; wrapMode: Text.WordWrap; text: editor.days.length ? "" : "No days picked — it rings once"; font.pixelSize: 16; color: Theme.sub }
            Row {
                x: 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 40; spacing: 12
                Pill { visible: editor.alarm !== null; width: 150; height: 68; text: "Delete"; icon: "trash"; onTapped: { room.deleteAlarm(editor.alarm.id); editor.open = false } }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 40; spacing: 12
                Pill { width: 150; height: 68; text: "Cancel"; onTapped: editor.open = false }
                Pill {
                    width: 170; height: 68; text: "Save"; lit: true
                    onTapped: {
                        if (editor.alarm) room.setAlarm(editor.alarm.id, editor.hour(), minT.currentIndex, editor.days)
                        else room.addAlarm(editor.hour(), minT.currentIndex, editor.days)
                        editor.open = false
                    }
                }
            }
        }
    }
}
