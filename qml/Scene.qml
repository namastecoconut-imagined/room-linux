import QtQuick
import QtQuick.Effects

// Room in the redesign (room-motion.html, HANDOFF.md): Home, the player, standby and the Room screen are one scene,
// so things travel between them rather than cutting — the song card grows into the player, the clock shrinks into
// the top bar, everything settles into standby. Each piece sits where its view puts it and glides there
// (cubic-bezier .22 1 .36 1: 0.85 s for moves, 0.7 s for fades, each piece 16 ms after the one before).
// Behind it all, the Field (the song's colours); over it, the vignette (Main). The Clock, Weather, Reminders and
// Settings screens (view "other") still have their own screens, over the Field.
//
// The touch screen doesn't answer between y 118 and 500 (Theme.deadA0 – deadB1): nothing tappable or draggable sits
// there — only the clock, the glance list, up next, the song's words. Laid out on the 1368 × 912 stage.
Item {
    id: sc
    width: 1368; height: 912
    property string view: "home"              // home · player · standby · room · other
    property string roomName: ""
    property real now: Date.now() / 1000
    property bool night: false
    property bool dayTime: true
    property bool musicFace: false            // standby with the music (Main: only while it's actually playing)
    property string sheet: ""                 // an open sheet: scenes · speakers · library
    signal openPlayer()
    signal openRoom(string name)
    signal openClock()
    signal openWeather()
    signal openReminders()
    signal openSettings()
    signal goHome()

    readonly property bool hV: view === "home"
    readonly property bool pV: view === "player"
    readonly property bool sV: view === "standby"
    readonly property bool rV: view === "room"
    readonly property bool oV: view === "other"
    readonly property bool menu: rV || oV

    // ---------------------------------------------------------------- what's playing
    readonly property var music: room.music
    readonly property bool exists: music.exists === true
    readonly property bool live: exists && !music.idle                    // Home's card shows the song
    readonly property bool m: sV ? musicFace : live                      // "music" for this view
    readonly property bool spotify: music.source !== "airplay"
    readonly property var field: music.field || ({})
    // the song's place: after a seek, hold the new place until the player reports it (Spotify takes a second or two)
    property real seekTo: -1
    property real seekAt: 0
    // the song's place moves smoothly: while it's on screen and playing, its clock ticks 20 times a second (in step
    // with the background, which redraws that often anyway — so no extra drawing), not once a second in jumps
    property real fineNow: 0
    Timer {
        id: fine
        interval: 50; repeat: true
        running: sc.visible && sc.music.playing === true && prog.opacity > 0
        onTriggered: sc.fineNow = Date.now() / 1000
    }
    readonly property real tNow: fine.running && fineNow > 0 ? fineNow : now
    readonly property real livePos: exists ? Math.min(music.duration || 0, (music.position || 0) + (music.playing ? tNow - music.at : 0)) : 0
    readonly property real pos: seekTo >= 0 && tNow - seekAt < 4 && Math.abs(livePos - (seekTo + (music.playing ? tNow - seekAt : 0))) > 2
                                ? Math.min(music.duration || 0, seekTo + (music.playing ? tNow - seekAt : 0)) : livePos
    function seek(f) { var s = f * (music.duration || 0); seekTo = s; seekAt = tNow; room.seek(s) }
    function mmss(s) { s = Math.max(0, Math.round(s)); return Math.floor(s / 60) + ":" + Theme.two(s % 60) }

    // a new song: the old cover and words blur away (0.42 s), the new ones resolve in, one after another (90 ms)
    readonly property string songKey: exists ? (music.title || "") + "|" + (music.artist || "") : ""
    property string sTitle: ""
    property string sArtist: ""
    property string sAlbum: ""
    property string sArt: ""
    property real kCover: 1
    property real kSb: 1
    property real kTitle: 1
    property real kWords: 1
    function commitSong() {
        sTitle = music.title || ""; sArtist = music.artist || ""; sAlbum = music.album || ""; sArt = music.art || ""
        if (swipeWait) { swipeWait = false; swipeBack.stop(); slideIn(-swipeDir) }     // the new cover comes in from the other side
    }

    // the player's cover, swiped: it follows your finger; let go past 36 px and it flies off that way (the song
    // skips), and the next cover slides in from the other side once the player has moved on (or the same one comes
    // back after 3 s if it didn't)
    property real swipeX: 0
    property real swipeO: 1
    property int swipeDir: 0
    property bool swipeWait: false
    readonly property bool swiping: swipeWait || flyOut.running || slideInA.running || swipeX !== 0
    function flyAway(dir) {
        swipeDir = dir; slideInA.stop()
        flyOut.to = dir * (cover.width + 160); flyOut.start(); fadeOut.start()
        if (dir < 0) room.next(); else room.previous()
        swipeWait = true; swipeBack.restart()
    }
    function slideIn(from) {
        flyOut.stop(); fadeOut.stop()
        swipeX = from * cover.width * 0.45; swipeO = 0
        slideInA.restart()
    }
    function swipeReset() { swipeWait = false; swipeBack.stop(); flyOut.stop(); fadeOut.stop(); slideInA.stop(); swipeX = 0; swipeO = 1 }
    onPVChanged: if (!pV) swipeReset()
    NumberAnimation { id: flyOut; target: sc; property: "swipeX"; duration: 260; easing.type: Easing.InCubic }
    NumberAnimation { id: fadeOut; target: sc; property: "swipeO"; to: 0; duration: 260; easing.type: Easing.InQuad }
    ParallelAnimation {
        id: slideInA
        NumberAnimation { target: sc; property: "swipeX"; to: 0; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
        NumberAnimation { target: sc; property: "swipeO"; to: 1; duration: 420; easing.type: Easing.OutQuad }
    }
    NumberAnimation { id: springBack; target: sc; property: "swipeX"; to: 0; duration: 380; easing.type: Easing.OutBack }
    Timer { id: swipeBack; interval: 3000; onTriggered: { sc.swipeWait = false; sc.slideIn(sc.swipeDir) } }
    onSongKeyChanged: if (sTitle === "" && sArtist === "") commitSong(); else if (songKey !== "") swap.restart()
    Connections { target: sc; function onMusicChanged() { if (!swap.running && sc.songKey !== "" && (sc.music.art || "") !== sc.sArt) sc.sArt = sc.music.art || "" } }
    Component.onCompleted: commitSong()
    component In: NumberAnimation { to: 1; duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: sc; properties: "kCover,kSb,kTitle,kWords"; to: 0; duration: 420; easing.type: Easing.InQuad }
        ScriptAction { script: sc.commitSong() }
        ParallelAnimation {
            In { target: sc; property: "kCover" }
            SequentialAnimation { PauseAnimation { duration: 90 } In { target: sc; property: "kSb" } }
            SequentialAnimation { PauseAnimation { duration: 180 } In { target: sc; property: "kTitle" } }
            SequentialAnimation { PauseAnimation { duration: 270 } In { target: sc; property: "kWords" } }
        }
    }

    // ---------------------------------------------------------------- what's going on (only what's real)
    readonly property var wx: room.weather
    readonly property var things: room.things
    readonly property var timers: (things.timers || []).filter(function (t) { return !t.done })
    readonly property var due: (things.reminders || []).filter(function (r) { return !r.done && (r.today || r.dueNow) })
    readonly property var nextAlarm: things.nextAlarm || ({})
    readonly property var ev: room.events || []
    readonly property var rooms: room.rooms || []
    readonly property var lit: rooms.filter(function (r) { return r.on > 0 })
    readonly property var date: new Date(now * 1000)
    readonly property string wxLine: {
        if (!wx || wx.ok !== true) return ""
        var r = Theme.rainAt(wx.hours)
        return (wx.t !== undefined ? wx.t + "° " : "") + (wx.d || "").toLowerCase()
               + (r >= 0 ? " · rain at " + Theme.hourText(wx.hours[r].h, room.clock24) : "")
    }
    readonly property string alarmText: nextAlarm.h !== undefined
        ? Theme.hm(nextAlarm.h, nextAlarm.m, room.clock24) + (room.clock24 ? "" : " " + Theme.ampm(nextAlarm.h, false)) : ""
    function dueTime(r) { var w = r.when || ""; var i = w.indexOf(" · "); return i >= 0 ? w.slice(i + 3) : w }
    // everything worth showing, in this order (room-motion.html facts())
    readonly property var facts: {
        var f = []
        if (timers.length) { var t = timers[0]; f.push({ k: "timer", label: "Timer" + (t.label ? " · " + t.label : ""), val: Theme.countdown(t.left), bar: t.total > 0 ? 1 - t.left / t.total : 0 }) }
        if (wxLine) f.push({ k: "wx", label: "Weather", val: wxLine })
        if (ev.length) f.push({ k: "next", label: "Next · " + ev[0].when, val: ev[0].title, sub: ev.length > 1 ? "Then " + ev[1].title + ", " + ev[1].when : (ev[0].extra || "") })
        if (alarmText) f.push({ k: "alarm", label: "Alarm", val: alarmText, sub: nextAlarm.in ? "In " + nextAlarm.in : "" })
        if (due.length) f.push({ k: "rem", label: "Reminders", val: due.length + " today", sub: due[0].text + (dueTime(due[0]) ? " · " + dueTime(due[0]) : "") })
        if (rooms.length) f.push({ k: "lights", label: "Lights", val: lit.length ? lit.length + (lit.length === 1 ? " room on" : " rooms on") : "All off",
                                   sub: lit.map(function (r) { return Theme.shortName(r.name) + " " + r.level }).join(" · ") })
        return f
    }
    readonly property var glance: {
        var g = [{ k: "date", kind: "date", text: Qt.formatDate(date, "dddd, d MMM") }]
        facts.forEach(function (f) {
            if (f.k === "lights") return
            if (f.k === "timer") g.push({ k: "timer", kind: "timer", text: f.label + " · " + f.val, bar: f.bar })
            else if (f.k === "wx") g.push({ k: "wx", text: f.val })
            else if (f.k === "next") g.push({ k: "next", text: "Next · " + f.val + " " + ev[0].when })
            else if (f.k === "alarm") g.push({ k: "alarm", text: "Alarm · " + f.val })
            else if (f.k === "rem") g.push({ k: "rem", text: due.length + (due.length === 1 ? " reminder today" : " reminders today") })
        })
        return g
    }

    // ---------------------------------------------------------------- the background
    readonly property real lift: m && !menu && field.lum !== undefined ? Math.max(0, Math.min(0.4, (field.lum - 0.22) * 1.2)) : 0
    readonly property var curRoom: {
        for (var i = 0; i < rooms.length; i++) if (rooms[i].name === roomName) return rooms[i]
        return null
    }
    Field {
        id: bg
        cover: sc.field
        mode: sc.rV ? "room" : sc.m ? "music" : "idle"
        playing: sc.m && !sc.rV && sc.music.playing === true
        roomColour: roomV.light
        roomOn: sc.curRoom && sc.curRoom.on > 0 ? sc.curRoom.level / 100 : 0
        k: sc.sV ? 0.75 : 1
        lightA: sc.rV ? (sc.curRoom && sc.curRoom.on > 0 ? 0.8 : 0.2) : sc.sV ? 0.9 : 0.95
        // standby: darker overall, so its lights stand out further from the base to keep their movement visible
        pop: sc.sV ? 1.8 : 1.45
        dim: sc.sV ? 0.35 : sc.pV ? Math.max(0.1, sc.lift) : sc.oV ? 0.3 : sc.lift
        fps: sc.sV ? (sc.night ? 8 : sc.dayTime ? 12 : 10) : 20
        glassRect: card.opacity > 0.01 ? Qt.rect(card.x, card.y, card.width, card.height) : Qt.rect(0, 0, 0, 0)
    }

    // ---------------------------------------------------------------- the pieces
    component Mover: Item {
        id: mv
        property int order: 0
        transformOrigin: Item.TopLeft
        visible: opacity > 0.002
        Behavior on x { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        Behavior on y { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        Behavior on width { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        Behavior on height { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        Behavior on scale { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: mv.order * 16 } NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
    }
    // something you press: shrinks a touch (0.94) while pressed
    component Tap: Press { pressScale: 0.94 }
    component Btn: Tap {
        id: b
        property alias text: lb.text
        property color ink: Theme.w62
        width: lb.implicitWidth + 16; height: 44
        Mono { id: lb; anchors.centerIn: parent; color: b.ink }
    }

    // ================================================================= Home's song card (it grows into the player)
    Mover {
        id: card
        order: 1
        x: sc.pV ? 44 : 690; y: sc.pV ? 140 : 128
        width: sc.pV ? 1280 : 420; height: sc.pV ? 730 : 740
        opacity: sc.hV || sc.pV ? 1 : 0
        Pane { anchors.fill: parent }
        MouseArea { anchors.fill: parent; enabled: sc.hV && sc.live; onClicked: sc.openPlayer() }
    }
    Mover {
        id: cover
        order: 2
        x: sc.pV ? 72 : 706; y: sc.pV ? 168 : 144
        width: sc.pV ? 674 : 388; height: sc.pV ? 674 : 388     // (not "height: width": that would chase the moving width and lag)
        opacity: (sc.hV && sc.m) || sc.pV ? sc.kCover : 0
        // a new song's blur (not while a swipe carries the cover past its edges: the blur would clip it)
        layer.enabled: sc.kCover < 0.999 && !sc.swiping
        layer.effect: MultiEffect { blurEnabled: true; blur: 1 - sc.kCover; blurMax: 32 }
        Item {
            anchors.fill: parent
            opacity: sc.swipeO
            scale: coverTap.dip
            transform: Translate { x: sc.swipeX }
            RectangularShadow { anchors.fill: parent; offset.y: 24; blur: 50; spread: -14; radius: 14; color: Qt.rgba(0, 0, 0, 0.6) }
            Art {
                anchors.fill: parent; radius: 14
                source: sc.sArt; rgb: sc.music.rgb || [201, 185, 163]; rgb2: sc.music.rgb2 || [44, 40, 34]
            }
        }
        // the player's cover: tap to play / pause; swipe sideways to skip — it follows your finger (its lower part:
        // the screen answers there)
        MouseArea {
            anchors.fill: parent; enabled: sc.pV && sc.exists
            preventStealing: true
            property real x0: 0
            onPressed: (e) => { x0 = e.x; coverTap.press(); if (!sc.swipeWait) { sc.swipeReset(); springBack.stop() } }
            onPositionChanged: (e) => { if (!sc.swipeWait) sc.swipeX = (e.x - x0) * 0.9 }
            onReleased: (e) => {
                var dx = e.x - x0
                coverTap.release()
                if (sc.swipeWait) return
                if (Math.abs(dx) > 36) sc.flyAway(dx < 0 ? -1 : 1)
                else { springBack.start(); if (Math.abs(dx) < 20) room.playPause() }
            }
            onCanceled: { coverTap.release(); if (!sc.swipeWait) springBack.start() }
        }
        // a tap on the cover shows like any button's: it dips and springs back
        QtObject {
            id: coverTap
            property real dip: 1
            property real t0: 0
            function press() { t0 = Date.now(); cUp.stop(); cDown.restart() }
            function release() { cDown.stop(); cUp.restart() }
        }
        NumberAnimation { id: cDown; target: coverTap; property: "dip"; to: 0.97; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { id: cUp; target: coverTap; property: "dip"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    Mover {
        id: title
        order: 3
        x: sc.pV ? 790 : sc.sV ? 236 : 722; y: sc.pV ? 170 : sc.sV ? 722 : 556
        scale: sc.pV ? 2.2 : 1
        width: sc.pV ? 232 : sc.sV ? 560 : 376; height: tc.height
        opacity: sc.hV || sc.pV || (sc.sV && sc.m) ? sc.kTitle : 0
        layer.enabled: sc.kTitle < 0.999
        layer.effect: MultiEffect { blurEnabled: true; blur: 1 - sc.kTitle; blurMax: 32 }
        Column {
            id: tc
            width: parent.width
            // 30 px on 36 px lines (line-height 1.2), the type centred in each line as the design has it
            T { width: parent.width; height: 36; verticalAlignment: Text.AlignVCenter; text: sc.live || sc.sV ? sc.sTitle : "Nothing playing"; font.pixelSize: 30; color: "white" }
            T { width: parent.width; height: 36; verticalAlignment: Text.AlignVCenter; text: sc.live || sc.sV ? sc.sArtist : "Pick up where you left off"; font.pixelSize: 30; color: Theme.w62 }
        }
    }
    // where it's playing: on Home just the words (a target that small isn't worth aiming at); in the player a proper
    // button beside the volume (where it plays, how loud), for choosing the speaker (Spotify only)
    Mover {
        id: meta
        order: 4
        x: sc.pV ? 792 : 722; y: sc.pV ? 660 : 632
        width: 360; height: sc.pV ? 44 : 30
        opacity: (sc.hV || sc.pV) && sc.live ? 1 : 0
        readonly property real room_: sc.pV && sc.live && sc.spotify ? spk.width + 28 : 0     // what the volume leaves it
        Tap {
            id: spk
            enabled: sc.pV && sc.spotify
            width: Math.min(260, spkL.implicitWidth + (sc.pV ? 36 : 0)); height: parent.height
            onTapped: { room.refreshDevices(); sc.sheet = "speakers" }
            Rectangle {
                anchors.fill: parent; radius: 8; color: "transparent"
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3)
                opacity: sc.pV && sc.spotify ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }
            }
            Mono {
                id: spkL; anchors.centerIn: parent; size: 13; width: Math.min(implicitWidth, 260 - 36); elide: Text.ElideRight
                color: sc.pV ? "white" : Theme.w62
                text: (sc.music.device || (sc.spotify ? "Choose a speaker" : "AirPlay")) + (sc.pV && sc.spotify ? "  ▾" : "")
            }
        }
    }
    Mover {
        id: prog
        order: 5
        x: sc.pV ? 792 : sc.sV ? 236 : 722; y: sc.pV ? 516 : sc.sV ? 800 : 672
        width: sc.pV ? 500 : sc.sV ? 520 : 356; height: 48
        opacity: ((sc.hV && sc.live) || sc.pV || (sc.sV && sc.m)) && (sc.music.duration || 0) > 0 ? 1 : 0
        Seek {
            id: seek
            y: -14; width: parent.width                 // the line on the box's top edge (the design's margin-top: -14px)
            shadow: true
            value: sc.music.duration > 0 ? sc.pos / sc.music.duration : 0
            enabled: sc.music.canSeek !== false && !sc.sV
            live: false
            onReleased: (v) => sc.seek(v)
        }
        Item {
            y: 18; width: parent.width; height: 16
            Mono { size: 12; color: Theme.w62; text: sc.mmss(seek.shown * (sc.music.duration || 0)) }
            Mono { anchors.right: parent.right; size: 12; color: Theme.w62; text: "-" + sc.mmss((1 - seek.shown) * (sc.music.duration || 0)) }
        }
    }
    Mover {
        id: vol
        order: 6
        x: sc.pV ? 792 : 722; y: sc.pV ? 667 : 724
        width: sc.pV ? 500 : 356; height: 30
        opacity: (sc.hV || sc.pV) && sc.music.canVolume !== false && sc.exists ? 1 : 0
        property real dragV: -1
        property real inset: meta.room_
        Behavior on inset { NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        Mono { x: vol.inset; anchors.verticalCenter: parent.verticalCenter; size: 13; color: Theme.w62; text: "Vol" }
        Seek {
            id: volSeek
            x: vol.inset + 41; width: parent.width - vol.inset - 41 - 42
            value: (sc.music.volume || 0) / 100
            every: 80
            onMoved: (v) => room.setVolumeLive(Math.round(v * 100))
            onReleased: (v) => room.setVolume(Math.round(v * 100))
        }
        Mono { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 13; text: Math.round(volSeek.shown * 100) }
    }
    Mover {
        id: btns
        order: 7
        x: sc.pV ? 792 : 722; y: sc.pV ? 578 : 790
        scale: sc.pV ? 1.25 : 1
        width: 300; height: 44
        opacity: sc.hV || sc.pV ? 1 : 0
        Mono { id: pauseRef; visible: false; text: "Pause" }          // the pill keeps Pause's width when it says Play
        Row {
            spacing: 12; height: parent.height
            Tap {
                width: (sc.live ? Math.max(ppL.implicitWidth, pauseRef.implicitWidth) : ppL.implicitWidth) + 40 + 26; height: 44
                onTapped: sc.live ? room.playPause() : room.playLiked()
                Rectangle { anchors.fill: parent; radius: 8; color: "white" }
                Row {
                    anchors.centerIn: parent; spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; size: 16; color: "#2b1810"; name: sc.live && sc.music.playing ? "pause" : "play" }
                    Mono { id: ppL; anchors.verticalCenter: parent.verticalCenter; color: "#2b1810"; text: !sc.live ? "Liked songs" : sc.music.playing ? "Pause" : "Play" }
                }
            }
            Tap {
                visible: sc.live; width: 40; height: 44
                onTapped: room.previous()
                Icon { anchors.centerIn: parent; name: "prev"; size: 20; color: "white" }
            }
            Tap {
                visible: sc.live; width: 30; height: 44
                onTapped: room.next()
                Icon { anchors.centerIn: parent; name: "next"; size: 20; color: "white" }
            }
            Tap {             // nothing playing: your playlists (outlined, so it reads as a button)
                visible: !sc.live; width: plL.implicitWidth + 36; height: 44
                onTapped: sc.sheet = "library"
                Rectangle { anchors.fill: parent; radius: 8; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
                Mono { id: plL; anchors.centerIn: parent; color: "white"; text: "Playlists" }
            }
        }
    }
    Mover {
        id: upn
        order: 8
        x: 792; y: 358; scale: 0.9
        opacity: sc.pV && (sc.music.nextUp || []).length > 0 ? 1 : 0
        width: 460; height: upc.height
        Column {
            id: upc
            Mono { color: Theme.w62; text: "Up next"; height: 34; verticalAlignment: Text.AlignVCenter }
            Repeater { model: (sc.music.nextUp || []).slice(0, 2); Mono { width: 460; height: 34; verticalAlignment: Text.AlignVCenter; text: modelData.title } }
        }
    }
    Mover {
        id: lib
        order: 9
        // the names end level with the big cover's bottom edge, the card's own margin below them (no heading: the
        // covers and their names say what they are, and it left the row crowding the card's edge)
        x: 792; y: 842 - 104
        opacity: sc.pV ? 1 : 0
        width: 500; height: 104
        readonly property var lists: [{ name: "Liked songs", uri: "liked", art: "" }].concat(sc.music.playlists || [])
        Row {
            spacing: 16
            Repeater {
                model: lib.lists.slice(0, 4)
                Tap {
                    width: 80; height: 104
                    onTapped: modelData.uri === "liked" ? room.playLiked() : room.playUri(modelData.uri)
                    Art { width: 80; height: 80; radius: 8; source: modelData.art || ""; liked: modelData.uri === "liked"
                          rgb: [[140, 94, 78], [78, 110, 140], [110, 140, 94], [140, 122, 78]][index % 4]; rgb2: [21, 21, 21] }
                    Mono { y: 88; width: 80; size: 11; text: modelData.name }
                }
            }
            Tap {
                width: 80; height: 104
                onTapped: sc.sheet = "library"
                Rectangle { width: 80; height: 80; radius: 8; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
                            Mono { anchors.centerIn: parent; size: 12; text: "All ›" } }
                Mono { y: 88; size: 11; text: Math.max(0, lib.lists.length - 4) + " more" }
            }
        }
    }

    // ================================================================= the clock (it travels: Home, top bar, standby)
    Mover {
        id: clock
        order: 10
        x: sc.hV ? 40 : (sc.pV || sc.rV) ? 652 : sc.sV ? (sc.m ? 56 : 52) : 652
        y: sc.hV ? 120 : (sc.pV || sc.rV) ? 38 : sc.sV ? (sc.m ? 52 : 150) : 38
        scale: sc.hV ? 1 : (sc.pV || sc.rV) ? 0.2 : sc.sV ? (sc.m ? 0.38 : 1.28) : 0.2
        opacity: sc.oV ? 0 : 1
        width: clockT.implicitWidth; height: clockT.implicitHeight
        Serif {
            id: clockT
            text: Theme.clock(sc.date, room.clock24)
            font.pixelSize: 250; font.letterSpacing: -7.5
        }
    }

    // ================================================================= Home: the glance list, the footer, the lights
    Mover {
        id: info
        order: 11
        x: 48; y: 392; width: 560; height: 360
        opacity: sc.hV ? 1 : 0
        GlanceList { items: sc.glance }
    }
    Mover {
        id: foot
        order: 12
        x: 48; y: 824
        opacity: sc.hV ? 1 : 0
        width: 400; height: 50
        Column {
            spacing: 4
            Mono { color: Theme.w62; text: "Room · " + (room.here ? room.here.toLowerCase() + " panel" : "panel") }
            Mono {
                color: Theme.w62
                // and how warm it is (the old standby's "⚡ Cool": Cool / Normal / Warm / Hot from the CPU sensor)
                readonly property string warm: (room.status || "").replace("⚡", "").trim()
                text: "Surface · " + (room.battery.pct === undefined ? "plugged in" : room.battery.charging ? "plugged in" : room.battery.pct + "%")
                      + (warm ? " · " + warm : "")
            }
        }
    }
    // top bar, left: Home · Alarms · Weather · Reminders · Scenes
    Mover {
        id: nav
        order: 13
        x: 44; y: 34
        opacity: sc.hV ? 1 : 0
        width: navR.width; height: 44
        Row {
            id: navR
            spacing: 20; height: 44
            Mono { anchors.verticalCenter: parent.verticalCenter; text: "Home"; rightPadding: 8 }
            Btn { text: "Alarms"; onTapped: sc.openClock() }
            Btn { text: "Weather"; onTapped: sc.openWeather() }
            Btn { text: "Reminders"; onTapped: sc.openReminders() }
            Btn { text: "Scenes"; onTapped: sc.sheet = "scenes" }
        }
    }
    // top bar, right: All off · Dim · Night · the mic · settings
    Mover {
        id: ctl
        order: 14
        x: 1332 - 640; y: 34        // a fixed box, its row kept to the right edge (a width that follows the row would
        opacity: sc.hV || sc.pV ? 1 : 0     // drag x behind it, easing, every time a label changed)
        width: 640; height: 44
        Row {
            id: ctlR
            anchors.right: parent.right
            spacing: 12; height: 44
            Btn { text: "All off"; onTapped: room.allOff() }
            Btn { text: "Dim"; onTapped: room.dimAll() }
            Btn { text: "Night"; onTapped: room.night() }
            // (boxes a little wider than what's drawn, so the gaps read as the design's 28 px)
            Orb {
                anchors.verticalCenter: parent.verticalCenter; width: 40; height: 44
                ready: room.voice.state !== undefined && room.voice.state !== "off"
                listening: room.voice.state === "listening"
                voice: listening ? room.voiceLevel : 0
                onTapped: room.listen()
            }
            Tap {
                width: 40; height: 44
                onTapped: sc.openSettings()
                Icon { anchors.centerIn: parent; name: "set"; size: 22; color: "white" }
            }
        }
    }
    // the player and the Room screen: ‹ Home
    Mover {
        id: back
        order: 15
        x: 36; y: 34
        opacity: sc.pV || sc.rV ? 1 : 0
        width: 120; height: 44
        Tap {
            anchors.fill: parent
            onTapped: sc.goHome()
            Row {
                anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 10
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "back"; size: 20; color: "white" }
                Mono { anchors.verticalCenter: parent.verticalCenter; text: "Home" }
            }
        }
    }
    // the Room screen's top bar: Turn off / on · settings
    Mover {
        id: roomTop
        order: 16
        x: 1332 - 640; y: 34
        opacity: sc.rV ? 1 : 0
        width: 640; height: 44
        Row {
            id: rtR
            anchors.right: parent.right
            spacing: 12; height: 44
            Btn { text: sc.curRoom && sc.curRoom.on > 0 ? "Turn off" : "Turn on"; ink: "white"; onTapped: room.toggleRoom(sc.roomName) }
            Tap { width: 40; height: 44; onTapped: sc.openSettings(); Icon { anchors.centerIn: parent; name: "set"; size: 22; color: "white" } }
        }
    }
    Mover {
        id: roomV
        order: 17
        x: 0; y: sc.rV ? 0 : 24
        width: 1368; height: 912
        opacity: sc.rV ? 1 : 0
        property alias light: rview.light
        RoomView { id: rview; r: sc.curRoom }
    }

    // Home's lights: each room's name ›, its level, a thin line (tap the name for the room, drag the line, tap the number)
    Mover {
        id: lightsCap
        order: 21
        x: 1150; y: 540
        opacity: sc.hV ? 1 : 0
        width: 180; height: 20
        Mono { color: Theme.w62; text: "Lights" }
    }
    Repeater {
        model: sc.rooms
        Mover {
            id: rw
            order: 22 + index
            readonly property real gap: Math.min(68, (880 - 582) / Math.max(1, sc.rooms.length))
            readonly property bool reach: modelData.reachable !== 0 && modelData.reachable !== false
            readonly property int lv: modelData.on > 0 ? modelData.level : 0
            x: 1150; y: 582 + index * gap; width: 180; height: 66
            opacity: sc.hV ? (rw.lv > 0 ? 1 : 0.5) : 0
            property real local: 0
            readonly property real f: drag.pressed ? local : lv / 100
            property real shownLv: drag.pressed ? Math.round(local * 100) : lv
            Behavior on shownLv { enabled: !drag.pressed; NumberAnimation { duration: 700; easing.type: Easing.OutQuart } }
            Tap {
                width: nm.implicitWidth + 8; height: 26
                onTapped: sc.openRoom(modelData.name)
                Mono { id: nm; text: Theme.shortName(modelData.name) + " ›"; width: Math.min(implicitWidth, 140) }
            }
            Tap {
                anchors.right: parent.right; width: 40; height: 26
                enabled: rw.reach
                onTapped: room.toggleRoom(modelData.name)
                Mono { anchors.right: parent.right; text: !rw.reach ? "—" : Math.round(rw.shownLv) > 0 ? Math.round(rw.shownLv) : "—" }
            }
            Item {
                y: 32; width: parent.width; height: 2
                Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.2) }
                Rectangle {
                    width: parent.width * rw.f; height: 2; color: "white"
                    Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
                }
                Glow {
                    x: parent.width * rw.f - 15; y: -6; width: 30; height: 14
                    color: Qt.rgba(1, 220 / 255, 180 / 255, 1); strength: 0.95
                    opacity: rw.f > 0 ? 1 : 0
                    Behavior on x { enabled: !drag.pressed; NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
                    Behavior on opacity { NumberAnimation { duration: 600 } }
                }
            }
            Timer { id: send; interval: 120; onTriggered: rw.apply(Math.round(rw.local * 100)) }
            function apply(v) { if (v <= 0) room.roomOff(modelData.name); else room.setRoomLevel(modelData.name, v) }
            MouseArea {
                id: drag
                x: 0; y: 22; width: parent.width; height: 44
                enabled: rw.reach && sc.hV
                preventStealing: true
                function at(x) { return Math.max(0, Math.min(1, x / width)) }
                onPressed: (e) => { rw.local = at(e.x) }
                onPositionChanged: (e) => { rw.local = at(e.x); if (!send.running) send.start() }
                onReleased: { send.stop(); rw.apply(Math.round(rw.local * 100)) }
            }
        }
    }

    // ================================================================= standby
    Mover {
        id: words
        order: 22 + sc.rooms.length
        x: 0; y: 0; width: 1368; height: 912
        opacity: sc.sV && sc.m ? sc.kWords : 0
        StandbyWords { artist: sc.sArtist.toLowerCase(); title: sc.sTitle.toLowerCase(); album: sc.sAlbum.toLowerCase(); running: words.visible }
    }
    Mover {
        id: sbTop
        order: 23 + sc.rooms.length
        x: sc.m ? 1324 - 600 : 56; y: sc.m ? 54 : 520
        width: 600; height: 60
        opacity: sc.sV ? 1 : 0
        Column {
            width: parent.width
            Mono { width: parent.width; height: 28; verticalAlignment: Text.AlignVCenter; horizontalAlignment: sc.m ? Text.AlignRight : Text.AlignLeft; text: Qt.formatDate(sc.date, "dddd, d MMMM") }
            Mono { width: parent.width; height: 28; verticalAlignment: Text.AlignVCenter; horizontalAlignment: sc.m ? Text.AlignRight : Text.AlignLeft; text: sc.wxLine; color: Theme.w62 }
        }
    }
    Mover {
        id: sbMods
        order: 24 + sc.rooms.length
        readonly property var mods: sc.facts.filter(function (f) { return f.k !== "wx" }).slice(0, sc.m ? 4 : 5)
        readonly property int cols: sc.m ? 2 : Math.max(1, mods.length)
        readonly property real mw: sc.m ? 240 : Math.min(300, 1256 / Math.max(1, mods.length) - 24)
        x: sc.sV ? (sc.m ? 820 : 56) : 56; y: sc.sV ? (sc.m ? 700 : 640) : 760
        width: sc.m ? 504 : 1256; height: 170
        opacity: sc.sV ? 1 : 0
        Repeater {
            model: sbMods.mods
            Item {
                x: (index % sbMods.cols) * (sbMods.mw + 24); y: Math.floor(index / sbMods.cols) * 84
                width: sbMods.mw; height: 80
                Mono { size: 12; color: Theme.w42; text: modelData.label; width: parent.width }
                Text {
                    id: val
                    // a one-line box exactly the type's size, the glyphs centred in it (CSS line-height: 1)
                    y: 21; width: parent.width; height: font.pixelSize
                    text: modelData.val
                    font.family: modelData.k === "timer" ? Theme.serif : Theme.face
                    font.pixelSize: modelData.k === "timer" ? (sc.m ? 40 : 54) : (sc.m ? 22 : 26)
                    color: modelData.k === "timer" ? Theme.timer2 : "white"
                    renderType: Text.QtRendering; elide: Text.ElideRight
                    FontMetrics { id: vfm; font: val.font }
                    transform: Translate { y: (val.font.pixelSize - vfm.height) / 2 }
                }
                Item {
                    visible: modelData.bar !== undefined
                    y: val.y + val.height + 12; width: parent.width; height: 2
                    Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.2) }
                    RectangularShadow { width: parent.width * (modelData.bar || 0); height: 2; blur: 10; color: Qt.rgba(1, 190 / 255, 122 / 255, 0.7); visible: width > 1 }
                    Rectangle { width: parent.width * (modelData.bar || 0); height: 2; color: Theme.timer }
                }
                Mono {
                    visible: modelData.bar === undefined
                    y: val.y + val.height + 8; width: parent.width
                    size: 12; color: Theme.w62; text: modelData.sub || ""
                }
            }
        }
    }
    Mover {
        id: sbCover
        order: 25 + sc.rooms.length
        x: 56; y: 716; width: 150; height: 150
        opacity: sc.sV && sc.m ? sc.kSb : 0
        RectangularShadow { anchors.fill: parent; offset.y: 18; blur: 40; spread: -12; radius: 12; color: Qt.rgba(0, 0, 0, 0.6) }
        Art { anchors.fill: parent; radius: 12; source: sc.sArt; rgb: sc.music.rgb || [201, 185, 163]; rgb2: sc.music.rgb2 || [44, 40, 34] }
    }
    readonly property rect coverRect: Qt.rect(sbCover.x, sbCover.y, sbCover.width, sbCover.height)

    // ================================================================= the sheets
    Sheet {
        kind: sc.sheet
        onClose: sc.sheet = ""
    }
}
