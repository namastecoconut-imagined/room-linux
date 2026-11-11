import QtQuick
import QtQuick.Shapes
// Line icons on a 24-unit grid.
Item {
    id: i
    property string name
    property real size: 24
    property color color: Theme.tx
    property bool filled: name === "play" || name === "pause" || name === "next" || name === "prev" || name === "heartOn"
    width: size; height: size
    readonly property var paths: ({
        "bulb": "M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0 0 12 3z",
        "mic": "M9 6a3 3 0 0 1 6 0v6a3 3 0 0 1-6 0zM5 11a7 7 0 0 0 14 0M12 18v3",
        "play": "M7 4.5v15l12-7.5z",
        "pause": "M6 5h4v14H6zM14 5h4v14h-4z",
        "next": "M6 6v12l9-6zM16 6h2v12h-2z",
        "prev": "M18 6v12l-9-6zM6 6h2v12H6z",
        "speaker": "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM12 11a3 3 0 1 0 0 6 3 3 0 1 0 0-6zM12 7v.1",
        "timer": "M12 5a8 8 0 1 0 0 16 8 8 0 1 0 0-16zM12 9v4l2.5 2M9 2h6",
        "back": "M15 5l-7 7 7 7",
        "power": "M12 3v8M6.3 6.3a8 8 0 1 0 11.4 0",
        "moon": "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z",
        "heart": "M12 20s-7-4.4-7-9.6A3.9 3.9 0 0 1 12 8a3.9 3.9 0 0 1 7 2.4C19 15.6 12 20 12 20z",
        "heartOn": "M12 20s-7-4.4-7-9.6A3.9 3.9 0 0 1 12 8a3.9 3.9 0 0 1 7 2.4C19 15.6 12 20 12 20z",
        "lib": "M7.5 5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5zM16.5 5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5zM7.5 14a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5zM16.5 14a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5z",
        "cloud": "M7 18h10a4 4 0 0 0 .6-7.96A6 6 0 0 0 6.2 9.6 4.2 4.2 0 0 0 7 18z",
        "check": "M5 12.5l4.5 4.5L19 7.5",
        "scenes": "M12 3a9 9 0 1 0 0 18 9 9 0 1 0 0-18zM12 3v18",
        "plus": "M12 5v14M5 12h14",
        "close": "M6 6l12 12M18 6L6 18",
        "alarm": "M12 6a7 7 0 1 0 0 14 7 7 0 1 0 0-14zM12 9.5V13l2 1.5M4 5.5l3-2.5M20 5.5l-3-2.5",
        "umbrella": "M12 3a9 9 0 0 1 9 9H3a9 9 0 0 1 9-9zM12 12v6a2 2 0 0 0 4 0",
        "trash": "M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13",
        "settings": "M4 7h9M17 7h3M15 5v4M4 17h3M11 17h9M9 15v4",
        "globe": "M12 3a9 9 0 1 0 0 18 9 9 0 1 0 0-18zM3.5 9h17M3.5 15h17M12 3c-2.4 2.6-3.6 5.6-3.6 9s1.2 6.4 3.6 9M12 3c2.4 2.6 3.6 5.6 3.6 9s-1.2 6.4-3.6 9",
        "chev": "M9 5l7 7-7 7",
        "dim": "M12 8a4 4 0 1 0 0 8 4 4 0 1 0 0-8zM12 3v1.5M12 19.5V21M3 12h1.5M19.5 12H21M5.6 5.6l1 1M17.4 17.4l1 1M5.6 18.4l1-1M17.4 6.6l1-1"
    })
    Shape {
        anchors.fill: parent
        scale: i.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: i.filled ? "transparent" : i.color
            fillColor: i.filled ? i.color : "transparent"
            strokeWidth: 1.6
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: i.paths[i.name] || "" }
        }
    }
}
