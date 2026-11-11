import QtQuick
import QtQuick.Shapes
// The mic, as a small glowing orb (blue-white) that swells with your voice: tap it and Room listens.
Item {
    id: o
    property real voice: 0                 // 0…1 while it listens
    property bool listening: false
    property bool ready: true              // the assistant is running
    signal tapped()
    width: 60; height: 60
    readonly property real k: 1 + o.voice * 0.5 + (o.listening ? 0.25 : 0)
    // the glow round it (box-shadow 0 0 14px 2px, brighter and wider while it listens and as you speak)
    Glow {
        anchors.centerIn: parent
        width: 26 + 2 * (16 + o.voice * 30 + (o.listening ? 8 : 0)); height: width
        color: "#8cbeff"; strength: (o.listening ? 0.75 : 0.45) * (o.ready ? 1 : 0.5)
    }
    Shape {
        anchors.centerIn: parent; width: 26; height: 26
        scale: o.k * (ma.pressed ? 0.94 : 1)
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        opacity: o.ready ? 1 : 0.5
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {        // radial-gradient(circle at 40% 35%, #e9f6ff, #8fc3ff 45%, transparent 72%)
                centerX: 10.4; centerY: 9.1; centerRadius: 23; focalX: 10.4; focalY: 9.1
                GradientStop { position: 0; color: "#e9f6ff" }
                GradientStop { position: 0.45; color: "#8fc3ff" }
                GradientStop { position: 0.72; color: Qt.rgba(120 / 255, 180 / 255, 1, 0) }
            }
            PathRectangle { x: 0; y: 0; width: 26; height: 26; radius: 13 }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; onClicked: o.tapped() }
}
