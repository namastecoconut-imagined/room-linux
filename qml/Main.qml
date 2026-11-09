import QtQuick
import QtQuick.Window

// Room on the Surface. Everything is drawn on a 1368 × 912 stage (the Surface Pro 6 at 200%), scaled to whatever
// the window is, so it stays sharp and proportioned on any 3:2 screen.
//
// Standby follows the iPhone panel exactly (NativePanel.tick, once a second):
//  • the music player (and any open sheet) keeps the panel awake — it never drops into standby there
//  • on home, standbySec (15 s) untouched → standby fades in; night hours use nightStandbySec if config sets one
//  • in a menu (room, clock, weather, reminders) it waits menuStandbySec (3 min) before standby (then home)
//  • any touch, click, scroll or mouse movement counts as being used
//  • a touch only counts while awake; on standby only a real tap wakes it (held ≥ 40 ms, moved < 30 phone pt) —
//    a brush or a ghost touch doesn't. On music standby, tapping the cover opens the player.
//  • music standby shows only while music is actually playing
Window {
    id: win
    width: Theme.stageW; height: Theme.stageH
    visible: true
    visibility: windowed ? Window.Windowed : Window.FullScreen
    color: "black"
    title: "Room"

    property real now: Date.now() / 1000
    // F11: leave full screen to reach the desktop (and back again)
    // a panel: always full screen (if something knocks it into a window, it goes back within a few seconds)
    Timer {
        interval: 4000; repeat: true; running: !windowed && !win.keptWindowed
        onTriggered: if (win.visibility !== Window.FullScreen) win.visibility = Window.FullScreen
    }
    property bool keptWindowed: false
    Shortcut { sequence: "F11"; onActivated: { win.keptWindowed = win.visibility === Window.FullScreen; win.visibility = win.keptWindowed ? Window.Windowed : Window.FullScreen } }

    // the screen you're on while awake, and whether standby is showing over it
    property string screen: startScreen === "clockedit" ? "clock" : startScreen.indexOf("music") === 0 && startScreen !== "musicstandby" ? "music" : ["music", "room", "clock", "weather", "reminders", "assistant", "settings"].indexOf(startScreen) >= 0 ? startScreen : "home"
    property string roomName: room.rooms.length ? room.rooms[0].name : ""
    property bool standbyOn: startScreen === "standby" || startScreen === "musicstandby"
    property real lastTouch: standbyOn ? 0 : Date.now() / 1000
    readonly property bool playing: room.music.exists && room.music.playing
    readonly property bool musicFace: playing || startScreen === "musicstandby"
    readonly property var timing: room.timing
    function nightHour(h) {
        var a = timing.nightStart, b = timing.nightEnd
        return a > b ? (h >= a || h < b) : (h >= a && h < b)
    }
    readonly property bool lateNight: nightHour(new Date(now * 1000).getHours())
    readonly property bool dayTime: { var h = new Date(now * 1000).getHours(); return h >= 7 && h < 18 }
    property bool sheetOpen: false        // speaker picker / library over the player

    // Alexa: the wake word (or a tap) brings up the assistant from anywhere, standby included; a few seconds after
    // the answer it goes back to where you were
    readonly property string voiceState: room.voice.state || "off"
    readonly property bool talking: voiceState === "listening" || voiceState === "thinking" || voiceState === "speaking"
    property string beforeVoice: "home"
    onVoiceStateChanged: {
        if (voiceState === "listening" && screen !== "assistant") { beforeVoice = screen; screen = "assistant"; wake() }
        if (voiceState === "idle" && screen === "assistant") voiceClose.restart()
        else voiceClose.stop()
    }
    // like the phone: a quick close after a plain "done", longer with a card to read, a moment after a miss
    readonly property string voiceStage: room.voice.stage || ""
    onVoiceStageChanged: if (voiceState === "idle" && screen === "assistant") voiceClose.restart()
    Timer { id: voiceClose; interval: room.voice.card ? 7000 : win.voiceStage === "miss" ? 3400 : 2600; onTriggered: if (win.screen === "assistant" && !win.talking) win.screen = win.beforeVoice === "assistant" ? "home" : win.beforeVoice }
    // a video: comes up as soon as it's asked for (after the assistant closes, if it's still showing)
    readonly property bool videoOn: room.video.active
    onVideoOnChanged: {
        if (videoOn) { if (screen === "assistant") beforeVoice = "video"; else screen = "video"; wake() }
        else { if (screen === "video") screen = "home"; if (beforeVoice === "video") beforeVoice = "home" }
    }
    readonly property bool alerting: room.alert && room.alert.kind !== undefined
    onAlertingChanged: if (alerting) wake()
    function wake() { lastTouch = Date.now() / 1000; standbyOn = false }
    function enterStandby() { screen = "home"; standbyOn = true }

    // burn-in care: the slow drift (see the stage) and the nightly refresh
    property real orbitAmp: standbyOn ? 28 : 6
    Behavior on orbitAmp { NumberAnimation { duration: 6000; easing.type: Easing.InOutSine } }
    // whole pixels, moved once every 20 s: a sub-pixel shift four times a second redrew the whole screen non-stop
    property real driftNow: Date.now() / 1000
    Timer { interval: 20000; running: true; repeat: true; onTriggered: win.driftNow = Date.now() / 1000 }
    readonly property real shiftX: Math.round(orbitAmp * Math.sin(2 * Math.PI * driftNow / 1260))
    readonly property real shiftY: Math.round(orbitAmp * Math.sin(2 * Math.PI * driftNow / 1740 + 1))
    property string refreshedOn: ""
    onNowChanged: {
        var at = timing.refreshAt
        if (!at || !standbyOn || alerting || talking || refreshRun.running) return
        var d = new Date(now * 1000), hm = Theme.two(d.getHours()) + ":" + Theme.two(d.getMinutes()), day = d.toDateString()
        if (hm === at && refreshedOn !== day) { refreshedOn = day; refreshRun.start() }
    }

    Timer { interval: win.screen === "music" && !win.standbyOn ? 250 : 1000; running: true; repeat: true; onTriggered: win.now = Date.now() / 1000 }
    // standby fully up: nothing underneath it is drawn (it was all still being rendered behind the black)
    readonly property bool covered: standbyOn && standby.opacity >= 1
    // the once-a-second tick
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var t = Date.now() / 1000
            if (win.screen === "music" || win.screen === "video" || win.sheetOpen || win.alerting || win.talking) win.lastTouch = t   // the player (and an alert) keeps it awake
            // scrolling, mouse moves and keys count as use too (seen by the app itself, so a list that takes the
            // scroll still counts); on standby only a real tap wakes it
            if (!win.standbyOn) win.lastTouch = Math.max(win.lastTouch, room.lastInput())
            var wait = win.screen !== "home" && win.screen !== "assistant" ? win.timing.menuStandbySec
                     : (win.lateNight ? win.timing.nightStandbySec : win.timing.standbySec)
            var want = t - win.lastTouch > wait
            if (want && !win.standbyOn) win.enterStandby()
            else if (!want && win.standbyOn) win.standbyOn = false
        }
    }
    onStandbyOnChanged: room.setScreenState(standbyOn, standbyOn && lateNight)
    onLateNightChanged: room.setScreenState(standbyOn, standbyOn && lateNight)
    Component.onCompleted: room.setScreenState(standbyOn, standbyOn && lateNight)

    Rectangle { anchors.fill: parent; color: "black" }

    Item {
        id: stage
        width: Theme.stageW; height: Theme.stageH
        anchors.centerIn: parent
        scale: Math.min(win.width / Theme.stageW, win.height / Theme.stageH)
        // burn-in care (an old LCD): everything drifts very slowly round a small loop, so nothing — the clock, a
        // label, a hairline — sits on the same pixels for hours. ±6 px while in use (unnoticeable), ±28 px on standby.
        transform: Translate { x: win.shiftX; y: win.shiftY }

        Home {
            now: visible ? win.now : 0
            opacity: win.screen === "home" ? 1 : 0
            visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
            onOpenMusic: win.screen = "music"
            onOpenRoom: (name) => { win.roomName = name; win.screen = "room" }
            onOpenClock: win.screen = "clock"
            onOpenWeather: win.screen = "weather"
            onOpenReminders: win.screen = "reminders"
            onOpenSettings: win.screen = "settings"
            onOpenAssistant: { win.beforeVoice = "home"; win.screen = "assistant"; room.listen() }
        }
        RoomScreen {
            name: win.roomName
            opacity: win.screen === "room" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        ClockScreen {
            now: visible ? win.now : 0
            opacity: win.screen === "clock" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        WeatherScreen {
            opacity: win.screen === "weather" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        SettingsScreen {
            opacity: win.screen === "settings" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        RemindersScreen {
            opacity: win.screen === "reminders" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        VideoScreen {
            ducked: win.talking
            opacity: win.screen === "video" ? 1 : 0; visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        Assistant {
            active: win.screen === "assistant"
            opacity: active ? 1 : 0; visible: opacity > 0 && !win.covered
            // in fast (it should feel instant after "Alexa"), out gently
            Behavior on opacity { NumberAnimation { duration: win.screen === "assistant" ? 150 : 300; easing.type: Easing.OutQuad } }
            onClose: win.screen = "home"
        }
        MusicPlayer {
            now: visible ? win.now : 0
            opacity: win.screen === "music" ? 1 : 0
            visible: opacity > 0 && !win.covered
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
            onPickingChanged: win.sheetOpen = picking || library
            onLibraryChanged: win.sheetOpen = picking || library
        }
        // standby fades in over 0.9 s (ease-out) and back out over 0.9 s when woken, as on the phone;
        // the plain and music faces crossfade over 0.8 s
        Item {
            id: standby
            anchors.fill: parent
            opacity: win.standbyOn ? 1 : 0
            visible: opacity > 0
            // "Alexa" from standby: out of the way at once
            Behavior on opacity { NumberAnimation { duration: !win.standbyOn && win.screen === "assistant" ? 150 : 900; easing.type: Easing.OutCubic } }
            Rectangle { anchors.fill: parent; color: "black" }
            Standby {
                id: plainFace
                now: visible ? win.now : 0
                night: win.lateNight
                dayTime: win.dayTime
                active: win.standbyOn
                opacity: win.musicFace ? 0 : 1
                visible: opacity > 0 && standby.visible
                Behavior on opacity { NumberAnimation { duration: 800 } }
            }
            MusicStandby {
                id: musicFace
                now: visible ? win.now : 0
                night: win.lateNight
                dayTime: win.dayTime
                opacity: win.musicFace ? 1 : 0
                visible: opacity > 0 && standby.visible
                Behavior on opacity { NumberAnimation { duration: 800 } }
            }
        }
        // an alarm, timer or reminder going off — over everything, standby included
        Alert {}
        // (checks) where the touch screen doesn't respond
        Repeater {
            model: showDead ? [[Theme.deadA0, Theme.deadB1]] : []
            Rectangle { y: modelData[0]; width: Theme.stageW; height: modelData[1] - modelData[0]; color: Qt.rgba(1, 0, 0, 0.18) }
        }
        // burn-in care: once a night (refreshAt, 04:00), while on standby, a minute of slow full-screen colour washes
        // exercises every pixel and clears any image that's started to stick
        Rectangle {
            id: refresher
            x: -100; y: -100; width: Theme.stageW + 200; height: Theme.stageH + 200
            visible: refreshRun.running
            color: "black"
            SequentialAnimation {
                id: refreshRun
                ColorAnimation { target: refresher; property: "color"; to: "#ffffff"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#ff0000"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#00ff00"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#0000ff"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#ffffff"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#808080"; duration: 8000 }
                ColorAnimation { target: refresher; property: "color"; to: "#000000"; duration: 12000 }
            }
            MouseArea { anchors.fill: parent; enabled: refreshRun.running; onClicked: { refreshRun.stop(); win.wake() } }
        }
    }

    // any touch while awake counts as activity (it never blocks the touch itself)
    PointHandler {
        target: null
        acceptedDevices: PointerDevice.AllDevices
        onActiveChanged: if (!win.standbyOn) win.lastTouch = Date.now() / 1000
    }

    // standby takes its own touches: only a real tap wakes it, and the tap doesn't also press what's underneath
    MouseArea {
        anchors.fill: parent
        enabled: win.standbyOn
        property real t0: 0
        property point p0
        onPressed: (e) => { t0 = Date.now(); p0 = Qt.point(e.x, e.y) }
        onReleased: (e) => {
            var held = Date.now() - t0
            var s = stage.scale, slop = 72 * s       // 30 phone points
            if (held < 40 || Math.abs(e.x - p0.x) > slop || Math.abs(e.y - p0.y) > slop) return
            var p = stage.mapFromItem(win.contentItem, e.x, e.y)
            var c = musicFace.coverRect
            var onCover = win.musicFace && p.x > c.x - 30 && p.x < c.x + c.width + 30 && p.y > c.y - 30 && p.y < c.y + c.height + 30
            win.wake()
            if (onCover) win.screen = "music"
        }
    }
    // ROOM_SHOT: save a picture of the screen and quit (used to check builds)
    Timer {
        interval: shotMs; running: shotPath !== ""
        onTriggered: win.contentItem.grabToImage(function (r) { r.saveToFile(shotPath); Qt.quit() })
    }
}
