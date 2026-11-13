import QtQuick
import QtQuick.Effects
import "../../qml"
import "demo.js" as Demo

// YouTube in Room's look. An app: Room loads this when you open it (Home → Apps) and throws all of it away when you
// close it, so nothing of it runs otherwise. (The screens for now, with made-up videos from demo.js.)
//
// Laid out like Room's own screens on the 1368 × 912 stage: the top bar and the lower part (y 500 down) are where you
// tap; the band between doesn't feel touch (Theme.deadA0–deadB1), so it shows what's there to read — the video you've
// picked, big. Lists go a page at a time with the arrows (swiping isn't reliable on this screen).
//  • Browse: Subscriptions · Home · Watch later. Tap a video to pick it (it comes up big above); tap it again to play.
//  • Search: the keyboard comes up; recent searches sit just above it. Search shows the results the same way.
//  • The player: see Player.qml.
Item {
    id: app
    width: Theme.stageW; height: Theme.stageH
    signal close()
    property string start: ""                  // (checks) where to open: browse · search · results · player · playerbare
    property string page: "browse"             // browse · search · player
    property string tab: "subs"                // subs · home · later · results
    property string query: ""
    readonly property var list: tab === "results" ? Demo.search : (Demo.feeds[tab] || [])
    property int sel: 0
    readonly property var cur: list.length ? list[Math.min(sel, list.length - 1)] : null
    property var video: null                   // what's playing
    property real now: Date.now()
    Timer { interval: 10000; running: true; repeat: true; onTriggered: app.now = Date.now() }

    function pick(i) { if (i === sel) play(list[i]); else sel = i }
    function play(v) { video = v; page = "player" }
    function setTab(t) { tab = t; sel = 0; strip.page = 0 }
    function search(q) { query = q || field.text; if (query === "") return; field.focus = false; setTab("results"); page = "browse" }
    function openSearch() { page = "search"; field.text = ""; field.forceActiveFocus() }
    function back() {
        if (page === "player") page = "browse"
        else if (page === "search") { field.focus = false; page = "browse" }
        else if (tab === "results") setTab("subs")
        else app.close()
    }

    Component.onCompleted: {
        if (start === "search") { page = "search"; field.text = "lo-fi bea"; field.forceActiveFocus() }
        else if (start === "results") { query = "lo-fi beats"; tab = "results"; sel = 1 }
        else if (start === "player" || start === "playerbare") { video = Demo.subs[0]; page = "player"; player.controls = start === "player" }
        else if (start === "browse2") { sel = 2 }
    }

    // ---------------------------------------------------------------- behind it all: the picked video, blurred
    Rectangle { anchors.fill: parent; color: "#0b0807" }
    Item {
        id: bg
        anchors.fill: parent
        readonly property string src: app.cur ? app.cur.thumb : ""
        property bool front: false                  // which of the two layers shows the newest
        property string a: ""
        property string b: ""
        onSrcChanged: { if (front) a = src; else b = src; front = !front }
        Component.onCompleted: { a = src; front = false }
        component Wash: Item {
            id: w
            property alias source: im.source
            property bool on: false
            anchors.fill: parent
            opacity: on ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
            visible: opacity > 0.002
            Image { id: im; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; sourceSize.width: 320; visible: false; asynchronous: true }
            MultiEffect {
                anchors.fill: parent; source: im; autoPaddingEnabled: false
                blurEnabled: true; blur: 1.0; blurMax: 64; saturation: 0.25; brightness: -0.08
            }
        }
        Wash { source: bg.a; on: !bg.front }
        Wash { source: bg.b; on: bg.front }
        // dark enough to read on, darkest at the bottom where the lists are
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(10 / 255, 7 / 255, 6 / 255, 0.42) }
                GradientStop { position: 0.5; color: Qt.rgba(10 / 255, 7 / 255, 6 / 255, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(10 / 255, 7 / 255, 6 / 255, 0.86) }
            }
        }
    }

    component Fade: Item {
        property bool on: true
        opacity: on ? 1 : 0
        visible: opacity > 0.002
        Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    }

    // ---------------------------------------------------------------- the top bar
    Fade {
        on: app.page !== "player"
        x: 0; y: 34; width: 1368; height: 44
        Press {
            id: backB
            x: 36; width: backR.implicitWidth + 16; height: 44; pressScale: 0.94
            reachTop: 34; reachBottom: 30
            onTapped: app.back()
            Row {
                id: backR
                anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 10
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "back"; size: 20; color: "white" }
                Mono { anchors.verticalCenter: parent.verticalCenter; text: app.page === "browse" && app.tab !== "results" ? "Home" : "YouTube" }
            }
        }
        Mono {
            x: backB.x + backB.width + 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.w62
            text: app.page === "search" || app.tab === "results" ? "/ Search" : "/ YouTube"
        }
        Serif { x: 652; y: 4; text: Theme.clock(new Date(app.now), room.clock24); font.pixelSize: 50; tracking: -0.03 }
        Press {
            visible: app.page === "browse"
            anchors.right: parent.right; anchors.rightMargin: 36
            width: srR.implicitWidth + 32; height: 44; pressScale: 0.95
            reachTop: 34; reachRight: 36; reachBottom: 30
            onTapped: app.openSearch()
            Rectangle { anchors.fill: parent; radius: 9; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.24) }
            Row {
                id: srR
                anchors.centerIn: parent; spacing: 9
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: "white" }
                Mono { anchors.verticalCenter: parent.verticalCenter; text: "Search" }
            }
        }
    }

    // ---------------------------------------------------------------- browse: the picked video, big (to read)
    Fade {
        id: hero
        on: app.page === "browse" && app.cur !== null
        x: 44; y: 134; width: 1280; height: 340
        readonly property var v: app.cur || ({})
        Art {
            id: heroArt
            width: 560; height: 315; radius: 14
            source: hero.v.thumb || ""
            rgb: [60, 44, 36]; rgb2: [20, 16, 14]
        }
        Badge { anchors.right: heroArt.right; anchors.bottom: heroArt.bottom; anchors.margins: 14; text: hero.v.duration || "" }
        Watched { x: 14; width: heroArt.width - 28; anchors.bottom: heroArt.bottom; anchors.bottomMargin: 8; value: hero.v.progress || 0 }
        Column {
            x: 604; width: 676; spacing: 0
            Mono { text: hero.v.channel || ""; color: Theme.w62; bottomPadding: 18 }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                text: hero.v.title || ""; color: "white"; lineHeight: 1.06
                font.family: Theme.face; font.pixelSize: 44; renderType: Text.QtRendering
            }
            Mono {
                topPadding: 18; width: parent.width; size: 13; color: Theme.w62
                text: (hero.v.views || "") + "  ·  " + (hero.v.age || "")
            }
            Text {
                topPadding: 16; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                visible: (hero.v.desc || "") !== ""
                text: hero.v.desc || ""; color: Theme.w62; lineHeight: 1.2
                font.family: Theme.face; font.pixelSize: 20; renderType: Text.QtRendering
            }
        }
        Mono {
            x: 604; y: 315 - 14; size: 13
            color: (hero.v.progress || 0) > 0 && (hero.v.progress || 0) < 1 ? Theme.timer : Theme.w42
            text: (hero.v.progress || 0) >= 1 ? "Watched  ·  tap it again to watch again"
                : (hero.v.progress || 0) > 0 ? "Carry on  ·  " + Math.round((1 - hero.v.progress) * app.secs(hero.v.duration) / 60) + " min left  ·  tap it again"
                : "Tap it again to play"
        }
    }
    function secs(d) { var p = (d || "0").split(":").map(Number), s = 0; for (var i = 0; i < p.length; i++) s = s * 60 + p[i]; return s }

    // a video's length, on its picture
    component Badge: Rectangle {
        property alias text: bt.text
        width: bt.implicitWidth + 16; height: 26; radius: 6
        color: Qt.rgba(8 / 255, 6 / 255, 5 / 255, 0.72)
        visible: text !== ""
        Mono { id: bt; anchors.centerIn: parent; size: 12; color: "white" }
    }
    // how much of it you've watched: a warm line along the bottom of the picture
    component Watched: Item {
        property real value: 0
        height: 4; visible: value > 0
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.28) }
        Rectangle { width: parent.width * Math.min(1, parent.value); height: parent.height; radius: 2; color: Theme.warm }
    }

    // ---------------------------------------------------------------- browse: the lists (the lower part — to tap)
    Fade {
        on: app.page === "browse"
        x: 44; y: 516; width: 1280; height: 380
        Row {
            spacing: 10
            Chip { visible: app.tab !== "results"; text: "Subscriptions"; warm: app.tab === "subs"; onTapped: app.setTab("subs") }
            Chip { visible: app.tab !== "results"; text: "Home"; warm: app.tab === "home"; onTapped: app.setTab("home") }
            Chip { visible: app.tab !== "results"; text: "Watch later"; warm: app.tab === "later"; onTapped: app.setTab("later") }
            Chip { visible: app.tab === "results"; text: "“" + app.query + "”"; warm: true; onTapped: app.openSearch() }
            Chip { visible: app.tab === "results"; text: "New search"; onTapped: app.openSearch() }
        }
        Row {           // more than four: the arrows go through them
            anchors.right: parent.right; spacing: 10
            visible: strip.pages > 1
            Mono {
                anchors.verticalCenter: parent.verticalCenter; rightPadding: 6; color: Theme.w62
                text: (strip.page * 4 + 1) + "–" + Math.min(app.list.length, strip.page * 4 + 4) + " of " + app.list.length
            }
            Chip { text: "‹"; padX: 22; opacity: strip.page > 0 ? 1 : 0.35; enabled: strip.page > 0; onTapped: strip.page-- }
            Chip { text: "›"; padX: 22; opacity: strip.page < strip.pages - 1 ? 1 : 0.35; enabled: strip.page < strip.pages - 1; onTapped: strip.page++ }
        }
        ListView {
            id: strip
            y: 68; width: 1280 + 24; height: 300
            orientation: ListView.Horizontal; spacing: 24; clip: true
            interactive: false
            model: app.list
            property int page: 0
            readonly property int pages: Math.max(1, Math.ceil(count / 4))
            contentX: originX + page * 4 * (302 + 24)
            Behavior on contentX { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            delegate: Press {
                id: tile
                width: 302; height: 300; pressScale: 0.97
                readonly property bool picked: index === app.sel
                onTapped: app.pick(index)
                Art { id: ta; width: 302; height: 170; radius: 10; source: modelData.thumb; rgb: [60, 44, 36]; rgb2: [20, 16, 14] }
                Rectangle {          // picked: a white ring just inside the picture's edge
                    anchors.fill: ta; radius: 10
                    color: "transparent"; border.width: 3; border.color: "white"
                    opacity: tile.picked ? 0.95 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
                Badge { anchors.right: ta.right; anchors.bottom: ta.bottom; anchors.margins: 10; text: modelData.duration }
                Watched { x: 10; width: ta.width - 20; anchors.bottom: ta.bottom; anchors.bottomMargin: 6; value: modelData.progress || 0 }
                Rectangle {          // picked: tap again to play
                    anchors.centerIn: ta; width: 64; height: 64; radius: 32; color: "white"
                    opacity: tile.picked ? 0.95 : 0; scale: tile.picked ? 1 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
                    Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 3; name: "play"; size: 28; color: Theme.onWhite }
                }
                Text {
                    y: 186; width: 302; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    text: modelData.title; color: tile.picked ? "white" : Qt.rgba(1, 1, 1, 0.82); lineHeight: 1.08
                    font.family: Theme.face; font.pixelSize: 20; renderType: Text.QtRendering
                }
                Mono { y: 248; width: 302; size: 12; color: Theme.w62; text: modelData.channel + "  ·  " + modelData.age }
            }
        }
    }

    // ---------------------------------------------------------------- search: what you type, big; recent above the keys
    Fade {
        on: app.page === "search"
        x: 44; y: 134; width: 1280; height: 430
        Mono { text: "Search YouTube"; color: Theme.w62 }
        TextInput {
            id: field
            y: 52; width: 1280; height: 120
            property string enterLabel: "Search"
            property bool enterAccepts: true
            onAccepted: app.search()
            color: "white"; selectionColor: Theme.warm
            font.family: Theme.serif; font.pixelSize: 104
            clip: true
            cursorDelegate: Rectangle {
                width: 3; color: Theme.warm
                SequentialAnimation on opacity { loops: Animation.Infinite; running: field.activeFocus
                    NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine } NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine } }
            }
            Serif {
                visible: field.text === ""
                text: "What would you like to watch?"; color: Theme.w42; font.pixelSize: 104; css: false
            }
        }
        Mono {
            y: 210; width: 900; wrapMode: Text.WordWrap; lineHeight: 1.6; size: 12; color: Theme.w62
            text: "Type, then Search. Or tap one you looked for before."
        }
        Row {           // just above the keyboard: the part of the screen that answers touch
            y: 374; spacing: 10
            Mono { anchors.verticalCenter: parent.verticalCenter; text: "Recent"; color: Theme.w62; rightPadding: 8 }
            Repeater {
                model: Demo.recent
                Chip { text: modelData; onTapped: { field.text = modelData; app.search(modelData) } }
            }
        }
    }

    // ---------------------------------------------------------------- playing
    Player {
        id: player
        anchors.fill: parent
        video: app.video
        visible: opacity > 0.002
        opacity: app.page === "player" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
        now: app.now
        onBack: app.back()
    }
}
