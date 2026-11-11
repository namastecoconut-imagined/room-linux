import QtQuick
// The redesign's vignette (shaders/vignette.frag): soft dark edges and a shade down the left, behind the clock.
// Over every screen; under the alerts, the assistant and the volume.
ShaderEffect {
    x: -40; y: -40; width: 1368 + 80; height: 912 + 80
    property size size: Qt.size(width, height)
    property point origin: Qt.point(x, y)
    fragmentShader: shaderDir + "vignette.frag.qsb"
}
