import QtQuick

// Settings: the screen (automatic brightness from the room's light, or set by hand) and switching to the desktop on
// the left; Bluetooth on the right — your speakers (connect, disconnect, forget) and, while this is open, a search
// for new ones to pair.
Item {
    id: st
    width: Theme.stageW; height: Theme.stageH
    signal back()
    readonly property var disp: room.display
    readonly property var bt: room.bluetooth
    readonly property var devices: bt.devices || []
    readonly property var mine: devices.filter(function (d) { return d.paired })
    readonly property var nearby: devices.filter(function (d) { return !d.paired })

    onVisibleChanged: visible ? room.btSearch() : room.btStop()

    Header { title: "Settings"; onBack: st.back() }

    component Toggle: Press {
        property bool on: false
        width: 88; height: 52
        Rectangle { anchors.fill: parent; radius: 26; color: parent.on ? Qt.rgba(1, 190 / 255, 122 / 255, 0.6) : Qt.rgba(1, 1, 1, 0.1) }
        Rectangle {
            y: 5; x: parent.on ? parent.width - width - 5 : 5
            width: 42; height: 42; radius: 21; color: Theme.ink
            Behavior on x { NumberAnimation { duration: 160 } }
        }
    }

    // ---------------------------------------------------------------- left: the screen, this panel
    Column {
        x: 96; y: 172; width: 528; spacing: 0
        SectionCap { text: "Screen"; bottomPadding: 34 }
        Item {
            width: parent.width; height: 70
            visible: st.disp.sensor === true
            T { y: 0; text: "Automatic brightness"; font.pixelSize: 30 }
            T {
                y: 44; font.pixelSize: 19; color: Theme.sub
                text: st.disp.auto ? "Follows the room's light  ·  now " + Math.round(st.disp.level * 100) + "%" : "Off — you set it below"
            }
            Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: st.disp.auto === true; onTapped: room.setAutoBrightness(!on) }
        }
        T {
            visible: st.disp.sensor !== true; width: parent.width; wrapMode: Text.WordWrap
            text: "Brightness"; font.pixelSize: 30
        }
        Item { width: 1; height: 40 }
        LevelSlider {
            width: parent.width; height: 80
            value: Math.round((st.disp.level || 0.5) * 100)
            tint: Theme.warm
            onMoved: (v) => room.setBrightness(v / 100)
        }
        T {
            topPadding: 14; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 18; color: Theme.sub
            text: st.disp.canSet === false ? "This screen's brightness can't be set from here"
                : st.disp.sensor ? "Slide to set it yourself — automatic turns off until you turn it back on"
                : "No light sensor found, so it stays where you set it"
        }
        Item { width: 1; height: 70 }
        SectionCap { text: "This panel"; bottomPadding: 26 }
        Press {
            visible: room.kiosk
            width: parent.width; height: 120; pressScale: 0.985
            onTapped: confirm.open = true
            Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, 0.05) }
            T { x: 28; y: 24; text: "Switch to desktop"; font.pixelSize: 26 }
            T { x: 28; y: 66; width: parent.width - 90; text: "Restarts into GNOME"; font.pixelSize: 18; color: Theme.sub }
            Icon { anchors.right: parent.right; anchors.rightMargin: 28; anchors.verticalCenter: parent.verticalCenter; name: "chev"; size: 22; color: Theme.sub }
        }
        T {
            visible: !room.kiosk; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 19; color: Theme.sub
            text: "Running inside the GNOME desktop. To start as just the panel, run  room-kiosk on  and restart."
        }
        T {
            visible: room.desktopNote !== ""; topPadding: 14; width: parent.width; wrapMode: Text.WordWrap
            text: room.desktopNote; font.pixelSize: 18; color: Theme.warm
        }
    }

    // ---------------------------------------------------------------- right: Bluetooth
    Rectangle { x: 690; y: 150; width: 1; height: 720; color: Qt.rgba(1, 1, 1, 0.06) }
    SectionCap { x: 744; y: 190; text: "Bluetooth" }
    Press {
        x: 1296 - width; y: 164; height: 56; width: searchRow.width + 48
        onTapped: if (!st.bt.searching) room.btSearch()
        Rectangle { anchors.fill: parent; radius: 28; color: Qt.rgba(1, 1, 1, 0.06) }
        Row {
            id: searchRow
            anchors.centerIn: parent; spacing: 10
            Rectangle {
                visible: st.bt.searching === true
                width: 10; height: 10; radius: 5; color: Theme.warm; anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: st.bt.searching === true && st.visible; loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 700 }
                    NumberAnimation { from: 0.25; to: 1; duration: 700 }
                }
            }
            T { text: st.bt.searching ? "Searching…" : "Search"; font.pixelSize: 19; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    component DeviceRow: Item {
        id: dr
        property var d
        width: 552; height: 106
        readonly property string busy: d.busy || ""
        T { y: 20; width: parent.width - 220; text: dr.d.name; font.pixelSize: 28; elide: Text.ElideRight }
        T {
            y: 60; width: parent.width - 220; font.pixelSize: 18; elide: Text.ElideRight
            color: dr.busy === "" && dr.d.connected ? Theme.warm : Theme.sub
            text: dr.busy !== "" ? dr.busy
                : dr.d.connected ? "Connected" + (dr.d.kind === "Speaker" || dr.d.kind === "" ? "  ·  AirPlay plays here" : "")
                : dr.d.paired ? ((dr.d.kind ? dr.d.kind + "  ·  " : "") + "Paired")
                : (dr.d.kind || "Nearby")
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
            opacity: dr.busy === "" ? 1 : 0.35
            enabled: dr.busy === ""
            RoundBtn {
                visible: dr.d.paired && !dr.d.connected
                size: 52; icon: "trash"; iconSize: 20
                onTapped: room.btForget(dr.d.mac)
            }
            Pill {
                height: 52; width: Math.max(120, implicitWidth); fontSize: 19
                text: dr.d.connected ? "Disconnect" : dr.d.paired ? "Connect" : "Pair"
                fill: dr.d.paired ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(239 / 255, 231 / 255, 222 / 255, 0.95)
                onTapped: dr.d.connected ? room.btDisconnect(dr.d.mac) : dr.d.paired ? room.btConnect(dr.d.mac) : room.btPair(dr.d.mac)
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rule }
    }

    Flickable {
        x: 744; y: 236; width: 552; height: 620
        contentHeight: btCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: btCol
            width: 552
            Repeater { model: st.mine; DeviceRow { d: modelData } }
            T { visible: st.mine.length === 0; text: "Nothing paired yet"; font.pixelSize: 24; color: Theme.sub; topPadding: 20; bottomPadding: 20 }
            Item { width: 1; height: 34; visible: st.nearby.length > 0 }
            SectionCap { visible: st.nearby.length > 0; text: "Nearby"; font.pixelSize: 13; bottomPadding: 4 }
            Repeater { model: st.nearby; DeviceRow { d: modelData } }
            T {
                topPadding: 22; width: 552; wrapMode: Text.WordWrap; font.pixelSize: 18
                color: st.bt.note ? Theme.warm : Theme.sub
                text: st.bt.note ? st.bt.note : st.bt.powered === false ? "Bluetooth is off — searching turns it on"
                      : "Put a speaker in pairing mode and it shows up here"
            }
        }
    }

    // ---------------------------------------------------------------- switch to desktop: are you sure?
    Item {
        id: confirm
        anchors.fill: parent
        property bool open: false
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: confirm.open = false }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.7) }
        Rectangle {
            x: 384; y: 256; width: 600; height: 330; radius: 26; color: "#141210"
            MouseArea { anchors.fill: parent }
            T { x: 44; y: 44; text: "Switch to the desktop?"; font.pixelSize: 32 }
            T {
                x: 44; y: 100; width: 512; wrapMode: Text.WordWrap; font.pixelSize: 20; color: Theme.sub; lineHeight: 1.3
                text: "The Surface restarts into GNOME. To come back to just the panel, run  room-kiosk on  and restart."
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 44; anchors.bottom: parent.bottom; anchors.bottomMargin: 40; spacing: 16
                Pill { width: 140; height: 60; text: "Cancel"; fontSize: 21; onTapped: confirm.open = false }
                Pill {
                    width: 260; height: 60; text: "Restart to desktop"; fontSize: 21
                    fill: Qt.rgba(239 / 255, 231 / 255, 222 / 255, 0.95)
                    onTapped: { confirm.open = false; room.switchToDesktop() }
                }
            }
        }
    }
}
