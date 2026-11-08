import QtQuick

// Weather: the temperature large and thin, what it's like, a rain warning when it's coming, the next three days,
// sunrise and sunset, and the next 12 hours as bars (taller = warmer; blue dots = the chance of rain).
Item {
    id: ws
    width: Theme.stageW; height: Theme.stageH
    property var wx: room.weather
    readonly property var hours: (wx.hours || []).slice(0, 12)
    readonly property int rainAt: Theme.rainAt(wx.hours)
    signal back()

    Glow { x: 300 - 560; y: 300 - 560; width: 1120; height: 1120; color: Qt.rgba(130 / 255, 160 / 255, 210 / 255, 1); strength: 0.12 }
    Header { title: "Weather"; note: wx.updated ? "updated " + wx.updated : ""; onBack: ws.back() }

    T { visible: wx.ok !== true; x: 96; y: 180; text: "Getting the weather…"; font.pixelSize: 30; color: Theme.sub }
    Item {
        visible: wx.ok === true
        anchors.fill: parent
        T { x: 90; y: 140; text: (wx.t || 0) + "°"; font.pixelSize: 150; font.weight: Font.ExtraLight }
        T { x: 96; y: 330; text: Theme.cap(wx.d || ""); font.pixelSize: 30 }
        T {
            x: 96; y: 374
            text: ["Feels " + wx.feels + "°", (wx.hum ? "humidity " + wx.hum + "%" : ""), (wx.aqi ? "air " + wx.aqi + " " + Theme.aqiWord(wx.aqi) : "")].filter(function (s) { return s }).join("  ·  ")
            font.pixelSize: 20; color: Theme.sub
        }
        Row {
            x: 96; y: 434; spacing: 12
            visible: ws.rainAt >= 0
            Icon { name: "umbrella"; size: 24; color: Theme.rain; anchors.verticalCenter: parent.verticalCenter }
            T { text: ws.rainAt >= 0 ? "Rain likely around " + Theme.hourText(ws.hours[ws.rainAt].h, room.clock24) + "  ·  " + ws.hours[ws.rainAt].p + "%" : ""; font.pixelSize: 22; color: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.75) }
        }

        // the next days
        Column {
            x: 744; y: 150; width: 528
            Repeater {
                model: wx.days || []
                Item {
                    width: 528; height: 72
                    T { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 22 }
                    T { x: 96; anchors.verticalCenter: parent.verticalCenter; width: 260; text: modelData.d + (modelData.p >= 50 ? "  ·  " + modelData.p + "%" : ""); font.pixelSize: 22; color: Theme.sub }
                    T { anchors.right: parent.right; anchors.rightMargin: 64; anchors.verticalCenter: parent.verticalCenter; text: modelData.hi + "°"; font.pixelSize: 22 }
                    T { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.lo + "°"; font.pixelSize: 22; color: Theme.sub }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
                }
            }
            T { topPadding: 22; visible: !!wx.sunrise; text: "Sunrise " + wx.sunrise + "  ·  sunset " + wx.sunset; font.pixelSize: 18; color: Theme.sub }
        }

        // the next 12 hours
        SectionCap { x: 96; y: 512; text: "Next 12 hours" }
        Item {
            x: 96; y: 552; width: 1176; height: 260
            readonly property real lo: { var m = 999; for (var i = 0; i < ws.hours.length; i++) m = Math.min(m, ws.hours[i].t); return m }
            readonly property real hi: { var m = -999; for (var i = 0; i < ws.hours.length; i++) m = Math.max(m, ws.hours[i].t); return m }
            Repeater {
                model: ws.hours
                Item {
                    x: ws.hours.length > 1 ? index * (1176 - 60) / (ws.hours.length - 1) : 0
                    width: 60; height: 260
                    T { width: 60; horizontalAlignment: Text.AlignHCenter; text: modelData.t + "°"; font.pixelSize: 19 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 6; radius: 3
                        height: 20 + 110 * (parent.parent.hi > parent.parent.lo ? (modelData.t - parent.parent.lo) / (parent.parent.hi - parent.parent.lo) : 0.5)
                        y: 166 - height
                        color: Qt.rgba(244 / 255, 238 / 255, 230 / 255, 0.55)
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 180
                        width: (modelData.p || 0) >= 50 ? 10 : 6; height: 8; radius: 4
                        color: Qt.rgba(127 / 255, 180 / 255, 1, 0.08 + (modelData.p || 0) / 100)
                    }
                    T { y: 204; width: 60; horizontalAlignment: Text.AlignHCenter; text: Theme.hour(modelData.h, room.clock24).replace("a", "").replace("p", ""); font.pixelSize: 16; color: Theme.sub }
                }
            }
        }
    }
}
