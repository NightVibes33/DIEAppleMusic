import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PageScroll {
    id: home
    spacing: 14

    function submit() {
        var text = links.text.trim()
        if (!text) { links.forceActiveFocus(); Store.toast("Paste at least one Apple Music link.", "bad", "alert"); return }
        Store.startJob(text.split(/\s+/).filter(function (x) { return x }), Store.linkLabel(text))
        links.text = ""
    }

    // Sign-in banner
    Rectangle {
        visible: !Store.configured
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        implicitHeight: 80
        radius: 8
        color: Theme.panel
        border.color: Theme.hairline
        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 18
            Rectangle {
                width: 44; height: 44; radius: 11
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ff5c75" }
                    GradientStop { position: 1; color: "#d81c3c" }
                }
                Icon { anchors.centerIn: parent; name: "note"; size: 22 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Sign in with your Apple ID"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; text: Theme.appName + " uses your Apple Music subscription to download and play songs."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; elide: Text.ElideRight }
            }
            AppButton { text: "Sign In"; kind: "primary"; onClicked: Store.onboardingRequested() }
        }
    }

    SectionHead { text: "Download"; chevron: false }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 96
        radius: 10
        color: "#242424"
        border.color: links.activeFocus ? Qt.rgba(0, 0.57, 1, 0.6) : Theme.hairline
        RowLayout {
            anchors.fill: parent
            spacing: 0
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    id: links
                    padding: 16
                    leftPadding: 18
                    wrapMode: TextArea.Wrap
                    color: Theme.text
                    placeholderText: "Paste Apple Music links: songs, albums, playlists, artists or music videos. One per line. You can also enter isrc:USUM71703085"
                    placeholderTextColor: Theme.text3
                    selectionColor: Theme.select
                    font.family: Theme.font
                    font.pixelSize: 15
                    background: null
                    Keys.onReturnPressed: (e) => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else home.submit() }
                }
            }
            AppButton {
                Layout.alignment: Qt.AlignTop
                Layout.margins: 12
                text: "Download"; icon: "download"; kind: "primary"; large: true
                onClicked: home.submit()
            }
        }
    }
    RowLayout {
        spacing: 24
        Toggle { text: "Let me pick songs from albums and playlists"; checked: Store.prefs.optSelect; onToggled: (c) => Store.prefs.optSelect = c }
        Toggle { visible: Store.prefs.advanced; text: "Ask which stream to use for each song"; checked: Store.prefs.optAsk; onToggled: (c) => Store.prefs.optAsk = c }
    }

    // Active downloads
    SectionHead {
        visible: Store.activeCount > 0
        Layout.topMargin: 14
        text: "Downloading"
        linkText: "See All"
        onLinkClicked: Store.go("downloads")
    }
    Repeater {
        model: Store.jobs
        delegate: ColumnLayout {
            required property int jobId
            required property bool done
            Layout.fillWidth: true
            visible: !done
            spacing: 0
            Repeater {
                model: Store.jobModel(parent.jobId)
                delegate: QueueRow {
                    required property var model
                    required property int index
                    Layout.fillWidth: true
                    visible: !model.status
                    it: model
                    jobId: parent.jobId
                    striped: index % 2 === 0
                }
            }
        }
    }

    // Recently downloaded shelf
    SectionHead {
        Layout.topMargin: 14
        text: "Recently Downloaded"
        linkText: Store.recentAlbums.length ? "See All" : ""
        onLinkClicked: Store.go("recent")
    }
    ListView {
        visible: Store.recentAlbums.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 186 + 62
        orientation: ListView.Horizontal
        spacing: 22
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Store.recentAlbums.slice(0, 14)
        delegate: AlbumCard {
            required property var modelData
            width: 186
            artwork: modelData.artwork
            title: modelData.album
            subtitle: modelData.artist
            onPrimary: Store.playList(modelData.tracks.slice().reverse(), 0)
            onSecondary: Store.call("reveal", [modelData.tracks[0].path])
            onClicked: Store.openLocalAlbum(modelData)
            onContextRequested: Store.showMenu({ entries: modelData.tracks.slice().reverse() })
        }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
    }
    Rectangle {
        visible: Store.recentAlbums.length === 0
        Layout.fillWidth: true
        implicitHeight: 150
        radius: 8
        color: Theme.panel
        border.color: Theme.hairline
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10
            Rectangle { Layout.alignment: Qt.AlignHCenter; width: 56; height: 56; radius: 14; color: Theme.fill; Icon { anchors.centerIn: parent; name: "clock"; size: 26; color: Theme.text2 } }
            Text { text: "Albums and songs you download appear here with their artwork."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
        }
    }
}
