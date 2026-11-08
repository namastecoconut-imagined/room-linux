import QtQuick
import QtQuick.Window

// Room on the Surface. Everything is drawn on a 1368 × 912 stage (the Surface Pro 6 at 200%), scaled to whatever
// the window is, so it stays sharp and proportioned on any 3:2 screen.
//
// Standby follows the iPhone panel exactly (NativePanel.tick, once a second):
//  • the music player (and any open sheet) keeps the panel awake — it never drops into standby there
//  • otherwise, standbySec (15 s) untouched → it goes back to home and standby fades in; night hours use
//    nightStandbySec if config sets one, else the same 15 s
//  • any other screen left alone for idleReturnSec (60 s) goes back to home
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
    // Esc: leave full screen (to reach the desktop); F11: back to full screen
    Shortcut { sequence: "Esc"; onActivated: win.visibility = Window.Windowed }
    Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }

    // the screen you're on while awake, and whether standby is showing over it
    property string screen: ["music", "room", "clock", "weather", "reminders", "assistant"].indexOf(startScreen) >= 0 ? startScreen : "home"
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

    readonly property bool alerting: room.alert && room.alert.kind !== undefined
    onAlertingChanged: if (alerting) wake()
    function wake() { lastTouch = Date.now() / 1000; standbyOn = false }
    function enterStandby() { screen = "home"; standbyOn = true }

    Timer { interval: 250; running: true; repeat: true; onTriggered: win.now = Date.now() / 1000 }
    // the once-a-second tick
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var t = Date.now() / 1000
            if (win.screen === "music" || win.sheetOpen || win.alerting) win.lastTouch = t   // the player (and an alert) keeps it awake
            var wait = win.lateNight ? win.timing.nightStandbySec : win.timing.standbySec
            var want = t - win.lastTouch > wait
            if (want && !win.standbyOn) win.enterStandby()
            else if (!want && win.standbyOn) win.standbyOn = false
            if (!win.standbyOn && t - win.lastTouch > win.timing.idleReturnSec && win.screen !== "home") win.screen = "home"
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

        Home {
            now: win.now
            opacity: win.screen === "home" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
            onOpenMusic: win.screen = "music"
            onOpenRoom: (name) => { win.roomName = name; win.screen = "room" }
            onOpenClock: win.screen = "clock"
            onOpenWeather: win.screen = "weather"
            onOpenReminders: win.screen = "reminders"
            onOpenAssistant: { win.screen = "assistant"; room.listen() }
        }
        RoomScreen {
            name: win.roomName
            opacity: win.screen === "room" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        ClockScreen {
            now: win.now
            opacity: win.screen === "clock" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        WeatherScreen {
            opacity: win.screen === "weather" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        RemindersScreen {
            opacity: win.screen === "reminders" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        Assistant {
            active: win.screen === "assistant"
            opacity: active ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            onClose: win.screen = "home"
        }
        MusicPlayer {
            now: win.now
            opacity: win.screen === "music" ? 1 : 0
            visible: opacity > 0
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
            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            Rectangle { anchors.fill: parent; color: "black" }
            Standby {
                id: plainFace
                now: win.now
                night: win.lateNight
                dayTime: win.dayTime
                active: win.standbyOn
                opacity: win.musicFace ? 0 : 1
                visible: opacity > 0 && standby.visible
                Behavior on opacity { NumberAnimation { duration: 800 } }
            }
            MusicStandby {
                id: musicFace
                now: win.now
                night: win.lateNight
                dayTime: win.dayTime
                opacity: win.musicFace ? 1 : 0
                visible: opacity > 0 && standby.visible
                Behavior on opacity { NumberAnimation { duration: 800 } }
            }
        }
        // an alarm, timer or reminder going off — over everything, standby included
        Alert {}
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
