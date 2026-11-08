import QtQuick

// The answer cards beside the assistant's reply (the phone's renderCard): plain type on black, one thing per line,
// plenty of room. weather · forecast · air · timer · music · schedule · alarm
Item {
    id: ac
    property string kind: ""
    implicitHeight: Math.max(288, col.implicitHeight)
    readonly property color mut: Qt.rgba(246 / 255, 239 / 255, 232 / 255, 0.52)
    readonly property color tx: Qt.rgba(246 / 255, 239 / 255, 232 / 255, 1)
    readonly property color blue: Qt.rgba(159 / 255, 196 / 255, 1, 1)
    readonly property var wx: room.weather || {}
    readonly property var timers: (room.things.timers || [])
    readonly property var m: room.music || {}

    component Head: Item {
        property alias text: ht.text
        width: ac.width; height: 53
        Text { id: ht; font.family: Theme.face; font.pixelSize: 23; font.weight: Font.Medium; font.letterSpacing: 4.3; font.capitalization: Font.AllUppercase; color: ac.mut; renderType: Text.QtRendering }
    }
    component Row2: Item {
        property bool first: false
        property string a: ""
        property string b: ""
        property string c: ""          // a muted second part on the right (the low)
        property bool small: false
        width: ac.width; height: 101
        Rectangle { visible: !parent.first; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
        Text { y: 29; text: parent.a; color: ac.tx; font.family: Theme.face; font.pixelSize: 34; renderType: Text.QtRendering }
        Text {
            y: 29; anchors.right: parent.right
            textFormat: Text.StyledText
            text: parent.b + (parent.c ? "&nbsp;&nbsp;<font color='#85" + "f6efe8'>" + parent.c + "</font>" : "")
            color: parent.small ? ac.mut : ac.tx
            font.family: Theme.face; font.pixelSize: parent.small ? 31 : 34; renderType: Text.QtRendering
            font.features: { "tnum": 1 }
        }
    }
    component Note: Item {
        property alias text: nt.text
        property alias color: nt.color
        width: ac.width; height: nt.text ? 72 : 0
        Text { id: nt; y: 24; width: parent.width; color: ac.mut; font.family: Theme.face; font.pixelSize: 29; renderType: Text.QtRendering; elide: Text.ElideRight }
    }
    component Big: Column {
        property alias text: bt.text
        property alias unit: bu.text
        width: ac.width
        Text { id: bt; height: 130; color: ac.tx; font.family: Theme.face; font.pixelSize: 110; font.weight: Font.Light; renderType: Text.QtRendering; font.features: { "tnum": 1 } }
        Item { width: 1; height: bu.text ? 58 : 0; Text { id: bu; color: ac.mut; font.family: Theme.face; font.pixelSize: 31; renderType: Text.QtRendering } }
    }
    component Bar: Item {
        property real f: 0
        width: ac.width; height: 48
        Rectangle {
            y: 14; width: parent.width; height: 7; radius: 3.5; color: Qt.rgba(1, 1, 1, 0.1)
            Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.parent.f)); height: 7; radius: 3.5; color: Theme.accent
                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } } }
        }
    }

    function hr(h) { return room.clock24 ? Theme.two(h) + ":00" : ((h % 12) || 12) + (h < 12 ? " am" : " pm") }
    function clockOf(s) { s = Math.max(0, Math.round(s)); return s >= 3600 ? Math.floor(s / 3600) + ":" + Theme.two(Math.floor(s % 3600 / 60)) : Math.floor(s / 60) + ":" + Theme.two(s % 60) }

    Column {
        id: col
        width: ac.width

        // weather — now, then three hours ahead
        Head { visible: ac.kind === "weather"; text: "Now · Bangalore" }
        Big { visible: ac.kind === "weather" && ac.wx.ok === true; text: (ac.wx.t !== undefined ? ac.wx.t : "–") + "°"; unit: Theme.cap(ac.wx.d) + " · feels " + ac.wx.feels + "°" }
        Repeater {
            model: ac.kind === "weather" ? (ac.wx.hours || []).filter(function (h, i) { return i % 3 === 2 }).slice(0, 3) : []
            Row2 { first: index === 0; a: ac.hr(modelData.h); b: modelData.t + "°" }
        }
        Note { visible: (ac.kind === "weather" || ac.kind === "forecast") && ac.wx.ok !== true; text: "still loading…" }

        // forecast — the next three days
        Head { visible: ac.kind === "forecast"; text: "Next three days" }
        Repeater {
            model: ac.kind === "forecast" ? (ac.wx.days || []).slice(0, 3) : []
            Row2 { first: index === 0; a: index === 0 ? "Today" : modelData.name; b: modelData.hi + "°"; c: modelData.lo + "°" }
        }
        Note {
            readonly property var rd: ac.kind === "forecast" ? (ac.wx.days || []).slice(0, 3).filter(function (d) { return d.p >= 40 })[0] : undefined
            visible: !!rd; color: ac.blue
            text: rd ? "Rain likely " + (rd.name === "Today" ? "today" : rd.name) + " · " + rd.p + "%" : ""
        }

        // air quality
        Head { visible: ac.kind === "air"; text: "Air quality" }
        Big { visible: ac.kind === "air"; text: ac.wx.aqi ? "" + ac.wx.aqi : "–"; unit: ac.wx.aqi ? Theme.cap(Theme.aqiWord(ac.wx.aqi)) : "not available" }
        Note { visible: ac.kind === "air" && !!ac.wx.aqi; text: ac.wx.aqi > 100 ? "Maybe keep the windows shut" : "Fine to air the room" }

        // timer
        Head { visible: ac.kind === "timer"; text: ac.timers.length ? (ac.timers[0].label || "Timer") : "Timers" }
        Big { visible: ac.kind === "timer" && ac.timers.length > 0; text: ac.timers.length ? ac.clockOf(ac.timers[0].left) : "" }
        Bar { visible: ac.kind === "timer" && ac.timers.length > 0; f: ac.timers.length ? 1 - ac.timers[0].left / Math.max(1, ac.timers[0].total) : 0 }
        Note { visible: ac.kind === "timer"; text: ac.timers.length > 1 ? (ac.timers.length - 1) + " more running" : ac.timers.length ? "" : "No timers running" }

        // music
        Head { visible: ac.kind === "music"; text: ac.m.exists ? (ac.m.playing ? "Playing" : "Paused") : "Music" }
        Text {
            visible: ac.kind === "music"; width: ac.width
            text: ac.m.exists ? ac.m.title : "Nothing playing"
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            color: ac.tx; font.family: Theme.face; font.pixelSize: 43; font.weight: Font.Medium; renderType: Text.QtRendering
            bottomPadding: 14
        }
        Item { visible: ac.kind === "music" && !!ac.m.exists; width: ac.width; height: 72
            Text { text: ac.m.artist || ""; width: parent.width; elide: Text.ElideRight; color: ac.mut; font.family: Theme.face; font.pixelSize: 34; renderType: Text.QtRendering } }
        Bar { visible: ac.kind === "music" && !!ac.m.exists; f: ac.m.duration ? (ac.m.position || 0) / ac.m.duration : 0 }

        // schedule
        Head { visible: ac.kind === "schedule"; text: "Coming up" }
        Note { visible: ac.kind === "schedule" && !(room.events || []).length; text: "Nothing on the calendar" }
        Repeater {
            model: ac.kind === "schedule" ? (room.events || []).slice(0, 3) : []
            Item {
                width: ac.width; height: 130
                Rectangle { visible: index > 0; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                Text { y: 24; text: modelData.when + (modelData.extra ? " · " + modelData.extra : ""); color: ac.mut; font.family: Theme.face; font.pixelSize: 29; renderType: Text.QtRendering }
                Text { y: 65; width: parent.width; elide: Text.ElideRight; text: modelData.title; color: ac.tx; font.family: Theme.face; font.pixelSize: 34; renderType: Text.QtRendering }
            }
        }

        // alarms
        Head { visible: ac.kind === "alarm"; text: "Alarms" }
        Repeater {
            id: alarms
            model: ac.kind === "alarm" ? (room.things.alarms || []).filter(function (a) { return a.on }).slice(0, 3) : []
            Row2 { first: index === 0; small: true
                a: Theme.hm(modelData.h, modelData.m, room.clock24) + (room.clock24 ? "" : " " + Theme.ampm(modelData.h, false))
                b: modelData.daysText || "Once" }
        }
        Note { visible: ac.kind === "alarm" && alarms.count === 0; text: "No alarms set" }
    }
}
