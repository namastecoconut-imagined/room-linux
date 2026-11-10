import QtQuick
import QtQuick.Controls.Basic

// Reminders, kept on this panel only. Tap one to tick it off (tap again to bring it back), hold to delete it. Due
// today shows in amber. Add one with the button (type it and pick when). The list sits low on the
// screen and the counts up top, clear of the strips the touch screen doesn't answer in.
Item {
    id: rm
    width: Theme.stageW; height: Theme.stageH
    property var list: (room.things.reminders || [])
    signal back()
    signal talk()

    Header { title: "Reminders"; onBack: rm.back() }
    readonly property var open_: rm.list.filter(function (r) { return !r.done })
    readonly property var dueToday: rm.list.filter(function (r) { return !r.done && (r.today || r.dueNow) })

    // ---------------------------------------------------------------- to read (in the strip that doesn't take touch)
    Column {
        x: 96; y: Theme.deadA0 + 40; spacing: 10
        SectionCap { text: "Reminders" }
        T {
            text: rm.open_.length ? rm.open_.length + (rm.open_.length === 1 ? " to remember" : " to remember") : "Nothing to remember"
            font.pixelSize: 52; font.weight: Font.Light; color: rm.open_.length ? Theme.ink : Theme.sub
        }
        T {
            visible: rm.dueToday.length > 0
            text: rm.dueToday.length + " due today"; font.pixelSize: 22; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.9)
        }
    }
    T {
        x: 744; y: Theme.deadA0 + 60; width: 528; wrapMode: Text.WordWrap; lineHeight: 1.3
        text: "Kept on this panel only. When one's due, Room chimes and shows it on standby until you tick it off. Tap a reminder to tick it, hold to delete it."
        font.pixelSize: 19; color: Theme.sub
    }

    // ---------------------------------------------------------------- add (in the working strip)
    Pill {     // in the top bar
        x: 1296 - width; y: Theme.topY; width: 260; height: 68
        text: "Add a reminder"; icon: "plus"
        onTapped: adder.show()
    }

    // ---------------------------------------------------------------- the list (under the thin strip)
    ListView {
        id: lv
        x: 96; y: Theme.deadB1 + 4; width: 1176; height: 900 - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rm.list
        delegate: Item {
            width: lv.width; height: 100
            Press {
                x: 0; anchors.verticalCenter: parent.verticalCenter; width: 64; height: 64
                onTapped: room.toggleReminder(modelData.id)
                Rectangle {
                    anchors.centerIn: parent; width: 44; height: 44; radius: 22
                    color: modelData.done ? Qt.rgba(1, 190 / 255, 122 / 255, 0.7) : "transparent"
                    border.width: 2; border.color: modelData.done ? Qt.rgba(1, 190 / 255, 122 / 255, 0.7) : Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.35)
                    Icon { anchors.centerIn: parent; visible: modelData.done; name: "check"; size: 22; color: "#111" }
                }
            }
            Press {
                x: 86; width: parent.width - 86; height: parent.height
                pressScale: 1
                onHeld: room.deleteReminder(modelData.id)
                onTapped: room.toggleReminder(modelData.id)
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    T { text: modelData.text; font.pixelSize: 26; font.strikeout: modelData.done; color: modelData.done ? Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.4) : Theme.ink; width: 1000; elide: Text.ElideRight }
                    T { visible: modelData.when !== "" && !modelData.done; text: modelData.when; font.pixelSize: 17; color: modelData.dueNow || modelData.today ? Qt.rgba(1, 190 / 255, 122 / 255, 0.9) : Theme.sub }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
        }
    }

    // ---------------------------------------------------------------- the add sheet
    Item {
        id: adder
        anchors.fill: parent
        property bool open: false
        property int pick: 0
        function show() { field.text = ""; pick = 0; open = true; field.forceActiveFocus() }
        readonly property var picks: ["No time", "In 1 hour", "This evening", "Tomorrow morning"]
        function due() {
            var d = new Date()
            if (pick === 1) return d.getTime() / 1000 + 3600
            if (pick === 2) { d.setHours(d.getHours() >= 18 ? d.getHours() + 1 : 18, 0, 0, 0); return d.getTime() / 1000 }
            if (pick === 3) { d.setDate(d.getDate() + 1); d.setHours(9, 0, 0, 0); return d.getTime() / 1000 }
            return 0
        }
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: adder.open = false }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.9) }
        T { x: 96; y: Theme.deadA0 + 60; text: "New reminder"; font.pixelSize: 44 }
        T { x: 96; y: Theme.deadA0 + 122; text: "Type it, pick when, then Add"; font.pixelSize: 20; color: Theme.sub }
        Rectangle {
            x: (parent.width - width) / 2; y: Theme.deadB1 + 4; width: 1176; height: 900 - y; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            TextField {
                id: field
                x: 40; y: 36; width: 1096; height: 84
                placeholderText: "Remind me to…"
                font.pixelSize: 30; font.family: Theme.face
                color: Theme.ink; placeholderTextColor: Theme.sub
                background: Rectangle { radius: 18; color: Qt.rgba(1, 1, 1, 0.05) }
                leftPadding: 24
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: save.tapped()
            }
            Row {
                x: 40; y: 148; spacing: 12
                Repeater {
                    model: adder.picks
                    Pill { width: 220; height: 68; fontSize: 17; text: modelData; lit: adder.pick === index; onTapped: adder.pick = index }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 36; spacing: 12
                Pill { width: 150; height: 68; text: "Cancel"; onTapped: adder.open = false }
                Pill {
                    id: save
                    width: 170; height: 68; text: "Add"; lit: true
                    onTapped: { if (field.text.trim() !== "") room.addReminder(field.text, adder.due()); adder.open = false }
                }
            }
        }
    }
}
