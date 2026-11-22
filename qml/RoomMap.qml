import QtQuick
import "roomsdata.js" as Data

// A room drawn as it is (the Room screen, for rooms that have a drawing: tools/rooms/<room>.js, baked by
// tools/rooms/bake.py): lines only, on Room's background, seen from the doorway, every lamp where it really is and
// lit as it really is — its shade in its own colour, its light spreading around it. Tap a lamp (its number, or its row
// along the bottom: most of the drawing is where the screen doesn't feel touch) and the drawing glides in on that
// corner of the room; RoomView's controls then work on that lamp alone. Picking it again, or "‹ Whole room", glides
// back out. The drawing is one picture moved and scaled; nothing is drawn as paths here.
Item {
    id: rm
    width: 1368; height: 912
    property var r: null                               // the room (room.rooms[…])
    property int sel: 0                                // the lamp picked (its number in the drawing), or 0
    signal picked(int n)
    readonly property string key: r ? String(r.name).toLowerCase().replace(/[^a-z0-9]/g, "") : ""
    readonly property var map: key !== "" && Data.maps[key] ? Data.maps[key] : null
    readonly property bool has: map !== null
    readonly property string dir: Qt.resolvedUrl("../assets/rooms/" + key + "/")

    // each drawn lamp's bulb: the first of the room's lamps whose name has one of its words (in its order of
    // preference), and what's left over in order
    readonly property var bulbs: {
        if (!map || !r) return []
        var free = (r.lamps || []).slice(), got = []
        map.lamps.forEach(function (l, i) {
            got[i] = null
            for (var w = 0; w < l.match.length && !got[i]; w++)
                for (var j = 0; j < free.length; j++)
                    if (String(free[j].name).toLowerCase().indexOf(l.match[w]) >= 0) { got[i] = free[j]; free.splice(j, 1); break }
        })
        map.lamps.forEach(function (l, i) { if (!got[i] && free.length) got[i] = free.shift() })
        return got
    }
    function bulb(n) { return n > 0 && n <= bulbs.length ? bulbs[n - 1] : null }
    function lit(b) { return b !== null && b.reachable !== false && b.on }
    function tone(b, a) { var g = b && b.glow && b.glow.length === 3 ? b.glow : [255, 190, 122]; return Qt.rgba(g[0] / 255, g[1] / 255, g[2] / 255, a) }

    // ---------------------------------------------------------------- the camera
    readonly property rect view: Qt.rect(676, 100, 692, 688)        // the drawing's area (it stops at its edges)
    readonly property real zoom: 2.3
    property real k: 1
    property real tx: 0
    property real ty: 0
    function aim() {
        var l = map && sel > 0 ? map.lamps[sel - 1] : null
        k = l ? zoom : 1
        tx = l ? view.x + view.width / 2 + 2 - l.x * zoom : 0
        ty = l ? view.y + view.height / 2 - 10 - (l.y + 30) * zoom : 0       // (a little below the lamp: what it lights)
    }
    onSelChanged: aim()
    onMapChanged: aim()
    component Glide: NumberAnimation { duration: Theme.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    Behavior on k { Glide {} }
    Behavior on tx { Glide {} }
    Behavior on ty { Glide {} }
    function sx(x) { return x * k + tx }
    function sy(y) { return y * k + ty }

    component Tinted: ShaderEffect {
        property alias src: im.source
        property color tint: "white"
        Image { id: im; asynchronous: true; smooth: true; visible: false }
        property variant source: im
        fragmentShader: shaderDir + "tint.frag.qsb"
    }

    // ---------------------------------------------------------------- the lamps' light (over the whole screen, not
    // cut by the drawing's edges: it's light, not part of the drawing)
    Repeater {
        model: rm.has ? rm.map.lamps : []
        Tinted {
            readonly property var b: rm.bulb(modelData.n)
            readonly property real lv: rm.lit(b) ? b.level : 0
            readonly property real rad: (110 + lv * 1.5) * (1 + (rm.k - 1) * 0.45)
            x: rm.sx(modelData.x) - rad; y: rm.sy(modelData.y) - rad; width: rad * 2; height: rad * 2
            src: rm.has ? Qt.resolvedUrl("../assets/rooms/glow.png") : ""
            tint: rm.tone(b, 0.42 * lv / 100 + 0.12)
            opacity: lv > 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 500 } }
        }
    }

    // ---------------------------------------------------------------- the drawing
    Item {
        id: clipper
        x: rm.view.x; y: rm.view.y; width: rm.view.width; height: rm.view.height
        clip: true
        visible: rm.has
        Item {
            x: -rm.view.x; y: -rm.view.y
            transform: [ Scale { xScale: rm.k; yScale: rm.k }, Translate { x: rm.tx; y: rm.ty } ]
            Image {
                x: rm.has ? rm.map.lines.x : 0; y: rm.has ? rm.map.lines.y : 0
                width: rm.has ? rm.map.lines.w : 0; height: rm.has ? rm.map.lines.h : 0
                source: rm.has ? rm.dir + "lines.png" : ""
                asynchronous: true; smooth: true; mipmap: true; cache: false
            }
            // the lit lamps' shades, in their own colour
            Repeater {
                model: rm.has ? rm.map.lamps : []
                Tinted {
                    readonly property var b: rm.bulb(modelData.n)
                    visible: modelData.shade !== undefined && opacity > 0.01
                    x: modelData.shade ? modelData.shade.x : 0; y: modelData.shade ? modelData.shade.y : 0
                    width: modelData.shade ? modelData.shade.w : 0; height: modelData.shade ? modelData.shade.h : 0
                    src: modelData.shade ? rm.dir + "shade" + modelData.n + ".png" : ""
                    tint: rm.tone(b, 0.92)
                    opacity: rm.lit(b) ? 0.55 + 0.45 * b.level / 100 : 0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }
            }
        }
        // the numbers: the same size at any zoom; the picked one ringed, the others fading back while zoomed in
        Repeater {
            model: rm.has ? rm.map.lamps : []
            Item {
                readonly property bool on: rm.sel === modelData.n
                readonly property real dx: (modelData.x > 1150 || modelData.n <= 2 ? -24 : 24) * Math.min(1.6, rm.k)
                x: rm.sx(modelData.x) - rm.view.x; y: rm.sy(modelData.y) - rm.view.y
                opacity: rm.sel > 0 && !on ? Math.max(0.25, 1 - (rm.k - 1)) : 1
                Rectangle {
                    visible: parent.on; anchors.centerIn: parent
                    width: 2 * (18 + 8 * (rm.k - 1) / 1.3); height: width; radius: width / 2
                    color: "transparent"; border.width: 2; border.color: Theme.timer
                }
                Rectangle {
                    x: parent.dx - 12; y: -36; width: 24; height: 24; radius: 12
                    color: parent.on ? Theme.timer : Qt.rgba(20 / 255, 12 / 255, 8 / 255, 0.8)
                    border.width: 1; border.color: parent.on ? Theme.timer : Qt.rgba(1, 1, 1, 0.7)
                    Mono { anchors.centerIn: parent; size: 12; text: modelData.n; color: parent.parent.on ? "#3a2010" : "white" }
                }
                Press {                                // (only the ones below the band that doesn't feel touch answer)
                    x: parent.dx - 26; y: -50; width: 52; height: 52; pressScale: 1
                    onTapped: rm.picked(modelData.n)
                }
            }
        }
    }

    // ---------------------------------------------------------------- the lamps, along the bottom (what you tap)
    Grid {
        x: 700; y: 800; columns: 3; columnSpacing: 18; rowSpacing: 0
        visible: rm.has
        Repeater {
            model: rm.has ? rm.map.lamps : []
            Press {
                readonly property var b: rm.bulb(modelData.n)
                readonly property bool on: rm.sel === modelData.n
                width: 200; height: 48; pressScale: 0.97
                onTapped: rm.picked(modelData.n)
                Rectangle { width: parent.width; height: 1; color: parent.on ? Theme.timer : Qt.rgba(1, 1, 1, 0.18) }
                Rectangle {
                    x: 0; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11
                    color: parent.on ? Theme.timer : "transparent"
                    border.width: parent.on ? 0 : 1; border.color: Qt.rgba(1, 1, 1, 0.5)
                    Mono { anchors.centerIn: parent; size: 11; text: modelData.n; color: parent.parent.on ? "#3a2010" : "white" }
                }
                T {
                    x: 32; anchors.verticalCenter: parent.verticalCenter; width: 128; elide: Text.ElideRight
                    text: modelData.name; font.pixelSize: 17
                    color: rm.lit(parent.b) ? "white" : Qt.rgba(1, 1, 1, 0.45)
                }
                Mono {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 12; color: Theme.w62
                    text: !parent.b || parent.b.reachable === false ? "—" : rm.lit(parent.b) ? parent.b.level : "Off"
                }
            }
        }
    }
}
