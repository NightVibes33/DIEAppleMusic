import QtQuick
import QtQuick.Layouts

// Fluent-style switch, as in Apple Music for Windows settings.
RowLayout {
    id: t
    property bool checked: false
    property string text
    signal toggled(bool checked)
    spacing: 10
    function flip() { t.checked = !t.checked; t.toggled(t.checked) }
    Rectangle {
        implicitWidth: 40
        implicitHeight: 20
        radius: 10
        color: t.checked ? Theme.select : "transparent"
        border.color: t.checked ? Theme.select : Qt.rgba(1, 1, 1, 0.55)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 12
            height: 12
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: t.checked ? 24 : 4
            color: t.checked ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: t.flip() }
    }
    Text {
        visible: t.text !== ""
        text: t.text
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
        MouseArea { anchors.fill: parent; onClicked: t.flip() }
    }
}
