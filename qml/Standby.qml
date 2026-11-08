import QtQuick

// Standby — the breathing dot field and morning glow (drawn in one GPU shader), the dot clock that rearranges each
// minute, weather and what's next. Very dark: it's what the room sees most of the day.
Item {
    id: sb
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false
    property var wx: room.weather
    property real t: 0
    // time runs only while standby is showing, so a hidden standby costs nothing
    NumberAnimation on t { running: sb.visible; from: 0; to: 100000; duration: 100000 * 1000; loops: Animation.Infinite }

    ShaderEffect {
        anchors.fill: parent
        property real time: sb.t
        property real level: room.level
        property real pitch: 22 * (width > 0 ? width / Theme.stageW : 1)
        property real dim: sb.night ? 0.45 : 1.0
        property size res: Qt.size(width, height)
        property color c1: "#ffb38a"
        property color c2: "#8cc4ff"
        property color c3: "#ffd6c0"
        vertexShader: shaderDir + "standby.vert.qsb"
        fragmentShader: shaderDir + "standby.frag.qsb"
        blending: false
    }

    DotText {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: 250
        pitch: 30
        text: Theme.clock(new Date(sb.now * 1000), room.clock24)
        opacity: sb.night ? 0.6 : 1
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; y: 528; spacing: 10
        visible: wx.ok === true
        T { text: wx.t + "°"; font.pixelSize: 28; font.weight: Font.Light }
        T { text: (wx.d || "") + (wx.hi !== null && wx.hi !== undefined ? "  ·  ↑" + wx.hi + "° ↓" + wx.lo + "°" : ""); font.pixelSize: 28; font.weight: Font.Light; color: Theme.mut }
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; y: 582
        readonly property var ev: room.events.length ? room.events[0] : null
        visible: ev !== null
        text: ev ? ev.when + "  ·  " + ev.title : ""
        font.pixelSize: 22; color: Theme.mut
    }
    T {
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 40
        text: Qt.formatDate(new Date(sb.now * 1000), "dddd d MMMM").toUpperCase()
        font.pixelSize: 17; font.letterSpacing: 2.4; color: Theme.dim
    }
}
