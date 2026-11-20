import QtQuick
import QtQuick.Controls

// One right-click menu for songs, albums, playlists and Up Next rows. It shows
// only what applies to the item: catalog, library, or a file on this computer.
Menu {
    id: m
    property var spec: ({})
    readonly property var entries: spec.entries || []
    readonly property var coll: spec.collection || null
    readonly property bool hasEntries: entries.length > 0
    readonly property bool streamable: entries.some(function (e) { return e.meta && !e.path })
    readonly property bool local: entries.length > 0 && entries.every(function (e) { return !!e.path })
    readonly property string link: spec.link || (coll ? coll.link || "" : "") || (entries.length === 1 ? entries[0].link || "" : "")

    function show(s) { spec = s; popup() }

    background: Rectangle { implicitWidth: 230; radius: 8; color: "#2f2f2f"; border.color: Qt.rgba(1, 1, 1, 0.1) }
    delegate: MenuItem {
        id: mi
        implicitHeight: visible ? 34 : 0
        height: visible ? implicitHeight : 0
        background: Rectangle { radius: 5; color: mi.highlighted ? Theme.fillHover : "transparent" }
        contentItem: Text { leftPadding: 6; text: mi.text; color: mi.enabled ? (mi.text.indexOf("Recycle") >= 0 ? Theme.bad : Theme.text) : Theme.text3; font.family: Theme.font; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
    }

    Action { text: m.coll ? "Open" : "Play"; enabled: m.hasEntries || !!m.coll
        onTriggered: m.coll && !m.hasEntries ? Store.openCollection(m.coll) : Store.playList(m.entries, 0) }
    Action { text: "Play Next"; enabled: m.hasEntries; onTriggered: Store.playNext(m.entries) }
    Action { text: "Add to Up Next"; enabled: m.hasEntries; onTriggered: Store.addToQueue(m.entries) }
    Action { text: "Remove from Up Next"; enabled: m.spec.queueIndex !== undefined && m.spec.queueIndex > Store.playIndex
        onTriggered: Store.removeFromQueue(m.spec.queueIndex) }
    MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Theme.hairline } }
    Action { text: m.coll && (m.coll.kind === "album" || m.coll.kind === "playlist") ? "Download " + (m.coll.kind === "album" ? "Album" : "Playlist") : "Download"
        enabled: (m.coll && (m.coll.kind === "album" || m.coll.kind === "playlist")) || m.streamable
        onTriggered: {
            if (m.coll && (m.coll.kind === "album" || m.coll.kind === "playlist"))
                Store.startJob([{ type: m.coll.kind === "album" ? "albums" : "playlists", meta: m.coll.meta, library: m.coll.library, label: m.coll.title }],
                               m.coll.title, { art: m.coll.artwork, sub: m.coll.subtitle, auto: false })
            else Store.downloadEntries(m.entries)
        } }
    Action { text: "Copy Link"; enabled: m.link !== ""; onTriggered: Store.copyLinks([{ link: m.link }]) }
    Action { text: "Show in Folder"; enabled: m.local; onTriggered: Store.call("reveal", [m.entries[0].path]) }
    MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Theme.hairline } }
    Action { text: "Move to Recycle Bin"; enabled: m.local; onTriggered: Store.deleteEntries(m.entries) }
}
