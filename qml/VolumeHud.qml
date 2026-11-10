import QtQuick
import QtQuick.Effects

// The Surface's volume buttons: a big capsule in the middle of the screen, Apple's volume slider — the level fills
// it in solid white from the left (straight edge), the rest is frosted glass with a fine light rim, and a speaker
// sits at the start with one, two or three waves for how loud it is; everything behind blurs while it's up.
// Fades in, settles, fades out after 1.5 s.
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

    // everything behind goes soft while the capsule's up
    ShaderEffectSource {
        id: whole
        anchors.fill: parent
        sourceItem: hud.backdrop
        live: veil.visible
        visible: false
    }
    MultiEffect {
        id: veil
        anchors.fill: parent
        source: whole
        visible: hud.backdrop !== null && opacity > 0
        opacity: cap.opacity
        blurEnabled: true; blur: 1.0; blurMax: 40
        brightness: -0.08
        autoPaddingEnabled: false
    }
    MouseArea { anchors.fill: parent; enabled: cap.shown; onPressed: (m) => { cap.shown = false; m.accepted = false } }

    Item {
        id: cap
        property bool shown: false
        anchors.centerIn: parent
        width: 560; height: 164
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.94
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: cap.shown ? 160 : 420; easing.type: Easing.OutQuad } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        // the glass: what's behind, blurred, inside the capsule; a fine light rim
        ShaderEffectSource {
            id: behind
            anchors.fill: parent
            sourceItem: hud.backdrop
            sourceRect: Qt.rect(cap.x, cap.y, cap.width, cap.height)
            live: cap.visible
            hideSource: false
            visible: false
        }
        Rectangle { id: capsule; anchors.fill: parent; radius: height / 2; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: behind
            visible: hud.backdrop !== null
            blurEnabled: true; blur: 1.0; blurMax: 48
            saturation: 0.1; brightness: 0.06
            maskEnabled: true; maskSource: capsule
            autoPaddingEnabled: false         // blurred edges stay inside the capsule (no square halo)
        }
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.13)
            border.color: Qt.rgba(1, 1, 1, 0.45); border.width: 1.5
        }
        // the level: solid white from the left, its right edge straight
        Item {
            width: Math.max(0, Math.min(cap.width, cap.width * hud.level / 100))
            height: cap.height
            clip: true
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Rectangle { width: cap.width; height: cap.height; radius: height / 2; color: "#ffffff" }
        }
        // the speaker: dark on the white, light on the glass
        readonly property bool onWhite: cap.width * hud.level / 100 > 104
        Canvas {
            id: spk
            x: 42; anchors.verticalCenter: parent.verticalCenter
            width: 64; height: 48
            property int waves: hud.level === 0 ? 0 : hud.level < 34 ? 1 : hud.level < 67 ? 2 : 3
            property color ink: cap.onWhite ? "#111111" : "#ffffff"
            onWavesChanged: requestPaint()
            onInkChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                c.fillStyle = ink; c.strokeStyle = ink; c.lineCap = "round"
                // the cone
                c.beginPath(); c.moveTo(2, 17); c.lineTo(11, 17); c.lineTo(23, 6); c.lineTo(23, 42); c.lineTo(11, 31); c.lineTo(2, 31)
                c.closePath(); c.fill()
                if (waves === 0) {            // muted: a small cross
                    c.lineWidth = 3.5
                    c.beginPath(); c.moveTo(32, 17); c.lineTo(44, 31); c.moveTo(44, 17); c.lineTo(32, 31); c.stroke()
                    return
                }
                c.lineWidth = 3.5
                for (var i = 0; i < waves; i++) {
                    var r = 9 + i * 8
                    c.beginPath(); c.arc(25, 24, r, -Math.PI / 4.2, Math.PI / 4.2); c.stroke()
                }
            }
        }
    }
}
