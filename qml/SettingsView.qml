import QtQuick

// The Settings screen (room-motion.html fillScreen('set')). Up top, to read: the screen's brightness big and how
// it's being set; the Bluetooth speaker that's connected, big. Below on the left: automatic brightness (when there's
// a light sensor) and the brightness itself — sliding it turns automatic off; then this panel: the web browser (once
// the desktop is gone), switch to the desktop (while it's there) and shut down, each asking first. On the right: your
// Bluetooth devices and what's nearby — connect, disconnect, forget, pair; Search looks for more (it also searches
// while this screen is open). The battery sits in the top bar (Scene).
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
    visible: opacity > 0.002
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    onShownChanged: shown ? room.btSearch() : room.btStop()
    readonly property bool sheetOpen: confirm.open

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
        Mono { text: "Screen"; color: Theme.w62 }
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
    // ---------------------------------------------------------------- to read: Bluetooth
    Rise {
        order: 1
        x: 744; y: 126; width: 580; height: 220
        Mono { text: "Bluetooth"; color: Theme.w62 }
        Serif {
            y: 26; width: parent.width; elide: Text.ElideRight; font.pixelSize: 64
            text: sv.connected.length ? sv.connected[0].name : "Nothing connected"
            color: sv.connected.length ? "white" : Theme.w62
        }
        Mono {
            y: 26 + 64 + 14; width: parent.width; wrapMode: Text.WordWrap
            color: sv.bt.note ? Theme.timer : Theme.w62
            text: sv.bt.note ? sv.bt.note
                : sv.bt.powered === false ? "Bluetooth is off · searching turns it on"
                : sv.connected.length ? "Connected · AirPlay plays here" : "Put a speaker in pairing mode, then Search"
        }
    }

    // ---------------------------------------------------------------- brightness (lower left)
    Rise {
        order: 2
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
            Chip { visible: room.kiosk && room.browser && !room.desktop; text: room.browserOpen ? "Opening…" : "Web browser"; onTapped: room.openBrowser() }
            Chip { visible: room.kiosk && room.desktop; text: "Switch to desktop"; onTapped: { confirm.kind = "desktop"; confirm.open = true } }
            Chip { text: "Shut down"; onTapped: { confirm.kind = "off"; confirm.open = true } }
            Mono {
                visible: !room.kiosk; anchors.verticalCenter: parent.verticalCenter; leftPadding: 8
                size: 12; color: Theme.w62; text: "In the GNOME desktop · for just the panel: room-kiosk on, then restart"
            }
        }
    }

    // ---------------------------------------------------------------- Bluetooth devices (lower right)
    Rise {
        order: 3
        x: 744; y: 524; width: 580; height: 360
        Mono { text: "Your devices and nearby"; color: Theme.w62 }
        Row {
            anchors.right: parent.right; y: -13; spacing: 4; height: 44
            Row {           // more than four: the arrows go through them
                visible: list.pages > 1; spacing: 0
                Press { width: 44; height: 44; enabled: list.page > 0; opacity: enabled ? 1 : 0.35; onTapped: list.page--; Mono { anchors.centerIn: parent; text: "‹" } }
                Press { width: 44; height: 44; enabled: list.page < list.pages - 1; opacity: enabled ? 1 : 0.35; onTapped: list.page++; Mono { anchors.centerIn: parent; text: "›" } }
            }
            Press {
                width: sr.width + 16; height: 44
                onTapped: if (!sv.bt.searching) room.btSearch()
                Row {
                    id: sr
                    anchors.centerIn: parent; spacing: 8
                    Rectangle {
                        visible: sv.bt.searching === true
                        width: 8; height: 8; radius: 4; color: "#ffbe7a"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            running: sv.bt.searching === true && sv.shown; loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.25; duration: 700 }
                            NumberAnimation { from: 0.25; to: 1; duration: 700 }
                        }
                    }
                    Mono { text: sv.bt.searching ? "Searching…" : "Search"; color: "white" }
                }
            }
        }
        Mono { y: 46; visible: sv.sorted.length === 0; color: Theme.w62; text: "Nothing paired yet" }
        Item {
            id: list
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
    }

    // ---------------------------------------------------------------- switch to desktop / shut down: are you sure?
    SheetFrame {
        id: confirm
        paneY: 560
        onClose: open = false
        property string kind: "off"             // off · desktop
        Serif { x: 36; y: 40; font.pixelSize: 64; text: confirm.kind === "off" ? "Shut down the Surface?" : "Switch to the desktop?" }
        Mono {
            x: 36; y: 40 + 64 + 18; width: 1280 - 72; wrapMode: Text.WordWrap; color: Theme.w62
            text: confirm.kind === "off" ? "Room, AirPlay and Spotify stop until you press the power button to start it again."
                : "The Surface restarts into GNOME. To come back to just the panel: room-kiosk on, then restart."
        }
        Row {
            x: 36; y: 40 + 64 + 18 + 60; spacing: 10
            Chip { solid: true; text: confirm.kind === "off" ? "Shut down" : "Restart to desktop"; onTapped: { confirm.open = false; confirm.kind === "off" ? room.shutDown() : room.switchToDesktop() } }
            Chip { text: "Cancel"; onTapped: confirm.open = false }
        }
    }
    Component.onCompleted: if (startScreen === "setconfirm") { confirm.kind = "off"; confirm.open = true }     // (checks)
}
