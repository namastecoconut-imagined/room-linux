import QtQuick
import QtQuick.Controls.Basic

// Reminders, kept on this panel only. Tap the circle to tick one off (tap again to bring it back), hold a row to
// delete it. Due today shows in amber. Add one by tapping (type it — the on-screen keyboard comes up — and pick
// when), or by voice once that's set up.
Item {
    id: rm
    width: Theme.stageW; height: Theme.stageH
    property var list: (room.things.reminders || [])
    signal back()
    signal talk()

    Header { title: "Reminders"; note: "kept on this panel only"; onBack: rm.back() }

    ListView {
        id: lv
        x: 96; y: 160; width: 640; height: 700
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rm.list
        delegate: Item {
            width: lv.width; height: modelData.when ? 112 : 92
            Press {
                x: 0; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56
                onTapped: room.toggleReminder(modelData.id)
                Rectangle {
                    anchors.centerIn: parent; width: 40; height: 40; radius: 20
                    color: modelData.done ? Qt.rgba(1, 190 / 255, 122 / 255, 0.7) : "transparent"
                    border.width: 2; border.color: modelData.done ? Qt.rgba(1, 190 / 255, 122 / 255, 0.7) : Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.35)
                    Icon { anchors.centerIn: parent; visible: modelData.done; name: "check"; size: 22; color: "#111" }
                }
            }
            Press {
                x: 82; width: parent.width - 82; height: parent.height
                pressScale: 1
                onHeld: room.deleteReminder(modelData.id)
                onTapped: room.toggleReminder(modelData.id)
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    T { text: modelData.text; font.pixelSize: 26; font.strikeout: modelData.done; color: modelData.done ? Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.4) : Theme.ink; width: 560 }
                    T { visible: modelData.when !== "" && !modelData.done; text: modelData.when; font.pixelSize: 17; color: modelData.dueNow || modelData.today ? Qt.rgba(1, 190 / 255, 122 / 255, 0.9) : Theme.sub }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
        }
    }
    T { visible: rm.list.length === 0; x: 96; y: 180; text: "Nothing to remember"; font.pixelSize: 28; color: Theme.sub }

    // ---------------------------------------------------------------- add
    Press {
        x: 820; y: 160; width: 452; height: 300
        pressScale: 0.98
        onTapped: adder.show()
        Rectangle { anchors.fill: parent; radius: 28; color: Qt.rgba(1, 1, 1, 0.035); border.color: Qt.rgba(1, 1, 1, 0.06) }
        RoundBtn { x: 32; y: 32; size: 96; icon: "plus"; iconSize: 32; onTapped: adder.show() }
        T { x: 32; y: 156; text: "Add a reminder"; font.pixelSize: 26 }
        T { x: 32; y: 198; width: 390; wrapMode: Text.WordWrap; text: "Tap to type it, or say\n“Alexa, remind me to … at 6”"; font.pixelSize: 18; color: Theme.sub; lineHeight: 1.2 }
    }
    T {
        x: 820; y: 492; width: 452; wrapMode: Text.WordWrap; lineHeight: 1.3
        text: "When one's due, Room chimes and shows it on standby until you tick it off. Hold a reminder to delete it."
        font.pixelSize: 18; color: Theme.sub
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
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.65) }
        Rectangle {
            x: (parent.width - width) / 2; y: 90; width: 840; height: 380; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            SectionCap { x: 40; y: 40; text: "New reminder" }
            TextField {
                id: field
                x: 40; y: 80; width: 760; height: 80
                placeholderText: "Remind me to…"
                font.pixelSize: 30; font.family: Theme.face
                color: Theme.ink; placeholderTextColor: Theme.sub
                background: Rectangle { radius: 18; color: Qt.rgba(1, 1, 1, 0.05) }
                leftPadding: 24
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: save.tapped()
            }
            Row {
                x: 40; y: 188; spacing: 10
                Repeater {
                    model: adder.picks
                    Pill { width: 180; height: 56; fontSize: 17; text: modelData; lit: adder.pick === index; onTapped: adder.pick = index }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 36; spacing: 12
                Pill { width: 150; height: 64; text: "Cancel"; onTapped: adder.open = false }
                Pill {
                    id: save
                    width: 170; height: 64; text: "Add"; lit: true
                    onTapped: { if (field.text.trim() !== "") room.addReminder(field.text, adder.due()); adder.open = false }
                }
            }
        }
    }
}
