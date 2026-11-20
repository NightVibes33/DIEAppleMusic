import QtQuick

// Column captions aligned with SongRow's layout.
Item {
    id: h
    property string c1: "Song"
    property string c2: "Artist"
    property string c3: "Album"
    property string c4: "Status"
    property real trailingWidth: 170
    implicitHeight: 30
    readonly property bool wide: width > 760
    readonly property real flexible: width - 24 - 40 - trailingWidth - 64 - 14 * (wide ? 5 : 4)
    readonly property real parts: wide ? 4.8 : 3.5
    Row {
        x: 12 + 40 + 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Text { width: h.flexible * 2.2 / h.parts; text: h.c1; color: Theme.text2; font.pixelSize: 12; font.family: Theme.font }
        Text { width: h.flexible * 1.3 / h.parts; text: h.c2; color: Theme.text2; font.pixelSize: 12; font.family: Theme.font }
        Text { visible: h.wide; width: h.flexible * 1.3 / h.parts; text: h.c3; color: Theme.text2; font.pixelSize: 12; font.family: Theme.font }
        Text { width: h.trailingWidth; text: h.c4; color: Theme.text2; font.pixelSize: 12; font.family: Theme.font }
    }
}
