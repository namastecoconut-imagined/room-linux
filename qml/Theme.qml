pragma Singleton
import QtQuick

// Colours and type from the iPhone panel (NativeKit Theme), sized for a 12" screen seen from across a room.
QtObject {
    readonly property color tx: "#f4f2ef"
    readonly property color mut: "#9a9794"
    readonly property color dim: "#5d5b58"
    readonly property color warm: "#ffbe7a"
    readonly property color accent: "#ffcf9c"
    readonly property color hair: Qt.rgba(1, 1, 1, 0.09)
    // Helvetica Neue when it's installed (it's the panel's face); Inter Tight, which ships with Room, otherwise
    readonly property string face: Qt.fontFamilies().indexOf("Helvetica Neue") >= 0 ? "Helvetica Neue" : "Inter Tight"
    readonly property real stageW: 1368
    readonly property real stageH: 912

    function rgb(a, alpha) { return Qt.rgba(a[0] / 255, a[1] / 255, a[2] / 255, alpha === undefined ? 1 : alpha) }
    function two(n) { return (n < 10 ? "0" : "") + n }
    function clock(d, h24) {
        var h = d.getHours(), m = d.getMinutes()
        if (!h24) { h = h % 12; if (h === 0) h = 12 }
        return (h24 ? two(h) : "" + h) + ":" + two(m)
    }
    function dateLine(d) { return Qt.formatDate(d, "dddd, d MMMM") }
    function hour(h, h24) { return h24 ? two(h) : ((h % 12 === 0 ? 12 : h % 12) + (h < 12 ? "a" : "p")) }
    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + two(s % 60) }
}
