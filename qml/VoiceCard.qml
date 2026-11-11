import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// What the assistant found or did, beside its answer (room-motion.html aCard): a glass card, 512 × 320, drawn from
// Room's own state so it stays live (a timer counts down in it). The assistant picks the kind with its answer —
// weather (now, the next hours) · forecast (tomorrow, the next days) · air · timer · music · schedule · alarm; Room
// adds "lights" itself when the answer changed some (the room, its level, its lamps).
Item {
    id: vc
    width: 512; height: 320
    property string kind: ""
    property var lit: []
    readonly property var wx: room.weather || ({})
    readonly property bool wxOk: wx.ok === true

    Rectangle {
        anchors.fill: parent; radius: 22
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.1) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.03) }
        }
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
    }
    Rectangle { x: 22; y: 1; width: parent.width - 44; height: 1; color: Qt.rgba(1, 1, 1, 0.22) }       // the top edge catching the light

    component Big: Serif { font.pixelSize: 96; height: 96 }
    component Note: Mono { size: 13; color: Theme.w62 }
    // a fine line with its level lit, in the sliders' style (to read, not to drag)
    component Level: Item {
        id: lv
        property real f: 0
        property color tint: "#ffc98f"
        height: 2
        Rectangle { width: parent.width; height: 2; color: Qt.rgba(1, 1, 1, 0.16) }
        RectangularShadow { width: parent.width * lv.f; height: 2; blur: 10; color: Qt.rgba(lv.tint.r, lv.tint.g, lv.tint.b, 0.8); visible: width > 1 }
        Rectangle { width: parent.width * lv.f; height: 2; color: lv.tint }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: vc.kind === "weather" ? now : vc.kind === "forecast" ? days : vc.kind === "air" ? air
                       : vc.kind === "timer" ? timer : vc.kind === "music" ? music : vc.kind === "schedule" ? schedule
                       : vc.kind === "alarm" ? alarm : vc.kind === "lights" ? lights : null
    }

    // ---------------------------------------------------------------- weather: now, and the next eight hours
    Component {
        id: now
        Item {
            id: nw
            readonly property var hrs: vc.wxOk ? (vc.wx.hours || []).slice(0, 8) : []
            readonly property int rain: Theme.rainAt(vc.wx.hours || [])
            readonly property real lo: { var m = 999; for (var i = 0; i < hrs.length; i++) m = Math.min(m, hrs[i].t); return m }
            readonly property real hi: { var m = -999; for (var i = 0; i < hrs.length; i++) m = Math.max(m, hrs[i].t); return m }
            Note { x: 30; y: 28; text: vc.wxOk ? "Now · " + Theme.cap(vc.wx.d || "") : "Weather" }
            Row {
                x: 30; y: 54; spacing: 14
                Big { id: tNow; text: vc.wxOk ? vc.wx.t + "°" : "–" }
                Serif { visible: vc.wxOk; text: "feels " + vc.wx.feels + "°"; font.pixelSize: 36; css: false; color: Qt.rgba(1, 1, 1, 0.6)
                        anchors.baseline: tNow.baseline; transform: Translate { y: tNow.shift } }
            }
            Mono {
                x: 30; y: 168; size: 13
                color: nw.rain >= 0 ? Theme.rainC : Theme.w62
                text: !vc.wxOk ? "" : nw.rain === 0 ? "Raining now · " + vc.wx.hours[0].p + "%"
                    : nw.rain > 0 ? "Rain " + vc.wx.hours[nw.rain].p + "% around " + Theme.hourText(vc.wx.hours[nw.rain].h, room.clock24)
                    : "High " + vc.wx.hi + "° · low " + vc.wx.lo + "°"
            }
            Row {
                x: 30; y: 200; spacing: 10; height: 66
                Repeater {
                    model: nw.hrs
                    Item {
                        width: (512 - 60 - 70) / 8; height: 66
                        readonly property bool wet: index === nw.rain
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                            width: parent.width; radius: 3
                            height: 6 + (modelData.t - nw.lo) / Math.max(4, nw.hi - nw.lo) * 40
                            color: parent.wet ? Theme.rainC : Qt.rgba(1, 1, 1, 0.35)
                        }
                        Mono { anchors.bottom: parent.bottom; width: parent.width; horizontalAlignment: Text.AlignHCenter; size: 10; color: Theme.w62
                               text: index === 0 ? "Now" : Theme.hour(modelData.h, room.clock24) }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- forecast: tomorrow, then the next three days
    Component {
        id: days
        Item {
            readonly property var ds: vc.wxOk ? (vc.wx.days || []) : []
            readonly property var tm: ds.length > 1 ? ds[1] : null
            Note { x: 30; y: 28; text: tm ? "Tomorrow · " + Theme.cap(tm.d || "") : "Forecast" }
            Row {
                x: 30; y: 52; spacing: 12
                Big { id: tHi; text: tm ? tm.hi + "°" : "–" }
                Serif { visible: !!tm; text: "/ " + (tm ? tm.lo : "") + "°"; font.pixelSize: 40; css: false; color: Qt.rgba(1, 1, 1, 0.6)
                        anchors.baseline: tHi.baseline; transform: Translate { y: tHi.shift } }
            }
            Mono {
                x: 30; y: 162; size: 13
                color: tm && tm.p >= 30 ? Theme.rainC : Theme.w62
                text: !tm ? "" : tm.p >= 30 ? "Rain " + tm.p + "% in the day" : "No rain expected"
            }
            Rectangle { x: 30; y: 196; width: 452; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
            Repeater {
                model: parent.ds.slice(0, 3)
                Item {
                    x: 30 + index * 158; y: 212; width: 150; height: 90
                    Mono { size: 12; color: Theme.w62; text: modelData.name }
                    Serif { y: 22; text: modelData.hi + "° / " + modelData.lo + "°"; font.pixelSize: 30; height: 30 }
                    Mono { y: 64; size: 11; color: modelData.p >= 30 ? Theme.rainC : Theme.w62
                           text: modelData.p >= 30 ? "Rain " + modelData.p + "%" : Theme.cap(modelData.d || "") }
                }
            }
        }
    }

    // ---------------------------------------------------------------- air
    Component {
        id: air
        Item {
            readonly property int q: vc.wx.aqi || 0
            readonly property color tone: q <= 50 ? "#9fe0b0" : q <= 100 ? "#ffd98a" : q <= 150 ? "#ffb27a" : "#ff8a7a"
            Note { x: 30; y: 28; text: "Air quality · now" }
            Row {
                x: 30; y: 54; spacing: 16
                Big { id: aq; text: parent.parent.q ? parent.parent.q : "–" }
                Serif { visible: parent.parent.q > 0; text: Theme.aqiWord(parent.parent.q); font.pixelSize: 40; css: false; color: Qt.rgba(1, 1, 1, 0.6)
                        anchors.baseline: aq.baseline; transform: Translate { y: aq.shift } }
            }
            Level { x: 30; y: 196; width: 452; f: Math.min(1, parent.q / 300); tint: parent.tone }
            Note { x: 30; y: 222; size: 12; text: "Good to 50 · moderate to 100 · poor past 150" }
        }
    }

    // ---------------------------------------------------------------- timer: the newest, counting down
    Component {
        id: timer
        Item {
            readonly property var ts: (room.things.timers || []).filter(function (t) { return !t.done })
            readonly property var t: ts.length ? ts[ts.length - 1] : null
            Mono { x: 30; y: 28; size: 13; color: t ? Theme.timer : Theme.w62
                   text: t ? "Timer" + (t.label ? " · " + t.label : "") + (t.paused ? " · paused" : "") : "Timers" }
            Serif {
                x: 30; y: 56; font.pixelSize: 120; height: 120
                text: t ? Theme.countdown(t.left) : "None"
                color: t ? Theme.timer2 : Qt.rgba(1, 1, 1, 0.35)
            }
            Level {
                x: 30; y: 222; width: 452; visible: !!t; tint: Theme.timer
                f: t && t.total > 0 ? Math.max(0, Math.min(1, 1 - t.left / t.total)) : 0
            }
            Note { x: 30; y: 246; size: 12; visible: !!t; text: t ? "Of " + Math.round(t.total / 60) + " min" + (ts.length > 1 ? " · " + ts.length + " running" : "") : "" }
        }
    }

    // ---------------------------------------------------------------- music: what's playing now
    Component {
        id: music
        Item {
            readonly property var m: room.music || ({})
            Art {
                x: 26; y: 60; width: 200; height: 200; radius: 14
                source: parent.m.art || ""; rgb: parent.m.rgb || [201, 185, 163]; rgb2: parent.m.rgb2 || [44, 40, 34]
            }
            Column {
                x: 26 + 200 + 24; width: 512 - x - 26; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Note { text: parent.parent.m.playing ? "Now playing" : "Paused" }
                Text { width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                       text: parent.parent.m.title || "Nothing playing"; color: "white"
                       font.family: Theme.face; font.pixelSize: 32; renderType: Text.QtRendering }
                Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.m.artist || ""; color: Theme.w62
                       font.family: Theme.face; font.pixelSize: 20; renderType: Text.QtRendering }
                Item { width: 1; height: 8 }
                Note { width: parent.width; size: 11; visible: !!parent.parent.m.device; text: "On the " + (parent.parent.m.device || "") }
            }
        }
    }

    // ---------------------------------------------------------------- schedule: what's coming up
    Component {
        id: schedule
        Item {
            readonly property var ev: (room.events || []).slice(0, 3)
            Note { x: 30; y: 28; text: "Coming up" }
            Serif { x: 30; y: 70; visible: parent.ev.length === 0; text: "Nothing on"; font.pixelSize: 64; color: Qt.rgba(1, 1, 1, 0.5) }
            Repeater {
                model: parent.ev
                Item {
                    x: 30; y: 62 + index * 82; width: 452; height: 72
                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: "white"
                           font.family: Theme.face; font.pixelSize: 26; renderType: Text.QtRendering }
                    Mono { y: 38; size: 12; color: modelData.today ? Theme.timer : Theme.w62
                           text: modelData.when + (modelData.extra ? " · " + modelData.extra : "") }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08); visible: index < 2 }
                }
            }
        }
    }

    // ---------------------------------------------------------------- alarm: the next one
    Component {
        id: alarm
        Item {
            readonly property var na: room.things.nextAlarm || ({})
            readonly property bool has: na.h !== undefined
            readonly property int on: (room.things.alarms || []).filter(function (a) { return a.on }).length
            Note { x: 30; y: 28; text: "Next alarm" + (has && na.in ? " · in " + na.in : "") }
            Row {
                x: 30; y: 56
                Serif { id: aT; text: parent.parent.has ? Theme.hm(parent.parent.na.h, parent.parent.na.m, room.clock24) : "None"
                        font.pixelSize: 120; height: 120; color: parent.parent.has ? "white" : Qt.rgba(1, 1, 1, 0.35) }
                Serif { visible: parent.parent.has && !room.clock24; text: " " + Theme.ampm(parent.parent.na.h, false); font.pixelSize: 48
                        css: false; anchors.baseline: aT.baseline; transform: Translate { y: aT.shift } }
            }
            Note { x: 30; y: 222; text: parent.on === 0 ? "No alarms on" : parent.on === 1 ? "1 alarm on" : parent.on + " alarms on" }
        }
    }

    // ---------------------------------------------------------------- lights: the room it changed (or each of them)
    Component {
        id: lights
        Item {
            readonly property var rs: (room.rooms || []).filter(function (r) { return vc.lit.indexOf(r.name) >= 0 })
            readonly property var r: rs.length === 1 ? rs[0] : null
            readonly property color tint: r && r.glow && r.glow.length ? Qt.rgba(r.glow[0] / 255, r.glow[1] / 255, r.glow[2] / 255, 1) : "#ffc98f"
            // one room: its level big, its lamps
            Item {
                anchors.fill: parent; visible: !!parent.r
                readonly property var r: parent.r || ({})
                Note { x: 30; y: 28; width: 452; text: (parent.r.name || "") + (parent.r.on ? " · " + (parent.r.sub || "").split(" · ")[0] : "") }
                Row {
                    x: 30; y: 56
                    Serif { id: lv; text: parent.parent.r.on ? parent.parent.r.level : "Off"; font.pixelSize: 120; height: 120
                            color: parent.parent.r.on ? "white" : Qt.rgba(1, 1, 1, 0.45) }
                    Serif { visible: !!parent.parent.r.on; text: "%"; font.pixelSize: 48; css: false; anchors.baseline: lv.baseline; transform: Translate { y: lv.shift } }
                }
                Level { x: 30; y: 222; width: 452; f: parent.r.on ? (parent.r.level || 0) / 100 : 0; tint: parent.parent.tint }
                Note {
                    x: 30; y: 246; width: 452; size: 11; wrapMode: Text.WordWrap; maximumLineCount: 2
                    text: (parent.r.lamps || []).map(function (l) { return l.name + " " + (!l.reachable ? "away" : l.on ? l.level : "off") }).join(" · ")
                }
            }
            // several rooms: a line each
            Item {
                anchors.fill: parent; visible: parent.rs.length > 1
                Note { x: 30; y: 28; text: "Lights" }
                Repeater {
                    model: parent.parent.rs.slice(0, 4)
                    Item {
                        x: 30; y: 62 + index * 62; width: 452; height: 56
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: "white"
                               font.family: Theme.face; font.pixelSize: 24; renderType: Text.QtRendering }
                        Mono { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; size: 13
                               color: modelData.on ? "white" : Theme.w62; text: modelData.on ? modelData.level + "%" : "Off" }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                    }
                }
            }
        }
    }
}
