import QtQuick
import QtQuick.Effects
// Album art with rounded corners; while it loads (or with no art) it's a gradient in the cover's colours.
Item {
    id: c
    property string source: ""
    property var rgb: [201, 185, 163]
    property var rgb2: [44, 40, 34]
    property real radius: 20
    Rectangle {
        id: ph
        anchors.fill: parent; radius: c.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Theme.rgb(c.rgb) }
            GradientStop { position: 1; color: Theme.rgb(c.rgb2) }
        }
        visible: img.status !== Image.Ready
    }
    Image {
        id: img
        anchors.fill: parent
        source: c.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        sourceSize: Qt.size(640, 640)
        onStatusChanged: if (status === Image.Error) console.warn("[room] cover didn't load:", source)
    }
    Rectangle { id: mask; anchors.fill: parent; radius: c.radius; visible: false; layer.enabled: true; layer.smooth: true }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: img.status === Image.Ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
