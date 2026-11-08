import QtQuick

// Alexa — a ring of dots that moves with your voice, what you said large underneath, and the answer below it.
// Listening: the ring swells with the mic. Thinking: it turns slowly. Speaking: it breathes. Tap the ring to talk
// again; × (or a few seconds after the answer) goes back.
Item {
    id: as
    width: Theme.stageW; height: Theme.stageH
    property bool active: false
    property var v: room.voice
    readonly property string st: v.state || "off"
    signal close()
    property real t: 0
    Timer { interval: 40; repeat: true; running: as.active && as.visible; onTriggered: as.t += 0.04 }
    property real lvl: st === "listening" ? room.level : st === "speaking" ? 0.35 + 0.25 * Math.sin(t * 5.5) : 0.15
    Behavior on lvl { NumberAnimation { duration: 90 } }

    Glow { anchors.centerIn: ring; width: 1040; height: 1040; color: Theme.accent; strength: 0.12 + 0.14 * as.lvl }
    RoundBtn { x: 56; y: 48; size: 64; icon: "close"; iconSize: 22; onTapped: { room.cancelVoice(); as.close() } }

    Press {
        id: ring
        x: 684 - 200; y: 290 - 200; width: 400; height: 400
        pressScale: 0.97
        onTapped: room.listen()
        Repeater {
            model: 48
            Rectangle {
                readonly property real a: index / 48 * Math.PI * 2 + (as.st === "thinking" ? as.t * 0.9 : 0)
                readonly property real wob: 0.5 + 0.5 * Math.sin(index * 1.7 + as.t * 3)
                readonly property real r: 130 + wob * 34 * (0.25 + as.lvl)
                x: 200 + Math.cos(a) * r - 6; y: 200 + Math.sin(a) * r - 6
                width: 12; height: 12; radius: 6
                color: Qt.rgba(1, 207 / 255, 156 / 255, (as.st === "off" ? 0.2 : 0.35) + (as.st === "off" ? 0.2 : 0.55) * wob)
            }
        }
        Icon { anchors.centerIn: parent; visible: as.st === "idle" || as.st === "off"; name: "mic"; size: 40; color: Qt.rgba(1, 207 / 255, 156 / 255, as.st === "off" ? 0.4 : 0.8) }
    }

    SectionCap {
        anchors.horizontalCenter: parent.horizontalCenter; y: 528
        text: as.st === "listening" ? "Listening" : as.st === "thinking" ? "One moment" : as.st === "speaking" ? "" : as.st === "off" ? "Voice is off" : (as.v.heard ? "" : "Tap the ring or say “Alexa”")
        color: Qt.rgba(1, 207 / 255, 156 / 255, 0.8)
    }
    T {
        id: heardT
        anchors.horizontalCenter: parent.horizontalCenter; y: 572; width: 1100
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 2
        text: as.st === "off" ? (as.v.error || "Voice isn't set up yet") : as.v.heard ? "“" + as.v.heard + "”" : ""
        font.pixelSize: as.st === "off" ? 30 : 44; font.weight: Font.Light; lineHeight: 1.12
        color: as.v.reply ? Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.6) : Theme.ink
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: heardT.y + heardT.height + 26; width: 1000
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 3
        text: as.v.reply || ""
        font.pixelSize: 32; lineHeight: 1.15
        color: Theme.accent
    }
    T {
        visible: !as.v.heard && as.st !== "off"
        anchors.horizontalCenter: parent.horizontalCenter; y: 800
        text: "Try “set a timer for 10 minutes”  ·  “turn the living room to 40 percent”  ·  “play Liked Songs”"
        font.pixelSize: 19; color: Theme.sub
    }
}
