import QtQuick
// The redesign's pill button (room-motion.html .pill): mono caps in a rounded box with a fine outline; "solid" is
// white with dark type (the main action), "warm" is the warm accent (a chosen option). It dips when tapped.
Press {
    id: c
    property string text: ""
    property bool solid: false
    property bool warm: false
    property real padX: 18
    property real size: 15                  // the type (alerts use larger buttons)
    pressScale: 0.95
    width: lab.implicitWidth + 2 * padX; height: 44
    Rectangle {
        anchors.fill: parent; radius: 9
        color: c.solid ? "white" : c.warm ? "#ffbe7a" : "transparent"
        border.width: c.solid || c.warm ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.24)
        Behavior on color { ColorAnimation { duration: 300 } }
    }
    Mono { id: lab; anchors.centerIn: parent; text: c.text; size: c.size; color: c.solid ? "#1a120c" : c.warm ? "#1a0f08" : "white" }
}
