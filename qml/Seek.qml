import QtQuick
import QtQuick.Shapes
// A slider in the "light point" style: a hairline (18 % white), lit to the value with a line that brightens
// towards the playhead, and the playhead itself a soft glow — the same language as the rooms' light lines. While you
// drag, the glow grows and the value (if given) floats above it. Takes touches 10 px above and below the line too.
//
// Steady, not jittery:
//  • it eases to your finger when you touch down, and back to the real value if it differs when you let go
//    (it doesn't jump);
//  • while you drag it follows your finger with a little smoothing (this touch screen's readings wobble);
//  • after you let go it holds where you left it until the player reports that value (Spotify takes a second or
//    two — without this it snapped back to the old value, then forward again), or for 3 s at most.
Item {
    id: s
    property real value: 0                 // 0…1
    property bool live: true               // send moved() while dragging (else only released())
    property int every: 100                // at most this often while dragging (ms)
    property bool shadow: false            // (unused in this style; kept for callers)
    property string label: ""              // shown above the light while you drag (the time, the volume)
    property color tint: Qt.rgba(1, 220 / 255, 190 / 255, 1)    // the glow's warm edge
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
    Rectangle { y: 14; width: parent.width; height: 2; color: Qt.rgba(1, 1, 1, 0.18) }
    Rectangle {
        y: 14; width: parent.width * s.shown; height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(1, 240 / 255, 225 / 255, 0.25) }
            GradientStop { position: 1; color: "white" }
        }
    }
    // the light: white at its heart, a warm halo, gone at its edge
    Shape {
        id: light
        property real d: s.dragging ? 30 : 17
        Behavior on d { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        x: parent.width * s.shown - d / 2; y: 15 - d / 2; width: d; height: d
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: light.d / 2; centerY: light.d / 2; centerRadius: light.d / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: "white" }
                GradientStop { position: 0.28; color: "white" }
                GradientStop { position: 0.55; color: Qt.rgba(s.tint.r, s.tint.g, s.tint.b, 0.55) }
                GradientStop { position: 1; color: Qt.rgba(s.tint.r, s.tint.g, s.tint.b, 0) }
            }
            PathRectangle { x: 0; y: 0; width: light.d; height: light.d; radius: light.d / 2 }
        }
    }
    Mono {
        visible: s.label !== ""
        opacity: s.dragging ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        x: parent.width * s.shown - width / 2; y: -18
        size: 15; color: "white"; text: s.label
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
