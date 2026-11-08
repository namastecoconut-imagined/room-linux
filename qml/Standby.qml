import QtQuick

// Standby — a calm dashboard for the living room (P3). The iPhone panel's breathing dot field and four drifting
// colour blobs stay exactly as they were (one GPU shader, 12 fps by day, 10 in the evening, 8 at night; the dots fade
// down around the words; a sound sends a ripple). On top, in two columns:
//   left: the date, the dot clock (rearranges each minute), then the weather now and the next 12 hours as dot columns
//         (taller = warmer, the top dot amber, a blue dot over the first hour rain is likely)
//   right: what's coming up on the calendar, then which rooms have lights on
// Anything with nothing to show says so in a line, or (weather) leaves its space empty.
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
        // (every word block is a direct child of the face, so its own x / y are its place — and they keep the
        // binding live as the layout settles)
        return Qt.vector4d(item.x / k - 8, item.y / k - 6, item.width / k + 16, item.height / k + 12)
    }

    ShaderEffect {
        anchors.fill: parent
        blending: false
        property real bt: sb.bt
        property real gt: sb.gt
        property real period: sb.glowPeriod
        property real gday: sb.dayTime ? 1 : 0
        property real boost: sb.night ? 0.5 : 0.7                  // the dots: faint
        property real gstr: sb.night ? 0.14 : 0.2                  // the glow: one soft warm light
        property real glowV: sb.glowV
        property real frozen: 0
        property size res: Qt.size(width, height)
        property color dotCol: Qt.rgba(240 / 255, 232 / 255, 222 / 255, 1)
        // one warm glow, resting behind the clock and drifting only a little; the other three are off
        property color c0: Qt.rgba(1, 190 / 255, 130 / 255, 1)
        property color c1: "black"
        property color c2: "black"
        property color c3: "black"
        property vector4d home: Qt.vector4d((clock.x + clock.width / 2) / sb.k, (clock.y + clock.height / 2) / sb.k, 0.15, 0)
        property vector4d r0: sb.rectPt(clock, 0)
        property vector4d r1: sb.rectPt(dayL, 0)
        property vector4d r2: sb.rectPt(statusL, 0)
        property vector4d r3: sb.rectPt(rightCol, 0)
        property vector4d r4: Qt.vector4d(0, 0, 0, 0)
        property vector4d r5: Qt.vector4d(0, 0, 0, 0)
        property vector4d rip0: sb.rips[0]
        property vector4d rip1: sb.rips[1]
        property vector4d rip2: sb.rips[2]
        property vector4d rip3: sb.rips[3]
        vertexShader: shaderDir + "standby.vert.qsb"
        fragmentShader: shaderDir + "standby.frag.qsb"
    }

    // ---------------------------------------------------------------- top: the date, ⚡ status
    readonly property real margin: 96
    readonly property color txt: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.92)
    readonly property color sub: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.5)
    readonly property color capC: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.42)
    T {
        id: dayL
        x: sb.margin; y: 72; width: implicitWidth
        text: Qt.formatDate(new Date(sb.now * 1000), "dddd  d MMMM")
        font.pixelSize: 28; color: sb.sub
    }
    T {
        id: statusL
        x: sb.width - sb.margin - width; y: 74; width: implicitWidth
        visible: text !== ""
        text: room.status
        font.pixelSize: 24; color: sb.sub
    }

    // ---------------------------------------------------------------- the clock, on the screen's middle line
    ClockDots {
        id: clock
        x: sb.margin; y: (sb.height - height) / 2
        pitch: 24
        ink: sb.txt
        text: Theme.clock(new Date(sb.now * 1000), room.clock24)
    }

    // ---------------------------------------------------------------- right: now, next, the lights
    readonly property var hours: (wx.hours || []).slice(0, 12)
    readonly property int rainAt: {
        for (var i = 0; i < hours.length; i++) if ((hours[i].p || 0) >= 50) return i
        return -1
    }
    function hourText(h) { return room.clock24 ? h + ":00" : ((h % 12) || 12) + (h < 12 ? " am" : " pm") }
    readonly property var lit: room.rooms.filter(function (r) { return r.on > 0 })
    readonly property var known: room.rooms.filter(function (r) { return r.reachable > 0 })
    readonly property var ev: room.events
    component Cap2: T { font.pixelSize: 18; font.weight: Font.Medium; font.letterSpacing: 3.6; color: sb.capC; font.capitalization: Font.AllUppercase }
    component Rule: Item { width: rightCol.width; height: 61; Rectangle { y: 30; width: parent.width; height: 1; color: Qt.rgba(1, 238 / 255, 222 / 255, 0.1) } }

    Column {
        id: rightCol
        x: 800; y: clock.y - 14; width: sb.width - sb.margin - x
        // now
        Column {
            visible: wx.ok === true
            width: parent.width
            Cap2 { text: "Now"; bottomPadding: 10 }
            Row {
                spacing: 16
                T { id: tNow; text: (wx.t || 0) + "°"; font.pixelSize: 46; font.weight: Font.Light; color: sb.txt }
                T { anchors.baseline: tNow.baseline; text: Theme.cap(wx.d || ""); font.pixelSize: 28; color: sb.sub }
            }
            T {
                topPadding: 6; width: parent.width
                text: [(wx.hi !== null && wx.hi !== undefined ? wx.hi + "° / " + wx.lo + "°" : ""),
                       (wx.aqi ? "air " + wx.aqi : ""),
                       (sb.rainAt >= 0 ? "rain ~" + sb.hourText(sb.hours[sb.rainAt].h) : "")]
                      .filter(function (s) { return s }).join("   ·   ")
                font.pixelSize: 22; color: sb.sub
            }
        }
        Rule { visible: wx.ok === true }
        // next
        Cap2 { text: sb.ev.length ? "Next   ·   " + sb.ev[0].when + (sb.ev[0].today ? "" : "") : "Next"; bottomPadding: 10 }
        T {
            width: parent.width
            text: sb.ev.length ? sb.ev[0].title + (sb.ev[0].extra ? "" : "") : "Nothing coming up"
            font.pixelSize: 34; color: sb.ev.length ? sb.txt : sb.sub
        }
        T {
            visible: text !== ""; topPadding: 6; width: parent.width
            text: sb.ev.length > 1 ? "then " + sb.ev[1].title + "  ·  " + sb.ev[1].when : (sb.ev.length && sb.ev[0].extra ? sb.ev[0].extra : "")
            font.pixelSize: 22; color: sb.sub
        }
        // the lights
        Rule { visible: sb.known.length > 0 }
        Row {
            visible: sb.known.length > 0
            spacing: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: sb.lit.length ? Qt.rgba(1, 200 / 255, 140 / 255, 0.8) : Qt.rgba(1, 1, 1, 0.2)
            }
            T {
                width: rightCol.width - 20
                text: sb.lit.length ? sb.lit.map(function (r) { return r.name + " " + r.level + "%" }).join("   ·   ") : "All lights off"
                font.pixelSize: 22; color: sb.sub
            }
        }
    }
}
