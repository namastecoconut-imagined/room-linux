import QtQuick
// Home's glance list, under the clock: only what's real right now — the date, a running timer (amber, with its
// progress), the weather, what's next, the alarm, reminders due today. A line slides in when its thing starts and
// out when it ends; the lines below glide up or down to make room.
ListView {
    id: g
    property var items: []             // [{ k, text, kind: "date" | "timer" | "line", bar }]
    interactive: false
    width: 560; height: 360
    spacing: 0
    model: ListModel { id: lm }
    onItemsChanged: sync()
    Component.onCompleted: sync()
    function sync() {
        var want = items.map(function (x) { return x.k })
        for (var i = lm.count - 1; i >= 0; i--) if (want.indexOf(lm.get(i).k) < 0) lm.remove(i)
        for (var j = 0; j < items.length; j++) {
            var it = items[j], at = -1
            for (var q = 0; q < lm.count; q++) if (lm.get(q).k === it.k) { at = q; break }
            var row = { k: it.k, text: it.text, kind: it.kind || "line", bar: it.bar !== undefined ? it.bar : 0 }
            if (at < 0) lm.insert(Math.min(j, lm.count), row)
            else { if (at !== j) lm.move(at, j, 1); lm.set(j, row) }
        }
    }
    delegate: Item {
        width: g.width; height: kind === "timer" ? 48 : 30
        Mono {
            width: parent.width; text: model.text
            color: kind === "timer" ? Theme.timer : kind === "date" ? "white" : Theme.w62
        }
        Item {
            visible: kind === "timer"
            y: 32; width: 340; height: 2
            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.2) }
            Glow { x: parent.width * model.bar - 14; y: -13; width: 28; height: 28; color: "#ffbe7a"; strength: 0.7 }
            // steps once a second, unanimated: an easing that ran from one second into the next never stopped, and
            // kept the whole screen redrawing at full rate for as long as a timer ran
            Rectangle { width: parent.width * model.bar; height: 2; color: Theme.timer }
        }
    }
    add: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
        NumberAnimation { property: "x"; from: -16; to: 0; duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    }
    remove: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
        NumberAnimation { property: "x"; to: -16; duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
    }
    displaced: Transition {
        NumberAnimation { properties: "y"; duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease }
        NumberAnimation { property: "opacity"; to: 1; duration: 0 }
        NumberAnimation { property: "x"; to: 0; duration: 0 }
    }
}
