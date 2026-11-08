import QtQuick

// Standby — the iPhone panel's StandbyView on the Surface. The phone's 568-pt-wide layout scaled up (×2.408), with
// the Surface's extra height going between the top and bottom rows. The breathing dot field and the four drifting
// colour blobs are one GPU shader, redrawn at the phone's slow rates (12 fps by day, 10 in the evening, 8 when
// dimmed at night) — everything else is still. The dots fade down around the words; a sound sends a ripple out.
//   top left: the date · top right: ⚡ and how warm it is · clock under the date
//   bottom left: today's weather (dot numerals) · bottom right: what's next on the calendar
Item {
    id: sb
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property bool night: false            // night hours: dimmer, slower
    property bool dayTime: true           // 7–18: brighter dots, soft white instead of amber
    property bool active: false           // standby is showing
    property var wx: room.weather
    readonly property real k: 1368 / 568                 // phone points → stage px
    readonly property real dy: (912 / k) - 320          // extra height, in phone points (≈ 58.7)
    function px(pt) { return pt * k }

    // ---------------------------------------------------------------- colours (as on the phone)
    readonly property color ink: dayTime ? Qt.rgba(1, 244 / 255, 232 / 255, 1) : Qt.rgba(1, 222 / 255, 190 / 255, 0.85)
    readonly property color soft: dayTime ? Qt.rgba(1, 238 / 255, 222 / 255, 0.6) : Qt.rgba(1, 222 / 255, 190 / 255, 0.42)
    readonly property color gold: Qt.rgba(1, 207 / 255, 156 / 255, dayTime ? 0.9 : 0.6)

    // ---------------------------------------------------------------- the slow clock
    readonly property int fps: night ? 8 : dayTime ? 12 : 10
    readonly property real breathSlow: night ? 1.6 : 1
    readonly property real glowPeriod: 80 * (dayTime ? 1 : night ? 2 : 1.25)
    property real t0: Date.now() / 1000
    property real bt: 0
    property real gt: 0
    // a voice swell and ripples (only when the mic is on)
    property real level: 0
    property real floorL: -1
    property real glowV: 0
    property var rips: [Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0)]
    property int ripN: 0
    property real lastRipple: 0
    readonly property bool rippling: gt - lastRipple < 4
    Timer {
        interval: Math.round(1000 / (sb.rippling ? 30 : sb.fps)); repeat: true
        running: sb.active && sb.visible
        onTriggered: {
            var t = Date.now() / 1000 - sb.t0
            sb.bt = t / sb.breathSlow
            sb.gt = t
        }
    }
    onActiveChanged: if (active) { t0 = Date.now() / 1000 - gt; floorL = -1 }
    Connections {
        target: room
        enabled: room.micOn && sb.active && sb.visible
        function onLevelChanged() {
            var l = room.level, jump = l - sb.level
            sb.level = l
            if (sb.floorL < 0) sb.floorL = l; else sb.floorL += (l - sb.floorL) * (l < sb.floorL ? 0.3 : 0.01)
            var raw = Math.max(0, Math.min(1, (l - sb.floorL - 0.1) * 1.5))
            sb.glowV += (raw - sb.glowV) * (raw > sb.glowV ? 0.3 : 0.12)
            if (jump > 0.08 && l > 0.22 && sb.gt - sb.lastRipple > 0.9) {
                sb.lastRipple = sb.gt
                var r = sb.rips.slice(); r[sb.ripN] = Qt.vector4d(sb.gt, Math.min(1, 0.4 + jump * 1.6), 0, 0)
                sb.ripN = (sb.ripN + 1) % 4; sb.rips = r
            }
        }
    }

    // ---------------------------------------------------------------- where the words are (phone points) — the field
    // fades down around them
    function rectPt(item, pad) {
        if (!item || !item.visible || item.width <= 0) return Qt.vector4d(0, 0, 0, 0)
        var p = item.mapToItem(sb, 0, 0)
        return Qt.vector4d(p.x / k - 8, p.y / k - 6, item.width / k + 16, item.height / k + 12)
    }

    ShaderEffect {
        anchors.fill: parent
        blending: false
        property real bt: sb.bt
        property real gt: sb.gt
        property real period: sb.glowPeriod
        property real gday: sb.dayTime ? 1 : 0
        property real boost: sb.dayTime ? 1.5 : 1
        property real gstr: sb.dayTime ? 0.42 : 0.34
        property real glowV: sb.glowV
        property real frozen: 0
        property size res: Qt.size(width, height)
        property color dotCol: sb.dayTime ? Qt.rgba(1, 240 / 255, 226 / 255, 1) : Qt.rgba(1, 196 / 255, 140 / 255, 1)
        // the "day" set at every hour — warm yellow, sky blue, mint, coral (Aviral's pick on the phone)
        property color c0: Qt.rgba(1, 200 / 255, 90 / 255, 1)
        property color c1: Qt.rgba(90 / 255, 190 / 255, 1, 1)
        property color c2: Qt.rgba(120 / 255, 230 / 255, 180 / 255, 1)
        property color c3: Qt.rgba(1, 140 / 255, 120 / 255, 1)
        property vector4d r0: sb.rectPt(clock, 0)
        property vector4d r1: sb.rectPt(dayL, 0)
        property vector4d r2: sb.rectPt(statusL, 0)
        property vector4d r3: sb.rectPt(wxBox, 0)
        property vector4d r4: sb.rectPt(evBox, 0)
        property vector4d r5: Qt.vector4d(0, 0, 0, 0)
        property vector4d rip0: sb.rips[0]
        property vector4d rip1: sb.rips[1]
        property vector4d rip2: sb.rips[2]
        property vector4d rip3: sb.rips[3]
        vertexShader: shaderDir + "standby.vert.qsb"
        fragmentShader: shaderDir + "standby.frag.qsb"
    }

    // ---------------------------------------------------------------- top
    T {
        id: dayL
        x: px(28); y: px(26); width: implicitWidth
        text: Qt.formatDate(new Date(sb.now * 1000), "dddd  d MMMM")
        font.pixelSize: px(15); color: sb.soft
    }
    T {
        id: statusL
        anchors.right: parent.right; anchors.rightMargin: px(30); y: px(28); width: implicitWidth
        visible: text !== ""
        text: room.status
        font.pixelSize: px(13); color: sb.soft
    }
    ClockDots {
        id: clock
        x: px(28); y: px(72)
        pitch: px(15)
        ink: sb.ink
        text: Theme.clock(new Date(sb.now * 1000), room.clock24)
    }

    // ---------------------------------------------------------------- bottom left: weather
    Item {
        id: wxBox
        x: px(30); y: px(236 + sb.dy)
        visible: wx.ok === true
        width: Math.max(wxLine.x + wxLine.implicitWidth, wxSub.implicitWidth); height: px(48)
        DotText { id: wxDots; pitch: px(3.6); text: "" + (wx.t || 0); color: sb.ink; glide: 0 }
        Rectangle {
            id: deg
            x: wxDots.width + px(3); y: 0; width: px(6); height: px(6); radius: width / 2
            color: "transparent"; border.color: sb.soft; border.width: px(1.2)
        }
        T {
            id: wxLine
            x: deg.x + deg.width + px(9); y: (wxDots.height - height) / 2
            text: Theme.cap(wx.d || ""); font.pixelSize: px(15); color: sb.ink
        }
        T {
            id: wxSub
            y: px(30)
            text: [(wx.hi !== null && wx.hi !== undefined ? wx.hi + "° / " + wx.lo + "°" : ""),
                   (wx.aqi ? "air " + wx.aqi + " " + Theme.aqiWord(wx.aqi) : "")].filter(function (s) { return s }).join("  ·  ")
            font.pixelSize: px(13); color: sb.soft
        }
    }

    // ---------------------------------------------------------------- bottom right: what's next
    Column {
        id: evBox
        readonly property var ev: room.events.length ? room.events[0] : null
        visible: ev !== null
        anchors.right: parent.right; anchors.rightMargin: px(30)
        y: px(230 + sb.dy)
        spacing: px(3)
        T {
            anchors.right: parent.right
            text: evBox.ev ? (evBox.ev.today ? "NEXT  ·  " + evBox.ev.when.toUpperCase() : evBox.ev.when.toUpperCase()) : ""
            font.pixelSize: px(10); font.weight: Font.Medium; font.letterSpacing: px(1.6); color: sb.gold
        }
        T { anchors.right: parent.right; width: Math.min(implicitWidth, px(260)); horizontalAlignment: Text.AlignRight; text: evBox.ev ? evBox.ev.title : ""; font.pixelSize: px(15); color: sb.ink }
        T {
            anchors.right: parent.right
            visible: text !== ""
            text: evBox.ev ? (evBox.ev.extra || "") + (room.events.length > 1 ? (evBox.ev.extra ? "  ·  " : "") + "then " + (room.events.length - 1) + " more" : "") : ""
            font.pixelSize: px(13); color: sb.soft
        }
    }
}
