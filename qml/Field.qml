import QtQuick

// The background, design "Field" (room-motion.html): the screen takes its colour from the album cover.
// room/art.py reads each cover — its four main colours, where each sits, how much of it each fills, how vivid and
// contrasty it is, which way its light falls — and here those become four soft lights over a base fill, one per
// colour, where it sits on the cover, as big as its share (560 + 1500·√share px), drifting along the cover's light
// (a loop of 14–46 s, 60–220 px: faster and further for vivid, contrasty covers). Grain over them, then a dimmer.
// No music: a warm terracotta palette. The Room screen: the room's own light. A new song's colours cross-fade (2.2 s).
// While music plays the lights swirl (as lively as the old music standby) and swell with the room's sound (the mic's
// loudness over a running quiet floor: ≤ 10 % bigger, ≤ 16 % brighter); the rest of the time they only move gently,
// so the panel looks alive, and the mic plays no part.
// All of it is one shader (shaders/field.frag), redrawn ~20 times a second — the fanless Surface stays cool.
ShaderEffect {
    id: f
    x: -40; y: -40; width: 1368 + 80; height: 912 + 80        // past the edges: the burn-in drift never shows one
    blending: false
    // drawn at the design's size (1368 × 912 and its margins) and scaled up, not at the Surface's 2736 × 1824: a
    // quarter of the work for the graphics chip (at full size it drew ~5 W). It's all soft light, and its grain is a
    // design pixel each, so it looks the same — scaled up without smoothing, to keep the grain crisp.
    layer.enabled: true
    layer.smooth: false

    property var cover: ({})            // a cover's reading (music.field)
    property string mode: "music"       // music · idle · room · weather
    property color roomColour: "#ffc98f"
    property real roomOn: 1             // the room's level, 0…1
    property real k: 1                  // the lights' size (standby: 0.75)
    property real lightA: 0.95          // the lights' strength
    property real dim: 0                // the dimmer, 0…1
    property bool active: true          // drawn and moving
    property int fps: 20
    property rect glassRect: Qt.rect(0, 0, 0, 0)
    property real glassA: 1
    property bool playing: false        // music is playing (the sound swell, the full swirl)

    readonly property var idleP: ({ cols: [[196, 106, 62], [184, 102, 74], [74, 33, 23], [138, 69, 40]],
                                    pos: [[0.15, 0.25], [0.8, 0.2], [0.7, 0.85], [0.2, 0.9]], share: [0.3, 0.3, 0.2, 0.2],
                                    dir: [0.6, 0.3], period: 46, amp: 70, base: [90, 42, 22] })
    readonly property var weatherP: ({ cols: [[111, 143, 191], [61, 82, 119], [156, 180, 214], [27, 38, 56]],
                                       pos: [[0.75, 0.2], [0.2, 0.35], [0.55, 0.75], [0.15, 0.9]], share: [0.34, 0.3, 0.2, 0.16],
                                       dir: [-0.7, 0.3], period: 44, amp: 90, base: [27, 38, 56] })
    readonly property var roomP: {
        var c = [Math.round(roomColour.r * 255), Math.round(roomColour.g * 255), Math.round(roomColour.b * 255)], on = roomOn
        return { cols: [c, c, [58, 29, 12], c], pos: [[0.82, 0.28], [0.25, 0.75], [0.6, 0.9], [0.95, 0.8]],
                 share: [0.38 * on + 0.02, 0.22 * on + 0.02, 0.15, 0.12 * on + 0.02], dir: [0.4, 0.6], period: 40, amp: 60,
                 base: [11, 7, 5] }
    }
    readonly property bool hasCover: cover && cover.cols !== undefined && cover.cols.length === 4
    readonly property var pal: mode === "room" ? roomP : mode === "weather" ? weatherP : (mode === "music" && hasCover) ? cover : idleP
    // the base: from the cover (art.base_fill: its least common colour, as room-motion.html's BG.cols[3], kept off
    // black and white), the room's dark, the sky's, terracotta
    readonly property var baseRgb: pal.base !== undefined ? pal.base : pal.cols[3]

    function rgb(a) { return Qt.rgba(a[0] / 255, a[1] / 255, a[2] / 255, 1) }
    function lightSize(i) { return (560 + 1500 * Math.sqrt(pal.share[i] !== undefined ? pal.share[i] : 0.2)) * k * (mode === "room" ? 0.9 : 1) }

    // ---------------------------------------------------------------- what the shader gets (cross-fading over 2.2 s)
    component Glide: NumberAnimation { duration: 2200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    component Shade: ColorAnimation { duration: 2200; easing.type: Easing.InOutQuad }
    property color base: rgb(baseRgb);      Behavior on base { Shade {} }
    property color c0: rgb(pal.cols[0]);      Behavior on c0 { Shade {} }
    property color c1: rgb(pal.cols[1]);      Behavior on c1 { Shade {} }
    property color c2: rgb(pal.cols[2]);      Behavior on c2 { Shade {} }
    property color c3: rgb(pal.cols[3]);      Behavior on c3 { Shade {} }
    property real x0: pal.pos[0][0] * 1368;   Behavior on x0 { Glide {} }
    property real y0: pal.pos[0][1] * 912;    Behavior on y0 { Glide {} }
    property real x1: pal.pos[1][0] * 1368;   Behavior on x1 { Glide {} }
    property real y1: pal.pos[1][1] * 912;    Behavior on y1 { Glide {} }
    property real x2: pal.pos[2][0] * 1368;   Behavior on x2 { Glide {} }
    property real y2: pal.pos[2][1] * 912;    Behavior on y2 { Glide {} }
    property real x3: pal.pos[3][0] * 1368;   Behavior on x3 { Glide {} }
    property real y3: pal.pos[3][1] * 912;    Behavior on y3 { Glide {} }
    property real d0: lightSize(0);              Behavior on d0 { Glide {} }
    property real d1: lightSize(1);              Behavior on d1 { Glide {} }
    property real d2: lightSize(2);              Behavior on d2 { Glide {} }
    property real d3: lightSize(3);              Behavior on d3 { Glide {} }
    property real la: lightA;               Behavior on la { NumberAnimation { duration: 2000 } }
    property real dirX: pal.dir[0];           Behavior on dirX { Glide {} }
    property real dirY: pal.dir[1];           Behavior on dirY { Glide {} }
    property real ampV: pal.amp;              Behavior on ampV { Glide {} }
    property bool soft: false           // waking from standby: brighten slowly, evenly
    property real dimV: dim
    Behavior on dimV { NumberAnimation { duration: f.soft ? 1600 : Theme.fadeMs; easing.type: f.soft ? Easing.InOutSine : Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    property vector4d b0: Qt.vector4d(x0, y0, d0, la)
    property vector4d b1: Qt.vector4d(x1, y1, d1, la)
    property vector4d b2: Qt.vector4d(x2, y2, d2, la)
    property vector4d b3: Qt.vector4d(x3, y3, d3, la)
    property vector2d dir: Qt.vector2d(dirX, dirY)
    property real amp: ampV
    property real dimA: dimV
    property color dimC: "#050302"
    property real grainA: 0.13
    property real glassR: 22
    property real pop: 1.45             // brighter lights pushed away from the base, so their movement shows
    Behavior on pop { NumberAnimation { duration: 1400 } }
    property vector4d glass: Qt.vector4d(glassRect.x, glassRect.y, glassRect.width, glassRect.height)
    property size size: Qt.size(width, height)
    property point origin: Qt.point(x, y)

    // ---------------------------------------------------------------- the drift (a phase, so a new loop length never jumps)
    property real ph: 0
    // the swirl's phases, each advanced on its own and kept within one turn (a single clock wrapped every few hours
    // and the lights jumped): the turn (9 s a radian), each light's circling (6–8.4 s and 7.5–9.3 s a radian), and its
    // growing and shrinking (5–7.7 s a radian) — all scaled by pace and how lively the cover is
    property real rotP: 0
    property vector4d orbX: Qt.vector4d(0, 0, 0, 0)
    property vector4d orbY: Qt.vector4d(0, 0, 0, 0)
    property vector4d brP: Qt.vector4d(0, 0, 0, 0)
    readonly property real tau: 2 * Math.PI
    function turn(v, d) { return (v + d) % tau }
    property real pace: 2.2             // everything moves 2.2× the design's speed (the design's felt too still)
    // the swirl: 0.55 while music plays moves the screen as much as the old music standby did (measured: the same
    // share of the picture changing over 6 s; the design's drift alone moved it about half as much); otherwise a
    // gentle 0.25, so the panel never looks frozen
    property real mv: playing && mode === "music" ? 0.55 : 0.25
    Behavior on mv { NumberAnimation { duration: 2200 } }
    property real t: 0
    property real last: 0
    // its own clock — or, on music standby, the drifting words' (30 a second, every other frame): two clocks out of
    // step would have doubled the redrawing, and the background's 12 a second there looked steppy next to the words
    property bool external: false
    function advance() {
        var now = Date.now() / 1000
        var dt = f.last > 0 ? Math.min(0.25, now - f.last) : 0
        f.last = now
        f.t += dt
        f.ph = (f.ph + f.pace * dt / Math.max(10, f.pal.period || 30)) % 1000
        var w = f.pace * dt * 30 / Math.max(10, f.pal.period || 30)                    // the swirl: a lively cover turns it faster
        f.rotP = f.turn(f.rotP, w / 9)
        f.orbX = Qt.vector4d(f.turn(f.orbX.x, w / 6), f.turn(f.orbX.y, w / 6.8), f.turn(f.orbX.z, w / 7.6), f.turn(f.orbX.w, w / 8.4))
        f.orbY = Qt.vector4d(f.turn(f.orbY.x, w / 7.5), f.turn(f.orbY.y, w / 8.1), f.turn(f.orbY.z, w / 8.7), f.turn(f.orbY.w, w / 9.3))
        f.brP = Qt.vector4d(f.turn(f.brP.x, w / 5), f.turn(f.brP.y, w / 5.9), f.turn(f.brP.z, w / 6.8), f.turn(f.brP.w, w / 7.7))
        // the swell eases away when the music stops (or the mic is off: the level stops arriving)
        if (!room.micOn || !f.playing) f.sound *= 0.8
    }
    Timer {
        interval: Math.round(1000 / f.fps); repeat: true
        running: f.active && f.visible && !f.external
        onTriggered: f.advance()
        onRunningChanged: f.last = 0
    }
    onExternalChanged: last = 0

    // ---------------------------------------------------------------- the room's sound
    property real sound: 0
    property real floorL: -1
    property real lastL: 0
    Connections {
        target: room
        enabled: room.micOn && f.active && f.visible && f.playing
        function onLevelChanged() {
            var l = room.level
            f.lastL = l
            if (f.floorL < 0) f.floorL = l; else f.floorL += (l - f.floorL) * (l < f.floorL ? 0.3 : 0.01)
            var raw = Math.max(0, Math.min(1, (l - f.floorL - 0.1) * 1.5))
            f.sound += (raw - f.sound) * (raw > f.sound ? 0.3 : 0.12)
        }
    }

    fragmentShader: shaderDir + "field.frag.qsb"
}
