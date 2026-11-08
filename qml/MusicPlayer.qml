import QtQuick
import QtQuick.Shapes

// The music player — the iPhone panel's MusicScreen at Surface scale (×2.6 on the 568 × 320 phone layout).
// The cover is the controller (Car Thing + cover flow): tap it to pause, swipe it to skip, slide up or down anywhere
// for volume. The song's progress runs round the cover's edge; a glow in its colour pulses behind it to the beat.
// Laid out for the Surface's wider screen: the cover in its ring on the left with the equaliser and speaker under it;
// on the right the song (and like), what's next (tap to skip to it) and the controls. Top: back, library.
Item {
    id: mp
    width: Theme.stageW; height: Theme.stageH
    property real now: Date.now() / 1000
    property var music: room.music
    readonly property bool spotify: music.source !== "airplay"
    readonly property var nextUp: music.nextUp || []
    readonly property var recent: music.recent || []
    signal back()
    property bool picking: false
    property bool library: false

    // ---------------------------------------------------------------- geometry (stage px)
    // the grid: 64 px margins; cover column 64–648 (the ring's box), info column 720–1304; content between y 152 and 848
    readonly property real cx: 356                  // cover centre
    readonly property real cy: 444
    readonly property real cs: 540                  // cover size
    readonly property real ringPad: 22              // the ring runs this far outside the cover
    readonly property real ringR: 56                // ring corner radius
    readonly property real col: 720                 // the info column
    readonly property real colR: 1304
    readonly property real rw: cs + 2 * ringPad     // ring box
    readonly property real ringL: 4 * (rw - 2 * ringR) + 2 * Math.PI * ringR

    // ---------------------------------------------------------------- the beat (as on the phone)
    // The room's sound drives it when the mic is on; otherwise, while music plays, it sits at a steady 0.5 and the
    // equaliser's own wave keeps it alive. Quick to rise, slower to fall, eased every frame.
    property real beatNow: 0
    property real beatFloor: -1
    property real beatV: 0
    readonly property real beatTarget: music.playing ? (room.micOn ? beatV : 0.5) : 0
    Connections {
        target: room
        enabled: room.micOn && mp.visible
        function onLevelChanged() {
            var l = room.level
            if (mp.beatFloor < 0) mp.beatFloor = l
            else mp.beatFloor += (l - mp.beatFloor) * (l < mp.beatFloor ? 0.2 : 0.02)
            var target = Math.max(0, Math.min(1, (l - mp.beatFloor) * 5))
            mp.beatV += (target - mp.beatV) * (target > mp.beatV ? 0.8 : 0.3)
        }
    }
    FrameAnimation {
        running: mp.visible && (music.playing || mp.beatNow > 0.002)
        onTriggered: {
            var k = mp.beatTarget > mp.beatNow ? 0.32 : 0.1
            mp.beatNow += (mp.beatTarget - mp.beatNow) * Math.min(1, k * Math.min(0.05, frameTime) * 60)
        }
    }

    // ---------------------------------------------------------------- song position
    property real seekDrag: -1
    // after a seek, hold the new place until the player reports it (Spotify takes a second or two) — no jumping back
    property real seekTo: -1
    property real seekAt: 0
    readonly property real livePos: music.exists ? Math.min(music.duration || 0, (music.position || 0) + (music.playing ? now - music.at : 0)) : 0
    readonly property real pos: seekTo >= 0 && now - seekAt < 4 && Math.abs(livePos - (seekTo + (music.playing ? now - seekAt : 0))) > 2
                                ? Math.min(music.duration || 0, seekTo + (music.playing ? now - seekAt : 0)) : livePos
    function seekTo_(sec) { seekTo = sec; seekAt = now; room.seek(sec) }
    readonly property real f: seekDrag >= 0 ? seekDrag : (music.duration > 0 ? pos / music.duration : 0)

    // ---------------------------------------------------------------- volume (slide anywhere)
    property real volDrag: -1                        // 0…1 while sliding
    readonly property bool sliding: volDrag >= 0
    Timer { id: volSend; interval: 500; onTriggered: room.setVolume(Math.round(mp.volDrag * 100)) }

    // ---------------------------------------------------------------- cover flow
    property real flowDx: 0
    property string flyArt: ""                       // the cover that's flying in while the skip happens
    property real flyUntil: 0

    // ================================================================= background
    // the phone's wash: the cover shrunk to 6 × 4 pixels (saturated, darkened) and stretched smoothly over the
    // screen, so it's the cover's colours as soft light; crossfades when the song changes
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.rgb(music.rgb2 || [30, 28, 26]) }
            GradientStop { position: 1; color: Theme.rgb(music.rgb2 || [30, 28, 26]) }
        }
        visible: !(music.wash)
    }
    Repeater {
        id: washRep
        model: 2   // two layers so a new wash fades in over the old one
        Image {
            anchors.fill: parent
            property string url: ""
            source: url
            smooth: true; mipmap: false
            fillMode: Image.Stretch
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
        }
    }
    property int washSlot: 0
    property string washShown: ""
    function showWash() {
        var w = music.exists ? (music.wash || "") : ""
        var layers = [washRep.itemAt(0), washRep.itemAt(1)]
        if (!layers[0] || !layers[1] || w === washShown) return
        washShown = w
        washSlot = 1 - washSlot
        layers[washSlot].url = w
        layers[washSlot].opacity = w ? 1 : 0
        layers[1 - washSlot].opacity = 0
    }
    onMusicChanged: showWash()
    Component.onCompleted: showWash()
    // the phone's dim: darker to the right, where the controls are
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.64) }
        }
    }
    // the glow in the cover's colour, pulsing with the beat
    Shape {
        id: glow
        width: 1500; height: 1500
        x: mp.cx - width / 2; y: mp.cy - height / 2
        scale: 0.94 + 0.3 * mp.beatNow
        opacity: music.playing ? 0.62 + 0.38 * mp.beatNow : 0
        Behavior on opacity { enabled: !music.playing; NumberAnimation { duration: 600 } }
        preferredRendererType: Shape.CurveRenderer
        readonly property color c: Theme.rgb(music.rgb || [200, 185, 163])
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 750; centerY: 750; centerRadius: 750; focalX: 750; focalY: 750
                GradientStop { position: 0.0; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0.95) }
                GradientStop { position: 0.34; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0.7) }
                GradientStop { position: 0.54; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0.28) }
                GradientStop { position: 0.72; color: Qt.rgba(glow.c.r, glow.c.g, glow.c.b, 0) }
            }
            PathRectangle { x: 0; y: 0; width: 1500; height: 1500; radius: 750 }
        }
    }

    // ================================================================= gestures (under the buttons)
    // Where a drag starts and which way it goes decides what it does: along the bottom strip → seek; mostly
    // vertical → volume; mostly sideways → cover flow. A tap on the cover plays/pauses; a tap on the strip seeks.
    MouseArea {
        id: pad
        anchors.fill: parent
        preventStealing: true
        property string mode: ""
        property real x0: 0
        property real y0: 0
        property real v0: 0
        function inSeek(x, y) { return x >= mp.cx - mp.rw / 2 && x <= mp.cx + mp.rw / 2 && y >= mp.cy + mp.rw / 2 - 30 && y <= mp.cy + mp.rw / 2 + 82 }
        function seekF(x) { return Math.max(0, Math.min(1, (x - (mp.cx - mp.cs / 2)) / mp.cs)) }
        onPressed: (e) => { mode = ""; x0 = e.x; y0 = e.y }
        onPositionChanged: (e) => {
            var dx = e.x - x0, dy = e.y - y0
            if (mode === "" && Math.abs(dx) + Math.abs(dy) > 14) {
                if (inSeek(x0, y0)) mode = music.duration > 0 && music.canSeek ? "seek" : "none"   // never volume by accident
                else if (Math.abs(dy) >= Math.abs(dx)) { mode = "vol"; v0 = (music.volume || 0) / 100 }
                else mode = "flow"
            }
            if (mode === "seek") mp.seekDrag = seekF(e.x)
            else if (mode === "vol") { mp.volDrag = Math.max(0, Math.min(1, v0 - dy / 572)); if (!volSend.running) volSend.start() }
            else if (mode === "flow") mp.flowDx = dx
        }
        onReleased: (e) => {
            var dx = e.x - x0
            if (mode === "seek") { mp.seekTo_(seekF(e.x) * music.duration); mp.seekDrag = -1 }
            else if (mode === "vol") { volSend.stop(); room.setVolume(Math.round(mp.volDrag * 100)); mp.volDrag = -1 }
            else if (mode === "flow") mp.flowEnd(dx)
            else if (mode === "") {
                // a tap
                if (inSeek(e.x, e.y)) { if (music.duration > 0 && music.canSeek) mp.seekTo_(seekF(e.x) * music.duration) }
                else if (Math.abs(e.x - mp.cx) < mp.cs / 2 && Math.abs(e.y - mp.cy) < mp.cs / 2) room.playPause()
            }
            mode = ""
        }
        onCanceled: { mode = ""; mp.seekDrag = -1; mp.volDrag = -1; mp.flowDx = 0 }
    }

    // A swipe past 180 px (or a button) skips: the cover flies the way it was pushed and the next one comes in
    // from the other side.
    function flowEnd(dx) {
        var dir = dx < -180 ? 1 : dx > 180 ? -1 : 0
        if (dir === 0 || !music.exists) { flyBack.start(); return }
        skip(dir)
    }
    function skip(dir) {
        var nx = nextUp.length ? nextUp[0] : null, pv = recent.length ? recent[0] : null
        var art = dir > 0 ? (nx ? nx.art : "") : (pv ? pv.art : "")
        flyArt = art || music.art || ""
        flyUntil = now + 5
        flyOut.to = dir > 0 ? -820 : 820
        flyIn.from = dir > 0 ? 300 : -300
        fly.start()
        if (dir > 0) room.next(); else room.previous()
    }
    NumberAnimation { id: flyBack; target: mp; property: "flowDx"; to: 0; duration: 280; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: fly
        NumberAnimation { id: flyOut; target: mp; property: "flowDx"; duration: 280; easing.type: Easing.InCubic }
        PropertyAction { target: mp; property: "flowDx"; value: 0 }
        NumberAnimation { id: flyIn; target: mp; property: "flowDx"; to: 0; duration: 320; easing.type: Easing.OutCubic }
    }
    Connections { target: mp; function onMusicChanged() { if (mp.flyArt && mp.music.art === mp.flyArt) mp.flyArt = "" } }

    // ================================================================= the covers
    readonly property bool fade: sliding
    // the cover, with a soft shadow under it
    Item {
        id: box
        width: mp.cs; height: mp.cs
        x: mp.cx - mp.cs / 2 + mp.flowDx; y: mp.cy - mp.cs / 2
        rotation: mp.flowDx / 104
        opacity: Math.max(0.35, 1 - Math.abs(mp.flowDx) / 1040)
        Rectangle {
            x: -6; y: 50; width: parent.width + 12; height: parent.height - 30
            radius: 52; color: Qt.rgba(0, 0, 0, 0.4)
        }
        Cover {
            anchors.fill: parent
            radius: 40
            source: mp.flyArt && mp.now < mp.flyUntil ? mp.flyArt : (music.exists ? (music.art || "") : "")
            rgb: music.rgb || [200, 185, 163]; rgb2: music.rgb2 || [44, 40, 34]
            opacity: music.exists ? 1 : 0.3
        }
    }

    // the progress ring, traced clockwise from the top middle
    Item {
        id: ring
        x: mp.cx - mp.rw / 2; y: mp.cy - mp.rw / 2; width: mp.rw; height: mp.rw
        opacity: mp.fade ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }
        readonly property real w: mp.rw
        readonly property real r: mp.ringR
        readonly property string path: {
            var w = ring.w, r = ring.r
            return "M " + w / 2 + " 0 L " + (w - r) + " 0 A " + r + " " + r + " 0 0 1 " + w + " " + r +
                   " L " + w + " " + (w - r) + " A " + r + " " + r + " 0 0 1 " + (w - r) + " " + w +
                   " L " + r + " " + w + " A " + r + " " + r + " 0 0 1 0 " + (w - r) +
                   " L 0 " + r + " A " + r + " " + r + " 0 0 1 " + r + " 0 Z"
        }
        Shape {
            anchors.fill: parent
            ShapePath { strokeColor: Qt.rgba(1, 1, 1, 0.22); strokeWidth: 7; fillColor: "transparent"; PathSvg { path: ring.path } }
        }
        Shape {
            anchors.fill: parent
            visible: music.exists && mp.f > 0.001
            ShapePath {
                strokeColor: Theme.tx; strokeWidth: 7; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                // one dash as long as the progress, then a gap longer than the whole ring (in stroke widths)
                dashPattern: [Math.max(0.01, mp.f * mp.ringL / 7), mp.ringL]
                PathSvg { path: ring.path }
            }
        }
        // the head: a white dot with an amber halo that pulses while playing
        Item {
            visible: music.exists
            readonly property point pt: mp.ringPoint(mp.f * mp.ringL)
            x: pt.x; y: pt.y
            Rectangle {
                id: halo
                width: 58; height: 58; radius: 29; x: -29; y: -29; color: Theme.accent
                property real v: 0.5
                opacity: music.playing ? v : 0.5
                SequentialAnimation on v {
                    running: music.playing && mp.visible; loops: Animation.Infinite
                    NumberAnimation { from: 0.25; to: 0.75; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.75; to: 0.25; duration: 1200; easing.type: Easing.InOutSine }
                }
            }
            Rectangle { width: 26; height: 26; radius: 13; x: -13; y: -13; color: "white" }
        }
    }
    // the point `len` along the ring (same segments as the phone's ringPoint)
    function ringPoint(len) {
        var w = rw, r = ringR, s = w - 2 * r, q = Math.PI * r / 2
        var l = Math.max(0, Math.min(ringL, len))
        var segs = [
            [s / 2, function (d) { return Qt.point(w / 2 + d, 0) }],
            [q, function (d) { var a = -Math.PI / 2 + d / r; return Qt.point(w - r + r * Math.cos(a), r + r * Math.sin(a)) }],
            [s, function (d) { return Qt.point(w, r + d) }],
            [q, function (d) { var a = d / r; return Qt.point(w - r + r * Math.cos(a), w - r + r * Math.sin(a)) }],
            [s, function (d) { return Qt.point(w - r - d, w) }],
            [q, function (d) { var a = Math.PI / 2 + d / r; return Qt.point(r + r * Math.cos(a), w - r + r * Math.sin(a)) }],
            [s, function (d) { return Qt.point(0, w - r - d) }],
            [q, function (d) { var a = Math.PI + d / r; return Qt.point(r + r * Math.cos(a), r + r * Math.sin(a)) }],
            [s / 2, function (d) { return Qt.point(r + d, 0) }]
        ]
        for (var i = 0; i < segs.length; i++) { if (l <= segs[i][0]) return segs[i][1](l); l -= segs[i][0] }
        return Qt.point(w / 2, 0)
    }

    // ================================================================= under the cover: equaliser and speaker
    // the dot equaliser: 7 columns × 5 dots, about 12 steps a second, each column following the beat with a bit of
    // its own life, up to two dots per step; the top lit dot is amber
    Item {
        id: eq
        x: 64; y: 848 - height; width: 6 * 28 + 12; height: 4 * 16 + 12
        opacity: mp.fade ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }
        property var levels: [0, 0, 0, 0, 0, 0, 0]
        Timer {
            interval: 83; repeat: true
            running: mp.visible && (music.playing || eq.levels.some(function (n) { return n > 0 }))
            onTriggered: {
                var t = Date.now() / 1000, v = music.playing ? mp.beatNow : 0, out = []
                for (var c = 0; c < 7; c++) {
                    var wave = 0.55 + 0.25 * Math.sin(t * (1.6 + c * 0.37) + c * 1.7) + 0.2 * Math.random()
                    var want = v <= 0 ? 0 : Math.max(1, Math.round(v * 5 * wave))
                    var cur = eq.levels[c]
                    out.push(want > cur ? Math.min(want, cur + 2) : want < cur ? Math.max(want, cur - 2) : cur)
                }
                eq.levels = out
            }
        }
        Repeater {
            model: 35
            Rectangle {
                readonly property int c: Math.floor(index / 5)
                readonly property int r: index % 5
                readonly property int n: eq.levels[c]
                x: c * 28; y: (4 - r) * 16
                width: 12; height: 12; radius: 6
                color: r < n ? (r === n - 1 ? Theme.accent : Theme.tx) : Qt.rgba(0.96, 0.95, 0.94, 0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }
    // the speaker — tap it to move the music somewhere else; right edge of the cover column
    Press {
        x: 648 - width; y: 848 - height + 18; width: spk.implicitWidth + 62; height: 64; pressScale: 0.97
        opacity: mp.fade ? 0 : 1
        enabled: mp.spotify
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 24; color: Qt.rgba(0.96, 0.95, 0.94, 0.65) }
        T {
            id: spk; x: 46; anchors.verticalCenter: parent.verticalCenter
            text: music.exists && music.device ? "on " + music.device.toLowerCase() + "  ›" : "Choose a speaker  ›"
            font.pixelSize: 24; color: Qt.rgba(0.96, 0.95, 0.94, 0.65)
        }
        onTapped: { room.refreshDevices(); mp.picking = true }
    }

    // ================================================================= top: back, library
    RoundBtn { x: 28; y: 28; size: 96; iconSize: 36; icon: "back"; fill: "transparent"; opacity: mp.fade ? 0 : 1; onTapped: mp.back() }
    RoundBtn { x: 1368 - 28 - 96; y: 28; size: 96; iconSize: 36; icon: "lib"; fill: "transparent"; opacity: mp.fade ? 0 : 1; onTapped: mp.library = true }

    // ================================================================= right: the song, what's next, the controls
    Item {
        id: info
        x: mp.col; y: 0; width: mp.colR - mp.col; height: parent.height
        opacity: mp.fade ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }

        T {
            y: 160; width: parent.width - 100
            text: !music.exists ? "Nothing playing" : (music.context ? "PLAYING FROM · " + music.context.toUpperCase() : (mp.spotify ? "SPOTIFY" : (music.device || "").toUpperCase()))
            font.pixelSize: 15; font.letterSpacing: 2.4; color: Qt.rgba(0.96, 0.95, 0.94, 0.55)
        }
        T {
            x: -2; y: 186; width: parent.width - 100
            text: music.exists ? music.title : "Nothing playing"
            font.pixelSize: 68; font.weight: Font.Medium; font.letterSpacing: -0.6
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 44
        }
        // like, beside the title
        RoundBtn {
            x: parent.width - 80; y: 196; size: 80; iconSize: 32
            visible: music.exists && mp.spotify && music.liked !== null && music.liked !== undefined
            icon: music.liked ? "heartOn" : "heart"; fill: "transparent"
            ink: music.liked ? Theme.accent : Theme.tx
            onTapped: room.toggleLiked()
        }
        T {
            y: 270; width: parent.width
            text: music.exists ? music.artist : (music.error || (music.enabled ? "Pick a playlist in your library" : "Spotify isn’t linked yet"))
            font.pixelSize: 30; color: Qt.rgba(0.96, 0.95, 0.94, 0.65)
        }
        T {
            y: 316; visible: music.exists && music.duration > 0
            text: Theme.mmss(mp.f * music.duration) + "  ·  -" + Theme.mmss(music.duration - mp.f * music.duration)
            font.pixelSize: 22; color: Qt.rgba(0.96, 0.95, 0.94, 0.45)
        }

        // up next: tap one to skip straight to it
        Rectangle { y: 384; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1); visible: nextUp.length > 0 }
        T {
            y: 408; visible: nextUp.length > 0
            text: "UP NEXT"; font.pixelSize: 15; font.letterSpacing: 2.4; color: Qt.rgba(0.96, 0.95, 0.94, 0.55)
        }
        Column {
            y: 442; width: parent.width; spacing: 12
            Repeater {
                model: nextUp.slice(0, 4)
                Press {
                    width: info.width; height: 56; pressScale: 0.98
                    Cover { width: 56; height: 56; radius: 12; source: modelData.art || ""; rgb: [[110, 138, 138], [140, 94, 78], [122, 106, 140], [94, 140, 132]][index % 4]; rgb2: [30, 28, 26] }
                    T { x: 76; y: 3; width: parent.width - 76; text: modelData.title; font.pixelSize: 22 }
                    T { x: 76; y: 31; width: parent.width - 76; text: modelData.artist || ""; font.pixelSize: 17; color: Qt.rgba(0.96, 0.95, 0.94, 0.65) }
                    onTapped: { for (var i = 0; i <= index; i++) room.next() }
                }
            }
        }

        // previous · play · next, centred in the column with equal gaps, on the bottom line
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 848 - 116; height: 116; spacing: 68
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 88; iconSize: 30; icon: "prev"; fill: Qt.rgba(1, 1, 1, 0.09); onTapped: mp.skip(-1) }
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 116; iconSize: 40; icon: music.playing ? "pause" : "play"; fill: Theme.tx; ink: "black"; onTapped: room.playPause() }
            RoundBtn { anchors.verticalCenter: parent.verticalCenter; size: 88; iconSize: 30; icon: "next"; fill: Qt.rgba(1, 1, 1, 0.09); onTapped: mp.skip(1) }
        }
    }

    // ================================================================= the volume fader (shows while you slide)
    Item {
        anchors.fill: parent
        opacity: mp.sliding ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.2) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
        DotText {
            x: 1080; y: 331; pitch: 26; glide: 0
            text: "" + Math.round(Math.max(0, mp.volDrag) * 100)
        }
        T {
            x: 1080; y: 524; width: 190; wrapMode: Text.WordWrap
            text: ("volume" + (music.device ? " · " + music.device.toLowerCase() : "")).toUpperCase()
            font.pixelSize: 24; font.letterSpacing: 1.6; color: Qt.rgba(0.96, 0.95, 0.94, 0.6)
        }
        Rectangle {
            x: 1290; y: 76; width: 46; height: 760; radius: 23; clip: true
            color: Qt.rgba(1, 1, 1, 0.14)
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; radius: 23
                height: parent.height * Math.max(0, mp.volDrag)
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ffe2c4" }
                    GradientStop { position: 1; color: "#d9a37c" }
                }
            }
        }
    }

    // ================================================================= sheets
    SpeakerPicker {
        anchors.fill: parent
        open: mp.picking
        devices: music.devices || []
        onClose: mp.picking = false
        onPick: (id) => { room.transfer(id); mp.picking = false }
    }
    Library {
        anchors.fill: parent
        open: mp.library
        playlists: music.playlists || []
        onClose: mp.library = false
        onPlay: (uri) => { room.playUri(uri); mp.library = false }
    }
}
