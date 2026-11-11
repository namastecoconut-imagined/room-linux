import QtQuick
import QtQuick.Shapes

// The Weather screen (room-motion.html fillScreen('weather')); the background turns sky-coloured (Field "weather").
// Up top, to read: the temperature big in the serif, what it's like, feels-like · humidity · air · sunrise and sunset;
// on the right, the rain to expect (the next 12 hours, else tomorrow) or, with none, the day's high and low. Below:
// the next 12 hours as one soft line with the temperatures over it and the chance of rain as blue dots under it, and
// the next three days along the bottom. "Updated" sits in the top bar (Scene). Nothing here takes a tap.
Item {
    id: wv
    width: 1368; height: 912
    property bool shown: false
    readonly property var wx: room.weather
    readonly property bool ok: wx && wx.ok === true
    readonly property var hours: ok ? (wx.hours || []).slice(0, 12) : []
    readonly property var days: ok ? (wx.days || []).slice(0, 3) : []
    readonly property int rainAt: Theme.rainAt(wx ? wx.hours : [])
    readonly property var tomorrow: days.length > 1 ? days[1] : null
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    component Rise: Item {
        id: rz
        property int order: 0
        opacity: wv.shown ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: wv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        transform: Translate {
            y: wv.shown ? 0 : 14
            Behavior on y { SequentialAnimation { PauseAnimation { duration: wv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        }
    }

    Mono { visible: !wv.ok; x: 44; y: 150; text: "Getting the weather…"; color: Theme.w62; size: 18 }

    // ---------------------------------------------------------------- now
    Rise {
        order: 0
        visible: wv.ok
        x: 44; y: 120; width: 340; height: 240
        Serif { text: (wv.wx.t !== undefined ? wv.wx.t : "–") + "°"; font.pixelSize: 230 }
    }
    Rise {
        order: 1
        visible: wv.ok
        x: 400; y: 150; width: 360; height: 200
        Text {
            text: Theme.cap(wv.wx.d || ""); color: "white"
            font.family: Theme.face; font.pixelSize: 40; renderType: Text.QtRendering
        }
        Column {
            y: 64; spacing: 6
            Mono {
                color: Theme.w62
                text: ["Feels " + wv.wx.feels + "°", wv.wx.hum ? "humidity " + wv.wx.hum + "%" : ""].filter(function (s) { return s }).join(" · ")
            }
            Mono { visible: !!wv.wx.aqi; color: Theme.w62; text: "Air " + wv.wx.aqi + " · " + Theme.aqiWord(wv.wx.aqi || 0) }
            Mono { visible: !!wv.wx.sunrise; color: Theme.w62; text: "Sunrise " + wv.wx.sunrise + " · sunset " + wv.wx.sunset }
        }
    }
    // ---------------------------------------------------------------- the rain to expect (or the day's range)
    Rise {
        order: 2
        visible: wv.ok
        x: 1324 - 460; y: 150; width: 460; height: 220
        readonly property bool soon: wv.rainAt >= 0
        readonly property bool tmr: !soon && wv.tomorrow && (wv.tomorrow.p || 0) >= 50
        Mono {
            anchors.right: parent.right
            color: parent.soon || parent.tmr ? Theme.rainC : Theme.w62
            text: parent.soon ? (wv.rainAt === 0 ? "Rain now" : "Rain coming") : parent.tmr ? "Rain tomorrow" : "Today"
        }
        Serif {
            anchors.right: parent.right; y: 30; width: parent.width
            horizontalAlignment: Text.AlignRight; wrapMode: Text.WordWrap
            font.pixelSize: 56; lineHeight: 1.05
            height: implicitHeight
            text: parent.soon ? (wv.rainAt === 0 ? "Likely now, " : "Likely around " + Theme.hourText(wv.hours[wv.rainAt].h, room.clock24) + ", ")
                                + wv.hours[wv.rainAt].p + "%"
                  : parent.tmr ? wv.tomorrow.d + ", " + wv.tomorrow.p + "%"
                  : wv.days.length ? "High " + wv.days[0].hi + "°, low " + wv.days[0].lo + "°" : ""
        }
        Mono {
            anchors.right: parent.right; y: 30 + 2 * 59 + 14
            color: Theme.w62
            text: parent.soon || parent.tmr ? "Take an umbrella out" : "No rain expected"
        }
    }

    // ---------------------------------------------------------------- the next 12 hours: one soft line
    Rise {
        order: 3
        visible: wv.ok && wv.hours.length > 1
        x: 0; y: 0; width: 1368; height: 912
        Mono { x: 44; y: 530; text: "Next 12 hours"; color: Theme.w62 }
        Item {
            id: chart
            anchors.fill: parent
            readonly property int n: wv.hours.length
            readonly property real lo: { var m = 999; for (var i = 0; i < n; i++) m = Math.min(m, wv.hours[i].t); return m }
            readonly property real hi: { var m = -999; for (var i = 0; i < n; i++) m = Math.max(m, wv.hours[i].t); return m }
            readonly property real span: Math.max(6, hi - lo)
            function px(i) { return 44 + i * (1280 / Math.max(1, n - 1)) }
            function py(t) { return 736 - (t - lo) / span * 120 }
            readonly property string curve: {
                if (n < 2) return ""
                var d = "M " + px(0) + " " + py(wv.hours[0].t)
                for (var i = 1; i < n; i++) {
                    var x0 = px(i - 1), x1 = px(i), xm = x0 + (x1 - x0) / 2
                    d += " C " + xm + " " + py(wv.hours[i - 1].t) + " " + xm + " " + py(wv.hours[i].t) + " " + x1 + " " + py(wv.hours[i].t)
                }
                return d
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {         // the soft fill under the line
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: 0; y1: chart.py(chart.hi); x2: 0; y2: 790
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.18) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    PathSvg { path: chart.curve + (chart.n > 1 ? " L " + chart.px(chart.n - 1) + " 790 L " + chart.px(0) + " 790 Z" : "") }
                }
                ShapePath {         // the line
                    strokeColor: "white"; strokeWidth: 2; fillColor: "transparent"
                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                    PathSvg { path: chart.curve }
                }
            }
            Repeater {
                model: wv.hours
                Item {
                    readonly property real cx: chart.px(index)
                    readonly property real cy: chart.py(modelData.t)
                    Rectangle { x: cx - width / 2; y: cy - height / 2; width: index ? 6 : 12; height: width; radius: width / 2; color: "white" }
                    Serif { x: cx - width / 2; y: cy - 16 - 24; width: 60; horizontalAlignment: Text.AlignHCenter; text: modelData.t + "°"; font.pixelSize: 24 }
                    Rectangle {     // the chance of rain
                        readonly property real p: modelData.p || 0
                        width: 4 + p / 4; height: width; radius: width / 2
                        x: cx - width / 2; y: 796 - height / 2
                        color: Theme.rainC; opacity: Math.min(1, 0.3 + p / 40)
                    }
                    Mono {
                        x: cx - width / 2; y: 816; width: 60; horizontalAlignment: Text.AlignHCenter
                        size: 12; color: Theme.w62
                        text: index === 0 ? "Now" : Theme.hour(modelData.h, room.clock24)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- the next three days
    Rise {
        order: 4
        visible: wv.ok
        x: 44; y: 852; width: 1280; height: 20
        Repeater {          // first at the left, last at the right, the middle one centred
            model: wv.days
            Row {
                x: index === 0 ? 0 : index === wv.days.length - 1 ? 1280 - width : (1280 - width) / 2
                spacing: 8
                Mono { size: 13; text: modelData.name }
                Mono { size: 13; color: Theme.w62; text: "· " + modelData.d + " · " + modelData.hi + "° / " + modelData.lo + "° · " + (modelData.p || 0) + "%" }
            }
        }
    }
}
