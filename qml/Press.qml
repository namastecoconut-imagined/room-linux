import QtQuick
// Anything tappable. A touch shows at once: it dips (shrinks a touch) while pressed and springs back past its size
// and settles when you let go, and a soft light comes up behind it and fades (it stays put — no ripple). A tap so
// quick it's over before the dip could show still gets the whole dip and spring. Fires on release (and on long-press
// if asked).
Item {
    id: p
    signal tapped()
    signal held()
    property real pressScale: 0.96
    property bool bloom: true               // the light behind it
    property alias pressed: ma.pressed
    property real dip: 1
    scale: dip

    component Spring: NumberAnimation { target: p; property: "dip"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    NumberAnimation { id: down; target: p; property: "dip"; to: p.pressScale; duration: 90; easing.type: Easing.OutQuad }
    Spring { id: up }
    SequentialAnimation {
        id: quick
        NumberAnimation { target: p; property: "dip"; to: p.pressScale; duration: 70; easing.type: Easing.OutQuad }
        Spring {}
    }

    Glow {
        id: bl
        anchors.centerIn: parent; z: -1
        width: Math.min(220, Math.max(p.width, p.height) * 1.7); height: width
        color: "white"; strength: 0.35
        opacity: 0
        visible: opacity > 0.001
    }
    SequentialAnimation {
        id: bloomA
        NumberAnimation { target: bl; property: "opacity"; to: 1; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: bl; property: "opacity"; to: 0; duration: 480; easing.type: Easing.InOutQuad }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        pressAndHoldInterval: 900
        property real t0: 0
        onPressed: (e) => {
            t0 = Date.now(); quick.stop(); up.stop(); down.restart()
            if (p.bloom) bloomA.restart()
        }
        onReleased: { down.stop(); if (Date.now() - t0 < 80) quick.restart(); else up.restart() }
        onCanceled: { down.stop(); up.restart() }
        onClicked: p.tapped()
        onPressAndHold: p.held()
    }
}
