import QtQuick
import QtQuick.Effects
// A thin line you drag: the song's place, the volume. A 2 px line (22 % white), filled white to the value, a 14 px
// round knob. Takes touches 10 px above and below the line too.
Item {
    id: s
    property real value: 0                 // 0…1
    property bool live: true               // send moved() while dragging (else only released())
    property int every: 100                // at most this often while dragging (ms)
    property bool shadow: false            // a soft shadow under the knob (the song's place has one)
    signal moved(real v)
    signal released(real v)
    readonly property bool dragging: drag.pressed
    property real local: 0
    readonly property real shown: Math.max(0, Math.min(1, drag.pressed ? local : value))
    height: 30
    Rectangle { y: 14; width: parent.width; height: 2; color: Qt.rgba(1, 1, 1, 0.22) }
    Rectangle { y: 14; width: parent.width * s.shown; height: 2; color: "white" }
    RectangularShadow { visible: s.shadow; x: parent.width * s.shown - 7; y: 10; width: 14; height: 14; radius: 7; blur: 8; color: Qt.rgba(0, 0, 0, 0.4) }
    Rectangle {      // the knob grows under your finger while you drag
        x: parent.width * s.shown - 7; y: 8; width: 14; height: 14; radius: 7; color: "white"
        scale: drag.pressed ? 1.45 : 1
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
    }
    Timer { id: throttle; interval: s.every; onTriggered: s.moved(s.local) }
    MouseArea {
        id: drag
        anchors.fill: parent; anchors.topMargin: -10; anchors.bottomMargin: -10
        preventStealing: true
        function at(x) { return Math.max(0, Math.min(1, x / width)) }
        onPressed: (e) => { s.local = at(e.x) }
        onPositionChanged: (e) => { s.local = at(e.x); if (s.live && !throttle.running) throttle.start() }
        onReleased: { throttle.stop(); s.released(s.local) }
    }
}
