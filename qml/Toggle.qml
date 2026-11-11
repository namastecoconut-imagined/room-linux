import QtQuick
// The redesign's switch (room-motion.html .sw): 58 × 34, warm when on, the knob glides (0.4 s).
Press {
    id: t
    property bool on: false
    pressScale: 0.95
    width: 58; height: 34
    Rectangle {
        anchors.fill: parent; radius: 17
        color: t.on ? "#ffbe7a" : Qt.rgba(1, 1, 1, 0.2)
        Behavior on color { ColorAnimation { duration: 350 } }
    }
    Rectangle {
        x: t.on ? 28 : 4; y: 4; width: 26; height: 26; radius: 13; color: "white"
        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    }
}
