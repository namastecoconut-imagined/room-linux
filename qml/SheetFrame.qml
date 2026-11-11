import QtQuick
// A sheet that rises from the bottom over the screen dimmed 55 % (room-motion.html's sheet): the alarm editor, a new
// reminder, "are you sure?". Tap outside to close. Its content goes inside (it's the pane's child).
Item {
    id: sf
    width: 1368; height: 912
    property bool open: false
    property real paneY: 520                // where its top edge sits (the screen answers touch below 500)
    property real paneH: 912 - 32 - paneY
    default property alias content: pane.data
    signal close()
    visible: scrim.opacity > 0.001
    z: 50
    Rectangle {
        id: scrim
        x: -40; y: -40; width: parent.width + 80; height: parent.height + 80
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: sf.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        MouseArea { anchors.fill: parent; enabled: sf.open; onClicked: sf.close() }
    }
    Rectangle {
        id: pane
        x: 44; y: sf.open ? sf.paneY : 960; width: 1280; height: sf.paneH; radius: 26
        Behavior on y { NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        opacity: sf.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        color: Qt.rgba(18 / 255, 14 / 255, 12 / 255, 0.9)          // (no blur behind it here, so a little denser than the design)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
        clip: true
        MouseArea { anchors.fill: parent }          // taps on the sheet don't close it
        Rectangle { x: 18; width: parent.width - 36; y: 1; height: 1; color: Qt.rgba(1, 1, 1, 0.3) }
    }
}
