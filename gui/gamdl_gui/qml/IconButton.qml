import QtQuick
import QtQuick.Controls

Rectangle {
    id: b
    property string icon
    property real iconSize: 20
    property color iconColor: Theme.text
    property bool active: false
    property string tip
    signal clicked()
    implicitWidth: 36
    implicitHeight: 36
    radius: 6
    color: !enabled ? "transparent" : ma.pressed ? Qt.rgba(1, 1, 1, 0.05) : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
    opacity: enabled ? 1 : 0.35
    Icon { anchors.centerIn: parent; name: b.icon; size: b.iconSize; color: b.active ? Theme.select : b.iconColor }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    ToolTip.visible: b.tip !== "" && ma.containsMouse
    ToolTip.text: b.tip
    ToolTip.delay: 700
}
