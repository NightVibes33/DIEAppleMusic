import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Column {
    id: t
    spacing: 8
    z: 50
    function show(text, kind, icon) { toastModel.append({ text: text, kind: kind, icon: icon }) }
    ListModel { id: toastModel }
    Repeater {
        model: toastModel
        delegate: Item {
            id: toast
            required property string text
            required property string kind
            required property string icon
            required property int index
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(560, row.implicitWidth + 32)
            height: Math.max(40, row.implicitHeight + 20)
            RectangularShadow { anchors.fill: bg; radius: 10; blur: 30; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.45) }
            Rectangle { id: bg; anchors.fill: parent; radius: 10; color: Qt.rgba(0.2, 0.2, 0.2, 0.96); border.color: Qt.rgba(1, 1, 1, 0.08) }
            RowLayout {
                id: row
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 528)
                spacing: 10
                Icon { name: toast.icon || "check"; size: 18; color: toast.kind === "ok" ? Theme.ok : toast.kind === "bad" ? Theme.bad : "#ffffff" }
                Text { Layout.maximumWidth: 490; text: toast.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; wrapMode: Text.Wrap }
            }
            NumberAnimation on opacity { from: 0; to: 1; duration: 160 }
            Timer { interval: 4200; running: true; onTriggered: toastModel.remove(toast.index) }
        }
    }
}
