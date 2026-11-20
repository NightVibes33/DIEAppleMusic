import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PromptSheet {
    id: s
    wide: true
    title: prompt ? prompt.title : ""
    subtitle: prompt ? prompt.options.length + " items" : ""
    property var picked: ({})
    property int version: 0
    property string filter: ""
    readonly property int count: { version; var n = 0; for (var k in picked) if (picked[k]) n++; return n }

    Component.onCompleted: {
        var p = {}
        for (var i = 0; i < prompt.options.length; i++) p[prompt.options[i].index] = true
        picked = p; version++
    }
    function setAll(on) {
        for (var i = 0; i < prompt.options.length; i++) {
            var o = prompt.options[i]
            if (!filter || o.title.toLowerCase().indexOf(filter) >= 0) picked[o.index] = on
        }
        version++
    }

    Field { Layout.fillWidth: true; placeholderText: "Filter"; onTextChanged: s.filter = text.toLowerCase() }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 420)
        clip: true
        model: s.prompt ? s.prompt.options : []
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool shown: !s.filter || modelData.title.toLowerCase().indexOf(s.filter) >= 0
            width: ListView.view.width
            height: shown ? 38 : 0
            visible: shown
            radius: 6
            color: rh.hovered ? Theme.fillQuiet : "transparent"
            HoverHandler { id: rh }
            MouseArea { anchors.fill: parent; onClicked: { s.picked[modelData.index] = !s.picked[modelData.index]; s.version++ } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12
                Check { checked: s.version >= 0 && !!s.picked[modelData.index]; onToggled: { s.picked[modelData.index] = !s.picked[modelData.index]; s.version++ } }
                Text { text: index + 1; color: Theme.text3; font.family: Theme.font; font.pixelSize: 13; Layout.preferredWidth: 22; horizontalAlignment: Text.AlignRight }
                Text { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; elide: Text.ElideRight }
            }
        }
    }
    footer: [
        AppButton { text: "Select All"; kind: "quiet"; onClicked: s.setAll(true) },
        AppButton { text: "Select None"; kind: "quiet"; onClicked: s.setAll(false) },
        Item { Layout.fillWidth: true },
        AppButton { text: "Cancel"; kind: "quiet"; onClicked: s.cancel() },
        AppButton {
            text: "Download (" + s.count + ")"
            kind: "primary"
            enabled: s.count > 0
            onClicked: {
                var out = []
                for (var i = 0; i < s.prompt.options.length; i++) if (s.picked[s.prompt.options[i].index]) out.push(s.prompt.options[i].index)
                s.answer(out)
            }
        }
    ]
}
