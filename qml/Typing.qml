pragma Singleton
import QtQuick

// Who's being typed into, for anything that needs to make room for the on-screen keyboard (Keyboard.qml): a sheet
// with a text box in it rises so the box stays above the keys (SheetFrame).
QtObject {
    property Item target: null          // the text box the keyboard is typing into (null: the keyboard's down)
    readonly property bool up: target !== null
    property real top: 912              // the keyboard's top edge (stage px)
    function inside(item, ancestor) {
        for (var p = item; p; p = p.parent) if (p === ancestor) return true
        return false
    }
}
