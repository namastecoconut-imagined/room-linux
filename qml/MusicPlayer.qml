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
    property bool library: startScreen === "musiclib"         // (checks: opened by name)

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
    FrameAnimation {                                 // in step with the screen (a timer made it judder)
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

    // ---------------------------------------------------------------- volume (the slider at the bottom right)
    property real volDrag: -1                        // 0…1 while sliding
    readonly property bool sliding: volDrag >= 0
    Timer { id: volSend; interval: 80; onTriggered: room.setVolumeLive(Math.round(mp.volDrag * 100)) }

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
            Behavior on opacity { NumberAnimation { duration: 1100; easing.type: Easing.InOutQuad } }
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
    Component.onCompleted: { showWash(); if (startScreen === "musicspk") picking = true }
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
        property color c: Theme.rgb(music.rgb || [200, 185, 163])
        Behavior on c { ColorAnimation { duration: 1100; easing.type: Easing.InOutQuad } }      // the new song's colour eases in
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
    // A sideways drag on the cover skips (even a small one); a tap on the cover plays/pauses. No seeking and no
    // up-and-down volume here — they got in the way of the swipe; volume has its own slider, bottom right.
    MouseArea {
        id: pad
        anchors.fill: parent
        preventStealing: true
        property string mode: ""
        property real x0: 0
        property real y0: 0
        property real t0: 0
        onPressed: (e) => { mode = ""; x0 = e.x; y0 = e.y; t0 = Date.now() }
        onPositionChanged: (e) => {
            var dx = e.x - x0, dy = e.y - y0
            if (mode === "" && Math.abs(dx) + Math.abs(dy) > 10) {
                if (Math.abs(dy) > Math.abs(dx) * 1.6) mode = "none"     // clearly up/down: nothing
                else { mode = "flow"; x0 = e.x - (dx > 0 ? 4 : -4) }     // follow from here, without a jump
            }
            if (mode === "flow") mp.flowDx = e.x - x0
        }
        onReleased: (e) => {
            var dx = e.x - x0
            if (mode === "flow") mp.flowEnd(dx, Date.now() - t0)
            else if (mode === "") {
                // a tap on the cover: play / pause
                if (Math.abs(e.x - mp.cx) < mp.cs / 2 && Math.abs(e.y - mp.cy) < mp.cs / 2) room.playPause()
            }
            mode = ""
        }
        onCanceled: { mode = ""; mp.flowDx = 0 }
    }

    // A swipe past 180 px (or a button) skips: the cover flies the way it was pushed and the next one comes in
    // from the other side.
    function flowEnd(dx, ms) {
        // even a small swipe skips (asked for: the cover is a small target in the part of the screen that answers)
        var far = Math.abs(dx) > 36
        var dir = !far ? 0 : dx < 0 ? 1 : -1
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
    readonly property bool fade: false
    // the cover, with a soft shadow under it
    Item {
        id: box
        width: mp.cs; height: mp.cs
        x: mp.cx - mp.cs / 2 + mp.flowDx; y: mp.cy - mp.cs / 2
        rotation: mp.flowDx / 104
        opacity: Math.max(0.35, 1 - Math.abs(mp.flowDx) / 1040)
        // drawn once into a texture and then only moved, turned and faded while it's swiped — the rounded-corner
        // effect isn't redone every frame, so the cover keeps up with the finger
        layer.enabled: true
        layer.smooth: true
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
        opacity: 1
        // a new song's words fade in, rather than snapping
        property string song: music.title || ""
        onSongChanged: infoIn.restart()
        NumberAnimation { id: infoIn; target: info; property: "opacity"; from: 0.15; to: 1; duration: 900; easing.type: Easing.OutQuad }
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
        // the head: a small dot — the ring only shows where the song is (it isn't a control: seeking is off, it got in
        // the way of swiping the cover)
        Item {
            visible: music.exists
            readonly property point pt: mp.ringPoint(mp.f * mp.ringL)
            x: pt.x; y: pt.y
            Rectangle { width: 14; height: 14; radius: 7; x: -7; y: -7; color: "white" }
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
            // the arrow only where tapping does something (AirPlay's speaker is chosen on the phone)
            text: (music.exists && music.device ? "on " + music.device.toLowerCase() : "Choose a speaker") + (mp.spotify ? "  ›" : "")
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
        // like — up in the top bar, beside the library (the title's band doesn't take touch)
        RoundBtn {
            x: 1368 - 28 - 96 - 96 - mp.col; y: 28; size: 96; iconSize: 34
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
            y: 332; visible: music.exists && music.duration > 0
            text: Theme.mmss(mp.f * music.duration) + "  ·  -" + Theme.mmss(music.duration - mp.f * music.duration)
            font.pixelSize: 22; color: Qt.rgba(0.96, 0.95, 0.94, 0.45)
        }

        // up next: tap one to skip straight to it (under the thin strip, which holds just its label)
        T {
            y: Theme.capY; visible: nextUp.length > 0
            text: "UP NEXT"; font.pixelSize: 15; font.letterSpacing: 2.4; color: Qt.rgba(0.96, 0.95, 0.94, 0.55)
        }
        Column {
            y: Theme.deadB1 + 10; width: parent.width; spacing: 12
            Repeater {
                model: nextUp.slice(0, 2)
                Press {
                    width: info.width; height: 64; pressScale: 0.98
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

    // ================================================================= the swipe hint: two quiet arrows just outside the cover,
    // level with its lower part (where the screen answers) — nothing drawn over the art
    Repeater {
        model: [-1, 1]
        Icon {
            visible: music.exists
            name: modelData < 0 ? "back" : "chev"
            size: 30
            color: Qt.rgba(1, 1, 1, 0.45)
            x: mp.cx + modelData * (mp.rw / 2 + 4) - (modelData < 0 ? 30 : 0) + (modelData < 0 ? -2 : 2)
            y: mp.cy + mp.cs / 2 - 150
            opacity: Math.abs(mp.flowDx) > 4 ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    // ================================================================= volume: a slider at the bottom right
    Item {
        id: vol
        x: mp.col; y: 664; width: mp.colR - mp.col; height: 56
        visible: music.exists
        readonly property real v: mp.sliding ? mp.volDrag : (music.volume || 0) / 100
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 22; color: Qt.rgba(0.96, 0.95, 0.94, 0.65) }
        Item {
            id: track
            x: 44; width: parent.width - 44 - 64; height: parent.height
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.16) }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * vol.v; height: 6; radius: 3; color: Theme.tx }
            Rectangle {
                x: parent.width * vol.v - 14; anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28; radius: 14; color: Theme.tx
            }
        }
        T { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.round(vol.v * 100); font.pixelSize: 20; color: Qt.rgba(0.96, 0.95, 0.94, 0.65) }
        MouseArea {
            x: track.x - 16; width: track.width + 32; height: parent.height
            preventStealing: true
            function at(px) { return Math.max(0, Math.min(1, (px - 16) / track.width)) }
            onPressed: (e) => { mp.volDrag = at(e.x) }
            onPositionChanged: (e) => { mp.volDrag = at(e.x); if (!volSend.running) volSend.start() }
            onReleased: { volSend.stop(); room.setVolume(Math.round(mp.volDrag * 100)); mp.volDrag = -1 }
            onCanceled: { mp.volDrag = -1 }
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
        playlists: [{ name: "Liked Songs", uri: "liked", art: "" }].concat(music.playlists || [])
        onClose: mp.library = false
        onPlay: (uri) => { room.playUri(uri); mp.library = false }
    }
}
