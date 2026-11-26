import QtQuick
import QtQuick.Controls
import "pixeldata.js" as Pix

// The Pixel display screen: what the 32 × 32 dot display on Bluetooth shows, chosen from here (the link itself, and
// what's sent, is room/pixel — `pixel` here).
// Up top, to read (the touch screen doesn't answer between y 118 and 500): what's on the display now — its name big,
// the display itself drawn dot for dot — and its link. In the top bar: brightness and on / off. Below, what you
// touch: the kinds of picture (Clock · Art · Light · Timers · Text · Library · Setup) and the chosen kind's choices.
// Tapping a choice shows it on the display at once.
// The pictures are drawn here (pixeldata.js: the clock faces and art loops, dot by dot) and handed to `pixel` as
// frames. A clock face is a still, sent again each minute (each second with the seconds dot) for as long as it's
// showing — whatever screen Room is on, standby included; an art loop is 48 frames sent once, which the display then
// plays by itself — a scrolling message goes the same way. Effects, one colour and the Classic clock are the display's
// own. A countdown, the stopwatch, the scoreboard and the assistant's face are up "for now": what was showing is
// remembered and comes back when they're done. Saved GIFs and pictures (the Library) are files on the Surface.
Item {
    id: pv
    objectName: "pixelView"
    width: 1368; height: 912
    property bool shown: false
    property real now: Date.now() / 1000
    readonly property bool sheetOpen: editor.open || tuning.open
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    property bool everShown: false
    onShownChanged: if (shown) { everShown = true; textPeek() }

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
    readonly property string over: v.over                       // up for now: timer · native · face
    readonly property string overItem: v.overItem
    readonly property string itemsKey: JSON.stringify(v.items)
    readonly property var items: JSON.parse(itemsKey)
    readonly property string item: v.sel.item
    readonly property string slidesKey: v.sel.slides.join("|")
    readonly property var slides: slidesKey === "" ? [] : slidesKey.split("|")
    readonly property string facesKey: v.sel.faces.join("|")
    readonly property var faces: facesKey === "" ? [] : facesKey.split("|")
    readonly property int every: v.sel.every
    readonly property bool shuffle: v.sel.shuffle
    readonly property string faceOrder: v.sel.faceOrder
    readonly property int cdSet: v.sel.cdSet
    readonly property int scoreA: v.sel.score[0]
    readonly property int scoreB: v.sel.score[1]
    readonly property string timerStyle: v.sel.timerStyle
    readonly property string text: v.sel.text
    readonly property int textCol: v.sel.textCol
    readonly property int textSpeed: v.sel.textSpeed
    readonly property int textSize: v.sel.textSize
    readonly property string textFont: v.sel.textFont
    readonly property string textLook: v.sel.textLook
    readonly property bool held: v.held
    readonly property bool flip: v.sel.flip
    readonly property bool ecoOn: v.sel.eco.on
    readonly property int ecoStart: v.sel.eco.start
    readonly property int ecoEnd: v.sel.eco.end
    readonly property int ecoLight: v.sel.eco.light
    function ecoSet(key, value) { var e = { on: ecoOn, start: ecoStart, end: ecoEnd, light: ecoLight }; e[key] = value; pixel.choose("eco", e) }
    function hhmm(m) { return Theme.two(Math.floor(m / 60)) + ":" + Theme.two(m % 60) }
    readonly property string tuneKey: JSON.stringify(v.sel.tune)
    readonly property var tune: JSON.parse(tuneKey)
    function tuneSet(key, value) { var t = JSON.parse(tuneKey); t[key] = value; pixel.choose("tune", t) }
    function tuneIs(name) { var t = v.tunes[name]; for (var k in t) if (t[k] !== tune[k]) return false; return true }
    function itemOf(id) { for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i]; return null }
    function toggled(list, id) { var a = list.slice(), i = a.indexOf(id); if (i >= 0) a.splice(i, 1); else a.push(id); return a }
    function col(i) { return Pix.hex(pal[i % pal.length]) }
    function effectName(style) { for (var i = 0; i < Pix.EFFECTS.length; i++) if (Pix.EFFECTS[i][0] === style) return Pix.EFFECTS[i][1]; return "Effect" }

    readonly property var tabs: [["clock", "Clock"], ["art", "Art"], ["light", "Light"], ["timers", "Timers"], ["text", "Text"], ["library", "Library"], ["setup", "Setup"]]
    property string tab: { var m = /^pixel-([a-z]+)/.exec(startScreen); return m && m[1] !== "lost" ? m[1] : "clock" }
    onTabChanged: if (tab === "library" || tab === "setup") pixel.rescan()
    Component.onCompleted: if (startScreen === "pixel-tune") { tab = "setup"; tuning.open = true }      // (checks)
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
        if (mode !== "clockface" || !linked || !on || over !== "") return
        var t = Date.now() / 1000, key = secs ? Math.floor(t) : Math.floor(t / 60)
        if (key !== sentAt) { sentAt = key; showFace(face) }
    }
    Timer { interval: 1000; repeat: true; running: pv.mode === "clockface" && pv.linked && pv.on && pv.over === ""; onTriggered: pv.keepTime() }
    Connections {
        target: pixel
        function onAgain() { pv.sentAt = -1; pv.keepTime() }
        function onRedraw() {              // (the picture tuning changed: what's showing, drawn and sent again)
            if (pv.over !== "") return
            if (pv.mode === "art") pv.showArt(pv.art); else if (pv.mode === "text") pv.showText(); else { pv.sentAt = -1; pv.keepTime() }
        }
    }
    function clockAgain() { if (mode === "classic") pixel.classic(); else if (mode === "clockface") showFace(face) }

    // ---------------------------------------------------------------- loops: an art piece's 48 frames (drawn a few
    // at a time between the screen's own frames, so a tap never holds the screen up) or a message's, then sent as one
    property var job: null
    readonly property bool drawing: job !== null
    function showArt(id) { pixel.loopBegin(); job = { id: id, i: 0, n: Pix.ART_FRAMES, col: col(artCol), ms: pace, mode: "art", label: Pix.ART_NAMES[id] } }
    function sendFrames(frames, mode, label, ms) { pixel.loopBegin(); job = { frames: frames, i: 0, n: frames.length, ms: ms, mode: mode, label: label } }
    Timer {
        interval: 1; repeat: true; running: pv.job !== null
        onTriggered: {
            var j = pv.job
            for (var k = 0; k < (j.frames ? 12 : 2) && j.i < j.n; k++, j.i++) pixel.loopFrame((j.frames ? j.frames[j.i] : Pix.artFrame(j.id, j.i / j.n, j.col)).buffer)
            if (j.i >= j.n) { pv.job = null; pixel.loopEnd(j.mode, j.label, j.ms) }
        }
    }

    // ---------------------------------------------------------------- a scrolling message: written once on a strip
    // (off screen) in the chosen face and size, then cut into frames a dot apart
    property var textFrames: []
    property int textMs: 60
    property int textI: 0
    readonly property string textFamily: textFont === "serif" ? "Instrument Serif" : textFont === "mono" ? Theme.mono : Theme.face
    readonly property int textPx: Math.max(6, Math.round(32 * textSize / 100))
    readonly property string textLine: (text.trim() || " ").replace(/\s+/g, " ")
    TextMetrics { id: measure; font.family: pv.textFamily; font.pixelSize: pv.textPx; font.bold: true; text: pv.textLine }
    function writeText(why) {              // the strip made as long as the message (plus a display's width each side), then written
        strip.want = why
        strip.width = Math.min(4000, Math.ceil(measure.advanceWidth) + 64)
        Qt.callLater(strip.requestPaint)
    }
    function showText() { writeText("send") }
    Canvas {
        id: strip
        x: -5000; width: 64; height: 32
        property string want: ""
        onPaint: {
            if (want === "") return
            var ctx = getContext("2d"), N = 32, w = Math.round(width), str = pv.textLine
            ctx.font = "bold " + pv.textPx + "px '" + pv.textFamily + "'"
            var fg = pv.col(pv.textCol), fl = fg[0] + fg[1] + fg[2], crisp = pv.textLook === "crisp"
            ctx.fillStyle = "#000000"; ctx.fillRect(0, 0, w, N)
            ctx.fillStyle = pv.pal[pv.textCol]; ctx.textBaseline = "middle"; ctx.fillText(str, N, N / 2 + 1)
            var all = ctx.getImageData(0, 0, w, N).data
            var step = Math.max(1, Math.ceil((w - N) / 300)), frames = []
            for (var off = 0; off + N <= w && frames.length < 300; off += step) {
                var f = new Uint8ClampedArray(N * N * 4)
                for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
                    var q = (y * w + x + off) * 4, d = (y * N + x) * 4
                    if (crisp) { var on = (all[q] + all[q + 1] + all[q + 2]) * 2 > fl; f[d] = on ? fg[0] : 0; f[d + 1] = on ? fg[1] : 0; f[d + 2] = on ? fg[2] : 0 }
                    else { f[d] = all[q]; f[d + 1] = all[q + 1]; f[d + 2] = all[q + 2] }
                    f[d + 3] = 255
                }
                frames.push(f)
            }
            var send = want === "send"; want = ""
            pv.textFrames = frames; pv.textMs = Math.max(20, Math.round(160 / pv.textSpeed)) * step; pv.textI = 0
            if (send) pv.sendFrames(frames, "text", str.length > 22 ? str.slice(0, 21) + "…" : str, pv.textMs)
        }
    }
    // (after a restart the message is on the display but not written here yet: written again, to look at only)
    function textPeek() { if (mode === "text" && textFrames.length === 0 && shown && !drawing) writeText("look") }
    onModeChanged: textPeek()

    // ---------------------------------------------------------------- timers and the scoreboard, up for now.
    // "Minimal": drawn here in the clock's digits and colour, sent each second. "Built-in": the display's own screens.
    property string tool: startScreen.indexOf("-sw") > 0 ? "sw" : startScreen.indexOf("-score") > 0 ? "score" : "cd"
    readonly property bool minimal: timerStyle === "minimal"
    property var tm: null                  // a running countdown ("cd") or stopwatch ("sw"): { kind, total, t0, paused, at }
    property int tmSecs: 0
    property int tmLast: -1
    property var overPx: null              // the frame that's up
    property string nativeKind: ""         // the display's own: which is up, and whether it's paused
    property bool nativePaused: false
    property bool scoreUp: false
    function tmNow() {
        var t = tm; if (!t) return 0
        if (t.paused) return t.at
        var el = Math.floor((Date.now() - t.t0) / 1000)
        return t.kind === "cd" ? Math.max(0, t.total - el) : el
    }
    function up(kind, frame) { overPx = frame; pixel.temp("timer", kind, frame.buffer) }
    function tmTick() {
        var t = tm; if (!t || t.paused) return
        var s = tmNow(); if (s === tmLast) return
        tmLast = s; tmSecs = s
        up(t.kind, Pix.timerFrame(t.kind, s, t.total, col(clockCol)))
        if (t.kind === "cd" && s <= 0) { tm = null; blink.n = 0; blink.start() }
    }
    Timer { interval: 200; repeat: true; running: pv.tm !== null && !pv.tm.paused; onTriggered: pv.tmTick() }
    Timer {                                // time's up: 00:00 flashes three times, then what was showing comes back
        id: blink
        property int n: 0
        interval: 450; repeat: true
        onTriggered: { n++; pv.up("cd", n % 2 ? Pix.blank() : Pix.timerFrame("cd", 0, 1, pv.col(pv.clockCol))); if (n >= 6) { stop(); pixel.restore() } }
    }
    function tmStart(kind) {
        blink.stop(); scoreUp = false; nativeKind = ""
        if (!minimal) { nativeKind = kind; nativePaused = false; pixel.native(kind === "cd" ? "cd_start" : "sw_start", Math.floor(cdSet / 60), cdSet % 60); return }
        tm = { kind: kind, total: kind === "cd" ? cdSet : 0, t0: Date.now(), paused: false, at: 0 }; tmLast = -1; tmTick()
    }
    function tmPause() {
        if (nativeKind !== "") { nativePaused = !nativePaused; pixel.native((nativeKind === "cd" ? "cd_" : "sw_") + (nativePaused ? "pause" : "resume"), Math.floor(cdSet / 60), cdSet % 60); return }
        var t = tm; if (!t) return
        if (!t.paused) { tm = { kind: t.kind, total: t.total, t0: t.t0, paused: true, at: tmNow() }; tmSecs = tm.at }
        else { tm = { kind: t.kind, total: t.total, t0: Date.now() - (t.kind === "cd" ? t.total - t.at : t.at) * 1000, paused: false, at: 0 }; tmLast = -1; tmTick() }
    }
    function tmStop() {
        if (nativeKind !== "") pixel.native(nativeKind === "cd" ? "cd_stop" : "sw_reset", 0, 0)
        pixel.restore()
    }
    function scoreShow() {
        blink.stop(); tm = null; nativeKind = ""; scoreUp = true
        if (minimal) up("score", Pix.scoreFrame(scoreA, scoreB, col(clockCol))); else { nativeKind = "score"; pixel.native("score", scoreA, scoreB) }
    }
    function scoreSet(a, b) {
        a = Math.max(0, Math.min(999, a)); b = Math.max(0, Math.min(999, b))
        pixel.choose("score", [a, b])
        if (scoreUp && over !== "") { if (minimal) up("score", Pix.scoreFrame(a, b, col(clockCol))); else pixel.native("score", a, b) }
    }
    // whatever was up is gone (it finished, or something else was put on the display)
    onOverChanged: if (over === "") { tm = null; blink.stop(); scoreUp = false; nativeKind = ""; nativePaused = false }
    readonly property bool timing: over === "timer" || over === "native"
    readonly property string timerKind: tm ? tm.kind : nativeKind !== "" ? nativeKind : scoreUp ? "score" : "cd"

    // ---------------------------------------------------------------- the assistant's face: up while it answers
    readonly property string voiceState: room.voice.state || "off"
    onVoiceStateChanged: { if (voiceState === "speaking") pixel.faceOn(); else pixel.faceOff() }
    Timer { id: faceTest; interval: 5000; onTriggered: pixel.faceOff() }

    // ---------------------------------------------------------------- the display's picture, here: what's showing,
    // moving as it moves (only while this screen is up)
    property real artT: 0
    property int effF: 0
    Timer {
        interval: pv.mode === "art" ? Math.max(120, pv.pace) : 120; repeat: true
        running: pv.shown && pv.linked && pv.on && pv.over === "" && (pv.mode === "art" || pv.mode === "effect" || pv.mode === "text")
        onTriggered: { pv.artT = (pv.artT + 1 / Pix.ART_FRAMES) % 1; pv.effF = (pv.effF + 1) % 24; pv.textI++ }
    }
    readonly property var picture: {
        if (!linked || !on) return Pix.blank()
        if (over === "timer") return overPx || Pix.blank()
        if (over === "native") return nativeKind === "score" ? Pix.scoreFrame(scoreA, scoreB, col(clockCol)) : Pix.timerFrame(nativeKind === "sw" ? "sw" : "cd", nativeKind === "sw" ? 0 : cdSet, cdSet, col(clockCol))
        if (shownItem) return shownItem.url === "" ? Pix.artFrame(shownItem.id.replace(".gif", ""), 0.3, col(8)) : null
        if (mode === "text") return textFrames.length ? textFrames[textI % textFrames.length] : Pix.blank()
        if (mode === "art") return Pix.artFrame(art, artT, col(artCol))
        if (mode === "effect") return Pix.effectFrame(effect, effCols.map(col), effF)
        if (mode === "colour") return Pix.solid(col(solidCol))
        if (mode === "classic") return faceFrame("classic", minuteNow)
        if (mode === "clockface") return faceFrame(face, secs ? now : minuteNow)
        return Pix.blank()
    }
    // a saved picture that's on the display: the assistant's face, or the Library's
    readonly property var shownItem: over === "face" ? itemOf(overItem) : over === "" && (mode === "library" || mode === "slideshow") ? itemOf(item) : null
    readonly property string title: !v.enabled ? "Switched off" : !held ? "Released" : !linked ? (link === "connecting" ? "Connecting" : "Looking for it")
                                    : !on ? "Off" : over === "face" ? v.overLabel
                                    : timing ? (timerKind === "score" ? scoreA + " – " + scoreB : tm ? Pix.mmss(tmSecs).join(":") : timerKind === "sw" ? "Stopwatch" : "Countdown")
                                    : mode === "slideshow" && shownItem ? shownItem.name : label !== "" ? label : "Nothing yet"
    readonly property string kind: !v.enabled ? "\"pixel\": false in config.json" : !held ? "Room has let go of it. Another app can connect to it now." : !linked ? (v.name ? v.name + " isn't answering. Is it powered on?" : "No pixel display found yet. Is it powered on?")
                                   : !on ? "The display is dark. Turn on to bring it back." : drawing ? "Drawing the loop…"
                                   : sending && pct > 0 ? "Sending · " + pct + "%"
                                   : over === "face" ? "The assistant's face · while it answers"
                                   : timing ? (timerKind === "score" ? "Scoreboard" : (timerKind === "sw" ? "Stopwatch" : "Countdown") + (tm ? (tm.paused ? " · paused" : " · running") : nativePaused ? " · paused" : " · on the display"))
                                   : mode === "text" ? "Scrolling text" : mode === "library" ? "From the library" : mode === "slideshow" ? "Slideshow · changes every " + everText(every)
                                   : mode === "clockface" ? "Clock face · kept in time by Room" : mode === "classic" ? "Clock · the display's own"
                                   : mode === "art" ? "Art · loops on the display" : mode === "effect" ? "Effect · made by the display"
                                   : mode === "colour" ? "One colour" : "Tap something below to show it"

    function everText(s) { return s < 60 ? s + " s" : s < 3600 ? (s / 60) + " min" : (s / 3600) + " h" }

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
        property url src: ""               // (a saved picture: its first frame)
        property real k: 1
        onPxChanged: cv.requestPaint()
        onSrcChanged: cv.requestPaint()
        onKChanged: cv.requestPaint()
        Rectangle { anchors.fill: parent; radius: width * 0.085; color: "#060505"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12) }
        Canvas {
            id: cv
            anchors.fill: parent; anchors.margins: parent.width * 0.075
            onImageLoaded: requestPaint()
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                var data = sl.px
                if (!data && sl.src != "") {
                    if (!isImageLoaded(sl.src)) { loadImage(sl.src); return }
                    ctx.drawImage(sl.src, 0, 0, 32, 32); data = ctx.getImageData(0, 0, 32, 32).data; ctx.clearRect(0, 0, width, height)
                }
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
        property url src: ""
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
        Image { x: 12; y: 12; width: tl.side - 24; height: tl.side - 24; visible: tl.src != ""; source: tl.src; smooth: false; fillMode: Image.PreserveAspectCrop; asynchronous: true }
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
    component Step: Row {
        id: sp
        property string value: ""
        property real wide: 84
        signal less()
        signal more()
        spacing: 8
        Chip { text: "−"; padX: 17; onTapped: sp.less() }
        Text { width: sp.wide; height: 44; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: sp.value; color: "white"; font.pixelSize: 22; font.family: Theme.face; renderType: Text.QtRendering }
        Chip { text: "+"; padX: 17; onTapped: sp.more() }
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
                : !pv.v.enabled ? "" : !pv.held ? "Setup → Take it back, to use it from here again"
                : pv.link === "connecting" ? "Found it · connecting" : "Searching · tries again by itself"
        }
    }
    Rise {
        order: 1
        x: 1324 - 336; y: 136; width: 336; height: 336
        Slab { id: slab; anchors.fill: parent; px: pv.picture; src: pv.picture === null && pv.shownItem ? pv.shownItem.url : "" }
    }

    // ---------------------------------------------------------------- to touch: the kinds
    Rise {
        order: 2
        x: 44; y: 514; width: 1280; height: 44
        Row { spacing: 10; Repeater { model: pv.tabs; Chip { text: modelData[1]; warm: pv.tab === modelData[0]; onTapped: pv.tab = modelData[0] } } }
        Row {
            anchors.right: parent.right; spacing: 10; visible: pv.tab === "timers"
            Mono { anchors.verticalCenter: parent.verticalCenter; rightPadding: 8; color: Theme.w62; text: "Drawn" }
            Repeater { model: [["minimal", "Minimal"], ["builtin", "Built-in"]]; Chip { text: modelData[1]; warm: pv.timerStyle === modelData[0]; onTapped: { if (pv.timing) pv.tmStop(); pixel.choose("timerStyle", modelData[0]) } } }
        }
        Mono {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; color: Theme.w42
            visible: pv.tab === "clock" || pv.tab === "art" || pv.tab === "light" || pv.tab === "library"
            text: pv.linked ? "Tap one to show it" : "Choices are kept and shown once it's connected"
        }
    }

    // ---- Clock: fourteen faces, colour, 24-hour, seconds
    Rise {
        order: 3; visible: pv.tab === "clock" && !pv.sheetOpen
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
        order: 3; visible: pv.tab === "art" && !pv.sheetOpen
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
        order: 3; visible: pv.tab === "light" && !pv.sheetOpen
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
    // ---- Timers: countdown, stopwatch or scoreboard — one at a time, as only one can be on the display
    Rise {
        order: 3; visible: pv.tab === "timers" && !pv.sheetOpen
        x: 44; y: 592; width: 1280; height: 290
        Row { spacing: 10; Repeater { model: [["cd", "Countdown"], ["sw", "Stopwatch"], ["score", "Scoreboard"]]; Chip { text: modelData[1]; warm: pv.tool === modelData[0]; onTapped: pv.tool = modelData[0] } } }
        Item {
            y: 84; width: parent.width; height: 200; visible: pv.tool === "cd"
            readonly property bool mine: pv.timing && pv.timerKind === "cd"
            Serif { text: Pix.mmss(parent.mine && pv.tm ? pv.tmSecs : pv.cdSet).join(":"); font.pixelSize: 124; color: parent.mine ? Theme.timer2 : "white" }
            Column {
                x: 430; y: 6; spacing: 18
                opacity: parent.mine ? 0.35 : 1; enabled: !parent.mine
                Row {
                    spacing: 8
                    Chip { text: "−"; padX: 17; onTapped: pixel.choose("cdSet", Math.max(5, pv.cdSet - 60)) }
                    Mono { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; rightPadding: 6; text: "Min"; color: Theme.w62 }
                    Chip { text: "+"; padX: 17; onTapped: pixel.choose("cdSet", Math.min(5999, pv.cdSet + 60)) }
                    Item { width: 22; height: 1 }
                    Chip { text: "−"; padX: 17; onTapped: pixel.choose("cdSet", Math.max(5, pv.cdSet - 5)) }
                    Mono { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; rightPadding: 6; text: "Sec"; color: Theme.w62 }
                    Chip { text: "+"; padX: 17; onTapped: pixel.choose("cdSet", Math.min(5999, pv.cdSet + 5)) }
                }
                Row { spacing: 10; Repeater { model: [1, 5, 10, 25]; Chip { text: modelData + " min"; warm: pv.cdSet === modelData * 60; onTapped: pixel.choose("cdSet", modelData * 60) } } }
            }
            Row {
                anchors.right: parent.right; y: 6; spacing: 10
                Chip { solid: true; visible: !parent.parent.mine; text: "Start"; onTapped: pv.tmStart("cd") }
                Chip { visible: parent.parent.mine; text: (pv.tm && pv.tm.paused) || pv.nativePaused ? "Resume" : "Pause"; onTapped: pv.tmPause() }
                Chip { visible: parent.parent.mine; text: "Stop"; onTapped: pv.tmStop() }
            }
        }
        Item {
            y: 84; width: parent.width; height: 200; visible: pv.tool === "sw"
            readonly property bool mine: pv.timing && pv.timerKind === "sw"
            Serif { text: Pix.mmss(parent.mine && pv.tm ? pv.tmSecs : 0).join(":"); font.pixelSize: 124; color: parent.mine ? Theme.timer2 : Qt.rgba(1, 1, 1, 0.45) }
            Row {
                anchors.right: parent.right; y: 6; spacing: 10
                Chip { solid: true; visible: !parent.parent.mine; text: "Start"; onTapped: pv.tmStart("sw") }
                Chip { visible: parent.parent.mine; text: (pv.tm && pv.tm.paused) || pv.nativePaused ? "Resume" : "Pause"; onTapped: pv.tmPause() }
                Chip { visible: parent.parent.mine; text: "Reset"; onTapped: pv.tmStop() }
            }
        }
        Item {
            y: 84; width: parent.width; height: 200; visible: pv.tool === "score"
            readonly property bool mine: pv.timing && pv.timerKind === "score"
            Serif { x: 0; width: 180; horizontalAlignment: Text.AlignHCenter; text: pv.scoreA; font.pixelSize: 124 }
            Rectangle { x: 239; y: 16; width: 1; height: 92; color: Qt.rgba(1, 1, 1, 0.25) }
            Serif { x: 300; width: 180; horizontalAlignment: Text.AlignHCenter; text: pv.scoreB; font.pixelSize: 124 }
            Row { x: 37; y: 148; spacing: 8; Chip { text: "−"; padX: 17; onTapped: pv.scoreSet(pv.scoreA - 1, pv.scoreB) } Chip { text: "+"; padX: 17; onTapped: pv.scoreSet(pv.scoreA + 1, pv.scoreB) } }
            Row { x: 337; y: 148; spacing: 8; Chip { text: "−"; padX: 17; onTapped: pv.scoreSet(pv.scoreA, pv.scoreB - 1) } Chip { text: "+"; padX: 17; onTapped: pv.scoreSet(pv.scoreA, pv.scoreB + 1) } }
            Row {
                anchors.right: parent.right; y: 6; spacing: 10
                Chip { solid: !parent.parent.mine; text: parent.parent.mine ? "Take it down" : "Show scoreboard"; onTapped: { if (parent.parent.mine) pv.tmStop(); else pv.scoreShow() } }
                Chip { text: "Reset"; onTapped: pv.scoreSet(0, 0) }
            }
        }
    }

    // ---- Text: a scrolling message
    Rise {
        order: 3; visible: pv.tab === "text" && !pv.sheetOpen
        x: 44; y: 592; width: 1280; height: 290
        Item {
            width: 700; height: parent.height
            Mono { text: "Message"; color: Theme.w62 }
            Press {
                y: 34; width: 700; height: 64; pressScale: 0.99
                onTapped: editor.ask()
                Rectangle { anchors.fill: parent; radius: 9; color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.24) }
                Text { x: 22; width: 560; height: 64; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; text: pv.text; color: "white"; font.pixelSize: 26; font.family: Theme.face; renderType: Text.QtRendering }
                Mono { anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter; text: "Edit"; color: Theme.w62 }
            }
            Mono { y: 126; text: "Text colour"; color: Theme.w62 }
            Swatches { y: 160; width: 700; cols: pv.pal; pick: pv.textCol; onChose: (i) => { pixel.choose("textCol", i); if (pv.mode === "text") pv.showText() } }
            Chip { y: 240; solid: true; text: "Show on display"; onTapped: pv.showText() }
        }
        Column {
            x: 800; width: 480; spacing: 18
            Line { label: "Speed"; Step { value: pv.textSpeed; onLess: pv.textSet("textSpeed", Math.max(1, pv.textSpeed - 1)); onMore: pv.textSet("textSpeed", Math.min(10, pv.textSpeed + 1)) } }
            Line { label: "Size"; Step { value: pv.textSize + "%"; onLess: pv.textSet("textSize", Math.max(30, pv.textSize - 5)); onMore: pv.textSet("textSize", Math.min(90, pv.textSize + 5)) } }
            Line { label: "Typeface"; Repeater { model: [["sans", "Sans"], ["serif", "Serif"], ["mono", "Mono"]]; Chip { text: modelData[1]; warm: pv.textFont === modelData[0]; onTapped: pv.textSet("textFont", modelData[0]) } } }
            Line { label: "Look"; Repeater { model: [["crisp", "Crisp"], ["soft", "Smooth"]]; Chip { text: modelData[1]; warm: pv.textLook === modelData[0]; onTapped: pv.textSet("textLook", modelData[0]) } } }
        }
    }
    function textSet(key, value) { pixel.choose(key, value); if (mode === "text") showText() }

    // ---- Library: what's saved, and a slideshow of the ticked ones
    property int libPage: 0
    property string doomed: ""              // (held once: hold again to delete)
    Timer { id: spare; interval: 4000; onTriggered: pv.doomed = "" }
    Rise {
        order: 3; visible: pv.tab === "library" && !pv.sheetOpen
        x: 44; y: 592; width: 1280; height: 290
        Loader {
            active: pv.everShown && pv.tab === "library"
            sourceComponent: Row {
                spacing: 18
                Repeater {
                    model: pv.items.slice(pv.libPage * 7, pv.libPage * 7 + 7)
                    Column {
                        spacing: 10
                        Tile {
                            label: pv.doomed === modelData.id ? "Hold to delete" : modelData.name
                            picked: pv.over === "" && (pv.mode === "library" || pv.mode === "slideshow") && pv.item === modelData.id
                            src: modelData.url
                            px: modelData.url === "" ? Pix.artFrame(modelData.id.replace(".gif", ""), 0.3, pv.col(8)) : null
                            onTapped: { pv.doomed = ""; pixel.show(modelData.id) }
                            onHeld: { if (pv.doomed === modelData.id) { pv.doomed = ""; pixel.remove(modelData.id) } else { pv.doomed = modelData.id; spare.restart() } }
                        }
                        Press {
                            id: tk
                            readonly property bool inIt: pv.slides.indexOf(modelData.id) >= 0
                            width: 108; height: 40; pressScale: 0.95
                            onTapped: pixel.choose("slides", pv.toggled(pv.slides, modelData.id))
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: tk.inIt ? "#ffbe7a" : "transparent"; border.width: tk.inIt ? 0 : 1.5; border.color: Qt.rgba(1, 1, 1, 0.5)
                                            Icon { anchors.centerIn: parent; visible: tk.inIt; name: "check"; size: 10; color: "#1a0f08" } }
                                Mono { anchors.verticalCenter: parent.verticalCenter; size: 11; text: "Slideshow"; color: tk.inIt ? "white" : Theme.w42 }
                            }
                        }
                    }
                }
            }
        }
        Note {
            y: 214; width: 860
            text: (pv.items.length ? "Tap one to show it · hold twice to delete it" : "Nothing saved yet")
                  + "\nNew GIFs and pictures: copy them into " + pv.v.libraryPath + " on the Surface"
        }
        Row {
            y: 244; spacing: 10; visible: pv.items.length > 7
            Chip { text: "‹"; padX: 22; opacity: pv.libPage > 0 ? 1 : 0.35; enabled: pv.libPage > 0; onTapped: pv.libPage-- }
            Chip { text: "›"; padX: 22; opacity: (pv.libPage + 1) * 7 < pv.items.length ? 1 : 0.35; enabled: (pv.libPage + 1) * 7 < pv.items.length; onTapped: pv.libPage++ }
        }
        Item {
            x: 936; width: 344; height: parent.height
            Mono { text: "Slideshow"; color: Theme.w62 }
            Column {
                y: 36; width: parent.width; spacing: 12
                Line {
                    label: "Change every"
                    Step {
                        readonly property var steps: [30, 60, 300, 900, 3600]
                        value: pv.everText(pv.every); wide: 76
                        onLess: pixel.choose("every", steps[Math.max(0, steps.indexOf(pv.every) - 1)])
                        onMore: pixel.choose("every", steps[Math.min(steps.length - 1, steps.indexOf(pv.every) + 1)])
                    }
                }
                Line { label: "Shuffle"; Toggle { on: pv.shuffle; onTapped: pixel.choose("shuffle", !pv.shuffle) } }
            }
            Chip {
                y: 172; solid: pv.mode !== "slideshow"; text: pv.mode === "slideshow" ? "Stop slideshow" : "Start slideshow"
                opacity: pv.slides.length || pv.mode === "slideshow" ? 1 : 0.4; enabled: pv.slides.length > 0 || pv.mode === "slideshow"
                onTapped: pixel.slideshow(pv.mode !== "slideshow")
            }
            Note { y: 232; width: 344; text: pv.slides.length ? pv.slides.length + " ticked" : "Tick the ones to go round" }
        }
    }

    // ---- Setup: the assistant's face, night dimming, picture tuning, the display itself
    property int facePage: 0
    Rise {
        order: 3; visible: pv.tab === "setup" && !pv.sheetOpen
        x: 44; y: 592; width: 1280; height: 290
        Item {
            width: 290; height: parent.height
            Mono { text: "Assistant face"; color: Theme.w62 }
            Loader {
                y: 36; active: pv.everShown && pv.tab === "setup"
                sourceComponent: Row {
                    spacing: 13
                    Repeater {
                        model: pv.items.slice(pv.facePage * 3, pv.facePage * 3 + 3)
                        Tile {
                            side: 88; label: modelData.name.split(" ")[0]; picked: pv.faces.indexOf(modelData.id) >= 0
                            src: modelData.url
                            px: modelData.url === "" ? Pix.artFrame(modelData.id.replace(".gif", ""), 0.3, pv.col(8)) : null
                            onTapped: pixel.choose("faces", pv.toggled(pv.faces, modelData.id))
                        }
                    }
                }
            }
            Note { y: 60; width: 290; visible: pv.items.length === 0; text: "Pictures in the Library can be chosen here. Nothing is saved there yet." }
            Row {
                y: 172; spacing: 10
                Repeater { model: [["order", "In order"], ["shuffle", "Shuffle"]]; Chip { text: modelData[1]; warm: pv.faceOrder === modelData[0]; onTapped: pixel.choose("faceOrder", modelData[0]) } }
            }
            Row {
                y: 228; spacing: 10
                Chip { text: "Show it now"; opacity: pv.faces.length ? 1 : 0.4; enabled: pv.faces.length > 0; onTapped: { pixel.faceOn(); faceTest.restart() } }
                Chip { text: "‹"; padX: 17; visible: pv.items.length > 3; opacity: pv.facePage > 0 ? 1 : 0.35; enabled: pv.facePage > 0; onTapped: pv.facePage-- }
                Chip { text: "›"; padX: 17; visible: pv.items.length > 3; opacity: (pv.facePage + 1) * 3 < pv.items.length ? 1 : 0.35; enabled: (pv.facePage + 1) * 3 < pv.items.length; onTapped: pv.facePage++ }
            }
        }
        Item {
            x: 330; width: 290; height: parent.height
            Mono { text: "Night dimming"; color: Theme.w62 }
            Column {
                y: 36; width: parent.width; spacing: 12
                Line { label: "Dim at night"; Toggle { on: pv.ecoOn; onTapped: pv.ecoSet("on", !pv.ecoOn) } }
                Line { label: "From"; Step { value: pv.hhmm(pv.ecoStart); wide: 70; onLess: pv.ecoSet("start", (pv.ecoStart + 1410) % 1440); onMore: pv.ecoSet("start", (pv.ecoStart + 30) % 1440) } }
                Line { label: "To"; Step { value: pv.hhmm(pv.ecoEnd); wide: 70; onLess: pv.ecoSet("end", (pv.ecoEnd + 1410) % 1440); onMore: pv.ecoSet("end", (pv.ecoEnd + 30) % 1440) } }
                Line {
                    label: "At"
                    Step {
                        readonly property var steps: [5, 10, 20, 30]
                        value: pv.ecoLight + "%"; wide: 70
                        onLess: pv.ecoSet("light", steps[Math.max(0, steps.indexOf(pv.ecoLight) - 1)])
                        onMore: pv.ecoSet("light", steps[Math.min(steps.length - 1, steps.indexOf(pv.ecoLight) + 1)])
                    }
                }
            }
        }
        Item {
            x: 660; width: 290; height: parent.height
            Mono { text: "Picture tuning"; color: Theme.w62 }
            Flow {
                y: 36; width: 290; spacing: 10
                Repeater {
                    model: [["balanced", "Balanced"], ["bright", "Bright"], ["deep", "Deep"], ["off", "Off"]]
                    Chip { text: modelData[1]; warm: pv.tuneIs(modelData[0]); onTapped: pixel.choose("tune", pv.v.tunes[modelData[0]]) }
                }
            }
            Chip { y: 160; text: "Fine tune"; onTapped: tuning.open = true }
            Note { y: 224; width: 290; text: "LEDs show mid tones brighter than a screen. This corrects what's sent." }
        }
        Item {
            x: 990; width: 290; height: parent.height
            Mono { text: "Display"; color: Theme.w62 }
            Column { y: 36; width: parent.width; spacing: 12; Line { label: "Flip 180°"; Toggle { on: pv.flip; onTapped: pixel.choose("flip", !pv.flip) } } }
            Note {
                y: 96; width: 290
                text: (pv.v.name || "No display yet") + (pv.v.firmware ? " · firmware " + pv.v.firmware : "")
                      + "\n" + (pv.v.answer !== "" ? pv.v.answer : pv.linked ? "Packets of " + pv.v.packet + " bytes" : pv.held ? "Not connected" : "Released")
            }
            Chip { y: 160; text: "Check connection"; opacity: pv.linked ? 1 : 0.4; enabled: pv.linked; onTapped: pixel.check() }
            Chip { y: 216; text: pv.held ? "Release display" : "Take it back"; solid: !pv.held; onTapped: pixel.hold(!pv.held) }
        }
    }

    // ---------------------------------------------------------------- picture tuning, value by value
    SheetFrame {
        id: tuning
        paneY: 520
        onClose: open = false
        Serif { x: 36; y: 30; font.pixelSize: 44; text: "Fine tune" }
        Chip { x: 1280 - 36 - width; y: 30; solid: true; text: "Done"; onTapped: tuning.open = false }
        component Dial: Line {
            property string k: ""
            property int lo: 0
            property int hi: 100
            property int by: 1
            readonly property int val: pv.tune[k] === undefined ? 0 : pv.tune[k]
            Step {
                wide: 84
                value: parent.parent.k === "exp" ? (parent.parent.val / 100).toFixed(2) + "×" : parent.parent.k === "gamma" || parent.parent.k === "sat" ? (parent.parent.val / 10).toFixed(1)
                       : parent.parent.k === "lift" ? "" + parent.parent.val : parent.parent.val + "%"
                onLess: pv.tuneSet(parent.parent.k, Math.max(parent.parent.lo, parent.parent.val - parent.parent.by))
                onMore: pv.tuneSet(parent.parent.k, Math.min(parent.parent.hi, parent.parent.val + parent.parent.by))
            }
        }
        Column {
            x: 36; y: 106; width: 560; spacing: 10
            Dial { label: "Exposure"; k: "exp"; lo: 50; hi: 250; by: 10 }
            Dial { label: "Contrast"; k: "gamma"; lo: 10; hi: 30 }
            Dial { label: "Shadow lift"; k: "lift"; lo: 0; hi: 40; by: 2 }
            Dial { label: "Vividness"; k: "sat"; lo: 0; hi: 25 }
        }
        Column {
            x: 684; y: 106; width: 560; spacing: 10
            Dial { label: "Red"; k: "r"; lo: 40; hi: 100; by: 5 }
            Dial { label: "Green"; k: "g"; lo: 40; hi: 100; by: 5 }
            Dial { label: "Blue"; k: "b"; lo: 40; hi: 100; by: 5 }
            Note { width: 560; topPadding: 8; text: "Each change is sent to the display at once, so you can judge it there." }
        }
    }

    // ---------------------------------------------------------------- the message, typed
    SheetFrame {
        id: editor
        paneY: 560
        onClose: open = false
        function ask() { box.text = pv.text; open = true; box.forceActiveFocus() }
        function done() { pixel.choose("text", box.text.trim() === "" ? "Hello" : box.text); open = false; pv.showText() }
        Serif { x: 36; y: 36; font.pixelSize: 56; text: "Message" }
        TextField {
            id: box
            property string enterLabel: "Show"
            property bool enterAccepts: true
            x: 36; y: 36 + 56 + 30; width: 1280 - 72; height: 60
            maximumLength: 200
            font.family: Theme.face; font.pixelSize: 32
            color: "white"
            leftPadding: 0; topPadding: 0; bottomPadding: 0
            background: Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, box.activeFocus ? 0.6 : 0.2) }
            inputMethodHints: Qt.ImhNoPredictiveText
            onAccepted: editor.done()
        }
        Row {
            x: 36; y: 36 + 56 + 30 + 60 + 30; spacing: 10
            Chip { solid: true; text: "Show on display"; onTapped: editor.done() }
            Chip { text: "Cancel"; onTapped: editor.open = false }
        }
    }

    function setEffCols(c) { pixel.choose("effCols", c); if (mode === "effect") pixel.effect(effectName(effect)) }
}
