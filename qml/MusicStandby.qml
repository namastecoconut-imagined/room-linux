import QtQuick

// Music standby — the iPhone panel's music face of StandbyView. Still a standby: near-black, the cover's colours only
// a hint behind (the 6 × 4 wash under an 80% shade, and two soft glows in the cover's colour drifting very slowly).
// The artist's name in huge, faint Inter Tight slides left forever across the middle. Left: the dot clock, the
// weather, the song, its progress, ⚡ status. Right: the cover, a touch dimmed. Tap the cover for the player.
Item {
    id: ms
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false
    property bool dayTime: true
    property var music: room.music
    property var wx: room.weather
    readonly property real k: 1368 / 568
    readonly property real dy: ((912 / k) - 320) / 2         // the extra height, split above and below
    function px(pt) { return pt * k }
    readonly property rect coverRect: Qt.rect(cover.x, cover.y, cover.width, cover.height)

    // ---------------------------------------------------------------- the wash, pulled almost to black
    Image {
        anchors.fill: parent
        source: music.wash || ""
        smooth: true; fillMode: Image.Stretch
        visible: status === Image.Ready
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.8) }

    // ---------------------------------------------------------------- two glows in the cover's colours
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
            width: px(640); height: width
            x: px(230 + 170 * Math.sin(modelData[0] * a + modelData[2])) - width / 2
            y: px(160 + ms.dy + 100 * Math.cos(modelData[1] * a + modelData[2])) - height / 2
            color: Theme.rgb(index === 0 ? ms.base : ms.alt)
            strength: 0.3 * 0.9
        }
    }

    // ---------------------------------------------------------------- the artist's name, sliding left forever
    Item {
        id: marquee
        anchors.left: parent.left; anchors.right: parent.right
        y: px(200 + ms.dy) - name.font.pixelSize * 0.97
        height: name.implicitHeight
        clip: false
        readonly property string label: (music.artist || music.title || "") + "     "
        property real off: 0
        Timer {
            interval: 33; repeat: true; running: ms.visible && name.implicitWidth > 0
            onTriggered: marquee.off = (marquee.off + ms.px(26) * 0.033) % Math.max(1, name.implicitWidth)
        }
        Row {
            x: -marquee.off
            Repeater {
                model: Math.ceil(1368 / Math.max(1, name.implicitWidth)) + 1
                T {
                    text: marquee.label
                    font.family: "Inter Tight"; font.pixelSize: ms.px(170); elide: Text.ElideNone
                    color: Qt.rgba(1, 1, 1, ms.dayTime ? 0.065 : 0.05)
                }
            }
        }
        T { id: name; visible: false; text: marquee.label; font.family: "Inter Tight"; font.pixelSize: ms.px(170); elide: Text.ElideNone }
    }

    // ---------------------------------------------------------------- left column
    DotText {
        id: mClock
        x: px(29); y: px(36 + ms.dy)
        pitch: px(8.5); glide: 0
        color: Qt.rgba(0.96, 0.95, 0.94, 0.88)
        text: Theme.clock(new Date(ms.now * 1000), room.clock24)
    }
    Item {
        x: px(31); y: mClock.y + mClock.height + px(26)
        visible: wx.ok === true
        width: px(250); height: wd.height
        DotText { id: wd; pitch: px(2.6); glide: 0; text: "" + (wx.t || 0); color: Qt.rgba(0.96, 0.95, 0.94, 0.8) }
        Rectangle {
            id: wdeg
            x: wd.width + px(2); width: px(4); height: px(4); radius: width / 2
            color: "transparent"; border.color: Qt.rgba(0.96, 0.95, 0.94, 0.7); border.width: px(1)
        }
        T {
            x: wdeg.x + wdeg.width + px(8); y: (wd.height - height) / 2
            text: Theme.cap(wx.d || "") + (wx.hi !== null && wx.hi !== undefined ? "  ·  " + wx.hi + "° / " + wx.lo + "°" : "")
            font.pixelSize: px(12); color: Qt.rgba(0.96, 0.95, 0.94, 0.55)
        }
    }
    T {
        x: px(31); y: px(198 + ms.dy); width: px(228)
        text: music.title || ""
        font.pixelSize: px(24); font.weight: Font.Light; fontSizeMode: Text.HorizontalFit; minimumPixelSize: px(18)
    }
    T { x: px(31); y: px(230 + ms.dy); width: px(228); text: music.artist || ""; font.pixelSize: px(13); color: Qt.rgba(0.96, 0.95, 0.94, 0.55) }
    Item {
        x: px(31); y: px(262 + ms.dy); width: px(213); height: px(2)
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? ms.now - music.at : 0))
        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.16) }
        Rectangle { height: parent.height; radius: height / 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Qt.rgba(1, 1, 1, 0.85) }
    }
    T { x: px(31); y: px(276 + ms.dy); text: room.status; font.pixelSize: px(12); color: Qt.rgba(0.96, 0.95, 0.94, 0.5) }

    // ---------------------------------------------------------------- right half: the cover, a touch dimmed
    Item {
        id: cover
        width: px(268); height: width
        x: 1368 - px(26) - width; y: (912 - height) / 2
        Cover { anchors.fill: parent; radius: px(14); source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34] }
        Rectangle { anchors.fill: parent; radius: px(14); color: Qt.rgba(0, 0, 0, 0.18) }
    }
}
