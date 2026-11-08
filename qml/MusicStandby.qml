import QtQuick
import QtQuick.Effects

// Music standby — still standby (very dark), built around the cover: dot clock and weather on the left, the song
// under it, the cover on the right half, the cover blurred to near-black behind, and the artist's name drifting
// faintly across. No controls: tapping the cover opens the player.
Item {
    id: ms
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var music: room.music
    property var wx: room.weather
    signal openMusic()

    // the cover, blurred into the background (rendered small — it's a blur, nobody can tell)
    CoverWash { anchors.fill: parent; source: music.art || ""; rgb: music.rgb || [80, 70, 60]; rgb2: music.rgb2 || [20, 18, 16]; strength: 0.6 }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.78) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
        }
    }

    // the artist, huge and faint, drifting right to left
    T {
        id: drift
        y: 240
        text: (music.artist || "") + "     " + (music.artist || "")
        font.pixelSize: 520; font.letterSpacing: -14
        color: Qt.rgba(1, 1, 1, 0.035)
        elide: Text.ElideNone
        NumberAnimation on x { running: ms.visible; from: 0; to: -Math.max(1, drift.implicitWidth / 2); duration: Math.max(20000, drift.implicitWidth * 40); loops: Animation.Infinite }
    }

    Glow { x: 1020 - 330; y: 456 - 330; width: 660; height: 660; strength: 0.18; color: Theme.rgb(music.rgb || [200, 185, 163]) }

    DotText { x: 72; y: 96; pitch: 20; text: Theme.clock(new Date(ms.now * 1000), room.clock24) }
    Row {
        x: 72; y: 290; spacing: 10
        visible: wx.ok === true
        T { text: wx.t + "°"; font.pixelSize: 24; font.weight: Font.Light }
        T { text: (wx.d || "") + (wx.hi !== null && wx.hi !== undefined ? "  ·  ↑" + wx.hi + "° ↓" + wx.lo + "°" : ""); font.pixelSize: 24; font.weight: Font.Light; color: Theme.mut }
    }
    T { x: 72; y: 552; width: 560; text: music.title || ""; font.pixelSize: 62; font.letterSpacing: -0.8 }
    T { x: 72; y: 640; width: 560; text: music.artist || ""; font.pixelSize: 28; color: Theme.mut }
    Item {
        x: 72; y: 720; width: 440; height: 3
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? ms.now - music.at : 0))
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.14) }
        Rectangle { height: 3; radius: 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Qt.rgba(0.96, 0.95, 0.94, 0.8) }
    }

    Press {
        x: 700; y: 96; width: 600; height: 600; pressScale: 0.985
        Cover { anchors.fill: parent; radius: 30; source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34] }
        onTapped: ms.openMusic()
    }
    T { x: 700; y: 736; text: music.device || ""; font.pixelSize: 18; color: Theme.dim }
}
