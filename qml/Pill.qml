import QtQuick
// A rounded button with a label (and an optional icon before it). `lit` gives it the warm wash.
Press {
    id: p
    property string text: ""
    property string icon: ""
    property bool lit: false
    property color fill: lit ? Qt.rgba(1, 190 / 255, 122 / 255, 0.16) : Qt.rgba(1, 1, 1, 0.06)
    property real fontSize: 19
    property color ink: fill.a > 0.5 && fill.hslLightness > 0.6 ? "#151311" : Theme.ink
    height: 64
    pressScale: 0.97
    Rectangle { anchors.fill: parent; radius: height / 2; color: p.fill }
    Row {
        anchors.centerIn: parent; spacing: 10
        Icon { visible: p.icon !== ""; name: p.icon; size: 22; anchors.verticalCenter: parent.verticalCenter }
        T { text: p.text; color: p.ink; font.pixelSize: p.fontSize; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideNone }
    }
}
