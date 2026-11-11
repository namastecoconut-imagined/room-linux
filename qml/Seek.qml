import QtQuick
import QtQuick.Effects
// A thin line you drag: the song's place, the volume. A 2 px line (22 % white), filled white to the value, a 14 px
// round knob. Takes touches 10 px above and below the line too.
//
// Steady, not jittery:
//  • the knob eases to your finger when you touch down, and back to the real value if it differs when you let go
//    (it doesn't jump);
//  • while you drag it follows your finger with a little smoothing (this touch screen's readings wobble);
//  • after you let go it holds where you left it until the player reports that value (Spotify takes a second or
//    two — without this the knob snapped back to the old value, then forward again), or for 3 s at most.
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
    property real heldV: -1                 // where you let go, held until the player catches up
    readonly property real target: Math.max(0, Math.min(1, drag.pressed ? local : heldV >= 0 ? heldV : value))
    property real shown: target
    property bool easing: false             // ease only the jumps (touch down, let go, catching up), never the
    Behavior on shown {                     // steady ticking — an always-running easing would redraw nonstop
        enabled: s.easing
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    function ease() { easing = true; easeOff.restart() }
    Timer { id: easeOff; interval: 260; onTriggered: s.easing = false }
    onValueChanged: if (heldV >= 0 && Math.abs(value - heldV) < 0.015) { heldV = -1 }
    Timer { id: hold; interval: 3000; onTriggered: { s.ease(); s.heldV = -1 } }

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
        onPressed: (e) => { hold.stop(); s.heldV = -1; s.ease(); s.local = at(e.x) }
        onPositionChanged: (e) => {
            s.local += (at(e.x) - s.local) * 0.6            // a little smoothing of the wobble
            if (s.live && !throttle.running) throttle.start()
        }
        onReleased: (e) => {
            throttle.stop()
            s.heldV = s.local; hold.restart()
            s.released(s.local)
        }
        onCanceled: { throttle.stop(); s.ease() }
    }
}
