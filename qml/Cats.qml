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
    property bool alarm: false                          // an alarm or timer's going off: they race about
    property real floorY: Theme.stageH                  // the screen's bottom edge, in the stage's coordinates
    property bool demoFast: false                       // (checks) everything happens sooner
    readonly property string where: alarm ? "alert" : !scene ? "" : scene.catSheet ? "sheet"
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
                if (c.spotId === "curve" && !c.flying) { var s = cats.spot("curve"); if (s) c.ay = s.yAt(c.ax) }
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
    function turnTo(c, x) { return (x - c.ax) * c.dir < 0 ? ["turn", { flip: true }, "turn.back"] : [] }

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
        var x = toRight ? Theme.stageW + 130 : -130
        return route(c.pose, "stand").concat(turnTo(c, x), ["run.in",
            { c: "run", early: true, until: function () { return (x - c.ax) * c.dir < 0 } },
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
        if (o.shown && o.pose !== "none") {
            var chase = o.spotId === "floor" ? runOff(o, right)
                      : o.spotId !== "below" ? leapPlan(o, f, Math.max(f.x0, Math.min(f.x1, o.ax + (right ? 120 : -120))), null).concat(runOff(o, right)) : null
            if (chase) { chaser.c = o; chaser.plan = chase; chaser.tries = 0; o.thinkAt = now + 60; chaser.restart() }
        }
        return runOff(c, right)
    }
    Timer {                                             // the other one gives chase, as soon as it's free (a moment later)
        id: chaser; property var c: null; property var plan: []; property int tries: 0; interval: 600
        onTriggered: if (c) { if (c.free()) { c.go(plan); c = null } else if (++tries < 12) restart(); else c = null }
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
        if (night) {                                        // asleep, wherever they are
            if (p === "none" && f) c.go(popUp(c, f, placeOn(f, c), "sit").concat(route("sit", "curl")))
            else if (p === "peek") c.go(["peek.down"])
            else if (p !== "curl") c.go(route(p, "curl"))
            c.thinkAt = later(30, 90); return
        }
        if (s && s.low && (p === "sit" || p === "stand")) { c.go(route(p, "loaf")); c.thinkAt = later(3, 8); return }
        if (music && (p === "sit" || p === "loaf" || p === "drape") && Math.random() < 0.35) {
            var beats = Math.round(rnd(4, 10))
            c.go([p + ".bob.in", { c: p + ".bob", until: function () { return !cats.music || --beats <= 0 } }, p + ".bob.out"])
            c.thinkAt = later(2, 6); return
        }
        var o = []
        if (calm) {                                         // Bebo
            if (p === "curl") o = [[0.45, route(p, "loaf")], [0.55, []]]
            else if (p === "loaf") o = [[0.2, ["loaf.knead.in", { c: "loaf.knead", n: Math.round(rnd(3, 7)) }, "loaf.knead.out"]], [0.08, ["loaf.roll"]],
                                        [s && s.yAt ? 0.15 : 0, along(c, s, false, "loaf")], [music ? 0.05 : 0, pushPlan(c)],
                                        [0.18, route(p, "curl")], [0.2, route(p, "sit")], [edge ? 0.12 : 0, route(p, "drape")], [0.3, []]]
            else if (p === "sit") o = [[0.15, ["sit.yawn"]], [0.2, ["sit.wash"]], [0.18, route(p, "loaf")],
                                       [0.14, along(c, s, false, pick(["sit", "loaf"]))], [0.05, elsewhere(c, s, "sit")], [0.28, []],
                                       [music ? 0.08 : 0, pushPlan(c)], [s && s.floor ? 0.04 : 0, function () { return zoomies(c) }]]
            else if (p === "drape") o = [[0.3, route(p, "loaf")], [0.1, ["drape.swat"]], [0.6, []]]
            else if (p === "stand") o = [[1, route(p, "sit")]]
            else if (p === "peek") o = [[1, f ? ["peek.down"].concat(popUp(c, f, c.ax, "sit")) : ["peek.down"]]]
            else if (p === "none") o = [[0.6, f ? popUp(c, f, placeOn(f, c), "sit") : null],
                                        [0.4, f ? runIn(c, placeOn(f, c), Math.random() < 0.5, "sit") : null]]
        } else {                                            // Evan
            var fl = s && s.floor
            if (p === "stand") o = [[0.22, along(c, s, false, null)], [0.25, elsewhere(c, s, null)], [0.1, ["stand.stretch"]],
                                    [0.16, route(p, "sit")], [fl ? 0.1 : 0, along(c, s, true, null)], [fl ? 0.12 : 0, hopDown(c)],
                                    [0.02, ["stand.startle"]], [fl ? 0.1 : 0, function () { return zoomies(c) }], [music ? 0.12 : 0, pushPlan(c)],
                                    [fl ? 0.08 : 0, function () { var x = placeOn(f, c); return Math.abs(x - c.ax) > 260 ? runPlan(c, x, null) : null }]]
            else if (p === "sit") o = [[0.3, route(p, "stand")], [0.12, ["sit.wash"]], [0.08, ["sit.yawn"]], [0.08, ["sit.swat"]],
                                       [0.12, route(p, "loaf")], [0.3, []], [fl ? 0.06 : 0, function () { return zoomies(c) }]]
            else if (p === "loaf") o = [[edge ? 0.2 : 0, route(p, "drape")], [0.1, ["loaf.knead.in", { c: "loaf.knead", n: Math.round(rnd(2, 5)) }, "loaf.knead.out"]],
                                        [0.25, route(p, "sit")], [0.07, route(p, "curl")], [0.38, []], [0.12, ["loaf.roll"]],
                                        [s && s.yAt ? 0.3 : 0, along(c, s, false, "loaf")], [music ? 0.12 : 0, pushPlan(c)]]
            else if (p === "drape") o = [[0.3, route(p, "loaf")], [0.15, ["drape.swat"]], [0.55, []], [s && s.yAt ? 0.25 : 0, along(c, s, false, "drape")]]
            else if (p === "curl") o = [[0.6, route(p, "loaf")], [0.4, []]]
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
        c.thinkAt = calm ? later(8, 22) : later(4, 12)
    }

    // ---------------------------------------------------------------- arriving on a screen
    onWhereChanged: { bebo.shown = false; evan.shown = false; arrive.restart() }
    Timer { id: arrive; interval: 1100; onTriggered: cats.place() }       // (after the screen has settled)
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
        if (c.flying || c.spotId === "below" || c.spotId === "") return
        var s = spot(c.spotId)
        if (!s) { lost(c); return }
        c.ay = yOn(s, c.ax)
        if (!c.free()) return
        var m = Math.min(28, wide(s) / 2)
        c.ax = Math.max(s.x0 + m, Math.min(s.x1 - m, c.ax))
    }
    function lost(c) {
        c.shown = false
        Qt.callLater(function () {
            var f = spot("floor")
            if (!f) return
            relost.c = c; relost.restart()
        })
    }
    Timer {
        id: relost; property var c: null; interval: 600
        onTriggered: { var f = cats.spot("floor"); if (c && f) { cats.put(c, f, cats.night ? "curl" : "sit"); c.shown = true } }
    }
    onFloorYChanged: both.forEach(function (c) { if (c.spotId === "floor" && !c.flying) c.ay = floorY })
    onNightChanged: both.forEach(function (c) { c.thinkAt = now })

    // ---------------------------------------------------------------- the assistant listening: ears up, a curious look
    onListeningChanged: hear()
    function hear() { if (listening && where !== "") both.forEach(function (c) {
        if (!c.shown || !c.free()) return
        var p = c.pose, held = { until: function () { return !cats.listening } }
        if (p === "sit" || p === "loaf" || p === "drape") { held.c = p + ".alert"; c.go([p + ".alert.in", held, p + ".alert.out"]) }
        else if (p === "stand") { held.c = "sit.alert"; c.go(["stand>sit", "sit.alert.in", held, "sit.alert.out"]) }
        else if (p === "curl") c.go(["curl.ear"])
        else if (p === "peek") c.go(["peek.look"])
    }) }

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
