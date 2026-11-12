import QtQuick

// Words that come in one at a time — the assistant's: what you asked, then Room's answer (room-motion.html aWords).
// Each fades in and rises a few pixels, `gap` ms after the one before. Laid out here — wrapped to the width, from the
// left or centred, a little smaller each step until it fits `maxHeight` — so every word can move on its own: when more
// of the answer arrives, the words already in stay where they are and only the new ones come in; if the space changes
// they glide to their new places. In the serif, lines `leading` × the size apart, as the design's line-height.
Item {
    id: ws
    property string text: ""
    property real size: 50              // the largest it's drawn; smaller if it doesn't fit
    property real minSize: 28
    property real maxHeight: 300
    property real leading: 1.14
    property int gap: 85
    property bool centre: false
    property color color: "white"
    readonly property real drawn: cur   // the size it's drawn at
    readonly property real textHeight: rows * cur * leading
    property real cur: size
    property int rows: 0
    property double lastAt: 0           // when the newest word comes in

    Text { id: probe; visible: false; font.family: Theme.serif; font.pixelSize: 100 }
    FontMetrics { id: fm; font: probe.font }          // measured at 100, scaled
    ListModel { id: wm }
    // laid out once things settle (during creation the measuring font isn't set yet)
    onTextChanged: Qt.callLater(lay)
    onWidthChanged: Qt.callLater(lay)
    onSizeChanged: Qt.callLater(lay)
    onMaxHeightChanged: Qt.callLater(lay)
    Component.onCompleted: Qt.callLater(lay)

    function lay() {
        var words = text.split(/\s+/).filter(function (w) { return w.length > 0 })
        if (!words.length || width <= 0) { wm.clear(); rows = 0; lastAt = 0; return }
        var s = size, L
        for (;;) {
            L = place(words, s)
            if (L.rows * s * leading <= maxHeight + 0.5 || s <= minSize) break
            s = Math.max(minSize, s - 2)
        }
        cur = s; rows = L.rows
        // the words already in, as long as they're the same, stay; the rest come in one after another
        var keep = 0
        while (keep < wm.count && keep < words.length && wm.get(keep).w === words[keep]) keep++
        while (wm.count > keep) wm.remove(wm.count - 1)
        var now = Date.now()
        var next = keep > 0 ? Math.max(now, lastAt + gap) : now
        for (var i = 0; i < words.length; i++) {
            var p = L.pos[i]
            if (i < keep) {
                wm.setProperty(i, "px", p.x); wm.setProperty(i, "py", p.y); wm.setProperty(i, "over", p.over)
            } else {
                wm.append({ w: words[i], px: p.x, py: p.y, over: p.over, at: next })
                lastAt = next; next += gap
            }
        }
    }
    // greedy lines, then each line's words placed (centred lines start further in)
    function place(words, s) {
        var k = s / 100, sp = fm.advanceWidth(" ") * k, lh = s * leading
        var lines = [[]], widths = [0]
        for (var i = 0; i < words.length; i++) {
            var w = fm.advanceWidth(words[i]) * k
            var n = lines.length - 1
            var need = widths[n] > 0 ? widths[n] + sp + w : w
            if (widths[n] > 0 && need > width) { lines.push([]); widths.push(0); n++; need = w }
            lines[n].push({ i: i, w: w })
            widths[n] = need
        }
        var pos = []
        for (var r = 0; r < lines.length; r++) {
            var x = centre ? (width - widths[r]) / 2 : 0
            for (var j = 0; j < lines[r].length; j++) {
                pos[lines[r][j].i] = { x: x, y: r * lh, over: (r + 1) * lh > maxHeight + 0.5 }
                x += lines[r][j].w + sp
            }
        }
        return { rows: lines.length, pos: pos }
    }

    Repeater {
        model: wm
        Text {
            id: wd
            required property string w
            required property real px
            required property real py
            required property bool over
            required property double at
            property bool placed: false
            property real off: 8                // rises into place
            // the glyphs centred in the line box, as the design (a web page) places them
            readonly property real centreY: (font.pixelSize * ws.leading - fm.height * font.pixelSize / 100) / 2
            text: w
            x: px; y: py
            visible: !over
            font.family: Theme.serif; font.pixelSize: ws.cur
            color: ws.color
            renderType: Text.CurveRendering        // Kasero's hairlines hold up (see Serif.qml)
            opacity: 0
            transform: Translate { y: wd.centreY + wd.off }
            Behavior on x { enabled: wd.placed; NumberAnimation { duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            Behavior on y { enabled: wd.placed; NumberAnimation { duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            Behavior on font.pixelSize { enabled: wd.placed; NumberAnimation { duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            Component.onCompleted: {
                var d = at - Date.now()
                if (d < -600) { opacity = 1; off = 0 }
                else { come.wait = Math.max(0, d); come.start() }
                placed = true
            }
            SequentialAnimation {
                id: come
                property int wait: 0
                PauseAnimation { duration: come.wait }
                ParallelAnimation {
                    NumberAnimation { target: wd; property: "opacity"; to: 1; duration: 450; easing.type: Easing.OutCubic }
                    NumberAnimation { target: wd; property: "off"; to: 0; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
                }
            }
        }
    }
}
