import QtQuick
import "scenesdata.js" as Data

// A standby scene's drawing (HANDOFF "render once, then play"; tools/scenes/bake.py made the pictures): one still
// picture, the moving pieces over it, each with a map of when its pixels appear. Drawing on is `now` going up,
// rubbing out is `now` coming down — one number into a small shader (scene.frag); nothing is drawn as paths here.
// The moving pieces only turn, slide or fade, as the prototype's do, each time `t` (seconds) steps on — Scene.qml
// steps it with the background, so nothing here keeps a clock of its own.
// front: only the pieces drawn over the cats (props.json), for the copy above them (Main.qml).
Item {
    id: sa
    width: 1368; height: 912
    property string key: ""                   // "room-night", or "" (nothing loaded: no memory used)
    property real now: 0                      // build units drawn
    property real fadeU: 0.5                  // a fill's fade (0.9 s) in build units, at this draw's pace
    property real t: 0                        // the scenery's clock, seconds
    property bool front: false
    readonly property var man: key && Data.baked[key] ? Data.baked[key] : null
    readonly property string dir: key ? Qt.resolvedUrl("../assets/scenes/" + key + "/") : ""
    // all its pictures are in (the draw waits for them: a piece arriving late would skip its part of the draw)
    readonly property bool ready: man !== null && loaded >= (front ? man.front.length : 1 + man.sprites.length)
    property int loaded: 0
    onKeyChanged: { loaded = 0; kicks = ({}) }
    visible: man !== null && now > 0

    // ---------------------------------------------------------------- the movements (index.html's keyframes)
    function swing(m) {                       // alternate, ease-in-out: 0 → 1 → 0 …
        var u = (sa.t - (m.delay || 0)) / m.dur, c = u - 2 * Math.floor(u / 2), x = c < 1 ? c : 2 - c
        return m.kind === "cloud" ? x : 0.5 - 0.5 * Math.cos(Math.PI * x)
    }
    function cycle(m) { var u = (sa.t - (m.delay || 0)) / m.dur; return u - Math.floor(u) }

    // ---------------------------------------------------------------- the cats playing with things (Cats.qml)
    // a swat: the piece swings out `amp` degrees (a curtain: leans) after `delay` s, and settles back over ~3 s
    property var kicks: ({})
    function kick(name, amp, delay) { var k = Object.assign({}, kicks); k[name] = { at: t + (delay || 0), amp: amp }; kicks = k }
    function kicked(m) {
        var k = m.name ? kicks[m.name] : null
        if (!k || t < k.at) return 0
        var e = t - k.at
        return e > 6 ? 0 : k.amp * Math.exp(-e / 1.4) * Math.sin(2 * Math.PI * e / 1.3)
    }
    // where a moth or butterfly is now (stage units), and whether it's out
    function at(name) {
        for (var i = 0; i < sprites.count; i++) {
            var it = sprites.itemAt(i)
            if (it && it.m.name === name) return { x: it.fx, y: it.fy, on: it.visible && it.opacity > 0.3 }
        }
        return null
    }

    component Layer: ShaderEffect {
        id: ly
        property var lay
        x: lay.x; y: lay.y; width: lay.w; height: lay.h
        readonly property bool ok: artImg.status === Image.Ready && mapImg.status === Image.Ready
        onOkChanged: if (ok) sa.loaded++
        Image { id: artImg; source: sa.dir + ly.lay.art; asynchronous: true; cache: false; smooth: true; visible: false }
        Image { id: mapImg; source: sa.dir + ly.lay.map; asynchronous: true; cache: false; smooth: false; visible: false }
        property variant art: artImg
        property variant map: mapImg
        property real now: sa.now
        property real fade: sa.fadeU
        property real tmax: sa.man ? sa.man.tmax : 12
        visible: ok
        fragmentShader: shaderDir + "scene.frag.qsb"
    }

    Repeater {
        model: sa.man && !sa.front ? [sa.man.base] : []
        Layer { lay: modelData }
    }
    Repeater {
        id: sprites
        model: sa.man && !sa.front ? sa.man.sprites : []
        Layer {
            id: sp
            readonly property var m: modelData
            readonly property real fx: interp.x
            readonly property real fy: interp.y
            readonly property real kk: sa.kicked(m)
            lay: modelData
            readonly property real ox: (m.origin ? m.origin[0] : m.x + m.w / 2) - m.x
            readonly property real oy: (m.origin ? m.origin[1] : m.y + m.h / 2) - m.y
            readonly property real s: m.kind === "path" ? 0 : sa.swing(m)
            opacity: m.kind === "tw" ? 1 - 0.75 * s : m.kind === "breathe" ? 0.7 + 0.3 * s
                   : m.kind === "blink" ? (sa.cycle(m) < 0.5 ? 1 : 0.15)
                   : m.kind === "lit" ? (sa.cycle(m) < 0.62 || sa.cycle(m) >= 0.84 ? 1 : 0)
                   : m.kind === "path" ? path.fadeNow : 1
            transform: [
                Scale { origin.x: 60; origin.y: 60; xScale: sp.m.kind === "path" && sp.m.flap ? path.flapNow : 1 },
                Rotation { origin.x: sp.ox; origin.y: sp.oy
                           angle: sp.m.kind === "sway" ? -5 + 10 * sp.s + sp.kk : sp.m.kind === "sway2" ? -2.2 + 4.4 * sp.s + sp.kk
                                : sp.m.kind === "spin" ? 360 * sa.cycle(sp.m) : sp.m.kind === "path" && sp.m.rotate ? path.angle : 0 },
                Matrix4x4 {                          // the curtains: a sideways lean from the rail
                    readonly property real k: sp.m.kind === "curt" ? Math.tan((-1.6 + 3.2 * sp.s + sp.kk) * Math.PI / 180) : 0
                    matrix: Qt.matrix4x4(1, k, 0, -k * sp.oy, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                },
                Translate { x: sp.m.kind === "swim" ? -9 + 18 * sp.s : sp.m.kind === "cloud" ? -70 + 180 * sp.s
                               : sp.m.kind === "path" ? path.px - 60 - sp.m.x : 0
                            y: sp.m.kind === "path" ? path.py - 60 - sp.m.y : 0 }
            ]
            // a moth, a butterfly or the falling leaf: along its path (SMIL animateMotion), from its start time
            QtObject {
                id: path
                readonly property real u: sp.m.kind === "path" ? (sa.t - (sp.m.delay || 0)) / sp.m.dur : 0
                readonly property real p: u - Math.floor(u)
                readonly property real px: interp.x
                readonly property real py: interp.y
                readonly property real angle: interp.angle
                readonly property real flapNow: { if (!sp.m.flap) return 1; var f = sa.t / sp.m.flap.dur; f -= Math.floor(f); return 1 - 0.75 * (f < 0.5 ? 2 * f : 2 - 2 * f) }
                readonly property real fadeNow: {
                    if (sp.m.kind !== "path") return 1
                    if (u < 0) return 0
                    var f = sp.m.fade; if (!f) return 1
                    for (var i = 1; i < f.times.length; i++) if (p <= f.times[i])
                        return f.values[i - 1] + (f.values[i] - f.values[i - 1]) * (p - f.times[i - 1]) / Math.max(1e-6, f.times[i] - f.times[i - 1])
                    return f.values[f.values.length - 1]
                }
            }
            PathInterpolator {
                id: interp
                progress: sp.m.kind === "path" ? path.p : 0
                path: Path { PathSvg { path: sp.m.kind === "path" ? sp.m.path : "M0,0 L1,0" } }
            }
        }
    }
    Repeater {
        model: sa.man && sa.front ? sa.man.front : []
        Layer { lay: modelData }
    }
}
