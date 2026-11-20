import QtQuick

Rectangle {
    width: 13
    height: 13
    radius: 2
    color: Qt.rgba(1, 1, 1, 0.45)
    Text {
        anchors.centerIn: parent
        text: "E"
        color: "#1c1c1c"
        font.pixelSize: 9
        font.weight: Font.Black
        font.family: Theme.font
    }
}
