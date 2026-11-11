import QtQuick

// Standby with music: the song's words drifting by, far bigger than the screen, with motion blur (room-motion.html —
// the current panel's drifting words, kept): the artist enormous and faint (bold, 380 px, drifting right, blurred
// 16 px sideways), the title in the serif (230 px, drifting left, a touch of blur, a blurred ghost trailing it), the
// album small in mono (58 px, drifting right). All lowercase; each row loops, one word crossing at a time.
//
// Light on the Surface: each word is drawn and blurred once (when the song changes) into a picture, and only that
// picture is moved after that — 30 times a second.
Item {
    id: w
    width: 1368; height: 912
    property string artist: ""
    property string title: ""
    property string album: ""
    property bool running: true

    property real t: 0
    property real acc: 0
    signal ticked()                  // each step (the background keeps time with it on music standby)
    FrameAnimation {                 // 30 a second (every other frame): smooth for slow movement, half the drawing
        running: w.running && w.visible
        onTriggered: {
            w.acc += Math.min(0.1, frameTime)
            if (currentFrame % 2) return
            w.t += w.acc; w.acc = 0
            w.ticked()
        }
    }

    component Row: Item {
        id: r
        property string text: ""
        property real size: 200
        property string family: Theme.face
        property int weight: Font.Normal
        property bool caps: false
        property color colour: "white"
        property real sigma: 0                // the blur, stage px (sideways)
        property real speed: 20               // stage px a second; negative drifts right
        property real start: 0
        property real offset: 0               // (a ghost sits this far behind)
        property real quality: 1              // the picture's resolution (blurred rows don't need full)
        width: w.width; height: word.height
        readonly property real pad: Math.ceil(3 * sigma) + 2
        readonly property real gap: Math.max(size * 0.6, 750)
        readonly property real period: label.implicitWidth + gap
        readonly property real res: Math.max(1, Theme.px) * quality

        // the word, padded so the blur has room to spread
        Item {
            id: word
            width: label.implicitWidth + 2 * r.pad; height: label.implicitHeight
            Text {
                id: label
                x: r.pad
                text: r.text
                color: r.colour
                font.family: r.family; font.pixelSize: r.size; font.weight: r.weight
                font.letterSpacing: r.caps ? r.size * 0.1 : -r.size * 0.03
                font.capitalization: r.caps ? Font.AllUppercase : Font.MixedCase
                renderType: Text.QtRendering
            }
        }
        readonly property size tex: Qt.size(Math.max(1, Math.ceil(word.width * r.res)), Math.max(1, Math.ceil(word.height * r.res)))
        ShaderEffectSource {           // the word as a picture
            id: flat
            sourceItem: word; hideSource: true; visible: false; smooth: true
            textureSize: r.tex
        }
        ShaderEffect {                 // blurred sideways (only when the word changes: its picture is kept below)
            id: blurred
            width: word.width; height: word.height
            property variant source: flat
            property real sigma: width > 1 ? r.sigma / width : 0
            fragmentShader: shaderDir + "hblur.frag.qsb"
        }
        ShaderEffectSource {           // …kept as a picture; the copies below only move it
            id: baked
            sourceItem: r.sigma > 0 ? blurred : word; hideSource: true; visible: false; smooth: true
            textureSize: r.tex
        }
        readonly property real x0: r.period > 0 ? -(((w.t * r.speed + r.start) % r.period) + r.period) % r.period : 0
        Repeater {
            model: r.text === "" ? 0 : Math.ceil(w.width / Math.max(1, r.period)) + 1
            ShaderEffect {
                property variant source: baked
                x: r.x0 + index * r.period - r.pad + r.offset
                width: word.width; height: word.height
            }
        }
    }

    Row {        // the artist: enormous, faint, drifting right behind everything
        y: 40; text: w.artist; size: 380; weight: Font.Bold; speed: -14; start: 200
        colour: Qt.rgba(1, 246 / 255, 236 / 255, 0.09); sigma: 16; quality: 0.5
    }
    Row {        // the title: big and bright, drifting left
        y: 300; text: w.title; size: 230; family: Theme.serif; speed: 26
        colour: Qt.rgba(1, 246 / 255, 236 / 255, 0.92); sigma: 2.5
    }
    Row {        // the title's ghost: blurred, trailing it
        y: 300; text: w.title; size: 230; family: Theme.serif; speed: 26; offset: 18
        colour: Qt.rgba(1, 246 / 255, 236 / 255, 0.92); sigma: 16; quality: 0.5; opacity: 0.28
    }
    Row {        // the album: small, in mono, drifting right a little faster
        y: 560; text: w.album; size: 58; family: Theme.mono; caps: true; speed: -36; start: 400
        colour: Qt.rgba(1, 246 / 255, 236 / 255, 0.4); sigma: 5; quality: 0.75
    }
}
