import QtQuick
import "../../qml"

// The player: the video fills the width (16:9 in the 3:2 screen, so a band above and below it). Tap the lower part
// and the controls come up for a few seconds — the title, the place in the video (drag it), back 10 s, play/pause,
// on 10 s — with ‹ YouTube, captions and quality in the top bar. Otherwise it's just the picture, and a hairline
// along the bottom for where you are. (The screens for now: the picture is the video's still.)
Item {
    id: pl
    property var video: null
    property real now: Date.now()
    property bool controls: true
    property bool paused: false
    signal back()
    readonly property var v: video || ({})
    readonly property real dur: secs(v.duration)
    property real at: 0.36
    onVideoChanged: { var p = video ? (video.progress || 0) : 0; at = p > 0 && p < 1 ? p : 0 }
    function secs(d) { var p = (d || "0").split(":").map(Number), s = 0; for (var i = 0; i < p.length; i++) s = s * 60 + p[i]; return s }
    function hms(s) { s = Math.max(0, Math.round(s)); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h ? h + ":" + Theme.two(m) : m) + ":" + Theme.two(s % 60) }
    function poke() { controls = true; hide.restart() }
    Timer { id: hide; interval: 4000; onTriggered: if (!pl.paused && !seek.dragging) pl.controls = false }

    Rectangle { anchors.fill: parent; color: "black" }
    Image {
        id: frame
        width: parent.width; height: Math.round(parent.width * 9 / 16)
        anchors.verticalCenter: parent.verticalCenter
        source: pl.v.thumb || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true
        sourceSize.width: 1368
    }
    // the bare picture: where you are, a hairline along the very bottom
    Rectangle {
        anchors.bottom: parent.bottom; width: parent.width * pl.at; height: 3; color: Theme.warm
        opacity: pl.controls ? 0 : 0.8
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }
    // a tap anywhere in the part that answers touch brings the controls up (or puts them away)
    MouseArea {
        y: Theme.deadB1; width: parent.width; height: parent.height - Theme.deadB1
        onClicked: if (pl.controls) { pl.controls = false; hide.stop() } else pl.poke()
    }

    Item {
        id: ctl
        anchors.fill: parent
        opacity: pl.controls ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
        Rectangle {
            width: parent.width; height: 180
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.62) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        Rectangle {
            y: 430; width: parent.width; height: parent.height - 430
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.62) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.88) }
            }
        }

        // top bar: ‹ YouTube · the clock · captions, quality
        Item {
            y: 34; width: parent.width; height: 44
            Press {
                x: 36; width: pbR.implicitWidth + 16; height: 44; pressScale: 0.94
                reachTop: 34; reachBottom: 30
                onTapped: pl.back()
                Row {
                    id: pbR
                    anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "back"; size: 20; color: "white" }
                    Mono { anchors.verticalCenter: parent.verticalCenter; text: "YouTube" }
                }
            }
            Serif { x: 652; y: 4; text: Theme.clock(new Date(pl.now), room.clock24); font.pixelSize: 50; tracking: -0.03 }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 36; spacing: 10
                Chip { text: "CC"; onTapped: pl.poke() }
                Chip { text: "1080p"; onTapped: pl.poke() }
            }
        }

        // what it is
        Column {
            x: 44; y: 572; width: 1000
            Mono { text: pl.v.channel || ""; color: Theme.w62; bottomPadding: 12 }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: pl.v.title || ""; color: "white"
                font.family: Theme.face; font.pixelSize: 34; renderType: Text.QtRendering
            }
        }
        // where you are — drag it
        Seek {
            id: seek
            x: 44; y: 690; width: 1280
            value: pl.at
            label: pl.hms(value * pl.dur)
            onReleased: (v) => { pl.at = v; pl.poke() }
            onMoved: (v) => hide.restart()
        }
        Mono { x: 44; y: 730; size: 13; color: Theme.w62; text: pl.hms(pl.at * pl.dur) }
        Mono { anchors.right: seek.right; y: 730; size: 13; color: Theme.w62; text: "-" + pl.hms((1 - pl.at) * pl.dur) }

        // back 10 s · play / pause · on 10 s
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 778; spacing: 44
            Jump { dir: -1; anchors.verticalCenter: parent.verticalCenter; onTapped: { pl.at = Math.max(0, pl.at - 10 / Math.max(1, pl.dur)); pl.poke() } }
            Press {
                width: 92; height: 92; pressScale: 0.92
                onTapped: { pl.paused = !pl.paused; pl.poke() }
                Rectangle { anchors.fill: parent; radius: 46; color: "white" }
                Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: pl.paused ? 3 : 0; name: pl.paused ? "play" : "pause"; size: 36; color: Theme.onWhite }
            }
            Jump { dir: 1; anchors.verticalCenter: parent.verticalCenter; onTapped: { pl.at = Math.min(1, pl.at + 10 / Math.max(1, pl.dur)); pl.poke() } }
        }
    }
    component Jump: Press {
        id: j
        property int dir: 1
        width: 72; height: 72; pressScale: 0.9
        Rectangle { anchors.fill: parent; radius: 36; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3) }
        Icon { anchors.centerIn: parent; name: j.dir < 0 ? "replay" : "forward"; size: 40; color: "white" }
        Mono { anchors.centerIn: parent; anchors.verticalCenterOffset: 2; text: "10"; size: 11 }
    }
}
