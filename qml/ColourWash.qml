import QtQuick
import QtQuick.Effects

// The song's colours as a soft, slowly moving background (home and music standby). The cover is read at a few
// pixels, stretched and blurred until it's only colour; two copies of it drift and turn against each other, so the
// colours swirl very slowly. A new song's colours fade in over the old ones.
//
// Light on the Surface: each copy is blurred once (a cached layer) and only moved after that, and the movement steps
// 20 times a second, not 60 — a third of the redrawing. Nothing moves while it's
// hidden or faded out.
Item {
    id: cw
    property string art: ""             // the cover (any size: only a 24 × 24 read of it is used)
    property real strength: 1           // 0 = gone (nothing playing), 1 = full
    property bool moving: true
    clip: true

    property real t: 0
    Timer {
        interval: 50; repeat: true
        running: cw.moving && cw.visible && cw.opacity > 0 && cw.strength > 0
        onTriggered: cw.t += 0.05
    }

    // two slots, so a new cover's colours fade in over the old ones
    property int front: 0
    onArtChanged: {
        var n = front === 0 ? s1 : s0
        n.src = art
        front = n === s0 ? 0 : 1
    }
    Component.onCompleted: { s0.src = art; front = 0 }

    component Blob: Item {
        property string src: ""
        readonly property int status: im.status
        width: cw.width * 1.6; height: cw.height * 1.6
        Image {
            id: im
            anchors.fill: parent
            source: parent.src
            sourceSize: Qt.size(24, 24)
            smooth: true; fillMode: Image.Stretch
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; saturation: 0.2 }
        }
    }
    component Swirl: Item {
        id: sw
        property string src: ""
        property bool on: false
        anchors.fill: parent
        opacity: on && src !== "" && a.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 1600; easing.type: Easing.InOutQuad } }
        // movement you can see but that never hurries: each copy circles and turns once every ~30–50 s
        Blob {
            id: a
            src: sw.src
            x: -cw.width * 0.3 + cw.width * 0.16 * Math.sin(cw.t / 6)
            y: -cw.height * 0.3 + cw.height * 0.14 * Math.cos(cw.t / 7.5)
            rotation: 22 * Math.sin(cw.t / 9)
            scale: 1 + 0.12 * Math.sin(cw.t / 5)
        }
        Blob {
            src: sw.src
            x: -cw.width * 0.3 + cw.width * 0.18 * Math.cos(cw.t / 5.5)
            y: -cw.height * 0.3 + cw.height * 0.16 * Math.sin(cw.t / 8)
            rotation: 180 + 26 * Math.cos(cw.t / 7)
            scale: 1.1 + 0.12 * Math.cos(cw.t / 6.5)
            opacity: 0.6
        }
    }
    Item {
        anchors.fill: parent
        opacity: cw.strength
        Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.InOutQuad } }
        Swirl { id: s0; on: cw.front === 0 }
        Swirl { id: s1; on: cw.front === 1 }
    }
}
