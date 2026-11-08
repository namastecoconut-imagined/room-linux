import QtQuick
import QtQuick.Window

// Room on the Surface. Everything is drawn on a 1368 × 912 stage (the Surface Pro 6 at 200%), scaled to whatever
// the window is, so it stays sharp and proportioned on any 3:2 screen.
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
    property string screen: startScreen === "standby" || startScreen === "musicstandby" ? "standby" : startScreen === "music" ? "music" : "home"
    property real lastTouch: Date.now() / 1000
    readonly property bool playing: room.music.exists && room.music.playing
    readonly property bool night: {
        var h = new Date(now * 1000).getHours()
        return h >= 23 || h < 7
    }

    Timer { interval: 250; running: true; repeat: true; onTriggered: win.now = Date.now() / 1000 }
    // idle → standby after standbySec untouched
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: if (win.screen !== "standby" && win.now - win.lastTouch > room.standbySec) win.screen = "standby"
    }
    onScreenChanged: room.setStandby(screen === "standby")

    Rectangle { anchors.fill: parent; color: "black" }

    Item {
        id: stage
        width: Theme.stageW; height: Theme.stageH
        anchors.centerIn: parent
        scale: Math.min(win.width / Theme.stageW, win.height / Theme.stageH)

        Home {
            id: home
            now: win.now
            opacity: win.screen === "home" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
            onOpenMusic: win.screen = "music"
        }
        MusicPlayer {
            now: win.now
            opacity: win.screen === "music" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
            onBack: win.screen = "home"
        }
        Standby {
            now: win.now
            night: win.night
            opacity: win.screen === "standby" && !(win.playing || startScreen === "musicstandby") ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
        }
        MusicStandby {
            now: win.now
            opacity: win.screen === "standby" && (win.playing || startScreen === "musicstandby") ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
        }
    }

    // any touch: note it (for the idle timer) and, on standby, wake to home. It never blocks the touch itself.
    PointHandler {
        target: null
        acceptedDevices: PointerDevice.AllDevices
        onActiveChanged: {
            win.lastTouch = Date.now() / 1000
            if (active && win.screen === "standby") wakeTimer.start()
        }
    }
    // standby swallows the tap that wakes it, so it doesn't also press whatever's under the finger on home
    MouseArea {
        anchors.fill: parent
        enabled: win.screen === "standby"
        // on music standby, tapping the cover opens the player; anywhere else wakes to home
        onPressed: (e) => {
            win.lastTouch = Date.now() / 1000
            var p = stage.mapFromItem(win.contentItem, e.x, e.y)
            var onCover = (win.playing || startScreen === "musicstandby") && p.x > 700 && p.x < 1300 && p.y > 96 && p.y < 696
            win.screen = onCover ? "music" : "home"
        }
    }
    // ROOM_SHOT: save a picture of the screen and quit (used to check builds)
    Timer {
        interval: shotMs; running: shotPath !== ""
        onTriggered: win.contentItem.grabToImage(function (r) { r.saveToFile(shotPath); Qt.quit() })
    }
    Timer { id: wakeTimer; interval: 1; onTriggered: win.lastTouch = Date.now() / 1000 }
}
