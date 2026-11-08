import QtQuick
// A fat pill slider for brightness: drag anywhere on it. Shows the light's own colour as it fills.
// Sends at most ~8 changes a second while dragging, and the final value on release.
Item {
    id: s
    property int value: 0          // 0 = off
    property color tint: Theme.warm
    property bool on: value > 0
    signal moved(int v)
    property int shown: drag.pressed ? local : value
    property int local: 0
    height: 58
    Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.06) }
    Rectangle {
        height: parent.height; radius: height / 2
        width: s.on || drag.pressed ? Math.max(height, parent.width * s.shown / 100) : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(s.tint.r, s.tint.g, s.tint.b, 0.22) }
            GradientStop { position: 1; color: Qt.rgba(s.tint.r, s.tint.g, s.tint.b, 0.55) }
        }
        Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }
    T {
        anchors.verticalCenter: parent.verticalCenter; x: 22
        text: (s.on || drag.pressed) ? s.shown + "%" : ""
        font.pixelSize: 19
    }
    Timer { id: throttle; interval: 120; onTriggered: s.moved(s.local) }
    MouseArea {
        id: drag
        anchors.fill: parent
        preventStealing: true
        function at(x) { return Math.max(10, Math.min(100, Math.round(x / width * 100))) }
        onPressed: (e) => { s.local = at(e.x) }
        onPositionChanged: (e) => { s.local = at(e.x); if (!throttle.running) throttle.start() }
        onReleased: { throttle.stop(); s.moved(s.local) }
    }
}
