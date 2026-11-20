import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: e
    property string icon
    property string title
    property string text
    property string action
    signal actionClicked()
    spacing: 10
    Item { Layout.preferredHeight: 50 }
    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 64; height: 64; radius: 16; color: Theme.fill
        Icon { anchors.centerIn: parent; name: e.icon; size: 30; color: Theme.text2 }
    }
    Text { Layout.alignment: Qt.AlignHCenter; text: e.title; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.DemiBold; visible: e.title !== "" }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 420
        text: e.text
        color: Theme.text2
        font.family: Theme.font
        font.pixelSize: 14
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }
    AppButton { visible: e.action !== ""; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 6; text: e.action; kind: "primary"; onClicked: e.actionClicked() }
}
