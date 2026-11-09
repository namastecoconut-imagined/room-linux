import QtQuick

// Home. Top bar: four shortcuts (Alarms, Weather, Reminders, Scenes); All off · Dim · Night, the mic, settings.
// The middle band (the touch screen doesn't answer there) is for reading: dot clock, one sentence (day, date,
// weather), what's set,
// what's next. Lower part: what's playing with its controls, and every room as a tile (tap to switch it, slide the
// bar for brightness, hold for the room).
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

    // ---------------------------------------------------------------- top bar, left: the shortcuts
    readonly property var dueToday: (things.reminders || []).filter(function (r) { return !r.done && (r.today || r.dueNow) })
    Row {
        x: 72; y: Theme.topY; spacing: 10
        Repeater {
            model: [["Alarms", "alarm", 128], ["Weather", "cloud", 140], ["Reminders", "check", 162], ["Scenes", "scenes", 128]]
            Pill {
                width: modelData[2]; height: 68; text: modelData[0]; icon: modelData[1]; fontSize: 17
                onTapped: index === 0 ? home.openClock() : index === 1 ? home.openWeather() : index === 2 ? home.openReminders() : scenes.open = true
            }
        }
    }

    // ---------------------------------------------------------------- left: date, clock, weather, what's set (to read)
    DotText { id: hClock; x: 72; y: Theme.deadA0 + 34; pitch: 20; text: Theme.clock(new Date(home.now * 1000), room.clock24) }
    Column {
        id: hLine
        x: 72; y: hClock.y + hClock.height + 34; width: 546; spacing: 4
        T { width: parent.width; text: Theme.dayLine(new Date(home.now * 1000)); font.pixelSize: 26; font.weight: Font.Light; color: Theme.ink }
        T { width: parent.width; text: Theme.wxLine(home.wx, room.clock24); font.pixelSize: 26; font.weight: Font.Light; color: Theme.sub }
    }
    T {
        x: 72; y: hLine.y + hLine.height + 26; width: 546; elide: Text.ElideRight; font.pixelSize: 20; color: Theme.sub
        visible: text !== ""
        text: [(home.things.timers || []).length ? "Timer " + Theme.countdown(home.things.timers[0].left) : "",
               (home.things.nextAlarm && home.things.nextAlarm.h !== undefined ? "Alarm " + Theme.hm(home.things.nextAlarm.h, home.things.nextAlarm.m, room.clock24) + (room.clock24 ? "" : " " + Theme.ampm(home.things.nextAlarm.h, false)) : ""),
               (home.dueToday.length ? home.dueToday.length + " reminder" + (home.dueToday.length > 1 ? "s" : "") + " today" : "")]
              .filter(function (s) { return s }).join("   ·   ")
    }

    // ---------------------------------------------------------------- left: what's playing — big, with its controls
    Press {
        id: musicCard
        // paused a while (or nothing at all): the card goes back to its shortcuts
        readonly property bool live: music.exists && !music.idle
        x: 72; y: Theme.deadB1 + 14; width: 546; height: 866 - y
        pressScale: 0.99
        onTapped: home.openMusic()
        Rectangle { anchors.fill: parent; radius: 28; color: Qt.rgba(1, 1, 1, 0.04); border.color: Qt.rgba(1, 1, 1, 0.06) }
        Cover {
            x: 26; y: 26; width: 150; height: 150; radius: 14
            visible: musicCard.live
            source: music.art || ""; rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34]
        }
        Rectangle { visible: !musicCard.live; x: 26; y: 26; width: 90; height: 90; radius: 12; color: Qt.rgba(1, 1, 1, 0.05); Icon { anchors.centerIn: parent; name: "lib"; size: 26; color: Theme.sub } }
        Column {
            x: musicCard.live ? 202 : 136; y: musicCard.live ? 50 : 30; width: parent.width - x - 26; spacing: 8
            T { width: parent.width; text: musicCard.live ? (music.title || "") : "Nothing playing"; font.pixelSize: 30; elide: Text.ElideRight }
            T { width: parent.width; text: musicCard.live ? [music.artist, music.device].filter(function (s) { return s }).join("  ·  ") : "Tap for your playlists, or AirPlay to Room"; font.pixelSize: 19; color: Theme.sub; elide: Text.ElideRight }
        }
        // nothing playing: Liked Songs, and what you last played — one tap each
        Column {
            visible: !musicCard.live && music.enabled !== false
            x: 26; width: parent.width - 52
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            spacing: 12
            Repeater {
                model: {
                    var rows = [{ key: "liked", name: "Liked Songs", sub: "Shuffle", art: "" }]
                    var l = music.last || {}
                    if (l.uri) rows.push({ key: "last", name: l.name || "", art: l.art || "",
                                           sub: "Last played" + (l.kind && l.kind !== "song" ? " · " + l.kind : "") })
                    return rows
                }
                Press {
                    width: parent.width; height: 72
                    pressScale: 0.98
                    onTapped: modelData.key === "liked" ? room.playLiked() : room.playLast()
                    Rectangle { anchors.fill: parent; radius: 18; color: Qt.rgba(1, 1, 1, 0.06) }
                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; width: 50; height: 50; radius: 9
                        visible: modelData.key === "liked"
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#5b3fd8" }
                            GradientStop { position: 1; color: "#8fb7ff" }
                        }
                        Icon { anchors.centerIn: parent; name: "heartOn"; size: 22; color: "white" }
                    }
                    Cover {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; width: 50; height: 50; radius: 9
                        visible: modelData.key !== "liked"
                        source: modelData.art; rgb: [70, 60, 80]; rgb2: [30, 26, 34]
                    }
                    Column {
                        x: 78; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 78 - 76; spacing: 3
                        T { width: parent.width; text: modelData.name; font.pixelSize: 19; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        T { width: parent.width; text: modelData.sub; font.pixelSize: 15; color: Theme.sub; elide: Text.ElideRight }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 13; anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 46; radius: 23; color: Theme.ink
                        Icon { anchors.centerIn: parent; name: "play"; size: 16; color: "#111" }
                    }
                }
            }
        }
        Item {
            visible: musicCard.live && (music.duration || 0) > 0
            x: 26; y: 202; width: parent.width - 52; height: 4
            readonly property real pos: Math.min(music.duration || 0, (music.position || 0) + (music.playing ? home.now - music.at : 0))
            Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.13) }
            Rectangle { height: 4; radius: 2; width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); color: Theme.ink }
        }
        Row {
            visible: musicCard.live
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            spacing: 70
            RoundBtn { size: 96; icon: "prev"; iconSize: 26; anchors.verticalCenter: parent.verticalCenter; onTapped: room.previous() }
            RoundBtn { size: 112; icon: music.playing ? "pause" : "play"; iconSize: 32; fill: Theme.ink; ink: "#111"; onTapped: room.playPause() }
            RoundBtn { size: 96; icon: "next"; iconSize: 26; anchors.verticalCenter: parent.verticalCenter; onTapped: room.next() }
        }
    }

    // ---------------------------------------------------------------- top bar, right: All off · Dim · Night · mic · settings
    Rectangle { x: 690; y: 40; width: 1; height: 832; color: Qt.rgba(1, 1, 1, 0.06) }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 72; y: Theme.topY; spacing: 10
        Repeater {
            model: [["All off", "power", 124], ["Dim", "dim", 104], ["Night", "moon", 118]]
            Pill {
                width: modelData[2]; height: 68; text: modelData[0]; icon: modelData[1]; fontSize: 17
                onTapped: index === 0 ? room.allOff() : index === 1 ? room.dimAll() : room.night()
            }
        }
        RoundBtn { size: 68; icon: "mic"; iconSize: 26; onTapped: home.openAssistant() }
        RoundBtn { size: 68; icon: "settings"; iconSize: 24; onTapped: home.openSettings() }
    }

    // ---------------------------------------------------------------- right: what's next (to read)
    Column {
        x: 744; y: Theme.deadA0 + 36; width: 552
        spacing: 10
        readonly property var ev: room.events
        SectionCap { text: parent.ev.length ? "Next  ·  " + parent.ev[0].when : "Next" }
        T { width: parent.width; text: parent.ev.length ? parent.ev[0].title : "Nothing coming up"; font.pixelSize: 44; elide: Text.ElideRight; color: parent.ev.length ? Theme.ink : Theme.sub }
        T {
            width: parent.width; visible: text !== ""; elide: Text.ElideRight
            text: parent.ev.length > 1 ? "then " + parent.ev[1].title + "  ·  " + parent.ev[1].when : ""
            font.pixelSize: 22; color: Theme.sub
        }
    }

    // ---------------------------------------------------------------- right: the rooms, as tiles in the lower part
    SectionCap { x: 744; y: Theme.capY; text: "Lights" }
    T {
        anchors.right: parent.right; anchors.rightMargin: 72; y: Theme.capY - 4
        text: rooms.length ? lit.length + " of " + rooms.length + " rooms on" : ""
        font.pixelSize: 18; color: Theme.sub
    }
    GridView {
        id: grid
        x: 744; y: Theme.deadB1 + 8; width: 552 + 16; height: 880 - y + 16
        cellWidth: 284; cellHeight: 196
        clip: true
        interactive: rooms.length > 4
        boundsBehavior: Flickable.StopAtBounds
        model: rooms
        delegate: Press {
            width: 268; height: 180
            pressScale: 0.985
            onTapped: if (modelData.reachable) room.toggleRoom(modelData.name)
            onHeld: home.openRoom(modelData.name)
            opacity: modelData.reachable ? 1 : 0.45
            Rectangle {
                anchors.fill: parent; radius: 24
                color: modelData.on ? Qt.rgba(modelData.glow[0] / 255, modelData.glow[1] / 255, modelData.glow[2] / 255, 0.08) : Qt.rgba(1, 1, 1, 0.035)
                border.color: Qt.rgba(1, 1, 1, 0.06)
            }
            Rectangle {
                x: parent.width - 34; y: 26; width: 12; height: 12; radius: 6
                color: modelData.on ? Theme.rgb(modelData.glow) : Qt.rgba(1, 1, 1, 0.2)
                Glow { anchors.centerIn: parent; width: 40; height: 40; visible: modelData.on > 0; color: Theme.rgb(modelData.glow); strength: 0.6 }
            }
            T { x: 22; y: 18; width: parent.width - 64; text: modelData.name; font.pixelSize: 25; elide: Text.ElideRight }
            T { x: 22; y: 56; width: parent.width - 44; text: modelData.sub; font.pixelSize: 17; color: Theme.sub; elide: Text.ElideRight }
            LevelSlider {
                x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                width: parent.width - 36; height: 56
                value: modelData.on ? modelData.level : 0
                tint: Theme.rgb(modelData.glow)
                enabled: modelData.reachable > 0
                onMoved: (v) => room.setRoomLevel(modelData.name, v)
            }
        }
    }
    T {
        visible: rooms.length === 0
        x: 744; y: Theme.deadB1 + 24; width: 552; wrapMode: Text.WordWrap
        text: "No lights yet — add your rooms to config.json"; font.pixelSize: 21; color: Theme.sub
    }
    T {
        visible: rooms.length > 0
        x: 744; y: grid.y + Math.min(2, Math.ceil(rooms.length / 2)) * 196 + 2      // right under the last tile
        text: "Tap a room to switch it  ·  hold for more"; font.pixelSize: 15; color: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.3)
    }

    // ---------------------------------------------------------------- the scenes sheet (low on the screen, where touch works)
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
            x: (parent.width - width) / 2; y: Theme.deadB1 + 6; width: 760; height: 896 - y; radius: 32
            color: "#141312"; border.color: Qt.rgba(1, 1, 1, 0.07)
            MouseArea { anchors.fill: parent }
            SectionCap { x: 40; y: 34; text: "Scenes · the whole house" }
            RoundBtn { anchors.right: parent.right; anchors.rightMargin: 24; y: 16; size: 56; icon: "close"; iconSize: 20; onTapped: scenes.open = false }
            Grid {
                x: 40; y: 88; columns: 2; spacing: 16
                Repeater {
                    model: [["Evening", "Every room warm at half"], ["Movie", "This room very low, the rest off"], ["Night", "A candle glow here, the rest off"], ["All off", "Every light in the house"]]
                    Press {
                        width: 332; height: 140
                        onTapped: { room.houseScene(modelData[0]); scenes.open = false }
                        Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, 0.05) }
                        T { x: 24; y: 34; text: modelData[0]; font.pixelSize: 26 }
                        T { x: 24; y: 76; width: 290; text: modelData[1]; font.pixelSize: 17; color: Theme.sub }
                    }
                }
            }
        }
    }
}
