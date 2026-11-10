import QtQuick

// When an alarm, a timer or a reminder goes off: full-screen, over everything (standby included), a soft pulse of
// warm light. Alarm: Snooze (9 min) · Stop. Timer: +1 min · Stop. Reminder: Done · Later.
Item {
    id: al
    width: Theme.stageW; height: Theme.stageH
    property var a: room.alert
    readonly property bool showing: a && a.kind !== undefined
    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 300 } }
    property real t: 0
    Timer { interval: 50; repeat: true; running: al.visible; onTriggered: al.t += 0.05 }

    MouseArea { anchors.fill: parent }          // nothing underneath is pressed while it shows
    Rectangle { anchors.fill: parent; anchors.margins: -60; color: "#060505" }
    Glow { anchors.centerIn: parent; width: 1300; height: 1300; color: Theme.warm; strength: 0.16 + 0.1 * (0.5 + 0.5 * Math.sin(al.t * 2.4)) }
    Icon {
        anchors.horizontalCenter: parent.horizontalCenter; y: 170
        name: !al.showing ? "alarm" : al.a.kind === "reminder" ? "check" : al.a.kind === "timer" ? "timer" : "alarm"
        size: 64; color: Theme.accent
    }
    SectionCap { anchors.horizontalCenter: parent.horizontalCenter; y: 272; text: al.showing ? al.a.sub : ""; color: Qt.rgba(1, 207 / 255, 156 / 255, 0.85) }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 320; width: 1100
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: al.showing ? al.a.title : ""
        font.pixelSize: al.showing && al.a.kind === "reminder" ? 72 : 120; font.weight: Font.Light
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: 640; spacing: 20
        Pill {
            width: 260; height: 96; fontSize: 24
            text: !al.showing ? "" : al.a.kind === "alarm" ? "Snooze" : al.a.kind === "timer" ? "+1 min" : "Later"
            onTapped: {
                if (al.a.kind === "alarm") room.snoozeAlert()
                else if (al.a.kind === "timer") { room.startTimer(60, "Timer"); room.stopAlert() }
                else room.stopAlert()
            }
        }
        Pill {
            width: 260; height: 96; fontSize: 24; lit: true
            text: al.showing && al.a.kind === "reminder" ? "Done" : "Stop"
            onTapped: { if (al.a.kind === "reminder") room.toggleReminder(al.a.id); room.stopAlert() }
        }
    }
}
