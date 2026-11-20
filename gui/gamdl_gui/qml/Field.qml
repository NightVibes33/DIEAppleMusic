import QtQuick
import QtQuick.Controls

TextField {
    id: f
    property bool numeric: false
    implicitHeight: 32
    leftPadding: 10
    rightPadding: 10
    color: Theme.text
    placeholderTextColor: Theme.text3
    selectionColor: Theme.select
    selectedTextColor: "#ffffff"
    font.family: Theme.font
    font.pixelSize: 14
    horizontalAlignment: numeric ? TextInput.AlignRight : TextInput.AlignLeft
    background: Rectangle {
        radius: 6
        color: f.activeFocus ? "#262626" : Theme.fill
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            height: f.activeFocus ? 2 : 1
            color: f.activeFocus ? Theme.select : Qt.rgba(1, 1, 1, 0.14)
        }
    }
}
