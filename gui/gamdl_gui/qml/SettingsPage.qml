import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

PageScroll {
    id: page
    spacing: 14
    signal signInRequested()

    property var schema: []
    property string path: ""
    property var form: ({})
    property string original: ""
    property int version: 0
    property bool dirty: false

    readonly property var current: {
        for (var i = 0; i < schema.length; i++) if (schema[i].id === Store.settingsTab) return schema[i]
        return schema.length ? schema[0] : null
    }

    function load() {
        var s = Store.callSync("get_settings")
        schema = s.schema; path = s.path
        form = s.values; original = JSON.stringify(s.values)
        dirty = false; version++
    }
    function value(f) { return version >= 0 && form[f.section] ? form[f.section][f.key] : null }
    function setValue(f, v) {
        form[f.section][f.key] = v
        dirty = JSON.stringify(form) !== original
        version++
    }
    function save() {
        Store.call("save_settings", [form], function (r) {
            if (!r.ok) { Store.toast(Store.friendlyError(r.error), "bad", "alert"); return }
            Store.refreshState()
            Store.sessionOk = false
            Store.sessionDesc = ""
            load()
            Store.autoConnect()
            Store.toast("Settings saved", "ok", "check")
        })
    }
    readonly property var qualities: [
        { id: "standard", title: "High Quality", text: "AAC at 256 kbps, the same quality Apple Music streams. Works with every account. Recommended.", priority: ["aac"] },
        { id: "atmos", title: "Dolby Atmos when available", text: "Spatial audio for songs that have it. Everything else downloads in High Quality.", priority: ["atmos", "aac"] },
        { id: "lossless", title: "Lossless when available", text: "Apple Lossless (ALAC). Everything else downloads in High Quality.", priority: ["alac", "aac"], needsWrapper: true,
          blocked: "Apple only allows lossless downloads through a wrapper service. Set one up under advanced settings to use this." }
    ]
    readonly property var simpleFields: [
        { section: "output", key: "directory", label: "Save music to", help: "", type: "folder-opt" },
        { section: "output", key: "no_lyrics_file", label: "Save lyrics with each song", help: "Keeps a lyrics file next to the song, so lyrics also work offline.", type: "check", invert: true },
        { section: "output", key: "save_cover", label: "Save album artwork as a picture", help: "Artwork is always included inside the song file.", type: "check" },
        { section: "download", key: "overwrite", label: "Replace songs I already have", help: "When this is off, songs already in your music folder are skipped.", type: "check" }
    ]
    function qualityId() {
        if (version < 0 || !form.download) return "standard"
        var p = form.download.song_codec_priority || []
        if (form.download.song_codec) return "custom"
        if (p[0] === "atmos") return "atmos"
        if (p[0] && p[0].indexOf("alac") === 0) return "lossless"
        return "standard"
    }
    function setQuality(q) {
        form.download.song_codec = null
        setValue({ section: "download", key: "song_codec_priority" }, q.priority.slice())
    }

    // Choices are plain values or [value, label] pairs. Pairs can arrive as Qt
    // sequences, where Array.isArray is false, so check for a length instead.
    function choices(f) {
        var out = []
        for (var i = 0; i < f.choices.length; i++) {
            var c = f.choices[i]
            out.push(c !== null && typeof c === "object" && c.length === 2 ? [c[0], c[1]] : [c, c])
        }
        return out
    }
    Component.onCompleted: load()

    Flow {
        visible: Store.prefs.advanced
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        Repeater {
            model: page.schema
            Chip {
                required property var modelData
                text: modelData.title
                on: page.current && page.current.id === modelData.id
                onClicked: Store.settingsTab = modelData.id
            }
        }
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Math.min(860, page.width - 48)
        Layout.maximumWidth: 860
        spacing: 22

        // Account status
        Rectangle {
            visible: !Store.prefs.advanced || (page.current && page.current.id === "account")
            Layout.fillWidth: true
            implicitHeight: Math.max(72, accountInfo.implicitHeight + 32)
            radius: 8
            color: Theme.panel
            border.color: Theme.hairline
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                Rectangle {
                    width: 40; height: 40; radius: 20
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#5e5ce6" }
                        GradientStop { position: 1; color: "#bf5af2" }
                    }
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: Store.accountProfile.image || ""
                        visible: !!Store.accountProfile.image
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: Rectangle { width: 40; height: 40; radius: 20; color: "white" }
                        }
                    }
                    Icon { anchors.centerIn: parent; name: "person"; size: 22; visible: !Store.accountProfile.image }
                    Rectangle { width: 12; height: 12; radius: 6; anchors.right: parent.right; anchors.bottom: parent.bottom; color: Store.sessionOk ? Theme.ok : Theme.text3; border.color: Theme.panel; border.width: 2 }
                }
                ColumnLayout {
                    id: accountInfo
                    Layout.fillWidth: true
                    spacing: 4
                    Text { text: Store.accountTitle; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                    Text {
                        Layout.fillWidth: true
                        text: Store.accountDetail
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight
                    }
                }
                AppButton { visible: !Store.appState.auth; text: "Sign In with Apple ID…"; kind: "primary"; onClicked: page.signInRequested() }
                AppButton { visible: !!Store.appState.auth; text: "Sign Out"; kind: "danger"; onClicked: Store.signOut() }
            }
        }

        // ---- Simple settings: what most people need ----
        ColumnLayout {
            visible: !Store.prefs.advanced
            Layout.fillWidth: true
            spacing: 22

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.leftMargin: 4; text: "Sound quality"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: qcol.implicitHeight
                    radius: 8
                    color: Theme.panel
                    border.color: Theme.hairline
                    ColumnLayout {
                        id: qcol
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: page.qualities
                            delegate: ColumnLayout {
                                id: qopt
                                required property var modelData
                                required property int index
                                readonly property bool usable: !modelData.needsWrapper || Store.appState.auth === "wrapper"
                                readonly property bool chosen: page.qualityId() === modelData.id
                                Layout.fillWidth: true
                                spacing: 0
                                Rectangle { visible: qopt.index > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: qrow.implicitHeight + 24
                                    opacity: qopt.usable ? 1 : 0.5
                                    MouseArea { anchors.fill: parent; enabled: qopt.usable; onClicked: page.setQuality(qopt.modelData) }
                                    RowLayout {
                                        id: qrow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 16
                                        spacing: 14
                                        Check { radio: true; checked: qopt.chosen; onToggled: if (qopt.usable) page.setQuality(qopt.modelData) }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text { text: qopt.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                                            Text { Layout.fillWidth: true; text: qopt.usable ? qopt.modelData.text : qopt.modelData.blocked; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.leftMargin: 4; text: "Downloads"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: simpleRows.implicitHeight
                    radius: 8
                    color: Theme.panel
                    border.color: Theme.hairline
                    ColumnLayout {
                        id: simpleRows
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: page.simpleFields
                            delegate: ColumnLayout {
                                id: srow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 0
                                Rectangle { visible: srow.index > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: 16
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 12
                                    spacing: 24
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: srow.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                                        Text { visible: srow.modelData.help !== ""; Layout.fillWidth: true; text: srow.modelData.help; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap }
                                    }
                                    Toggle {
                                        visible: srow.modelData.type === "check"
                                        checked: { var v = !!page.value(srow.modelData); return srow.modelData.invert ? !v : v }
                                        onToggled: (c) => page.setValue(srow.modelData, srow.modelData.invert ? !c : c)
                                    }
                                    RowLayout {
                                        visible: srow.modelData.type === "folder-opt"
                                        Layout.preferredWidth: 380
                                        spacing: 8
                                        Field {
                                            id: dirField
                                            Layout.fillWidth: true
                                            text: page.value(srow.modelData) || ""
                                            placeholderText: "Choose a folder"
                                            onTextEdited: page.setValue(srow.modelData, text || null)
                                        }
                                        AppButton { text: "Browse…"; onClicked: Store.pick("folder", dirField.text, function (p) { page.setValue(srow.modelData, p) }) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Advanced switch (both modes)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 8
            color: Theme.panel
            border.color: Theme.hairline
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Show advanced settings"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                    Text { Layout.fillWidth: true; text: "Codecs, file naming, tags, DRM devices and library tools. Most people never need these."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight }
                }
                Toggle { checked: Store.prefs.advanced; onToggled: (c) => { Store.prefs.advanced = c; if (c) Store.settingsTab = "account" } }
            }
        }

        Repeater {
            model: Store.prefs.advanced && page.current ? page.current.groups : []
            delegate: ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.leftMargin: 4; text: group.modelData.title; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rows.implicitHeight
                    radius: 8
                    color: Theme.panel
                    border.color: Theme.hairline
                    ColumnLayout {
                        id: rows
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: group.modelData.fields
                            delegate: ColumnLayout {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property var f: modelData
                                readonly property bool stacked: f.type === "order"
                                Layout.fillWidth: true
                                spacing: 0
                                Rectangle { visible: row.index > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }
                                Item {
                                    id: cell
                                    Layout.fillWidth: true
                                    Layout.margins: 16
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 12
                                    readonly property real ctlWidth: Math.min(380, width * 0.5)
                                    implicitHeight: row.stacked ? labels.implicitHeight + 10 + ctl.implicitHeight
                                                                : Math.max(labels.implicitHeight, ctl.implicitHeight)
                                    ColumnLayout {
                                        id: labels
                                        anchors.left: parent.left
                                        anchors.top: row.stacked ? parent.top : undefined
                                        anchors.verticalCenter: row.stacked ? undefined : parent.verticalCenter
                                        width: row.stacked ? parent.width : parent.width - cell.ctlWidth - 24
                                        spacing: 2
                                        Text { text: row.f.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                                        Text { visible: row.f.help !== ""; Layout.fillWidth: true; text: row.f.help; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap }
                                    }
                                    Loader {
                                        id: ctl
                                        anchors.right: parent.right
                                        anchors.bottom: row.stacked ? parent.bottom : undefined
                                        anchors.verticalCenter: row.stacked ? undefined : parent.verticalCenter
                                        width: row.stacked ? parent.width : cell.ctlWidth
                                        property var f: row.f
                                        sourceComponent: {
                                            switch (row.f.type) {
                                            case "check": return checkCtl
                                            case "int": case "int-opt": return intCtl
                                            case "choice": case "choice-opt": case "cover": return choiceCtl
                                            case "file": case "file-opt": case "folder-opt": return pathCtl
                                            case "order": return orderCtl
                                            default: return textCtl
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Settings are saved in " + page.path
            color: Theme.text3; font.family: Theme.font; font.pixelSize: 12
        }
        Item { Layout.preferredHeight: page.dirty ? 70 : 0 }
    }

    // ---- control types ----
    Component {
        id: checkCtl
        Item {
            implicitHeight: 24
            Toggle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; checked: !!page.value(parent.parent.f); onToggled: (c) => page.setValue(parent.parent.f, c) }
        }
    }
    Component {
        id: intCtl
        Item {
            readonly property bool optional: parent.f.type === "int-opt"
            implicitHeight: 32
            Field {
                anchors.right: parent.right
                width: 110
                numeric: true
                validator: IntValidator { bottom: optional ? 0 : 1 }
                text: { var v = page.value(parent.parent.f); return v === null || v === undefined ? "" : String(v) }
                placeholderText: parent.parent.f.type === "int-opt" ? "Off" : ""
                onEditingFinished: {
                    var raw = text.trim(), f = parent.parent.f
                    if (f.type === "int-opt") page.setValue(f, raw === "" || Number(raw) === 0 ? null : Number(raw))
                    else if (raw !== "") page.setValue(f, Number(raw))
                }
            }
        }
    }
    Component {
        id: textCtl
        Field {
            readonly property var f: parent.f
            text: { var v = page.value(f); return v === null || v === undefined ? "" : String(v) }
            echoMode: f.type === "password" ? TextInput.Password : TextInput.Normal
            placeholderText: f.type === "text-opt" ? "Automatic" : f.type === "password" ? "Not set" : ""
            onTextEdited: page.setValue(f, (f.type === "text-opt" || f.type === "password") && text.trim() === "" ? null : text)
        }
    }
    Component {
        id: pathCtl
        RowLayout {
            readonly property var f: parent.f
            spacing: 8
            Field {
                id: pf
                Layout.fillWidth: true
                text: { var v = page.value(parent.f); return v ? String(v) : "" }
                placeholderText: "Not set"
                onTextEdited: page.setValue(parent.f, text.trim() === "" && parent.f.type !== "file" ? null : text)
            }
            AppButton {
                text: "Browse…"
                onClicked: { var f = parent.f; Store.pick(f.type === "folder-opt" ? "folder" : "file", pf.text, function (p) { page.setValue(f, p) }) }
            }
        }
    }
    Component {
        id: choiceCtl
        ComboBox {
            id: combo
            readonly property var f: parent.f
            readonly property var opts: (f.type === "choice-opt" ? [["", "Default"]] : []).concat(page.choices(f))
            model: opts.map(function (o) { return o[1] })
            currentIndex: {
                var v = page.value(f)
                for (var i = 0; i < opts.length; i++) if (String(opts[i][0]) === String(v === null || v === undefined ? "" : v)) return i
                return 0
            }
            onActivated: (i) => {
                var raw = opts[i][0]
                page.setValue(f, f.type === "cover" ? (raw === "max" ? "max" : Number(raw)) : (f.type === "choice-opt" && raw === "" ? null : raw))
            }
            implicitHeight: 32
            font.family: Theme.font
            font.pixelSize: 14
            background: Rectangle { radius: 6; color: combo.hovered ? Theme.fillHover : Theme.fill }
            contentItem: Text { leftPadding: 10; text: combo.displayText; color: Theme.text; font: combo.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            indicator: Icon { x: combo.width - width - 10; y: (combo.height - height) / 2; name: "chev-down"; size: 14; color: Theme.text2 }
            popup: Popup {
                y: combo.height + 4
                width: combo.width
                padding: 4
                implicitHeight: Math.min(contentItem.implicitHeight + 8, 320)
                background: Rectangle { radius: 8; color: "#2f2f2f"; border.color: Qt.rgba(1, 1, 1, 0.1) }
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: combo.popup.visible ? combo.delegateModel : null
                    ScrollBar.vertical: ScrollBar {}
                }
            }
            delegate: ItemDelegate {
                required property int index
                required property var modelData
                width: combo.width - 8
                height: 32
                highlighted: combo.highlightedIndex === index
                background: Rectangle { radius: 5; color: parent.highlighted ? Theme.fillHover : "transparent" }
                contentItem: Text { text: modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
            }
        }
    }
    Component {
        id: orderCtl
        Flow {
            readonly property var f: parent.f
            readonly property bool numbered: f.key.indexOf("priority") >= 0
            spacing: 6
            Repeater {
                model: page.choices(parent.f)
                Chip {
                    required property var modelData
                    readonly property var list: page.value(parent.f) || []
                    readonly property int pos: list.indexOf(modelData[0])
                    small: true
                    text: modelData[1]
                    on: pos >= 0
                    badge: parent.numbered && pos >= 0 ? String(pos + 1) : ""
                    onClicked: {
                        var l = list.slice()
                        if (pos >= 0) l.splice(pos, 1); else l.push(modelData[0])
                        if (!l.length && parent.numbered) { Store.toast("Keep at least one codec.", "bad", "alert"); return }
                        page.setValue(parent.f, l)
                    }
                }
            }
        }
    }

    // Floating save bar
    Rectangle {
        visible: page.dirty
        parent: page
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: Math.min(520, page.width - 48)
        height: 52
        radius: 12
        color: Qt.rgba(0.17, 0.17, 0.17, 0.97)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 10
            spacing: 10
            Text { Layout.fillWidth: true; text: "You have unsaved changes."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
            AppButton { text: "Revert"; kind: "quiet"; onClicked: page.load() }
            AppButton { text: "Save"; kind: "primary"; onClicked: page.save() }
        }
    }
}
