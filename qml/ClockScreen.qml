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

    Header { title: "Clock"; onBack: cs.back() }

    // ---------------------------------------------------------------- left: the time, timers
    DotText { x: 96; y: 150; pitch: 22; text: Theme.clock(new Date(cs.now * 1000), room.clock24) }
    T { x: 96; y: 330; text: Qt.formatDate(new Date(cs.now * 1000), "dddd d MMMM"); font.pixelSize: 22; color: Theme.sub }

    SectionCap { x: 96; y: 420; text: "Timers" }
    Column {
        x: 96; y: 456; spacing: 14
        Repeater {
            model: cs.timers.slice(0, 2)
            Item {
                width: 520; height: cs.timers.length > 1 ? 104 : 150
                readonly property real frac: modelData.total > 0 ? 1 - modelData.left / modelData.total : 0
                Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.07); border.color: Qt.rgba(1, 1, 1, 0.06) }
                Rectangle { x: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; height: 3; radius: 2; width: (parent.width - 48) * parent.frac; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.7) }
                T {
                    x: 28; y: cs.timers.length > 1 ? 14 : 24
                    text: Theme.countdown(modelData.left)
                    font.pixelSize: cs.timers.length > 1 ? 44 : 58; font.weight: Font.Light
                    color: modelData.paused ? Theme.sub : Theme.ink
                }
                T {
                    x: 30; anchors.bottom: parent.bottom; anchors.bottomMargin: cs.timers.length > 1 ? 16 : 26
                    text: (modelData.label || "Timer") + "  ·  of " + Theme.countdown(modelData.total) + (modelData.paused ? "  ·  paused" : "")
                    font.pixelSize: 17; color: Theme.sub
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                    RoundBtn { size: 60; icon: modelData.paused ? "play" : "pause"; iconSize: 20; onTapped: room.pauseTimer(modelData.id) }
                    RoundBtn { size: 60; icon: "close"; iconSize: 20; onTapped: room.cancelTimer(modelData.id) }
                }
            }
        }
        T { visible: cs.timers.length === 0; text: "No timers running"; font.pixelSize: 24; color: Theme.sub; topPadding: 6; bottomPadding: 10 }
    }
    Row {
        x: 96; y: cs.timers.length === 0 ? 520 : cs.timers.length === 1 ? 630 : 700; spacing: 12
        Repeater {
            model: [["+1 min", 60], ["5 min", 300], ["10 min", 600], ["15 min", 900]]
            Pill {
                width: 118; height: 64; text: modelData[0]; fontSize: 18
                onTapped: index === 0 && cs.timers.length ? room.addTime(cs.timers[0].id, 60) : room.startTimer(modelData[1], "")
            }
        }
    }
    T {
        x: 96; y: cs.timers.length === 0 ? 606 : cs.timers.length === 1 ? 716 : 786
        text: "Or say “Alexa, set a timer for 20 minutes”"; font.pixelSize: 18; color: Theme.sub
    }

    // ---------------------------------------------------------------- right: alarms
    Rectangle { x: 690; y: 150; width: 1; height: 720; color: Qt.rgba(1, 1, 1, 0.06) }
    SectionCap { x: 744; y: 172; text: "Alarms" }
    RoundBtn { x: 1296 - 56; y: 150; size: 56; icon: "plus"; iconSize: 22; onTapped: editor.edit(null) }
    ListView {
        id: alarmList
        x: 744; y: 216; width: 552; height: Math.min(4, Math.max(1, cs.alarms.length)) * 140
        clip: true
        interactive: cs.alarms.length > 4
        boundsBehavior: Flickable.StopAtBounds
        model: cs.alarms
        delegate: Press {
            width: alarmList.width; height: 140
            pressScale: 0.985
            onTapped: editor.edit(modelData)
            Row {
                y: 30
                T { id: at; text: Theme.hm(modelData.h, modelData.m, room.clock24); font.pixelSize: 52; font.weight: Font.Light; color: modelData.on ? Theme.ink : Theme.sub }
                T { anchors.baseline: at.baseline; leftPadding: 8; text: Theme.ampm(modelData.h, room.clock24); font.pixelSize: 22; color: modelData.on ? Theme.ink : Theme.sub }
            }
            T { y: 96; text: modelData.daysText; font.pixelSize: 18; color: Theme.sub }
            Press {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 88; height: 52
                onTapped: room.toggleAlarm(modelData.id)
                Rectangle { anchors.fill: parent; radius: 26; color: modelData.on ? Qt.rgba(1, 190 / 255, 122 / 255, 0.6) : Qt.rgba(1, 1, 1, 0.1) }
                Rectangle {
                    y: 5; x: modelData.on ? parent.width - width - 5 : 5
                    width: 42; height: 42; radius: 21; color: Theme.ink
                    Behavior on x { NumberAnimation { duration: 160 } }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
        }
    }
    T {
        visible: cs.alarms.length === 0
        x: 744; y: 236; text: "No alarms yet — tap + to add one"; font.pixelSize: 24; color: Theme.sub
    }
    T {
        x: 744; y: alarmList.y + alarmList.height + 28; width: 552; wrapMode: Text.WordWrap
        visible: things.nextAlarm && things.nextAlarm.in !== undefined
        text: things.nextAlarm && things.nextAlarm.in ? "Next alarm in " + things.nextAlarm.in + "  ·  lights fade up 10 min before" : ""
        font.pixelSize: 18; color: Theme.sub
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
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.65) }
        Rectangle {
            anchors.centerIn: parent; width: 980; height: 600; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            SectionCap { x: 40; y: 40; text: editor.alarm ? "Change alarm" : "New alarm" }
            component Wheel: Tumbler {
                id: tw
                width: 150; height: 300
                visibleItemCount: 5
                delegate: T {
                    text: tw.fmt(modelData)
                    font.pixelSize: 56; font.weight: Font.Light
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / 2.6
                    color: Theme.ink
                }
                property var fmt: function (v) { return "" + v }
            }
            Rectangle { x: 50; y: 96 + 120; width: 350; height: 60; radius: 14; color: Qt.rgba(1, 1, 1, 0.05) }
            Row {
                x: 60; y: 96; spacing: 10
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
            SectionCap { x: 610; y: 110; text: "Repeat" }
            Grid {
                x: 610; y: 146; columns: 4; spacing: 10
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    Pill {
                        width: 76; height: 56; text: modelData; fontSize: 16
                        lit: editor.days.indexOf(index) >= 0
                        onTapped: {
                            var d = editor.days.slice(), i = d.indexOf(index)
                            if (i >= 0) d.splice(i, 1); else d.push(index)
                            editor.days = d
                        }
                    }
                }
            }
            T { x: 610; y: 290; width: 320; wrapMode: Text.WordWrap; text: editor.days.length ? "" : "No days picked — it rings once"; font.pixelSize: 16; color: Theme.sub }
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
