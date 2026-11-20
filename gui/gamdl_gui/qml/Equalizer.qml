import QtQuick

// Animated "now playing" bars.
Row {
    id: eq
    property bool running: true
    property color color: Theme.brand
    spacing: 2
    height: 14
    Repeater {
        model: 3
        Rectangle {
            required property int index
            width: 3
            radius: 1
            color: eq.color
            anchors.bottom: parent.bottom
            height: 5
            SequentialAnimation on height {
                running: eq.running
                loops: Animation.Infinite
                PauseAnimation { duration: index * 140 }
                NumberAnimation { to: 14; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { to: 4; duration: 300; easing.type: Easing.InOutSine }
            }
        }
    }
}
