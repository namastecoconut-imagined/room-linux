import QtQuick

// The standby clock, as on the phone: a dot-matrix time whose dots rearrange when the minute changes. Each digit
// keeps its own dots; a dot that's needed elsewhere loosens (out a little, ±22 pt) and settles into its new place
// over 1.3–1.55 s; new dots appear from up to 30 pt away and fade in over 0.6 s; dots no longer needed drift off
// and fade over 0.8 s.
Item {
    id: clk
    property string text: "00:00"
    property real pitch: 36
    property color ink: Theme.tx
    property real k: pitch / 15            // phone points → pixels at this size
    readonly property var glyphs: ({
        "0": ["01110","10001","10001","10001","10001","10001","01110"], "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"], "3": ["01110","10001","00001","00110","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"], "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"], "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"], "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ":": ["0","0","1","0","1","0","0"]
    })
    readonly property real r: pitch * 0.36
    property bool ready: false
    // per character slot: its dots' targets (reading order within the glyph, as the phone does)
    readonly property var layout: {
        var out = [], x = 0
        for (var c = 0; c < text.length; c++) {
            var g = glyphs[text[c]]; if (!g) continue
            var pts = []
            for (var y = 0; y < 7; y++) for (var i = 0; i < g[0].length; i++) if (g[y][i] === "1") pts.push([x + i * pitch + r, y * pitch + r])
            out.push(pts)
            x += g[0].length * pitch + pitch
        }
        return { slots: out, w: Math.max(1, x - pitch) }
    }
    width: layout.w; height: 7 * pitch
    Component.onCompleted: ready = true

    Repeater {
        model: 5 * 35
        Rectangle {
            id: d
            readonly property int slot: Math.floor(index / 35)
            readonly property int n: index % 35
            readonly property var target: slot < clk.layout.slots.length && n < clk.layout.slots[slot].length ? clk.layout.slots[slot][n] : null
            width: clk.r * 2; height: width; radius: width / 2
            color: clk.ink
            antialiasing: true
            property real fx: 0; property real fy: 0     // from
            property real mx: 0; property real my: 0     // the loosened mid-point
            property real tx: 0; property real ty: 0     // to
            property real p: 1
            // a curve through the mid-point: from → loosened → settled
            x: (1 - p) * (1 - p) * fx + 2 * (1 - p) * p * (2 * mx - (fx + tx) / 2) + p * p * tx - clk.r
            y: (1 - p) * (1 - p) * fy + 2 * (1 - p) * p * (2 * my - (fy + ty) / 2) + p * p * ty - clk.r
            opacity: 0
            property bool on: false
            NumberAnimation { id: settle; target: d; property: "p"; from: 0; to: 1; easing.type: Easing.Bezier; easing.bezierCurve: [0.3, 0, 0.2, 1, 1, 1] }
            NumberAnimation { id: fadeIn; target: d; property: "opacity"; to: 1; duration: 600 }
            NumberAnimation { id: fadeOut; target: d; property: "opacity"; to: 0; duration: 800 }
            function place() {
                var animate = clk.ready && clk.visible && clk.opacity > 0.5
                var cx = x + clk.r, cy = y + clk.r
                if (target) {
                    var t = target
                    if (on && t[0] === tx && t[1] === ty) return      // this digit didn't change
                    if (!on) {
                        // a new dot: from somewhere near, fading in
                        var sx = animate ? t[0] + (Math.random() * 60 - 30) * clk.k : t[0]
                        var sy = animate ? t[1] + (Math.random() * 60 - 30) * clk.k : t[1]
                        fx = sx; fy = sy; mx = (sx + t[0]) / 2; my = (sy + t[1]) / 2
                        on = true
                    } else {
                        fx = cx; fy = cy
                        mx = (cx + t[0]) / 2 + (Math.random() * 44 - 22) * clk.k
                        my = (cy + t[1]) / 2 + (Math.random() * 44 - 22) * clk.k
                    }
                    tx = t[0]; ty = t[1]
                    if (animate && (fx !== tx || fy !== ty)) { settle.duration = 1300 + Math.random() * 250; settle.restart() } else { settle.stop(); p = 1 }
                    fadeOut.stop()
                    if (animate) fadeIn.restart(); else opacity = 1
                } else if (on) {
                    // no longer needed: drift off and fade
                    on = false
                    settle.stop()
                    fx = cx; fy = cy
                    tx = cx + (animate ? (Math.random() * 60 - 30) * clk.k : 0)
                    ty = cy + (animate ? (Math.random() * 60 - 30) * clk.k : 0)
                    mx = (fx + tx) / 2; my = (fy + ty) / 2
                    if (animate) { settle.duration = 800; settle.restart(); fadeIn.stop(); fadeOut.restart() } else { p = 1; opacity = 0 }
                }
            }
            onTargetChanged: place()
            Component.onCompleted: place()
        }
    }
}
