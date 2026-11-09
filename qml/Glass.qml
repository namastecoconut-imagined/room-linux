import QtQuick
// A pane of frosted glass over the song's colours (home): see-through white, a hairline edge, a faint light along
// the top.
Rectangle {
    radius: 30
    property bool tinted: true          // over colour (music playing) the glass is a touch more visible
    color: Qt.rgba(1, 1, 1, tinted ? 0.085 : 0.05)
    border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
    Behavior on color { ColorAnimation { duration: 1200 } }
    Rectangle {
        anchors.fill: parent; radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
