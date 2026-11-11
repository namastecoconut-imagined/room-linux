import QtQuick
// The redesign's small type: IBM Plex Mono, uppercase, 0.08em apart, 15 px — nav, labels, every small detail.
Text {
    color: "white"
    font.family: Theme.mono
    property real size: 15
    font.pixelSize: size
    font.letterSpacing: size * 0.08
    font.capitalization: Font.AllUppercase
    renderType: Text.QtRendering
    elide: Text.ElideRight
}
