import QtQuick
import "pixeldata.js" as Pix

// The Pixel display screen: what the 32 × 32 dot display on Bluetooth shows, chosen from here (the link itself, and
// what's sent, is room/pixel — `pixel` here).
// Up top, to read (the touch screen doesn't answer between y 118 and 500): what's on the display now — its name big,
// the display itself drawn dot for dot — and its link. In the top bar: brightness and on / off. Below, what you
// touch: the kinds of picture (Clock · Art · Light) and the chosen kind's choices. Tapping a choice shows it on the
// display at once.
// The pictures are drawn here (pixeldata.js: the clock faces and art loops, dot by dot) and handed to `pixel` as
// frames. A clock face is a still, sent again each minute (each second with the seconds dot) for as long as it's
// showing — whatever screen Room is on, standby included; an art loop is 48 frames sent once, which the display then
// plays by itself. Effects, one colour and the Classic clock are the display's own.
Item {
    id: pv
    objectName: "pixelView"
    width: 1368; height: 912
    property bool shown: false
    property real now: Date.now() / 1000
    readonly property bool sheetOpen: false
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    property bool everShown: false
    onShownChanged: if (shown) everShown = true

    // ---------------------------------------------------------------- what `pixel` says, a value at a time (so a
    // change to one — the upload's progress, say — doesn't redraw every tile)
    readonly property var v: pixel.view
    readonly property string link: v.link
    readonly property bool linked: v.link === "on"
    readonly property bool on: v.on
    readonly property int bright: v.bright
    readonly property string mode: v.mode
    readonly property string label: v.label
    readonly property bool sending: v.sending
    readonly property int pct: Math.round(v.progress * 100)
    readonly property var pal: v.palette
    readonly property string face: v.sel.face
    readonly property int clockCol: v.sel.clockCol
    readonly property bool h24: v.sel.h24
    readonly property bool secs: v.sel.secs
    readonly property bool date: v.sel.date
    readonly property string art: v.sel.art
    readonly property int artCol: v.sel.artCol
    readonly property int pace: v.sel.pace
    readonly property int effect: v.sel.effect
    readonly property string effKey: v.sel.effCols.join(",")
    readonly property var effCols: effKey.split(",").map(Number)
    readonly property int solidCol: v.sel.solidCol
    function col(i) { return Pix.hex(pal[i % pal.length]) }
    function effectName(style) { for (var i = 0; i < Pix.EFFECTS.length; i++) if (Pix.EFFECTS[i][0] === style) return Pix.EFFECTS[i][1]; return "Effect" }

    readonly property var tabs: [["clock", "Clock"], ["art", "Art"], ["light", "Light"]]
    property string tab: { var m = /^pixel-([a-z]+)/.exec(startScreen); return m && (m[1] === "art" || m[1] === "light") ? m[1] : "clock" }
    property int artPage: 0

    // ---------------------------------------------------------------- the clock faces
    readonly property real minuteNow: Math.floor(now / 60) * 60           // (changes once a minute: the tiles follow it)
    readonly property var clockOpts: ({ col: col(clockCol), h24: h24, secs: secs })
    function faceFrame(id, at) {
        var d = new Date(at * 1000)
        return id === "classic" ? Pix.classicFrame(d, { col: col(clockCol), h24: h24, secs: date }) : Pix.clockFrame(id, d, clockOpts)
    }
    function showFace(id) {
        if (id === "classic") { pixel.classic(); return }
        pixel.still("clockface", Pix.FACE_NAMES[id], Pix.clockFrame(id, new Date(), clockOpts).buffer)
    }
    // a face that's showing is kept in time: drawn and sent again when the minute (or second) changes
    property real sentAt: -1
    function keepTime() {
        if (mode !== "clockface" || !linked || !on) return
        var t = Date.now() / 1000, key = secs ? Math.floor(t) : Math.floor(t / 60)
        if (key !== sentAt) { sentAt = key; showFace(face) }
    }
    Timer { interval: 1000; repeat: true; running: pv.mode === "clockface" && pv.linked && pv.on; onTriggered: pv.keepTime() }
    Connections { target: pixel; function onAgain() { pv.sentAt = -1; pv.keepTime() } }
    function clockAgain() { if (mode === "classic") pixel.classic(); else if (mode === "clockface") showFace(face) }

    // ---------------------------------------------------------------- the art loops: 48 frames, drawn a few at a
    // time between the screen's own frames (so a tap never holds the screen up), then sent as one loop
    property var job: null
    readonly property bool drawing: job !== null
    function showArt(id) { pixel.loopBegin(); job = { id: id, i: 0, col: col(artCol), pace: pace } }
    Timer {
        interval: 1; repeat: true; running: pv.job !== null
        onTriggered: {
            var j = pv.job
            for (var k = 0; k < 2 && j.i < Pix.ART_FRAMES; k++, j.i++) pixel.loopFrame(Pix.artFrame(j.id, j.i / Pix.ART_FRAMES, j.col).buffer)
            if (j.i >= Pix.ART_FRAMES) { pv.job = null; pixel.loopEnd("art", Pix.ART_NAMES[j.id], j.pace) }
        }
    }

    // ---------------------------------------------------------------- the display's picture, here: what's showing,
    // moving as it moves (only while this screen is up)
    property real artT: 0
    property int effF: 0
    Timer {
        interval: pv.mode === "art" ? Math.max(120, pv.pace) : 120; repeat: true
        running: pv.shown && pv.linked && pv.on && (pv.mode === "art" || pv.mode === "effect")
        onTriggered: { pv.artT = (pv.artT + 1 / Pix.ART_FRAMES) % 1; pv.effF = (pv.effF + 1) % 24 }
    }
    readonly property var picture: {
        if (!linked || !on) return Pix.blank()
        if (mode === "art") return Pix.artFrame(art, artT, col(artCol))
        if (mode === "effect") return Pix.effectFrame(effect, effCols.map(col), effF)
        if (mode === "colour") return Pix.solid(col(solidCol))
        if (mode === "classic") return faceFrame("classic", minuteNow)
        if (mode === "clockface") return faceFrame(face, secs ? now : minuteNow)
        return Pix.blank()
    }
    readonly property string title: !v.enabled ? "Switched off" : !linked ? (link === "connecting" ? "Connecting" : "Looking for it")
                                    : !on ? "Off" : label !== "" ? label : "Nothing yet"
    readonly property string kind: !v.enabled ? "\"pixel\": false in config.json" : !linked ? (v.name ? v.name + " isn't answering. Is it powered on?" : "No pixel display found yet. Is it powered on?")
                                   : !on ? "The display is dark. Turn on to bring it back." : drawing ? "Drawing the loop…"
                                   : sending && pct > 0 ? "Sending · " + pct + "%"
                                   : mode === "clockface" ? "Clock face · kept in time by Room" : mode === "classic" ? "Clock · the display's own"
                                   : mode === "art" ? "Art · loops on the display" : mode === "effect" ? "Effect · made by the display"
                                   : mode === "colour" ? "One colour" : "Tap something below to show it"

    function catSpots(sc, out) {
        var a = slab.mapToItem(sc, 0, 0)
        out.push({ id: "slab", x0: a.x + 30, x1: a.x + slab.width - 30, y: a.y })
        out.push({ id: "floor", x0: 330, x1: 1040, floor: true })
    }

    // ---------------------------------------------------------------- pieces
    component Rise: Item {
        id: rz
        property int order: 0
        opacity: pv.shown ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: pv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        transform: Translate {
            y: pv.shown ? 0 : 14
            Behavior on y { SequentialAnimation { PauseAnimation { duration: pv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        }
    }
    // the display, dot for dot: a black slab, each LED a dot with a little light round it
    component Slab: Item {
        id: sl
        property var px: null
        property real k: 1
        onPxChanged: cv.requestPaint()
        onKChanged: cv.requestPaint()
        Rectangle { anchors.fill: parent; radius: width * 0.085; color: "#060505"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12) }
        Canvas {
            id: cv
            anchors.fill: parent; anchors.margins: parent.width * 0.075
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                var data = sl.px
                if (!data) data = Pix.blank()
                var cell = width / 32, r = cell * 0.4, x, y, i, R, G, B
                for (y = 0; y < 32; y++) for (x = 0; x < 32; x++) {            // the light each lit dot throws
                    i = (y * 32 + x) * 4; R = data[i] * sl.k; G = data[i + 1] * sl.k; B = data[i + 2] * sl.k
                    if (R + G + B <= 24) continue
                    ctx.fillStyle = "rgba(" + Math.round(R) + "," + Math.round(G) + "," + Math.round(B) + ",0.13)"
                    ctx.beginPath(); ctx.arc(x * cell + cell / 2, y * cell + cell / 2, cell * 1.25, 0, 6.2832); ctx.fill()
                }
                for (y = 0; y < 32; y++) for (x = 0; x < 32; x++) {
                    i = (y * 32 + x) * 4; R = data[i] * sl.k; G = data[i + 1] * sl.k; B = data[i + 2] * sl.k
                    var lit = R + G + B > 24
                    ctx.fillStyle = lit ? "rgb(" + Math.round(R) + "," + Math.round(G) + "," + Math.round(B) + ")" : "#1c1b1b"
                    ctx.beginPath(); ctx.arc(x * cell + cell / 2, y * cell + cell / 2, lit ? r : r * 0.8, 0, 6.2832); ctx.fill()
                }
            }
        }
    }
    // one choice: its picture, small, and its name
    component Tile: Press {
        id: tl
        property var px: null
        property string label: ""
        property bool picked: false
        property real side: 108
        width: side; height: side + 28
        pressScale: 0.95
        onPxChanged: tc.requestPaint()
        Rectangle { width: tl.side; height: tl.side; radius: 16; color: "#060505"; border.width: tl.picked ? 2 : 1; border.color: tl.picked ? "#ffbe7a" : Qt.rgba(1, 1, 1, 0.16) }
        Canvas {
            id: tc
            x: 12; y: 12; width: tl.side - 24; height: tl.side - 24
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                var data = tl.px; if (!data) return
                var c = width / 32
                for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++) {
                    var i = (y * 32 + x) * 4; if (data[i] + data[i + 1] + data[i + 2] <= 12) continue
                    ctx.fillStyle = "rgb(" + data[i] + "," + data[i + 1] + "," + data[i + 2] + ")"
                    ctx.fillRect(x * c, y * c, c + 0.4, c + 0.4)
                }
            }
        }
        Mono { y: tl.side + 9; width: tl.side; horizontalAlignment: Text.AlignHCenter; size: 12; text: tl.label; color: tl.picked ? "white" : Theme.w62 }
    }
    component Swatches: Flow {
        id: sw
        property int pick: -1
        property var cols: Pix.palette
        signal chose(int i)
        spacing: 14
        Repeater {
            model: sw.cols
            Press {
                width: 40; height: 40; pressScale: 0.9
                onTapped: sw.chose(index)
                Rectangle { anchors.centerIn: parent; width: 52; height: 52; radius: 26; color: "transparent"; border.width: 2; border.color: "white"; visible: index === sw.pick }
                Rectangle { anchors.fill: parent; radius: 20; color: modelData; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
            }
        }
    }
    component Line: Item {
        property string label: ""
        default property alias ctl: slot.data
        width: parent ? parent.width : 0; height: 44
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: "white"; font.pixelSize: 22; font.family: Theme.face; renderType: Text.QtRendering }
        Row { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10 }
    }
    component Note: Mono { size: 12; color: Theme.w42; wrapMode: Text.WordWrap; lineHeight: 1.6; elide: Text.ElideNone }

    // ---------------------------------------------------------------- the top bar: brightness, on / off
    Row {
        anchors.right: parent.right; anchors.rightMargin: 36; y: 34; height: 44; spacing: 10
        opacity: pv.linked ? 1 : 0.35
        Chip { text: "−"; padX: 17; enabled: pv.linked; onTapped: pixel.brightness(pv.bright - 5) }
        Mono { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; rightPadding: 8; text: "Brightness " + pv.bright + "%" }
        Chip { text: "+"; padX: 17; enabled: pv.linked; onTapped: pixel.brightness(pv.bright + 5) }
        Item { width: 14; height: 1 }
        Chip { text: pv.on ? "Turn off" : "Turn on"; enabled: pv.linked; onTapped: pixel.power(!pv.on) }
    }

    // ---------------------------------------------------------------- to read: what's on the display
    Rise {
        order: 0
        x: 44; y: 126; width: 860; height: 340
        Row {
            spacing: 12
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 5; color: pv.linked ? "#ffbe7a" : "transparent"; border.width: pv.linked ? 0 : 1.5; border.color: Theme.w62 }
            Mono { text: pv.linked && pv.on ? "On the pixel display" : "Pixel display"; color: Theme.w62 }
        }
        Serif {
            y: 44; width: parent.width; text: pv.title
            font.pixelSize: 128; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 72
            color: pv.linked && pv.on ? "white" : Qt.rgba(1, 1, 1, 0.5)
        }
        Text { y: 44 + 128 + 26; width: parent.width; text: pv.kind; color: Theme.w62; font.pixelSize: 30; font.family: Theme.face; renderType: Text.QtRendering; elide: Text.ElideRight }
        Mono {
            y: 270; color: Theme.w62
            text: pv.linked ? (pv.v.name || "Display") + " · connected · brightness " + pv.bright + "%"
                : !pv.v.enabled ? "" : pv.link === "connecting" ? "Found it · connecting" : "Searching · tries again by itself"
        }
    }
    Rise {
        order: 1
        x: 1324 - 336; y: 136; width: 336; height: 336
        Slab { id: slab; anchors.fill: parent; px: pv.picture }
    }

    // ---------------------------------------------------------------- to touch: the kinds
    Rise {
        order: 2
        x: 44; y: 514; width: 1280; height: 44
        Row { spacing: 10; Repeater { model: pv.tabs; Chip { text: modelData[1]; warm: pv.tab === modelData[0]; onTapped: pv.tab = modelData[0] } } }
        Mono { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; color: Theme.w42; text: pv.linked ? "Tap one to show it" : "Choices are kept and shown once it's connected" }
    }

    // ---- Clock: fourteen faces, colour, 24-hour, seconds
    Rise {
        order: 3; visible: pv.tab === "clock"
        x: 44; y: 592; width: 1280; height: 290
        Loader {
            active: pv.everShown && pv.tab === "clock"
            sourceComponent: Grid {
                columns: 7; columnSpacing: 18; rowSpacing: 12
                Repeater {
                    model: Pix.FACES
                    Tile {
                        label: modelData[1]; px: pv.faceFrame(modelData[0], pv.minuteNow)
                        picked: (pv.mode === "clockface" || pv.mode === "classic") && pv.face === modelData[0]
                        onTapped: { pixel.choose("face", modelData[0]); pv.showFace(modelData[0]) }
                    }
                }
            }
        }
        Item {
            x: 936; width: 344; height: parent.height
            Mono { text: "Colour"; color: Theme.w62 }
            Swatches { y: 36; width: 344; cols: pv.pal; pick: pv.clockCol; onChose: (i) => { pixel.choose("clockCol", i); pv.clockAgain() } }
            Column {
                y: 166; width: parent.width; spacing: 6
                Line { label: "24-hour"; Toggle { on: pv.h24; onTapped: { pixel.choose("h24", !pv.h24); pv.clockAgain() } } }
                Line {
                    label: pv.face === "classic" ? "Show the date" : "Seconds dot"
                    Toggle {
                        on: pv.face === "classic" ? pv.date : pv.secs
                        onTapped: { if (pv.face === "classic") pixel.choose("date", !pv.date); else pixel.choose("secs", !pv.secs); pv.clockAgain() }
                    }
                }
            }
        }
    }

    // ---- Art: twenty-eight loops, fourteen at a time
    Rise {
        order: 3; visible: pv.tab === "art"
        x: 44; y: 592; width: 1280; height: 290
        Loader {
            active: pv.everShown && pv.tab === "art"
            sourceComponent: Grid {
                columns: 7; columnSpacing: 18; rowSpacing: 12
                Repeater {
                    model: Pix.ART.slice(pv.artPage * 14, pv.artPage * 14 + 14)
                    Tile {
                        label: modelData[1]; px: Pix.artFrame(modelData[0], 0.3, pv.col(pv.artCol))
                        picked: pv.mode === "art" && pv.art === modelData[0]
                        onTapped: { pixel.choose("art", modelData[0]); pv.showArt(modelData[0]) }
                    }
                }
            }
        }
        Item {
            x: 936; width: 344; height: parent.height
            Mono { text: "Colour"; color: Theme.w62 }
            Swatches { y: 36; width: 344; cols: pv.pal; pick: pv.artCol; onChose: (i) => { pixel.choose("artCol", i); if (pv.mode === "art") pv.showArt(pv.art) } }
            Mono { y: 158; text: "Pace"; color: Theme.w62 }
            Row {
                y: 190; spacing: 10
                Repeater {
                    model: [["Calm", 140], ["Steady", 85], ["Lively", 50]]
                    Chip { text: modelData[0]; warm: pv.pace === modelData[1]; onTapped: { pixel.choose("pace", modelData[1]); if (pv.mode === "art") pv.showArt(pv.art) } }
                }
            }
            Row {
                anchors.right: parent.right; y: 244; spacing: 10
                Mono { anchors.verticalCenter: parent.verticalCenter; rightPadding: 6; color: Theme.w62; text: (pv.artPage * 14 + 1) + "–" + (pv.artPage * 14 + 14) + " of " + Pix.ART.length }
                Chip { text: "‹"; padX: 22; opacity: pv.artPage > 0 ? 1 : 0.35; enabled: pv.artPage > 0; onTapped: pv.artPage-- }
                Chip { text: "›"; padX: 22; opacity: pv.artPage < 1 ? 1 : 0.35; enabled: pv.artPage < 1; onTapped: pv.artPage++ }
            }
        }
    }

    // ---- Light: the display's own effects, or one colour
    Rise {
        order: 3; visible: pv.tab === "light"
        x: 44; y: 592; width: 1280; height: 290
        Item {
            width: 600; height: parent.height
            Mono { text: "Effects"; color: Theme.w62 }
            Flow {
                y: 36; width: 600; spacing: 10
                Repeater {
                    model: Pix.EFFECTS
                    Chip { text: modelData[1]; warm: pv.mode === "effect" && pv.effect === modelData[0]; onTapped: { pixel.choose("effect", modelData[0]); pixel.effect(modelData[1]) } }
                }
            }
            Mono { y: 202; text: "Effect colours · tap one to change it"; color: Theme.w62 }
            Row {
                y: 236; spacing: 14
                Repeater {
                    model: pv.effCols
                    Press {
                        width: 40; height: 40; pressScale: 0.9
                        onTapped: { var c = pv.effCols.slice(); c[index] = (c[index] + 1) % pv.pal.length; pv.setEffCols(c) }
                        Rectangle { anchors.fill: parent; radius: 20; color: pv.pal[modelData % pv.pal.length]; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
                    }
                }
                Item { width: 6; height: 1 }
                Chip { text: "+ Add"; opacity: pv.effCols.length < 7 ? 1 : 0.35; enabled: pv.effCols.length < 7; onTapped: pv.setEffCols(pv.effCols.concat([(pv.effCols.length * 3) % pv.pal.length])) }
                Chip { text: "Remove"; opacity: pv.effCols.length > 2 ? 1 : 0.35; enabled: pv.effCols.length > 2; onTapped: pv.setEffCols(pv.effCols.slice(0, -1)) }
            }
        }
        Item {
            x: 700; width: 580; height: parent.height
            Mono { text: "One colour"; color: Theme.w62 }
            Swatches { y: 36; width: 600; cols: pv.pal; pick: pv.mode === "colour" ? pv.solidCol : -1; onChose: (i) => { pixel.choose("solidCol", i); pixel.colour("One colour") } }
            Note { y: 112; width: 520; text: "Fills the whole display with it." }
        }
    }
    function setEffCols(c) { pixel.choose("effCols", c); if (mode === "effect") pixel.effect(effectName(effect)) }
}
