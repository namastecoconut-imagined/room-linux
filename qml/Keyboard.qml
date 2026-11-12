import QtQuick

// The on-screen keyboard (in the kiosk there's no other). It rises from the bottom whenever a text box is being typed
// in — the Wi-Fi password — and goes when it's done. Big keys, all in the lower part of the screen (the only part
// that answers touch): letters; 123 (numbers and punctuation); #+= (more symbols). Shift capitalises the next letter,
// twice in a row locks it; a sentence starts capitalised (not in a password). ⌫ repeats while held. The key on the
// right does what the box says (Join, Done…); the ⌄ key puts the keyboard away. A key types the moment it's touched
// (two thumbs can overlap), with a bubble above it showing what it typed.
Item {
    id: kb
    width: Theme.stageW; height: Theme.stageH
    property Item target: null          // the text box (Main: the window's focused item, if it's one that takes text)
    property bool allowed: true
    property Item sink: null            // where focus goes when the keyboard's put away
    readonly property bool up: allowed && target !== null
    readonly property real side: 18
    readonly property real gap: 10
    readonly property real rowH: 70
    readonly property real u: (width - 2 * side - 9 * gap) / 10        // one key
    readonly property real panelH: 18 + 4 * rowH + 3 * gap + 22
    readonly property real keysTop: height - panelH
    Binding { target: Typing; property: "target"; value: kb.up ? kb.target : null }
    Binding { target: Typing; property: "top"; value: kb.keysTop }

    property string page: "abc"         // abc · 123 · sym
    property int shift: 0               // 0 off · 1 the next letter · 2 locked
    property double shiftAt: 0
    readonly property bool secret: target !== null && target.echoMode !== undefined && target.echoMode !== TextInput.Normal
    onTargetChanged: { page = "abc"; autoShift() }
    // a sentence starts with a capital (not a password, or a box that says not to)
    function autoShift() {
        if (shift === 2) return
        var t = target
        if (!t || secret || (t.inputMethodHints & Qt.ImhNoAutoUppercase)) { shift = 0; return }
        var s = t.text.slice(0, t.cursorPosition)
        shift = s.length === 0 || /[.!?]\s+$/.test(s) ? 1 : 0
    }

    // ---------------------------------------------------------------- what the keys do
    function type(s) {
        var t = target
        if (!t) return
        if (t.selectedText.length) t.remove(t.selectionStart, t.selectionEnd)
        if (t.maximumLength > 0 && t.length >= t.maximumLength) return
        t.insert(t.cursorPosition, s)
    }
    function letter(c) {
        type(shift > 0 ? c.toUpperCase() : c)
        if (shift === 1) shift = 0
        autoShift()
    }
    function back() {
        var t = target
        if (!t) return
        if (t.selectedText.length) t.remove(t.selectionStart, t.selectionEnd)
        else if (t.cursorPosition > 0) t.remove(t.cursorPosition - 1, t.cursorPosition)
        autoShift()
    }
    function space() {
        type(" ")
        if (page !== "abc") page = "abc"
        autoShift()
    }
    function shiftKey() {
        var now = Date.now()
        if (shift === 2) shift = 0
        else if (shift === 1 && now - shiftAt < 400) shift = 2
        else shift = shift === 1 ? 0 : 1
        shiftAt = now
    }
    function enter() {
        var t = target
        if (!t) return
        if (t.enterAccepts === true) t.accepted()
        else hide()
    }
    function hide() {
        var t = target
        if (!t) return
        t.focus = false
        if (t.activeFocus && sink) sink.forceActiveFocus()
    }
    readonly property string enterLabel: target && target.enterLabel ? target.enterLabel : "Done"

    // ---------------------------------------------------------------- the rows
    // each key: [what it shows / types, how many keys wide (0: it shares what's left)]
    readonly property var pages: ({
        "abc": [[["q"], ["w"], ["e"], ["r"], ["t"], ["y"], ["u"], ["i"], ["o"], ["p"]],
                [["a"], ["s"], ["d"], ["f"], ["g"], ["h"], ["j"], ["k"], ["l"]],
                [["⇧", 0], ["z"], ["x"], ["c"], ["v"], ["b"], ["n"], ["m"], ["⌫", 0]],
                [["123", 1.5], ["⌄", 1], [" ", 0], ["↵", 2.2]]],
        "123": [[["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["0"]],
                [["-"], ["/"], [":"], [";"], ["("], [")"], ["₹"], ["&"], ["@"], ["\""]],
                [["#+=", 0], [".", 1.4], [",", 1.4], ["?", 1.4], ["!", 1.4], ["'", 1.4], ["⌫", 0]],
                [["ABC", 1.5], ["⌄", 1], [" ", 0], ["↵", 2.2]]],
        "sym": [[["["], ["]"], ["{"], ["}"], ["#"], ["%"], ["^"], ["*"], ["+"], ["="]],
                [["_"], ["\\"], ["|"], ["~"], ["<"], [">"], ["$"], ["€"], ["£"], ["•"]],
                [["123", 0], [".", 1.4], [",", 1.4], ["?", 1.4], ["!", 1.4], ["'", 1.4], ["⌫", 0]],
                [["ABC", 1.5], ["⌄", 1], [" ", 0], ["↵", 2.2]]]
    })
    // a row's keys placed: [label, x, width]
    function lay(row) {
        var fixed = 0, flex = 0, avail = width - 2 * side - (row.length - 1) * gap
        for (var i = 0; i < row.length; i++) {
            var w = row[i].length > 1 ? row[i][1] : 1
            if (w === 0) flex++; else fixed += w * u
        }
        var fw = flex ? Math.max(u, (avail - fixed) / flex) : 0
        var total = fixed + fw * flex + (row.length - 1) * gap
        var x = (width - total) / 2, out = []
        for (var j = 0; j < row.length; j++) {
            var kw = row[j].length > 1 ? (row[j][1] === 0 ? fw : row[j][1] * u) : u
            out.push([row[j][0], x, kw])
            x += kw + gap
        }
        return out
    }
    function act(k) {
        if (k === "⇧") shiftKey()
        else if (k === "⌫") back()
        else if (k === "123") page = "123"
        else if (k === "#+=") page = "sym"
        else if (k === "ABC") { page = "abc"; autoShift() }
        else if (k === "⌄") hide()
        else if (k === " ") space()
        else if (k === "↵") enter()
        else if (page === "abc") letter(k)
        else type(k)
    }

    // ---------------------------------------------------------------- the panel
    Item {
        id: panel
        x: -60; width: kb.width + 120
        height: kb.panelH + 60
        y: kb.up ? kb.keysTop : kb.height + 20
        opacity: kb.up ? 1 : 0
        visible: opacity > 0.002
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
        Behavior on opacity { NumberAnimation { duration: kb.up ? 200 : 360 } }
        // touches on the panel stay on it (between the keys too)
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#1c1510" }
                GradientStop { position: 1; color: "#0a0705" }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        Repeater {
            model: 4
            Item {
                id: rowI
                required property int index
                x: 60; y: 18 + index * (kb.rowH + kb.gap)
                width: kb.width; height: kb.rowH
                Repeater {
                    model: kb.lay(kb.pages[kb.page][rowI.index])
                    Key {}
                }
            }
        }
    }

    component Key: Item {
        id: k
        required property var modelData
        readonly property string key: modelData[0]
        readonly property bool special: ["⇧", "⌫", "123", "#+=", "ABC", "⌄", "↵", " "].indexOf(key) >= 0 && key !== " "
        readonly property bool glyph: !special && key !== " "
        readonly property bool down: tap.pressed
        x: modelData[1]; width: modelData[2]; height: kb.rowH
        // lit: shift on (white when locked); the enter key is the solid one
        readonly property bool lit: key === "⇧" && kb.shift > 0
        Rectangle {
            anchors.fill: parent; radius: 12
            color: k.key === "↵" ? (k.down ? "#e8ddd2" : "white")
                 : k.lit ? (kb.shift === 2 ? "white" : Qt.rgba(1, 1, 1, 0.42))
                 : k.down ? Qt.rgba(1, 1, 1, 0.34)
                 : k.special ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { ColorAnimation { duration: k.down ? 0 : 160 } }
        }
        Text {
            visible: k.glyph
            anchors.centerIn: parent
            text: kb.page === "abc" && kb.shift > 0 ? k.key.toUpperCase() : k.key
            color: "white"
            font.family: Theme.face; font.pixelSize: 30
            renderType: Text.QtRendering
        }
        Mono {
            visible: k.key === "123" || k.key === "#+=" || k.key === "ABC" || k.key === " " || k.key === "↵"
            anchors.centerIn: parent
            text: k.key === " " ? "space" : k.key === "↵" ? kb.enterLabel : k.key
            color: k.key === "↵" ? Theme.onWhite : k.key === " " ? Theme.w62 : "white"
        }
        Icon {
            visible: k.key === "⇧" || k.key === "⌫" || k.key === "⌄"
            anchors.centerIn: parent; size: 28
            name: k.key === "⇧" ? (kb.shift > 0 ? "shiftOn" : "shift") : k.key === "⌫" ? "bksp" : "kbdown"
            color: k.lit && kb.shift === 2 ? Theme.onWhite : "white"
        }
        // what it typed, in a bubble above the key
        Rectangle {
            visible: k.glyph && k.down
            x: -6; y: -84; width: k.width + 12; height: 78; radius: 14
            color: "#3a2d24"
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16)
            Text {
                anchors.centerIn: parent
                text: kb.page === "abc" && kb.shift > 0 ? k.key.toUpperCase() : k.key
                color: "white"; font.family: Theme.face; font.pixelSize: 44
                renderType: Text.QtRendering
            }
        }
        // ⌫ held: once, then over and over
        Timer {
            id: rep
            interval: 450; repeat: true
            running: k.key === "⌫" && k.down
            onRunningChanged: interval = 450
            onTriggered: { interval = 70; kb.back() }
        }
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.WithinBounds
            onPressedChanged: if (pressed) kb.act(k.key)
        }
    }
}
