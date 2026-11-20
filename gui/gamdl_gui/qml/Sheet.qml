import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// Centered modal sheet with title, body and a button row.
Popup {
    id: s
    property string title
    property string subtitle
    property bool wide: false
    default property alias content: body.data
    property alias footer: foot.data
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(wide ? 760 : 560, parent ? parent.width - 48 : 560)
    height: Math.min(implicitHeight, parent ? parent.height - 48 : 600)
    modal: true
    dim: true
    padding: 0
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.45) }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }

    background: Item {
        RectangularShadow { anchors.fill: bg; radius: 12; blur: 48; offset.y: 16; color: Qt.rgba(0, 0, 0, 0.6) }
        Rectangle { id: bg; anchors.fill: parent; radius: 12; color: Theme.sheet; border.color: Qt.rgba(1, 1, 1, 0.09) }
    }

    contentItem: ColumnLayout {
        spacing: 0
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 22
            Layout.bottomMargin: 8
            spacing: 6
            visible: s.title !== ""
            Text { Layout.fillWidth: true; text: s.title; color: Theme.text; font.family: Theme.display; font.pixelSize: 20; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
            Text { Layout.fillWidth: true; visible: s.subtitle !== ""; text: s.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; wrapMode: Text.Wrap }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 8
            spacing: 12
        }
        RowLayout {
            id: foot
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 16
            Layout.bottomMargin: 20
            spacing: 10
        }
    }
}
