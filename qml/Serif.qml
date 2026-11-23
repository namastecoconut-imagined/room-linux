import QtQuick
// The redesign's display type (Theme.serif: Helvetica Now Display Medium, or Instrument Serif) — the clock, big numbers, room names, the standby title.
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
    font.weight: Theme.serifWeight
    font.pixelSize: 84
    // the display face's spacing (Helvetica Now Display: 4 % tighter). Tracking is a share of the size; set here rather
    // than bound, since the spacing is part of the font it depends on
    property real tracking: Theme.serifTrack
    function track() { var w = tracking * font.pixelSize; if (Math.abs(font.letterSpacing - w) > 0.01) font.letterSpacing = w }
    onTrackingChanged: track()
    onFontChanged: track()
    Component.onCompleted: track()
    // drawn from the glyphs' own curves: crisp at the clock's size (and a thin serif's hairlines hold up — the usual
    // distance fields broke Kasero's into dashes)
    renderType: Text.CurveRendering
    elide: Text.ElideNone
    FontMetrics { id: fm; font: t.font }
    transform: Translate { y: t.css ? t.shift : 0 }
}
