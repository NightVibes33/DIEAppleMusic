import QtQuick
import QtQuick.Layouts

Sheet {
    id: m
    property string okLabel: "OK"
    property bool cancelable: false
    property bool isError: false
    property string message
    property var onOk: null

    function show(t, text, ok, cancel) { title = t; message = text; okLabel = ok || "OK"; cancelable = !!cancel; isError = true; onOk = null; open() }
    function ask(t, text, ok, cb) { title = t; message = text; okLabel = ok || "Continue"; cancelable = true; isError = false; onOk = cb; open() }

    Rectangle {
        visible: m.isError
        Layout.fillWidth: true
        implicitHeight: msg.implicitHeight + 20
        radius: 8
        color: Qt.rgba(1, 0.35, 0.37, 0.12)
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            Icon { Layout.alignment: Qt.AlignTop; name: "alert"; size: 18; color: Theme.bad }
            Text { id: msg; Layout.fillWidth: true; text: m.message; color: "#ffb3b5"; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 13 }
        }
    }
    Text { visible: !m.isError; Layout.fillWidth: true; text: m.message; color: Theme.text2; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: 14 }

    footer: [
        AppButton { visible: m.isError; text: "Show Activity"; kind: "quiet"; onClicked: { m.close(); Store.dialogs.drawer = "log" } },
        Item { Layout.fillWidth: true },
        AppButton { visible: m.cancelable; text: "Cancel"; kind: "quiet"; onClicked: m.close() },
        AppButton { text: m.okLabel; kind: "primary"; onClicked: { var cb = m.onOk; m.close(); if (cb) cb() } }
    ]
}
