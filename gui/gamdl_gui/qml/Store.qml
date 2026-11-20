pragma Singleton
import QtQuick
import QtCore

// App state, backend calls, engine events and the play queue.
QtObject {
    id: store

    // ---- navigation ----
    property string view: "home"
    property var backStack: []
    property string toolId: "organize"
    property string settingsTab: "account"

    function go(v) {
        if (v === view) return
        var s = backStack.slice(); s.push(view === "collection" ? { view: view, collection: collection } : view); backStack = s
        view = v
    }
    function back() {
        if (!backStack.length) return
        var s = backStack.slice(); var last = s.pop(); backStack = s
        if (typeof last === "object") { collection = last.collection; view = last.view }
        else view = last
    }

    // ---- persisted preferences ----
    property Settings prefs: Settings {
        category: "ui"
        property bool optSelect: false
        property bool optAsk: false
        property string toolDir: ""
        property string libSort: "recent"
        property real volume: 0.8
        property bool debugLog: false
        property bool libraryCollapsed: false
        property bool toolsCollapsed: false
        property bool advanced: false
        property int winX: -1
        property int winY: -1
        property int winW: 0
        property int winH: 0
        property bool winMax: false
        property string lastQueue: ""
        property int lastIndex: -1
    }

    // ---- app state ----
    property var appState: ({})
    property bool sessionOk: false
    property string sessionDesc: ""
    property var accountProfile: ({})
    property string status: ""
    readonly property bool configured: !!(appState.auth && appState.directory)

    signal toastRequested(string text, string kind, string icon)
    signal onboardingRequested()
    signal promptArrived()
    signal appleSigninFinished(bool ok, string error)
    signal signinNeedsToken()
    signal signedOut()
    signal menuRequested(var spec)
    signal jobsFinished()
    signal errorRequested(string title, string text)

    function toast(text, kind, icon) { toastRequested(text, kind || "", icon || "check") }

    property var dialogs: null
    function pick(kind, current, cb) { if (dialogs) dialogs.pick(kind, current || "", cb) }
    function copy(text) { Bridge.copyText(text); toast("Copied", "ok", "check") }

    // ---- backend calls ----
    property var _callbacks: ({})
    function call(name, args, cb) {
        var id = Bridge.call(name, JSON.stringify(args || []))
        if (cb) _callbacks[id] = cb
    }
    function callSync(name, args) { return JSON.parse(Bridge.callSync(name, JSON.stringify(args || []))) }

    property Connections _conn: Connections {
        target: Bridge
        function onResult(id, json) {
            var cb = store._callbacks[id]
            if (cb) { delete store._callbacks[id]; cb(JSON.parse(json)) }
        }
        function onEvents(json) { store.handle(JSON.parse(json)) }
    }

    function refreshState() {
        appState = callSync("get_state")
        history.clear()
        for (var i = 0; i < (appState.history || []).length; i++) history.append(histRow(appState.history[i]))
        mergeScan()
        recomputeAlbums()
        // A new or changed music folder: look for the songs already in it.
        if ((appState.directory || "") !== scannedDir) scanLibrary()
    }

    // Reconnect the saved Apple ID session at launch, quietly.
    property bool connecting: false
    function autoConnect() {
        if (!appState.auth || sessionOk || connecting) return
        connecting = true
        call("connect_apple_music", [], function (r) {
            connecting = false
            if (r.ok) {
                sessionOk = true
                if (!sessionDesc) sessionDesc = "Connected to Apple Music"
                return
            }
            sessionOk = false
            sessionDesc = "Saved Apple ID could not be verified"
            var msg = friendlyError(r.error)
            logModel.append({ level: "warn", msg: "Couldn't reconnect to Apple Music: " + msg, time: stamp() })
        })
    }

    function signOut() {
        dialogs.confirm("Sign out of Apple Music?",
            Theme.appName + " will forget your Apple ID on this computer. Music you've already downloaded stays where it is.",
            "Sign Out", function () {
                var r = JSON.parse(Bridge.signOut())
                if (!r.ok) { toast(friendlyError(r.error), "bad", "alert"); return }
                sessionOk = false
                sessionDesc = ""
                libItems = { "playlists": [], "albums": [], "songs": [], "music-videos": [] }
                libLoaded = ({})
                libVersion++
                refreshState()
                signedOut()
                toast("Signed out of Apple Music", "ok", "check")
            })
    }

    function ensureReady(needFolder) {
        if (!appState.auth || (needFolder !== false && !appState.directory)) { onboardingRequested(); return false }
        return true
    }

    // ---- downloads ----
    property ListModel jobs: ListModel {}
    property var _jobItems: ({})
    property var _itemLoc: ({})
    property int activeCount: 0
    property int itemsTotal: 0
    property int itemsDone: 0
    property string focusKey: ""
    property var focus: null   // the item shown in the top bar while downloading

    function jobModel(id) { return _jobItems[id] || null }
    function jobIndex(id) { for (var i = 0; i < jobs.count; i++) if (jobs.get(i).jobId === id) return i; return -1 }

    function addJob(id, label, extra) {
        if (jobIndex(id) >= 0) return
        _jobItems[id] = Qt.createQmlObject('import QtQuick; ListModel {}', store)
        var row = { jobId: id, label: label, slug: label, sub: "", art: "", done: false, summary: "", auto: true, failed: false, sourcesJson: "" }
        for (var k in (extra || {})) row[k] = extra[k]
        jobs.insert(0, row)
    }

    function startJob(sources, label, extra) {
        if (!ensureReady(true)) return
        call("start_job", [sources, prefs.optSelect, prefs.optAsk], function (id) {
            var e = {}
            for (var k in (extra || {})) e[k] = extra[k]
            e.sourcesJson = JSON.stringify(sources)
            addJob(id, label, e)
            toast("Added to Downloading", "ok", "download")
        })
    }

    function recount() {
        var total = 0, done = 0, active = 0
        for (var i = 0; i < jobs.count; i++) {
            var m = _jobItems[jobs.get(i).jobId]
            if (!m) continue
            for (var j = 0; j < m.count; j++) {
                total++
                if (m.get(j).status) done++; else active++
            }
        }
        itemsTotal = total; itemsDone = done; activeCount = active
        updateFocus()
    }

    function itemByKey(key) {
        var loc = _itemLoc[key]
        if (!loc) return null
        var m = _jobItems[loc.job]
        return m ? { model: m, index: loc.index, data: m.get(loc.index) } : null
    }

    function updateFocus() {
        var it = focusKey ? itemByKey(focusKey) : null
        if (it && !it.data.status) { focus = it.data; return }
        for (var i = 0; i < jobs.count; i++) {
            var m = _jobItems[jobs.get(i).jobId]
            if (!m) continue
            for (var j = 0; j < m.count; j++) if (!m.get(j).status) { focus = m.get(j); return }
        }
        focus = null
    }

    function clearFinished() {
        for (var i = jobs.count - 1; i >= 0; i--) {
            var j = jobs.get(i)
            if (j.done) { delete _jobItems[j.jobId]; jobs.remove(i) }
        }
        recount()
    }

    // ---- library (from download history) ----
    property ListModel history: ListModel {}
    property var albums: []         // everything: Gamdl downloads + music found in the folder
    property var recentAlbums: []   // only what Gamdl downloaded

    function histRow(h) {
        return { title: h.title || "", artist: h.artist || "", album: h.album || "", artwork: h.artwork || "",
                 path: h.path || "", kind: h.kind || "Song", explicit: !!h.explicit, time: h.time || "", duration: h.duration || 0, local: !!h.local }
    }
    function recomputeAlbums() {
        var map = {}, order = []
        for (var i = 0; i < history.count; i++) {
            var h = history.get(i)
            var key = (h.album || h.title) + "\u0000" + h.artist
            if (!map[key]) { map[key] = { album: h.album || h.title, artist: h.artist, artwork: h.artwork, tracks: [] }; order.push(key) }
            map[key].tracks.push(histRow(h))
        }
        var list = order.map(function (k) { return map[k] })
        list.forEach(function (a) { a.time = a.tracks.reduce(function (m, t) { return t.time > m ? t.time : m }, "") })
        list.sort(function (a, b) { return a.time < b.time ? 1 : a.time > b.time ? -1 : 0 })
        albums = list
        recentAlbums = list.filter(function (a) { return a.tracks.some(function (t) { return !t.local }) })
    }
    function historyEntries() {
        var out = []
        for (var i = 0; i < history.count; i++) out.push(histRow(history.get(i)))
        return out
    }

    // ---- search ----
    property ListModel results: ListModel {}
    property string searchTerm: ""
    property string searchKind: "songs"
    property string searchApi: "apple-music"
    property int searchToken: 0
    property bool searchLoading: false
    property bool searchMore: false
    property string searchError: ""

    function runSearch(term) {
        if (term !== undefined) searchTerm = term
        if (!searchTerm) return
        if (!ensureReady(false)) return
        if (searchApi === "itunes" && searchKind === "playlists") { searchKind = "songs"; toast("iTunes search has no playlists.", "", "alert") }
        searchToken++
        results.clear(); searchMore = false; searchError = ""; searchLoading = true
        go("search")
        var token = searchToken
        call("search", [token, searchTerm, searchKind, searchApi], function (r) {
            if (!r.ok && token === searchToken) { searchLoading = false; searchError = friendlyError(r.error) }
        })
    }
    function searchNext() {
        searchLoading = true
        call("search_more", [searchToken, searchKind], function (r) { if (!r.ok) { searchLoading = false; searchError = r.error } })
    }
    function resultMeta(i) { return JSON.parse(results.get(i).metaJson) }
    function downloadResult(i) {
        var r = results.get(i)
        startJob([{ type: searchKind, meta: resultMeta(i), label: r.name + " — " + r.artist }], r.name, { art: r.artwork, sub: r.artist, auto: false })
    }

    // ---- the person's Apple Music library ----
    property var libItems: ({ "playlists": [], "albums": [], "songs": [], "music-videos": [] })
    property var libLoading: ({})
    property var libLoaded: ({})
    property string libError: ""
    property int libVersion: 0

    function loadLibrary(kind, refresh) {
        if (!ensureReady(false)) return
        if (libLoading[kind] || (libLoaded[kind] && !refresh)) return
        libLoading[kind] = true; libError = ""; libVersion++
        call("library_load", [kind, !!refresh], function (r) {
            libLoading[kind] = false
            if (r.ok) libLoaded[kind] = true
            else libError = friendlyError(r.error)
            libVersion++
        })
    }
    function loadWholeLibrary(refresh) {
        var kinds = ["playlists", "albums", "songs", "music-videos"]
        for (var i = 0; i < kinds.length; i++) loadLibrary(kinds[i], refresh)
    }
    function librarySource(kind, item) {
        return { library: true, type: kind, meta: item.meta, label: item.name + (item.artist ? " — " + item.artist : "") }
    }
    function downloadLibrary(kind, items) {
        if (!items.length) return
        startJob(items.map(function (it) { return librarySource(kind, it) }),
                 items.length === 1 ? items[0].name : items.length + " items from your library",
                 items.length === 1 ? { art: items[0].artwork, sub: items[0].artist } : { sub: "Your Apple Music" })
    }
    function copyLinks(items) {
        var links = items.map(function (it) { return it.link }).filter(function (l) { return l })
        if (!links.length) { toast("Apple Music has no shareable link for this item.", "bad", "alert"); return }
        Bridge.copyText(links.join("\n"))
        toast(links.length === 1 ? "Link copied" : links.length + " links copied", "ok", "link")
    }
    function playLibrary(kind, items, start) {
        if (kind === "songs") {
            playList(items.map(function (s) { return { title: s.name, artist: s.artist, album: s.album, artwork: s.artwork, explicit: s.explicit, meta: s.meta } }), start)
            return
        }
        if (kind === "music-videos") { toast("Music videos can't play in the app yet. Download them instead.", "", "video"); return }
        var item = items[start]
        status = "Loading " + item.name + "…"
        call("collection_tracks", ["library-" + kind, item.meta], function (r) {
            status = ""
            if (!r.ok) { toast(friendlyError(r.error), "bad", "alert"); return }
            playList(r.tracks.map(function (t) { return { title: t.name, artist: t.artist, album: t.album, artwork: t.artwork || item.artwork, explicit: t.explicit, meta: t.meta } }), 0)
        })
    }

    // ---- music already in the music folder ----
    property bool scanning: false
    property var scanItems: []
    property string scannedDir: ""
    function scanLibrary() {
        if (scanning) return
        scanning = true
        var dir = appState.directory || ""
        call("scan_library", [], function (r) {
            scanning = false
            if (!r.ok) return
            scanItems = r.items
            scannedDir = dir
            lastScan = Date.now()
            // Rebuild from the saved history (which drops files deleted outside
            // the app) plus what's in the folder now, so removed songs disappear.
            refreshState()
            if ((appState.directory || "") !== scannedDir) scanLibrary()
        })
    }
    // Look again when the window comes back to the front: songs may have been
    // added, moved or deleted in File Explorer meanwhile.
    property real lastScan: 0
    function checkLibrary() {
        if (!scanning && Date.now() - lastScan > 10000) scanLibrary()
    }
    // Adds songs found in the music folder that the download history doesn't list.
    function mergeScan() {
        var known = {}
        for (var i = 0; i < history.count; i++) known[history.get(i).path] = true
        var added = 0
        for (var j = 0; j < scanItems.length; j++) {
            var it = scanItems[j]
            if (known[it.path]) continue
            history.append(histRow(it)); added++
        }
        return added > 0
    }

    // ---- album, playlist and artist pages ----
    property var collection: null
    property int _collToken: 0
    function entryFrom(s, library) {
        return { title: s.name, artist: s.artist, album: s.album, artwork: s.artwork, explicit: !!s.explicit,
                 duration: s.duration || 0, meta: s.meta, link: s.link || "", downloadType: "songs", library: !!library }
    }
    function openCollection(spec) {
        var c = { kind: spec.kind, title: spec.title || "", subtitle: spec.subtitle || "", artwork: spec.artwork || "",
                  meta: spec.meta || null, library: !!spec.library, link: spec.link || "", tracks: spec.tracks || [],
                  albums: [], singles: [], loading: !spec.tracks, error: "" }
        if (view === "collection") { var st = backStack.slice(); st.push({ view: "collection", collection: collection }); backStack = st; collection = c }
        else { collection = c; go("collection") }
        if (spec.tracks) return
        var token = ++_collToken
        var finish = function (update) {
            if (token !== _collToken) return
            var n = {}
            for (var k in collection) n[k] = collection[k]
            for (var u in update) n[u] = update[u]
            n.loading = false
            collection = n
        }
        if (c.kind === "artist") {
            call("artist", [c.meta], function (r) {
                if (!r.ok) return finish({ error: friendlyError(r.error) })
                finish({ tracks: r.top.map(function (x) { return entryFrom(x, false) }), albums: r.albums, singles: r.singles,
                         artwork: c.artwork || r.artwork, link: r.link || c.link })
            })
        } else {
            call("collection_tracks", [(c.library ? "library-" : "") + (c.kind === "album" ? "albums" : "playlists"), c.meta], function (r) {
                if (!r.ok) return finish({ error: friendlyError(r.error) })
                finish({ tracks: r.tracks.map(function (x) { return entryFrom(x, c.library) }) })
            })
        }
    }
    function openSummary(kind, s, library) {
        if (kind === "artists") openCollection({ kind: "artist", title: s.name, artwork: s.artwork, meta: s.meta, link: s.link })
        else if (kind === "albums" || kind === "playlists")
            openCollection({ kind: kind === "albums" ? "album" : "playlist", title: s.name, subtitle: s.artist, artwork: s.artwork,
                             meta: s.meta, link: s.link, library: !!library })
    }
    function openLocalAlbum(a) {
        openCollection({ kind: "local", title: a.album, subtitle: a.artist, artwork: a.artwork, tracks: a.tracks.slice().reverse() })
    }

    // ---- queue control ----
    function playNext(entries) {
        if (!entries.length) return
        if (!current || !playQueue.length) { playList(entries, 0); return }
        var q = playQueue.slice()
        Array.prototype.splice.apply(q, [playIndex + 1, 0].concat(entries))
        playQueue = q
        toast(entries.length === 1 ? "\u201c" + entries[0].title + "\u201d will play next" : entries.length + " songs will play next", "ok", "queue")
    }
    function addToQueue(entries) {
        if (!entries.length) return
        if (!current || !playQueue.length) { playList(entries, 0); return }
        playQueue = playQueue.concat(entries)
        toast(entries.length === 1 ? "Added \u201c" + entries[0].title + "\u201d to Up Next" : "Added " + entries.length + " songs to Up Next", "ok", "queue")
    }
    function removeFromQueue(i) {
        if (i <= playIndex || i >= playQueue.length) return
        var q = playQueue.slice(); q.splice(i, 1); playQueue = q
    }
    function rememberQueue() {
        try {
            prefs.lastQueue = JSON.stringify(playQueue.slice(0, 200))
            prefs.lastIndex = playIndex
        } catch (e) { }
    }
    function restoreQueue() {
        if (!prefs.lastQueue) return
        try {
            var q = JSON.parse(prefs.lastQueue)
            if (!q.length) return
            playQueue = q
            playIndex = Math.max(0, Math.min(prefs.lastIndex, q.length - 1))
            current = q[playIndex]
        } catch (e) { }
    }

    // ---- downloads from any song, album or playlist ----
    function sourceFor(entry) {
        return entry.library ? { library: true, type: entry.downloadType || "songs", meta: entry.meta, label: entry.title }
                             : { type: entry.downloadType || "songs", meta: entry.meta, label: entry.title }
    }
    function downloadEntries(entries, label, extra) {
        var list = entries.filter(function (e) { return e.meta && !e.path })
        if (!list.length) return
        startJob(list.map(sourceFor), label || (list.length === 1 ? list[0].title : list.length + " songs"),
                 extra || (list.length === 1 ? { art: list[0].artwork, sub: list[0].artist, auto: false } : {}))
    }
    function retryJob(jobId) {
        var i = jobIndex(jobId)
        if (i < 0) return
        var j = jobs.get(i)
        if (!j.sourcesJson) return
        startJob(JSON.parse(j.sourcesJson), j.label, { art: j.art, sub: j.sub, auto: false })
    }

    // ---- delete from computer ----
    function deleteEntries(entries) {
        var paths = entries.map(function (e) { return e.path }).filter(function (x) { return x })
        if (!paths.length) return
        dialogs.confirm(paths.length === 1 ? "Move \u201c" + entries[0].title + "\u201d to the Recycle Bin?" : "Move " + paths.length + " songs to the Recycle Bin?",
            "The files are removed from your music folder. You can restore them from the Recycle Bin.", "Move to Recycle Bin", function () {
                call("delete_files", [paths], function (r) {
                    var gone = {}
                    paths.forEach(function (x) { gone[x] = true })
                    for (var i = history.count - 1; i >= 0; i--) if (gone[history.get(i).path]) history.remove(i)
                    scanItems = scanItems.filter(function (t) { return !gone[t.path] })
                    recomputeAlbums()
                    if (collection && collection.kind === "local") {
                        var n = {}
                        for (var k in collection) n[k] = collection[k]
                        n.tracks = collection.tracks.filter(function (t) { return !gone[t.path] })
                        collection = n
                    }
                    if (r.ok) toast(r.moved === 1 ? "Moved to the Recycle Bin" : r.moved + " songs moved to the Recycle Bin", "ok", "check")
                    else toast(r.error, "bad", "alert")
                })
            })
    }

    // ---- right-click menu ----
    // spec: { entries: [entry], collection: {kind, meta, library, title, ...}, link, queueIndex }
    function showMenu(spec) { menuRequested(spec) }

    // ---- activity log & tools ----
    property ListModel logModel: ListModel {}
    property string toolOut: ""
    property bool toolRunning: false

    // ---- player ----
    property var player: null
    property var playQueue: []
    property int playIndex: -1
    property var current: null
    property bool loading: false
    property string playSource: ""
    property bool shuffle: false
    property int repeatMode: 0   // 0 off, 1 all, 2 one
    property int _loadToken: 0
    readonly property bool playing: player !== null && player.playbackState === 1
    // Volume is the system master volume when Windows allows it (else the app's own).
    readonly property bool sysVolume: !!Bridge && Bridge.systemVolumeAvailable
    readonly property real volume: sysVolume ? Bridge.systemVolume : prefs.volume
    readonly property bool muted: sysVolume ? Bridge.systemMuted : prefs.volume <= 0
    function setVolume(v) {
        v = Math.max(0, Math.min(1, v))
        if (Bridge.systemVolumeAvailable) Bridge.setSystemVolume(v); else prefs.volume = v
    }
    function toggleMute() {
        if (Bridge.systemVolumeAvailable) Bridge.setSystemMuted(!Bridge.systemMuted)
        else prefs.volume = prefs.volume > 0 ? 0 : 0.8
    }

    function playList(entries, start) {
        if (!entries || !entries.length) return
        playQueue = entries
        playIndex = Math.max(0, Math.min(start || 0, entries.length - 1))
        loadCurrent()
    }
    function loadCurrent() {
        var e = playQueue[playIndex]
        if (!e) return
        current = e; loading = true
        loadLyrics(e)
        rememberQueue()
        var token = ++_loadToken
        if (player) player.stop()
        var done = function (r) {
            if (token !== _loadToken) return
            loading = false
            if (!r.ok) {
                if (e.path) {   // the file was deleted or moved outside the app
                    toast("“" + e.title + "” isn't in your music folder anymore. It was moved or deleted.", "bad", "alert")
                    scanLibrary()
                } else toast(friendlyError(r.error), "bad", "alert")
                return
            }
            if (r.source === "preview" && r.note) toast("Playing a 30-second preview. " + friendlyError(r.note), "", "note")
            playSource = r.source || "local"
            player.source = r.url
            player.play()
            prefetchNext()
        }
        if (e.path) call("media_url", [e.path], done)
        else if (e.meta) { status = "Getting " + e.title + "…"; call("stream", [e.meta], function (r) { status = ""; done(r) }) }
    }
    // ---- Now Playing & lyrics ----
    property bool nowPlayingOpen: false
    property var lyricLines: []
    property bool lyricsSynced: false
    property bool lyricsLoading: false
    property string lyricsError: ""
    property int _lyricsToken: 0
    function loadLyrics(e) {
        var token = ++_lyricsToken
        lyricLines = []; lyricsSynced = false; lyricsError = ""; lyricsLoading = true
        call("lyrics", [{ path: e.path || "", meta: e.meta || null, title: e.title || "", artist: e.artist || "", album: e.album || "", duration: e.duration || 0 }], function (r) {
            if (token !== _lyricsToken) return
            lyricsLoading = false
            lyricLines = (r.lines || []).filter(function (l) { return l.text !== "" || l.t !== null })
            lyricsSynced = !!r.synced
            if (!r.ok) lyricsError = friendlyError(r.error)
        })
    }
    function lyricIndexAt(ms) {
        var lo = 0, hi = lyricLines.length - 1, ans = -1
        while (lo <= hi) {
            var mid = (lo + hi) >> 1
            if (lyricLines[mid].t !== null && lyricLines[mid].t <= ms) { ans = mid; lo = mid + 1 } else hi = mid - 1
        }
        return ans
    }
    function jumpTo(i) { if (i >= 0 && i < playQueue.length) { playIndex = i; loadCurrent() } }

    function prefetchNext() {
        prefetch(playQueue[playIndex + 1])
    }
    // Fetches a song into the stream cache ahead of time (once per song).
    property var _prefetched: ({})
    function prefetch(e) {
        var m = e && !e.path ? e.meta : null
        if (!m || !m.id || _prefetched[m.id] || !configured) return
        _prefetched[m.id] = true
        call("stream", [m])
    }
    function toggle() {
        if (!player || !current) { var h = historyEntries(); if (h.length) playList(h, 0); return }
        if (String(player.source) === "") { loadCurrent(); return }
        if (playing) player.pause(); else player.play()
    }
    function next(auto) {
        if (!playQueue.length) return
        if (auto && repeatMode === 2) { player.position = 0; player.play(); return }
        var i
        if (shuffle) i = Math.floor(Math.random() * playQueue.length)
        else i = playIndex + 1
        if (i >= playQueue.length) { if (repeatMode === 1 || !auto) i = 0; else { player.stop(); return } }
        playIndex = i; loadCurrent()
    }
    function prev() {
        if (!playQueue.length) return
        if (player && player.position > 3000) { player.position = 0; return }
        playIndex = Math.max(0, playIndex - 1); loadCurrent()
    }
    function isCurrent(entry) {
        if (!current || !entry) return false
        if (entry.path && current.path) return entry.path === current.path
        return current.title === entry.title && current.artist === entry.artist
    }

    // ---- engine events ----
    function stamp() { return Qt.formatTime(new Date(), "hh:mm:ss") }

    function handle(batch) {
        for (var b = 0; b < batch.length; b++) {
            var e = batch[b]
            try { _handle(e) } catch (err) { console.warn("event", e.type, err) }
        }
    }

    function _handle(e) {
        switch (e.type) {
        case "log":
            if (e.level === "debug" && !prefs.debugLog) return
            logModel.append({ level: e.level, msg: e.msg, time: stamp() })
            if (logModel.count > 600) logModel.remove(0, logModel.count - 600)
            return
        case "status": status = e.text === "Ready" ? "" : e.text; return
        case "session": sessionOk = e.ok; sessionDesc = e.desc; return
        case "account_profile": accountProfile = e.profile || ({}); return
        case "job_started": addJob(e.job, "Download"); return
        case "job_finished": {
            var ji = jobIndex(e.job)
            if (ji < 0) return
            var m = _jobItems[e.job]
            for (var k = 0; k < m.count; k++) if (!m.get(k).status) m.setProperty(k, "status", "cancelled")
            var sum = e.summary, failed = (sum.failed || 0) + (sum.partial || 0)
            jobs.setProperty(ji, "done", true)
            jobs.setProperty(ji, "failed", failed > 0)
            jobs.setProperty(ji, "summary", summaryText(sum))
            var label = jobs.get(ji).label
            if (failed && !sum.found) toast(label + ": couldn't download. Open Activity for details.", "bad", "alert")
            else if (sum.found) toast(label + ": " + summaryText(sum), failed ? "bad" : "ok", failed ? "alert" : "check")
            recount()
            if (activeCount === 0) { jobsFinished(); scanLibrary() }
            return
        }
        case "item_added": {
            if (jobIndex(e.job) < 0) addJob(e.job, "Download")
            var model = _jobItems[e.job], info = e.info
            model.append({ key: e.job + "-" + e.item, title: info.title || "", artist: info.artist || "", album: info.album || "",
                           artwork: info.artwork || "", kind: info.kind || "Song", explicit: !!info.explicit, duration: info.duration || 0,
                           stage: "Waiting", pct: -1, detail: "", status: "", message: "", path: "" })
            _itemLoc[e.job + "-" + e.item] = { job: e.job, index: model.count - 1 }
            var idx = jobIndex(e.job), job = jobs.get(idx)
            if (job.auto) {
                var albumsSeen = {}, artistsSeen = {}, na = 0, nr = 0
                for (var x = 0; x < model.count; x++) {
                    var it = model.get(x)
                    var a = it.album || it.title
                    if (!albumsSeen[a]) { albumsSeen[a] = 1; na++ }
                    if (!artistsSeen[it.artist]) { artistsSeen[it.artist] = 1; nr++ }
                }
                jobs.setProperty(idx, "label", na === 1 ? (info.album || info.title) : job.slug)
                jobs.setProperty(idx, "sub", nr === 1 ? info.artist : "Various artists")
            }
            if (!jobs.get(idx).art) jobs.setProperty(idx, "art", info.artwork || "")
            recount()
            return
        }
        case "item_event": {
            var r = itemByKey(e.job + "-" + e.item)
            if (!r) return
            r.model.setProperty(r.index, "stage", e.stage)
            r.model.setProperty(r.index, "detail", (e.detail || "").replace(/^audio\s+/, ""))
            if (e.pct >= 0) r.model.setProperty(r.index, "pct", e.pct)
            else if (e.stage !== "Downloading") r.model.setProperty(r.index, "pct", -1)
            if (e.stage === "Downloading" && focusKey !== e.job + "-" + e.item) { focusKey = e.job + "-" + e.item; updateFocus() }
            return
        }
        case "item_finished": {
            var f = itemByKey(e.job + "-" + e.item)
            if (!f) return
            f.model.setProperty(f.index, "status", e.status)
            f.model.setProperty(f.index, "message", friendlyError(e.message))
            f.model.setProperty(f.index, "path", e.path || "")
            f.model.setProperty(f.index, "pct", 100)
            recount()
            return
        }
        case "history":
            history.insert(0, histRow(e.entry)); recomputeAlbums(); return
        case "prompt":
            promptQueue.push(e); promptArrived(); return
        case "signin_finish":
            signinNeedsToken(); return
        case "apple_signin":
            appleSigninFinished(e.ok, e.error || ""); return
        case "search": {
            if (e.token !== searchToken) return
            for (var s = 0; s < e.items.length; s++) {
                var it2 = e.items[s]
                results.append({ name: it2.name, artist: it2.artist, album: it2.album, artwork: it2.artwork, explicit: !!it2.explicit,
                                 duration: it2.duration || 0, details: it2.details || "", metaJson: JSON.stringify(it2.meta) })
            }
            searchMore = e.more; searchLoading = false
            return
        }
        case "library_chunk": {
            var current = e.reset ? [] : libItems[e.kind]
            libItems[e.kind] = current.concat(e.items)
            libVersion++
            return
        }
        case "library_error":
            libError = friendlyError(e.error); return
        case "tool_output":
            toolOut = (toolOut + e.text).slice(-200000); return
        case "tool_done":
            toolOut += "\n" + (e.code === 0 ? "Finished." : "Stopped with exit code " + e.code + ".") + "\n\n"
            toolRunning = false
            return
        }
    }

    property var promptQueue: []

    // ---- text helpers ----
    function summaryText(sum) {
        if (!sum) return "Finished"
        var p = [], n = function (k) { return sum[k] || 0 }
        if (n("downloaded")) p.push(n("downloaded") + " downloaded")
        if (n("overwritten")) p.push(n("overwritten") + " replaced")
        if (n("skipped")) p.push(n("skipped") + " skipped")
        if (n("partial")) p.push(n("partial") + " with errors")
        if (n("failed")) p.push(n("failed") + " failed")
        if (n("cancelled")) p.push("stopped")
        return p.join(" · ") || (sum.found ? "Finished" : "Nothing found at this link")
    }
    function statusText(s) {
        return ({ downloaded: "Downloaded", overwritten: "Replaced", skipped: "Skipped", failed: "Failed",
                  partial: "Saved with errors", cancelled: "Stopped" })[s] || s
    }
    function friendlyError(msg) {
        if (!msg) return ""
        msg = String(msg).replace(/gamdl/gi, Theme.appName)
        if (/uploaded song has no single direct asset/i.test(msg)) return "This is a song you uploaded to your library. Apple doesn't stream uploaded songs, so it can't play here."
        if (/no usable tag metadata/i.test(msg)) return "Apple Music didn't return playback data. Check that you're signed in with an active subscription."
        if (/rejected|401|403|unauthori[sz]ed/i.test(msg)) return "Apple Music rejected the sign-in. Sign in with your Apple ID again."
        if (/cookies file not found/i.test(msg)) return msg.replace("Cookies file not found:", "Couldn't find the cookies file at") + ". Sign in again in Settings."
        return msg
    }
    function linkLabel(text) {
        var links = text.split(/\s+/).filter(function (x) { return x })
        if (links.length > 1) return links.length + " links"
        var m = (links[0] || "").match(/music\.apple\.com\/\w+\/(album|playlist|artist|song|music-video|post)\/([^\/?#]+)/i)
        if (m) return decodeURIComponent(m[2]).replace(/-/g, " ").replace(/\b\w/g, function (c) { return c.toUpperCase() })
        return links[0] || "Download"
    }
    function fmtDur(ms) {
        if (!ms || ms < 0) return "0:00"
        var s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }
    // Account label shown in the sidebar and Settings (never the OS user name).
    readonly property string accountTitle: sessionOk ? (accountProfile.name || "Apple Music account") : connecting ? "Checking Apple Music session…" : appState.auth ? (sessionDesc === "Saved Apple ID could not be verified" ? "Apple Music session unavailable" : "Apple Music sign-in saved") : "Not signed in"
    readonly property string accountDetail: {
        if (sessionOk) {
            var m = sessionDesc.match(/storefront (\w+)/)
            return "Account verified" + (m ? " · " + m[1].toUpperCase() + " store" : "")
        }
        if (connecting) return "Checking the saved sign-in…"
        if (appState.auth) return sessionDesc === "Saved Apple ID could not be verified"
            ? "The saved sign-in could not be verified. The app will retry automatically."
            : "A saved Apple Music sign-in is available on this device."
        return "Sign in with your Apple ID"
    }
    readonly property var methodLabel: ({ "cookies": "Apple ID", "media-user-token": "Media User Token", "wrapper": "Wrapper" })
}
