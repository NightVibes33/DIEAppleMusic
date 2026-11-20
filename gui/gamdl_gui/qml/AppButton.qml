import QtQuick
import QtQuick.Layouts

Rectangle {
    id: b
    property string text
    property string icon
    property string kind: "default"   // default | primary | blue | danger | quiet
    property bool large: false
    property bool busy: false
    signal clicked()
    implicitHeight: large ? 38 : 32
    implicitWidth: row.implicitWidth + (large ? 44 : 32)
    radius: large ? 8 : 6
    opacity: enabled ? 1 : 0.45
    readonly property color base: kind === "primary" ? Theme.brand : kind === "blue" ? Theme.select : kind === "quiet" ? "#3a3a3a" : Theme.fill
    color: !enabled ? base : ma.pressed ? Qt.darker(base, 1.12) : ma.containsMouse ? (kind === "primary" ? Theme.brandHover : Qt.lighter(base, 1.14)) : base
    Behavior on color { ColorAnimation { duration: 90 } }
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Spinner { visible: b.busy; size: 14 }
        Icon { visible: b.icon !== "" && !b.busy; name: b.icon; size: 16; color: b.kind === "danger" ? Theme.bad : "#ffffff" }
        Text {
            text: b.text
            color: b.kind === "danger" ? Theme.bad : Theme.text
            font.family: Theme.font
            font.pixelSize: b.large ? 15 : 14
            font.weight: Font.Medium
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !b.busy; onClicked: b.clicked() }
}
