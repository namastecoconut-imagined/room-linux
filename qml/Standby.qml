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
        property vector4d r4: sb.rectPt(rightCol, 0)
        property vector4d r5: sb.rectPt(hoursBox, 0)
        property vector4d rip0: sb.rips[0]
        property vector4d rip1: sb.rips[1]
        property vector4d rip2: sb.rips[2]
        property vector4d rip3: sb.rips[3]
        vertexShader: shaderDir + "standby.vert.qsb"
        fragmentShader: shaderDir + "standby.frag.qsb"
    }

    // ---------------------------------------------------------------- left: date, clock
    readonly property real colL: 72
    readonly property real colR: 760
    T {
        id: dayL
        x: sb.colL; y: 64; width: implicitWidth
        text: Qt.formatDate(new Date(sb.now * 1000), "dddd  d MMMM")
        font.pixelSize: 30; color: sb.soft
    }
    T {
        id: statusL
        anchors.right: parent.right; anchors.rightMargin: sb.colL; y: 66; width: implicitWidth
        visible: text !== ""
        text: room.status
        font.pixelSize: 26; color: sb.soft
    }
    ClockDots {
        id: clock
        x: sb.colL; y: 150
        pitch: 22
        ink: sb.ink
        text: Theme.clock(new Date(sb.now * 1000), room.clock24)
    }

    // ---------------------------------------------------------------- left: the weather, now and the next 12 hours
    readonly property var hours: (wx.hours || []).slice(0, 12)
    readonly property int rainAt: {
        for (var i = 0; i < hours.length; i++) if ((hours[i].p || 0) >= 50) return i
        return -1
    }
    function hourLabel(h) { return room.clock24 ? ("" + h) : ("" + ((h % 12) || 12)) }
    Column {
        id: wxBox
        x: sb.colL; y: 390
        visible: wx.ok === true
        spacing: 4
        T { text: "WEATHER"; font.pixelSize: 20; font.weight: Font.Medium; font.letterSpacing: 3.2; color: sb.gold; bottomPadding: 6 }
        Row {
            spacing: 18
            T { text: (wx.t || 0) + "°"; font.pixelSize: 52; font.weight: Font.Light; color: sb.ink }
            T { anchors.baseline: parent.children[0].baseline; text: Theme.cap(wx.d || ""); font.pixelSize: 30; color: sb.soft }
        }
        T {
            text: [(wx.hi !== null && wx.hi !== undefined ? wx.hi + "° / " + wx.lo + "°" : ""),
                   (wx.aqi ? "air " + wx.aqi + " " + Theme.aqiWord(wx.aqi) : ""),
                   (sb.rainAt >= 0 ? "rain ~" + sb.hourLabel(sb.hours[sb.rainAt].h) + (room.clock24 ? ":00" : (sb.hours[sb.rainAt].h < 12 ? " am" : " pm")) : "")]
                  .filter(function (s) { return s }).join("  ·  ")
            font.pixelSize: 24; color: sb.soft
        }
    }
    Item {
        id: hoursBox
        x: sb.colL; y: 700 - 6 * 22 - 6
        visible: wx.ok === true && sb.hours.length > 0
        width: sb.hours.length * 46; height: 6 * 22 + 6 + 24 + 20
        readonly property real lo: { var m = 999; for (var i = 0; i < sb.hours.length; i++) m = Math.min(m, sb.hours[i].t); return m }
        readonly property real hi: { var m = -999; for (var i = 0; i < sb.hours.length; i++) m = Math.max(m, sb.hours[i].t); return m }
        Repeater {
            model: sb.hours
            Item {
                x: index * 46; width: 12; height: hoursBox.height
                // 1–6 dots: the day's coolest hour is one dot, its warmest six
                readonly property int n: hoursBox.hi > hoursBox.lo ? 1 + Math.round(5 * (modelData.t - hoursBox.lo) / (hoursBox.hi - hoursBox.lo)) : 3
                Repeater {
                    model: 6
                    Rectangle {
                        y: 6 * 22 + 6 - index * 22 - 0
                        width: 12; height: 12; radius: 6
                        readonly property bool on: index < parent.n
                        color: !on ? Qt.rgba(1, 244 / 255, 232 / 255, 0.12)
                               : index === parent.n - 1 ? Qt.rgba(1, 207 / 255, 156 / 255, 0.95)
                               : Qt.rgba(1, 244 / 255, 232 / 255, 0.85)
                    }
                }
                Rectangle {
                    visible: index === sb.rainAt
                    y: 6 * 22 + 6 - 6 * 22 - 6; width: 12; height: 12; radius: 6
                    color: "#7fb4ff"
                }
                T {
                    x: -6; width: 24; y: 6 * 22 + 6 + 24
                    horizontalAlignment: Text.AlignHCenter
                    text: sb.hourLabel(modelData.h)
                    font.pixelSize: 17; color: sb.soft
                }
            }
        }
    }

    // ---------------------------------------------------------------- right: coming up, then the house
    readonly property var lit: room.rooms.filter(function (r) { return r.on > 0 })
    readonly property var known: room.rooms.filter(function (r) { return r.reachable > 0 })
    Column {
        id: rightCol
        x: sb.colR; y: 150; width: 1368 - sb.colL - sb.colR
        spacing: 0
        T { text: "COMING UP"; font.pixelSize: 20; font.weight: Font.Medium; font.letterSpacing: 3.2; color: sb.gold; bottomPadding: 6 }
        Repeater {
            model: room.events.slice(0, 3)
            Item {
                width: rightCol.width; height: 72
                T { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 128; text: modelData.when; font.pixelSize: 26; color: sb.soft }
                Row {
                    x: 128; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                    T { text: modelData.title; font.pixelSize: 28; color: sb.ink; width: Math.min(implicitWidth, rightCol.width - 128 - 160) }
                    T { visible: (modelData.extra || "") !== ""; anchors.baseline: parent.children[0].baseline; text: "·  " + (modelData.extra || ""); font.pixelSize: 24; color: sb.soft }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 238 / 255, 222 / 255, 0.12) }
            }
        }
        T {
            visible: room.events.length === 0
            topPadding: 10
            text: "Nothing coming up"
            font.pixelSize: 30; color: sb.ink
        }
        Item { width: 1; height: 56 }
        T {
            visible: sb.known.length > 0
            text: "AT HOME"; font.pixelSize: 20; font.weight: Font.Medium; font.letterSpacing: 3.2; color: sb.gold; bottomPadding: 16
        }
        Flow {
            visible: sb.lit.length > 0
            width: rightCol.width; spacing: 12
            Repeater {
                model: sb.known
                Rectangle {
                    readonly property bool on: modelData.on > 0
                    height: 50; radius: 25
                    width: chip.implicitWidth + 40 + 20
                    color: on ? Qt.rgba(1, 190 / 255, 122 / 255, 0.16) : Qt.rgba(1, 1, 1, 0.05)
                    Rectangle { x: 20; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: parent.on ? "#ffbe7a" : Qt.rgba(1, 1, 1, 0.2) }
                    T {
                        id: chip
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name + "  ·  " + (parent.on ? modelData.level + "%" : "off")
                        font.pixelSize: 22; color: parent.on ? sb.ink : sb.soft
                    }
                }
            }
        }
        T {
            visible: sb.known.length > 0 && sb.lit.length === 0
            text: "All lights off"; font.pixelSize: 28; color: sb.soft
        }
    }
}
