import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string name
    property color color: "#ffffff"
    property real size: 20
    implicitWidth: size
    implicitHeight: size
    readonly property bool tinted: !Qt.colorEqual(color, "#ffffff")

    Image {
        id: img
        anchors.fill: parent
        source: root.name ? Qt.resolvedUrl("icons/" + root.name + ".svg") : ""
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        smooth: true
        visible: !root.tinted
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: root.tinted
        colorization: 1.0
        colorizationColor: root.color
    }
}
