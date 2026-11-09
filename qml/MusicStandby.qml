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
    property color glowC: Qt.rgba((lit[0] + 255) / 510, (lit[1] + 235) / 510, (lit[2] + 215) / 510, 1)
    Behavior on glowC { ColorAnimation { duration: 1200; easing.type: Easing.InOutQuad } }
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
    // every other screen frame (30 a second): half the drawing, still in step with the screen so it doesn't judder
    property real acc: 0
    FrameAnimation {
        running: ms.visible
        onTriggered: {
            ms.acc += Math.min(0.1, frameTime)
            if (currentFrame % 2) return
            var dt = ms.acc
            ms.acc = 0
            ms.gt += dt
            var k = ms.beatTarget > ms.beatNow ? 0.12 : 0.035      // eased: it swells with the music, never flickers
            ms.beatNow += (ms.beatTarget - ms.beatNow) * Math.min(1, k * dt * 60)
        }
    }
    readonly property real breath: 0.5 - 0.5 * Math.cos(2 * Math.PI * (gt % 12) / 12)       // 0…1 every 12 s
    readonly property real glow: (ms.night ? 0.6 : 1) * (0.28 + 0.08 * breath + 0.3 * beatNow)

    // ---------------------------------------------------------------- the room: the cover's wash, darkened at the edges
    Rectangle { anchors.fill: parent; color: "black" }
    // two layers, so a new song's wash fades in over the old one
    property int washFront: 0
    property string washWant: music.wash || ""
    onWashWantChanged: {
        var n = washFront === 0 ? w1 : w0
        if (n.source == washWant && n.status === Image.Ready) washShow(n); else n.source = washWant
    }
    function washShow(img) {
        var other = img === w0 ? w1 : w0
        washFront = img === w0 ? 0 : 1
        img.opacity = night ? 0.3 : 0.5
        other.opacity = 0
    }
    Component.onCompleted: w0.source = washWant
    component Wash: Image {
        anchors.fill: parent
        smooth: true; fillMode: Image.Stretch
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.InOutQuad } }
        layer.enabled: true                          // softened further: a wash of colour, no blocks or edges
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
        onStatusChanged: if (status === Image.Ready && source == ms.washWant) ms.washShow(this)
    }
    Wash { id: w0 }
    Wash { id: w1 }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.9) }
        }
    }

    // ---------------------------------------------------------------- the light behind the clock: the cover, blurred
    // the halo dips, takes the new cover's colours, and comes back up — no jump
    property string haloArt: music.art || ""
    property real haloK: 1
    onHaloArtChanged: haloSwap.restart()
    SequentialAnimation {
        id: haloSwap
        NumberAnimation { target: ms; property: "haloK"; to: 0; duration: 500; easing.type: Easing.InQuad }
        ScriptAction { script: haloSrc.source = ms.haloArt }
        NumberAnimation { target: ms; property: "haloK"; to: 1; duration: 1000; easing.type: Easing.OutQuad }
    }
    Image {
        id: haloSrc
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
        opacity: ms.haloK * (ms.night ? 0.3 : 0.5) * (0.9 + 0.1 * ms.breath + 0.12 * ms.beatNow)
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
    // a running timer and the next alarm, quietly under the date
    readonly property var timers: (room.things.timers || []).filter(function (t) { return !t.done })
    readonly property var nextAlarm: room.things.nextAlarm || ({})
    T {
        anchors.horizontalCenter: parent.horizontalCenter
        y: clockBox.y + clockBox.height + 6
        visible: text !== ""
        textFormat: Text.StyledText
        text: [ms.timers.length ? "<font color='#f4eee6'>" + (ms.timers[0].label || "Timer") + "  " + Theme.countdown(ms.timers[0].left) + "</font>" : "",
               ms.nextAlarm.in !== undefined ? "Alarm " + Theme.hm(ms.nextAlarm.h, ms.nextAlarm.m, room.clock24) + (room.clock24 ? "" : " " + Theme.ampm(ms.nextAlarm.h, false)) : ""]
              .filter(function (s) { return s }).join("   ·   ")
        font.pixelSize: 24; color: ms.soft
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
