import QtQuick

// Words that arrive one by one (the phone's WordFlow): new words rise into place; words already shown stay put.
// Each line is laid out from its left edge and the line as a whole glides to stay centred, so the words on it travel
// together and a new word can never land on top of an old one. When the recogniser changes its mind about an earlier
// word ("Um, what's" → "what's"), only the words that changed come and go — the rest stay and slide over.
Item {
    id: wf
    property real size: 67
    property int weight: Font.Medium
    property color color: Qt.rgba(1, 248 / 255, 240 / 255, 1)
    property real lineHeight: 1.14
    property bool centered: true
    property string placeholder: ""
    property real usedHeight: 0
    property var words: []
    clip: false

    // where each line starts (eased): the words on a line ride on it
    property real off0: 0; property real off1: 0; property real off2: 0; property real off3: 0; property real off4: 0
    readonly property var glide: [0.2, 0.8, 0.2, 1, 1, 1]
    Behavior on off0 { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
    Behavior on off1 { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
    Behavior on off2 { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
    Behavior on off3 { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
    Behavior on off4 { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
    function off(l) { return [off0, off1, off2, off3, off4][Math.min(l, 4)] }

    function norm(w) { return (w || "").toLowerCase().replace(/[^a-z0-9']/g, "") }

    function say(text) {
        var ws = (text || "").split(/\s+/).filter(function (w) { return w.length > 0 })
        placeholder = ""
        var a = words.map(norm), b = ws.map(norm), n = a.length, m = b.length
        // longest common run of words (in order) between what's shown and what's new: those stay
        var L = []
        for (var i = 0; i <= n; i++) { L.push([]); for (var j = 0; j <= m; j++) L[i].push(0) }
        for (i = n - 1; i >= 0; i--)
            for (j = m - 1; j >= 0; j--)
                L[i][j] = a[i] === b[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1])
        var keep = []                       // pairs [old index, new index]
        i = 0; j = 0
        while (i < n && j < m) {
            if (a[i] === b[j]) { keep.push([i, j]); i++; j++ }
            else if (L[i + 1][j] >= L[i][j + 1]) i++
            else j++
        }
        // drop the old words that aren't kept (from the end, so indexes hold)
        var kept = {}
        for (var k = 0; k < keep.length; k++) kept[keep[k][0]] = true
        for (i = n - 1; i >= 0; i--) if (!kept[i]) wm.remove(i)
        // now the model is exactly the kept words, in order; add the new ones where they belong
        var isKeptNew = {}
        for (k = 0; k < keep.length; k++) isKeptNew[keep[k][1]] = true
        for (j = 0; j < m; j++) {
            if (isKeptNew[j]) wm.setProperty(j, "w", ws[j])          // same word, maybe new punctuation/case
            else wm.insert(j, { w: ws[j] })
        }
        words = ws
        Qt.callLater(layout)
    }
    function clear() { wm.clear(); words = []; usedHeight = 0 }

    function layout() {
        var space = size * 0.24, lh = size * lineHeight
        var x = 0, line = 0, items = [], lineW = [0], fresh = 0
        for (var i = 0; i < rep.count; i++) {
            var d = rep.itemAt(i); if (!d) { Qt.callLater(layout); return }
            var w = d.implicitWidth
            if (x > 0 && x + w > wf.width) { x = 0; line++; lineW.push(0) }
            items.push({ d: d, x: x, line: line, y: line * lh + (lh - d.implicitHeight) / 2 })
            lineW[line] = x + w
            x += w + space
        }
        // line offsets first (they glide), then each word to its spot on its line
        var offs = [0, 0, 0, 0, 0]
        for (var l = 0; l < lineW.length && l < 5; l++) offs[l] = centered ? (wf.width - lineW[l]) / 2 : 0
        var moving = false
        for (var j = 0; j < items.length; j++) if (items[j].d.born && (items[j].d.lx !== items[j].x || items[j].d.line !== items[j].line)) moving = true
        off0 = offs[0]; off1 = offs[1]; off2 = offs[2]; off3 = offs[3]; off4 = offs[4]
        for (j = 0; j < items.length; j++) {
            var it = items[j]
            if (!it.d.born) { it.d.enter(it.x, it.line, it.y, (moving ? 160 : 0) + fresh * 70); fresh++ }
            else it.d.move(it.x, it.line, it.y)
        }
        usedHeight = rep.count ? (line + 1) * lh : 0
    }
    onSizeChanged: Qt.callLater(layout)
    onWidthChanged: Qt.callLater(layout)

    ListModel { id: wm }
    Repeater {
        id: rep
        model: wm
        delegate: Text {
            id: d
            text: model.w
            color: wf.color
            font.family: Theme.face; font.pixelSize: wf.size; font.weight: wf.weight
            renderType: Text.QtRendering
            opacity: 0
            property bool born: false
            property real lx: 0                  // x on its line
            property int line: 0
            property real rise: 0
            x: lx + wf.off(line)
            y: ty + rise
            property real ty: 0
            Behavior on lx { enabled: d.born; NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
            Behavior on ty { enabled: d.born; NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide } }
            function enter(px, l, py, delay) {
                lx = px; line = l; ty = py; rise = 12 * 2.4; opacity = 0
                born = true
                inA.delay = Math.max(0, delay); inA.restart()
            }
            function move(px, l, py) {
                if (l !== line) {
                    // changing lines: fade across rather than fly diagonally through other words
                    lineA.px = px; lineA.l = l; lineA.py = py; lineA.restart()
                } else { lx = px; ty = py }
            }
            SequentialAnimation {
                id: inA
                property int delay: 0
                PauseAnimation { duration: inA.delay }
                ParallelAnimation {
                    NumberAnimation { target: d; property: "rise"; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide }
                    NumberAnimation { target: d; property: "opacity"; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: wf.glide }
                }
            }
            SequentialAnimation {
                id: lineA
                property real px: 0; property int l: 0; property real py: 0
                NumberAnimation { target: d; property: "opacity"; to: 0; duration: 140 }
                ScriptAction { script: { d.born = false; d.lx = lineA.px; d.line = lineA.l; d.ty = lineA.py; d.born = true } }
                NumberAnimation { target: d; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            }
        }
    }
    Text {
        visible: wf.placeholder !== "" && rep.count === 0
        width: wf.width
        horizontalAlignment: wf.centered ? Text.AlignHCenter : Text.AlignLeft
        text: wf.placeholder
        color: Qt.rgba(1, 240 / 255, 225 / 255, 0.32)
        font.family: Theme.face; font.pixelSize: wf.size; font.weight: wf.weight
        renderType: Text.QtRendering
    }
}
