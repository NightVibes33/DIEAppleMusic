import QtQuick
import QtQuick.Layouts

Rectangle {
    id: n
    property string icon
    property string text
    property bool active: false
    property bool indent: false
    property int badge: 0
    property string trailingIcon
    signal clicked()
    implicitHeight: 40
    radius: 6
    color: active ? Theme.fill : hover.hovered ? Theme.fillQuiet : "transparent"
    HoverHandler { id: hover }
    Rectangle {
        visible: n.active
        width: 3
        height: 16
        radius: 2
        color: Theme.select
        anchors.verticalCenter: parent.verticalCenter
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: n.indent ? 42 : 12
        anchors.rightMargin: 12
        spacing: 14
        Icon { name: n.icon; size: n.indent ? 18 : 20 }
        Text {
            Layout.fillWidth: true
            text: n.text
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 15
            elide: Text.ElideRight
        }
        Rectangle {
            visible: n.badge > 0
            implicitWidth: Math.max(22, bt.implicitWidth + 14)
            implicitHeight: 20
            radius: 10
            color: Theme.brand
            Text { id: bt; anchors.centerIn: parent; text: n.badge; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: Theme.font }
        }
        Icon { visible: n.trailingIcon !== ""; name: n.trailingIcon; size: 16; color: Theme.text2 }
    }
    MouseArea { anchors.fill: parent; onClicked: n.clicked() }
}
