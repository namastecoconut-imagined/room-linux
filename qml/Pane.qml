import QtQuick
// The redesign's glass, used sparingly: white 15 % → 5 % down the pane, a 1 px line round it (15 %), a brighter 1 px
// light along the top (30 %). What's behind it is softened by the background itself (Field: no grain, a little more
// colour inside the pane), which costs nothing — a real blur of the screen behind it would, every frame.
Rectangle {
    radius: 22
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.15) }
        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.05) }
    }
    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
    Rectangle {
        x: parent.radius * 0.7; width: parent.width - parent.radius * 1.4; y: 1; height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.12; color: Qt.rgba(1, 1, 1, 0.3) }
            GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 0.3) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
