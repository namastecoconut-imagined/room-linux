import QtQuick
import QtQuick.Effects

// Music standby — "Poster". The song's colours fill the room, slowly moving (ColourWash); the title is set huge
// across the middle. Top left: the time and the day, with a running timer / the next alarm under it; top right: ⚡
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

    // ---------------------------------------------------------------- the title, huge (fades over to the next song)
    property string shownTitle: music.title || ""
    property string wantTitle: music.title || ""
    onWantTitleChanged: titleSwap.restart()
    SequentialAnimation {
        id: titleSwap
        NumberAnimation { target: title; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InQuad }
        ScriptAction { script: ms.shownTitle = ms.wantTitle }
        NumberAnimation { target: title; property: "opacity"; to: 1; duration: 900; easing.type: Easing.OutQuad }
    }
    T {
        id: title
        x: 64; width: 1240
        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 10
        height: 420
        verticalAlignment: Text.AlignVCenter
        text: ms.shownTitle
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        fontSizeMode: Text.Fit; minimumPixelSize: 84
        font.pixelSize: 196; font.weight: Font.DemiBold; font.letterSpacing: -5
        lineHeight: 0.92
        color: ms.ink
        opacity: 1
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.35); shadowBlur: 0.8; shadowVerticalOffset: 6; shadowHorizontalOffset: 0 }
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
