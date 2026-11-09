import QtQuick

// The library: your playlists as covers in a row along the bottom (swipe sideways, tap one to play it) — low on the
// screen, under the strips the touch screen doesn't answer in. Opens over the player; Back to close.
Item {
    id: lib
    property bool open: false
    property var playlists: []
    signal close()
    signal play(string uri)
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.94) }
    MouseArea { anchors.fill: parent; onClicked: lib.close() }

    RoundBtn { x: 24; y: 24; size: 110; iconSize: 40; icon: "back"; fill: "transparent"; onTapped: lib.close() }
    T { x: 96; y: Theme.deadA0 + 40; text: "Playlists"; font.pixelSize: 64; font.weight: Font.Light }
    T { x: 98; y: Theme.deadA0 + 130; text: lib.playlists.length + " of yours  ·  swipe along the bottom, tap one to play"; font.pixelSize: 22; color: Theme.sub }

    ListView {
        id: grid
        orientation: ListView.Horizontal
        x: 48; y: Theme.deadB1 + 12; width: 1368 - 96; height: 896 - y
        spacing: 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: lib.playlists
        delegate: Press {
            width: 296; height: grid.height; pressScale: 0.96
            Cover {
                width: parent.width; height: 296; radius: 30
                source: modelData.art || ""
                rgb: [[140, 94, 78], [78, 110, 140], [110, 140, 94], [140, 122, 78], [122, 106, 140], [94, 140, 132]][index % 6]
                rgb2: [21, 21, 21]
            }
            T { y: 312; width: parent.width; text: modelData.name; font.pixelSize: 24; elide: Text.ElideRight }
            onTapped: lib.play(modelData.uri)
        }
        T { visible: lib.playlists.length === 0; text: "Your playlists show up here"; color: Theme.dim; font.pixelSize: 28 }
    }
}
