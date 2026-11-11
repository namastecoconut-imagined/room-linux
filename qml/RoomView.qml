import QtQuick
import QtQuick.Effects

// One room (the redesign's Room screen, room-motion.html fillRoom): its name and how it's lit up top, its level big
// on the right (all to read — the touch screen doesn't answer between y 118 and 500); below, everything you touch:
// brightness, warmth, colour, the room's scenes, and every lamp (tap to switch, drag to dim). The background takes
// the room's own light (Field, from Scene).
Item {
    id: rv
    width: 1368; height: 912
    property var r: null                          // the room (room.rooms[…])
    readonly property string name: r ? r.name : ""
    readonly property bool on: r ? r.on > 0 : false
    readonly property int level: r && r.on > 0 ? r.level : 0

    readonly property var ks: [["Candle", 2200, "#ffab5e"], ["Warm", 2700, "#ffc98f"], ["Neutral", 4000, "#fff1dc"], ["Daylight", 6500, "#dbe8ff"]]
    readonly property var cs: ["#ff6b4a", "#ffa53a", "#ffd84a", "#ff5fa2", "#a46bff", "#4a8dff", "#3ad6a0"]
    readonly property bool coloured: r && r.rgb && r.rgb.length === 3
    readonly property var kn: {
        var k = r && r.kelvin ? r.kelvin : 2700, best = ks[0]
        for (var i = 1; i < ks.length; i++) if (Math.abs(ks[i][1] - k) < Math.abs(best[1] - k)) best = ks[i]
        return best
    }
    // the room's light: its colour, or its warmth
    readonly property color light: coloured ? Theme.rgb(r.rgb) : kn[2]
    function same(hex, rgb) {
        var c = Qt.color(hex)
        return rgb && Math.abs(c.r * 255 - rgb[0]) < 3 && Math.abs(c.g * 255 - rgb[1]) < 3 && Math.abs(c.b * 255 - rgb[2]) < 3
    }

    // ---------------------------------------------------------------- to read: the name, how it's lit, the level
    Column {
        x: 44; y: 126; spacing: 18
        Serif { text: rv.name; font.pixelSize: 84 }
        Mono {
            color: Theme.w62
            text: !rv.r ? "" : (rv.coloured ? "Colour" : rv.kn[0] + " · " + (rv.r.kelvin || 2700) + "K")
                  + " · " + rv.r.total + (rv.r.total === 1 ? " lamp, " : " lamps, ") + rv.r.on + " on"
        }
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 44; y: 110
        Serif {
            id: big
            property real shown: bar.dragging ? Math.round(bar.local * 100) : rv.level
            Behavior on shown { enabled: !bar.dragging; NumberAnimation { duration: 700; easing.type: Easing.OutQuart } }
            text: Math.round(shown) > 0 ? Math.round(shown) : "Off"
            font.pixelSize: 250
            color: Math.round(shown) > 0 ? "white" : Qt.rgba(1, 1, 1, 0.4)
        }
        Serif { visible: Math.round(big.shown) > 0; text: "%"; font.pixelSize: 90; anchors.baseline: big.baseline
                css: false; transform: Translate { y: big.shift } }
    }

    // ---------------------------------------------------------------- brightness
    Mono { x: 44; y: 524; text: "Brightness · drag"; color: Theme.w62 }
    Item {
        id: bar
        x: 44; y: 552; width: 600; height: 44
        property real local: 0
        readonly property bool dragging: ma.pressed
        readonly property real f: dragging ? local : rv.level / 100
        Rectangle { y: 20; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.15) }
        RectangularShadow {
            y: 20; width: parent.width * bar.f; height: 4; radius: 2
            color: rv.light; blur: 18; visible: width > 1
        }
        Rectangle {
            y: 20; width: parent.width * bar.f; height: 4; radius: 2; color: rv.light
            Behavior on width { enabled: !bar.dragging; NumberAnimation { duration: 250 } }
        }
        Rectangle {
            x: parent.width * bar.f - 12; y: 10; width: 24; height: 24; radius: 12; color: "white"
            scale: bar.dragging ? 1.3 : 1           // grows under your finger while you drag
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        }
        Timer { id: send; interval: 120; onTriggered: rv.setLevel(Math.round(bar.local * 100)) }
        MouseArea {
            id: ma
            anchors.fill: parent; preventStealing: true
            function at(x) { return Math.max(0, Math.min(1, x / width)) }
            onPressed: (e) => { bar.local = at(e.x) }
            onPositionChanged: (e) => { bar.local = at(e.x); if (!send.running) send.start() }
            onReleased: { send.stop(); rv.setLevel(Math.round(bar.local * 100)) }
        }
    }
    function setLevel(v) { if (v <= 0) room.roomOff(rv.name); else room.setRoomLevel(rv.name, v) }

    // ---------------------------------------------------------------- warmth
    Mono { x: 44; y: 620; text: "Warmth"; color: Theme.w62 }
    Row {
        x: 44; y: 650; spacing: 10
        Repeater {
            model: rv.ks
            Press {
                readonly property bool sel: !rv.coloured && rv.kn[1] === modelData[1]
                width: lab.implicitWidth + 32; height: lab.implicitHeight + 24; pressScale: 0.95
                onTapped: room.setRoomKelvin(rv.name, modelData[1])
                Rectangle {
                    anchors.fill: parent; radius: 8
                    color: parent.sel ? modelData[2] : "transparent"
                    border.width: parent.sel ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                }
                Mono { id: lab; anchors.centerIn: parent; text: modelData[0]; color: parent.sel ? "#1a0f08" : Qt.rgba(1, 1, 1, 0.7) }
            }
        }
    }

    // ---------------------------------------------------------------- colour
    Mono { x: 44; y: 722; text: "Colour"; color: Theme.w62 }
    Row {
        x: 44; y: 750; spacing: 14
        Repeater {
            model: rv.cs
            Press {
                width: 44; height: 44; pressScale: 0.94
                readonly property bool sel: rv.coloured && rv.same(modelData, rv.r.rgb)
                onTapped: { var c = Qt.color(modelData); room.setRoomColour(rv.name, Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)) }
                Rectangle { anchors.centerIn: parent; visible: parent.sel; width: 54; height: 54; radius: 27; color: "white" }
                Rectangle { anchors.centerIn: parent; visible: parent.sel; width: 50; height: 50; radius: 25; color: "black" }
                Rectangle { anchors.fill: parent; radius: 22; color: modelData }
            }
        }
    }

    // ---------------------------------------------------------------- the room's scenes
    Row {
        x: 44; y: 832; spacing: 30
        Repeater {
            model: ["Relax", "Read", "Movie", "Night"]
            Press {
                width: sl.implicitWidth; height: sl.implicitHeight + 5; pressScale: 0.94
                onTapped: room.roomScene(rv.name, modelData)
                Mono { id: sl; text: modelData }
                Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.45) }
            }
        }
    }

    // ---------------------------------------------------------------- every lamp
    Item {
        x: 744; y: 524; width: 580; height: 20
        Mono { text: "Lamps"; color: Theme.w62 }
        Mono { anchors.right: parent.right; text: "Tap to switch · drag to dim"; color: Theme.w62 }
    }
    Repeater {
        model: rv.r ? rv.r.lamps : []
        Item {
            id: lamp
            readonly property real gap: Math.min(62, (888 - 560) / Math.max(1, rv.r.lamps.length))
            x: 744; y: 560 + index * gap; width: 580; height: 52
            readonly property int lv: modelData.on ? modelData.level : 0
            opacity: lv > 0 ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 400 } }
            Press {
                width: 200; height: parent.height; pressScale: 0.97
                enabled: modelData.reachable !== false
                onTapped: room.toggleLamp(modelData.id)
                T { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; text: modelData.name; font.pixelSize: 22; color: "white" }
            }
            Item {
                id: ln
                x: 220; width: parent.width - 220 - 64; height: 44; anchors.verticalCenter: parent.verticalCenter
                property real local: 0
                readonly property real f: lma.pressed ? local : lamp.lv / 100
                Rectangle { y: 21; width: parent.width; height: 2; color: Qt.rgba(1, 1, 1, 0.18) }
                RectangularShadow { y: 21; width: parent.width * ln.f; height: 2; color: rv.light; blur: 10; visible: width > 1 }
                Rectangle {
                    y: 21; width: parent.width * ln.f; height: 2; color: rv.light
                    Behavior on width { enabled: !lma.pressed; NumberAnimation { duration: 250 } }
                }
                Timer { id: lsend; interval: 150; onTriggered: room.setLampLevel(modelData.id, Math.round(ln.local * 100)) }
                MouseArea {
                    id: lma
                    anchors.fill: parent; preventStealing: true
                    enabled: modelData.reachable !== false
                    function at(x) { return Math.max(0, Math.min(1, x / width)) }
                    onPressed: (e) => { ln.local = at(e.x) }
                    onPositionChanged: (e) => { ln.local = at(e.x); if (!lsend.running) lsend.start() }
                    onReleased: { lsend.stop(); room.setLampLevel(modelData.id, Math.round(ln.local * 100)) }
                }
            }
            Mono {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 44
                horizontalAlignment: Text.AlignRight
                text: modelData.reachable === false ? "—" : lamp.lv > 0 ? lamp.lv : "Off"
            }
        }
    }
}
