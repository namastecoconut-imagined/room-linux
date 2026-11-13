import QtQuick

// The Reminders screen (room-motion.html fillScreen('rem')), kept on this panel only. Up top, to read: how many are
// left and how many are due today; on the right, how to add one — you ask the assistant ("Alexa, remind me to …"),
// with examples. Below: every reminder in two columns — tap one to tick it off (tap again to bring it back), hold it to
// delete it (it slides away). Four at a time; the arrows go through the rest (swiping isn't reliable on this screen).
// "+ Add a reminder" (here and in the top bar) starts the assistant listening for one: you just say what and when.
Item {
    id: rv
    width: 1368; height: 912
    property bool shown: false
    readonly property var list: room.things.reminders || []
    readonly property var open_: list.filter(function (r) { return !r.done })
    readonly property var dueToday: list.filter(function (r) { return !r.done && (r.today || r.dueNow) })
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    function add() { room.listenFor("reminder") }
    readonly property bool sheetOpen: false

    component Rise: Item {
        id: rz
        property int order: 0
        opacity: rv.shown ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: rv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        transform: Translate {
            y: rv.shown ? 0 : 14
            Behavior on y { SequentialAnimation { PauseAnimation { duration: rv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        }
    }

    // ---------------------------------------------------------------- to read
    // Kasero only at headline size (its stencil cuts are made for big type); the rest in Inter Tight and mono
    function catSpots(sc, out) {
        if (open_.length > 0) sc.catDigits(cnt, "count", true, out, remLbl)
        grid.catSpots(sc, out)
        out.push({ id: "floor", x0: 330, x1: 1040, floor: true })
    }
    Rise {
        order: 0
        x: 44; y: 126; width: 660; height: 300
        Mono { id: remLbl; text: "Reminders"; color: Theme.w62 }
        // none left: a headline, then what it means
        Serif { y: 40; visible: rv.open_.length === 0; text: "All clear"; font.pixelSize: 132; tracking: -0.03 }
        Text { y: 40 + 132 + 20; visible: rv.open_.length === 0; text: "Nothing to remember"; color: Theme.w62; font.pixelSize: 30; font.family: Theme.face; renderType: Text.QtRendering }
        // some: the count, big, and what it counts
        Row {
            y: 26; visible: rv.open_.length > 0; spacing: 20
            Serif { id: cnt; text: rv.open_.length; font.pixelSize: 150 }
            Text { anchors.baseline: cnt.baseline; transform: Translate { y: cnt.shift }
                   text: "to remember"; color: "white"; font.pixelSize: 34; font.family: Theme.face; renderType: Text.QtRendering }
        }
        Mono { y: 26 + 150 + 18; visible: rv.open_.length > 0 && rv.dueToday.length > 0; color: Theme.timer; text: rv.dueToday.length + " due today" }
    }
    // how to add one: ask — the part you'd change is white, the pattern dimmed
    Rise {
        order: 1
        x: 764; y: 126; width: 560; height: 300
        Mono { text: "To add one, ask Alexa"; color: Theme.w62 }
        Column {
            y: 40; width: parent.width; spacing: 14
            Repeater {
                model: ["water the plants at six", "call the bank tomorrow"]
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.StyledText
                    color: "white"; font.pixelSize: 30; font.family: Theme.face; renderType: Text.QtRendering
                    text: "<font color=\"#8cffffff\">“Remind me to</font> " + modelData + "<font color=\"#8cffffff\">”</font>"
                }
            }
        }
        Mono {
            y: 40 + 2 * 50 + 22; width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.6; size: 12; color: Theme.w62
            text: "Or tap + Add a reminder and just say what and when. When one's due, Room chimes and keeps it on standby until you tick it off."
        }
    }

    // ---------------------------------------------------------------- the list: two columns, four at a time
    Rise {
        order: 2
        x: 44; y: 524; width: 1280; height: 360
        Mono { text: "All reminders"; color: Theme.w62 }
        Mono { anchors.right: parent.right; visible: rv.list.length > 0; text: "Tap to tick off · hold to delete"; color: Theme.w62 }
        Text { y: 46; visible: rv.list.length === 0; text: "New reminders show up here."; color: Theme.w42; font.pixelSize: 26; font.family: Theme.face; renderType: Text.QtRendering }
        GridView {
            id: grid
            // where the cats can be: each row's line, on its right (clear of the words) — a reminder about the cats
            // is their favourite
            function catSpots(sc, out) {
                for (var i = 0; i < 4; i++) {
                    var idx = page * 4 + i; if (idx >= count) break
                    var m = rv.list[idx], col = i % 2, r = Math.floor(i / 2)
                    var a = grid.mapToItem(sc, col * cellWidth + 380, r * cellHeight + 80 - contentY + page * 192)
                    var fav = /\b(cats?|kittens?|bebo|evan|litter|vet)\b/i.test(m.text || "")
                    out.push({ id: "row" + i, x0: a.x, x1: a.x + 220, y: a.y, fav: fav })
                }
            }
            y: 36; width: 1280 + 24; height: 192
            cellWidth: 652; cellHeight: 96
            flow: GridView.FlowLeftToRight
            interactive: false; clip: true
            model: rv.list
            property int page: 0
            readonly property int pages: Math.max(1, Math.ceil(count / 4))
            onCountChanged: if (page >= pages) page = pages - 1
            contentY: page * 192
            Behavior on contentY { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            delegate: Item {
                id: row
                width: 628; height: 80
                property bool going: false
                opacity: going ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 420 } }
                transform: Translate { x: row.going ? -40 : 0; Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.InCubic } } }
                Timer { id: gone; interval: 450; onTriggered: room.deleteReminder(modelData.id) }
                Press {
                    anchors.fill: parent; pressScale: 0.985
                    onTapped: room.toggleReminder(modelData.id)
                    onHeld: { row.going = true; gone.start() }
                    Rectangle {         // the tick
                        x: 0; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; radius: 15
                        color: modelData.done ? "#ffbe7a" : "transparent"
                        border.width: modelData.done ? 0 : 2; border.color: Qt.rgba(1, 1, 1, 0.5)
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Icon { anchors.centerIn: parent; visible: modelData.done; name: "check"; size: 16; color: "#1a0f08" }
                    }
                    Column {
                        x: 50; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        opacity: modelData.done ? 0.45 : 1
                        Behavior on opacity { NumberAnimation { duration: 400 } }
                        Text {
                            width: 560; elide: Text.ElideRight
                            text: modelData.text; color: "white"; font.strikeout: modelData.done
                            font.family: Theme.face; font.pixelSize: 26; renderType: Text.QtRendering
                        }
                        Mono {
                            visible: (modelData.when || "") !== ""
                            size: 12; text: modelData.when || ""
                            color: !modelData.done && (modelData.today || modelData.dueNow) ? Theme.timer : Theme.w62
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
            }
        }
        Chip { y: 288; solid: true; text: "+ Add a reminder"; onTapped: rv.add() }
        Row {           // more than four: the arrows go through them
            anchors.right: parent.right; y: 288; spacing: 10
            visible: grid.pages > 1
            Mono {
                anchors.verticalCenter: parent.verticalCenter; rightPadding: 6; color: Theme.w62
                text: (grid.page * 4 + 1) + "–" + Math.min(grid.count, grid.page * 4 + 4) + " of " + grid.count
            }
            Chip { text: "‹"; padX: 22; opacity: grid.page > 0 ? 1 : 0.35; enabled: grid.page > 0; onTapped: grid.page-- }
            Chip { text: "›"; padX: 22; opacity: grid.page < grid.pages - 1 ? 1 : 0.35; enabled: grid.page < grid.pages - 1; onTapped: grid.page++ }
        }
    }
}
