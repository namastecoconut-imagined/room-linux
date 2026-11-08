import QtQuick
// A smoked-glass tile: barely-there light at the top, darker below, a hairline edge.
Rectangle {
    radius: 30
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.055) }
        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.02) }
    }
    border.color: Qt.rgba(1, 1, 1, 0.07)
    border.width: 1
    clip: true
}
