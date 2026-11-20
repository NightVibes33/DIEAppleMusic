import QtQuick

Rectangle {
    id: b
    property string icon
    property bool brand: false
    signal clicked()
    width: 34
    height: 34
    radius: 17
    color: brand || ma.containsMouse ? (ma.containsMouse ? Theme.brandHover : Theme.brand) : Qt.rgba(0.16, 0.16, 0.16, 0.85)
    Icon { anchors.centerIn: parent; name: b.icon; size: 16 }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}
