import QtQuick

// Choose where the music plays: every Spotify Connect speaker that's awake. Tap outside to close.
Item {
    id: sp
    property bool open: false
    property var devices: []
    signal close()
    signal pick(string id)
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: sp.close() }

    Rectangle {
        id: sheet
        radius: 30; border.color: Qt.rgba(1, 1, 1, 0.08); clip: true
        width: 560; height: Math.min(640, 120 + Math.max(1, sp.devices.length) * 88)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: sp.open ? 0 : 40
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        color: "#141312"
        MouseArea { anchors.fill: parent }   // taps on the sheet don't close it
        Cap { x: 32; y: 32; text: "Play on" }
        Column {
            x: 16; y: 72; width: parent.width - 32
            Repeater {
                model: sp.devices
                Press {
                    width: parent.width; height: 88; pressScale: 0.98
                    Rectangle { anchors.fill: parent; radius: 22; color: modelData.active ? Qt.rgba(1, 1, 1, 0.07) : "transparent" }
                    Icon { x: 22; anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 26; color: modelData.active ? Theme.warm : Theme.mut }
                    Column {
                        x: 70; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        T { text: modelData.name; font.pixelSize: 24; font.weight: modelData.active ? Font.Medium : Font.Normal }
                        T { text: modelData.active ? "Playing here" : modelData.type; font.pixelSize: 17; color: Theme.mut }
                    }
                    onTapped: sp.pick(modelData.id)
                }
            }
            T { visible: sp.devices.length === 0; x: 16; y: 16; text: "No speakers awake — open Spotify on one"; color: Theme.dim; font.pixelSize: 21 }
        }
    }
}
