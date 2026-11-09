import QtQuick
import QtQuick.Effects

// Music standby — "Poster", the Zune way. The song's colours fill the room, slowly moving (ColourWash); the artist,
// the title and the album drift across it as giant lowercase words. Top left: the time and the day, with a running timer / the next alarm under it; top right: ⚡
// status and the weather. Along the bottom: a small cover, the artist and what's next, and the progress. A new song
// fades its colours and title in over the old ones. Tap the song (bottom left) for the player.
Item {
    id: ms
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false
    property bool dayTime: true
    property var music: room.music
    property var wx: room.weather

    readonly property rect coverRect: Qt.rect(song.x, song.y, song.width, song.height)
    readonly property color ink: "#fff6ec"
    readonly property color soft: Qt.rgba(1, 0.965, 0.925, 0.62)
    readonly property var next: music.nextUp && music.nextUp.length ? music.nextUp[0] : null
    readonly property int rainAt: Theme.rainAt(wx.hours)

    // ---------------------------------------------------------------- the room: the song's colours, moving
    // (a little past every edge: on standby the whole screen drifts slowly against burn-in)
    Rectangle { anchors.fill: parent; anchors.margins: -60; color: "black" }
    ColourWash {
        anchors.fill: parent; anchors.margins: -60
        art: music.art || ""
        strength: ms.night ? 0.45 : 0.95
        moving: ms.visible
    }
    Rectangle {      // darker towards the bottom (where the small type is) and a touch at the top
        anchors.fill: parent; anchors.margins: -60
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, ms.night ? 0.45 : 0.18) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, ms.night ? 0.35 : 0.08) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, ms.night ? 0.8 : 0.55) }
        }
    }

    // ---------------------------------------------------------------- top: time · day, timer / alarm; status, weather
    readonly property var timers: (room.things.timers || []).filter(function (t) { return !t.done })
    readonly property var nextAlarm: room.things.nextAlarm || ({})
    Column {
        x: 72; y: 60; spacing: 6
        T {
            text: Theme.clock(new Date(ms.now * 1000), room.clock24) + "  ·  " + Qt.formatDate(new Date(ms.now * 1000), "dddd")
            font.pixelSize: 34; font.weight: Font.Normal; color: ms.ink; opacity: ms.night ? 0.75 : 0.9
        }
        T {
            visible: text !== ""
            textFormat: Text.StyledText
            text: [ms.timers.length ? "<font color='#fff6ec'>" + (ms.timers[0].label || "Timer") + "  " + Theme.countdown(ms.timers[0].left) + "</font>" : "",
                   ms.nextAlarm.in !== undefined ? "Alarm " + Theme.hm(ms.nextAlarm.h, ms.nextAlarm.m, room.clock24) + (room.clock24 ? "" : " " + Theme.ampm(ms.nextAlarm.h, false)) : ""]
                  .filter(function (s) { return s }).join("   ·   ")
            font.pixelSize: 22; color: ms.soft
        }
    }
    Column {
        anchors.right: parent.right; anchors.rightMargin: 72; y: 66; spacing: 6
        T {
            anchors.right: parent.right
            visible: wx.ok === true
            textFormat: Text.StyledText
            text: (wx.t !== undefined ? wx.t : "–") + "°  " + Theme.cap(wx.d || "")
                  + (ms.rainAt >= 0 ? "  ·  <font color='#9cc4ff'>rain " + Theme.hourText(wx.hours[ms.rainAt].h, room.clock24) + "</font>" : "")
            font.pixelSize: 24; color: ms.soft
        }
        T { anchors.right: parent.right; visible: text !== ""; text: room.status; font.pixelSize: 20; color: Qt.rgba(1, 0.965, 0.925, 0.4) }
    }

    // ---------------------------------------------------------------- Zune's now playing: giant words drifting by
    // Three layers of lowercase type, far bigger than the screen, sliding slowly sideways at different speeds and
    // in different directions — the artist faint and enormous behind, the title big and bright, the album small and
    // quiet below. Each loops seamlessly. A new song: they all fade out, change, and drift back in.
    property real zt: 0
    property real zacc: 0
    FrameAnimation {            // 30 a second (every other frame): smooth for slow movement, half the drawing
        running: ms.visible
        onTriggered: {
            ms.zacc += Math.min(0.1, frameTime)
            if (currentFrame % 2) return
            ms.zt += ms.zacc; ms.zacc = 0
        }
    }
    property string shownTitle: (music.title || "").toLowerCase()
    property string shownArtist: (music.artist || "").toLowerCase()
    property string shownAlbum: (music.album || "").toLowerCase()
    property string wantKey: (music.title || "") + "|" + (music.artist || "")
    onWantKeyChanged: swap.restart()
    SequentialAnimation {
        id: swap
        NumberAnimation { target: words; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                ms.shownTitle = (music.title || "").toLowerCase()
                ms.shownArtist = (music.artist || "").toLowerCase()
                ms.shownAlbum = (music.album || "").toLowerCase()
                ms.zt = 0
            }
        }
        NumberAnimation { target: words; property: "opacity"; to: 1; duration: 1400; easing.type: Easing.OutQuad }
    }
    component Drift: Item {
        id: dr
        property string text: ""
        property real size: 200
        property int weight: Font.Normal
        property real speed: 20                  // px a second; negative drifts right
        property real start: 0                   // where in the loop it begins (so the layers don't line up)
        property color colour: ms.ink
        width: ms.width; height: probe.height
        T { id: probe; visible: false; text: dr.text; font.pixelSize: dr.size; font.weight: dr.weight; font.letterSpacing: -dr.size * 0.03 }
        // a wide gap: one word crossing at a time, the next coming in as it leaves (Zune, not a ticker)
        readonly property real gap: Math.max(dr.size * 0.6, ms.width * 0.55)
        readonly property real period: probe.implicitWidth + gap
        Row {
            x: dr.period > 0 ? -(((ms.zt * dr.speed + dr.start) % dr.period) + dr.period) % dr.period : 0
            spacing: dr.gap
            Repeater {
                model: dr.text === "" ? 0 : Math.ceil((ms.width + 2 * dr.period) / Math.max(1, dr.period)) + 1
                T { text: dr.text; font.pixelSize: dr.size; font.weight: dr.weight; font.letterSpacing: -dr.size * 0.03; color: dr.colour; elide: Text.ElideNone }
            }
        }
    }
    Item {
        id: words
        anchors.fill: parent
        Drift {          // the artist: enormous, faint, drifting right behind everything
            y: 70; text: ms.shownArtist; size: 380; weight: Font.Bold; speed: -14; start: 200
            colour: Qt.rgba(1, 0.965, 0.925, ms.night ? 0.06 : 0.1)
        }
        Drift {          // the title: big and bright, drifting left
            y: 330; text: ms.shownTitle; size: 210; weight: Font.DemiBold; speed: 24
            colour: Qt.rgba(1, 0.965, 0.925, ms.night ? 0.75 : 0.96)
        }
        Drift {          // the album: small and quiet, drifting right a little faster
            y: 590; text: ms.shownAlbum; size: 64; weight: Font.Light; speed: -32; start: 400
            colour: Qt.rgba(1, 0.965, 0.925, ms.night ? 0.3 : 0.45)
        }
    }

    // ---------------------------------------------------------------- bottom: the song
    Item {
        id: song
        x: 72; y: 912 - 72 - 88
        width: 560; height: 88
        Cover {
            width: 88; height: 88; radius: 12
            source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34]
        }
        Column {
            x: 88 + 24; anchors.verticalCenter: parent.verticalCenter
            width: song.width - x; spacing: 6
            T { width: parent.width; text: music.artist || ""; font.pixelSize: 30; font.weight: Font.Medium; color: ms.ink }
            T { width: parent.width; visible: text !== ""; text: ms.next ? "next  ·  " + ms.next.title : (music.album || ""); font.pixelSize: 21; color: ms.soft }
        }
    }
    Item {
        x: 680; width: 1368 - 72 - x; height: 4
        anchors.verticalCenter: song.verticalCenter
        readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? ms.now - music.at : 0))
        visible: (music.duration || 0) > 0
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.22) }
        Rectangle { height: 4; radius: 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: ms.ink }
    }
}
