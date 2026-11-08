import QtQuick

// Alexa — a ring of dots that moves with your voice, and what you said, large. Speech isn't connected yet on the
// Surface (it comes with whisper.cpp), so for now the screen says so instead of pretending to listen.
Item {
    id: as
    width: Theme.stageW; height: Theme.stageH
    property bool active: false
    signal close()
    property real t: 0
    Timer { interval: 50; repeat: true; running: as.active && as.visible; onTriggered: as.t += 0.05 }
    property real lvl: room.micOn ? room.level : 0.25 + 0.15 * Math.sin(t * 2.3)

    Glow { anchors.centerIn: ring; width: 1040; height: 1040; color: Theme.accent; strength: 0.14 + 0.1 * as.lvl }
    RoundBtn { x: 56; y: 48; size: 64; icon: "close"; iconSize: 22; onTapped: as.close() }

    Item {
        id: ring
        x: 684 - 180; y: 330 - 180; width: 360; height: 360
        Repeater {
            model: 48
            Rectangle {
                readonly property real a: index / 48 * Math.PI * 2
                readonly property real wob: 0.5 + 0.5 * Math.sin(index * 1.7 + as.t * 3)
                readonly property real r: 150 + wob * 26 * (0.4 + as.lvl)
                x: 180 + Math.cos(a) * r - 6; y: 180 + Math.sin(a) * r - 6
                width: 12; height: 12; radius: 6
                color: Qt.rgba(1, 207 / 255, 156 / 255, 0.35 + 0.55 * wob)
            }
        }
    }
    SectionCap { anchors.horizontalCenter: parent.horizontalCenter; y: 572; text: room.micOn ? "Listening" : "Voice isn't set up yet"; color: Qt.rgba(1, 207 / 255, 156 / 255, 0.8) }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 620; width: 1000
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: room.micOn ? "" : "Speech on the Surface comes next (whisper.cpp). Until then, everything here works by touch."
        font.pixelSize: 34; font.weight: Font.Light; lineHeight: 1.15
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 790
        text: "Try “set a timer for 10 minutes”  ·  “what's the weather tomorrow”  ·  “play Liked Songs”"
        font.pixelSize: 19; color: Theme.sub
    }
}
