import QtQuick
import QtQuick.Shapes

// Music standby — "Ambient · reflection" (M4c). The cover sits in the middle of the screen, lit by its own colours,
// standing on a dark floor with a faint mirror image under it. Round it, in the corners:
//   top left: the dot clock (rearranges each minute, as on the phone) · top right: ⚡ and how warm it is
//   bottom left: the song, artist · what's next, and its progress · bottom right: the weather
// Behind: the cover's 6 × 4 wash, darkened towards the edges, and two soft glows in its colours drifting very slowly.
// Anything that isn't there (no next track, no weather) simply leaves its corner empty. Tap the cover for the player.
Item {
    id: ms
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false
    property bool dayTime: true
    property var music: room.music
    property var wx: room.weather

    readonly property real cs: 470                         // the cover
    readonly property real cx: 684
    readonly property real ctop: 196
    readonly property rect coverRect: Qt.rect(cover.x, cover.y, cover.width, cover.height)
    readonly property color ink: Qt.rgba(0.96, 0.95, 0.94, 1)
    readonly property color soft: Qt.rgba(0.96, 0.95, 0.94, 0.55)
    readonly property var next: music.nextUp && music.nextUp.length ? music.nextUp[0] : null

    // ---------------------------------------------------------------- the wash, darker towards the edges
    Image {
        anchors.fill: parent
        source: music.wash || ""
        smooth: true; fillMode: Image.Stretch
        visible: status === Image.Ready
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: ms.cx; centerY: 400; centerRadius: 900
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, ms.night ? 0.62 : 0.5) }
                GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, ms.night ? 0.92 : 0.86) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.94) }
            }
            PathRectangle { x: 0; y: 0; width: ms.width; height: ms.height }
        }
    }

    // ---------------------------------------------------------------- two glows in the cover's colours, behind it
    readonly property var base: Theme.lit(music.rgb || [255, 140, 110])
    readonly property var alt: {   // the cover's colour turned a little round the colour wheel
        var c = Qt.rgba(base[0] / 255, base[1] / 255, base[2] / 255, 1)
        var h = (c.hsvHue + 0.08) % 1
        var s = Qt.hsva(h < 0 ? 0 : h, c.hsvSaturation, c.hsvValue, 1)
        return [s.r * 255, s.g * 255, s.b * 255]
    }
    property real gt: 0
    readonly property real period: 200 * (night ? 2.5 : 1.5)
    Timer {
        interval: night ? 125 : 100; repeat: true; running: ms.visible
        onTriggered: ms.gt += interval / 1000
    }
    Repeater {
        model: [[2, 3, 1], [3, 2, 4]]
        Glow {
            readonly property real a: 2 * Math.PI * (ms.gt % ms.period) / ms.period
            width: 980; height: width
            x: ms.cx + 120 * Math.sin(modelData[0] * a + modelData[2]) - width / 2
            y: ms.ctop + ms.cs / 2 + 70 * Math.cos(modelData[1] * a + modelData[2]) - height / 2
            color: Theme.rgb(index === 0 ? ms.base : ms.alt)
            strength: ms.night ? 0.2 : 0.27
        }
    }

    // ---------------------------------------------------------------- the reflection: the cover mirrored, fading out
    Item {
        x: ms.cx - ms.cs / 2; y: ms.ctop + ms.cs + 6
        width: ms.cs; height: ms.cs * 0.42
        clip: true
        opacity: ms.night ? 0.22 : 0.32
        layer.enabled: true
        layer.effect: ShaderEffect {
            property real reach: 1.0
            fragmentShader: shaderDir + "fade.frag.qsb"
        }
        Cover {
            width: ms.cs; height: ms.cs; radius: 12
            source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34]
            transform: Scale { origin.y: ms.cs / 2; yScale: -1 }
        }
    }

    // ---------------------------------------------------------------- the cover
    Item {
        id: cover
        x: ms.cx - ms.cs / 2; y: ms.ctop
        width: ms.cs; height: ms.cs
        Cover { anchors.fill: parent; radius: 12; source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34] }
        Rectangle { anchors.fill: parent; radius: 12; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.08); border.width: 1 }
        Rectangle { anchors.fill: parent; radius: 12; color: Qt.rgba(0, 0, 0, ms.night ? 0.3 : 0.08) }
    }

    // ---------------------------------------------------------------- top
    ClockDots {
        x: 64; y: 64
        pitch: 14
        ink: Qt.rgba(0.96, 0.95, 0.94, 0.88)
        text: Theme.clock(new Date(ms.now * 1000), room.clock24)
    }
    T {
        anchors.right: parent.right; anchors.rightMargin: 64; y: 70
        visible: text !== ""
        text: room.status
        font.pixelSize: 24; color: ms.soft
    }

    // ---------------------------------------------------------------- bottom left: the song
    T {
        x: 64; y: 742; width: 620
        text: music.title || ""
        font.pixelSize: 50; font.weight: Font.Light; color: ms.ink
    }
    T {
        x: 64; y: 806; width: 620
        text: (music.artist || "") + (ms.next ? "   ·   next: " + ms.next.title : "")
        font.pixelSize: 26; color: ms.soft
    }
    Item {
        x: 64; y: 854; width: 300; height: 3
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? ms.now - music.at : 0))
        visible: (music.duration || 0) > 0
        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.14) }
        Rectangle { height: parent.height; radius: height / 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Qt.rgba(1, 1, 1, 0.8) }
    }

    // ---------------------------------------------------------------- bottom right: the weather
    Column {
        anchors.right: parent.right; anchors.rightMargin: 64; y: 752
        visible: wx.ok === true
        T { anchors.right: parent.right; text: (wx.t || 0) + "°"; font.pixelSize: 44; font.weight: Font.Light; color: ms.ink }
        T {
            anchors.right: parent.right
            text: Theme.cap(wx.d || "") + (wx.hi !== null && wx.hi !== undefined ? "  ·  " + wx.hi + "° / " + wx.lo + "°" : "")
            font.pixelSize: 24; color: ms.soft
        }
    }
}
