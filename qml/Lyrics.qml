import QtQuick
import QtQuick.Shapes

// The song's words as a lyric sheet (music standby, the player's cover, Home's cover): its lines set small and quiet
// in the serif, the one being sung bigger and bright, the sheet gliding up a line as the song moves on — and the
// line's last words (its hook, room/lyrics.py) written across it big in script, in a colour from the cover, with a
// pen flourish under them. Aviral's references: a typeset lyric sheet with the title scrawled over it; "enjoy every
// moment" in red brush script, underlined.
//
// Only timed lyrics (each line's start, from LRCLIB) — nothing here guesses at timing. Between sung lines (a gap in
// the singing) the hook goes and the sheet waits. Drawn as plain text; the writing-on is one small shader
// (wipe.frag) on the hook while it's being written, nothing after.
Item {
    id: ly
    property var lines: []
    property real pos: 0                       // the song's place, seconds
    property color accent: "#ffc499"
    // the sheet: its left edge, where the sung line's middle sits, its type and line spacing; the sung line's scale;
    // the hook's size
    property real sheetX: 200
    property real curY: 300
    property real fs: 34
    property real lh: 78
    property real cur: 1.75
    property real scriptPx: 300

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

    // ---------------------------------------------------------------- the sheet
    Repeater {
        model: ly.lines
        Text {
            readonly property real d: index - ly.gl
            readonly property real ad: Math.abs(d)
            visible: ad < 4.2 && (d > -2 || ad < 2)
            x: ly.sheetX
            y: ly.curY + d * ly.lh - height / 2
            transformOrigin: Item.Left
            scale: 1 + (ly.cur - 1) * Math.max(0, 1 - ad)
            text: modelData.text
            font.family: "Instrument Serif"; font.pixelSize: ly.fs
            color: "white"
            renderType: Text.QtRendering
            // above: the line just sung, fading out by two lines up (the clock's up there on standby); below: three
            // to come, fainter each
            opacity: (d < 0 ? (ad < 1 ? 1 - 0.62 * ad : Math.max(0, 0.38 * (2 - ad)))
                            : (ad < 1 ? 1 - 0.62 * ad : ad < 3 ? 0.38 - 0.12 * (ad - 1) : Math.max(0, 0.14 * (4 - ad))))
                     * (index === ly.idx && !ly.active ? 0.6 : 1)
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }

    // ---------------------------------------------------------------- the hook, written across the sung line
    property int hookIdx: -1                   // the line whose hook is up
    property real wu: 0                        // written: 0 → 1
    property real fu: 0                        // its flourish drawn: 0 → 1
    property real ho: 0                        // shown
    readonly property string hookText: hookIdx >= 0 && hookIdx < lines.length ? (lines[hookIdx].hook || "") : ""
    readonly property bool wantHook: active && (lines[idx].hook || "") !== ""
    onIdxChanged: rewrite()
    onWantHookChanged: rewrite()
    onLinesChanged: { hookIdx = -1; ho = 0; rewrite() }
    function rewrite() {
        if (wantHook && hookIdx === idx && ho > 0) return
        write.stop()
        if (ho > 0.01) { write.out = true; write.start() } else { write.out = false; write.start() }
    }
    SequentialAnimation {
        id: write
        property bool out: false
        // the old one fades (quickly), then the new one is written: the words, then the flourish under them
        NumberAnimation { target: ly; property: "ho"; to: 0; duration: write.out ? 260 : 0 }
        ScriptAction { script: { ly.wu = 0; ly.fu = 0; ly.hookIdx = ly.wantHook ? ly.idx : -1; ly.ho = ly.wantHook ? 1 : 0 } }
        PauseAnimation { duration: ly.wantHook ? 180 : 0 }
        NumberAnimation { target: ly; property: "wu"; to: 1; duration: ly.wantHook ? 1100 : 0; easing.type: Easing.OutCubic }
        NumberAnimation { target: ly; property: "fu"; to: 1; duration: ly.wantHook ? 450 : 0; easing.type: Easing.OutCubic }
    }

    // where the hook's words are in the sung line (the line's scale included)
    TextMetrics { id: pre; font.family: "Instrument Serif"; font.pixelSize: ly.fs
                  text: ly.hookIdx >= 0 && ly.hookIdx < ly.lines.length ? ly.lines[ly.hookIdx].text.slice(0, ly.lines[ly.hookIdx].text.lastIndexOf(ly.hookText)) : "" }
    FontMetrics { id: sfm; font.family: "Mrs Saint Delafield"; font.pixelSize: ly.scriptPx }
    Item {
        id: hook
        visible: ly.ho > 0.01 && ly.hookText !== ""
        opacity: ly.ho
        readonly property real pad: ly.scriptPx * 0.35
        // its box: like a web page's line-height 1 (the design), the hook's left a little before the words it's on
        // (kept on the screen: a long hook late in a long line moves left, over the line still)
        readonly property real boxX: Math.max(ly.sheetX - ly.scriptPx * 0.3,
                                              Math.min(ly.sheetX + pre.advanceWidth * ly.cur - ly.scriptPx * 0.3, ly.width - 24 - hw.implicitWidth - ly.scriptPx * 0.1))
        readonly property real boxY: ly.curY - ly.fs * ly.cur * 0.6 - ly.scriptPx * 0.42
        x: boxX - pad; y: boxY - pad
        width: hw.implicitWidth + 2 * pad + ly.scriptPx * 0.1; height: ly.scriptPx + 2 * pad
        transform: Rotation { origin.x: hook.pad; origin.y: hook.pad + ly.scriptPx * 0.7; angle: -7 }
        // the words
        Item {
            anchors.fill: parent
            layer.enabled: ly.wu < 1; layer.smooth: true
            layer.effect: ShaderEffect {
                property real u: ly.wu
                property real soft: 0.14
                property real lean: 0.08
                fragmentShader: shaderDir + "wipe.frag.qsb"
            }
            Text {
                id: hw
                x: hook.pad; y: hook.pad + (ly.scriptPx - sfm.height) / 2
                text: ly.hookText
                font.family: "Mrs Saint Delafield"; font.pixelSize: ly.scriptPx
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
                property real u: ly.fu
                property real soft: 0.1
                property real lean: 0
                fragmentShader: shaderDir + "wipe.frag.qsb"
            }
            Shape {
                id: fl
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real x0: hook.pad + hw.implicitWidth * 0.1
                readonly property real x1: hook.pad + hw.implicitWidth + ly.scriptPx * 0.05
                readonly property real yb: hook.pad + ly.scriptPx * 0.92
                readonly property real k: ly.scriptPx * 0.22
                ShapePath {
                    strokeColor: ly.accent; strokeWidth: Math.max(1.6, ly.scriptPx / 52); fillColor: "transparent"
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
