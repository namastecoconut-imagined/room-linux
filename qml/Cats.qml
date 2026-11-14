import QtQuick

// Bebo and Evan, living on the panel (standby and Home for now). Two cats at most, each always on something real —
// the top of a clock number, the line the clock stands on, the top of the music card, the bottom edge of the screen
// (Scene.catSpots, read from the layout as it is) — or just below that bottom edge, out of sight, about to peek up.
// Bebo is calm: sits, washes, yawns, kneads, lies down, naps, now and then strolls along what she's on. Evan is busy:
// walks and trots along the bottom edge, leaps up onto things and down again, drapes himself over an edge and swats
// at it, stretches, hops off the bottom of the screen and peeks back up somewhere else. At night they sleep. They
// nod along to music, prick up their ears when the assistant listens, and a cat on a clock number swats it when the
// minute changes. Nothing they do changes anything in Room, and they never take a touch.
Item {
    id: cats
    width: Theme.stageW; height: Theme.stageH
    property Item scene: null
    property bool night: false
    property bool music: false                          // music playing: they nod along
    property bool listening: false                      // the assistant's listening: ears up
    property real kbTop: -1                             // the on-screen keyboard's top edge, while it's up
    property Item voice: null                           // the assistant, while it's up over everything: they sit on its line
    property bool alarm: false                          // an alarm or timer's going off: they race about
    property real floorY: Theme.stageH                  // the screen's bottom edge, in the stage's coordinates
    property bool demoFast: false                       // (checks) everything happens sooner
    readonly property string where: alarm ? "alert" : voice ? "voice" : !scene ? "" : scene.catSheet ? "sheet"
        : scene.sV ? (scene.m ? "musicstandby" : "standby") : scene.hV ? "home" : scene.pV ? "player" : scene.wV ? "weather"
        : scene.rV ? "lights" : scene.remV ? "reminders" : scene.cV ? "clock" : scene.setV ? "settings" : ""
    property var spots: []
    property real now: Date.now() / 1000

    Cat { id: bebo; who: "bebo" }
    Cat { id: evan; who: "evan" }
    readonly property var both: [bebo, evan]

    // one tick steps both cats, so the screen's redrawn once for the two of them (10 a second)
    Timer {
        interval: 100; repeat: true
        running: cats.visible && (cats.where !== "" || bebo.visible || evan.visible)
        onTriggered: {
            cats.both.forEach(function (c) {
                if (c.item && c.item.follow && cats.scene) c.ax = cats.scene.catKnob() - 64 * c.k
                if (c.spotId === "curve" && !c.flying && !(c.item && c.item.leap)) { var s = cats.spot("curve"); if (s) c.ay = s.yAt(c.ax) }
            })
            bebo.tick(); evan.tick()
        }
    }

    function rnd(a, b) { return a + Math.random() * (b - a) }
    function pick(l) { return l[Math.floor(Math.random() * l.length)] }
    function other(c) { return c === bebo ? evan : bebo }
    function later(a, b) { return now + (demoFast ? rnd(a, b) / 3 : rnd(a, b)) }

    // ---------------------------------------------------------------- where they can be
    function readSpots() {
        if (where === "alert") { spots = [{ id: "floor", x0: 80, x1: Theme.stageW - 80, floor: true }]; return }    // over everything: the bottom edge
        if (where === "voice") { spots = voice.catSpots(cats); return }
        spots = scene ? scene.catSpots() : []
        if (where === "sheet" && kbTop > 0) spots.push({ id: "kbtop", x0: 140, x1: Theme.stageW - 140, y: kbTop })
    }
    // how high s is at x (the forecast's curve rises and falls; the bottom edge is the screen's)
    function yOn(s, x) { return s.floor ? floorY : s.yAt ? s.yAt(x) : s.y }
    // the pose to rest in on s: something just above a "low" edge, so lying down there; no draping over the bottom edge
    function restFor(s, p) {
        if (s && s.low && (!p || p === "sit" || p === "stand")) return "loaf"
        if (s && s.floor && p === "drape") return "loaf"
        return p
    }
    function spot(id) {
        for (var i = 0; i < spots.length; i++) if (spots[i].id === id) {
            var s = spots[i]
            return s.floor ? { id: s.id, x0: s.x0, x1: s.x1, y: floorY, floor: true } : s
        }
        return null
    }
    function wide(s) { return s.x1 - s.x0 }
    // a place along s for cat c: inside its ends, and clear of the other cat
    function placeOn(s, c, x) {
        var m = Math.min(28, wide(s) / 2), lo = s.x0 + m, hi = s.x1 - m, o = other(c)
        if (x === undefined) x = rnd(lo, hi)
        for (var n = 0; n < 10 && o.spotId === s.id && Math.abs(o.ax - x) < 120; n++) x = rnd(lo, hi)
        return Math.max(lo, Math.min(hi, x))
    }
    function roomFor(s, c) { var o = other(c); return o.spotId !== s.id || wide(s) > 260 }

    // ---------------------------------------------------------------- getting from one pose to another
    readonly property var edges: ({ stand: { sit: "stand>sit" }, sit: { stand: "sit>stand", loaf: "sit>loaf" },
                                    loaf: { sit: "loaf>sit", curl: "loaf>curl", drape: "loaf>drape" }, curl: { loaf: "curl>loaf" },
                                    drape: { loaf: "drape>loaf" }, peek: { none: "peek.down" }, none: { peek: "peek.up" } })
    function route(a, b) {
        if (!b || a === b) return []
        var seen = {}, q = [[a, []]]; seen[a] = true
        while (q.length) {
            var cur = q.shift(), e = edges[cur[0]] || {}
            for (var t in e) {
                if (seen[t]) continue
                var p = cur[1].concat([e[t]])
                if (t === b) return p
                seen[t] = true; q.push([t, p])
            }
        }
        return []
    }
    function turnTo(c, x) { return [{ face: x }] }        // (turns round then, if it needs to: see Cat.go)

    // ---------------------------------------------------------------- plans
    function walkPlan(c, x, then) {
        return route(c.pose, "stand").concat(turnTo(c, x),
            ["walk.in", { c: "walk", until: function () { return (x - c.ax) * c.dir < 51 * c.k } }, "walk.out"], route("stand", then))
    }
    function trotPlan(c, x, then) {
        return route(c.pose, "stand").concat(turnTo(c, x),
            ["trot.in", { c: "trot", until: function () { return (x - c.ax) * c.dir < 74 * c.k } }, "trot.out"], route("stand", then))
    }
    function leapPlan(c, s, x, then) {
        return route(c.pose, "stand").concat(turnTo(c, x), ["crouch", "takeoff",
            { c: "air", leap: { x: x, y: yOn(s, x) } },
            { call: function () { c.spotId = s.id } }, "land"], route("stand", restFor(s, then)))
    }
    function hopDown(c) {                                   // off the bottom edge, out of sight
        var x = c.ax + c.dir * rnd(50, 90)
        return route(c.pose, "stand").concat(["crouch", "takeoff", { c: "air", leap: { x: x, y: floorY + 180 } },
            { call: function () { c.pose = "none"; c.spotId = "below" } }])
    }
    function popUp(c, s, x, then) {                         // from out of sight, up onto s
        var m = x > Theme.stageW / 2, fx = x + (m ? 1 : -1) * rnd(40, 80)
        return [{ call: function () { c.mirror = m } },
                { c: "air", leap: { x: x, y: yOn(s, x) }, from: { x: fx, y: floorY + 170 } },
                { call: function () { c.spotId = s.id; c.pose = "stand" } }, "land"].concat(route("stand", restFor(s, then)))
    }
    function peekPlan(c, x) {
        return [{ call: function () { c.ax = x; c.ay = floorY; c.spotId = "floor"; c.mirror = Math.random() < 0.5 } }, "peek.up"]
    }
    function along(c, s, trot, then) {                      // somewhere else along what it's on
        if (!s || wide(s) < 170) return null
        var x = placeOn(s, c)
        for (var n = 0; n < 6 && Math.abs(x - c.ax) < 90; n++) x = placeOn(s, c)
        if (Math.abs(x - c.ax) < 90) return null
        return trot ? trotPlan(c, x, then) : walkPlan(c, x, then)
    }
    function elsewhere(c, s, then) {                        // up onto (or down to) something else
        var to = spots.map(function (t) { return spot(t.id) }).filter(function (t) {
            return (!s || t.id !== s.id) && !t.use && wide(t) >= 16 && roomFor(t, c) })
        if (!to.length) return null
        var t = pick(to)
        return leapPlan(c, t, placeOn(t, c), then)
    }

    // ---------------------------------------------------------------- running
    // a gallop to x along the bottom edge, and a skid to a stop (it can stop on any stride, so it stops where it means to)
    function runPlan(c, x, then) {
        return route(c.pose, "stand").concat(turnTo(c, x), ["run.in",
            { c: "run", early: true, until: function () { return (x - c.ax) * c.dir < 64 * c.k } }, "run.out"], route("stand", then))
    }
    // off the side of the screen, out of sight
    function runOff(c, toRight) {
        var x = toRight ? Theme.stageW + 130 : -130, strides = 0
        return route(c.pose, "stand").concat(turnTo(c, x), ["run.in",
            { c: "run", early: true, until: function () { return (toRight ? c.ax > x : c.ax < x) || ++strides > 400 } },
            { call: function () { c.pose = "none"; c.spotId = "below" } }])
    }
    // in from the side of the screen, already running, to x on the bottom edge
    function runIn(c, x, fromRight, then) {
        var sx = fromRight ? Theme.stageW + 130 : -130
        return [{ call: function () { c.ax = sx; c.ay = floorY; c.mirror = fromRight; c.pose = "stand"; c.spotId = "floor" } },
                { c: "run", early: true, until: function () { return (x - c.ax) * c.dir < 64 * c.k } }, "run.out"].concat(route("stand", then))
    }
    // zoomies: one bolts off the side of the screen and the other gives chase
    function zoomies(c) {
        var f = spot("floor"); if (!f || c.spotId !== "floor") return null
        var right = c.ax < Theme.stageW / 2, o = other(c)
        if (o.shown && o.pose !== "none" && o.spotId !== "below") {
            chaser.c = o; chaser.right = right; chaser.tries = 0; o.thinkAt = now + 60; chaser.restart()
        }
        return runOff(c, right)
    }
    // the chase, worked out once the other one's free to go: from where it is by then
    function chase(o, right) {
        var f = spot("floor"); if (!f || !o.shown || o.pose === "none" || o.spotId === "below") return null
        return o.spotId === "floor" ? runOff(o, right)
             : leapPlan(o, f, Math.max(f.x0, Math.min(f.x1, o.ax + (right ? 120 : -120))), null).concat(runOff(o, right))
    }
    Timer {                                             // the other one gives chase, as soon as it's free (a moment later)
        id: chaser; property var c: null; property bool right: true; property int tries: 0; interval: 600
        onTriggered: if (c) {
            if (c.free()) { var p = cats.chase(c, right); if (p) c.go(p); c.thinkAt = cats.later(3, 7); c = null }
            else if (++tries < 12) restart(); else { c.thinkAt = cats.now; c = null }
        }
    }

    // ---------------------------------------------------------------- pushing the song along (the seek bar's playhead)
    function pushPlan(c) {
        var sk = spot("seek"); if (!sk || !scene) return null
        var behind = scene.catKnob() - 64 * c.k
        if (behind < sk.x0 + 10 || behind > sk.x1 - 120 || other(c).spotId === "seek") return null
        var pushes = Math.round(rnd(4, 9))
        var off = spots.map(function (t) { return spot(t.id) }).filter(function (t) { return t.id !== "seek" && !t.use && roomFor(t, c) })
        var to = off.length ? pick(off) : null
        return leapPlan(c, sk, behind, null).concat([{ call: function () { if (c.mirror) c.mirror = false } }, "push.in",
            { c: "push", follow: true, until: function () { return --pushes <= 0 || scene.catKnob() > sk.x1 - 30 } }, "push.out"],
            to ? leapPlan(c, to, placeOn(to, c), pick(["sit", null])) : [])          // and off again, not left standing on the words
    }

    // ---------------------------------------------------------------- an alarm going off: they race up and down
    function dash(c) {
        var x = c.ax < Theme.stageW / 2 ? rnd(Theme.stageW - 300, Theme.stageW - 110) : rnd(110, 300)
        return runPlan(c, x, null)
    }
    function alarmed(c) {
        var p = c.pose, f = spot("floor")
        if (p === "none") return runIn(c, rnd(200, Theme.stageW - 200), Math.random() < 0.5, null)
        if (p === "peek") return ["peek.down"].concat(runIn(c, rnd(200, Theme.stageW - 200), Math.random() < 0.5, null))
        if (c.spotId !== "floor") return leapPlan(c, f, placeOn(f, c), null)
        return dash(c)
    }

    // ---------------------------------------------------------------- what they do next
    function choose(c, opts) {
        var ok = opts.filter(function (o) { return o[1] !== null && o[0] > 0 }), sum = 0
        ok.forEach(function (o) { sum += o[0] })
        var r = Math.random() * sum
        for (var i = 0; i < ok.length; i++) { r -= ok[i][0]; if (r <= 0) return ok[i] }
        return ok[ok.length - 1]
    }
    function think(c) {
        var s = spot(c.spotId), p = c.pose, calm = c === bebo, edge = s && !s.floor
        var f = spot("floor")
        if (alarm) { c.go(alarmed(c)); c.thinkAt = now; return }
        if (where === "voice") { attend(c); return }
        if (night) {                                        // asleep, wherever they are
            if (p === "none" && f) c.go(popUp(c, f, placeOn(f, c), "sit").concat(route("sit", "curl")))
            else if (p === "peek") c.go(["peek.down"])
            else if (p !== "curl") c.go(route(p, "curl"))
            c.thinkAt = later(30, 90); return
        }
        if (s && s.low && (p === "sit" || p === "stand")) { c.go(route(p, "loaf")); c.thinkAt = later(3, 8); return }
        if (music && (p === "sit" || p === "loaf" || p === "drape") && Math.random() < 0.2) {
            var beats = Math.round(rnd(4, 10))
            c.go([p + ".bob.in", { c: p + ".bob", until: function () { return !cats.music || --beats <= 0 } }, p + ".bob.out"])
            c.thinkAt = later(1, 3); return
        }
        var o = []
        var fl = s && s.floor, curve = s && s.yAt
        var zoom = function () { return zoomies(c) }
        var dash = function () { if (!f) return null; var x = placeOn(f, c); return Math.abs(x - c.ax) > 260 ? runPlan(c, x, null) : null }
        if (calm) {                                         // Bebo: calmer, but up and about
            if (p === "curl") o = [[0.6, route(p, "loaf")], [0.2, elsewhere(c, s, "sit")], [0.2, []]]
            else if (p === "loaf") o = [[0.12, ["loaf.knead.in", { c: "loaf.knead", n: Math.round(rnd(3, 6)) }, "loaf.knead.out"]], [0.08, ["loaf.roll"]],
                                        [0.06, route(p, "curl")], [0.12, route(p, "sit")], [edge ? 0.08 : 0, route(p, "drape")],
                                        [0.18, along(c, s, false, "loaf")], [s && s.low ? 0.4 : 0.22, elsewhere(c, s, pick(["sit", "loaf"]))],
                                        [music ? 0.05 : 0, pushPlan(c)], [0.08, []]]
            else if (p === "sit") o = [[0.1, ["sit.yawn"]], [0.12, ["sit.wash"]], [0.1, route(p, "loaf")],
                                       [0.25, along(c, s, false, pick(["sit", "loaf"]))], [0.22, elsewhere(c, s, pick(["sit", "loaf"]))],
                                       [fl ? 0.05 : 0, zoom], [fl ? 0.05 : 0, dash], [music ? 0.06 : 0, pushPlan(c)], [0.06, []]]
            else if (p === "drape") o = [[0.25, route(p, "loaf")], [0.1, ["drape.swat"]], [0.25, elsewhere(c, s, "sit")],
                                         [curve ? 0.15 : 0, along(c, s, false, "drape")], [0.15, []]]
            else if (p === "stand") o = [[0.3, route(p, "sit")], [0.3, along(c, s, false, "sit")], [0.3, elsewhere(c, s, "sit")], [0.1, ["stand.stretch"]]]
            else if (p === "peek") o = [[1, f ? ["peek.down"].concat(popUp(c, f, c.ax, "sit")) : ["peek.down"]]]
            else if (p === "none") o = [[0.6, f ? popUp(c, f, placeOn(f, c), "sit") : null],
                                        [0.4, f ? runIn(c, placeOn(f, c), Math.random() < 0.5, "sit") : null]]
        } else {                                            // Evan: always up to something
            if (p === "stand") o = [[0.25, along(c, s, false, null)], [0.25, elsewhere(c, s, null)], [0.06, ["stand.stretch"]],
                                    [0.08, route(p, "sit")], [fl ? 0.12 : 0, along(c, s, true, null)], [fl ? 0.1 : 0, hopDown(c)],
                                    [0.02, ["stand.startle"]], [fl ? 0.1 : 0, zoom], [music ? 0.12 : 0, pushPlan(c)], [fl ? 0.12 : 0, dash]]
            else if (p === "sit") o = [[0.2, along(c, s, false, null)], [0.25, elsewhere(c, s, null)], [0.08, ["sit.wash"]], [0.05, ["sit.yawn"]],
                                       [0.06, ["sit.swat"]], [0.06, route(p, "loaf")], [fl ? 0.08 : 0, zoom], [fl ? 0.08 : 0, dash],
                                       [music ? 0.1 : 0, pushPlan(c)], [0.04, []]]
            else if (p === "loaf") o = [[edge ? 0.12 : 0, route(p, "drape")], [0.06, ["loaf.knead.in", { c: "loaf.knead", n: Math.round(rnd(2, 5)) }, "loaf.knead.out"]],
                                        [0.08, route(p, "sit")], [0.03, route(p, "curl")], [0.1, ["loaf.roll"]],
                                        [curve ? 0.2 : 0, along(c, s, false, "loaf")], [music ? 0.12 : 0, pushPlan(c)],
                                        [0.25, elsewhere(c, s, null)], [0.05, []]]
            else if (p === "drape") o = [[0.2, route(p, "loaf")], [0.15, ["drape.swat"]], [0.25, elsewhere(c, s, null)],
                                         [curve ? 0.2 : 0, along(c, s, false, "drape")], [0.1, []]]
            else if (p === "curl") o = [[0.6, route(p, "loaf")], [0.25, elsewhere(c, s, null)], [0.15, []]]
            else if (p === "peek") o = [[0.45, ["peek.down"]], [0.35, f ? ["peek.down"].concat(popUp(c, f, placeOn(f, c), null)) : null], [0.2, []]]
            else if (p === "none") {
                var ups = spots.map(function (t) { return spot(t.id) }).filter(function (t) { return !t.floor && !t.use && wide(t) >= 16 && roomFor(t, c) })
                var u = ups.length ? pick(ups) : null
                o = [[0.45, f ? peekPlan(c, placeOn(f, c)) : null], [0.2, f ? popUp(c, f, placeOn(f, c), null) : null],
                     [0.25, f ? runIn(c, placeOn(f, c), Math.random() < 0.5, null) : null],
                     [0.2, u ? popUp(c, u, placeOn(u, c), pick(["sit", "loaf", null])) : null]]
            }
        }
        var ch = o.length ? choose(c, o) : null
        if (ch && typeof ch[1] === "function") ch = [ch[0], ch[1]() || []]
        if (ch && ch[1] && ch[1].length) c.go(ch[1])
        c.thinkAt = calm ? later(3, 8) : later(2, 5)
    }

    // ---------------------------------------------------------------- arriving on a screen
    onWhereChanged: { bebo.shown = false; evan.shown = false; arrive.interval = where === "voice" ? 500 : 1100; arrive.restart() }
    Timer { id: arrive; interval: 1100; onTriggered: cats.place() }       // (after the screen has settled; the assistant: at once)
    Component.onCompleted: arrive.restart()
    function put(c, s, p) {
        c.spotId = s.id; c.ax = placeOn(s, c); c.ay = yOn(s, c.ax)
        c.settle(restFor(s, p), Math.random() < 0.5)
    }
    function place() {
        readSpots(); now = Date.now() / 1000
        var f = spot("floor")
        if (where === "standby") {
            bebo.size = 170; evan.size = 170
            var d = spots.filter(function (s) { return s.id.indexOf("digit") === 0 }).sort(function (a, b) { return wide(b) - wide(a) })
            if (d.length < 2 || !f) return
            put(bebo, d[0], night ? "curl" : pick(["sit", "loaf", "sit"]))
            if (night) put(evan, d[1], "curl")
            else if (Math.random() < 0.5) put(evan, d[1], pick(["drape", "loaf", "sit"]))
            else { evan.spotId = "below"; evan.settle("none"); evan.go(peekPlan(evan, placeOn(f, evan))) }
        } else if (where === "home") {
            bebo.size = 150; evan.size = 150
            var ct = spot("cardtop")
            var hd = spots.filter(function (s) { return s.id.indexOf("digit") === 0 }).sort(function (a, b) { return wide(b) - wide(a) })
            put(bebo, hd.length ? hd[0] : f, night ? "curl" : pick(["loaf", "drape"]))
            if (ct) put(evan, ct, night ? "curl" : pick(["drape", "loaf", "sit"]))
            else if (f) put(evan, f, night ? "curl" : "sit")
        } else if (where !== "alert" && where !== "") {
            bebo.size = 130; evan.size = 130
            var edges = spots.filter(function (s) { return !s.floor && !s.use })
            var favs = edges.filter(function (s) { return s.fav })
            var sb = favs.length ? favs[0] : edges.length ? pick(edges) : f
            if (!sb) return
            put(bebo, sb, night ? "curl" : pick(["sit", "loaf"]))
            if (sb.fav) { bebo.ax = sb.x0 + 20; bebo.mirror = true }          // a reminder about the cats: she reads it
            var more = edges.filter(function (s) { return s.id !== sb.id || wide(s) > 260 })
            var se = more.length && (Math.random() < 0.65 || !f) ? pick(more) : f
            if (se) put(evan, se, night ? "curl" : pick(["sit", "loaf", "drape"]))
            if (se === f && !night && Math.random() < 0.5) { evan.spotId = "below"; evan.settle("none"); evan.go(peekPlan(evan, placeOn(f, evan))) }
        } else if (where === "voice") {                    // onto the line of light, facing the words
            bebo.size = 130; evan.size = 130
            var ln = spot("line"); if (!ln) return
            both.forEach(function (c) {
                c.spotId = ln.id; c.ax = placeOn(ln, c); c.ay = yOn(ln, c.ax)
                c.settle(restFor(ln, night ? "curl" : "sit"), c.ax > Theme.stageW / 2)
            })
        } else if (where === "alert") {
            bebo.size = 160; evan.size = 160
            both.forEach(function (c, i) {
                c.spotId = "below"; c.settle("none")
                c.go(runIn(c, i ? rnd(700, 1000) : rnd(300, 600), i === 1, null).concat(i ? ["stand.startle"] : []))
            })
        } else return
        bebo.shown = true; evan.shown = true
        hear()
        bebo.thinkAt = later(5, 12); evan.thinkAt = later(2, 6)
    }

    // ---------------------------------------------------------------- every second: decide, keep them on their edges
    Timer {
        interval: 1000; repeat: true; running: cats.where !== "" && cats.visible
        onTriggered: {
            cats.now = Date.now() / 1000
            cats.readSpots()
            cats.both.forEach(function (c) {
                if (!c.shown) return
                cats.keepOn(c)
                if (c.free() && cats.now >= c.thinkAt) cats.think(c)
            })
        }
    }
    // the layout moved under a cat (a number changed width, the card went): back onto its edge, or somewhere else
    function keepOn(c) {
        // (and not just after a leap, before it's counted as on where it landed: it was put back on what it had
        // jumped off for up to a second — gone from where it landed, then back)
        if (c.flying || (c.item && c.item.leap) || c.spotId === "below" || c.spotId === "") return
        var s = spot(c.spotId) || under(c)          // (a number's spot can change its name as the numbers change: same place)
        if (!s) { lost(c); return }
        c.spotId = s.id
        c.ay = yOn(s, c.ax)
        if (!c.free()) return
        var m = Math.min(28, wide(s) / 2)
        c.ax = Math.max(s.x0 + m, Math.min(s.x1 - m, c.ax))
    }
    function landing() { for (var i = 0; i < spots.length; i++) if (!spots[i].use) return spot(spots[i].id); return null }
    function under(c) {
        for (var i = 0; i < spots.length; i++) {
            var t = spot(spots[i].id)
            if (!t.use && c.ax > t.x0 - 30 && c.ax < t.x1 + 30 && Math.abs(yOn(t, c.ax) - c.ay) < 40) return t
        }
        return null
    }
    function lost(c) {
        c.shown = false
        Qt.callLater(function () {
            var f = spot("floor") || landing()
            if (!f) return
            relost.c = c; relost.restart()
        })
    }
    Timer {
        id: relost; property var c: null; interval: 600
        onTriggered: { var f = cats.spot("floor") || cats.landing(); if (c && f) { cats.put(c, f, cats.night ? "curl" : "sit"); c.shown = true } }
    }
    onFloorYChanged: both.forEach(function (c) { if (c.spotId === "floor" && !c.flying && !(c.item && c.item.leap)) c.ay = floorY })
    onNightChanged: both.forEach(function (c) { c.thinkAt = now })

    // ---------------------------------------------------------------- the assistant listening: ears up, a curious look
    onListeningChanged: hear()
    function hear() { if (listening && where !== "") both.forEach(function (c) {
        if (!c.shown || !c.idle()) return
        var p = c.pose, held = { until: function () { return !cats.listening } }
        if (p === "sit" || p === "loaf" || p === "drape") { held.c = p + ".alert"; c.go([p + ".alert.in", held, p + ".alert.out"]) }
        else if (p === "stand") { held.c = "sit.alert"; c.go(["stand>sit", "sit.alert.in", held, "sit.alert.out"]) }
        else if (p === "curl") c.go(["curl.ear"])
        else if (p === "peek") c.go(["peek.look"])
    }) }

    // ---------------------------------------------------------------- the assistant's up: they attend to it
    // listening: ears up (hear, above), and they keep still. Thinking: they sit and look about (their resting
    // glances). Answering: they settle, one lies down, and Evan hops up onto the card when one comes in.
    function attend(c) {
        var s = spot(c.spotId), p = c.pose, m = voice ? voice.mode : ""
        c.thinkAt = later(1.5, 3)
        if (listening || night || !s) return
        var card = spot("cardtop")
        if (m === "speak" || m === "done") {
            if (c === evan && card && c.spotId !== "cardtop" && roomFor(card, c) && Math.random() < 0.7)
                c.go(leapPlan(c, card, placeOn(card, c), pick(["loaf", "drape", "sit"])))
            else if (p === "sit" && Math.random() < (c === bebo ? 0.5 : 0.3)) c.go(route(p, "loaf"))
            else if (p === "sit" && Math.random() < 0.2) c.go(["sit.wash"])
            c.thinkAt = later(2, 5)
        } else if (m === "miss" && (p === "sit" || p === "loaf")) {
            c.go([p + ".alert.in", { c: p + ".alert", n: 1 }, p + ".alert.out"])
        }
    }

    // ---------------------------------------------------------------- the minute changes: a cat on a number swats it
    property int minute: new Date(now * 1000).getMinutes()
    onMinuteChanged: {
        if (where !== "standby" || night) return
        Qt.callLater(function () {
            cats.readSpots()
            cats.both.forEach(function (c) { if (c.shown) cats.keepOn(c) })
            var on = cats.both.filter(function (c) { return c.shown && c.free() && c.spotId.indexOf("digit") === 0 })
            if (!on.length) return
            var c = cats.pick(on), p = c.pose
            var plan = p === "drape" ? ["drape.swat"] : p === "sit" ? ["sit.swat"] : p === "stand" ? ["stand>sit", "sit.swat"]
                     : p === "loaf" ? ["loaf.alert.in", { c: "loaf.alert", n: 1 }, "loaf.alert.out"] : p === "curl" ? ["curl.ear"] : null
            if (plan) c.go(plan)
        })
    }
}
