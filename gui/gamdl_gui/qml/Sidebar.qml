import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: side
    color: Theme.sidebar
    signal aboutRequested()
    function focusSearch() { search.forceActiveFocus(); search.selectAll() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header: back, app name, more
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            WindowDragArea {}
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 8
                IconButton { icon: "back"; iconSize: 18; enabled: Store.backStack.length > 0; tip: "Back"; onClicked: Store.back() }
                Image {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    // The small version zooms in on the text so it reads at this size.
                    source: Qt.resolvedUrl("icons/app-small.png")
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                }
                Text { Layout.fillWidth: true; text: Theme.appName; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                IconButton { icon: "more"; tip: "About " + Theme.appName; onClicked: side.aboutRequested() }
            }
        }

        // Search
        Field {
            id: search
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 6
            Layout.bottomMargin: 12
            placeholderText: "Search"
            rightPadding: 34
            onAccepted: {
                var term = text.trim()
                if (!term) return
                if (/^(https?:\/\/|isrc:)/i.test(term)) { text = ""; Store.startJob([term], Store.linkLabel(term)); return }
                Store.runSearch(term)
            }
            Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 16; color: Theme.text2 }
        }

        // Navigation
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: nav.implicitHeight + 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: nav
                x: 10
                width: parent.width - 18
                spacing: 2
                NavItem { Layout.fillWidth: true; icon: "home"; text: "Home"; active: Store.view === "home"; onClicked: Store.go("home") }
                NavItem { Layout.fillWidth: true; icon: "download"; text: "Downloading"; badge: Store.activeCount; active: Store.view === "downloads"; onClicked: Store.go("downloads") }
                NavItem { Layout.fillWidth: true; icon: "search"; text: "Search"; active: Store.view === "search"; onClicked: { Store.go("search"); search.forceActiveFocus() } }

                NavItem {
                    Layout.fillWidth: true; icon: "library"; text: "Library"
                    trailingIcon: Store.prefs.libraryCollapsed ? "chev-down" : "chev-up"
                    onClicked: Store.prefs.libraryCollapsed = !Store.prefs.libraryCollapsed
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !Store.prefs.libraryCollapsed
                    spacing: 2
                    NavItem { Layout.fillWidth: true; indent: true; icon: "playlist"; text: "Your Apple Music"; active: Store.view === "library"; onClicked: Store.go("library") }
                    NavItem { Layout.fillWidth: true; indent: true; icon: "clock"; text: "Recently Downloaded"; active: Store.view === "recent"; onClicked: Store.go("recent") }
                    NavItem { Layout.fillWidth: true; indent: true; icon: "album"; text: "Albums"; active: Store.view === "albums"; onClicked: Store.go("albums") }
                    NavItem { Layout.fillWidth: true; indent: true; icon: "note"; text: "Songs"; active: Store.view === "songs"; onClicked: Store.go("songs") }
                }

                NavItem {
                    visible: Store.prefs.advanced
                    Layout.fillWidth: true; icon: "tools"; text: "Library Tools"
                    trailingIcon: Store.prefs.toolsCollapsed ? "chev-down" : "chev-up"
                    onClicked: Store.prefs.toolsCollapsed = !Store.prefs.toolsCollapsed
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Store.prefs.advanced && !Store.prefs.toolsCollapsed
                    spacing: 2
                    NavItem { Layout.fillWidth: true; indent: true; icon: "organize"; text: "Organize Files"; active: Store.view === "organize"; onClicked: Store.go("organize") }
                    NavItem { Layout.fillWidth: true; indent: true; icon: "db"; text: "Media Database"; active: Store.view === "database"; onClicked: Store.go("database") }
                    NavItem { Layout.fillWidth: true; indent: true; icon: "sync"; text: "Sync Playlists"; active: Store.view === "sync"; onClicked: Store.go("sync") }
                }
                NavItem { Layout.fillWidth: true; icon: "gear"; text: "Settings"; active: Store.view === "settings"; onClicked: Store.go("settings") }
            }
        }

        // Profile
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: profileHover.hovered ? Theme.fillQuiet : "transparent"
            HoverHandler { id: profileHover }
            MouseArea { anchors.fill: parent; onClicked: { Store.settingsTab = "account"; Store.go("settings") } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#5e5ce6" }
                        GradientStop { position: 1; color: "#bf5af2" }
                    }
                    Icon { anchors.centerIn: parent; name: "person"; size: 16 }
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: -1
                        color: Store.sessionOk ? Theme.ok : Theme.text3
                        border.color: Theme.sidebar; border.width: 2
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: Store.accountTitle
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Store.accountDetail
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight
                    }
                }
                Icon { name: "gear"; size: 18; color: Theme.text2 }
            }
        }
    }
}
