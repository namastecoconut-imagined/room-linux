pragma Singleton
import QtQuick

// Colours and type from the iPhone panel (NativeKit Theme), sized for a 12" screen seen from across a room.
QtObject {
    readonly property color tx: "#f4f2ef"
    readonly property color mut: "#9a9794"
    readonly property color dim: "#5d5b58"
    readonly property color warm: "#ffbe7a"
    readonly property color accent: "#ffcf9c"
    readonly property color hair: Qt.rgba(1, 1, 1, 0.09)
    // the quieter set the newer screens use (warm off-white at a few strengths)
    readonly property color ink: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.95)
    readonly property color sub: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.5)
    readonly property color rule: Qt.rgba(1, 1, 1, 0.07)
    readonly property color rain: "#7fb4ff"
    // Helvetica Neue when it's installed (it's the panel's face); Inter Tight, which ships with Room, otherwise
    readonly property string face: Qt.fontFamilies().indexOf("Helvetica Neue") >= 0 ? "Helvetica Neue" : "Inter Tight"
    readonly property real stageW: 1368
    readonly property real stageH: 912
    // This Surface's touch screen doesn't respond across a wide band of it (a fault in the digitiser, found with touch
    // tests): stage y deadA0–deadB1. Every screen keeps buttons, sliders and lists out of it — in the top bar (topY)
    // or the lower part — and puts only things to read there (the clock, the weather, labels). If it's measured
    // again, change it here.
    // (from the sensor test: 44 lines; 0–5 work, 6–7 fire phantom touches, 8–16 dead, 17–19 work, 20–23 dead, 24–43
    // work — one line ≈ 20.7 px. Room drops the phantom touches itself, see room/__main__.py)
    readonly property real deadA0: 118
    readonly property real deadB1: 500
    readonly property real topY: 40                 // where a top-bar control (68 high) sits
    readonly property real capY: deadB1 - 34         // a label just above the lower part

    function rgb(a, alpha) { return Qt.rgba(a[0] / 255, a[1] / 255, a[2] / 255, alpha === undefined ? 1 : alpha) }
    function two(n) { return (n < 10 ? "0" : "") + n }
    function clock(d, h24) {
        var h = d.getHours(), m = d.getMinutes()
        if (!h24) { h = h % 12; if (h === 0) h = 12 }
        return (h24 ? two(h) : "" + h) + ":" + two(m)
    }
    function hm(h, m, h24) { return h24 ? two(h) + ":" + two(m) : ((h % 12) || 12) + ":" + two(m) }
    function ampm(h, h24) { return h24 ? "" : (h < 12 ? "am" : "pm") }
    function dateLine(d) { return Qt.formatDate(d, "dddd, d MMMM") }
    function hour(h, h24) { return h24 ? two(h) : ((h % 12 === 0 ? 12 : h % 12) + (h < 12 ? "a" : "p")) }
    function hourText(h, h24) { return h24 ? two(h) + ":00" : ((h % 12) || 12) + (h < 12 ? " am" : " pm") }
    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : "" }
    function aqiWord(v) { return v <= 50 ? "good" : v <= 100 ? "moderate" : v <= 150 ? "poor" : v <= 200 ? "unhealthy" : v <= 300 ? "very unhealthy" : "hazardous" }
    // a cover colour bright enough to read as light: keeps the hue, lifts dark covers (the phone's StandbyView.lit)
    function lit(rgb) { var m = Math.max(1, rgb[0], rgb[1], rgb[2]), k = Math.max(1, 225 / m); return [Math.min(255, rgb[0] * k), Math.min(255, rgb[1] * k), Math.min(255, rgb[2] * k)] }
    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + two(s % 60) }
    function countdown(s) { s = Math.max(0, Math.ceil(s)); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h ? h + ":" + two(m) : two(m)) + ":" + two(s % 60) }
    // The line under the clock (design D1): "Monday evening, 9 November." then "22° and clear, rain around 4 pm."
    function dayPart(h) { return h >= 5 && h < 12 ? "morning" : h >= 12 && h < 17 ? "afternoon" : h >= 17 && h < 21 ? "evening" : "night" }
    function dayLine(d) { return Qt.formatDate(d, "dddd") + " " + dayPart(d.getHours()) + ", " + Qt.formatDate(d, "d MMMM") + "." }
    function wxLine(wx, h24) {
        if (!wx || wx.ok !== true) return "Getting the weather\u2026"
        var d = (wx.d || "").toLowerCase(), s = (wx.t === undefined || wx.t === null ? "" : wx.t + "\u00b0 and ") + d
        var r = rainAt(wx.hours), wet = /rain|drizzle|shower|thunder|storm/.test(d)
        // rain only when it's actually due; bad air only when there's no rain to mention
        if (r > 0) s += ", rain around " + hourText(wx.hours[r].h, h24)
        else if (r === 0 && !wet) s += ", rain any minute"
        else if (r < 0 && wx.aqi && wx.aqi > 150) s += ", air is " + aqiWord(wx.aqi) + " today"
        return s + "."
    }
    // the first hour (of the next 12) rain is likely, or -1
    function rainAt(hours) { for (var i = 0; i < (hours || []).length && i < 12; i++) if ((hours[i].p || 0) >= 50) return i; return -1 }
}
