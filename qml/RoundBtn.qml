import QtQuick
// A round button with an icon (drawn from SVG paths so it stays sharp at any size).
Press {
    id: b
    property real size: 64
    property string icon: ""
    property color fill: Qt.rgba(1, 1, 1, 0.08)
    property color ink: Theme.tx
    property real iconSize: size * 0.36
    width: size; height: size
    Rectangle { anchors.fill: parent; radius: width / 2; color: b.fill }
    Icon { anchors.centerIn: parent; name: b.icon; size: b.iconSize; color: b.ink }
}
