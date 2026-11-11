import QtQuick

// The redesign's sheets: they rise from the bottom (to y 540, where the screen answers touch) over the screen dimmed
// 55 %. Scenes for the whole house, where the music plays (Spotify Connect speakers, and the Bluetooth speaker on
// this panel), and your playlists and albums. Tap outside, or Close.
Item {
    id: sh
    width: 1368; height: 912
    property string kind: ""                   // "" (closed) · scenes · speakers · library
    signal close()
    readonly property bool open: kind !== ""
    property string shown: ""                  // what's in it (kept while it slides away)
    onKindChanged: if (kind !== "") shown = kind
    readonly property var music: room.music
    visible: scrim.opacity > 0.001
    component Ease: NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }

    Rectangle {
        id: scrim
        anchors.fill: parent; anchors.margins: -40
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: sh.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        MouseArea { anchors.fill: parent; enabled: sh.open; onClicked: sh.close() }
    }
    Rectangle {
        id: pane
        x: 44; y: sh.open ? 540 : 960; width: 1280; height: 340; radius: 26
        Behavior on y { Ease {} }
        opacity: sh.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        color: Qt.rgba(18 / 255, 14 / 255, 12 / 255, 0.78)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
        clip: true
        MouseArea { anchors.fill: parent }          // taps on the sheet don't close it
        Rectangle { x: 18; width: parent.width - 36; y: 1; height: 1; color: Qt.rgba(1, 1, 1, 0.3) }

        Mono {
            x: 36; y: 30; color: Theme.w62
            text: sh.shown === "scenes" ? "Scenes · the whole house" : sh.shown === "speakers" ? "Play on" : "Playlists and albums"
        }
        Press {
            anchors.right: parent.right; anchors.rightMargin: 14; y: 14; width: cl.implicitWidth + 32; height: 46; pressScale: 0.94
            onTapped: sh.close()
            Mono { id: cl; anchors.centerIn: parent; text: "Close"; color: Theme.w62 }
        }

        // ------------------------------------------------------------ scenes, for the whole house
        Row {
            visible: sh.shown === "scenes"
            x: 36; y: 72; spacing: 16
            Repeater {
                model: {
                    var here = room.here || "This room"
                    return [["Evening", "Warm, 50% everywhere"], ["Movie", here + " low, rest off"],
                            ["Night", here + " glowing, rest off"], ["All off", "Every light"]]
                }
                Press {
                    width: (1280 - 72 - 48) / 4; height: 200; pressScale: 0.97
                    onTapped: { room.houseScene(modelData[0]); sh.close() }
                    Rectangle { anchors.fill: parent; radius: 16; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                    Serif { x: 22; y: 22; text: modelData[0]; font.pixelSize: 46 }
                    Mono { x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 22; width: parent.width - 44; text: modelData[1]; size: 12; color: Theme.w62 }
                }
            }
        }

        // ------------------------------------------------------------ where the music plays
        Flickable {
            visible: sh.shown === "speakers"
            x: 36; y: 64; width: 1280 - 72; height: 340 - 64 - 14
            contentHeight: spk.height; clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: spk
                width: parent.width
                Repeater {
                    model: {
                        var bt = ((room.bluetooth || {}).devices || []).filter(function (d) { return d.connected })
                        return (sh.music.devices || []).map(function (d) {
                            var here = sh.music.hereDevice && d.name.toLowerCase() === sh.music.hereDevice
                            return { id: d.id, active: d.active,
                                     name: here && bt.length ? bt[0].name : here ? "This panel" : d.name,
                                     sub: here ? (bt.length ? "Bluetooth · on this panel" : "On this panel") : "Spotify Connect" }
                        })
                    }
                    Press {
                        width: spk.width; height: 62; pressScale: 0.99
                        onTapped: { room.transfer(modelData.id); sh.close() }
                        T { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 24; color: "white" }
                        Mono {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 12
                            text: modelData.active ? "● Playing here" : modelData.sub; color: modelData.active ? "white" : Theme.w62
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                    }
                }
                Mono { visible: (sh.music.devices || []).length === 0; topPadding: 18; text: "No speakers awake — open Spotify on one"; color: Theme.w62 }
            }
        }

        // ------------------------------------------------------------ playlists and albums
        ListView {
            visible: sh.shown === "library"
            x: 36; y: 72; width: 1280 - 72; height: 240
            orientation: ListView.Horizontal; spacing: 22; clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: [{ name: "Liked songs", uri: "liked", art: "" }].concat(sh.music.playlists || [])
            delegate: Press {
                width: 128; height: 200; pressScale: 0.95
                onTapped: { if (modelData.uri === "liked") room.playLiked(); else room.playUri(modelData.uri); sh.close() }
                Art {
                    width: 128; height: 128; radius: 10
                    source: modelData.art || ""; liked: modelData.uri === "liked"
                    rgb: [[140, 94, 78], [78, 110, 140], [110, 140, 94], [140, 122, 78], [122, 106, 140], [94, 140, 132]][index % 6]; rgb2: [21, 21, 21]
                }
                Mono { y: 140; width: parent.width; text: modelData.name; size: 12 }
            }
        }
    }
}
