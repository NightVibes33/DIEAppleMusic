import QtQuick

Rectangle {
    id: m
    property real value: -1   // 0..100, or -1 for busy
    property color tint: "#ffffff"
    implicitHeight: 4
    radius: 2
    clip: true
    color: Qt.rgba(1, 1, 1, 0.1)
    Rectangle {
        visible: m.value >= 0
        height: parent.height
        radius: 2
        color: m.tint
        width: parent.width * Math.max(0, Math.min(100, m.value)) / 100
        Behavior on width { NumberAnimation { duration: 250 } }
    }
    Rectangle {
        id: busyBar
        visible: m.value < 0
        height: parent.height
        radius: 2
        width: parent.width * 0.35
        color: Qt.rgba(1, 1, 1, 0.55)
        SequentialAnimation on x {
            running: busyBar.visible
            loops: Animation.Infinite
            NumberAnimation { from: -m.width * 0.35; to: m.width; duration: 1100; easing.type: Easing.InOutQuad }
        }
    }
}
