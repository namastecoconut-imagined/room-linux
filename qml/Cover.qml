import QtQuick
import QtQuick.Effects
// Album art with rounded corners. A new cover fades in over the old one once it has loaded (no blank, no jump);
// before any cover has loaded — or with no art — it's a gradient in the cover's colours.
Item {
    id: c
    property string source: ""
    property var rgb: [201, 185, 163]
    property var rgb2: [44, 40, 34]
    property real radius: 20
    property int fade: 900

    property int front: 0                    // which of the two pictures is on top
    readonly property bool anyShown: a.opacity > 0.01 || b.opacity > 0.01
    onSourceChanged: load()
    Component.onCompleted: load()
    function load() {
        var top = front === 0 ? a : b
        if (source === "" ) { a.opacity = 0; b.opacity = 0; return }
        if (top.source == source && top.status === Image.Ready) return
        var next = front === 0 ? b : a
        if (next.source == source && next.status === Image.Ready) { show(next); return }   // already loaded there
        next.source = source                 // shown once it's ready (onStatusChanged below)
    }
    function show(img) {
        if (img.source != c.source) return   // a newer cover was asked for meanwhile
        var other = img === a ? b : a
        front = img === a ? 0 : 1
        img.z = 1; other.z = 0
        img.opacity = 1
        other.opacity = 0
    }

    Rectangle {
        anchors.fill: parent; radius: c.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Theme.rgb(c.rgb) }
            GradientStop { position: 1; color: Theme.rgb(c.rgb2) }
        }
        opacity: c.anyShown ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: c.fade; easing.type: Easing.InOutQuad } }
    }
    Item {
        id: pics
        anchors.fill: parent
        visible: false
        Image {
            id: a
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; sourceSize: Qt.size(640, 640)
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: c.fade; easing.type: Easing.InOutQuad } }
            onStatusChanged: {
                if (status === Image.Ready) c.show(a)
                else if (status === Image.Error) console.warn("[room] cover didn't load:", source)
            }
        }
        Image {
            id: b
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; sourceSize: Qt.size(640, 640)
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: c.fade; easing.type: Easing.InOutQuad } }
            onStatusChanged: {
                if (status === Image.Ready) c.show(b)
                else if (status === Image.Error) console.warn("[room] cover didn't load:", source)
            }
        }
    }
    Rectangle { id: mask; anchors.fill: parent; radius: c.radius; visible: false; layer.enabled: true; layer.smooth: true }
    MultiEffect {
        anchors.fill: parent
        source: pics
        visible: c.anyShown
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
