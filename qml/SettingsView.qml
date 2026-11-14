import QtQuick
import QtQuick.Controls.Basic

// The Settings screen (room-motion.html fillScreen('set')). Up top, to read: the screen's brightness big and how
// it's being set; the Wi-Fi network it's on and the Bluetooth speaker that's connected. Below on the left: automatic
// brightness (when there's a light sensor) and the brightness itself — sliding it turns automatic off; then this
// panel: the web browser (once the desktop is gone), switch to the desktop (while it's there) and shut down, each
// asking first. On the right, Wi-Fi or Bluetooth (the switch at the top): the networks around — join one (its
// password typed on the on-screen keyboard), connect to a saved one, forget one; or your Bluetooth devices and what's
// nearby — connect, disconnect, forget, pair. Search looks for more (it also searches while this screen is open).
// The battery sits in the top bar (Scene).
Item {
    id: sv
    width: 1368; height: 912
    property bool shown: false
    readonly property var disp: room.display || ({})
    readonly property var bt: room.bluetooth || ({})
    readonly property var devices: bt.devices || []
    // connected first, then the rest you've paired, then what's nearby
    readonly property var sorted: devices.filter(function (d) { return d.connected })
                                  .concat(devices.filter(function (d) { return d.paired && !d.connected }))
                                  .concat(devices.filter(function (d) { return !d.paired }))
    readonly property var connected: devices.filter(function (d) { return d.connected })
    readonly property var wifi: room.wifiState || ({})
    readonly property var nets: wifi.networks || []
    // which list is on the right: wifi · bt (Wi-Fi first when it isn't on any network)
    property string tab: ""
    readonly property string list_: tab !== "" ? tab : (wifi.current ? "bt" : "wifi")
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    onShownChanged: { if (shown) { room.wifiSearch(); room.btSearch() } else room.btStop() }
    readonly property bool sheetOpen: confirm.open || joiner.open
    function signalWord(p) { return p >= 70 ? "strong" : p >= 45 ? "good" : p >= 25 ? "weak" : "very weak" }

    component Rise: Item {
        id: rz
        property int order: 0
        opacity: sv.shown ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: sv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        transform: Translate {
            y: sv.shown ? 0 : 14
            Behavior on y { SequentialAnimation { PauseAnimation { duration: sv.shown ? 120 + rz.order * 35 : 0 } NumberAnimation { duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } } }
        }
    }

    // ---------------------------------------------------------------- to read: the screen
    Rise {
        order: 0
        x: 44; y: 126; width: 640; height: 220
        Mono { id: scrLbl; text: "Screen"; color: Theme.w62 }
        Row {
            y: 26
            Serif { id: bri; text: Math.round((bar.dragging ? bar.shown : (sv.disp.level || 0)) * 100); font.pixelSize: 120 }
            Serif { text: "%"; font.pixelSize: 48; css: false; anchors.baseline: bri.baseline; transform: Translate { y: bri.shift } }
        }
        Mono {
            y: 26 + 120 + 12; width: 640; wrapMode: Text.WordWrap; color: Theme.w62
            text: sv.disp.canSet === false ? "This screen's brightness can't be set from here"
                : sv.disp.sensor !== true ? "No light sensor, so it stays where you set it"
                : sv.disp.auto ? "Automatic · following the room's light" : "Set by hand · automatic is off"
        }
    }
    // ---------------------------------------------------------------- to read: Wi-Fi, then Bluetooth
    Rise {
        order: 1
        x: 744; y: 126; width: 580; height: 130
        Mono { text: "Wi-Fi"; color: Theme.w62 }
        Serif {
            y: 26; width: parent.width; elide: Text.ElideRight; font.pixelSize: 52
            text: sv.wifi.current ? sv.wifi.current : "Not connected"
            color: sv.wifi.current ? "white" : Theme.w62
        }
        Mono {
            y: 26 + 52 + 12; width: parent.width; elide: Text.ElideRight
            color: sv.wifi.note ? Theme.timer : Theme.w62
            text: sv.wifi.note ? sv.wifi.note
                : sv.wifi.ready !== true ? "Looking for Wi-Fi…"
                : sv.wifi.device === "" ? "No Wi-Fi on this panel"
                : sv.wifi.radio === false ? "Wi-Fi is off · Search turns it on"
                : sv.wifi.current ? "Connected" : "Pick a network below to join it"
        }
    }
    Rise {
        order: 2
        x: 744; y: 280; width: 580; height: 130
        Mono { text: "Bluetooth"; color: Theme.w62 }
        Serif {
            y: 26; width: parent.width; elide: Text.ElideRight; font.pixelSize: 52
            text: sv.connected.length ? sv.connected[0].name : "Nothing connected"
            color: sv.connected.length ? "white" : Theme.w62
        }
        Mono {
            y: 26 + 52 + 12; width: parent.width; elide: Text.ElideRight
            color: sv.bt.note ? Theme.timer : Theme.w62
            text: sv.bt.note ? sv.bt.note
                : sv.bt.powered === false ? "Bluetooth is off · searching turns it on"
                : sv.connected.length ? "Connected · AirPlay plays here" : "Put a speaker in pairing mode, then Search"
        }
    }

    // ---------------------------------------------------------------- brightness (lower left)
    Rise {
        order: 3
        x: 44; y: 524; width: 600; height: 360
        Mono { text: "Brightness"; color: Theme.w62 }
        Item {
            y: 32; width: 600; height: 44
            visible: sv.disp.sensor === true
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Automatic brightness"; color: "white"; font.family: Theme.face; font.pixelSize: 22; renderType: Text.QtRendering }
            Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: sv.disp.auto === true; onTapped: room.setAutoBrightness(!on) }
        }
        Seek {
            id: bar
            y: 86; width: 600
            enabled: sv.disp.canSet !== false
            value: sv.disp.level || 0
            every: 120
            label: Math.round(shown * 100) + "%"
            onMoved: (v) => room.setBrightness(Math.max(0.03, v))
            onReleased: (v) => room.setBrightness(Math.max(0.03, v))
        }
        Mono { y: 132; visible: sv.disp.sensor === true; color: Theme.w62; text: "Sliding it turns automatic off" }
        Mono { y: 182; visible: room.desktopNote !== ""; width: 600; wrapMode: Text.WordWrap; color: Theme.timer; text: room.desktopNote }
        Mono { y: 212; text: "This panel"; color: Theme.w62 }
        Row {
            y: 244; spacing: 10
            Chip { text: "More settings"; onTapped: more.open = true }
            Chip { visible: room.kiosk && room.browser && !room.desktop; text: room.browserOpen ? "Opening…" : "Web browser"; onTapped: room.openBrowser() }
            Chip { visible: room.kiosk && room.desktop; text: "Switch to desktop"; onTapped: { confirm.kind = "desktop"; confirm.open = true } }
            Chip { text: "Shut down"; onTapped: { confirm.kind = "off"; confirm.open = true } }
            Mono {
                visible: !room.kiosk; anchors.verticalCenter: parent.verticalCenter; leftPadding: 8
                size: 12; color: Theme.w62; text: "In the GNOME desktop · for just the panel: room-kiosk on, then restart"
            }
        }
    }

    // ---------------------------------------------------------------- Wi-Fi or Bluetooth (lower right)
    Rise {
        id: listBox
        order: 3
        x: 744; y: 524; width: 580; height: 360
        readonly property Item cur: sv.list_ === "bt" ? list : wlist
        // the switch: Wi-Fi · Bluetooth
        Row {
            y: -13; spacing: 8; height: 44
            Chip { text: "Wi-Fi"; warm: sv.list_ === "wifi"; onTapped: { sv.tab = "wifi"; room.wifiSearch() } }
            Chip { text: "Bluetooth"; warm: sv.list_ === "bt"; onTapped: { sv.tab = "bt"; room.btSearch() } }
        }
        Row {
            anchors.right: parent.right; y: -13; spacing: 4; height: 44
            Row {           // more than four: the arrows go through them
                visible: listBox.cur.pages > 1; spacing: 0
                Press { width: 44; height: 44; enabled: listBox.cur.page > 0; opacity: enabled ? 1 : 0.35; onTapped: listBox.cur.page--; Mono { anchors.centerIn: parent; text: "‹" } }
                Press { width: 44; height: 44; enabled: listBox.cur.page < listBox.cur.pages - 1; opacity: enabled ? 1 : 0.35; onTapped: listBox.cur.page++; Mono { anchors.centerIn: parent; text: "›" } }
            }
            Press {
                id: srch
                readonly property bool busy: sv.list_ === "bt" ? sv.bt.searching === true : sv.wifi.searching === true
                width: sr.width + 16; height: 44
                onTapped: if (!busy) { sv.list_ === "bt" ? room.btSearch() : room.wifiSearch() }
                Row {
                    id: sr
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        visible: srch.busy
                        width: 8; height: 8; radius: 4; color: "#ffbe7a"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            running: srch.busy && sv.shown; loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.25; duration: 700 }
                            NumberAnimation { from: 0.25; to: 1; duration: 700 }
                        }
                    }
                    Mono { text: srch.busy ? "Searching…" : "Search"; color: "white" }
                }
            }
        }

        // ---- Bluetooth: your devices and what's nearby
        Mono { y: 46; visible: sv.list_ === "bt" && sv.sorted.length === 0; color: Theme.w62; text: "Nothing paired yet" }
        Item {
            id: list
            visible: sv.list_ === "bt"
            y: 36; width: parent.width; height: 4 * 80
            clip: true
            property int page: 0
            readonly property int pages: Math.max(1, Math.ceil(sv.sorted.length / 4))
            onPagesChanged: if (page >= pages) page = pages - 1
            Column {
                y: -list.page * 4 * 80
                Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
                Repeater {
                    model: sv.sorted
                    Item {
                        id: dr
                        width: 580; height: 80
                        readonly property var d: modelData
                        readonly property string busy: d.busy || ""
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            width: parent.width - acts.width - 16
                            Text { width: parent.width; elide: Text.ElideRight; text: dr.d.name; color: "white"; font.family: Theme.face; font.pixelSize: 24; renderType: Text.QtRendering }
                            Mono {
                                width: parent.width; elide: Text.ElideRight; size: 12
                                color: dr.busy === "" && dr.d.connected ? Theme.timer : Theme.w62
                                text: dr.busy !== "" ? dr.busy
                                    : dr.d.connected ? (dr.d.kind ? dr.d.kind + " · " : "") + "connected" + (dr.d.kind === "Speaker" || !dr.d.kind ? " · AirPlay plays here" : "")
                                    : dr.d.paired ? (dr.d.kind ? dr.d.kind + " · " : "") + "paired"
                                    : (dr.d.kind ? dr.d.kind + " · " : "") + "nearby"
                            }
                        }
                        Row {
                            id: acts
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            opacity: dr.busy === "" ? 1 : 0.35
                            enabled: dr.busy === ""
                            Chip { visible: dr.d.connected; text: "Disconnect"; onTapped: room.btDisconnect(dr.d.mac) }
                            Chip { visible: dr.d.paired && !dr.d.connected; text: "Forget"; onTapped: room.btForget(dr.d.mac) }
                            Chip { visible: dr.d.paired && !dr.d.connected; solid: true; text: "Connect"; onTapped: room.btConnect(dr.d.mac) }
                            Chip { visible: !dr.d.paired; solid: true; text: "Pair"; onTapped: room.btPair(dr.d.mac) }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                    }
                }
            }
        }

        // ---- Wi-Fi: the networks around
        Mono { y: 46; visible: sv.list_ === "wifi" && sv.nets.length === 0; color: Theme.w62
               text: sv.wifi.searching ? "Looking for networks…" : "No networks found · Search again" }
        Item {
            id: wlist
            visible: sv.list_ === "wifi"
            y: 36; width: parent.width; height: 4 * 80
            clip: true
            property int page: 0
            readonly property int pages: Math.max(1, Math.ceil(sv.nets.length / 4))
            onPagesChanged: if (page >= pages) page = pages - 1
            Column {
                y: -wlist.page * 4 * 80
                Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
                Repeater {
                    model: sv.nets
                    Item {
                        id: wr
                        width: 580; height: 80
                        readonly property var n: modelData
                        readonly property string busy: n.busy || ""
                        // how strong: four bars
                        Row {
                            id: bars
                            anchors.verticalCenter: parent.verticalCenter; spacing: 3; height: 20
                            Repeater {
                                model: 4
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: 4; height: 6 + index * 4.5; radius: 1
                                    color: wr.n.signal >= [1, 30, 55, 75][index] ? "white" : Qt.rgba(1, 1, 1, 0.22)
                                }
                            }
                        }
                        Column {
                            x: bars.width + 16; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            width: parent.width - x - wacts.width - 16
                            Text { width: parent.width; elide: Text.ElideRight; text: wr.n.ssid; color: "white"; font.family: Theme.face; font.pixelSize: 24; renderType: Text.QtRendering }
                            Mono {
                                width: parent.width; elide: Text.ElideRight; size: 12
                                color: wr.busy === "" && wr.n.active ? Theme.timer : Theme.w62
                                text: wr.busy !== "" ? wr.busy
                                    : (wr.n.active ? "Connected" : wr.n.saved ? "Saved" : wr.n.secure ? "Password" : "Open")
                                      + " · " + sv.signalWord(wr.n.signal)
                            }
                        }
                        Row {
                            id: wacts
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                            opacity: wr.busy === "" ? 1 : 0.35
                            enabled: wr.busy === ""
                            Chip { visible: wr.n.saved; text: "Forget"; onTapped: { confirm.kind = "forget"; confirm.ssid = wr.n.ssid; confirm.open = true } }
                            Chip { visible: wr.n.saved && !wr.n.active; solid: true; text: "Connect"; onTapped: room.wifiJoin(wr.n.ssid, "") }
                            Chip {
                                visible: !wr.n.saved; solid: true; text: "Join"
                                onTapped: wr.n.secure ? joiner.ask(wr.n.ssid) : room.wifiJoin(wr.n.ssid, "")
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- switch to desktop / shut down: are you sure?
    // where the cats can be: the screen's brightness number, its slider's line (clear of the words), the bottom edge
    function catSpots(sc, out) {
        sc.catDigits(bri, "bri", true, out, scrLbl)
        var a = bar.mapToItem(sc, 280, 14), b = bar.mapToItem(sc, bar.width - 30, 14)
        out.push({ id: "slider", x0: a.x, x1: b.x, y: a.y })
        out.push({ id: "floor", x0: 430, x1: 700, floor: true })
    }
    readonly property bool sheetUp: confirm.open || joiner.open || more.open        // (the cats: up onto its top edge)
    readonly property real sheetTop: confirm.open ? confirm.paneTop : more.open ? more.paneTop : joiner.paneTop
    SheetFrame {
        id: confirm
        paneY: 560
        onClose: open = false
        property string kind: "off"             // off · desktop · forget (a Wi-Fi network)
        property string ssid: ""
        readonly property bool onIt: kind === "forget" && ssid === (sv.wifi.current || "")
        Serif {
            x: 36; y: 40; width: 1280 - 72; elide: Text.ElideRight; font.pixelSize: 64
            text: confirm.kind === "off" ? "Shut down the Surface?" : confirm.kind === "desktop" ? "Switch to the desktop?"
                : "Forget “" + confirm.ssid + "”?"
        }
        Mono {
            x: 36; y: 40 + 64 + 18; width: 1280 - 72; wrapMode: Text.WordWrap; color: Theme.w62
            text: confirm.kind === "off" ? "Room, AirPlay and Spotify stop until you press the power button to start it again."
                : confirm.kind === "desktop" ? "The Surface restarts into GNOME. To come back to just the panel: room-kiosk on, then restart."
                : confirm.onIt ? "The panel is on it now: it drops off Wi-Fi (music, lights and the assistant stop working) until you join a network again."
                : "Its password goes too. Join it again any time."
        }
        Row {
            x: 36; y: 40 + 64 + 18 + 60; spacing: 10
            Chip {
                solid: true; text: confirm.kind === "off" ? "Shut down" : confirm.kind === "desktop" ? "Restart to desktop" : "Forget"
                onTapped: {
                    confirm.open = false
                    if (confirm.kind === "off") room.shutDown()
                    else if (confirm.kind === "desktop") room.switchToDesktop()
                    else room.wifiForget(confirm.ssid)
                }
            }
            Chip { text: "Cancel"; onTapped: confirm.open = false }
        }
    }
    // ---------------------------------------------------------------- joining a network: its password
    SheetFrame {
        id: joiner
        paneY: 560
        onClose: open = false
        property string ssid: ""
        function ask(n) { ssid = n; pw.text = ""; pw.shown = false; open = true; pw.forceActiveFocus() }
        function join() { if (pw.text.length) { room.wifiJoin(ssid, pw.text); sv.tab = "wifi"; open = false } }
        Serif { x: 36; y: 36; width: 1280 - 72; elide: Text.ElideRight; font.pixelSize: 56; text: "Join “" + joiner.ssid + "”" }
        Mono { x: 36; y: 36 + 56 + 22; color: Theme.w62; text: "Password" }
        TextField {
            id: pw
            property bool shown: false
            // (for the on-screen keyboard: its enter key says Join, and joins)
            property string enterLabel: "Join"
            property bool enterAccepts: true
            x: 36; y: 36 + 56 + 46; width: 1280 - 72 - 150; height: 60
            echoMode: shown ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            font.family: Theme.face; font.pixelSize: 32
            color: "white"
            leftPadding: 0; topPadding: 0; bottomPadding: 0
            background: Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, pw.activeFocus ? 0.6 : 0.2) }
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            onAccepted: joiner.join()
        }
        Chip { x: 1280 - 36 - width; y: 36 + 56 + 54; text: pw.shown ? "Hide" : "Show"; onTapped: pw.shown = !pw.shown }
        Row {
            x: 36; y: 36 + 56 + 46 + 60 + 30; spacing: 10
            Chip { solid: true; text: "Join"; enabled: pw.text.length > 0; opacity: enabled ? 1 : 0.4; onTapped: joiner.join() }
            Chip { text: "Cancel"; onTapped: joiner.open = false }
        }
    }

    // ---------------------------------------------------------------- more settings: the panel's own (a sheet, in pages)
    // What used to be set in config.json by hand, set here instead (kept by Room, apart from config.json).
    readonly property var pv: room.panel || ({})
    function pget(k, d) { return pv[k] !== undefined ? pv[k] : d }
    function pset(k, v) { if (room.setPanel) room.setPanel(k, v) }
    function hourText(h) {
        if (pget("clock24", room.clock24)) return (h < 10 ? "0" : "") + h + ":00"
        return ((h % 12) || 12) + (h < 12 ? " am" : " pm")
    }
    function minText(s) { return Math.round(s / 60) + " min" }
    readonly property var mins: [60, 120, 180, 300, 600, 900, 1200, 1800]     // the steps for "after how long"
    function stepMin(s, d) {
        var i = 0; while (i < mins.length - 1 && mins[i] < s) i++
        return mins[Math.max(0, Math.min(mins.length - 1, i + d))]
    }
    // one setting: what it is (and a line under it), and its switch or stepper on the right
    component Line: Item {
        id: ln_
        property string label: ""
        property string sub: ""
        default property alias control: slot.data
        width: 572; height: 64
        Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 5; width: parent.width - slot.width - 24
            T { width: parent.width; text: ln_.label; font.pixelSize: 22; color: "white" }
            Mono { visible: ln_.sub !== ""; width: parent.width; text: ln_.sub; size: 12; color: Theme.w62 }
        }
        Item { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: childrenRect.width; height: childrenRect.height }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }
    }
    component Step: Row {
        id: st_
        property string value: ""
        signal less()
        signal more()
        spacing: 8
        Chip { text: "−"; padX: 16; onTapped: st_.less() }
        T { anchors.verticalCenter: parent.verticalCenter; width: 92; horizontalAlignment: Text.AlignHCenter; text: st_.value; font.pixelSize: 22; color: "white" }
        Chip { text: "+"; padX: 16; onTapped: st_.more() }
    }
    SheetFrame {
        id: more
        paneY: 520
        onClose: open = false
        property string page: "cats"
        Row {
            x: 36; y: 26; spacing: 10
            Repeater {
                model: [["cats", "Cats"], ["night", "Clock & night"], ["standby", "Standby"], ["sound", "Sound"], ["updates", "Updates"]]
                Chip { text: modelData[1]; warm: more.page === modelData[0]; onTapped: more.page = modelData[0] }
            }
        }
        Chip { x: 1280 - 36 - width; y: 26; text: "Done"; onTapped: more.open = false }

        // Bebo and Evan
        Column {
            visible: more.page === "cats"; x: 36; y: 92
            Line { label: "Bebo and Evan"; sub: "On every screen"
                   Toggle { on: sv.pget("cats", true); onTapped: sv.pset("cats", !on) } }
            Line { label: "Sleep at night"; sub: "Curled up from " + sv.hourText(sv.pget("nightStart", room.timing.nightStart)) + " to " + sv.hourText(sv.pget("nightEnd", room.timing.nightEnd))
                   opacity: sv.pget("cats", true) ? 1 : 0.4
                   Toggle { on: sv.pget("catsSleep", true); onTapped: sv.pset("catsSleep", !on) } }
        }
        // the clock, and when night is
        Column {
            visible: more.page === "night"; x: 36; y: 92
            Line { label: "24-hour clock"; sub: sv.pget("clock24", room.clock24) ? "16:30" : "4:30 pm"
                   Toggle { on: sv.pget("clock24", room.clock24); onTapped: sv.pset("clock24", !on) } }
            Line { label: "Night starts"; sub: "The screen dims · night standby"
                   Step { value: sv.hourText(sv.pget("nightStart", room.timing.nightStart))
                          onLess: sv.pset("nightStart", (sv.pget("nightStart", room.timing.nightStart) + 23) % 24)
                          onMore: sv.pset("nightStart", (sv.pget("nightStart", room.timing.nightStart) + 1) % 24) } }
            Line { label: "Night ends"; sub: "Back to day"
                   Step { value: sv.hourText(sv.pget("nightEnd", room.timing.nightEnd))
                          onLess: sv.pset("nightEnd", (sv.pget("nightEnd", room.timing.nightEnd) + 23) % 24)
                          onMore: sv.pset("nightEnd", (sv.pget("nightEnd", room.timing.nightEnd) + 1) % 24) } }
        }
        // how long before standby
        Column {
            visible: more.page === "standby"; x: 36; y: 92
            Line { label: "Home"; sub: "Nothing playing"
                   Step { value: sv.minText(sv.pget("homeIdleSec", room.timing.homeIdleSec))
                          onLess: sv.pset("homeIdleSec", sv.stepMin(sv.pget("homeIdleSec", room.timing.homeIdleSec), -1))
                          onMore: sv.pset("homeIdleSec", sv.stepMin(sv.pget("homeIdleSec", room.timing.homeIdleSec), 1)) } }
            Line { label: "Home, music playing"; sub: "Then the music standby"
                   Step { value: sv.minText(sv.pget("homePlayingSec", room.timing.homePlayingSec))
                          onLess: sv.pset("homePlayingSec", sv.stepMin(sv.pget("homePlayingSec", room.timing.homePlayingSec), -1))
                          onMore: sv.pset("homePlayingSec", sv.stepMin(sv.pget("homePlayingSec", room.timing.homePlayingSec), 1)) } }
            Line { label: "The music player"; sub: "Or a sheet over it"
                   Step { value: sv.minText(sv.pget("musicSec", room.timing.musicSec))
                          onLess: sv.pset("musicSec", sv.stepMin(sv.pget("musicSec", room.timing.musicSec), -1))
                          onMore: sv.pset("musicSec", sv.stepMin(sv.pget("musicSec", room.timing.musicSec), 1)) } }
        }
        Column {
            visible: more.page === "standby"; x: 36 + 572 + 64; y: 92
            Line { label: "Every other screen"; sub: "Weather, Clock, Lights, Reminders, Settings"
                   Step { value: sv.minText(sv.pget("menuStandbySec", room.timing.menuStandbySec))
                          onLess: sv.pset("menuStandbySec", sv.stepMin(sv.pget("menuStandbySec", room.timing.menuStandbySec), -1))
                          onMore: sv.pset("menuStandbySec", sv.stepMin(sv.pget("menuStandbySec", room.timing.menuStandbySec), 1)) } }
            Mono { width: 572; topPadding: 18; wrapMode: Text.WordWrap; size: 12; color: Theme.w62
                   text: "With no touch for this long, standby comes" }
        }
        // a newer Room: one tap checks, and if there is one, updates to it (Room restarts; if the new one doesn't
        // start, it goes back on its own)
        Column {
            id: upd
            visible: more.page === "updates"; x: 36; y: 92
            readonly property var u: room.update || ({})
            readonly property bool busy: u.state === "checking" || u.state === "updating"
            Line { label: "Room"; sub: "Version " + (upd.u.version || "")
                   Chip { solid: true; text: upd.busy ? (upd.u.state === "updating" ? "Updating…" : "Checking…") : "Check for updates"
                          opacity: upd.busy ? 0.5 : 1; onTapped: if (!upd.busy) room.checkForUpdate() } }
            Mono { visible: (upd.u.note || "") !== ""; width: 1208; topPadding: 16; size: 12
                   color: upd.u.state === "error" || upd.u.state === "back" ? Theme.timer : "white"; text: upd.u.note || "" }
            Repeater {
                model: upd.u.changes || []
                Mono { width: 1208; topPadding: 6; size: 12; color: Theme.w62; text: "· " + modelData }
            }
        }
        // the microphone, waking, the speakers
        Column {
            visible: more.page === "sound"; x: 36; y: 92
            Line { label: "Room's microphone"; sub: "Wakes the screen · the background moves with music"
                   Toggle { on: sv.pget("roomMic", true); onTapped: sv.pset("roomMic", !on) } }
            Line { label: "Wake on a sound"; sub: "Over the room's hum · lower wakes on less"
                   opacity: sv.pget("roomMic", true) ? 1 : 0.4
                   Step { value: sv.pget("wakeAbove", 10) + " dB"
                          onLess: sv.pset("wakeAbove", Math.max(3, sv.pget("wakeAbove", 10) - 1))
                          onMore: sv.pset("wakeAbove", Math.min(25, sv.pget("wakeAbove", 10) + 1)) } }
        }
        Column {
            visible: more.page === "sound"; x: 36 + 572 + 64; y: 92
            Line { label: "AirPlay to the speaker"; sub: "The Bluetooth one, when it's connected"
                   Toggle { on: sv.pget("airplayToBluetooth", true); onTapped: sv.pset("airplayToBluetooth", !on) } }
            Line { label: "Speaker limit"; sub: "Under full: at the very top they crackle"
                   Step { value: sv.pget("speakerHeadroomDb", 4) > 0 ? sv.pget("speakerHeadroomDb", 4) + " dB" : "None"
                          onLess: sv.pset("speakerHeadroomDb", Math.max(0, sv.pget("speakerHeadroomDb", 4) - 1))
                          onMore: sv.pset("speakerHeadroomDb", Math.min(12, sv.pget("speakerHeadroomDb", 4) + 1)) } }
        }
    }

    Component.onCompleted: {                    // (checks)
        if (startScreen === "setconfirm") { confirm.kind = "off"; confirm.open = true }
        if (startScreen.indexOf("setmore") === 0) { more.page = startScreen.slice(8) || "cats"; more.open = true }
        if (startScreen === "setmore-updates") room.checkForUpdate()
        if (startScreen === "setwifi") tab = "wifi"
        if (startScreen === "setjoin") { tab = "wifi"; joiner.ask("Airtel_Xstream_4410"); pw.text = "monsoon24" }
    }

}
