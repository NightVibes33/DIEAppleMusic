import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Artist or library browser: whole categories, or pick items page by page.
PromptSheet {
    id: s
    wide: true
    title: prompt ? prompt.title : ""
    subtitle: "Select whole categories, or open one to pick individual items."
    property var cats: []
    property int version: 0

    Component.onCompleted: {
        cats = prompt.categories.map(function (c) {
            return { kind: c.kind, label: c.label, all: false, open: false, page: 0, more: true, loading: false, items: [], picked: {}, excluded: {} }
        })
        version++
    }
    function pickedCount(c) { var n = 0; for (var k in c.picked) if (c.picked[k]) n++; return n }
    function load(ci) {
        var c = cats[ci]
        if (c.loading || !c.more) return
        c.loading = true; version++
        Store.call("browse_page", [prompt.id, c.kind, c.page], function (r) {
            c.loading = false
            if (r && r.items) { c.items = c.items.concat(r.items); c.more = r.more; c.page++ }
            else { c.more = false; Store.toast("Couldn't load " + c.label, "bad", "alert") }
            version++
        })
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(catCol.implicitHeight, 440)
        contentHeight: catCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: catCol
            width: parent.width
            spacing: 4
            Repeater {
                model: s.version >= 0 ? s.cats : []
                delegate: ColumnLayout {
                    id: cat
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 6
                        color: ch.hovered ? Theme.fillQuiet : "transparent"
                        HoverHandler { id: ch }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 4
                            spacing: 12
                            Check {
                                checked: cat.modelData.all
                                partial: !cat.modelData.all && s.pickedCount(cat.modelData) > 0
                                onToggled: { cat.modelData.all = !cat.modelData.all; cat.modelData.picked = {}; cat.modelData.excluded = {}; s.version++ }
                            }
                            Text { Layout.fillWidth: true; text: cat.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                            Text {
                                text: cat.modelData.all ? "All" : s.pickedCount(cat.modelData) ? s.pickedCount(cat.modelData) + " selected" : ""
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                            }
                            IconButton {
                                icon: cat.modelData.open ? "chev-up" : "chev-down"; iconSize: 16; width: 30; height: 30
                                onClicked: { cat.modelData.open = !cat.modelData.open; if (cat.modelData.open && cat.modelData.page === 0) s.load(cat.index); else s.version++ }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: cat.modelData.open
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 0
                        Repeater {
                            model: cat.modelData.open ? cat.modelData.items : []
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: 6
                                color: ih.hovered ? Theme.fillQuiet : "transparent"
                                HoverHandler { id: ih }
                                readonly property bool on: cat.modelData.all ? !cat.modelData.excluded[modelData.index] : !!cat.modelData.picked[modelData.index]
                                function flip() {
                                    var c = cat.modelData
                                    if (c.all) c.excluded[modelData.index] = !c.excluded[modelData.index]
                                    else c.picked[modelData.index] = !c.picked[modelData.index]
                                    s.version++
                                }
                                MouseArea { anchors.fill: parent; onClicked: parent.flip() }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    spacing: 12
                                    Check { checked: parent.parent.on; onToggled: parent.parent.flip() }
                                    Text { Layout.fillWidth: true; text: modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; elide: Text.ElideRight }
                                }
                            }
                        }
                        RowLayout {
                            visible: cat.modelData.loading
                            Layout.margins: 8
                            spacing: 8
                            Spinner {}
                            Text { text: "Loading…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                        }
                        Text {
                            visible: !cat.modelData.loading && cat.modelData.more && cat.modelData.page > 0
                            Layout.margins: 8
                            text: "Show More"
                            color: Theme.brand; font.family: Theme.font; font.pixelSize: 14
                            MouseArea { anchors.fill: parent; onClicked: s.load(cat.index) }
                        }
                        Text {
                            visible: !cat.modelData.loading && !cat.modelData.more && cat.modelData.items.length === 0
                            Layout.margins: 8
                            text: "Nothing here."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
    footer: [
        Item { Layout.fillWidth: true },
        AppButton { text: "Cancel"; kind: "quiet"; onClicked: s.cancel() },
        AppButton {
            text: "Download"
            kind: "primary"
            onClicked: {
                var sel = []
                for (var i = 0; i < s.cats.length; i++) {
                    var c = s.cats[i], idx = [], ex = []
                    for (var k in c.picked) if (c.picked[k]) idx.push(Number(k))
                    for (var e in c.excluded) if (c.excluded[e]) ex.push(Number(e))
                    if (c.all || idx.length) sel.push({ kind: c.kind, all: c.all, indices: idx, excluded: ex })
                }
                if (!sel.length) { Store.toast("Select at least one category or item.", "bad", "alert"); return }
                s.answer({ selections: sel })
            }
        }
    ]
}
