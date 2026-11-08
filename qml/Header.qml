import QtQuick
// Top of every inner screen: a round back button, the screen's name, and a quiet note on the right.
Item {
    id: h
    property string title: ""
    property string note: ""
    property string icon: "back"
    signal back()
    width: Theme.stageW; height: 160
    RoundBtn { x: 56; y: 48; size: 64; icon: h.icon; iconSize: 24; onTapped: h.back() }
    T { x: 144; y: 62; text: h.title; font.pixelSize: 26 }
    T { anchors.right: parent.right; anchors.rightMargin: 72; y: 66; text: h.note; font.pixelSize: 20; color: Theme.sub }
}
