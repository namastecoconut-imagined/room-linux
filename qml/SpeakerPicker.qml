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
        // low on the screen, under the strips the touch screen doesn't answer in
        width: 640; height: Math.min(896 - Theme.deadB1 - 6, 100 + Math.max(1, sp.devices.length) * 88)
        x: (parent.width - width) / 2
        y: 896 - height + (sp.open ? 0 : 40)
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        color: "#141312"
        MouseArea { anchors.fill: parent }   // taps on the sheet don't close it
        Cap { x: 32; y: 28; text: "Play on" }
        Flickable {
            x: 16; y: 64; width: parent.width - 32; height: parent.height - 76
            contentHeight: spCol.height; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: spCol
            width: parent.width
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
}
