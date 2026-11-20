import QtQuick
import QtQuick.Layouts

RowLayout {
    id: h
    property string text
    property string linkText
    property bool chevron: true
    signal linkClicked()
    spacing: 4
    Text {
        text: h.text
        color: Theme.text
        font.family: Theme.display
        font.pixelSize: 20
        font.weight: Font.Bold
    }
    Icon { visible: h.chevron; name: "chev-right"; size: 18; color: Theme.text2 }
    Item { Layout.fillWidth: true }
    Text {
        visible: h.linkText !== ""
        text: h.linkText
        color: linkMa.containsMouse ? Theme.brandHover : Theme.brand
        font.family: Theme.font
        font.pixelSize: 14
        font.underline: linkMa.containsMouse
        MouseArea { id: linkMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: h.linkClicked() }
    }
}
