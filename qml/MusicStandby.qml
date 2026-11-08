import QtQuick
import QtQuick.Effects

// Music standby — "B3". The dot clock, large and centred, glowing in the cover's colours; the glow breathes with the
// music (the room's sound through the mic, as the player's beat does) and a soft light of the cover's colours sits
// behind it. Under it, the date. Along the bottom: the song (a small cover, title, artist · next, progress) on the
// left, the weather (now, high/low, when rain is due) on the right; ⚡ status top right. Tap the song for the player.
Item {
    id: ms
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false
    property bool dayTime: true
    property var music: room.music
    property var wx: room.weather

    readonly property rect coverRect: Qt.rect(song.x, song.y, song.width, song.height)
    readonly property color ink: Qt.rgba(0.96, 0.95, 0.94, 1)
    readonly property color soft: Qt.rgba(0.96, 0.95, 0.94, 0.55)
    readonly property var next: music.nextUp && music.nextUp.length ? music.nextUp[0] : null
    readonly property var lit: Theme.lit(music.rgb || [255, 190, 140])
    // the cover's colour, softened towards warm white so the dots glow, not burn
    readonly property color glowC: Qt.rgba((lit[0] + 255) / 510, (lit[1] + 235) / 510, (lit[2] + 215) / 510, 1)
    readonly property int rainAt: Theme.rainAt(wx.hours)

    // ---------------------------------------------------------------- the beat: the room's sound, while music plays
    property real beatNow: 0
    property real beatFloor: -1
    property real beatV: 0
    readonly property real beatTarget: music.playing ? (room.micOn ? beatV : 0.35) : 0
    Connections {
        target: room
        enabled: room.micOn && ms.visible
        function onLevelChanged() {
            var l = room.level
            if (ms.beatFloor < 0) ms.beatFloor = l
            else ms.beatFloor += (l - ms.beatFloor) * (l < ms.beatFloor ? 0.2 : 0.02)
            var target = Math.max(0, Math.min(1, (l - ms.beatFloor) * 5))
            ms.beatV += (target - ms.beatV) * (target > ms.beatV ? 0.8 : 0.3)
        }
    }
    property real gt: 0
    // 20 frames a second, not the screen's 60 — the glow moves slowly; a third of the drawing
    Timer {
        interval: 50; repeat: true
        running: ms.visible
        onTriggered: {
            var dt = 0.05
            ms.gt += dt
            var k = ms.beatTarget > ms.beatNow ? 0.12 : 0.035      // eased: it swells with the music, never flickers
            ms.beatNow += (ms.beatTarget - ms.beatNow) * Math.min(1, k * dt * 60)
        }
    }
    readonly property real breath: 0.5 - 0.5 * Math.cos(2 * Math.PI * (gt % 12) / 12)       // 0…1 every 12 s
    readonly property real glow: (ms.night ? 0.6 : 1) * (0.28 + 0.08 * breath + 0.3 * beatNow)

    // ---------------------------------------------------------------- the room: the cover's wash, darkened at the edges
    Rectangle { anchors.fill: parent; color: "black" }
    Image {
        anchors.fill: parent
        source: music.wash || ""
        smooth: true; fillMode: Image.Stretch
        opacity: ms.night ? 0.3 : 0.5
        visible: status === Image.Ready
        layer.enabled: true                          // softened further: a wash of colour, no blocks or edges
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.9) }
        }
    }

    // ---------------------------------------------------------------- the light behind the clock: the cover, blurred
    Image {
        id: haloSrc
        source: music.art || ""
        sourceSize: Qt.size(4, 4)
        width: 4; height: 4
        smooth: true; visible: false
    }
    ShaderEffect {
        readonly property real sz: 1000 * (1 + 0.04 * ms.breath + 0.05 * ms.beatNow)
        x: ms.width / 2 - sz / 2; y: 360 - sz * 0.36
        width: sz; height: sz * 0.72
        visible: haloSrc.status === Image.Ready
        property var source: haloSrc
        property real sat: 1.4
        property real spread: 0.22                  // only the cover's colours, none of its shapes
        fragmentShader: shaderDir + "halo.frag.qsb"
        opacity: (ms.night ? 0.3 : 0.5) * (0.9 + 0.1 * ms.breath + 0.12 * ms.beatNow)
    }

    // ---------------------------------------------------------------- the clock, glowing
    Item {
        id: clockBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: 220
        width: clock.width + 160; height: clock.height + 160
        ClockDots {
            id: clock
            x: 80; y: 80
            pitch: 36
            ink: Qt.rgba(1, 0.985, 0.96, ms.night ? 0.7 : 1)
            text: Theme.clock(new Date(ms.now * 1000), room.clock24)
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: ms.glowC
            shadowBlur: 1.0
            shadowHorizontalOffset: 0; shadowVerticalOffset: 0
            shadowOpacity: Math.min(1, ms.glow)
            blurMax: 64
            shadowScale: 1.04
        }
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter
        y: clockBox.y + clockBox.height - 40
        text: Qt.formatDate(new Date(ms.now * 1000), "dddd, d MMMM")
        font.pixelSize: 26; color: ms.soft
    }
    T {
        anchors.right: parent.right; anchors.rightMargin: 72; y: 64
        visible: text !== ""
        text: room.status
        font.pixelSize: 22; color: Qt.rgba(0.96, 0.95, 0.94, 0.4)
    }

    // ---------------------------------------------------------------- bottom left: the song
    Item {
        id: song
        x: 72; y: 912 - 72 - 92
        width: 560; height: 92
        Item {
            id: thumb
            width: 92; height: 92
            Cover { anchors.fill: parent; radius: 10; source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34] }
            Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0, 0, 0, ms.night ? 0.3 : 0); border.color: Qt.rgba(1, 1, 1, 0.08); border.width: 1 }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: ms.glowC; shadowBlur: 0.8; shadowOpacity: 0.35 * ms.glow
                shadowHorizontalOffset: 0; shadowVerticalOffset: 0
            }
        }
        Column {
            x: 92 + 26; anchors.verticalCenter: parent.verticalCenter
            width: song.width - x
            spacing: 6
            T { width: parent.width; text: music.title || ""; font.pixelSize: 34; color: ms.ink }
            T {
                width: parent.width
                text: (music.artist || "") + (ms.next ? "   ·   next: " + ms.next.title : "")
                font.pixelSize: 22; color: ms.soft
            }
            Item {
                width: 320; height: 14
                readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? ms.now - music.at : 0))
                visible: (music.duration || 0) > 0
                Rectangle { y: 8; width: parent.width; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.14) }
                Rectangle { y: 8; height: 3; radius: 1.5; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Qt.rgba(1, 1, 1, 0.8) }
            }
        }
    }

    // ---------------------------------------------------------------- bottom right: the weather
    Column {
        anchors.right: parent.right; anchors.rightMargin: 72
        anchors.bottom: song.bottom; anchors.bottomMargin: 2
        visible: wx.ok === true
        spacing: 4
        T { anchors.right: parent.right; text: (wx.t !== undefined ? wx.t : "–") + "°"; font.pixelSize: 52; font.weight: Font.Light; color: ms.ink }
        T {
            anchors.right: parent.right
            textFormat: Text.StyledText
            text: Theme.cap(wx.d || "") + (wx.hi !== null && wx.hi !== undefined ? "  ·  " + wx.hi + "° / " + wx.lo + "°" : "")
                  + (ms.rainAt >= 0 ? "  ·  <font color='#7fb4ff'>rain " + Theme.hourText(wx.hours[ms.rainAt].h, room.clock24) + "</font>" : "")
            font.pixelSize: 22; color: ms.soft
        }
    }
}
