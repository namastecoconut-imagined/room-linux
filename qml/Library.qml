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

    Rectangle { anchors.fill: parent; color: "#0a0908" }
    MouseArea { anchors.fill: parent; onClicked: lib.close() }

    RoundBtn { x: 24; y: 24; size: 110; iconSize: 40; icon: "back"; fill: "transparent"; onTapped: lib.close() }
    T { x: 96; y: Theme.deadA0 + 40; text: "Playlists"; font.pixelSize: 64; font.weight: Font.Light }
    T { x: 98; y: Theme.deadA0 + 130; text: lib.playlists.length + " of yours  ·  the arrows go through them, tap one to play"; font.pixelSize: 22; color: Theme.sub }

    ListView {
        id: grid
        orientation: ListView.Horizontal
        x: (1368 - width) / 2; y: Theme.deadB1 + 12; width: 3 * 296 + 2 * 24; height: 896 - y        // three at a time
        interactive: false                      // the arrows move it (swiping isn't reliable on this screen)
        Behavior on contentX { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        function page(dir) {
            var step = (296 + 24) * 3
            contentX = Math.max(originX, Math.min(originX + contentWidth - width, contentX + dir * step))
        }
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

    // left / right, beside the row
    RoundBtn {
        x: grid.x - 40 - 92; y: grid.y + 148 - 46; size: 92; iconSize: 30; icon: "back"
        visible: lib.playlists.length > 3
        opacity: grid.contentX > grid.originX + 4 ? 1 : 0.3
        onTapped: grid.page(-1)
    }
    RoundBtn {
        x: grid.x + grid.width + 40; y: grid.y + 148 - 46; size: 92; iconSize: 30; icon: "chev"
        visible: lib.playlists.length > 3
        opacity: grid.contentX < grid.originX + grid.contentWidth - grid.width - 4 ? 1 : 0.3
        onTapped: grid.page(1)
    }
}
