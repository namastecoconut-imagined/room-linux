import QtQuick
import "catsdata.js" as Data

// One of Room's cats (Bebo or Evan), drawn frame by frame from its clip library (catsdata.js and the sprite sheets in
// assets/cats/). (ax, ay) is where it touches what it's on — paws on a line, belly on an edge — so it always rests on
// something real. It plays the clips it's given (a plan, from Cats.qml) one after another; with nothing to do it rests
// in its pose's breathing loop, now and then blinking, twitching an ear, glancing round or flicking its tail. It's
// never still. Cats.qml steps every cat together, 10 drawings a second.
Item {
    id: cat
    property string who: "bebo"
    property real size: 160                          // how wide its 200-unit cell is drawn (stage px)
    readonly property real k: size / Data.cellW      // stage px a unit
    function unit(n) { return n && Data.sheets[n] ? Data.sheets[n][2] : 1 }     // a sheet's px a unit (each its own)
    readonly property real s: k / unit(cc.s)         // stage px a pixel of the sheet showing
    property real ax: 0
    property real ay: 0
    property bool mirror: false                      // the drawings face right; mirrored, the cat faces left
    readonly property int dir: mirror ? -1 : 1
    property bool shown: false
    property string spotId: ""                       // (Cats.qml's: what it's on)
    property real thinkAt: 0                         // (Cats.qml's: when it next decides something)
    property bool engaged: false                     // (Cats.qml's: in a game with the other one)

    // ---------------------------------------------------------------- what it's playing
    property string clip: "sit"
    property int fi: 0
    property string pose: "sit"                      // the resting pose it's in: stand sit loaf curl drape peek, or none (out of sight)
    property var plan: []
    property var item: null                          // the plan step playing now ({ c, n, until, to, leap })
    property var pend: null                          // the step waiting for its sheet to load
    property bool restClip: true
    property bool hidden: false
    readonly property var cc: Data.clips[who][clip]
    readonly property var fr: Data.frames[cc.s][cc.f[Math.min(fi, cc.f.length - 1)]]
    function free() { return plan.length === 0 && pend === null && (restClip || hidden) }     // nothing to do but rest
    function idle() { return plan.length === 0 && (pend === null ? restClip || hidden : pend.rest === true) }   // (or about to)
    readonly property var rests: ({ stand: 1, sit: 1, loaf: 1, curl: 1, drape: 1, peek: 1, side: 1, belly: 1, none: 1 })

    // running and trotting glide between drawings (walking steps from one to the next, so the paws stay put)
    Behavior on ax { enabled: cat.cc.g === true && !arcA.running; NumberAnimation { duration: 100; easing.type: Easing.Linear } }
    x: ax - 100 * k
    y: ay - (180 - Data.top) * k
    width: Data.cellW * k; height: Data.cellH * k
    opacity: shown && !waiting ? 1 : 0
    property bool waiting: false                     // just put somewhere: unseen until its first drawing there is in
    visible: opacity > 0.01 && !hidden
    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
    transform: Scale { origin.x: 100 * cat.k; xScale: cat.mirror ? -1 : 1 }

    // four sheets kept: the one showing, the next one loading, and the ones used most lately — so going between
    // sitting, walking and lying down doesn't unpack the same drawings again and again (each sheet unpacked is work
    // for the processor, and a picture sent to the graphics chip)
    property var slots: ["", "", "", ""]
    property var used: [0, 0, 0, 0]
    property int stamp: 0
    readonly property int showing: slots.indexOf(cc.s)
    function url(n) { return n ? Qt.resolvedUrl("../assets/cats/" + n + ".png") : "" }
    function ready(n) { var i = slots.indexOf(n), it = i >= 0 ? sheetRep.itemAt(i) : null; return it !== null && it.ready }
    function load(n) {
        if (!n) return
        var i = slots.indexOf(n), u = used.slice()
        if (i < 0) {                                   // into the slot used least lately (never the one showing)
            for (var j = 0; j < slots.length; j++) if (j !== showing && (i < 0 || u[j] < u[i])) i = j
            var sl = slots.slice(); sl[i] = n; slots = sl
        }
        u[i] = ++stamp; used = u
    }
    Repeater {
        id: sheetRep
        model: 4
        Item {
            readonly property string sheet: cat.slots[index]
            readonly property bool ready: img.status === Image.Ready
            visible: cat.showing === index && ready
            x: cat.fr[4] * cat.s; y: cat.fr[5] * cat.s; width: cat.fr[2] * cat.s; height: cat.fr[3] * cat.s
            clip: true
            Image {
                id: img
                source: cat.url(parent.sheet); asynchronous: true; cache: false; smooth: true
                x: -cat.fr[0] * cat.s; y: -cat.fr[1] * cat.s
                width: (parent.sheet ? Data.sheets[parent.sheet][0] / cat.unit(parent.sheet) : 0) * cat.k
                height: (parent.sheet ? Data.sheets[parent.sheet][1] / cat.unit(parent.sheet) : 0) * cat.k
            }
        }
    }

    // ---------------------------------------------------------------- giving it things to do
    // a plan: clip names, or steps — { c: "walk", to: x } walks until near x; { c: "air", leap: { x, y }, from } flies
    // there; { c, n } plays a loop n times; { c, until: fn } loops until fn() says so; { flip: true } turns the
    // drawing round; { face: x } turns round (standing) if it's facing away from x — decided when it gets there, not
    // when the plan was made, as a leap before it may have turned it; { wait: fn } rests in whatever pose it's in until
    // fn() says go (the two of them keeping together); { call: fn } runs fn. A resting cat takes it near the bottom of
    // a breath (no jump) — or at once, given now (a fright).
    function go(steps, now) {
        plan = steps.map(function (st) { return typeof st === "string" ? { c: st } : st })
        load(sheetOf(firstClip()))
        if (now && pend === null && (restClip || hidden)) next()
    }
    // straight into a resting pose, no transition (arriving on a screen)
    function settle(p, m) {
        arcA.stop(); plan = []; item = null
        pose = p; hidden = p === "none"
        if (m !== undefined) mirror = m
        pend = p === "none" ? null : { c: p, rest: true }
        waiting = pend !== null
        if (pend) load(sheetOf(p))
    }
    function sheetOf(name) { var c = Data.clips[who][name]; return c ? c.s : "" }
    function firstClip() {
        for (var i = 0; i < plan.length; i++) if (plan[i].c) return plan[i].c
        return ""
    }

    // ---------------------------------------------------------------- the next drawing (10 a second)
    // even: every other tick (Cats.qml's beat). Resting, a cat draws only then, two drawings on — its breathing as
    // fast as ever, but the screen redrawn half as often while both just rest (each new drawing repaints it all)
    function tick(even) {
        if (pend) { tryStart(); return }
        if (hidden) { if (plan.length) next(); return }
        var rest = restClip && !item
        if (rest && !even) return
        var n = cc.f.length
        if (item && item.leap && !arcA.running) { next(); return }      // landed: on at once, whatever drawing it's on
        if (item && item.early && item.until && item.until()) { next(); return }   // (a gallop can stop on any stride)
        if (fi < n - 1) {
            // resting, and something to do: start it near the bottom of a breath, once its sheet is in
            if (restClip && plan.length && fi >= (clip === pose ? n * 3 / 4 : n - 3) && ready(sheetOf(firstClip()))) { next(); return }
            fi = rest ? Math.min(fi + 2, n - 1) : fi + 1; move(); return
        }
        // this clip is done: round again, or on to what's next
        if (cc.loop && item && !doneLooping()) { fi = 0; move(); return }
        if (rests[cc.b]) pose = cc.b
        next()
    }
    function doneLooping() {
        if (item.leap) return !arcA.running
        if (item.until) return item.until()
        if (item.n !== undefined) return --item.n <= 0
        return true
    }
    function next() {
        while (plan.length && !plan[0].c) {
            var st = plan.shift()
            if (st.flip) mirror = !mirror
            if (st.call) st.call()
            if (st.face !== undefined && (st.face - ax) * dir < 0) plan.unshift({ c: "turn" }, { flip: true }, { c: "turn.back" })
            if (st.wait && !st.wait()) plan.unshift({ c: pose, early: true, until: st.wait })
        }
        if (plan.length) pend = plan.shift()
        else if (pose === "none") { hidden = true; restClip = true; item = null; return }
        else pend = { c: restName(), rest: true }
        tryStart()
    }
    function tryStart() {
        var name = pend.c, c = Data.clips[who][name]
        if (!c) { console.warn("[room] cats: no clip " + who + " " + name); pend = null; plan = []; return }
        if (!ready(c.s)) { load(c.s); return }               // (rare: hold this drawing until its sheet is in)
        restClip = !!pend.rest; item = restClip ? null : pend; pend = null
        clip = name; fi = 0; hidden = false; waiting = false
        load(c.s)                                    // (kept: used just now)
        if (item && item.leap) arc(item.leap, item.from)
        move()
        // the sheet after this one, loading while this clip plays
        var nx = firstClip() || (rests[cc.b] && cc.b !== "none" ? cc.b : pose)
        load(sheetOf(nx))
    }
    function move() {
        if (cc.dx) ax += cc.dx[fi] * k * dir
    }
    // resting: the plain breathing loop, or now and then one of its small variations
    property bool varied: false
    function restName() {
        var p = pose, vs = []
        ;["blink", "ear", "look", "tail"].forEach(function (v) { if (Data.clips[who][p + "." + v]) vs.push(p + "." + v) })
        var r = varied || !vs.length || Math.random() < 0.4 ? p : vs[Math.floor(Math.random() * vs.length)]
        varied = r !== p
        return r
    }

    // ---------------------------------------------------------------- a leap: along an arc, then it lands
    property real lx0: 0
    property real ly0: 0
    property real lx1: 0
    property real ly1: 0
    property real lh: 0
    property real lt: 0
    onLtChanged: if (arcA.running) { ax = lx0 + (lx1 - lx0) * lt; ay = ly0 + (ly1 - ly0) * lt - lh * 4 * lt * (1 - lt) }
    function arc(to, from) {
        if (from) { ax = from.x; ay = from.y }
        lx0 = ax; ly0 = ay; lx1 = to.x; ly1 = to.y
        var dx = Math.abs(lx1 - lx0), up = Math.max(0, ly0 - ly1)
        lh = 40 + 0.2 * dx + 0.35 * up           // up and over, always coming down onto where it's going
        arcA.duration = Math.min(1100, 420 + 0.45 * Math.hypot(lx1 - lx0, ly1 - ly0))
        lt = 0; arcA.restart()
    }
    NumberAnimation { id: arcA; target: cat; property: "lt"; from: 0; to: 1; easing.type: Easing.Linear
        onFinished: { cat.ax = cat.lx1; cat.ay = cat.ly1 } }
    readonly property bool flying: arcA.running
}
