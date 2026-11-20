import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PromptSheet {
    id: s
    title: prompt ? prompt.title : ""
    subtitle: prompt ? prompt.subtitle : ""
    property int chosen: prompt && prompt.options.length ? prompt.options[0].index : 0

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 400)
        clip: true
        model: s.prompt ? s.prompt.options : []
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width
            height: 42
            radius: 6
            color: oh.hovered ? Theme.fillQuiet : "transparent"
            HoverHandler { id: oh }
            MouseArea { anchors.fill: parent; onClicked: s.chosen = modelData.index; onDoubleClicked: s.answer(modelData.index) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12
                Check { radio: true; checked: s.chosen === modelData.index; onToggled: s.chosen = modelData.index }
                Text { text: modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                Text { Layout.fillWidth: true; text: modelData.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideRight }
            }
        }
    }
    footer: [
        Item { Layout.fillWidth: true },
        AppButton { text: "Skip"; kind: "quiet"; onClicked: s.cancel() },
        AppButton { text: "Use This"; kind: "primary"; onClicked: s.answer(s.chosen) }
    ]
}
