import QtQuick

// An iPhone has started sending a video to "Room Screen": YouTube takes ~10 s before the picture comes (it opens in
// its own window over the panel), so meanwhile — over everything, standby included — a calm "getting it ready":
// a slow breathing light, the words, and a thin line that fills over the usual wait.
Item {
    id: vw
    width: Theme.stageW; height: Theme.stageH
    readonly property var w: room.videoWait || ({})
    readonly property bool showing: w.waiting === true
    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
    property real t: 0
    Timer { interval: 50; repeat: true; running: vw.visible; onTriggered: vw.t += 0.05 }

    MouseArea { anchors.fill: parent }           // nothing underneath is pressed while it shows
    Rectangle { anchors.fill: parent; color: "#050608" }
    Glow {
        anchors.centerIn: parent; width: 1200; height: 1200
        color: "#7fa8ff"; strength: 0.10 + 0.08 * (0.5 + 0.5 * Math.sin(vw.t * 1.8))
    }
    // a screen outline, softly breathing
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter; y: 214
        width: 172; height: 108; radius: 16; color: "transparent"
        border.width: 3; border.color: Qt.rgba(1, 1, 1, 0.55 + 0.35 * (0.5 + 0.5 * Math.sin(vw.t * 1.8)))
        Icon { anchors.centerIn: parent; name: "play"; size: 34; color: Qt.rgba(1, 1, 1, 0.85) }
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 372
        text: "Getting the video ready"; font.pixelSize: 64; font.weight: Font.Light
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 462
        text: (vw.w.from ? "From " + vw.w.from + "  ·  " : "") + "usually about 10 seconds"
        font.pixelSize: 24; color: Theme.sub
    }
    // fills over ~12 s, then waits at the end until the picture takes over
    Item {
        anchors.horizontalCenter: parent.horizontalCenter; y: 556; width: 420; height: 4
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.12) }
        Rectangle {
            id: fill
            height: parent.height; radius: 2; color: Theme.ink
            width: 0
        }
        NumberAnimation {
            id: grow; target: fill; property: "width"; from: 0; to: 420 * 0.92; duration: 12000
            easing.type: Easing.OutCubic
        }
        Connections { target: vw; function onShowingChanged() { if (vw.showing) { fill.width = 0; grow.restart() } else grow.stop() } }
        Component.onCompleted: if (vw.showing) grow.restart()
    }
}
