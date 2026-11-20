import QtQuick
import QtQuick.Layouts

Rectangle {
    id: c
    property string text
    property bool on: false
    property string badge
    property bool small: false
    signal clicked()
    implicitHeight: small ? 26 : 28
    implicitWidth: row.implicitWidth + 24
    radius: height / 2
    color: on ? "#ffffff" : ma.containsMouse ? Theme.fillHover : Theme.fill
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            visible: c.badge !== ""
            implicitWidth: Math.max(16, bt.implicitWidth + 8)
            implicitHeight: 16
            radius: 8
            color: "#111111"
            Text { id: bt; anchors.centerIn: parent; text: c.badge; color: "#ffffff"; font.pixelSize: 10; font.bold: true; font.family: Theme.font }
        }
        Text { text: c.text; color: c.on ? "#111111" : (ma.containsMouse ? Theme.text : Theme.text2); font.family: Theme.font; font.pixelSize: c.small ? 12.5 : 13 }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: c.clicked() }
}
