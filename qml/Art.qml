import QtQuick
// A cover for the redesign: rounded corners cut sharp at any size (shaders/roundimg), a new cover fading in over the
// old one once it's loaded — never a blank. Before any cover (or with none), a soft gradient in the song's colours.
Item {
    id: a
    property string source: ""
    property real radius: 14
    property var rgb: [201, 185, 163]
    property var rgb2: [44, 40, 34]
    property int fade: 700
    property bool liked: false            // "Liked songs": Spotify's own tile, a heart on purple-blue

    property int front: 0
    readonly property bool anyShown: sa.opacity > 0.01 || sb.opacity > 0.01
    onSourceChanged: load()
    Component.onCompleted: load()
    function load() {
        var top = front === 0 ? ia : ib
        if (source === "") { sa.opacity = 0; sb.opacity = 0; return }
        if (top.source == source && top.status === Image.Ready) return
        var next = front === 0 ? ib : ia
        if (next.source == source && next.status === Image.Ready) { show(next); return }
        next.source = source
    }
    function show(img) {
        if (img.source != a.source) return
        var s = img === ia ? sa : sb, o = img === ia ? sb : sa
        front = img === ia ? 0 : 1
        s.z = 1; o.z = 0; s.opacity = 1; o.opacity = 0
    }
    Rectangle {
        anchors.fill: parent; radius: a.radius
        visible: !a.liked
        opacity: a.anyShown ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: a.fade } }
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.rgb(a.rgb) }
            GradientStop { position: 1; color: Theme.rgb(a.rgb2) }
        }
    }
    Rectangle {
        anchors.fill: parent; radius: a.radius
        visible: a.liked
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#4a2fc4" }
            GradientStop { position: 1; color: "#8fb7ff" }
        }
        Icon { anchors.centerIn: parent; name: "heartOn"; size: parent.width * 0.32; color: "white" }
    }
    Image { id: ia; visible: false; asynchronous: true; cache: true; sourceSize: Qt.size(640, 640); onStatusChanged: if (status === Image.Ready) a.show(ia) }
    Image { id: ib; visible: false; asynchronous: true; cache: true; sourceSize: Qt.size(640, 640); onStatusChanged: if (status === Image.Ready) a.show(ib) }
    component Pic: ShaderEffect {
        property variant source
        property real radius: a.radius
        property real aa: 1 / Math.max(1, Theme.px * a.scale)
        property real aspect: 1
        property size size: Qt.size(width, height)
        anchors.fill: parent
        opacity: 0
        visible: opacity > 0.001 && !a.liked
        Behavior on opacity { NumberAnimation { duration: a.fade; easing.type: Easing.InOutQuad } }
        fragmentShader: shaderDir + "roundimg.frag.qsb"
    }
    Pic { id: sa; source: ia; aspect: ia.implicitHeight > 0 ? ia.implicitWidth / ia.implicitHeight : 1 }
    Pic { id: sb; source: ib; aspect: ib.implicitHeight > 0 ? ib.implicitWidth / ib.implicitHeight : 1 }
}
