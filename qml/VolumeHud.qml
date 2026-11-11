import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// The Surface's volume buttons (room-motion.html volH): a slim glass bar at the top centre, 300 × 56 — what it
// controls (the music's volume while something plays, else the speaker), the level as a light line (the sliders'
// style, here only to read), the number. Drops in, and fades away 1.5 s after the last press.
Item {
    id: hud
    width: Theme.stageW; height: Theme.stageH
    property int level: 0
    property string what: ""
    property Item backdrop: null          // what's behind (the stage): the glass blurs it
    Connections {
        target: room
        function onVolumeShown(v, w) { hud.level = v; hud.what = w; cap.shown = true; hide.restart() }
    }
    Timer { id: hide; interval: 1500; onTriggered: cap.shown = false }

    Item {
        id: cap
        property bool shown: false
        x: 534; y: shown ? 40 : 30; width: 300; height: 56
        opacity: shown ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: cap.shown ? 220 : 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

        // the glass: what's behind, blurred, inside the bar
        ShaderEffectSource {
            id: behind
            anchors.fill: parent
            sourceItem: hud.backdrop
            sourceRect: Qt.rect(cap.x, 40, cap.width, cap.height)
            live: cap.visible
            hideSource: false
            visible: false
        }
        Rectangle { id: shape; anchors.fill: parent; radius: 28; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: behind
            visible: hud.backdrop !== null
            blurEnabled: true; blur: 1.0; blurMax: 32
            maskEnabled: true; maskSource: shape
            autoPaddingEnabled: false
        }
        Rectangle {
            anchors.fill: parent; radius: 28
            color: Qt.rgba(20 / 255, 14 / 255, 10 / 255, 0.6)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
        }
        Mono {
            id: lab
            x: 22; anchors.verticalCenter: parent.verticalCenter; size: 12
            text: hud.what === "speaker" ? "Speaker" : "Vol"
        }
        Item {
            id: line
            x: lab.x + lab.width + 16; width: num.x - 16 - x; height: parent.height
            property real f: hud.level / 100
            Behavior on f { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            Rectangle { y: 27; width: parent.width; height: 2; color: Qt.rgba(1, 1, 1, 0.18) }
            Rectangle {
                y: 27; width: parent.width * line.f; height: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 240 / 255, 225 / 255, 0.25) }
                    GradientStop { position: 1; color: "white" }
                }
            }
            Shape {
                id: pt
                x: line.width * line.f - 8; y: 28 - 8; width: 16; height: 16
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 8; centerY: 8; centerRadius: 8; focalX: 8; focalY: 8
                        GradientStop { position: 0; color: "white" }
                        GradientStop { position: 0.28; color: "white" }
                        GradientStop { position: 0.55; color: Qt.rgba(1, 220 / 255, 190 / 255, 0.55) }
                        GradientStop { position: 1; color: Qt.rgba(1, 220 / 255, 190 / 255, 0) }
                    }
                    PathRectangle { x: 0; y: 0; width: 16; height: 16; radius: 8 }
                }
            }
        }
        Mono {
            id: num
            x: parent.width - 22 - width; anchors.verticalCenter: parent.verticalCenter; width: 28
            horizontalAlignment: Text.AlignRight; text: hud.level
        }
    }
    // (for checks: show it on start)
    Component.onCompleted: if (startScreen === "volhud") { hud.level = 67; hud.what = "music"; cap.shown = true }
}
