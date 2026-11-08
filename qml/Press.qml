import QtQuick
// Anything tappable: shrinks a touch while pressed, fires on release (and on long-press if asked).
Item {
    id: p
    signal tapped()
    signal held()
    property real pressScale: 0.96
    property alias pressed: ma.pressed
    scale: ma.pressed ? pressScale : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    MouseArea {
        id: ma
        anchors.fill: parent
        pressAndHoldInterval: 900
        onClicked: p.tapped()
        onPressAndHold: p.held()
    }
}
