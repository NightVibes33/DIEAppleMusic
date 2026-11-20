import QtQuick

// Invisible. Drag to move the window (Windows takes over the move, including
// snapping to screen edges); double-click to maximize or restore. Place it as
// the first child so buttons drawn on top still get their clicks.
MouseArea {
    id: d
    property bool maximizeOnDoubleClick: true
    property point _start
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onPressed: (m) => _start = Qt.point(m.x, m.y)
    onPositionChanged: (m) => {
        if (pressed && (Math.abs(m.x - _start.x) > 3 || Math.abs(m.y - _start.y) > 3)) Window.window.startSystemMove()
    }
    onDoubleClicked: {
        if (!maximizeOnDoubleClick) return
        var w = Window.window
        if (w.visibility === Window.Maximized) w.showNormal(); else w.showMaximized()
    }
    onWheel: (w) => w.accepted = false
}
