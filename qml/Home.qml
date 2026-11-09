import QtQuick

// Home — "calm two-column" (H2). Left: the date and dot clock, the weather, what's next, four shortcuts (Alarms,
// Weather, Reminders, Scenes) and what's playing. Right: every room's lights as big rows (tap a row for the room,
// the bulb to switch it, drag the pill for brightness), then All off · Dim · Night and the mic.
// Laid out on the 1368 × 912 stage (the Surface at 200%).
Item {
    id: home
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var wx: room.weather
    property var rooms: room.rooms
    property var music: room.music
    property var things: room.things
    readonly property var lit: rooms.filter(function (r) { return r.on > 0 })
    readonly property int rainAt: Theme.rainAt(wx.hours)
    signal openMusic()
    signal openSettings()
    signal openRoom(string name)
    signal openClock()
    signal openWeather()
    signal openReminders()
    signal openAssistant()

    // ---------------------------------------------------------------- the music's colour, low in the left corner
    Glow { x: 300 - 520; y: 820 - 520; width: 1040; height: 1040; strength: music.exists ? 0.22 : 0; color: Theme.rgb(Theme.lit(music.rgb || [160, 138, 108])) }
    Glow { x: 1020 - 500; y: 300 - 500; width: 1000; height: 1000; strength: lit.length ? 0.07 : 0; color: Theme.warm }

    // ---------------------------------------------------------------- left: date, clock
    T { x: 72; y: 60; text: Qt.formatDate(new Date(home.now * 1000), "dddd d MMMM"); font.pixelSize: 24; color: Theme.sub }
    Press {
        x: 72; y: 112; width: clockDots.width; height: clockDots.height
        pressScale: 0.98
        onTapped: home.openClock()
        DotText { id: clockDots; pitch: 20; text: Theme.clock(new Date(home.now * 1000), room.clock24) }
    }

    // ---------------------------------------------------------------- left: weather, next
    Press {
        id: wxBlock
        x: 72; y: 296; width: 560; height: 92
        pressScale: 0.98
        onTapped: home.openWeather()
        Row {
            id: wxRow
            spacing: 16
            T { id: tNow; text: wx.ok === true ? wx.t + "°" : "—"; font.pixelSize: 46; font.weight: Font.Light }
            T {
                anchors.baseline: tNow.baseline
                text: wx.ok === true ? Theme.cap(wx.d || "") + (home.rainAt >= 0 ? "  ·  rain ~" + Theme.hourText(wx.hours[home.rainAt].h, room.clock24) : "") : "Getting the weather…"
                font.pixelSize: 24; color: Theme.sub
            }
        }
        T {
            y: 62
            visible: wx.ok === true
            text: [(wx.hi !== null && wx.hi !== undefined ? wx.hi + "° / " + wx.lo + "°" : ""), (wx.aqi ? "air " + wx.aqi : "")].filter(function (s) { return s }).join("  ·  ")
            font.pixelSize: 20; color: Theme.sub
        }
    }
    Rectangle { x: 72; y: 412; width: 546; height: 1; color: Theme.rule }
    Column {
        x: 72; y: 444; width: 546
        spacing: 8
        readonly property var ev: room.events
        SectionCap { text: parent.ev.length ? "Next  ·  " + parent.ev[0].when : "Next" }
        T { width: parent.width; text: parent.ev.length ? parent.ev[0].title : "Nothing coming up"; font.pixelSize: 30; color: parent.ev.length ? Theme.ink : Theme.sub }
        T {
            width: parent.width; visible: text !== ""
            text: parent.ev.length > 1 ? "then " + parent.ev[1].title + "  ·  " + parent.ev[1].when : ""
            font.pixelSize: 20; color: Theme.sub
        }
    }

    // ---------------------------------------------------------------- left: shortcuts
    readonly property var dueToday: (things.reminders || []).filter(function (r) { return !r.done && (r.today || r.dueNow) })
    Row {
        x: 72; y: 588; spacing: 14
        Repeater {
            model: [
                { icon: "alarm", label: "Alarms", note: (home.things.timers || []).length ? Theme.countdown(home.things.timers[0].left) : (home.things.nextAlarm && home.things.nextAlarm.h !== undefined ? Theme.hm(home.things.nextAlarm.h, home.things.nextAlarm.m, room.clock24) : "") },
                { icon: "cloud", label: "Weather", note: home.wx.ok === true ? home.wx.t + "°" : "" },
                { icon: "check", label: "Reminders", note: home.dueToday.length ? "" + home.dueToday.length : "" },
                { icon: "scenes", label: "Scenes", note: "" }
            ]
            Press {
                width: 126; height: 108
                pressScale: 0.96
                onTapped: index === 0 ? home.openClock() : index === 1 ? home.openWeather() : index === 2 ? home.openReminders() : scenes.open = true
                Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(1, 1, 1, 0.035); border.color: Qt.rgba(1, 1, 1, 0.06) }
                Icon { x: 20; y: 18; name: modelData.icon; size: 26; color: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.8) }
                T { anchors.right: parent.right; anchors.rightMargin: 18; y: 20; text: modelData.note; font.pixelSize: 16; color: index === 2 ? Theme.warm : Theme.sub }
                T { x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 18; text: modelData.label; font.pixelSize: 18 }
            }
        }
    }

    // ---------------------------------------------------------------- left: what's playing
    Press {
        x: 72; y: 728; width: 546; height: 136
        pressScale: 0.98
        onTapped: home.openMusic()
        Rectangle { anchors.fill: parent; radius: 26; color: Qt.rgba(1, 1, 1, 0.04); border.color: Qt.rgba(1, 1, 1, 0.06) }
        Cover {
            x: 18; y: 18; width: 100; height: 100; radius: 12
            visible: music.exists
            source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34]
        }
        Rectangle { visible: !music.exists; x: 18; y: 18; width: 100; height: 100; radius: 12; color: Qt.rgba(1, 1, 1, 0.05); Icon { anchors.centerIn: parent; name: "lib"; size: 30; color: Theme.sub } }
        Column {
            x: 138; y: music.exists ? 26 : 38; width: 260; spacing: 4
            T { width: parent.width; text: music.exists ? (music.title || "") : "Nothing playing"; font.pixelSize: 24 }
            T { width: parent.width; text: music.exists ? [music.artist, music.device].filter(function (s) { return s }).join("  ·  ") : "Tap for your playlists"; font.pixelSize: 17; color: Theme.sub }
        }
        Item {
            visible: music.exists && (music.duration || 0) > 0
            x: 138; y: 100; width: 250; height: 3
            readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? home.now - music.at : 0))
            Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.15) }
            Rectangle { height: 3; radius: 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Theme.ink }
        }
        RoundBtn {
            visible: music.exists
            anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
            size: 68; icon: music.playing ? "pause" : "play"; iconSize: 22
            fill: Theme.ink; ink: "#111"
            onTapped: room.playPause()
        }
    }

    // ---------------------------------------------------------------- right: lights
    Rectangle { x: 690; y: 40; width: 1; height: 832; color: Qt.rgba(1, 1, 1, 0.06) }
    SectionCap { x: 744; y: 68; text: "Lights" }
    RoundBtn { x: 1296 - 56; y: 50; size: 56; icon: "settings"; iconSize: 22; onTapped: home.openSettings() }
    T {
        anchors.right: parent.right; anchors.rightMargin: 72 + 56 + 20; y: 64
        text: rooms.length ? lit.length + " of " + rooms.length + " rooms on" : ""
        font.pixelSize: 18; color: Theme.sub
    }
    ListView {
        id: list
        x: 744; y: 104; width: 552
        height: Math.min(4, Math.max(1, rooms.length)) * 128 - 16
        spacing: 16
        clip: true
        interactive: rooms.length > 4
        boundsBehavior: Flickable.StopAtBounds
        model: rooms
        delegate: Press {
            width: list.width; height: 112
            pressScale: 0.985
            onTapped: home.openRoom(modelData.name)
            Rectangle {
                anchors.fill: parent; radius: 24
                color: modelData.on ? Qt.rgba(modelData.glow[0] / 255, modelData.glow[1] / 255, modelData.glow[2] / 255, 0.07) : Qt.rgba(1, 1, 1, 0.035)
                border.color: Qt.rgba(1, 1, 1, 0.06)
            }
            Press {
                x: 22; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56
                opacity: modelData.reachable ? 1 : 0.35
                onTapped: room.toggleRoom(modelData.name)
                Rectangle {
                    anchors.fill: parent; radius: 28
                    color: modelData.on ? Qt.rgba(modelData.glow[0] / 255, modelData.glow[1] / 255, modelData.glow[2] / 255, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                }
                Rectangle {
                    anchors.centerIn: parent; width: 14; height: 14; radius: 7
                    color: modelData.on ? Theme.rgb(modelData.glow) : Qt.rgba(1, 1, 1, 0.22)
                }
                Glow { anchors.centerIn: parent; width: 44; height: 44; visible: modelData.on > 0; color: Theme.rgb(modelData.glow); strength: 0.6 }
            }
            Column {
                x: 98; anchors.verticalCenter: parent.verticalCenter; width: 250; spacing: 4
                T { width: parent.width; text: modelData.name; font.pixelSize: 24 }
                T { width: parent.width; text: modelData.sub; font.pixelSize: 17; color: Theme.sub }
            }
            LevelSlider {
                anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter
                width: 160; height: 56
                value: modelData.on ? modelData.level : 0
                tint: Theme.rgb(modelData.glow)
                opacity: modelData.reachable ? 1 : 0.35
                enabled: modelData.reachable > 0
                onMoved: (v) => room.setRoomLevel(modelData.name, v)
            }
        }
    }
    T {
        visible: rooms.length === 0
        x: 744; y: 120; width: 552; wrapMode: Text.WordWrap
        text: "No lights yet — add your rooms to config.json"; font.pixelSize: 21; color: Theme.sub
    }
    Row {
        x: 744; y: list.y + list.height + 32; spacing: 12
        Repeater {
            model: [["All off", "power"], ["Dim", "dim"], ["Night", "moon"]]
            Pill {
                width: 150; height: 68; text: modelData[0]; icon: modelData[1]
                onTapped: index === 0 ? room.allOff() : index === 1 ? room.dimAll() : room.night()
            }
        }
        RoundBtn { size: 68; icon: "mic"; iconSize: 26; onTapped: home.openAssistant() }
    }

    // ---------------------------------------------------------------- the scenes sheet (from the Scenes shortcut)
    Item {
        id: scenes
        property bool open: false
        anchors.fill: parent
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        MouseArea { anchors.fill: parent; onClicked: scenes.open = false }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
        Rectangle {
            anchors.centerIn: parent; width: 760; height: 380; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            SectionCap { x: 40; y: 40; text: "Scenes · the whole house" }
            RoundBtn { anchors.right: parent.right; anchors.rightMargin: 28; y: 24; size: 56; icon: "close"; iconSize: 20; onTapped: scenes.open = false }
            Grid {
                x: 40; y: 104; columns: 2; spacing: 16
                Repeater {
                    model: [["Evening", "Every room warm at half"], ["Movie", "This room very low, the rest off"], ["Night", "A candle glow here, the rest off"], ["All off", "Every light in the house"]]
                    Press {
                        width: 332; height: 112
                        onTapped: { room.houseScene(modelData[0]); scenes.open = false }
                        Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, 0.05) }
                        T { x: 24; y: 26; text: modelData[0]; font.pixelSize: 24 }
                        T { x: 24; y: 62; width: 290; text: modelData[1]; font.pixelSize: 16; color: Theme.sub }
                    }
                }
            }
        }
    }
}
