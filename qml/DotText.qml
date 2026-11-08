import QtQuick
// Dot-matrix numerals (the panel's 5×7 glyphs). A fixed pool of dots: when the text changes, each dot glides
// from where it was to its place in the new time — the clock rearranges itself each minute.
Item {
    id: root
    property string text: "00:00"
    property real pitch: 20
    property color color: Theme.tx
    property int glide: 900
    readonly property var glyphs: ({
        "0": ["01110","10001","10001","10001","10001","10001","01110"], "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"], "3": ["01110","10001","00001","00110","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"], "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"], "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"], "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ":": ["0","0","1","0","1","0","0"], "-": ["000","000","000","111","000","000","000"]
    })
    // dot centres in grid units, reading order — so dots travel short, tidy distances
    readonly property var layout: {
        var pts = [], x = 0
        for (var c = 0; c < text.length; c++) {
            var g = glyphs[text[c]]; if (!g) continue
            for (var col = 0; col < g[0].length; col++)
                for (var row = 0; row < 7; row++)
                    if (g[row][col] === "1") pts.push([x + col, row])
            x += g[0].length + 1
        }
        return { pts: pts, cols: Math.max(1, x - 1) }
    }
    width: layout.cols * pitch - pitch * 0.24
    height: 7 * pitch - pitch * 0.24
    readonly property real r: pitch * 0.38

    Repeater {
        model: 120
        Rectangle {
            readonly property var pt: index < root.layout.pts.length ? root.layout.pts[index] : null
            // spare dots wait, invisible, at the last real dot so they appear from there
            readonly property var at: pt || (root.layout.pts.length ? root.layout.pts[root.layout.pts.length - 1] : [0, 0])
            width: root.r * 2; height: width; radius: width / 2
            color: root.color
            x: at[0] * root.pitch; y: at[1] * root.pitch
            opacity: pt ? 1 : 0
            antialiasing: true
            Behavior on x { NumberAnimation { duration: root.glide; easing.type: Easing.InOutCubic } }
            Behavior on y { NumberAnimation { duration: root.glide; easing.type: Easing.InOutCubic } }
            Behavior on opacity { NumberAnimation { duration: root.glide * 0.6 } }
        }
    }
}
