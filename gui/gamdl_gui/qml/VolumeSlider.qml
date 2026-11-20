import QtQuick
import QtQuick.Controls

// Volume: drag the slider or scroll over it; the speaker toggles mute. It
// controls the system's master volume, so it always matches the taskbar.
Row {
    id: v
    property real sliderWidth: 96
    property real iconSize: 18
    property bool showMaxIcon: false
    property real trackHeight: 4
    spacing: 8

    Item {
        width: v.iconSize + 8; height: v.iconSize + 8
        anchors.verticalCenter: parent.verticalCenter
        Icon {
            anchors.centerIn: parent
            name: Store.muted || Store.volume <= 0.001 ? "vol-mute" : Store.volume < 0.5 ? "vol-low" : "volume"
            size: v.iconSize
            opacity: muteMa.containsMouse ? 1 : 0.75
        }
        MouseArea { id: muteMa; anchors.fill: parent; hoverEnabled: true; onClicked: Store.toggleMute() }
        ToolTip.visible: muteMa.containsMouse
        ToolTip.delay: 600
        ToolTip.text: Store.muted ? "Unmute" : "Mute"
    }

    Slider {
        id: s
        width: v.sliderWidth
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        from: 0; to: 1
        live: true
        // Follow the system while not dragging (a drag would otherwise break a
        // plain binding); dragging changes the system volume in real time.
        Binding on value { value: Store.muted ? 0 : Store.volume; when: !s.pressed; restoreMode: Binding.RestoreNone }
        onMoved: Store.setVolume(value)
        readonly property bool hot: hovered || pressed
        background: Rectangle {
            x: s.leftPadding
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.availableWidth
            height: s.hot ? v.trackHeight + 2 : v.trackHeight
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.2)
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Rectangle { width: s.visualPosition * parent.width; height: parent.height; radius: parent.radius; color: Qt.rgba(1, 1, 1, s.hot ? 0.95 : 0.8) }
        }
        handle: Rectangle {
            x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: 12; height: 12; radius: 6
            color: "#ffffff"
            scale: s.hot ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        WheelHandler {
            onWheel: (e) => Store.setVolume(Math.max(0, Math.min(1, Store.volume + (e.angleDelta.y > 0 ? 0.02 : -0.02))))
        }
        ToolTip.visible: pressed
        ToolTip.text: Math.round(s.value * 100) + "%"
    }

    Icon {
        visible: v.showMaxIcon
        anchors.verticalCenter: parent.verticalCenter
        name: "volume"; size: v.iconSize + 2; opacity: 0.7
    }
}
