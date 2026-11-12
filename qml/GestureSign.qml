import QtQuick
import QtQuick.Effects

// What a hand gesture just did (room/eyes.py): the volume capsule's glass at the top centre, holding the action's
// icon and its word — Next · Previous · Pause · Play. Drops in, and fades away 1.2 s later.
// Also the IR camera's light: a small warm dot at the very top centre, right under the camera, for as long as it's
// watching for a hand (the camera has no light of its own that says so).
Item {
    id: sign
    width: Theme.stageW; height: Theme.stageH
    property Item backdrop: null          // what's behind (the stage): the glass blurs it
    property string what: ""
    readonly property var names: ({ next: "Next", previous: "Previous", pause: "Pause", play: "Play" })
    readonly property var icons: ({ next: "next", previous: "prev", pause: "pause", play: "play" })
    Connections {
        target: room
        function onGestureShown(k) { sign.what = k; cap.shown = true; hide.restart() }
    }
    Timer { id: hide; interval: 1200; onTriggered: cap.shown = false }

    // the camera's light
    Rectangle {
        x: Theme.stageW / 2 - 3; y: 9; width: 6; height: 6; radius: 3
        color: Qt.rgba(1, 150 / 255, 110 / 255, 0.9)
        opacity: room.watching ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    Item {
        id: cap
        property bool shown: false
        width: row.implicitWidth + 56; height: 56
        x: (Theme.stageW - width) / 2; y: shown ? 40 : 30
        opacity: shown ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: cap.shown ? 220 : 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

        ShaderEffectSource {
            id: behind
            anchors.fill: parent
            sourceItem: sign.backdrop
            sourceRect: Qt.rect(cap.x, 40, cap.width, cap.height)
            live: cap.visible
            hideSource: false
            visible: false
        }
        Rectangle { id: shape; anchors.fill: parent; radius: 28; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: behind
            visible: sign.backdrop !== null
            blurEnabled: true; blur: 1.0; blurMax: 32
            maskEnabled: true; maskSource: shape
            autoPaddingEnabled: false
        }
        Rectangle {
            anchors.fill: parent; radius: 28
            color: Qt.rgba(20 / 255, 14 / 255, 10 / 255, 0.6)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
        }
        Row {
            id: row
            anchors.centerIn: parent; spacing: 12
            Icon { anchors.verticalCenter: parent.verticalCenter; size: 18; color: "white"; name: sign.icons[sign.what] || "play" }
            Mono { anchors.verticalCenter: parent.verticalCenter; size: 14; color: "white"; text: sign.names[sign.what] || "" }
        }
    }
}
