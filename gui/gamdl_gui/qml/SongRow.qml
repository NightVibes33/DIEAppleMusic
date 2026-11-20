import QtQuick
import QtQuick.Layouts

// One row of a song list: artwork (hover to play), title, artist, album,
// a trailing slot (status/time) and hover actions.
Rectangle {
    id: r
    property string artwork
    property string title
    property string sub
    property color subColor: Theme.text2
    property string artist
    property string album
    property bool explicit: false
    property string glyph: "note"
    property bool playing: false
    property bool playable: true
    property bool striped: false
    property real trailingWidth: 170
    // A song to start fetching when the pointer rests on the row, so it plays
    // right away when clicked (anything with Apple Music metadata in .meta).
    property var prefetch: null
    default property alias trailing: slot.data
    property alias actions: actionRow.data
    signal play()
    signal activated()
    signal contextRequested()

    implicitHeight: 56
    radius: 6
    color: hover.hovered ? Theme.fillQuiet : striped ? Theme.stripe : "transparent"
    HoverHandler { id: hover }
    Timer { interval: 300; running: hover.hovered && r.prefetch !== null; onTriggered: Store.prefetch(r.prefetch) }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) r.activated() }
        onClicked: (m) => { if (m.button === Qt.RightButton) r.contextRequested() }
    }

    readonly property bool wide: width > 760
    readonly property real flexible: width - 24 - 40 - trailingWidth - 64 - 14 * (wide ? 5 : 4)
    readonly property real parts: wide ? 4.8 : 3.5

    Row {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Item {
            width: 40
            height: 40
            Art { anchors.fill: parent; radius: 4; source: r.artwork; glyph: r.glyph }
            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.5)
                visible: r.playable && (hover.hovered || r.playing)
                Icon { anchors.centerIn: parent; name: "play-f"; size: 18; visible: !r.playing || playHover.hovered }
                Equalizer { anchors.centerIn: parent; visible: r.playing && !playHover.hovered; running: Store.playing }
                HoverHandler { id: playHover }
                MouseArea { anchors.fill: parent; onClicked: r.play() }
            }
        }
        Column {
            width: r.flexible * 2.2 / r.parts
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Row {
                spacing: 5
                width: parent.width
                Text {
                    id: titleText
                    width: Math.min(implicitWidth, parent.width - (r.explicit ? 18 : 0))
                    text: r.title
                    color: r.playing ? Theme.brand : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Explicit { visible: r.explicit; anchors.verticalCenter: titleText.verticalCenter }
            }
            Text {
                width: parent.width
                visible: r.sub !== ""
                text: r.sub
                color: r.subColor
                font.family: Theme.font
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
        Text {
            width: r.flexible * 1.3 / r.parts
            anchors.verticalCenter: parent.verticalCenter
            text: r.artist
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Text {
            visible: r.wide
            width: r.flexible * 1.3 / r.parts
            anchors.verticalCenter: parent.verticalCenter
            text: r.album
            color: Theme.text2
            font.family: Theme.font
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Item {
            id: slot
            width: r.trailingWidth
            height: 40
        }
        Row {
            id: actionRow
            width: 64
            height: 40
            layoutDirection: Qt.RightToLeft
            spacing: 2
            opacity: hover.hovered ? 1 : 0
        }
    }
}
