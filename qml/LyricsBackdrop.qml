import QtQuick

// The song's words, poster-style (Aviral's pick, 23 Nov: "A", from the Second Society reference): the line being sung
// set in the serif, centred, with the song's name small above it and the next line faint below — and behind it, the
// line's hook (its last words, room/lyrics.py) written huge in brush script, running off the edges, each word written
// in turn as the line starts. Music standby uses the whole screen; the player and Home lay it out on the cover (674
// across: Home's is the same, smaller).
//
// The script is Afelanity when it's installed (a licensed font: kept in ~/.config/room/fonts beside Kasero, never in
// the repo), Kristi (free, ships with Room) otherwise. Its colour is the cover's own, made strong.
//
// Only timed lyrics; between sung lines the script fades and the line waits, dimmed. Only the line being sung and the
// one just sung are drawn.
Item {
    id: lb
    property var lines: []
    property real pos: 0                       // the song's place, seconds
    property color ink: "#ff6a5c"              // the script's colour
    property string label: ""                  // "FIDELIO · ANSH"
    property bool big: true                    // the whole screen (standby), or a cover

    readonly property string script: Qt.fontFamilies().indexOf("Afelanity") >= 0 ? "Afelanity" : "Kristi"
    readonly property real scriptK: script === "Afelanity" ? 0.78 : 1

    // ---------------------------------------------------------------- where the song is
    readonly property int idx: {
        var i = -1
        for (var k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.15) i = k; else break }
        return i
    }
    readonly property bool active: idx >= 0 && pos < lines[idx].end + 0.3

    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    // the same "random" every time for a line (where its script words go)
    function jit(n) { var x = Math.sin(n * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x) }

    // the song's name, small, over the line
    Mono {
        x: 0; width: parent.width; horizontalAlignment: Text.AlignHCenter
        y: lb.big ? 250 : 150
        size: 13; color: Qt.rgba(1, 1, 1, 0.8); text: lb.label
        opacity: lb.idx >= 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }

    Repeater {
        model: lb.lines
        Item {
            id: ln
            anchors.fill: parent
            readonly property int li: index            // (the line's number, for the script words inside)
            readonly property bool near: index === lb.idx || index === lb.idx - 1
            readonly property bool on: index === lb.idx
            readonly property string hook: modelData.hook || ""
            readonly property var words: hook !== "" ? hook.split(" ") : []
            visible: near && opacity > 0.01
            // shown: the line being sung (a little dimmer in a gap after it); the one before fading away
            opacity: on ? (lb.active ? 1 : 0.55) : 0
            Behavior on opacity { NumberAnimation { duration: ln.on ? 500 : 420; easing.type: Easing.OutCubic } }
            // coming in: the line rises into place as its script is written, a word at a time
            property real rise: 0
            onOnChanged: if (on) { rise = 0; w0 = 0; w1 = 0; come.restart() } else come.stop()
            Component.onCompleted: if (on) rise = 1
            SequentialAnimation {
                id: come
                ParallelAnimation {
                    NumberAnimation { target: ln; property: "rise"; to: 1; duration: 650; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 150 }
                        NumberAnimation { target: ln; property: "w0"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 600 }
                        NumberAnimation { target: ln; property: "w1"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
            }
            property real w0: 1
            property real w1: 1

            // the script, behind
            Repeater {
                model: ln.near ? ln.words : []
                Item {
                    id: sw
                    readonly property real seed: ln.li * 31 + index * 7
                    readonly property bool two: ln.words.length > 1
                    readonly property real sz: (lb.big ? (two ? 380 : 470) : (two ? 230 : 290)) * lb.scriptK
                    readonly property real jx: (lb.jit(seed) - 0.5) * (lb.big ? 80 : 40)
                    readonly property real jy: (lb.jit(seed + 1) - 0.5) * (lb.big ? 30 : 20)
                    readonly property real tilt: -8 + (lb.jit(seed + 2) - 0.5) * 4
                    readonly property real pad: sz * 0.3
                    x: (lb.big ? (two ? (index ? 560 : -30) : 260) : (two ? (index ? 250 : -20) : 90)) + jx - pad
                    y: (lb.big ? (two ? (index ? 300 : 90) : 160) : (two ? (index ? 300 : 60) : 170)) + jy - pad
                    width: st.implicitWidth + 2 * pad; height: st.implicitHeight + 2 * pad
                    rotation: tilt; transformOrigin: Item.Center
                    readonly property real u: index === 0 ? ln.w0 : ln.w1
                    visible: u > 0
                    layer.enabled: u < 1; layer.smooth: true
                    layer.effect: ShaderEffect {
                        property real u: sw.u; property real soft: 0.14; property real lean: 0.08; property real flip: 0
                        fragmentShader: shaderDir + "wipe.frag.qsb"
                    }
                    Text {
                        id: st
                        x: sw.pad; y: sw.pad
                        text: modelData
                        font.family: lb.script; font.pixelSize: sw.sz
                        color: lb.ink; opacity: 0.92
                        style: lb.script === "Kristi" ? Text.Outline : Text.Normal; styleColor: lb.ink
                        renderType: Text.QtRendering
                    }
                }
            }
            // the line, over it, its hook in italic
            Text {
                id: lt
                readonly property int at: ln.hook !== "" ? modelData.text.lastIndexOf(ln.hook) : -1
                x: lb.big ? 214 : 47; width: lb.big ? 940 : 580
                y: (lb.big ? 286 : 184) + (1 - ln.rise) * 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                text: at < 0 ? lb.esc(modelData.text)
                             : lb.esc(modelData.text.slice(0, at)) + "<i>" + lb.esc(ln.hook) + "</i>" + lb.esc(modelData.text.slice(at + ln.hook.length))
                font.family: "Instrument Serif"; font.pixelSize: lb.big ? 62 : 46
                lineHeight: 1.02
                color: "white"; renderType: Text.QtRendering
                opacity: ln.rise
            }
            // the next line, faint, under it
            Text {
                x: 0; width: parent.width; horizontalAlignment: Text.AlignHCenter
                y: lt.y + lt.height + (lb.big ? 30 : 24)
                text: index + 1 < lb.lines.length ? lb.lines[index + 1].text : ""
                font.family: "Instrument Serif"; font.pixelSize: lb.big ? 24 : 22
                color: Qt.rgba(1, 1, 1, 0.42); renderType: Text.QtRendering
                elide: Text.ElideRight
                opacity: ln.rise
            }
        }
    }
}
