import QtQuick
import QtQuick.Effects

// The cover as a soft background: always a wash in the cover's own two colours (works even before or without the
// image), with the real cover blurred on top once it loads. The image is blurred straight from a small texture,
// so it costs almost nothing.
Item {
    id: w
    property string source: ""
    property var rgb: [80, 70, 60]
    property var rgb2: [20, 18, 16]
    property real strength: 0.7

    Rectangle {
        anchors.fill: parent
        opacity: w.strength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.rgb(w.rgb2) }
            GradientStop { position: 0.6; color: Theme.rgb(w.rgb, 0.85) }
            GradientStop { position: 1; color: Theme.rgb(w.rgb2) }
        }
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
    Image {
        id: img
        anchors.fill: parent
        source: w.source
        sourceSize: Qt.size(96, 96)          // tiny on purpose — it's going to be blurred
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        visible: img.status === Image.Ready
        opacity: w.strength
        blurEnabled: true; blur: 1.0; blurMax: 64
        saturation: 0.2
        autoPaddingEnabled: false
    }
}
