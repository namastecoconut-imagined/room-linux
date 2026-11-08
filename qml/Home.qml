import QtQuick

// Home — the glass three-column screen: time, weather and today on the left; every room's lights in the middle;
// what's playing and the mic on the right. Laid out on the 1368 × 912 stage (the Surface at 200%).
Item {
    id: home
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var wx: room.weather
    property var rooms: room.rooms
    property var music: room.music
    readonly property var hereRoom: {
        for (var i = 0; i < rooms.length; i++) if (rooms[i].here) return rooms[i]
        return rooms.length ? rooms[0] : null
    }
    signal openMusic()

    // ---------------------------------------------------------------- ambient light
    Glow { x: 1150 - 420; y: 170 - 420; width: 840; height: 840; strength: music.exists ? 0.30 : 0; color: Theme.rgb(music.rgb || [160, 138, 108]) }
    Glow { x: 560 - 340; y: 200 - 340; width: 680; height: 680; strength: hereRoom && hereRoom.on ? 0.10 : 0.03; color: Theme.rgb(hereRoom ? hereRoom.glow : [255, 190, 122]) }

    // ---------------------------------------------------------------- left: time, weather, today
    T { x: 56; y: 46; text: Theme.dateLine(new Date(home.now * 1000)); color: Theme.mut }
    DotText { x: 56; y: 100; pitch: 15; text: Theme.clock(new Date(home.now * 1000), room.clock24) }

    Glass {
        x: 40; y: 300; width: 420; height: 250
        T { x: 28; y: 18; text: wx.ok ? wx.t + "°" : "—"; font.pixelSize: 56; font.weight: Font.Light }
        Column {
            x: 150; y: 30; spacing: 4
            T { text: wx.d || ""; font.pixelSize: 21 }
            T {
                font.pixelSize: 18; color: Theme.mut
                text: (wx.hi !== undefined && wx.hi !== null ? "↑" + wx.hi + "° ↓" + wx.lo + "°" : "") + (wx.aqi ? "  ·  AQI " + wx.aqi : "")
            }
        }
        Row {
            x: 28; y: 120; spacing: (420 - 56 - 6 * 46) / 5
            Repeater {
                model: wx.hours ? wx.hours.slice(0, 6) : []
                Column {
                    width: 46; spacing: 8
                    readonly property var hs: wx.hours.slice(0, 6)
                    readonly property real lo: Math.min.apply(null, hs.map(function (h) { return h.t })) - 2
                    readonly property real hi: Math.max.apply(null, hs.map(function (h) { return h.t }))
                    T { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.hour(modelData.h, room.clock24); font.pixelSize: 16; color: Theme.mut }
                    Item {
                        width: 46; height: 46
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4; height: 46; radius: 2; color: Qt.rgba(1, 1, 1, 0.08) }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
                            width: 4; radius: 2
                            height: 8 + 38 * (modelData.t - lo) / Math.max(1, hi - lo)
                            color: index === 0 ? Theme.tx : Qt.rgba(0.96, 0.95, 0.94, 0.5)
                        }
                        // a drop of blue when rain is likely
                        Rectangle { visible: modelData.p >= 40; anchors.horizontalCenter: parent.horizontalCenter; y: -2; width: 6; height: 6; radius: 3; color: "#7fb4ff" }
                    }
                    T { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t + "°"; font.pixelSize: 19 }
                }
            }
        }
        Press { anchors.fill: parent; pressScale: 0.99 }
    }

    Glass {
        x: 40; y: 570; width: 420; height: 302
        Cap { x: 28; y: 28; text: "Today" }
        Column {
            x: 28; y: 62; width: 364
            Repeater {
                model: room.events
                Item {
                    width: 364; height: 66
                    T { y: 18; width: 92; text: modelData.when; font.pixelSize: 21; color: modelData.today ? Theme.tx : Theme.mut }
                    T { x: 100; y: 18; width: 264; text: modelData.title + (modelData.extra ? "  ·  " + modelData.extra : ""); font.pixelSize: 21; color: Theme.mut }
                    Rectangle { visible: index < room.events.length - 1; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hair }
                }
            }
            T { visible: room.events.length === 0; y: 18; text: "Nothing on the calendar"; color: Theme.dim; font.pixelSize: 21 }
        }
    }

    // ---------------------------------------------------------------- middle: lights
    Glass {
        id: lights
        x: 484; y: 40; width: 460; height: 832
        readonly property int onCount: rooms.reduce(function (a, r) { return a + r.on }, 0)
        readonly property int total: rooms.reduce(function (a, r) { return a + r.total }, 0)
        Cap { x: 26; y: 28; text: "Lights" }
        T { anchors.right: parent.right; anchors.rightMargin: 26; y: 24; text: lights.onCount + " of " + lights.total + " on"; font.pixelSize: 19; color: Theme.mut }

        ListView {
            id: list
            x: 0; y: 62; width: parent.width
            height: Math.min(4, rooms.length) * 96
            clip: true
            interactive: rooms.length > 4
            boundsBehavior: Flickable.StopAtBounds
            model: rooms
            delegate: Item {
                width: list.width; height: 96
                Rectangle { visible: index > 0; width: parent.width; height: 1; color: Theme.hair }
                RoundBtn {
                    x: 26; anchors.verticalCenter: parent.verticalCenter
                    size: 58; icon: "bulb"; iconSize: 26
                    fill: modelData.on ? Qt.rgba(modelData.glow[0] / 255, modelData.glow[1] / 255, modelData.glow[2] / 255, 0.22) : Qt.rgba(1, 1, 1, 0.07)
                    opacity: modelData.reachable ? 1 : 0.35
                    onTapped: room.toggleRoom(modelData.name)
                }
                Column {
                    x: 104; anchors.verticalCenter: parent.verticalCenter; width: 180; spacing: 4
                    T { width: 180; text: modelData.name; font.pixelSize: 22; font.weight: Font.Medium }
                    Row {
                        spacing: 6
                        Rectangle { visible: modelData.here; width: 10; height: 10; radius: 5; color: Theme.warm; anchors.verticalCenter: parent.verticalCenter }
                        T { text: modelData.sub; font.pixelSize: 18; color: Theme.mut; width: modelData.here ? 164 : 180 }
                    }
                }
                LevelSlider {
                    x: 296; width: parent.width - 296 - 26; anchors.verticalCenter: parent.verticalCenter
                    value: modelData.on ? modelData.level : 0
                    tint: Theme.rgb(modelData.glow)
                    opacity: modelData.reachable ? 1 : 0.35
                    enabled: modelData.reachable > 0
                    onMoved: (v) => room.setRoomLevel(modelData.name, v)
                }
            }
        }

        // warmth and colour for the room the panel is in
        Item {
            id: tone
            visible: hereRoom !== null
            x: 26; y: 62 + list.height + 24; width: parent.width - 52; height: 200
            Cap { text: "Warmth · " + (hereRoom ? hereRoom.name : "") }
            Item {
                id: wTrack
                y: 34; width: parent.width; height: 58
                readonly property real f: hereRoom ? (Math.max(2200, Math.min(6500, hereRoom.kelvin)) - 2200) / 4300 : 0.12
                property real dragF: f
                Rectangle {
                    anchors.fill: parent; radius: 29; opacity: 0.85
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ff9e4a" }
                        GradientStop { position: 0.45; color: "#ffd9a8" }
                        GradientStop { position: 1; color: "#dfe9ff" }
                    }
                }
                Rectangle {
                    width: 68; height: 68; radius: 34; y: -5
                    x: (wma.pressed ? wTrack.dragF : wTrack.f) * (wTrack.width - 58) + 29 - 34
                    color: Qt.rgba(1, 0.75, 0.48, 1); border.color: "white"; border.width: 3
                    Behavior on x { enabled: !wma.pressed; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                Timer { id: wThrottle; interval: 150; onTriggered: room.setRoomKelvin(hereRoom.name, Math.round(2200 + wTrack.dragF * 4300)) }
                MouseArea {
                    id: wma
                    anchors.fill: parent; anchors.margins: -10; preventStealing: true
                    function at(x) { return Math.max(0, Math.min(1, (x - 39) / (wTrack.width - 58))) }
                    onPressed: (e) => { wTrack.dragF = at(e.x) }
                    onPositionChanged: (e) => { wTrack.dragF = at(e.x); if (!wThrottle.running) wThrottle.start() }
                    onReleased: { wThrottle.stop(); room.setRoomKelvin(hereRoom.name, Math.round(2200 + wTrack.dragF * 4300)) }
                }
            }
            Row {
                y: 112; spacing: (tone.width - 6 * 56) / 5
                Repeater {
                    model: [[255, 110, 80], [255, 165, 50], [255, 70, 160], [140, 100, 255], [60, 160, 255], [60, 210, 150]]
                    Press {
                        width: 56; height: 56
                        Rectangle { anchors.fill: parent; radius: 28; color: Theme.rgb(modelData, 0.9) }
                        onTapped: room.setRoomColour(hereRoom.name, modelData[0], modelData[1], modelData[2])
                    }
                }
            }
        }

        Row {
            x: 26; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; spacing: 12
            Repeater {
                model: [["All off", "power"], ["Dim", "dim"], ["Night", "moon"]]
                Press {
                    width: (460 - 52 - 24) / 3; height: 64
                    Rectangle { anchors.fill: parent; radius: 32; color: Qt.rgba(1, 1, 1, 0.07) }
                    Row {
                        anchors.centerIn: parent; spacing: 10
                        Icon { name: modelData[1]; size: 22; anchors.verticalCenter: parent.verticalCenter }
                        T { text: modelData[0]; font.pixelSize: 20 }
                    }
                    onTapped: index === 0 ? room.allOff() : index === 1 ? room.dimAll() : room.night()
                }
            }
        }
    }

    // ---------------------------------------------------------------- right: music + mic
    Glass {
        x: 968; y: 40; width: 360; height: 686
        Cap { x: 28; y: 28; text: music.exists ? "Now playing" : "Music" }
        Press {
            x: 28; y: 66; width: 304; height: 304; pressScale: 0.98
            Cover { anchors.fill: parent; source: music.art || ""; rgb: music.rgb || [60, 56, 52]; rgb2: music.rgb2 || [20, 18, 16]; opacity: music.exists ? 1 : 0.25 }
            onTapped: home.openMusic()
        }
        Column {
            x: 28; y: 394; width: 304; spacing: 4
            T { width: 304; text: music.exists ? music.title : (music.enabled ? "Nothing playing" : "Spotify isn't set up"); font.pixelSize: 30; font.weight: Font.Medium }
            T { width: 304; text: music.exists ? music.artist : (music.error || "AirPlay to Room, or play from Spotify"); font.pixelSize: 21; color: Theme.mut }
        }
        Item {
            x: 28; y: 486; width: 304; height: 30
            readonly property real pos: music.exists ? Math.min(music.duration, music.position + (music.playing ? home.now - music.at : 0)) : 0
            Rectangle { width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.14) }
            Rectangle { width: parent.width * (music.duration > 0 ? parent.pos / music.duration : 0); height: 4; radius: 2; color: Theme.tx }
            T { y: 12; text: Theme.mmss(parent.pos); font.pixelSize: 15; color: Theme.dim }
            T { y: 12; anchors.right: parent.right; text: Theme.mmss(music.duration || 0); font.pixelSize: 15; color: Theme.dim }
        }
        Item {
            x: 28; y: 536; width: 304; height: 88
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 64; icon: "prev"; iconSize: 22; onTapped: room.previous() }
            RoundBtn {
                anchors.centerIn: parent; size: 88; iconSize: 28
                icon: music.playing ? "pause" : "play"; fill: Theme.tx; ink: "black"
                onTapped: room.playPause()
            }
            RoundBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 64; icon: "next"; iconSize: 22; onTapped: room.next() }
        }
        Row {
            x: 28; anchors.bottom: parent.bottom; anchors.bottomMargin: 24; spacing: 10
            Icon { name: "speaker"; size: 20; color: Theme.mut; anchors.verticalCenter: parent.verticalCenter }
            T { text: music.device || "No speaker"; font.pixelSize: 18; color: Theme.mut; width: 270 }
        }
    }

    Glass {
        x: 968; y: 746; width: 360; height: 126
        Press {
            anchors.fill: parent; pressScale: 0.98
            onTapped: room.listen()
            Rectangle { x: 28; y: 16; width: 94; height: 94; radius: 47; color: Qt.rgba(1, 1, 1, 0.1) }
            Icon { x: 28 + 47 - 17; y: 16 + 47 - 17; name: "mic"; size: 34 }
            Column {
                x: 144; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                T { text: "Say “Alexa”"; font.pixelSize: 22 }
                T { text: "or tap to talk"; font.pixelSize: 17; color: Theme.mut }
            }
        }
    }
}
