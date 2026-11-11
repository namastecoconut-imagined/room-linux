import QtQuick
// The redesign's display type: Instrument Serif — the clock, big numbers, room names, the standby title.
// Placed the way the design (a web page, line-height 1) places it: the line is as tall as the type, with the font's
// own ascent and descent centred in it. Qt puts the top of the ascent at the top instead, which sat big serif type
// ~15 % of its size too low (37 px for the 250 px clock) — `shift` moves it back up.
Text {
    id: t
    property bool css: true
    readonly property real shift: (font.pixelSize - fm.height) / 2
    height: css ? font.pixelSize : implicitHeight     // the line box (what sits below it is placed from this)
    color: "white"
    font.family: Theme.serif
    font.pixelSize: 84
    renderType: Text.QtRendering
    elide: Text.ElideNone
    FontMetrics { id: fm; font: t.font }
    transform: Translate { y: t.css ? t.shift : 0 }
}
