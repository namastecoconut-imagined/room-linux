import QtQuick

// The library: your playlists as covers (tap one to play it). Opens over the player; tap outside or Back to close.
Item {
    id: lib
    property bool open: false
    property var playlists: []
    signal close()
    signal play(string uri)
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.82) }
    MouseArea { anchors.fill: parent; onClicked: lib.close() }

    RoundBtn { x: 24; y: 24; size: 110; iconSize: 40; icon: "back"; fill: "transparent"; onTapped: lib.close() }
    T { x: 140; y: 56; text: "Playlists"; font.pixelSize: 40; font.weight: Font.Medium }

    GridView {
        id: grid
        x: 48; y: 156; width: 1368 - 96; height: 912 - 156 - 24
        cellWidth: width / 4; cellHeight: 340
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: lib.playlists
        delegate: Press {
            width: grid.cellWidth - 28; height: 320; pressScale: 0.96
            Cover {
                width: parent.width; height: 248; radius: 30
                source: modelData.art || ""
                rgb: [[140, 94, 78], [78, 110, 140], [110, 140, 94], [140, 122, 78], [122, 106, 140], [94, 140, 132]][index % 6]
                rgb2: [21, 21, 21]
            }
            T { y: 262; width: parent.width; text: modelData.name; font.pixelSize: 26 }
            onTapped: lib.play(modelData.uri)
        }
        T { visible: lib.playlists.length === 0; text: "Your playlists show up here"; color: Theme.dim; font.pixelSize: 28 }
    }
}
