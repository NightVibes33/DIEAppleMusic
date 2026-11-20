import QtQuick

// Fluent-style checkbox (also renders the "some selected" state).
Rectangle {
    id: cb
    property bool checked: false
    property bool partial: false
    property bool radio: false
    signal toggled()
    width: 18
    height: 18
    radius: radio ? 9 : 4
    color: checked || partial ? Theme.select : "transparent"
    border.color: checked || partial ? Theme.select : Qt.rgba(1, 1, 1, 0.55)
    border.width: 1
    Icon { anchors.centerIn: parent; visible: cb.checked && !cb.radio; name: "check"; size: 13 }
    Rectangle { anchors.centerIn: parent; visible: cb.partial && !cb.checked; width: 8; height: 2; color: "#ffffff" }
    Rectangle { anchors.centerIn: parent; visible: cb.radio && cb.checked; width: 8; height: 8; radius: 4; color: "#ffffff" }
    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: cb.toggled() }
}
