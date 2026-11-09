import QtQuick
import QtMultimedia

// A music video, full screen (design A). Title, progress and the buttons sit along the bottom — the part of the
// screen that answers touch — and fade out after 4 s; a touch down there brings them back. "Alexa, pause / next"
// work as with music; ✕ or "close the video" goes back to where you were.
Item {
    id: vs
    width: 1368; height: 912
    property bool ducked: false              // Room is listening or talking: the video's sound dips
    readonly property var v: room.video
    signal back()

    Rectangle { anchors.fill: parent; color: "black" }

    MediaPlayer {
        id: player
        source: vs.v.url
        audioOutput: AudioOutput { volume: vs.ducked ? 0.25 : 1; Behavior on volume { NumberAnimation { duration: 300 } } }
        videoOutput: out
        onSourceChanged: if (source.toString() !== "") play()
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) vs.v.ended()
        onErrorOccurred: (e, msg) => console.log("[room] video player:", msg)
    }
    Connections {
        target: vs.v
        function onChanged() {
            if (vs.v.url === "") player.stop()
            else if (vs.v.paused && player.playbackState === MediaPlayer.PlayingState) { player.pause(); vs.poke() }
            else if (!vs.v.paused && player.playbackState === MediaPlayer.PausedState) { player.play(); vs.poke() }
        }
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        opacity: player.playbackState !== MediaPlayer.StoppedState && player.position > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    }

    // finding it / can't play it
    Text {
        anchors.centerIn: parent
        width: 900; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: vs.v.error ? "Couldn’t play that — " + vs.v.error : "Finding “" + vs.v.title + "”…"
        visible: vs.v.loading || vs.v.error !== ""
        color: Theme.sub; font.family: Theme.face; font.pixelSize: 40; font.weight: Font.Medium
        renderType: Text.QtRendering
        SequentialAnimation on opacity {
            running: vs.v.loading; loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.4; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.4; to: 1; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // ------------------------------------------------------------------ the controls (bottom: where touch works)
    property bool shown: true
    function poke() { shown = true; hide.restart() }
    Timer { id: hide; interval: 4000; onTriggered: if (player.playbackState === MediaPlayer.PlayingState) vs.shown = false }
    onVisibleChanged: if (visible) poke()
    readonly property bool controls: shown || vs.v.paused || vs.v.loading || vs.v.error !== ""
    // a touch anywhere it can be felt brings them back (the band in the middle can't feel it)
    MouseArea { anchors.fill: parent; onPressed: (m) => { vs.poke(); m.accepted = false } }

    Item {
        anchors.fill: parent
        opacity: vs.controls ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 300
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.85) }
            }
        }
        Column {
            x: 64; y: 912 - 150 - height
            width: 820
            Text {
                width: parent.width; elide: Text.ElideRight
                text: vs.v.title; color: Theme.tx
                font.family: Theme.face; font.pixelSize: 44; font.weight: Font.DemiBold
                renderType: Text.QtRendering
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: vs.v.channel ? vs.v.channel + " · YouTube" : "YouTube"; color: Theme.sub
                font.family: Theme.face; font.pixelSize: 28
                renderType: Text.QtRendering
            }
        }
        // progress: shows where it is, not for dragging (like the music player)
        Rectangle {
            x: 64; y: 912 - 110; width: 1368 - 128; height: 4; radius: 2
            color: Qt.rgba(1, 1, 1, 0.18)
            Rectangle {
                height: parent.height; radius: 2; color: Theme.accent
                width: player.duration > 0 ? parent.width * Math.min(1, player.position / player.duration) : 0
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 64
            y: 912 - 150 - 108 + 20
            spacing: 22
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 88; iconSize: 28; icon: "close"; fill: Qt.rgba(1, 1, 1, 0.12); onTapped: { vs.v.close(); vs.back() } }
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 108; iconSize: 38; icon: vs.v.paused ? "play" : "pause"; fill: Theme.tx; ink: "black"; onTapped: { vs.v.togglePause(); vs.poke() } }
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 88; iconSize: 28; icon: "next"; fill: Qt.rgba(1, 1, 1, 0.12); onTapped: { vs.v.next(); vs.poke() } }
        }
    }
}
