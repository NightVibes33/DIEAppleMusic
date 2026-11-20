import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs
import QtMultimedia

ApplicationWindow {
    id: win
    onActiveChanged: if (active) Store.checkLibrary()
    width: Math.min(1320, Screen.desktopAvailableWidth - 60)
    height: Math.min(840, Screen.desktopAvailableHeight - 80)
    minimumWidth: 900
    minimumHeight: 580
    visible: true
    title: Theme.appName
    color: Theme.page
    flags: Qt.Window | Qt.FramelessWindowHint
    font.family: Theme.font

    property string drawer: ""
    readonly property var titles: ({ library: "Your Apple Music", home: "Home", downloads: "Downloading", search: "Search", recent: "Recently Downloaded",
                                     albums: "Albums", songs: "Songs", organize: "Organize Files", database: "Media Database",
                                     sync: "Sync Playlists", settings: "Settings" })

    MediaDevices { id: mediaDevices }
    MediaPlayer {
        id: mp
        // Perceptual volume: the slider position maps to loudness, not amplitude.
        // With system volume, the app plays at full level and Windows sets loudness.
        audioOutput: AudioOutput {
            volume: Store.sysVolume ? 1.0 : Math.pow(Store.prefs.volume, 2)
            // Follow Windows' default output live (headphones plugged in, Bluetooth
            // connecting), instead of sticking to the device that was default at launch.
            device: mediaDevices.defaultAudioOutput
        }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) Store.next(true)
        onErrorOccurred: (error, errorString) => {
            Store.loading = false
            var cur = Store.current
            if (cur && cur.path && error === MediaPlayer.FormatError) {
                Store.toast("This file's format can't play inside " + Theme.appName + ", so it opened in your default player.", "", "note")
                Store.call("open_path", [cur.path])
                return
            }
            Store.toast("Couldn't play " + (cur ? cur.title : "this song") + ": " + errorString, "bad", "alert")
        }
    }

    Component.onCompleted: {
        Store.player = mp
        Store.dialogs = win
        if (Store.prefs.winW > 0) {
            width = Math.max(minimumWidth, Store.prefs.winW)
            height = Math.max(minimumHeight, Store.prefs.winH)
            if (Store.prefs.winX >= 0) { x = Store.prefs.winX; y = Store.prefs.winY }
            if (Store.prefs.winMax) Qt.callLater(win.showMaximized)
        }
        Store.restoreQueue()
        Store.refreshState()
        Store.searchApi = Store.appState.search_api || "apple-music"
        Bridge.styleWindow(win)
        if (Store.appState.config_error) showError("Your settings file has a problem", Store.appState.config_error)
        else if (!Store.configured) onboardingLoader.open()
        else Store.autoConnect()
        Store.scanLibrary()
    }

    // ---- file pickers (used through Store.pick) ----
    property var _pickCb: null
    FolderDialog { id: folderDialog; onAccepted: if (win._pickCb) win._pickCb(Bridge.localPath(selectedFolder.toString())) }
    FileDialog { id: fileDialog; onAccepted: if (win._pickCb) win._pickCb(Bridge.localPath(selectedFile.toString())) }
    function pick(kind, current, cb) {
        _pickCb = cb
        if (kind.indexOf("folder") === 0) {
            if (current) folderDialog.currentFolder = Bridge.fileUrl(current)
            folderDialog.open()
        } else {
            fileDialog.open()
        }
    }

    // ---- layout ----
    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.preferredWidth: 298
            Layout.fillHeight: true
            onAboutRequested: aboutSheet.open()
        }

        Item {
            id: mainCol
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Artwork tint behind the top bar and page title, as in Apple Music.
            Item {
                id: tint
                width: parent.width
                height: 114
                clip: true
                readonly property string art: Store.current ? (Store.current.artwork || "") : Store.focus ? Store.focus.artwork : Store.history.count ? Store.history.get(0).artwork : ""
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#3a2a14" }
                        GradientStop { position: 0.5; color: "#26303d" }
                        GradientStop { position: 1.0; color: "#3a221d" }
                    }
                }
                Image {
                    id: tintImg
                    anchors.centerIn: parent
                    width: parent.width * 1.3
                    height: parent.width * 1.3
                    source: tint.art
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    sourceSize: Qt.size(256, 256)
                }
                MultiEffect {
                    anchors.fill: tintImg
                    source: tintImg
                    visible: tintImg.status === Image.Ready
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.5
                    opacity: 0.6
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.11, 0.11, 0.11, 0.15) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.11, 0.11, 0.11, 0.6) }
                    }
                }
            }

            TopBar {
                id: topBar
                width: parent.width
                height: 66
                player: mp
                drawer: win.drawer
                onDrawerToggled: (tab) => win.drawer = (win.drawer === tab ? "" : tab)
                onCloseRequested: win.requestClose()
                onLyricsRequested: nowPlaying.panel = "lyrics"
            }

            // Page title
            Item {
                id: titleBar
                y: 66
                width: parent.width
                height: 48
                z: 2
                WindowDragArea {}
                Text {
                    anchors.centerIn: parent
                    text: Store.view === "search" && Store.searchTerm ? "“" + Store.searchTerm + "”" : Store.view === "collection" ? "" : (win.titles[Store.view] || "")
                    color: Theme.text
                    font.family: Theme.display
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Loader {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: pageLoader.item ? pageLoader.item.actions : null
                }
            }

            Loader {
                id: pageLoader
                anchors.fill: parent
                anchors.topMargin: 114
                sourceComponent: {
                    switch (Store.view) {
                    case "downloads": return downloadsPage
                    case "search": return searchPage
                    case "recent": case "albums": return albumsPage
                    case "songs": return songsPage
                    case "organize": case "database": case "sync": return toolsPage
                    case "settings": return settingsPage
                    case "library": return libraryPage
                    case "collection": return collectionPage
                    default: return homePage
                    }
                }
            }
            Component { id: homePage; HomePage {} }
            Component { id: downloadsPage; DownloadsPage {} }
            Component { id: searchPage; SearchPage {} }
            Component { id: albumsPage; AlbumsPage { sortByName: Store.view === "albums" } }
            Component { id: songsPage; SongsPage {} }
            Component { id: toolsPage; ToolsPage { tool: Store.view } }
            Component { id: libraryPage; LibraryPage {} }
            Component { id: collectionPage; CollectionPage {} }
            Component { id: settingsPage; SettingsPage { onSignInRequested: onboardingLoader.open() } }

            DrawerPanel {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 74
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                tab: win.drawer
                onTabChanged: win.drawer = tab
            }
        }
    }

    NowPlaying { id: nowPlaying; anchors.fill: parent; player: mp; z: 40 }
    SignInScreen { id: signIn; anchors.fill: parent; z: 45; onOtherOptionsRequested: onboarding.open() }

    ItemMenu { id: itemMenu }
    Connections {
        target: Store
        function onMenuRequested(spec) { itemMenu.show(spec) }
        function onJobsFinished() { if (!win.active) win.alert(0) }
    }

    // Media keys and the taskbar's thumbnail buttons, from anywhere (the window
    // can be in the background or minimized).
    Connections {
        target: Bridge
        function onMediaAction(a) {
            if (a === "toggle") Store.toggle()
            else if (a === "next") Store.next(false)
            else if (a === "prev") Store.prev()
            else if (a === "stop" && Store.player) Store.player.stop()
        }
    }
    Connections {
        target: Store
        function onPlayingChanged() { Bridge.setPlaying(Store.playing) }
    }

    // Keyboard shortcuts while the window is active.
    Shortcut { sequence: "Space"; onActivated: Store.toggle() }
    Shortcut { sequences: ["Media Play", "Media Pause", "Toggle Media Play/Pause"]; onActivated: Store.toggle() }
    Shortcut { sequences: ["Media Next", "Ctrl+Right"]; onActivated: Store.next(false) }
    Shortcut { sequences: ["Media Previous", "Ctrl+Left"]; onActivated: Store.prev() }
    Shortcut { sequence: "Media Stop"; onActivated: if (Store.player) Store.player.stop() }
    Shortcut { sequence: "Ctrl+F"; onActivated: { Store.nowPlayingOpen = false; sidebar.focusSearch() } }
    Shortcut { sequence: "Ctrl+L"; onActivated: Store.nowPlayingOpen = !Store.nowPlayingOpen }
    Shortcut { sequence: "Ctrl+Up"; onActivated: Store.setVolume(Store.volume + 0.05) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: Store.setVolume(Store.volume - 0.05) }
    Shortcut { sequence: "Alt+Left"; onActivated: Store.back() }

    // Drop an Apple Music link anywhere on the window to download it.
    DropArea {
        id: drop
        anchors.fill: parent
        z: 90
        function links(d) {
            var t = (d.text || "") + " " + (d.urls || []).map(function (u) { return String(u) }).join(" ")
            return t.split(/\s+/).filter(function (x) { return /^https?:\/\/(music|itunes)\.apple\.com\//i.test(x) || /^isrc:/i.test(x) })
        }
        onEntered: (d) => { d.accepted = links(d).length > 0 }
        onDropped: (d) => {
            var l = links(d)
            if (l.length) Store.startJob(l, Store.linkLabel(l.join(" ")))
        }
        Rectangle {
            anchors.fill: parent
            visible: drop.containsDrag
            color: Qt.rgba(0.04, 0.04, 0.05, 0.75)
            border.color: Theme.brand
            border.width: 3
            Column {
                anchors.centerIn: parent
                spacing: 12
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "download"; size: 48; color: Theme.brand }
                Text { text: "Drop to download"; color: Theme.text; font.family: Theme.display; font.pixelSize: 22; font.weight: Font.Bold }
            }
        }
    }

    function rememberWindow() {
        Store.prefs.winMax = win.visibility === Window.Maximized
        if (!Store.prefs.winMax) {
            Store.prefs.winX = win.x; Store.prefs.winY = win.y
            Store.prefs.winW = win.width; Store.prefs.winH = win.height
        }
    }

    Toasts { id: toasts; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 22 }
    Connections {
        target: Store
        function onToastRequested(text, kind, icon) { toasts.show(text, kind, icon) }
        function onOnboardingRequested() { onboardingLoader.open() }
        function onPromptArrived() { win.nextPrompt() }
        function onErrorRequested(title, text) { win.showError(title, text) }
    }

    // ---- sheets ----
    QtObject {
        id: onboardingLoader
        function open() { if (!signIn.open) signIn.show() }
    }
    OnboardingSheet { id: onboarding }
    AboutSheet { id: aboutSheet }
    MessageSheet { id: messageSheet }

    function showError(title, text) { messageSheet.show(title, text, "OK", false) }
    function confirm(title, text, okLabel, cb) { messageSheet.ask(title, text, okLabel, cb) }

    property var activePrompt: null
    Component { id: selectSheet; SelectSheet {} }
    Component { id: browseSheet; BrowseSheet {} }
    Component { id: streamSheet; StreamSheet {} }
    Component { id: credentialsSheet; CredentialsSheet {} }
    Component { id: codeSheet; CodeSheet {} }
    function nextPrompt() {
        if (activePrompt || !Store.promptQueue.length) return
        var p = Store.promptQueue.shift()
        var comp = ({ select: selectSheet, browse: browseSheet, stream: streamSheet, credentials: credentialsSheet, two_factor: codeSheet })[p.kind]
        if (!comp) { Store.call("answer", [p.id, null, true]); return }
        activePrompt = comp.createObject(win, { prompt: p })
        activePrompt.closed.connect(function () {
            var s = activePrompt; activePrompt = null; s.destroy(); Qt.callLater(win.nextPrompt)
        })
        activePrompt.open()
    }

    // ---- close ----
    property bool _closing: false
    function requestClose() {
        rememberWindow()
        if (Store.activeCount > 0) confirm("Quit " + Theme.appName + "?", "Downloads are still running. Quitting stops them.", "Quit", function () { win._closing = true; Qt.quit() })
        else { _closing = true; Qt.quit() }
    }
    onClosing: (close) => {
        rememberWindow()
        if (!_closing && Store.activeCount > 0) { close.accepted = false; requestClose() }
    }

    // ---- native resize edges (frameless window) ----
    Repeater {
        model: [
            { e: Qt.LeftEdge, x: 0, y: 8, w: 5, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.RightEdge, x: -5, y: 8, w: 5, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.TopEdge, x: 8, y: 0, w: -16, h: 4, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, x: 8, y: -5, w: -16, h: 5, c: Qt.SizeVerCursor },
            { e: Qt.LeftEdge | Qt.TopEdge, x: 0, y: 0, w: 9, h: 9, c: Qt.SizeFDiagCursor },
            { e: Qt.RightEdge | Qt.BottomEdge, x: -9, y: -9, w: 9, h: 9, c: Qt.SizeFDiagCursor },
            { e: Qt.RightEdge | Qt.TopEdge, x: -9, y: 0, w: 9, h: 9, c: Qt.SizeBDiagCursor },
            { e: Qt.LeftEdge | Qt.BottomEdge, x: 0, y: -9, w: 9, h: 9, c: Qt.SizeBDiagCursor }
        ]
        MouseArea {
            required property var modelData
            visible: win.visibility !== Window.Maximized
            x: modelData.x < 0 ? win.width + modelData.x : modelData.x
            y: modelData.y < 0 ? win.height + modelData.y : modelData.y
            width: modelData.w < 0 ? win.width + modelData.w : modelData.w
            height: modelData.h < 0 ? win.height + modelData.h : modelData.h
            cursorShape: modelData.c
            z: 100
            onPressed: win.startSystemResize(modelData.e)
        }
    }
}
