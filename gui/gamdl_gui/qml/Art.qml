import QtQuick
import QtQuick.Effects

// Rounded artwork with a placeholder glyph while loading or when missing.
Item {
    id: root
    property string source
    property real radius: 6
    property string glyph: "note"
    readonly property bool ready: img.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "#2a2a2a"
        Icon { anchors.centerIn: parent; name: root.glyph; size: Math.max(12, parent.width * 0.34); color: "#5a5a5a"; visible: !root.ready }
    }
    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        sourceSize.width: 400
        sourceSize.height: 400
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: root.ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: root.radius; color: "black" }
    }
    Rectangle { anchors.fill: parent; radius: root.radius; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.06); border.width: 1 }
}
