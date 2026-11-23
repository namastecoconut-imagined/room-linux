import QtQuick
import QtQuick.Shapes

// The song's words as a lyric sheet (music standby, the player's cover, Home's cover): its lines set in the serif,
// the one being sung bright, the sheet gliding up a line as the song moves on — and that line's last words (its
// hook, room/lyrics.py) written over in script, in a colour from the cover, with a pen flourish under them: the
// pen passes along the words and they become handwriting (the line's own last words give way exactly where the pen
// has been). Aviral's references: a typeset lyric sheet with the title scrawled over it; "enjoy every moment" in
// brush script, underlined.
//
// Two layouts. Standby: one line each, the sung one bigger (a long one a little smaller, to fit). The player and
// Home (`wrap`): every line the same, bigger size, a long one running onto a second line; the hook's words set a
// little bigger in every line, so the room for the script is always there and nothing moves when it's written.
//
// Only timed lyrics (each line's start, from LRCLIB) — nothing here guesses at timing. Between sung lines (a gap in
// the singing) the hook goes and the sheet waits. Lines are broken here (not by Qt) so the hook's place is known.
Item {
    id: ly
    property var lines: []
    property real pos: 0                       // the song's place, seconds
    property color accent: "#ffc499"
    // the sheet: its left edge, where the sung line sits (its middle; wrap: its top), the type, the line spacing
    // (one line to the next; wrap: the gap between lines), and the sung line's scale (one-line layout)
    property real sheetX: 200
    property real curY: 300
    property real fs: 34
    property real lh: 78
    property real cur: 1.75
    property bool wrap: false
    property real gap: 14
    // how many lines show past the sung one: to come (fainter each), and already sung
    property int ahead: 3
    property int behind: 1
    property real margin: 36                   // kept clear on the right
    readonly property real avail: width - sheetX - margin
    readonly property real hookK: wrap ? 1.22 : 1                // the hook's words in the serif, against the line
    readonly property real scriptK: wrap ? 1.95 : 1.9            // the script, against the line (both: their size)

    FontMetrics { id: fmS; font.family: "Instrument Serif"; font.pixelSize: ly.fs }
    FontMetrics { id: fmB; font.family: "Instrument Serif"; font.pixelSize: Math.round(ly.fs * ly.hookK) }
    readonly property real lineStep: wrap ? Math.max(fmS.height, fmB.height) * 1.02 : fmS.height
    readonly property real lineAsc: wrap ? Math.max(fmS.ascent, fmB.ascent) : fmS.ascent

    // a line, broken to fit (wrap) → { lines: the words before the hook, line by line; lastW: the last one's width;
    // hookNew: the hook starts a line of its own }
    function layout(head, hook) {
        var words = head.trim().split(/\s+/).filter(function (w) { return w !== "" })
        var out = [], line = "", sp = fmS.advanceWidth(" ")
        words.forEach(function (w) {
            var t = line === "" ? w : line + " " + w
            if (wrap && line !== "" && fmS.advanceWidth(t) > avail) { out.push(line); line = w } else line = t
        })
        if (line !== "" || !out.length) out.push(line)
        var lastW = fmS.advanceWidth(out[out.length - 1])
        var hw = hook ? fmB.advanceWidth(hook) : 0
        var hookNew = wrap && hook !== "" && lastW > 0 && lastW + sp + hw > avail
        return { lines: out, lastW: lastW > 0 ? lastW + sp : 0, hookNew: hookNew }
    }

    // ---------------------------------------------------------------- where the song is
    readonly property int idx: {
        var i = -1
        for (var k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.15) i = k; else break }
        return i
    }
    // singing now (not in a gap after the line)
    readonly property bool active: idx >= 0 && pos < lines[idx].end + 0.3
    // the sheet's place (a line index), gliding to the line being sung (before the first: it waits below)
    property real gl: -1
    readonly property real glTo: idx
    onGlToChanged: { glAnim.to = glTo; glAnim.restart() }
    NumberAnimation { id: glAnim; target: ly; property: "gl"; duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    Component.onCompleted: gl = glTo
    // (wrap) where line x starts, down the sheet from line 0 (x may be between lines while it glides)
    function offAt(x) {
        var k = Math.floor(x), o = 0
        if (k < 0) return x * (lineStep + gap)
        for (var j = 0; j < k && j < rows.count; j++) { var it = rows.itemAt(j); o += (it ? it.height : lineStep) + gap }
        var c = k < rows.count ? rows.itemAt(k) : null
        return o + (x - k) * ((c ? c.height : lineStep) + gap)
    }

    // ---------------------------------------------------------------- the sheet
    Repeater {
        id: rows
        model: ly.lines
        Item {
            id: row
            readonly property real d: index - ly.gl
            readonly property real ad: Math.abs(d)
            readonly property string full: modelData.text
            readonly property string hk: modelData.hook || ""
            readonly property int hookAt: hk !== "" ? full.lastIndexOf(hk) : -1
            readonly property var lay: ly.layout(hookAt >= 0 ? full.slice(0, hookAt) : full, hookAt >= 0 ? hk : "")
            readonly property int nLines: lay.lines.length + (lay.hookNew ? 1 : 0)
            // where the hook's words sit (their start, on their baseline), in the line's own terms
            readonly property real hookX: lay.hookNew ? 0 : lay.lastW
            readonly property real hookBase: (nLines - 1) * ly.lineStep + ly.lineAsc
            readonly property bool writing: index === ly.hookIdx
            visible: ad < ly.ahead + 1.2 && d > -(ly.behind + 1)
            x: ly.sheetX
            height: nLines * ly.lineStep
            width: lay.lastW + (hookAt >= 0 ? hookSerif.implicitWidth : 0)
            y: ly.wrap ? ly.curY + ly.offAt(index) - ly.offAt(ly.gl) : ly.curY + d * ly.lh - height / 2
            // one line: the sung one bigger (a long one less, to fit with its hook in script)
            readonly property real fullW: fmS.advanceWidth(full)
            readonly property real base: ly.wrap ? 1 : Math.min(1, ly.avail / Math.max(1, fullW))
            readonly property real big: ly.wrap ? 1 : Math.min(ly.cur, ly.avail / Math.max(1, fullW * 1.12))
            scale: base + (big - base) * Math.max(0, 1 - ad)
            transformOrigin: Item.Left
            // a point in the line → the sheet (the line's scale is about its left middle)
            function toSheet(px, py) { return Qt.point(x + px * scale, y + height / 2 + (py - height / 2) * scale) }
            // above: what's been sung, fading out (the clock's up there on standby); below: what's to come, fainter each
            opacity: (d < 0 ? (ad < 1 ? 1 - 0.62 * ad : Math.max(0, 0.38 * (ly.behind + 1 - ad) / ly.behind))
                            : (ad < 1 ? 1 - 0.62 * ad : ad < ly.ahead ? 0.38 - 0.24 / Math.max(1, ly.ahead - 1) * (ad - 1)
                                                    : Math.max(0, 0.14 * (ly.ahead + 1 - ad))))
                     * (index === ly.idx && !ly.active ? 0.6 : 1)
            Behavior on opacity { NumberAnimation { duration: 400 } }
            Repeater {
                model: row.lay.lines
                Text {
                    y: index * ly.lineStep + ly.lineAsc - fmS.ascent
                    text: modelData
                    font.family: "Instrument Serif"; font.pixelSize: ly.fs
                    color: "white"; renderType: Text.QtRendering
                }
            }
            // the hook's words in the serif: the pen passes over them as the script is written, and they're gone
            Text {
                id: hookSerif
                visible: row.hookAt >= 0 && opacity > 0.01
                x: row.hookX; y: row.hookBase - fmB.ascent
                text: row.hk
                font.family: "Instrument Serif"; font.pixelSize: Math.round(ly.fs * ly.hookK)
                color: "white"; renderType: Text.QtRendering
                // (written: gone; and back as the script fades when the next line comes)
                opacity: row.writing && ly.wu >= 1 ? 1 - ly.ho : 1
                layer.enabled: row.writing && ly.wu > 0 && ly.wu < 1; layer.smooth: true
                layer.effect: ShaderEffect {
                    property real u: ly.wu; property real soft: 0.14; property real lean: 0.08; property real flip: 1
                    fragmentShader: shaderDir + "wipe.frag.qsb"
                }
            }
        }
    }

    // ---------------------------------------------------------------- the hook, written over the sung line's last words
    property int hookIdx: -1                   // the line whose hook is up
    property real wu: 0                        // written: 0 → 1
    property real fu: 0                        // its flourish drawn: 0 → 1
    property real ho: 0                        // shown
    readonly property string hookText: hookIdx >= 0 && hookIdx < lines.length ? (lines[hookIdx].hook || "") : ""
    readonly property bool wantHook: active && (lines[idx].hook || "") !== ""
    onIdxChanged: rewrite()
    onWantHookChanged: rewrite()
    onLinesChanged: { hookIdx = -1; ho = 0; wu = 0; rewrite() }
    function rewrite() {
        if (wantHook && hookIdx === idx && ho > 0) return
        write.stop()
        write.out = ho > 0.01
        write.start()
    }
    SequentialAnimation {
        id: write
        property bool out: false
        // the old one fades (quickly) and its line's own words come back; then the new one is written: the words, then
        // the flourish under them
        NumberAnimation { target: ly; property: "ho"; to: 0; duration: write.out ? 320 : 0 }
        ScriptAction { script: { ly.wu = 0; ly.fu = 0; ly.hookIdx = ly.wantHook ? ly.idx : -1; ly.ho = ly.wantHook ? 1 : 0 } }
        PauseAnimation { duration: ly.wantHook ? 420 : 0 }          // (the sheet's mostly settled on the new line)
        NumberAnimation { target: ly; property: "wu"; to: 1; duration: ly.wantHook ? 1100 : 0; easing.type: Easing.InOutSine }
        NumberAnimation { target: ly; property: "fu"; to: 1; duration: ly.wantHook ? 450 : 0; easing.type: Easing.OutCubic }
    }

    readonly property Item hookRow: hookIdx >= 0 && hookIdx < rows.count ? rows.itemAt(hookIdx) : null
    readonly property real hookPx: fs * scriptK * (hookRow ? hookRow.scale : 1)
    FontMetrics { id: sfm; font.family: "Mrs Saint Delafield"; font.pixelSize: ly.hookPx }
    Item {
        id: hook
        visible: ly.hookRow !== null && ly.ho > 0.01 && ly.hookText !== "" && ly.wu > 0
        opacity: ly.ho
        readonly property point at: ly.hookRow ? ly.hookRow.toSheet(ly.hookRow.hookX, ly.hookRow.hookBase) : Qt.point(0, 0)
        readonly property real pad: ly.hookPx * 0.35
        // the script's baseline on the line's
        x: at.x - ly.fs * 0.04 - pad; y: at.y - sfm.ascent - pad
        width: hw.implicitWidth + 2 * pad + ly.hookPx * 0.1; height: sfm.height + 2 * pad
        transform: Rotation { origin.x: hook.pad; origin.y: hook.pad + sfm.ascent; angle: -3 }
        // the words
        Item {
            anchors.fill: parent
            layer.enabled: ly.wu < 1; layer.smooth: true
            layer.effect: ShaderEffect {
                property real u: ly.wu; property real soft: 0.14; property real lean: 0.08; property real flip: 0
                fragmentShader: shaderDir + "wipe.frag.qsb"
            }
            Text {
                id: hw
                x: hook.pad; y: hook.pad
                text: ly.hookText
                font.family: "Mrs Saint Delafield"; font.pixelSize: ly.hookPx
                color: ly.accent
                renderType: Text.QtRendering
            }
        }
        // the flourish under them
        Item {
            anchors.fill: parent
            visible: ly.fu > 0
            layer.enabled: ly.fu < 1; layer.smooth: true
            layer.effect: ShaderEffect {
                property real u: ly.fu; property real soft: 0.1; property real lean: 0; property real flip: 0
                fragmentShader: shaderDir + "wipe.frag.qsb"
            }
            Shape {
                id: fl
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real x0: hook.pad + hw.implicitWidth * 0.1
                readonly property real x1: hook.pad + hw.implicitWidth + ly.hookPx * 0.05
                readonly property real yb: hook.pad + sfm.ascent + ly.hookPx * 0.16
                readonly property real k: ly.hookPx * 0.22
                ShapePath {
                    strokeColor: ly.accent; strokeWidth: Math.max(1.6, ly.hookPx / 52); fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: fl.x0; startY: fl.yb + fl.k * 0.2
                    PathCubic {
                        x: fl.x1; y: fl.yb - fl.k * 0.25
                        control1X: fl.x0 + (fl.x1 - fl.x0) * 0.3; control1Y: fl.yb - fl.k * 0.35
                        control2X: fl.x0 + (fl.x1 - fl.x0) * 0.7; control2Y: fl.yb + fl.k * 0.15
                    }
                }
            }
        }
    }
}
