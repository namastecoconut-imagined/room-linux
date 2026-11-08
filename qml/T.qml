import QtQuick
// Text in the panel's face and colours.
Text {
    color: Theme.tx
    font.family: Theme.face
    font.pixelSize: 22
    font.weight: Font.Normal
    renderType: Text.QtRendering
    elide: Text.ElideRight
    font.features: { "tnum": 1 }
}
