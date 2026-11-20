import QtQuick

// Square artwork with title and subtitle; hover shows play and a secondary action.
Item {
    id: c
    property string artwork
    property string title
    property string subtitle
    property bool explicit: false
    property string glyph: "album"
    property string primaryIcon: "play-f"
    property string secondaryIcon: "folder"
    property bool secondaryBrand: false
    property bool round: false
    signal primary()
    signal secondary()
    signal clicked()
    signal contextRequested()
    implicitHeight: col.implicitHeight

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => { if (m.button === Qt.RightButton) c.contextRequested(); else c.clicked() }
    }
    Column {
        id: col
        width: parent.width
        spacing: 8
        Item {
            width: parent.width
            height: width
            Art { anchors.fill: parent; source: c.artwork; glyph: c.glyph; radius: c.round ? width / 2 : 6 }
            Rectangle {
                anchors.fill: parent
                radius: c.round ? width / 2 : 6
                visible: hover.hovered && !c.round
                gradient: Gradient {
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                }
            }
            CircleButton {
                visible: hover.hovered && c.primaryIcon !== ""
                icon: c.primaryIcon
                brand: true
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                onClicked: c.primary()
            }
            CircleButton {
                visible: hover.hovered && c.secondaryIcon !== ""
                icon: c.secondaryIcon
                brand: c.secondaryBrand
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                onClicked: c.secondary()
            }
        }
        Column {
            width: parent.width
            spacing: 1
            Text {
                width: parent.width
                horizontalAlignment: c.round ? Text.AlignHCenter : Text.AlignLeft
                text: c.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: c.subtitle
                color: Theme.text2
                font.family: Theme.font
                font.pixelSize: 14
                elide: Text.ElideRight
            }
        }
    }
}
