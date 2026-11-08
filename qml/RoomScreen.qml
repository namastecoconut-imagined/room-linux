import QtQuick

// One room: a tall brightness fader (drag up and down; the button at its foot switches the room), warmth from
// candle to daylight, seven colours, each lamp on its own, and four presets for the room.
Item {
    id: rs
    width: Theme.stageW; height: Theme.stageH
    property string name: ""
    signal back()
    readonly property var r: {
        var rs_ = room.rooms
        for (var i = 0; i < rs_.length; i++) if (rs_[i].name === name) return rs_[i]
        return null
    }
    readonly property bool on: r ? r.on > 0 : false
    readonly property var glow: r ? r.glow : [255, 190, 122]

    Glow { x: 300 - 560; y: 480 - 560; width: 1120; height: 1120; strength: rs.on ? 0.12 + 0.16 * (r.level / 100) : 0.03; color: Theme.rgb(rs.glow) }

    Header {
        title: rs.name
        note: r ? r.total + (r.total === 1 ? " lamp" : " lamps") + "  ·  " + (r.on ? r.on + " on" : "off") : ""
        onBack: rs.back()
    }

    // ---------------------------------------------------------------- the fader
    Item {
        id: fader
        x: 96; y: 160; width: 400; height: 660
        property int local: 0
        readonly property int shown: drag.pressed ? local : (rs.on ? r.level : 0)
        Rectangle { anchors.fill: parent; radius: 44; color: Qt.rgba(1, 1, 1, 0.05) }
        // the fill: rounded at the foot like the track, straight across the top
        Item {
            anchors.bottom: parent.bottom; width: parent.width
            height: parent.height * fader.shown / 100
            Behavior on height { enabled: !drag.pressed; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            clip: true
            // taller than what shows, so its rounded top is clipped off and the edge reads straight
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: parent.height + 44
                radius: 44; color: Theme.rgb(rs.glow, 0.42)
            }
        }
        Row {
            x: 36; y: 36
            T { id: big; text: fader.shown > 0 ? fader.shown : "Off"; font.pixelSize: 76; font.weight: Font.Light }
            T { visible: fader.shown > 0; anchors.baseline: big.baseline; text: "%"; font.pixelSize: 34; font.weight: Font.Light }
        }
        T { x: 38; y: 132; text: r ? r.sub : ""; font.pixelSize: 20; color: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.7) }
        Timer { id: throttle; interval: 120; onTriggered: room.setRoomLevel(rs.name, fader.local) }
        MouseArea {
            id: drag
            anchors.fill: parent
            preventStealing: true
            function at(y) { return Math.max(5, Math.min(100, Math.round((1 - y / height) * 100))) }
            onPressed: (e) => { fader.local = at(e.y) }
            onPositionChanged: (e) => { fader.local = at(e.y); if (!throttle.running) throttle.start() }
            onReleased: { throttle.stop(); room.setRoomLevel(rs.name, fader.local) }
        }
        Pill {
            x: 36; anchors.bottom: parent.bottom; anchors.bottomMargin: 36; width: 128; height: 60
            text: rs.on ? "Turn off" : "Turn on"; fontSize: 18
            fill: Qt.rgba(0, 0, 0, 0.28)
            onTapped: room.toggleRoom(rs.name)
        }
    }

    // ---------------------------------------------------------------- warmth
    SectionCap { x: 600; y: 166; text: "Warmth" }
    Item {
        id: warmth
        x: 600; y: 204; width: 696; height: 64
        readonly property real k: r && r.kelvin ? r.kelvin : 2700
        property real f: drag2.pressed ? local : (k - 2200) / 4300
        property real local: 0
        Rectangle {
            anchors.fill: parent; radius: 32
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#d8884a" }
                GradientStop { position: 0.35; color: "#e8c9a0" }
                GradientStop { position: 0.7; color: "#dfe3ea" }
                GradientStop { position: 1; color: "#b9cbea" }
            }
            opacity: rs.on ? 1 : 0.4
        }
        Rectangle {
            x: Math.max(0, Math.min(1, warmth.f)) * (warmth.width - 76); y: -6
            width: 76; height: 76; radius: 38
            color: Qt.hsla(0.08, 0.7 - 0.6 * warmth.f, 0.72 + 0.1 * warmth.f, 1)
            border.color: "white"; border.width: 3
            visible: rs.on
        }
        Timer { id: wThrottle; interval: 150; onTriggered: room.setRoomKelvin(rs.name, Math.round(2200 + warmth.local * 4300)) }
        MouseArea {
            id: drag2
            anchors.fill: parent; anchors.margins: -12
            preventStealing: true
            function at(x) { return Math.max(0, Math.min(1, (x - 12 - 38) / (warmth.width - 76))) }
            onPressed: (e) => { warmth.local = at(e.x) }
            onPositionChanged: (e) => { warmth.local = at(e.x); if (!wThrottle.running) wThrottle.start() }
            onReleased: { wThrottle.stop(); room.setRoomKelvin(rs.name, Math.round(2200 + warmth.local * 4300)) }
        }
    }
    Item {
        x: 600; y: 284; width: 696; height: 20
        T { x: 0; text: "Candle"; font.pixelSize: 16; color: Theme.sub }
        T { x: 696 * 0.3; text: "Warm"; font.pixelSize: 16; color: Theme.sub }
        T { x: 696 * 0.62; text: "Neutral"; font.pixelSize: 16; color: Theme.sub }
        T { anchors.right: parent.right; text: "Daylight"; font.pixelSize: 16; color: Theme.sub }
    }

    // ---------------------------------------------------------------- colour
    SectionCap { x: 600; y: 354; text: "Colour" }
    Row {
        x: 600; y: 392; spacing: (696 - 7 * 76) / 6
        Repeater {
            model: [[232, 100, 74], [232, 152, 42], [233, 200, 74], [224, 74, 142], [138, 90, 224], [58, 144, 224], [58, 191, 142]]
            Press {
                width: 76; height: 76
                onTapped: room.setRoomColour(rs.name, modelData[0], modelData[1], modelData[2])
                Rectangle { anchors.fill: parent; radius: 38; color: Theme.rgb(modelData, 0.88) }
            }
        }
    }

    // ---------------------------------------------------------------- lamps
    SectionCap { x: 600; y: 516; text: "Lamps" }
    Flickable {
        id: lampsF
        x: 600; y: 552; width: 696; height: 132
        contentWidth: lampsRow.width
        interactive: contentWidth > width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Row {
            id: lampsRow
            spacing: 14
            Repeater {
                model: r ? r.lamps : []
                Press {
                    readonly property int n: rs.r ? rs.r.lamps.length : 1
                    width: n <= 3 ? (696 - 14 * (n - 1)) / Math.max(1, n) : 220; height: 132
                    opacity: modelData.reachable ? 1 : 0.4
                    onTapped: room.toggleLamp(modelData.id)
                    Rectangle {
                        anchors.fill: parent; radius: 24
                        color: modelData.on ? Theme.rgb(rs.glow, 0.08) : Qt.rgba(1, 1, 1, 0.035)
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                    }
                    Rectangle {
                        x: 20; y: 20; width: 52; height: 52; radius: 26
                        color: modelData.on ? Theme.rgb(rs.glow, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                        Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: modelData.on ? Theme.rgb(rs.glow) : Qt.rgba(1, 1, 1, 0.22) }
                    }
                    T { anchors.right: parent.right; anchors.rightMargin: 20; y: 24; text: !modelData.reachable ? "Not found" : modelData.on ? modelData.level + "%" : "Off"; font.pixelSize: 16; color: Theme.sub }
                    T { x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; width: parent.width - 40; text: modelData.name; font.pixelSize: 19 }
                }
            }
        }
    }

    // ---------------------------------------------------------------- presets
    Row {
        x: 600; y: 752; spacing: 12
        Repeater {
            model: ["Relax", "Read", "Movie", "Night"]
            Pill { width: (696 - 36) / 4; height: 68; text: modelData; onTapped: room.roomScene(rs.name, modelData) }
        }
    }
}
