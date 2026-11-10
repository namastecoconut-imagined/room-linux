import QtQuick

// The Surface's volume buttons: a pill in the middle of the screen shows the new level for a moment (over everything, standby
// included) — the speaker icon, a bar and the number, and whether it's the music or the speaker that changed.
Item {
    id: hud
    width: Theme.stageW; height: Theme.stageH
    property int level: 0
    property string what: ""
    Connections {
        target: room
        function onVolumeShown(v, w) { hud.level = v; hud.what = w; pill.opacity = 1; hide.restart() }
    }
    Timer { id: hide; interval: 1600; onTriggered: pill.opacity = 0 }
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: 460; height: 76; radius: 38
        color: Qt.rgba(0.07, 0.07, 0.08, 0.96)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: pill.opacity > 0.5 ? 400 : 150; easing.type: Easing.OutQuad } }
        Icon { x: 26; anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 26; color: Theme.ink }
        Item {
            x: 72; width: 290; height: 8; anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(1, 1, 1, 0.16) }
            Rectangle {
                height: parent.height; radius: 4; color: Theme.ink
                width: parent.width * hud.level / 100
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            }
        }
        T {
            anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight; width: 64
            text: hud.level + "%"; font.pixelSize: 22; color: Theme.ink
        }
        T {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom; anchors.topMargin: 8
            text: hud.what === "music" ? "music" : "speaker"; font.pixelSize: 15; color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
}
