import QtQuick

// Words that arrive one by one (the phone's WordFlow): new words since the last update slide up into place one after
// another; words already shown stay put (and ease over when the line re-centres).
Item {
    id: wf
    property real size: 67
    property int weight: Font.Medium
    property color color: Qt.rgba(1, 248 / 255, 240 / 255, 1)
    property real lineHeight: 1.14
    property bool centered: true
    property string placeholder: ""
    property real usedHeight: 0
    property var words: []
    clip: false

    function norm(w) { return (w || "").toLowerCase().replace(/[^a-z0-9']/g, "") }

    function say(text) {
        var ws = (text || "").split(/\s+/).filter(function (w) { return w.length > 0 })
        var same = 0
        while (same < words.length && same < ws.length && norm(words[same]) === norm(ws[same])) same++
        if (same === ws.length && ws.length === words.length) {
            for (var k = 0; k < ws.length; k++) wm.setProperty(k, "w", ws[k])
            return
        }
        while (wm.count > same) wm.remove(wm.count - 1)
        for (var i = same; i < ws.length; i++) wm.append({ w: ws[i] })
        for (var j = 0; j < same; j++) wm.setProperty(j, "w", ws[j])
        words = ws
        placeholder = ""
        Qt.callLater(layout, same)
    }
    function clear() { wm.clear(); words = []; usedHeight = 0 }

    function layout(from) {
        var space = size * 0.24, lh = size * lineHeight
        var x = 0, y = 0, frames = [], lineOf = [], lineW = [0]
        for (var i = 0; i < rep.count; i++) {
            var d = rep.itemAt(i); if (!d) return
            var w = d.implicitWidth
            if (x > 0 && x + w > wf.width) { x = 0; y += lh; lineW.push(0) }
            frames.push({ x: x, y: y + (lh - d.implicitHeight) / 2 })
            lineOf.push(lineW.length - 1)
            lineW[lineW.length - 1] = x + w
            x += w + space
        }
        for (var j = 0; j < rep.count; j++) {
            var f = frames[j]
            if (centered) f.x += (wf.width - lineW[lineOf[j]]) / 2
            rep.itemAt(j).place(f.x, f.y, j >= from, (j - from) * 70)
        }
        usedHeight = rep.count ? y + lh : 0
    }
    onSizeChanged: Qt.callLater(layout, 99999)
    onWidthChanged: Qt.callLater(layout, 99999)

    ListModel { id: wm }
    Repeater {
        id: rep
        model: wm
        delegate: Text {
            id: d
            text: model.w
            color: wf.color
            font.family: Theme.face; font.pixelSize: wf.size; font.weight: wf.weight
            renderType: Text.QtRendering
            opacity: 0
            property bool born: false
            function place(px, py, fresh, delay) {
                if (fresh || !born) {
                    born = true
                    moveA.stop(); inA.stop()
                    x = px; y = py + 12 * 2.4; opacity = 0
                    inA.toY = py; inA.delay = Math.max(0, delay); inA.start()
                } else if (x !== px || y !== py) {
                    moveA.toX = px; moveA.toY = py; moveA.start()
                }
            }
            SequentialAnimation {
                id: inA
                property real toY: 0
                property int delay: 0
                PauseAnimation { duration: inA.delay }
                ParallelAnimation {
                    NumberAnimation { target: d; property: "y"; to: inA.toY; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
                    NumberAnimation { target: d; property: "opacity"; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
                }
            }
            ParallelAnimation {
                id: moveA
                property real toX: 0
                property real toY: 0
                NumberAnimation { target: d; property: "x"; to: moveA.toX; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
                NumberAnimation { target: d; property: "y"; to: moveA.toY; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
            }
        }
    }
    Text {
        visible: wf.placeholder !== "" && rep.count === 0
        width: wf.width
        horizontalAlignment: wf.centered ? Text.AlignHCenter : Text.AlignLeft
        text: wf.placeholder
        color: Qt.rgba(1, 240 / 255, 225 / 255, 0.32)
        font.family: Theme.face; font.pixelSize: wf.size; font.weight: wf.weight
        renderType: Text.QtRendering
    }
}
