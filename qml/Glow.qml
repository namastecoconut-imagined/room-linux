import QtQuick
import QtQuick.Shapes
// A soft round light: a radial gradient from `color` to nothing. Cheap — no blur pass.
Shape {
    id: g
    property color color: Theme.warm
    property real strength: 0.3
    width: 600; height: 600
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: "transparent"
        fillGradient: RadialGradient {
            centerX: g.width / 2; centerY: g.height / 2; centerRadius: g.width / 2
            focalX: centerX; focalY: centerY
            GradientStop { position: 0; color: Qt.rgba(g.color.r, g.color.g, g.color.b, g.strength) }
            GradientStop { position: 0.45; color: Qt.rgba(g.color.r, g.color.g, g.color.b, g.strength * 0.45) }
            GradientStop { position: 1; color: Qt.rgba(g.color.r, g.color.g, g.color.b, 0) }
        }
        PathRectangle { x: 0; y: 0; width: g.width; height: g.height; radius: g.width / 2 }
    }
    Behavior on color { ColorAnimation { duration: 1200 } }
}
