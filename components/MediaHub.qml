// =====================================================================
//  MediaHub.qml — GPS Media Hub
//  One self-contained QtQuick component. Qt 6 / Quickshell friendly.
//  Imports: QtQuick, QtQuick.Controls, QtQuick.Layouts, QtQuick.Shapes
//
//  PRESENT  : navigation, selection, favorites, persistent watchlist /
//             reading-list status and progress; Wallhaven search plus
//             download/cache/apply and optional GPS theme sync; live AniList
//             anime/manga catalogue; Jamendo and Radio Browser music search
//             with a real Qt Multimedia player.
//  FUTURE   : media launching, yt-dlp / FFmpeg downloads, optional anime
//             hand-off and local library scanning. Remaining mock boundaries
//             are marked with "// >>> BACKEND:" comments.
// =====================================================================
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtMultimedia
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.config
import "MusicQueue.js" as MusicQueue
import "MediaCatalogue.js" as MediaCatalogue

Item {
    id: root
    implicitWidth: 1280
    implicitHeight: 800
    clip: true

    // ================================================================
    //  PUBLIC API
    // ================================================================
    // >>> BACKEND: connect these from the host (e.g. in shell.qml).
    signal wallpaperApplyRequested(var wallpaper, bool syncTheme)
    signal themeSyncRequested(string moodId)
    signal downloadRequested(var request)
    signal openMediaRequested(var item)
    signal openLocationRequested(string path)
    signal sourceLinkRequested(string url)
    // Emitted by the optional host close button; standalone use can ignore it.
    signal closeRequested()

    property bool wallhavenConnected: false
    property bool wallhavenUsingRemote: false
    // Wallhaven, AniList and Radio Browser are live public catalogues. Local
    // files and download execution remain future backend work.
    readonly property bool backendConnected: true
    readonly property bool downloadBackendConnected: false
    // Hosted mode: show the close button wired to closeRequested().
    property bool showCloseButton: false
    // Set false to skip loading remote artwork (gradient fallbacks are used instead).
    property bool loadRemoteArt: true
    property bool toolsStatusReady: false
    property var toolStatus: ({})
    property string toolsError: ""
    // 0 Home · 1 Wallpapers · 2 Anime · 3 Manga & Manhwa · 4 Music · 5 Downloads · 6 My Library
    property int page: 0

    readonly property bool compact: width < 1000
    readonly property int sidebarW: compact ? 68 : 208

    // ================================================================
    //  STATE (catalogue lists, music favorites/queue and mood are persisted)
    // ================================================================
    property string moodId: "system"
    readonly property var mood: findIn(moods, moodId) || moods[0]
    property color accent: mood ? mood.accent : Theme.brandAccent
    Behavior on accent { ColorAnimation { duration: 300 } }

    property var favorites: ({ wp1: true, wp3: true })
    property var statuses: ({})
    property var progress: ({})
    property var openedAt: ({})
    property var activity: []
    property var surprisePick: null
    property string featuredId: "wp0"

    // wallpapers page
    property string wpQuery: ""
    property string wpCategory: "All"
    property string wpColor: "Any"
    property string wpRes: "Any"
    property string wpAspect: "Any"
    property string wpSort: "Relevance"
    property string wpTag: ""
    readonly property bool sfwOnly: true
    property int wpVisible: 6
    property string wpSelectedId: ""
    property string wpShownId: ""
    property var randomRank: ({})

    // Wallhaven catalogue state. Until a search succeeds, the bundled sample
    // set remains visible and is labelled as such.
    property var wallhavenWallpapers: []
    property bool wallhavenLoaded: false
    property string wallhavenError: ""
    property string wallhavenErrorCode: ""
    property int wallhavenPage: 0
    property int wallhavenLastPage: 0
    property string wallhavenSeed: ""
    property int wallhavenSearchSeq: 0
    property int wallhavenApplySeq: 0
    readonly property bool wallhavenLoading: wallhavenBackend.searching
    readonly property bool wallhavenApplying: wallhavenBackend.applying
    onWpSelectedIdChanged: if (wpSelectedId !== "") wpShownId = wpSelectedId

    Timer {
        id: wallhavenSearchTimer
        interval: 450
        repeat: false
        onTriggered: root.runWallhavenSearch(false)
    }

    Timer {
        interval: 500
        repeat: true
        running: root.nowPlaying !== null && root.nowPlaying.id.indexOf("local:") === 0
        onTriggered: localPlayerStateWriter.save()
    }

    onPageChanged: {
        if (page === 1 && !wallhavenLoaded && !wallhavenLoading)
            wallhavenSearchTimer.restart()
        if (page === pgMusic) {
            if (musicSource === "local") {
                if (!localLoaded && !localLoading) reloadLocalLibrary()
            } else {
                scheduleMusicSearch()
            }
        }
    }
    onWpQueryChanged: { wpVisible = 6; scheduleWallhavenSearch() }
    onWpCategoryChanged: { wpVisible = 6; scheduleWallhavenSearch() }
    onWpColorChanged: { wpVisible = 6; scheduleWallhavenSearch() }
    onWpResChanged: { wpVisible = 6; scheduleWallhavenSearch() }
    onWpAspectChanged: { wpVisible = 6; scheduleWallhavenSearch() }
    onWpSortChanged: { wpVisible = 6; scheduleWallhavenSearch() }

    // overlays
    property string detailKind: ""
    property string detailId: ""
    property var detailShown: null
    readonly property var detailItem: detailKind === "anime" ? animeCatalogue.findMedia(detailId)
                                    : (detailKind === "manga" ? mangaCatalogue.findMedia(detailId) : null)
    onDetailItemChanged: if (detailItem) detailShown = detailItem
    property bool vibeOpen: false
    property string gq: ""
    property string pendingUrl: ""

    // toast
    property string toastText: ""
    property string toastKind: "info"
    property bool toastShown: false
    Timer { id: toastTimer; interval: 3600; onTriggered: root.toastShown = false }

    MediaHubWallhaven {
        id: wallhavenBackend
        onSearchSucceeded: (payload, request) => root.handleWallhavenSearch(payload, request)
        onSearchFailed: (message, code, request) => root.handleWallhavenFailure(message, code, request)
        onApplySucceeded: (payload, request) => root.handleWallhavenApplied(payload, request)
        onApplyFailed: (message, code, request) => root.handleWallhavenApplyFailure(message, code, request)
        onThemeSyncFinished: (ok, message) => root.handleWallhavenThemeSync(ok, message)
    }

    MediaHubMusic {
        id: musicBackend
        onStatusFinished: (configured, configPath, message) => root.handleMusicStatus(configured, configPath, message)
        onSearchSucceeded: (payload, request) => root.handleMusicSearch(payload, request)
        onSearchFailed: (message, code, request) => root.handleMusicSearchFailure(message, code, request)
    }
    MediaHubTools {
        id: toolsBackend
        onStatusFinished: (status) => {
            root.toolsStatusReady = status !== null
            root.toolStatus = status || ({})
            root.toolsError = status === null ? toolsBackend.error : ""
        }
        onCommandReady: (payload, action) => root.handleToolCommand(payload, action)
        onCommandFailed: (message, code, action) => root.handleToolFailure(message, code, action)
    }

    Component.onCompleted: {
        musicBackend.checkStatus()
        toolsBackend.checkStatus()
        MediaNowPlaying.localPlayer = hubPlayerAdapter
    }

    // ================================================================
    //  ANILIST CATALOGUES + PERSISTED MEDIA LIBRARY
    // ================================================================
    property bool mediaStateReady: false
    property var mediaLibrary: []
    readonly property string mediaStatePath: {
        var cfg = Quickshell.env("XDG_CONFIG_HOME")
        if (!cfg) cfg = Quickshell.env("HOME") + "/.config"
        return cfg + "/quickshell/media-hub-library.json"
    }
    readonly property string mediaSaveKey: JSON.stringify(mediaLibrary)
    onMediaSaveKeyChanged: if (mediaStateReady) mediaSaveTimer.restart()

    Timer {
        id: mediaSaveTimer
        interval: 500
        repeat: false
        onTriggered: root.saveMediaLibrary()
    }
    Component.onDestruction: {
        mediaSaveTimer.stop()
        if (mediaStateReady) saveMediaLibrary()
        if (MediaNowPlaying.localPlayer === hubPlayerAdapter)
            MediaNowPlaying.localPlayer = null
    }

    QtObject {
        id: localPlayerStateWriter
        function save() {
            var item = root.nowPlaying
            if (!item || typeof item.id !== "string" || item.id.indexOf("local:") !== 0) {
                localPlayerStateFile.setText('{"active":false}')
                return
            }
            localPlayerStateFile.setText(JSON.stringify({
                active: true,
                id: item.id,
                title: item.title,
                artist: item.artist,
                album: item.album,
                art: item.art,
                playing: root.playing,
                position: root.playPos,
                length: root.currentDuration,
                canPrevious: root.queue.length > 1
                    && (root.queueIndex > 0 || root.repeatOn || root.shuffleOn),
                canNext: root.queue.length > 1
                    && (root.queueIndex < root.queue.length - 1 || root.repeatOn || root.shuffleOn),
                updatedAt: Date.now()
            }))
        }
    }

    FileView {
        id: mediaLibraryFile
        path: root.mediaStatePath
        printErrors: false
        onLoaded: {
            var state = MediaCatalogue.parseState(mediaLibraryFile.text())
            if (state) {
                root.applyMediaLibrary(state.entries)
            } else {
                var raw = mediaLibraryFile.text()
                mediaLibraryBackup.path = root.mediaStatePath.replace(/\.json$/, ".corrupt-" + Date.now() + ".json")
                mediaLibraryBackup.setText(raw)
                root.mediaLibrary = []
                root.notify("Media library state was unreadable. A backup was kept and the list was reset.", "warn")
            }
            root.mediaStateReady = true
            if (!state) mediaSaveTimer.start()
        }
        onLoadFailed: root.mediaStateReady = true
    }

    FileView {
        id: mediaLibraryBackup
        printErrors: false
    }

    MediaHubCatalogue {
        id: animeCatalogue
        kind: "anime"
        savedEntries: root.mediaLibrary
    }
    MediaHubCatalogue {
        id: mangaCatalogue
        kind: "manga"
        savedEntries: root.mediaLibrary
    }
    readonly property alias animeModel: animeCatalogue
    readonly property alias mangaModel: mangaCatalogue

    // ================================================================
    //  SAMPLE DATA
    // ================================================================
    // Stitch artwork (remote). Any failure falls back to the gradient + glyph.
    // >>> BACKEND: replace with Wallhaven thumbnails / local cache paths.
    readonly property string artBase: ""
    readonly property var artIds: ({
        hero: "AB6AXuBFNmDHNGkY69HacDDeP4jD9L57JQ0i88karW2a4r2qMOh6ofHR9xKPYc1enF0R3Si51aZnEVaciwvnGtqFseMSWG5bLkJGloDggaGhWSxUwgS63V2xPwCpT_lFEw9p_dTcm49Zu3PsyQpiyEOVClqDzvlag823aSw8qd3zHzhH_IyidJITRgvm5Ml1qOp0-Pdj0Kt5GvEFxCOrcNEOMkw-BxRHqEcbXj5fsp1qXTs",
        anime1: "AB6AXuAWVwdToEd5uMivBa8MeqJ8zeWUNjpl6ity0e6VDq32HRn-KyV8zop7b2FJyoUz0RhZNi3d1iEcJX0m9rK9KeHunnu09wN5ujdZn1xBWalBZzRwWuhUG18OBlCKm5NBEtiBhp5G-s6uHzDetEfZH229_0ZXPxtuTH9pqz16Ra5mIPX3I7laRYR-OD4lJaqRG8055n7siE-Ifm73_bZrgUlyHEpiiTt9RjlHQ9T5li4",
        anime2: "AB6AXuClmixBId7QoEbBCwXbdFRtIFjdbUMceHHiRK7zE03ZAh29sArmUuZFXnTiKPkAW-yFj9M-TN6Zo4Ec1kBTaw4CvnwHJ6GXD07znVPxZm8paPEbBM_A_glj9TDjav7UOp9HSh5cYxyUQcmhp0on2tPH8db4Q-eFbFp35wPHVlQNg62nbw4bSnp62wP4yTtQH_P3i04L1B1HWZKpSUBaQqguuPGG8NnQZ1TXERtXUW8",
        manga1: "AB6AXuCsBcQkQT_KX3KgvfoKQvf16NevhsdyV2iOBMtnyft-h58rE4Xe8zmQAwEL0N-eRoMj30YpBoiHcuCTeWcemEo_lzqRnPeMIE62RBETEVsOYL7mW9pbj2fIrnGYCl8_e-nYVfXcRjAXzXXWTwgahOiAVIi7_k7ZMpzujf_uWC98RdthYJwhyy2Hi1BSqUtTgL_mwmSSWlhC-WDGf7O-HRp-U4HXN8Tfr9MhqLC-DwI",
        wp1: "AB6AXuD9smgvboZsJ0Jq-TdJ2Nw0Z1XCQpgIgmL89Q0-LhUdeov7geZKgK1ilJmu7Z4i_cO1yNjoIZHCYSXm0Y8QGgB0F-TwVxp4_rZVPdp32YM-ZLDwLt8TBgYXGUHwAz1M8XlisdoV8Ql99Ox4relGQU_BX-1aIG6gVZEdHUnH-mSjPsFL7Qzk6G7JAkcxUXJuLPwLws9oJA7msStH_fZrZcVM1f6zjdWrZqZQ0LLkuBE",
        wp2: "AB6AXuBgm-Ugckfysb_pNoRbsuNO5LlDysqV10qDU1Wh_tuTLKt8eibv4lDR0IeBLrpXPS9PCX5KtXJ8ihcbbWnbuUo7_bhW_aeV-uiLAELta2dluuX0H_hPzsQWuHIETazP67WcjMPSQnV2twJrgQCcaAhChVaYOVNbjbSk0Gzxst_0GPG2Poc5lRZPU76p4RNOXx1W97GyTH2Jx7RqB0Su0GyQc9DZ2hst-8zfy78YbHg",
        wp3: "AB6AXuD-y92-OlzXM2bpmlL9dtt0lHDGiXOmnC1yAPPEokcxxUrU7IkFXy79totTCHeFNuoQBr5UoHV13s2QWNo81aNflkIBiTq_o8fZ-cqlQcAN3Tjl43kMLK2dPzRMNa2ILACC6bQ_GemF7CA1Ox3Xhz81i6Sb1eVE0xUp7-i17_l6lYryoReVfRcsefqdykP9BM9KmXwk-9_pTwWtyhK_eHOTgHZmr0R8_N4184zLUPA",
        wp4: "AB6AXuCwaBq86RHSAw0rMzkVdwGcQBWGcHa_1ZnnKrdPvDmf9I7cb9tWjjZ_xsfciIxE0XMPFy2ljW-mOepKK2bUTOfVrYeL6m6PQYsBjzepYUtFmKVw2d6zkPrzOrb-VeBmJ8Ext-2FeXHz8htg-nDsL4fft3_rk95w6J50-xKlVDQF0nrSaPMNeA1b2DX1uwl7J2VnMDKMUNv4XY_c03DLHHkAOTIWC2BwHkdi6iicGlM",
        wp5: "AB6AXuBeRkX3zgWs5m453JkI9GX2IoF0OIZ5qR0uQg-V1Y0jjLBpFUoKFJdZzk2kjpE4IiyWr2UGXMyZPStzQgeq76Ba-rd1bQnEq_CMZiSAVmxc1-JHskail5JgFcFdw4MR0aTmBo7gLvjTGa8sK5MA3nMN_IITwecqZW1cDQpKWACUPWcTInEtcJsbzc-dKdDpY_djsgKKHbs4UuGQSrU7aK5hbiSGI2s5oP29yGIRxf4",
        wp6: "AB6AXuD8EqovB2EdtUnxaYmJeegspzDVtRj27l0CAaErYiBrIzPfW6fGud7DwzMqxGZGmWSANmkJysp1xOYWV3VpRBGKdA4XxXzB7MuxMkiZrMuMt9xXL-RXPflLDosVdd0KlNNFGzmmu7d6-tX_D7mhadfr09oP_34rkVKWoKkOgv4zXSGQBbIIf8JIq664MeZ7ehJhbqI0Tmcdp8DnAxJTK41ITnGuRtBR8cKz-R7Eko"
    })
    function artUrl(id) {
        if (!loadRemoteArt || !id) return ""
        if (typeof id === "string" && /^(https:\/\/|file:\/\/)/.test(id)) return id
        if (artBase !== "") return artBase + id
        return ""
    }

    readonly property var gradients: ({
        violet: ["#0b1030", "#2a1b5e", "#0e4a6b"],
        rose:   ["#2a1236", "#6b2c5f", "#f59e8b"],
        slate:  ["#0b0f17", "#1f2937", "#475569"],
        cosmic: ["#05070d", "#1b1060", "#7bd0ff"],
        amber:  ["#1a1208", "#5a3a14", "#fbbf24"],
        green:  ["#06150f", "#0f4a3a", "#7bd0ff"],
        red:    ["#12060a", "#4a1218", "#f97316"],
        teal:   ["#071a1f", "#0e4a5b", "#a78bfa"]
    })

    readonly property var moods: [
        { id: "system", name: "System Theme", desc: "Dynamic desktop wallpaper palette with live theme sync.",
          accent: Theme.brandAccent, palette: [Theme.surfaceDeep, Theme.track, Theme.surfaceBase, Theme.brandAccent], grad: ["#0b1030", "#2a1b5e", "#0e4a6b"], art: "", cat: "All" },
        { id: "midnight", name: "Midnight City", desc: "Neon, rainy streets in deep blue and violet.",
          accent: "#a78bfa", palette: ["#0f172a", "#38bdf8", "#818cf8", "#c084fc"], grad: gradients.violet, art: artIds.wp1, cat: "Cyberpunk" },
        { id: "soft", name: "Soft Escape", desc: "Pastel colours, peaceful scenery and warm light.",
          accent: "#f9a8d4", palette: ["#1e1b4b", "#fbcfe8", "#ddb8ff", "#fdba74"], grad: gradients.rose, art: artIds.wp2, cat: "Nature" },
        { id: "focus", name: "Focus Mode", desc: "Minimal visuals, dark colours and very little clutter.",
          accent: "#b6c4d9", palette: ["#0b0f17", "#1f2937", "#64748b", "#cbd5e1"], grad: gradients.slate, art: "", cat: "Minimal" },
        { id: "cosmic", name: "Cosmic Drift", desc: "Galaxies, stars, deep space and luminous gradients.",
          accent: "#7bd0ff", palette: ["#080e19", "#7bd0ff", "#be82f9", "#fde68a"], grad: gradients.cosmic, art: artIds.wp3, cat: "Dark" }
    ]

    readonly property var sampleWallpapers: [
        { id: "wp0", title: "Cybernetic Shinjuku Rain", author: "gps_curated", w: 1920, h: 1200, ratio: "16:10", size: "4.2 MB PNG",
          tags: ["cyberpunk", "rain", "night drive"], cats: ["Cyberpunk", "Dark", "Anime"], fam: ["Violet", "Cyan"],
          pal: ["#0f172a", "#38bdf8", "#818cf8", "#c084fc", "#1e1b4b"], likes: 5320, added: 9, art: artIds.hero, g: gradients.violet,
          desc: "Reflective puddle caustics, soft neon diffusion and a deep violet night palette." },
        { id: "wp1", title: "Tokyo Neon Rain: Shibuya 2099", author: "aetheric_rice", w: 1920, h: 1200, ratio: "16:10", size: "3.8 MB PNG",
          tags: ["cyberpunk", "tokyo", "night", "rain", "neon"], cats: ["Cyberpunk", "Dark"], fam: ["Violet", "Cyan"],
          pal: ["#0f172a", "#38bdf8", "#818cf8", "#c084fc", "#1e1b4b"], likes: 4821, added: 8, art: artIds.wp1, g: gradients.violet,
          desc: "High-contrast night cityscape with luminous accents that sit well behind bars, docks and translucent widgets." },
        { id: "wp2", title: "Minimalist Sakura Twilight", author: "kaito_minimal", w: 2560, h: 1600, ratio: "16:10", size: "4.2 MB PNG",
          tags: ["sakura", "fuji", "twilight", "minimal"], cats: ["Minimal", "Landscape", "Nature"], fam: ["Violet", "Rose"],
          pal: ["#1e1b4b", "#ddb8ff", "#fbcfe8"], likes: 3902, added: 7, art: artIds.wp2, g: gradients.rose,
          desc: "A calm silhouette of Mt. Fuji under a pastel violet and peach dusk." },
        { id: "wp3", title: "Carina Nebula Resonance", author: "astrophile_x", w: 3840, h: 2400, ratio: "16:10", size: "7.1 MB PNG",
          tags: ["space", "nebula", "galaxy", "stars"], cats: ["Dark", "Nature"], fam: ["Cyan", "Violet"],
          pal: ["#080e19", "#7bd0ff", "#be82f9"], likes: 6104, added: 6, art: artIds.wp3, g: gradients.cosmic,
          desc: "Iridescent nebula clouds and star clusters against a deep OLED-friendly void." },
        { id: "wp4", title: "Rainy Cafe Window Overlook", author: "lofi_drifter", w: 1920, h: 1200, ratio: "16:10", size: "3.2 MB WebP",
          tags: ["lofi", "cafe", "rain", "cozy"], cats: ["Anime"], fam: ["Amber"],
          pal: ["#1a202b", "#fde047", "#64748b"], likes: 2877, added: 5, art: artIds.wp4, g: gradients.amber,
          desc: "Warm amber interior light, a rain-streaked window and a quiet street outside." },
        { id: "wp5", title: "Lofoten Aurora Borealis", author: "nord_echoes", w: 2560, h: 1600, ratio: "16:10", size: "5.4 MB PNG",
          tags: ["aurora", "nordic", "fjord", "snow"], cats: ["Nature", "Landscape"], fam: ["Green", "Cyan"],
          pal: ["#0d131e", "#4ade80", "#7bd0ff"], likes: 4410, added: 4, art: artIds.wp5, g: gradients.green,
          desc: "Green and violet aurora over a glassy Arctic fjord." },
        { id: "wp6", title: "Project 09 // Orbital Armor", author: "cyber_forge", w: 1920, h: 1200, ratio: "16:10", size: "4.9 MB WebP",
          tags: ["mecha", "scifi", "hangar"], cats: ["Anime", "Cyberpunk", "Dark"], fam: ["Red", "Amber"],
          pal: ["#080e19", "#f97316", "#ef4444"], likes: 3350, added: 3, art: artIds.wp6, g: gradients.red,
          desc: "A biomechanical armoured silhouette in a dim underground hangar." },
        { id: "wp7", title: "Quiet Ridge // Monochrome", author: "slate_field", w: 2560, h: 1440, ratio: "16:9", size: "2.1 MB PNG",
          tags: ["minimal", "mountains", "mono"], cats: ["Minimal", "Landscape", "Dark"], fam: ["Slate"],
          pal: ["#0b0f17", "#334155", "#94a3b8"], likes: 1980, added: 2, art: "", g: gradients.slate,
          desc: "Layered grey ridgelines — about as low-clutter as a wallpaper gets." },
        { id: "wp8", title: "Ultrawide Violet Dunes", author: "dune_atlas", w: 3440, h: 1440, ratio: "21:9", size: "6.0 MB PNG",
          tags: ["dunes", "violet", "ultrawide"], cats: ["Landscape", "Nature"], fam: ["Violet", "Rose"],
          pal: ["#1e1b4b", "#a78bfa", "#f9a8d4"], likes: 2240, added: 1, art: "", g: gradients.teal,
          desc: "Soft violet dunes in an ultrawide frame." }
    ].map(function (w) { return Object.assign({ kind: "wallpaper", res: w.w + "\u00d7" + w.h }, w) })

    // The wallpaper browser never mixes sample records with live results.
    readonly property var wallpapers: root.wallhavenUsingRemote ? root.wallhavenWallpapers : root.sampleWallpapers

    // Ordinary categories map directly to Wallhaven. The descriptive chips
    // map to a tag phrase inside Wallhaven's general category.
    readonly property var wpCategories: ["All", "Anime", "Nature", "Minimal", "Cyberpunk", "Dark", "Landscape", "General", "People"]
    readonly property var wpSorts: ["Relevance", "Popular", "Latest", "Random"]
    readonly property var wpColors: ["Any", "Violet", "Cyan", "Amber", "Green", "Red", "Rose", "Slate"]
    readonly property var wpResolutions: ["Any", "1920+", "2560+", "4K+"]
    readonly property var wpAspects: ["Any", "16:10", "16:9", "21:9"]
    readonly property var resMin: ({ "Any": 0, "1920+": 1920, "2560+": 2560, "4K+": 3840 })
    readonly property var colorDots: ({ Violet: "#a78bfa", Cyan: "#7bd0ff", Amber: "#fbbf24", Green: "#4ade80", Red: "#ef4444", Rose: "#f9a8d4", Slate: "#94a3b8" })

    readonly property var animeStatuses: MediaCatalogue.statusOptions("anime")
    readonly property var mangaStatuses: MediaCatalogue.statusOptions("manga")

    // Remote AniList results are transient. Persisted entries live in
    // mediaLibrary and are exposed separately for the library/continue views.
    readonly property var animeList: animeCatalogue.entries
    readonly property var mangaList: mangaCatalogue.entries

    readonly property var mediaList: [
        { id: "lv1", kind: "video", title: "Neon Rain Timelapse.mp4", meta: "4:12 \u00b7 1.2 GB \u00b7 MP4", art: artIds.wp1, g: gradients.violet, added: 30 },
        { id: "lv2", kind: "video", title: "Kyoto Walk 4K.mkv", meta: "18:40 \u00b7 3.4 GB \u00b7 MKV", art: artIds.wp2, g: gradients.rose, added: 29 },
        { id: "lv3", kind: "video", title: "Orbital Armor Teaser.webm", meta: "1:05 \u00b7 88 MB \u00b7 WebM", art: artIds.wp6, g: gradients.red, added: 28 },
        { id: "lv4", kind: "video", title: "Lofi Study Session.mp4", meta: "52:10 \u00b7 1.9 GB \u00b7 MP4", art: artIds.wp4, g: gradients.amber, added: 27 },
        { id: "au1", kind: "audio", title: "Midnight City Mix.flac", meta: "58:20 \u00b7 410 MB \u00b7 FLAC", art: "", g: gradients.violet, added: 26 },
        { id: "au2", kind: "audio", title: "Rainfall Over Kabukicho.mp3", meta: "3:48 \u00b7 9 MB \u00b7 MP3", art: "", g: gradients.teal, added: 25 },
        { id: "au3", kind: "audio", title: "Orbital Radio Ambient.opus", meta: "1:12:00 \u00b7 62 MB \u00b7 Opus", art: "", g: gradients.cosmic, added: 24 },
        { id: "au4", kind: "audio", title: "Soft Escape Piano.m4a", meta: "4:21 \u00b7 11 MB \u00b7 M4A", art: "", g: gradients.rose, added: 23 }
    ]

    // Download queue — SAMPLE RECORDS. Progress never advances on its own.
    property int dlSeq: 100
    property var downloads: [
        { id: "d1", name: "Aether Chronicles S01E14 [1080p].mp4", type: "video", format: "MP4", quality: "1080p", dest: "~/Videos/GPS", status: "downloading", progress: 0.62, size: "412 / 664 MB", error: "" },
        { id: "d2", name: "Neon Requiem OST - Full Album.flac", type: "audio", format: "FLAC", quality: "Best", dest: "~/Music/GPS", status: "downloading", progress: 0.18, size: "96 / 530 MB", error: "" },
        { id: "d3", name: "Starlit Cartography PV [720p].webm", type: "video", format: "WebM", quality: "720p", dest: "~/Videos/GPS", status: "queued", progress: 0, size: "~48 MB est.", error: "" },
        { id: "d4", name: "Rainy Cafe Lofi Mix.mp3", type: "audio", format: "MP3", quality: "320k", dest: "~/Music/GPS", status: "completed", progress: 1, size: "112 MB", error: "" },
        { id: "d5", name: "Kinetic Garden Ep 02 [1080p].mkv", type: "video", format: "MKV", quality: "1080p", dest: "~/Videos/GPS", status: "completed", progress: 1, size: "1.1 GB", error: "" },
        { id: "d6", name: "Hollow Meridian Ep 07 [1080p].mp4", type: "video", format: "MP4", quality: "1080p", dest: "~/Videos/GPS", status: "failed", progress: 0.34, size: "\u2014", error: "HTTP 403 \u2014 the source refused the request (sample error)" }
    ]

    // ================================================================
    //  HELPERS & ACTIONS
    // ================================================================
    function findIn(list, id) {
        if (!list) return null
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    function isCatalogueId(id) { return /^(anime|manga)-[0-9]+$/.test(String(id || "")) }
    function catalogueKind(id) {
        if (String(id).indexOf("anime-") === 0) return "anime"
        if (String(id).indexOf("manga-") === 0) return "manga"
        return ""
    }
    function findCatalogueMedia(id) {
        var saved = findIn(mediaLibrary, id)
        if (saved) return saved
        if (detailShown && detailShown.id === id) return detailShown
        return catalogueKind(id) === "anime" ? animeCatalogue.findMedia(id) : mangaCatalogue.findMedia(id)
    }
    function syncMediaMaps() {
        var st = {}, pr = {}, op = {}
        for (var k in openedAt)
            if (!isCatalogueId(k)) op[k] = openedAt[k]
        for (var i = 0; i < mediaLibrary.length; i++) {
            var item = mediaLibrary[i]
            if (!item) continue
            if (item.userStatus) st[item.id] = item.userStatus
            if (item.progress > 0) pr[item.id] = item.progress
            if (item.openedAt > 0) op[item.id] = item.openedAt
        }
        statuses = st
        progress = pr
        openedAt = op
    }
    function applyMediaLibrary(entries) {
        var state = MediaCatalogue.normalizeState({ version: 1, entries: entries || [] })
        mediaLibrary = state ? state.entries : []
        var fav = Object.assign({}, favorites)
        for (var k in fav) if (isCatalogueId(k)) delete fav[k]
        for (var i = 0; i < mediaLibrary.length; i++)
            if (mediaLibrary[i].favorite) fav[mediaLibrary[i].id] = true
        favorites = fav
        syncMediaMaps()
    }
    function updateMediaEntry(media, patch) {
        if (!media) return false
        var changes = Object.assign({}, patch || {})
        if (changes.openedAt === undefined && openedAt[media.id])
            changes.openedAt = openedAt[media.id]
        var out = MediaCatalogue.updateEntry(mediaLibrary, media, changes)
        mediaLibrary = out
        var fav = Object.assign({}, favorites)
        var saved = findIn(out, media.id)
        if (saved && saved.favorite) fav[media.id] = true
        else delete fav[media.id]
        favorites = fav
        syncMediaMaps()
        return true
    }
    function saveMediaLibrary() {
        if (!mediaStateReady) return
        mediaLibraryFile.setText(MediaCatalogue.serialize(mediaLibrary))
    }
    function wallpaperById(id) { return findIn(wallpapers, id) }
    function moodById(id) { return findIn(moods, id) || moods[0] }

    function notify(msg, kind) {
        toastText = msg
        toastKind = kind || "info"
        toastShown = true
        toastTimer.restart()
    }
    function logActivity(text) { activity = [text].concat(activity).slice(0, 6) }
    function go(i) { page = i; vibeOpen = false }

    // --- mood / vibe ------------------------------------------------
    function setMood(id) { moodId = id }
    function exploreMood(id) {
        var m = moodById(id)
        moodId = id
        resetWpFilters()
        wpCategory = m.cat
        wpVisible = 6
        page = 1
        vibeOpen = false
        notify("Browsing \u201c" + m.name + "\u201d wallpapers" + (wallhavenUsingRemote ? " on Wallhaven." : " in the sample set until Wallhaven loads."), "info")
        logActivity("Explored vibe: " + m.name)
    }
    function syncThemeUnavailable() {
        themeSyncRequested(moodId)   // >>> BACKEND: GPS theme engine listens to this.
        notify("Theme sync isn't connected yet \u2014 the request was emitted, but nothing on your desktop changed.", "warn")
    }

    // --- favorites / lists / progress ---------------------------------
    function toggleFavorite(id, title) {
        var on = !favorites[id]
        if (isCatalogueId(id)) {
            var media = findCatalogueMedia(id)
            if (!media) {
                notify("That catalogue entry is no longer available. Search for it again.", "warn")
                return
            }
            updateMediaEntry(media, { favorite: on })
            logActivity((on ? "Favorited: " : "Unfavorited: ") + title)
            return
        }
        var f = Object.assign({}, favorites)
        if (on) f[id] = true; else delete f[id]
        favorites = f
        var item = findMusicItem(id)
        if (item) {
            var saved = musicFavorites.filter(function (it) { return it.id !== id })
            if (on) saved.unshift(item)
            musicFavorites = saved
        }
        logActivity((on ? "Favorited: " : "Unfavorited: ") + title)
    }
    function setStatus(id, s) {
        if (!isCatalogueId(id)) return
        var media = findCatalogueMedia(id)
        if (!media) return
        updateMediaEntry(media, s === "" ? { userStatus: "", progress: 0 } : { userStatus: s })
    }
    function toggleList(kind, id, title) {
        if (statuses[id]) {
            setStatus(id, "")
            logActivity("Removed from " + (kind === "anime" ? "watchlist: " : "reading list: ") + title)
        } else {
            setStatus(id, kind === "anime" ? "Plan to Watch" : "Plan to Read")
            logActivity("Added to " + (kind === "anime" ? "watchlist: " : "reading list: ") + title)
        }
    }
    function setProgress(id, n, total) {
        if (!isCatalogueId(id)) return
        var media = findCatalogueMedia(id)
        if (!media) return
        var max = total > 0 ? total : 100000
        var v = Math.max(0, Math.min(max, n))
        var patch = { progress: v }
        var s = statuses[id]
        if (total > 0 && v >= total) {
            if (s !== "Completed") patch.userStatus = "Completed"
        } else if (v > 0 && s !== "Dropped" && s !== "Watching" && s !== "Reading" && s !== "Completed") {
            patch.userStatus = catalogueKind(id) === "anime" ? "Watching" : "Reading"
        }
        updateMediaEntry(media, patch)
    }
    function markOpened(id) {
        var opened = Date.now()
        var o = Object.assign({}, openedAt)
        o[id] = opened
        openedAt = o
        if (isCatalogueId(id) && findIn(mediaLibrary, id))
            updateMediaEntry(findCatalogueMedia(id), { openedAt: opened })
    }
    function openDetail(kind, id) {
        markOpened(id)
        detailKind = kind
        detailId = id
    }
    function closeDetail() { detailKind = ""; detailId = ""; detailShown = null }

    // --- wallpapers -----------------------------------------------------
    function previewWallpaper(id) { wpSelectedId = id; page = 1 }

    function wallhavenCategorySpec() {
        switch (wpCategory) {
        case "Anime": return { code: "anime", term: "" }
        case "General": return { code: "general", term: "" }
        case "People": return { code: "people", term: "" }
        case "Nature": return { code: "general", term: "nature" }
        case "Minimal": return { code: "general", term: "minimal" }
        case "Cyberpunk": return { code: "general", term: "cyberpunk" }
        case "Dark": return { code: "general", term: "dark" }
        case "Landscape": return { code: "general", term: "landscape" }
        }
        return { code: "all", term: "" }
    }
    function wallhavenSorting() {
        if (wpSort === "Popular") return "favorites"
        if (wpSort === "Latest") return "date_added"
        if (wpSort === "Random") return "random"
        return "relevance"
    }
    function wallhavenAtleast() {
        if (wpRes === "1920+") return "1920x1080"
        if (wpRes === "2560+") return "2560x1440"
        if (wpRes === "4K+") return "3840x2160"
        return ""
    }
    function wallhavenColorCode() {
        return ({
            Violet: "663399",
            Cyan: "0099cc",
            Amber: "ff9900",
            Green: "669900",
            Red: "cc3333",
            Rose: "ea4c88",
            Slate: "999999"
        })[wpColor] || ""
    }
    function scheduleWallhavenSearch() {
        if (root.page !== 1) return
        wallhavenSearchTimer.restart()
    }
    function wallhavenRequest(append) {
        if (append && (wallhavenLoading || wallhavenPage <= 0
                       || (wallhavenWallpapers.length > 0 && wallhavenPage >= wallhavenLastPage)))
            return null
        var category = wallhavenCategorySpec()
        var query = wpQuery.trim()
        if (category.term !== "") query = query === "" ? category.term : query + " " + category.term
        return {
            query: query,
            category: category.code,
            sorting: wallhavenSorting(),
            order: "desc",
            atleast: wallhavenAtleast(),
            ratios: wpAspect === "Any" ? "" : String(wpAspect).replace(":", "x"),
            color: wallhavenColorCode(),
            page: append ? wallhavenPage + 1 : 1,
            seed: append ? wallhavenSeed : "",
            append: append === true
        }
    }
    function runWallhavenSearch(append) {
        var request = wallhavenRequest(append)
        if (!request) return
        wallhavenSearchSeq += 1
        request.seq = wallhavenSearchSeq
        wallhavenError = ""
        wallhavenErrorCode = ""
        wallhavenBackend.search(request)
    }
    function retryWallhaven() {
        wallhavenSearchTimer.stop()
        runWallhavenSearch(false)
    }
    function loadMoreWallhaven() {
        if (root.wallhavenLoading) return
        if (wpVisible < wallpapers.length) {
            wpVisible += 6
        } else if (wallhavenUsingRemote && wallhavenPage < wallhavenLastPage) {
            runWallhavenSearch(true)
        }
    }
    function wallhavenGradient(index) {
        var keys = ["violet", "rose", "cosmic", "amber", "green", "slate", "teal", "red"]
        return gradients[keys[index % keys.length]]
    }
    function normalizeWallhavenWallpaper(w, index) {
        if (!w || typeof w.id !== "string" || typeof w.full !== "string" || w.full === "") return null
        var pal = (w.colors && w.colors.length > 0)
            ? w.colors
            : ["#0b0f17", "#2a1b5e", "#7bd0ff"]
        return Object.assign({}, w, {
            kind: "wallpaper",
            isRemote: true,
            art: typeof w.thumb === "string" ? w.thumb : "",
            cats: [w.category || "General"],
            fam: [],
            pal: pal,
            g: wallhavenGradient(index),
            likes: Number(w.likes) || 0,
            added: Number(w.added) || 0
        })
    }
    function handleWallhavenSearch(payload, request) {
        if (!request || request.seq !== wallhavenSearchSeq) return
        var incoming = []
        var results = (payload.results && typeof payload.results.length === "number") ? payload.results : []
        for (var i = 0; i < results.length; i++) {
            var mapped = normalizeWallhavenWallpaper(results[i], incoming.length)
            if (mapped) incoming.push(mapped)
        }
        var firstConnect = !wallhavenConnected
        if (request.append) {
            var seen = {}
            var merged = wallhavenWallpapers.slice()
            for (var j = 0; j < merged.length; j++) seen[merged[j].id] = true
            for (var k = 0; k < incoming.length; k++) {
                if (!seen[incoming[k].id]) {
                    seen[incoming[k].id] = true
                    merged.push(incoming[k])
                }
            }
            wallhavenWallpapers = merged
            if (incoming.length > 0)
                wpVisible = Math.min(wallhavenWallpapers.length, wpVisible + 6)
        } else {
            wallhavenWallpapers = incoming
            wpVisible = 6
            wpTag = ""
            if (!findIn(wallhavenWallpapers, featuredId))
                featuredId = wallhavenWallpapers.length > 0 ? wallhavenWallpapers[0].id : ""
            if (!findIn(wallhavenWallpapers, wpSelectedId)) {
                wpSelectedId = ""
                wpShownId = ""
            }
        }
        wallhavenPage = Number(payload.page) || request.page
        wallhavenLastPage = Math.max(wallhavenPage, Number(payload.lastPage) || wallhavenPage)
        wallhavenSeed = typeof payload.seed === "string" ? payload.seed : ""
        wallhavenUsingRemote = true
        wallhavenConnected = true
        wallhavenLoaded = true
        wallhavenError = ""
        wallhavenErrorCode = ""
        logActivity("Wallhaven: " + incoming.length + " result(s) on page " + wallhavenPage)
        if (firstConnect)
            notify("Wallhaven connected \u2014 showing real SFW wallpapers.", "ok")
    }
    function handleWallhavenFailure(message, code, request) {
        if (!request || request.seq !== wallhavenSearchSeq) return
        wallhavenError = message
        wallhavenErrorCode = code
        wallhavenConnected = false
        notify("Wallhaven search failed: " + message, "warn")
        logActivity("Wallhaven search failed: " + code)
    }
    function handleWallhavenApplied(payload, request) {
        if (!request) return
        wallhavenConnected = true
        if (request.syncTheme)
            notify("Wallpaper applied. Syncing the GPS theme\u2026", "info")
        else
            notify("Wallpaper applied: " + request.title, "ok")
        logActivity("Applied Wallhaven wallpaper: " + request.title)
    }
    function handleWallhavenApplyFailure(message, code, request) {
        notify("Couldn't apply wallpaper: " + message, "warn")
        logActivity("Wallhaven apply failed: " + code)
    }
    function handleWallhavenThemeSync(ok, message) {
        if (ok) {
            notify("Wallpaper applied and GPS theme synced.", "ok")
            logActivity("GPS theme synced after Wallhaven apply")
        } else {
            notify("Wallpaper applied, but GPS theme sync failed: " + message, "warn")
            logActivity("GPS theme sync failed after Wallhaven apply")
        }
    }
    function requestApply(w, sync) {
        if (!w) return
        if (!w.isRemote) {
            notify("Bundled sample cards are previews only. Search Wallhaven to download and apply a wallpaper.", "warn")
            return
        }
        if (!w.full) {
            notify("This Wallhaven result has no downloadable image URL.", "warn")
            return
        }
        if (wallhavenApplying) {
            notify("Another wallpaper is still being applied. Give it a moment.", "info")
            return
        }
        wallpaperApplyRequested(w, sync)
        wallhavenApplySeq += 1
        var started = wallhavenBackend.apply({
            seq: wallhavenApplySeq,
            id: w.id,
            path: w.full,
            title: w.title,
            syncTheme: sync === true
        })
        if (started) {
            notify("Downloading and applying \u201c" + w.title + "\u201d\u2026", "info")
            logActivity("Applying Wallhaven wallpaper: " + w.title)
        } else {
            notify("A wallpaper apply is already running.", "info")
        }
    }
    function toolPlayers() {
        return root.toolStatus && root.toolStatus.players && typeof root.toolStatus.players.length === "number"
            ? root.toolStatus.players : []
    }
    function toolTerminals() {
        return root.toolStatus && root.toolStatus.terminals && typeof root.toolStatus.terminals.length === "number"
            ? root.toolStatus.terminals : []
    }
    function toolGuidance(key) {
        return root.toolStatus && root.toolStatus.guidance && root.toolStatus.guidance[key]
            ? String(root.toolStatus.guidance[key]) : ""
    }
    function validToolCommand(value) {
        if (!value || typeof value.length !== "number" || value.length < 1 || value.length > 16)
            return false
        for (var i = 0; i < value.length; i++) {
            if (typeof value[i] !== "string" || value[i] === "" || value[i].length > 4096)
                return false
        }
        return true
    }
    function toolCommandList(value) {
        var command = []
        for (var i = 0; i < value.length; i++) command.push(String(value[i]))
        return command
    }
    function launchAniCli() {
        if (!root.toolsStatusReady) {
            notify("Still checking optional playback tools. Try again in a moment.", "info")
            return
        }
        if (!toolsBackend.prepareAniCli())
            notify("A playback action is already being prepared.", "info")
    }
    function chooseLocalVideo() {
        localVideoDialog.open()
    }
    function launchLocalVideo(path) {
        if (!path) return
        if (!root.toolsStatusReady) {
            notify("Still checking optional playback tools. Try again in a moment.", "info")
            return
        }
        if (!toolsBackend.prepareLocalVideo(path))
            notify("A playback action is already being prepared.", "info")
    }
    function handleToolCommand(payload, action) {
        if (!payload || !root.validToolCommand(payload.command)) {
            notify("The playback helper did not return a valid launch command.", "warn")
            return
        }
        Quickshell.execDetached(root.toolCommandList(payload.command))
        if (action === "ani-cli") {
            notify("Opened ani-cli in " + (payload.terminal && payload.terminal.label ? payload.terminal.label : "a terminal") + ". Choose a title in its interactive menu.", "ok")
            logActivity("Opened ani-cli externally")
        } else {
            notify(payload.message || "Opened the selected video in an external player.", "ok")
            logActivity("Opened local video: " + (payload.path || ""))
        }
    }
    function handleToolFailure(message, code, action) {
        var text = String(message || "The external playback tool could not be started.")
        var guidance = code === "ani_cli_missing" ? toolGuidance("aniCli")
            : (code === "terminal_missing" ? toolGuidance("terminal")
            : (code === "player_missing" ? toolGuidance("player") : ""))
        if (guidance !== "" && text.indexOf(guidance) === -1) text += " " + guidance
        notify(text, "warn")
        if (action === "ani-cli") logActivity("ani-cli launch unavailable: " + code)
        else logActivity("Local video launch unavailable: " + code)
    }
    function openExternalUrl(url, site) {
        var value = String(url || "")
        if (!/^https:\/\/[^\s]+$/i.test(value) || value.length > 2048) {
            notify("That provider link is not a valid HTTPS destination.", "warn")
            return
        }
        sourceLinkRequested(value)
        notify("Opening " + (site || "official provider") + "\u2026", "info")
    }
    function openSource(w) {
        if (!w) return
        if (isCatalogueId(w.id) && w.siteUrl) {
            sourceLinkRequested(w.siteUrl)
            notify("Opening the official AniList page\u2026", "info")
            return
        }
        if (!w.isRemote || !w.source) {
            notify("Bundled sample cards don't have a Wallhaven source page.", "warn")
            return
        }
        sourceLinkRequested(w.source)
        notify("Opening the Wallhaven source page\u2026", "info")
    }
    function wallpaperSourceLabel(w) {
        return (w && w.isRemote) ? "Wallhaven" : "Bundled sample"
    }
    function wallpaperCardExtra(w) {
        if (!w) return ""
        if (w.tags && w.tags.length > 0) return "#" + w.tags.slice(0, 2).join("  #")
        if (w.isRemote) return "Wallhaven \u00b7 SFW" + (w.likes > 0 ? " \u00b7 " + w.likes + " favorites" : "")
        return ""
    }
    function shuffleWp() {
        var r = {}
        for (var i = 0; i < wallpapers.length; i++) r[wallpapers[i].id] = Math.random()
        randomRank = r
    }
    function filteredWallpapers() {
        if (wallhavenUsingRemote) {
            if (wpTag === "") return wallhavenWallpapers.slice()
            return wallhavenWallpapers.filter(function (w) {
                return w.tags && w.tags.indexOf(wpTag) >= 0
            })
        }
        var q = wpQuery.trim().toLowerCase()
        var out = []
        for (var i = 0; i < wallpapers.length; i++) {
            var w = wallpapers[i]
            if (wpCategory === "General" && w.cats.indexOf("Anime") >= 0) continue
            if (wpCategory === "People") continue
            if (wpCategory !== "All" && wpCategory !== "General" && w.cats.indexOf(wpCategory) < 0) continue
            if (wpColor !== "Any" && w.fam.indexOf(wpColor) < 0) continue
            if (resMin[wpRes] > 0 && w.w < resMin[wpRes]) continue
            if (wpAspect !== "Any" && w.ratio !== wpAspect) continue
            if (wpTag !== "" && w.tags.indexOf(wpTag) < 0) continue
            if (q && (w.title + " " + w.author + " " + w.tags.join(" ")).toLowerCase().indexOf(q) < 0) continue
            out.push(w)
        }
        if (wpSort === "Popular") out.sort(function (a, b) { return b.likes - a.likes })
        else if (wpSort === "Latest") out.sort(function (a, b) { return b.added - a.added })
        else if (wpSort === "Random") out.sort(function (a, b) { return (randomRank[a.id] || 0) - (randomRank[b.id] || 0) })
        return out
    }
    function allTags() {
        var seen = {}, out = []
        for (var i = 0; i < wallpapers.length; i++)
            for (var j = 0; j < wallpapers[i].tags.length; j++) {
                var t = wallpapers[i].tags[j]
                if (!seen[t]) { seen[t] = true; out.push(t) }
            }
        return out.slice(0, 14)
    }
    function activeWpFilters() {
        return (wpQuery.trim() !== "" ? 1 : 0) + (wpCategory !== "All" ? 1 : 0) + (wpColor !== "Any" ? 1 : 0)
             + (wpRes !== "Any" ? 1 : 0) + (wpAspect !== "Any" ? 1 : 0) + (wpTag !== "" ? 1 : 0)
    }
    function resetWpFilters() {
        wpQuery = ""; wpCategory = "All"; wpColor = "Any"; wpRes = "Any"; wpAspect = "Any"
        wpTag = ""; wpSort = "Relevance"; wpVisible = 6
    }

    // --- continue / counts ------------------------------------------------
    function continueList(kind) {
        var active = kind === "anime" ? "Watching" : "Reading"
        var out = mediaLibrary.filter(function (m) {
            return m.kind === kind && m.userStatus === active
                && (m.total <= 0 || (m.progress || 0) < m.total)
        })
        out.sort(function (a, b) { return (b.openedAt || 0) - (a.openedAt || 0) || (b.savedAt || 0) - (a.savedAt || 0) })
        return out
    }
    function continueAll() { return continueList("anime").slice(0, 2).concat(continueList("manga").slice(0, 2)) }
    function countListed(kind) {
        var n = 0
        for (var i = 0; i < mediaLibrary.length; i++)
            if (mediaLibrary[i].kind === kind && mediaLibrary[i].userStatus) n++
        return n
    }
    function favCount() { var n = 0; for (var k in favorites) n++; return n }
    function continueMedia(item) {
        if (!item) return
        markOpened(item.id)
        if (isCatalogueId(item.id)) {
            var catalogueItem = findCatalogueMedia(item.id)
            if (catalogueItem) {
                openSource(catalogueItem)
                logActivity("Opened AniList: " + item.title)
            } else {
                notify("That catalogue entry is no longer available. Search for it again.", "warn")
            }
            return
        }
        // >>> BACKEND: hand off local media to a player / reader.
        openMediaRequested(item)
        notify("Open request emitted for \u201c" + item.title + "\u201d. No player or reader is connected in this prototype.", "info")
        logActivity("Opened: " + item.title + " (hand-off not connected)")
    }

    // --- library ------------------------------------------------------------
    function libEntry(src, kind, sub, added) {
        return { kind: kind, id: src.id, title: src.title, sub: sub, art: src.cover || src.art || "", g: src.g, added: added,
                 opened: openedAt[src.id] || 0, fav: !!favorites[src.id] }
    }
    function libraryItems() {
        var out = [], i
        for (i = 0; i < wallpapers.length; i++) {
            var w = wallpapers[i]
            if (favorites[w.id]) out.push(libEntry(w, "wallpaper", w.res + " \u00b7 " + w.size, 40 + w.added))
        }
        for (i = 0; i < mediaLibrary.length; i++) {
            var m = mediaLibrary[i]
            if (!m.userStatus && !m.favorite) continue
            var progressLabel = m.total > 0
                ? (m.kind === "anime" ? "Ep " : "Ch ") + (m.progress || 0) + "/" + m.total
                : (m.kind === "anime" ? "Ep " : "Ch ") + (m.progress || 0) + "/?"
            out.push(libEntry(m, m.kind, (m.userStatus || "Favorite") + " \u00b7 " + progressLabel, m.savedAt || 0))
        }
        for (i = 0; i < mediaList.length; i++) out.push(libEntry(mediaList[i], mediaList[i].kind, mediaList[i].meta, mediaList[i].added))
        for (i = 0; i < musicFavorites.length; i++) {
            var song = musicFavorites[i]
            out.push(libEntry(song, song.kind, musicSub(song), 60 + i))
        }
        return out
    }
    readonly property var libFilterKind: ({ "Videos": "video", "Audio": "audio", "Wallpapers": "wallpaper", "Anime": "anime", "Manga & Manhwa": "manga" })
    function libraryList(filter, sort, q) {
        var needle = (q || "").trim().toLowerCase()
        var items = libraryItems().filter(function (it) {
            if (filter === "Favorites" && !it.fav) return false
            if (filter === "Music" && it.kind !== "track" && it.kind !== "station") return false
            if (libFilterKind[filter] && it.kind !== libFilterKind[filter]) return false
            if (needle && it.title.toLowerCase().indexOf(needle) < 0) return false
            return true
        })
        if (sort === "Recently Added") items.sort(function (a, b) { return b.added - a.added })
        else if (sort === "Recently Opened") items.sort(function (a, b) { return b.opened - a.opened || b.added - a.added })
        else if (sort === "Alphabetical") items.sort(function (a, b) { return a.title.localeCompare(b.title) })
        else if (sort === "Favorites") items.sort(function (a, b) { return (b.fav ? 1 : 0) - (a.fav ? 1 : 0) || a.title.localeCompare(b.title) })
        return items
    }
    function libraryLabel(kind) {
        return kind === "wallpaper" ? "Preview" : ((kind === "anime" || kind === "manga") ? "Open AniList" : (kind === "station" ? "Listen" : "Play"))
    }
    function libraryAction(it) {
        if (it.kind === "wallpaper") { previewWallpaper(it.id); return }
        if (it.kind === "track" || it.kind === "station") {
            var mi = findMusicItem(it.id)
            if (mi) playNow(mi, [mi])
            else notify("This saved song is missing its stream details.", "warn")
            return
        }
        continueMedia(it)
    }
    function libraryActivate(it) {
        if (it.kind === "wallpaper") previewWallpaper(it.id)
        else if (it.kind === "anime" || it.kind === "manga") openDetail(it.kind, it.id)
    }
    function kindLabel(kind) {
        return ({ wallpaper: "Wallpaper", anime: "Anime", manga: "Manga", video: "Video", audio: "Audio", track: "Track", station: "Radio" })[kind] || kind
    }

    // --- downloads ----------------------------------------------------------
    function updateDownload(id, patch) {
        downloads = downloads.map(function (d) { return d.id === id ? Object.assign({}, d, patch) : d })
    }
    function removeDownload(id) { downloads = downloads.filter(function (d) { return d.id !== id }) }
    function dlCount(status) {
        var n = 0
        for (var i = 0; i < downloads.length; i++) if (status === "all" || downloads[i].status === status) n++
        return n
    }
    function enqueue(url, mode, format, quality, dir) {
        // >>> BACKEND: hand the request to yt-dlp (+ FFmpeg for audio extraction / muxing).
        var host = url.replace(/^https?:\/\//i, "").split("/")[0]
        dlSeq++
        var rec = { id: "d" + dlSeq, name: host + " \u2014 title resolved by yt-dlp later", type: mode, format: format, quality: quality,
                    dest: dir, status: "queued", progress: 0, size: "waiting for backend", error: "" }
        downloads = [rec].concat(downloads)
        downloadRequested({ url: url, mode: mode, format: format, quality: quality, directory: dir })
        notify("Added to the queue as \u201cqueued\u201d. Nothing downloads until a backend handles downloadRequested.", "warn")
        logActivity("Queued URL (not started): " + host)
    }
    function dlAction(d, action) {
        if (action === "pause") { updateDownload(d.id, { status: "paused" }); notify("Paused in the UI only \u2014 no real transfer exists to pause.", "info") }
        else if (action === "resume") { updateDownload(d.id, { status: "downloading" }); notify("Resumed in the UI only \u2014 progress will not advance without a backend.", "info") }
        else if (action === "cancel") { removeDownload(d.id); notify("Removed from the sample queue.", "info") }
        else if (action === "remove") { removeDownload(d.id) }
        else if (action === "retry") { notify("Retry needs the download backend (yt-dlp), which isn't connected yet.", "warn"); downloadRequested({ retry: d.id, name: d.name }) }
        else if (action === "open") { openLocationRequested(d.dest); notify("Open-location request emitted for " + d.dest + ".", "info") }
    }

    // --- surprise me --------------------------------------------------------
    function pickRandom(list) { return list.length > 0 ? list[Math.floor(Math.random() * list.length)] : null }
    function cataloguePool(kind) {
        var remote = kind === "anime" ? animeList : mangaList
        if (remote.length > 0) return remote
        return mediaLibrary.filter(function (m) { return m.kind === kind })
    }
    function surprise() {
        var kinds = ["mood", "wallpaper"]
        if (cataloguePool("anime").length > 0) kinds.push("anime")
        if (cataloguePool("manga").length > 0) kinds.push("manga")
        if (jamendoTracks.length > 0) kinds.push("track")
        var k = pickRandom(kinds)
        if (k === "mood") {
            var others = moods.filter(function (m) { return m.id !== moodId })
            var m = pickRandom(others)
            if (!m) return
            setMood(m.id)
            surprisePick = { kind: "mood", id: m.id, title: m.name, sub: "Mood selected" }
        } else if (k === "wallpaper") {
            var w = pickRandom(wallpapers)
            if (!w) return
            featuredId = w.id
            surprisePick = { kind: "wallpaper", id: w.id, title: w.title, sub: "Featured wallpaper updated" }
        } else if (k === "anime") {
            var a = pickRandom(cataloguePool("anime"))
            if (!a) return
            surprisePick = { kind: "anime", id: a.id, title: a.title, sub: "Anime \u00b7 " + a.genres.join(", ") }
        } else if (k === "track") {
            var tk = pickRandom(jamendoTracks)
            if (!tk) return
            surprisePick = { kind: "track", id: tk.id, title: tk.title, sub: tk.artist + " \u00b7 " + tk.genre }
        } else {
            var g = pickRandom(cataloguePool("manga"))
            if (!g) return
            surprisePick = { kind: "manga", id: g.id, title: g.title, sub: g.type + " \u00b7 " + g.genres.join(", ") }
        }
        page = 0
        notify("Surprise: " + surprisePick.title, "ok")
        logActivity("Surprise Me \u2192 " + surprisePick.title)
    }
    function openSurprise() {
        var s = surprisePick
        if (!s) return
        if (s.kind === "mood") exploreMood(s.id)
        else if (s.kind === "wallpaper") previewWallpaper(s.id)
        else if (s.kind === "track") { var ti = findMusicItem(s.id); if (ti) playNow(ti, [ti]) }
        else openDetail(s.kind, s.id)
    }

    // --- global search --------------------------------------------------------
    function globalResults(query) {
        var q = (query || "").trim()
        if (q === "") return []
        if (/^https?:\/\//i.test(q)) return [{ kind: "url", id: q, title: "Prepare a download for this URL", sub: q }]
        var lq = q.toLowerCase(), out = [], seen = {}
        function scan(list, kind, subFn) {
            for (var i = 0; i < list.length; i++) {
                var it = list[i]
                var key = kind + ":" + it.id
                if (seen[key]) continue
                var hay = (it.title + " " + (it.altTitles ? it.altTitles.join(" ") : "") + " "
                    + (it.tags ? it.tags.join(" ") : "") + " " + (it.genres ? it.genres.join(" ") : "") + " "
                    + (it.artist || "") + " " + (it.author || "") + " "
                    + (it.studios ? it.studios.join(" ") : "")).toLowerCase()
                if (hay.indexOf(lq) >= 0) {
                    seen[key] = true
                    out.push({ kind: kind, id: it.id, title: it.title, sub: subFn(it) })
                }
            }
        }
        scan(wallpapers, "wallpaper", function (w) { return w.res + " \u00b7 " + w.author })
        scan(animeList, "anime", function (a) { return (a.seasonLabel || a.year) + " \u00b7 " + a.genres.slice(0, 2).join(", ") })
        scan(mangaList, "manga", function (m) { return m.type + " \u00b7 " + m.genres.slice(0, 2).join(", ") })
        scan(mediaLibrary.filter(function (m) { return m.kind === "anime" }), "anime", function (a) { return (a.seasonLabel || a.year) + " \u00b7 " + a.genres.slice(0, 2).join(", ") })
        scan(mediaLibrary.filter(function (m) { return m.kind === "manga" }), "manga", function (m) { return m.type + " \u00b7 " + m.genres.slice(0, 2).join(", ") })
        scan(mediaList, "media", function (m) { return m.meta })
        scan(jamendoTracks, "track", function (t) { return t.artist + " \u00b7 " + t.genre })
        scan(radioStations, "station", function (s) { return s.genre + " \u00b7 radio" })
        return out.slice(0, 7)
    }
    function openResult(r) {
        gq = ""
        gsearch.clear()
        if (r.kind === "url") { pendingUrl = r.id; page = pgDownloads }
        else if (r.kind === "wallpaper") previewWallpaper(r.id)
        else if (r.kind === "anime") { page = 2; openDetail("anime", r.id) }
        else if (r.kind === "manga") { page = 3; openDetail("manga", r.id) }
        else if (r.kind === "track" || r.kind === "station") {
            var mi2 = findMusicItem(r.id)
            page = pgMusic
            if (mi2) playNow(mi2, [mi2])
            else notify("That song is no longer in the current result set.", "warn")
        }
        else page = pgLibrary
    }

    // ================================================================
    //  INLINE BUILDING BLOCKS
    //  (inline components can't see root ids, so they only use properties)
    // ================================================================
    component Pal: QtObject {
        readonly property color bg: Theme.surfaceDeep
        readonly property color lowest: Theme.track
        readonly property color low: Theme.surfaceBase
        readonly property color cont: Theme.card
        readonly property color high: Theme.cardHover
        readonly property color highest: Theme.surfaceHigh
        readonly property color line: Theme.outlineSoft
        readonly property color border: Theme.border
        readonly property color text: Theme.textMain
        readonly property color dim: Theme.textDim
        readonly property color faint: Theme.textMuted
        readonly property color err: Theme.statusDanger
        readonly property color ok: Theme.statusGood
        readonly property color warn: Theme.statusWarn
        readonly property color cyan: "#7bd0ff"
        readonly property color orchid: Theme.accentSecondary
        readonly property color onAcc: Theme.onAccent
        readonly property color accent: root.accent
    }
    Pal { id: pal }

    component Lbl: Text {
        property bool mono: false
        property bool dim: false
        property bool faint: false
        // font.family takes one name; Qt falls back to a similar installed font if it is missing.
        font.family: mono ? Theme.fontMono : Theme.fontUi
        font.pixelSize: 13
        color: faint ? Theme.textMuted : (dim ? Theme.textDim : Theme.textMain)
    }

    // Icon strategy: plain Unicode glyphs (no icon font needed).
    // To use Material Symbols / Nerd Font instead, change `g()` and `font.family` here only.
    component Ico: Text {
        property string name: ""
        property color tint: Theme.textDim
        property int size: 16
        function g(n) {
            switch (n) {
            case "home": return "\u2302"
            case "wallpaper": return "\u25A3"
            case "anime": return "\u25B7"
            case "manga": return "\u25A4"
            case "download": return "\u2193"
            case "library": return "\u2750"
            case "search": return "\u2315"
            case "surprise": return "\u2726"
            case "vibe": return "\u25D0"
            case "heart": return "\u2665"
            case "heartO": return "\u2661"
            case "star": return "\u2605"
            case "play": return "\u25B6"
            case "pause": return "\u2016"
            case "check": return "\u2713"
            case "close": return "\u2715"
            case "plus": return "+"
            case "minus": return "\u2212"
            case "refresh": return "\u21BB"
            case "folder": return "\u25AD"
            case "link": return "\u2197"
            case "info": return "\u24D8"
            case "grid": return "\u25A6"
            case "list": return "\u2630"
            case "chev": return "\u203A"
            case "back": return "\u2039"
            case "sync": return "\u21C4"
            case "warn": return "\u26A0"
            case "cloud": return "\u2601"
            case "terminal": return "\u25B8_"
            case "eye": return "\u25C9"
            case "music": return "\u266A"
            case "video": return "\u25B6"
            case "tag": return "#"
            case "dot": return "\u25CF"
            case "desktop": return "\u25AD"
            default: return "\u2022"
            }
        }
        text: g(name)
        color: tint
        font.pixelSize: size
        font.family: "DejaVu Sans"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property string icon: ""
        property string kind: "secondary"   // primary | secondary | ghost | danger
        property color accent: Theme.brandAccent
        property bool compact: false
        property bool muted: false
        signal clicked()
        readonly property color fg: kind === "primary" ? Theme.onAccent : (kind === "danger" ? Theme.statusDanger : Theme.textMain)
        implicitHeight: compact ? 30 : 38
        implicitWidth: brow.implicitWidth + (compact ? 22 : 30)
        radius: compact ? 9 : 11
        color: kind === "primary" ? (bma.containsMouse ? Qt.lighter(accent, 1.12) : accent)
             : kind === "ghost" ? (bma.containsMouse ? Theme.cardHover : "transparent")
             : kind === "danger" ? (bma.containsMouse ? "#5a1a1d" : "#3b1417")
             : (bma.containsMouse ? Theme.surfaceHigh : Theme.card)
        border.width: kind === "secondary" ? 1 : 0
        border.color: Theme.outlineSoft
        opacity: muted ? 0.55 : 1
        scale: bma.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Row {
            id: brow
            anchors.centerIn: parent
            spacing: 7
            Ico { visible: b.icon !== ""; name: b.icon; size: b.compact ? 12 : 14; tint: b.fg; anchors.verticalCenter: parent.verticalCenter }
            Lbl { visible: b.label !== ""; text: b.label; color: b.fg; font.pixelSize: b.compact ? 12 : 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool active: false
        property color tint: Theme.textDim
        property color activeTint: Theme.statusDanger
        property int box: 32
        signal clicked()
        implicitWidth: box
        implicitHeight: box
        radius: box / 2
        color: ima.containsMouse ? Theme.surfaceHigh : Qt.alpha(Theme.card, 0.85)
        scale: ima.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        Ico { anchors.centerIn: parent; name: ib.icon; size: Math.round(ib.box * 0.45); tint: ib.active ? ib.activeTint : ib.tint }
        MouseArea { id: ima; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
        ToolTip.visible: ima.containsMouse && ib.tip !== ""
        ToolTip.text: ib.tip
        ToolTip.delay: 500
    }

    component Chip: Rectangle {
        id: ch
        property string label: ""
        property string icon: ""
        property string badge: ""
        property bool active: false
        property color accent: Theme.brandAccent
        property color dot: "transparent"
        signal clicked()
        implicitHeight: 30
        implicitWidth: crow.implicitWidth + 24
        radius: 15
        color: active ? Qt.alpha(accent, 0.20) : (cma.containsMouse ? Theme.surfaceHigh : Theme.surfaceBase)
        border.width: 1
        border.color: active ? Qt.alpha(accent, 0.75) : Theme.outlineSoft
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Row {
            id: crow
            anchors.centerIn: parent
            spacing: 6
            Rectangle { visible: ch.dot.a > 0; width: 9; height: 9; radius: 4.5; color: ch.dot; anchors.verticalCenter: parent.verticalCenter }
            Ico { visible: ch.icon !== ""; name: ch.icon; size: 12; tint: ch.active ? ch.accent : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
            Lbl { text: ch.label; font.pixelSize: 12; font.weight: ch.active ? Font.DemiBold : Font.Medium; color: ch.active ? "#f4efff" : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                visible: ch.badge !== ""
                height: 16; width: bdg.implicitWidth + 10; radius: 8
                color: "#40000000"
                anchors.verticalCenter: parent.verticalCenter
                Lbl { id: bdg; anchors.centerIn: parent; text: ch.badge; mono: true; font.pixelSize: 10; faint: true }
            }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }

    component Tag: Rectangle {
        id: tg
        property string text: ""
        property color tint: Theme.textDim
        property int px: 10
        implicitHeight: px + 10
        implicitWidth: tgl.implicitWidth + 14
        radius: 6
        color: Qt.alpha(tint, 0.14)
        Lbl { id: tgl; anchors.centerIn: parent; text: tg.text; mono: true; font.pixelSize: tg.px; color: tg.tint }
    }

    component Bar: Rectangle {
        property real value: 0
        property color tint: Theme.brandAccent
        implicitHeight: 6
        radius: height / 2
        color: Theme.track
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: parent.tint
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }

    component Toggle: Rectangle {
        id: tgl2
        property bool checked: false
        property color accent: Theme.brandAccent
        signal toggled()
        implicitWidth: 38
        implicitHeight: 22
        radius: 11
        color: checked ? accent : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: 16; height: 16; radius: 8; y: 3
            x: tgl2.checked ? 19 : 3
            color: tgl2.checked ? Theme.onAccent : Theme.textDim
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tgl2.toggled() }
    }

    component VScroll: ScrollBar {
        id: sb
        policy: ScrollBar.AsNeeded
        implicitWidth: 8
        contentItem: Rectangle {
            implicitWidth: 5
            radius: 3
            color: Theme.cardHover
            opacity: sb.pressed ? 0.95 : (sb.active || sb.hovered ? 0.7 : 0.0)
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        background: Item {}
    }

    component Wrap: Item {
        id: wr
        default property alias content: fl.data
        property real spacing: 8
        implicitHeight: fl.implicitHeight
        Flow { id: fl; width: wr.width; spacing: wr.spacing }
    }

    component Card: Rectangle {
        id: cd
        property int pad: 18
        property int gap: 12
        property color tint: "transparent"
        default property alias content: inner.data
        color: tint.a > 0 ? Qt.alpha(tint, 0.07) : Theme.surfaceBase
        radius: 16
        border.width: 1
        border.color: tint.a > 0 ? Qt.alpha(tint, 0.28) : Theme.outlineSoft
        implicitHeight: inner.implicitHeight + pad * 2
        ColumnLayout { id: inner; x: cd.pad; y: cd.pad; width: cd.width - cd.pad * 2; spacing: cd.gap }
    }

    component SearchField: Rectangle {
        id: sf
        property alias text: input.text
        property string placeholder: ""
        property string icon: "search"
        property color accent: Theme.brandAccent
        signal edited()
        signal submitted()
        readonly property bool focused: input.activeFocus
        function clear() { input.text = "" }
        function focusField() { input.forceActiveFocus() }
        implicitHeight: 38
        radius: 12
        color: input.activeFocus ? Theme.cardHover : Theme.surfaceBase
        border.width: 1
        border.color: input.activeFocus ? sf.accent : Theme.outlineSoft
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Ico { id: sfIcon; x: 12; anchors.verticalCenter: parent.verticalCenter; name: sf.icon; size: 15; tint: Theme.textMuted }
        TextInput {
            id: input
            anchors { left: sfIcon.right; leftMargin: 8; right: sfClear.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
            color: Theme.textMain
            selectionColor: Qt.alpha(sf.accent, 0.45)
            selectedTextColor: Theme.onAccent
            font.pixelSize: 13
            font.family: Theme.fontUi
            clip: true
            selectByMouse: true
            onTextEdited: sf.edited()
            onAccepted: sf.submitted()
            Keys.onEscapePressed: input.focus = false
        }
        Lbl {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: sf.placeholder
            color: Theme.textMuted
            opacity: 0.7
            elide: Text.ElideRight
        }
        Item {
            id: sfClear
            width: 22; height: 22
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            visible: input.text.length > 0
            Ico { anchors.centerIn: parent; name: "close"; size: 11; tint: Theme.textMuted }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { input.text = ""; sf.edited(); input.forceActiveFocus() } }
        }
    }

    // Artwork with a gradient fallback (used while loading, offline, or on error).
    component Art: Item {
        id: art
        property string src: ""
        property var grad: [Theme.surfaceBase, "#2a1b5e", "#0e4a6b"]
        property string glyph: ""
        property real radiusPx: 0
        property color frameColor: Theme.surfaceBase
        property real zoom: 1
        clip: true
        Item {
            anchors.fill: parent
            scale: art.zoom
            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: art.grad[0] }
                    GradientStop { position: 1.0; color: art.grad[1] }
                }
            }
            Rectangle {
                anchors.fill: parent
                opacity: 0.6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: art.grad[2] }
                }
            }
            Ico {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                name: art.glyph
                size: Math.round(Math.max(16, Math.min(art.width, art.height) * 0.28))
                tint: "#33ffffff"
            }
            Image {
                id: img
                anchors.fill: parent
                source: art.src
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 720
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 } }
            }
        }
        // Rounded corners without shaders: paint the four corner slivers in the surface colour.
        Shape {
            anchors.fill: parent
            visible: art.radiusPx > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: art.frameColor
                strokeColor: "transparent"
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                startX: 0; startY: 0
                PathLine { x: art.width; y: 0 }
                PathLine { x: art.width; y: art.height }
                PathLine { x: 0; y: art.height }
                PathLine { x: 0; y: 0 }
                PathMove { x: art.radiusPx; y: 0 }
                PathLine { x: art.width - art.radiusPx; y: 0 }
                PathArc { x: art.width; y: art.radiusPx; radiusX: art.radiusPx; radiusY: art.radiusPx }
                PathLine { x: art.width; y: art.height - art.radiusPx }
                PathArc { x: art.width - art.radiusPx; y: art.height; radiusX: art.radiusPx; radiusY: art.radiusPx }
                PathLine { x: art.radiusPx; y: art.height }
                PathArc { x: 0; y: art.height - art.radiusPx; radiusX: art.radiusPx; radiusY: art.radiusPx }
                PathLine { x: 0; y: art.radiusPx }
                PathArc { x: art.radiusPx; y: 0; radiusX: art.radiusPx; radiusY: art.radiusPx }
            }
        }
    }

    component Spec: Rectangle {
        property string k: ""
        property string v: ""
        implicitHeight: 28
        radius: 7
        color: Theme.card
        Lbl { x: 10; anchors.verticalCenter: parent.verticalCenter; text: parent.k; mono: true; faint: true; font.pixelSize: 11 }
        Lbl { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } width: parent.width * 0.62
              horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; text: parent.v; mono: true; font.pixelSize: 11 }
    }

    // Generic grid card used by Wallpapers, Anime, Manga and Library.
    component MediaCard: Rectangle {
        id: mc
        property string title: ""
        property string meta: ""
        property string extra: ""
        property string badge: ""
        property string corner: ""
        property string userStatus: ""
        property string src: ""
        property var grad: [Theme.surfaceBase, "#2a1b5e", "#0e4a6b"]
        property string glyph: ""
        property real aspect: 1.6
        property bool selected: false
        property bool fav: false
        property bool showList: false
        property bool listed: false
        property bool showPreview: false
        property bool showSource: false
        property string sourceTip: "Open source"
        property string previewIcon: "eye"
        property string previewTip: "Preview"
        property string primaryLabel: ""
        property string primaryIcon: "play"
        property color accent: Theme.brandAccent
        signal activated()
        signal primary()
        signal previewed()
        signal sourceRequested()
        signal favToggled()
        signal listToggled()
        readonly property real artW: width - 12
        readonly property real artH: artW / aspect
        implicitHeight: artH + 12 + 64
        height: implicitHeight
        radius: 14
        color: hh.hovered ? Theme.surfaceHigh : Theme.card
        border.width: selected ? 2 : 1
        border.color: selected ? accent : (hh.hovered ? Qt.alpha(accent, 0.5) : Theme.outlineSoft)
        scale: hh.hovered ? 1.012 : 1
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        HoverHandler { id: hh }
        Art {
            id: cardArt
            x: 6; y: 6
            width: mc.artW; height: mc.artH
            radiusPx: 10
            frameColor: mc.color
            src: mc.src; grad: mc.grad; glyph: mc.glyph
            zoom: hh.hovered ? 1.05 : 1
        }
        Tag { visible: mc.badge !== ""; x: 14; y: 14; text: mc.badge; tint: mc.accent; px: 9 }
        Tag { visible: mc.corner !== ""; anchors { right: cardArt.right; rightMargin: 8 } y: 14; text: mc.corner; tint: "#7bd0ff"; px: 9 }
        Tag {
            visible: mc.userStatus !== ""
            x: 14; y: cardArt.y + cardArt.height - height - 8
            opacity: hh.hovered ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            text: mc.userStatus; tint: "#86efac"; px: 9
        }
        Rectangle {
            x: cardArt.x; y: cardArt.y + cardArt.height * 0.45
            width: cardArt.width; height: cardArt.height * 0.55
            radius: 10
            opacity: hh.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.track, 0.9) }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mc.activated() }
        RowLayout {
            x: 14
            y: cardArt.y + cardArt.height - 42
            width: mc.artW - 16
            spacing: 6
            opacity: hh.hovered ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Btn { visible: mc.primaryLabel !== ""; compact: true; kind: "primary"; accent: mc.accent; label: mc.primaryLabel; icon: mc.primaryIcon; onClicked: mc.primary() }
            Item { Layout.fillWidth: true }
            IconBtn { visible: mc.showPreview; box: 30; icon: mc.previewIcon; tip: mc.previewTip; onClicked: mc.previewed() }
            IconBtn { visible: mc.showSource; box: 30; icon: "link"; tip: mc.sourceTip; onClicked: mc.sourceRequested() }
            IconBtn { visible: mc.showList; box: 30; icon: mc.listed ? "check" : "plus"; tip: mc.listed ? "Remove from list" : "Add to list"; active: mc.listed; activeTint: "#86efac"; onClicked: mc.listToggled() }
            IconBtn { box: 30; icon: mc.fav ? "heart" : "heartO"; tip: mc.fav ? "Unfavorite" : "Favorite"; active: mc.fav; onClicked: mc.favToggled() }
        }
        Lbl { x: 12; y: cardArt.y + cardArt.height + 9; width: mc.width - 24; text: mc.title; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
        Lbl { x: 12; y: cardArt.y + cardArt.height + 28; width: mc.width - 24; text: mc.meta; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 11 }
        Lbl { x: 12; y: cardArt.y + cardArt.height + 45; width: mc.width - 24; text: mc.extra; elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
    }

    // Continue Watching / Reading shelf card.
    component ShelfCard: Rectangle {
        id: sc
        property string title: ""
        property string sub: ""
        property string badge: ""
        property string src: ""
        property var grad: [Theme.surfaceBase, "#2a1b5e", "#0e4a6b"]
        property string glyph: ""
        property real value: 0
        property string valueLabel: ""
        property string btnLabel: "Continue"
        property string btnIcon: "play"
        property color accent: Theme.brandAccent
        signal activated()
        signal cont()
        readonly property real artW: width - 12
        readonly property real artH: artW * 9 / 16
        implicitHeight: artH + 6 + 78 + 30 + 10
        height: implicitHeight
        radius: 14
        color: shh.hovered ? Theme.surfaceHigh : Theme.card
        border.width: 1
        border.color: shh.hovered ? Qt.alpha(accent, 0.5) : Theme.outlineSoft
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
        HoverHandler { id: shh }
        Art { id: shArt; x: 6; y: 6; width: sc.artW; height: sc.artH; radiusPx: 10; frameColor: sc.color; src: sc.src; grad: sc.grad; glyph: sc.glyph; zoom: shh.hovered ? 1.05 : 1 }
        Tag { visible: sc.badge !== ""; x: 14; y: 14; text: sc.badge; tint: sc.accent; px: 9 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sc.activated() }
        Lbl { x: 12; y: shArt.y + shArt.height + 10; width: sc.width - 24; text: sc.title; elide: Text.ElideRight; font.pixelSize: 14; font.weight: Font.DemiBold }
        Lbl { x: 12; y: shArt.y + shArt.height + 29; width: sc.width - 24; text: sc.sub; elide: Text.ElideRight; dim: true; font.pixelSize: 12 }
        Bar { x: 12; y: shArt.y + shArt.height + 52; width: sc.width - 24; height: 5; value: sc.value; tint: sc.accent }
        Lbl { x: 12; y: shArt.y + shArt.height + 60; text: sc.valueLabel; mono: true; faint: true; font.pixelSize: 10 }
        Btn { x: 12; y: shArt.y + shArt.height + 78; width: sc.width - 24; compact: true; label: sc.btnLabel; icon: sc.btnIcon; accent: sc.accent; onClicked: sc.cont() }
    }

    // ================================================================
    //  MUSIC — Jamendo + Radio Browser + Qt Multimedia playback
    // ================================================================
    readonly property int pgMusic: 4
    readonly property int pgDownloads: 5
    readonly property int pgLibrary: 6

    readonly property var musicSources: [
        { id: "jamendo", name: "Jamendo", sub: "Free Creative Commons music", icon: "music", accent: "#a78bfa" },
        { id: "radio", name: "Internet Radio", sub: "Endless stations via Radio Browser", icon: "cloud", accent: "#7bd0ff" },
        { id: "local", name: "Local files", sub: "Your own music folders", icon: "folder", accent: "#ddb8ff" }
    ]
    readonly property var musicMoods: [
        { name: "Night Drive", vibe: "midnight", tag: "synthwave", accent: "#a78bfa", g: gradients.violet, desc: "Neon synths, wet asphalt" },
        { name: "Dreamy", vibe: "soft", tag: "ambient", accent: "#f9a8d4", g: gradients.rose, desc: "Soft pianos, warm light" },
        { name: "Focus", vibe: "focus", tag: "instrumental", accent: "#b6c4d9", g: gradients.slate, desc: "Low-clutter deep work" },
        { name: "Cosmic", vibe: "cosmic", tag: "ambient", accent: "#7bd0ff", g: gradients.cosmic, desc: "Drones, stars, slow orbits" },
        { name: "Energize", vibe: "", tag: "electronic", accent: "#fbbf24", g: gradients.amber, desc: "Drive and momentum" },
        { name: "Rainy Day", vibe: "", tag: "lofi", accent: "#5eead4", g: gradients.teal, desc: "Lofi, windows and rain" }
    ]
    readonly property var radioGenres: ["All", "Lofi", "Ambient", "Synthwave", "Jazz", "Classical", "Electronic", "Rock", "Soundtrack"]

    // Live catalogue results. Search results are not persisted; favorites and
    // the queue are, with full stream metadata so they survive later searches.
    property var jamendoTracks: []
    property var radioStations: []
    property var localTracks: []
    property bool localLoaded: false
    property bool localLoading: false
    property string localError: ""
    property int localIndexedCount: 0
    property int localSkippedCount: 0
    property int localScanRequestId: 0
    property string localMusicDir: Quickshell.env("GPS_MUSIC_DIR")
        || (Quickshell.env("HOME") + "/Music")
    property var musicFavorites: []
    property bool musicStatusChecked: false
    property bool jamendoConfigured: false
    property string jamendoConfigPath: ""
    property string musicStatusMessage: ""
    property bool jamendoLoaded: false
    property bool radioLoaded: false
    property bool musicLoading: false
    property string musicError: ""
    property string musicErrorCode: ""
    property int musicSearchSeq: 0
    property string musicPlaybackError: ""
    readonly property var mprisPlayer: MediaNowPlaying.player
    property real mprisPositionBase: 0
    property real mprisPositionStamp: 0
    property real mprisTick: 0
    property bool mprisLyricsOpen: false
    readonly property string mprisLyricsKey: mprisPlayer
        ? MediaLyrics.keyFor(
            mprisPlayer.trackArtist,
            mprisPlayer.trackTitle,
            mprisPlayer.trackAlbum,
            mprisPlayer.length
        )
        : ""
    readonly property var mprisLyricsResult: mprisLyricsKey !== ""
        && MediaLyrics.resultKey === mprisLyricsKey ? MediaLyrics.result : null
    readonly property int mprisLyricsLineIndex: {
        const lyrics = mprisLyricsResult
        if (!lyrics || lyrics.status !== "synced") return -1
        let current = -1
        for (let i = 0; i < lyrics.lines.length; i++) {
            if (lyrics.lines[i].t <= mprisPosition) current = i
            else break
        }
        return current
    }
    readonly property real mprisPosition: mprisPlayer
        ? Math.max(0, mprisPositionBase + (mprisPlayer.isPlaying ? (mprisTick - mprisPositionStamp) / 1000 : 0))
        : 0

    function syncMprisPosition() {
        if (!mprisPlayer) return
        mprisPositionBase = mprisPlayer.position
        mprisPositionStamp = Date.now()
        mprisTick = mprisPositionStamp
    }

    function lookupMprisLyrics() {
        if (!mprisPlayer || !mprisPlayer.trackTitle) return false
        MediaLyrics.lookup(
            mprisPlayer.trackArtist,
            mprisPlayer.trackTitle,
            mprisPlayer.trackAlbum,
            mprisPlayer.length
        )
        return true
    }

    onMprisPlayerChanged: {
        root.syncMprisPosition()
        if (root.mprisLyricsOpen) root.lookupMprisLyrics()
    }

    Connections {
        target: root.mprisPlayer
        function onPositionChanged() { root.syncMprisPosition() }
        function onTrackTitleChanged() {
            root.syncMprisPosition()
            if (root.mprisLyricsOpen) root.lookupMprisLyrics()
        }
        function onTrackArtistChanged() {
            if (root.mprisLyricsOpen) root.lookupMprisLyrics()
        }
        function onTrackAlbumChanged() {
            if (root.mprisLyricsOpen) root.lookupMprisLyrics()
        }
        function onLengthChanged() {
            if (root.mprisLyricsOpen) root.lookupMprisLyrics()
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.page === root.pgMusic && root.mprisPlayer !== null && root.mprisPlayer.isPlaying
        onTriggered: root.mprisTick = Date.now()
    }

    property string musicSource: "jamendo"
    property string musicMood: ""
    property string musicView: "Discover"
    property string musicQuery: ""
    property string musicWebSearchQuery: ""
    property string radioGenre: "All"
    property string radioCountry: ""
    property bool queueOpen: true
    property var queue: []
    property int queueIndex: -1
    property bool playing: false
    property real playPos: 0
    property real volume: 0.7
    property bool muted: false
    property bool shuffleOn: false
    property bool repeatOn: false
    property bool pendingMixPlay: false
    property bool pendingMixShuffle: false
    property bool musicStateReady: false
    readonly property var nowPlaying: (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null
    readonly property real currentDuration: audioPlayer.duration > 0
        ? audioPlayer.duration / 1000
        : (nowPlaying && nowPlaying.dur > 0 ? nowPlaying.dur : 0)
    readonly property string musicStatePath: {
        var cfg = Quickshell.env("XDG_CONFIG_HOME")
        if (!cfg) cfg = Quickshell.env("HOME") + "/.config"
        return cfg + "/quickshell/media-hub-music.json"
    }
    readonly property string musicSaveKey: JSON.stringify([
        musicFavorites, queue, queueIndex, musicSource, musicMood,
        volume, muted, shuffleOn, repeatOn, localMusicDir
    ])
    onMusicSaveKeyChanged: if (musicStateReady) musicSaveTimer.restart()
    onNowPlayingChanged: localPlayerStateWriter.save()
    onPlayingChanged: localPlayerStateWriter.save()

    Timer {
        id: musicSearchTimer
        interval: 450
        repeat: false
        onTriggered: root.runMusicSearch()
    }

    Timer {
        id: musicSaveTimer
        interval: 500
        repeat: false
        onTriggered: root.saveMusicState()
    }

    MediaPlayer {
        id: audioPlayer
        source: ""
        audioOutput: AudioOutput {
            id: audioOutput
            volume: root.muted ? 0 : root.volume
        }
        onPlaybackStateChanged: root.playing = playbackState === MediaPlayer.PlayingState
        onPositionChanged: (position) => {
            if (root.nowPlaying && root.nowPlaying.kind === "track")
                root.playPos = Math.max(0, position / 1000)
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                root.skip(1)
            } else if (mediaStatus === MediaPlayer.InvalidMedia && root.nowPlaying) {
                root.notePlaybackError("This stream could not be played. Try another result.")
            }
        }
        onErrorOccurred: (error, errorString) => {
            if (error !== MediaPlayer.NoError && root.nowPlaying)
                root.notePlaybackError(String(errorString || "Playback failed."))
        }
    }

    QtObject {
        id: hubPlayerAdapter
        readonly property string dbusName: "gps.media-hub"
        readonly property string identity: "GPS Media Hub"
        readonly property string desktopEntry: "gps-media-hub"
        readonly property string uniqueId: root.nowPlaying ? root.nowPlaying.id : ""
        readonly property string trackTitle: root.nowPlaying ? root.nowPlaying.title : ""
        readonly property string trackArtist: root.nowPlaying ? root.nowPlaying.artist : ""
        readonly property string trackAlbum: root.nowPlaying
            ? (root.nowPlaying.album || root.nowPlaying.genre || "") : ""
        readonly property string trackAlbumArtist: trackArtist
        readonly property string trackArtUrl: root.nowPlaying ? root.nowPlaying.art : ""
        readonly property string trackArtists: trackArtist
        readonly property bool isPlaying: root.playing
        readonly property real position: root.playPos
        readonly property real length: root.currentDuration
        readonly property bool positionSupported: root.nowPlaying !== null
            && root.nowPlaying.kind === "track" && root.currentDuration > 0
        readonly property bool lengthSupported: positionSupported
        readonly property bool canSeek: positionSupported
        readonly property bool canControl: root.nowPlaying !== null
        readonly property bool canPlay: canControl
        readonly property bool canPause: canControl && isPlaying
        readonly property bool canTogglePlaying: canControl
        readonly property bool canGoPrevious: root.queue.length > 1
            && (root.queueIndex > 0 || root.repeatOn || root.shuffleOn)
        readonly property bool canGoNext: root.queue.length > 1
            && (root.queueIndex < root.queue.length - 1 || root.repeatOn || root.shuffleOn)
        readonly property var playbackState: root.playing
            ? MprisPlaybackState.Playing
            : (root.nowPlaying ? MprisPlaybackState.Paused : MprisPlaybackState.Stopped)

        function play() { if (!root.playing) root.togglePlay() }
        function pause() { if (root.playing) audioPlayer.pause() }
        function togglePlaying() { root.togglePlay() }
        function next() { root.skip(1) }
        function previous() { root.skip(-1) }
        function stop() { root.stopPlayer() }
        function seekTo(seconds) {
            if (!positionSupported) return
            root.seekFrac(Math.max(0, Math.min(1, Number(seconds) / length)))
        }
        function seek(offset) { seekTo(position + Number(offset)) }
    }

    FileView {
        id: localPlayerStateFile
        path: MediaNowPlaying.localStatePath
        printErrors: false
    }

    FileView {
        id: musicStateFile
        path: root.musicStatePath
        printErrors: false
        onLoaded: {
            root.applyMusicState(MusicQueue.parseState(musicStateFile.text(), root.defaultMusicState()))
            root.musicStateReady = true
        }
        onLoadFailed: root.musicStateReady = true
    }

    Connections {
        target: HubProvider
        function onSucceeded(requestId, payload) {
            if (requestId !== root.localScanRequestId) return
            root.handleLocalLibrary(payload, requestId)
        }
        function onFailed(requestId, error) {
            if (requestId !== root.localScanRequestId) return
            root.localLoading = false
            root.localError = error && error.message ? error.message : "The local music scan failed."
        }
    }

    onMusicQueryChanged: if (page === pgMusic) scheduleMusicSearch()
    onMusicMoodChanged: if (page === pgMusic) scheduleMusicSearch()
    onMusicViewChanged: if (page === pgMusic) scheduleMusicSearch()
    onRadioGenreChanged: if (page === pgMusic && musicSource === "radio") scheduleMusicSearch()
    onRadioCountryChanged: if (page === pgMusic && musicSource === "radio") scheduleMusicSearch()

    function fmtTime(s) {
        s = Math.max(0, Math.floor(s))
        var r = s % 60
        return Math.floor(s / 60) + ":" + (r < 10 ? "0" : "") + r
    }
    function musicMoodFor(vibeId) {
        for (var i = 0; i < musicMoods.length; i++) if (musicMoods[i].vibe === vibeId) return musicMoods[i].name
        return ""
    }
    function moodInfo(name) {
        for (var i = 0; i < musicMoods.length; i++) if (musicMoods[i].name === name) return musicMoods[i]
        return null
    }
    function musicTagForMood(name) {
        var info = moodInfo(name)
        return info ? info.tag : ""
    }
    function musicSourceState(id) {
        if (id === "jamendo") {
            if (musicLoading && musicSource === "jamendo") return "SEARCHING"
            if (musicError !== "" && musicSource === "jamendo") return "OFFLINE"
            return jamendoConfigured ? "LIVE CATALOGUE" : "SETUP REQUIRED"
        }
        if (id === "radio") {
            if (musicLoading && musicSource === "radio") return "SEARCHING"
            return musicError !== "" && musicSource === "radio" ? "OFFLINE" : (radioLoaded ? "LIVE DIRECTORY" : "READY")
        }
        if (id === "local") {
            if (localLoading) return "SCANNING"
            if (localError !== "") return "UNAVAILABLE"
            return localLoaded ? (localIndexedCount + " TRACKS") : "READY"
        }
        return "UNAVAILABLE"
    }
    function musicSourceTint(id) {
        if (id === "jamendo") {
            if (musicError !== "" && musicSource === "jamendo") return "#ffb4ab"
            return jamendoConfigured ? "#86efac" : "#fde047"
        }
        if (id === "radio") return musicError !== "" && musicSource === "radio" ? "#ffb4ab" : "#7bd0ff"
        return localError !== "" && musicSource === "local" ? "#ffb4ab" : (localLoaded ? "#ddb8ff" : "#948e9d")
    }
    function setMusicSource(id) {
        musicSource = id
        musicView = id === "radio" ? "Popular" : "Discover"
        radioGenre = "All"
        radioCountry = ""
        musicQuery = ""
        musicError = ""
        musicErrorCode = ""
        musicLoading = false
        pendingMixPlay = false
        pendingMixShuffle = false
        if (id === "local")
            reloadLocalLibrary()
        else
            scheduleMusicSearch()
    }

    function reloadLocalLibrary() {
        const directory = localMusicDir.trim()
        if (directory === "" || directory.charAt(0) !== "/") {
            localError = "Choose an absolute music folder path."
            return false
        }
        localLoading = true
        localError = ""
        localScanRequestId = HubProvider.run("media-hub-library.py", ["scan", directory])
        if (localScanRequestId < 0) {
            localLoading = false
            localError = HubProvider.error && HubProvider.error.message
                ? HubProvider.error.message : "Could not start the local music scan."
            return false
        }
        return true
    }

    function setLocalMusicDirectory(directory) {
        const value = String(directory || "").trim()
        if (value === "" || value.charAt(0) !== "/") {
            localError = "Choose a valid absolute music folder."
            return false
        }
        localMusicDir = value
        localTracks = []
        localLoaded = false
        localIndexedCount = 0
        localSkippedCount = 0
        localError = ""
        if (musicSource === "local") reloadLocalLibrary()
        return true
    }

    function handleLocalLibrary(payload, requestId) {
        if (requestId !== localScanRequestId) return
        if (!payload || !MusicQueue.isArrayLike(payload.results)) {
            localLoading = false
            localError = "The local music provider returned an invalid index."
            return
        }
        localTracks = MusicQueue.sanitizeLibraryList(payload.results)
        localIndexedCount = localTracks.length
        localSkippedCount = Number.isInteger(payload.skipped) && payload.skipped >= 0 ? payload.skipped : 0
        localLoaded = true
        localLoading = false
        localError = ""
        logActivity("Local music: indexed " + localIndexedCount + " track(s)")
    }
    function scheduleMusicSearch() {
        if (page !== pgMusic || musicSource === "local") return
        if (!musicStatusChecked) return
        if (musicSource === "jamendo" && !jamendoConfigured) return
        if (musicView === "Favorites") return
        musicSearchTimer.restart()
    }
    function runMusicSearch() {
        if (page !== pgMusic || musicSource === "local" || !musicStatusChecked) return
        if (musicSource === "jamendo" && !jamendoConfigured) return
        if (musicView === "Favorites") return
        var moodTag = musicTagForMood(musicMood)
        var tag = musicSource === "radio" && radioGenre !== "All" ? radioGenre : moodTag
        var order = "popularity_total"
        if (musicSource === "radio") {
            order = "clickcount"
        } else if (musicView === "Trending") {
            order = "popularity_week"
        } else if (musicView === "New") {
            order = "releasedate_desc"
        }
        musicSearchSeq++
        musicLoading = true
        musicError = ""
        musicErrorCode = ""
        var request = {
            seq: musicSearchSeq,
            source: musicSource,
            query: musicQuery.trim(),
            tag: tag,
            country: radioCountry.trim(),
            order: order,
            mood: musicMood,
            limit: 40,
            offset: 0
        }
        if (!musicBackend.search(request)) {
            musicLoading = false
            musicError = "Could not start the music search."
            musicErrorCode = "invalid_request"
        }
    }
    function handleMusicStatus(configured, path, message) {
        musicStatusChecked = true
        jamendoConfigured = configured
        jamendoConfigPath = path
        musicStatusMessage = message
        if (page === pgMusic) {
            if (musicSource === "jamendo" && !configured) return
            scheduleMusicSearch()
        }
    }
    function handleMusicSearch(payload, request) {
        if (!request || request.seq !== musicSearchSeq || request.source !== musicSource) return
        var incoming = MusicQueue.sanitizeList(payload.results, 60)
        if (request.mood !== "") {
            for (var m = 0; m < incoming.length; m++) {
                if (incoming[m].moods.indexOf(request.mood) < 0)
                    incoming[m].moods = incoming[m].moods.concat([request.mood])
            }
        }
        var firstLoad = request.source === "jamendo" ? !jamendoLoaded : !radioLoaded
        if (request.source === "jamendo") {
            jamendoTracks = incoming
            jamendoLoaded = true
        } else {
            radioStations = incoming
            radioLoaded = true
        }
        musicLoading = false
        musicError = ""
        musicErrorCode = ""
        logActivity((request.source === "jamendo" ? "Jamendo: " : "Radio Browser: ") + incoming.length + " result(s)")
        if (pendingMixPlay) {
            pendingMixPlay = false
            var mix = request.source === "jamendo" ? filteredTracks() : filteredStations()
            var shuffle = pendingMixShuffle
            pendingMixShuffle = false
            if (mix.length === 0)
                notify("No playable results for this mix. Try another mood or search.", "info")
            else
                playAll(mix, shuffle)
        } else if (firstLoad && incoming.length > 0) {
            notify((request.source === "jamendo" ? "Jamendo" : "Radio Browser") + " connected \u2014 " + incoming.length + " live result(s).", "ok")
        }
    }
    function handleMusicSearchFailure(message, code, request) {
        if (!request || request.seq !== musicSearchSeq || request.source !== musicSource) return
        musicLoading = false
        musicError = message
        musicErrorCode = code
        pendingMixPlay = false
        pendingMixShuffle = false
        if (code === "jamendo_unconfigured") {
            jamendoConfigured = false
            musicStatusMessage = message
            musicError = ""
            musicErrorCode = ""
        } else {
            notify("Music search failed: " + message, "warn")
        }
        logActivity("Music search failed: " + code)
    }
    function defaultMusicState() {
        return {
            favorites: musicFavorites,
            queue: queue,
            queueIndex: queueIndex,
            source: musicSource,
            localMusicDir: localMusicDir,
            mood: musicMood,
            volume: volume,
            muted: muted,
            shuffleOn: shuffleOn,
            repeatOn: repeatOn
        }
    }
    function applyMusicState(state) {
        if (!state) return
        musicFavorites = MusicQueue.sanitizeList(state.favorites, 200)
        queue = MusicQueue.sanitizeList(state.queue, 200)
        queueIndex = MusicQueue.normalizeIndex(state.queueIndex, queue.length)
        musicSource = state.source
        localMusicDir = state.localMusicDir || localMusicDir
        musicView = musicSource === "radio" ? "Popular" : "Discover"
        musicMood = moodInfo(state.mood) ? state.mood : ""
        volume = state.volume
        muted = state.muted
        shuffleOn = state.shuffleOn
        repeatOn = state.repeatOn
        var fav = Object.assign({}, favorites)
        for (var i = 0; i < musicFavorites.length; i++) fav[musicFavorites[i].id] = true
        favorites = fav
        if (page === pgMusic) {
            if (musicSource === "local") reloadLocalLibrary()
            else scheduleMusicSearch()
        }
    }
    function saveMusicState() {
        if (!musicStateReady) return
        musicStateFile.setText(JSON.stringify({
            favorites: musicFavorites,
            queue: queue,
            queueIndex: queueIndex,
            source: musicSource,
            localMusicDir: localMusicDir,
            mood: musicMood,
            volume: volume,
            muted: muted,
            shuffleOn: shuffleOn,
            repeatOn: repeatOn
        }, null, 2))
    }
    function musicRef(it) { return MusicQueue.sanitizeItem(it) }
    function musicItem(ref) {
        if (!ref) return null
        var clean = MusicQueue.sanitizeItem(ref)
        if (clean) return clean
        var lists = [jamendoTracks, radioStations, localTracks, musicFavorites]
        for (var i = 0; i < lists.length; i++) {
            var found = findIn(lists[i], ref.id)
            if (found) return MusicQueue.sanitizeItem(found)
        }
        return null
    }
    function findMusicItem(id) {
        var lists = [jamendoTracks, radioStations, localTracks, musicFavorites, queue]
        for (var i = 0; i < lists.length; i++) {
            var found = findIn(lists[i], id)
            if (found) return MusicQueue.sanitizeItem(found)
        }
        return null
    }
    function filteredTracks() {
        var q = musicQuery.trim().toLowerCase(), out = []
        var list = musicView === "Favorites"
            ? musicFavorites.filter(function (it) {
                return it.kind === "track" && (musicSource !== "local" || it.id.indexOf("local:") === 0)
            })
            : (musicSource === "local" ? localTracks : jamendoTracks)
        for (var i = 0; i < list.length; i++) {
            var t = list[i]
            if (musicSource !== "local" && musicMood !== "" && t.moods.indexOf(musicMood) < 0) continue
            if (q && (t.title + " " + t.artist + " " + t.album + " " + t.genre).toLowerCase().indexOf(q) < 0) continue
            out.push(t)
        }
        return musicSource === "local" ? out.slice(0, 200) : out
    }
    function filteredStations() {
        var q = musicQuery.trim().toLowerCase(), out = []
        var list = musicView === "Favorites"
            ? musicFavorites.filter(function (it) { return it.kind === "station" })
            : radioStations
        for (var i = 0; i < list.length; i++) {
            var s = list[i]
            if (musicMood !== "" && s.moods.indexOf(musicMood) < 0) continue
            if (radioGenre !== "All" && s.genre.toLowerCase().indexOf(radioGenre.toLowerCase()) < 0) continue
            if (q && (s.title + " " + s.genre + " " + s.country).toLowerCase().indexOf(q) < 0) continue
            out.push(s)
        }
        return out
    }
    function musicSub(it) {
        if (!it) return ""
        if (it.kind === "station") {
            var quality = it.bitrate > 0 ? (it.bitrate + " kbps") : "live stream"
            return (it.genre || "Radio") + " \u00b7 " + (it.codec || "audio") + " \u00b7 " + quality
        }
        return it.artist + (it.album ? (" \u00b7 " + it.album) : "")
    }
    function openMusicWebSearch(service) {
        const query = musicWebSearchQuery.trim()
        if (query === "") return false

        const encoded = encodeURIComponent(query)
        let url = ""
        if (service === "youtube")
            url = "https://music.youtube.com/search?q=" + encoded
        else if (service === "jiosaavn")
            url = "https://www.jiosaavn.com/search/song/" + encoded
        else if (service === "spotify")
            url = "https://open.spotify.com/search/" + encoded
        else
            return false

        Quickshell.execDetached(["xdg-open", url])
        return true
    }
    function startCurrent() {
        if (!nowPlaying) return
        MediaNowPlaying.automaticPlayerSelection()
        musicPlaybackError = ""
        playPos = 0
        audioPlayer.source = nowPlaying.streamUrl
        audioPlayer.play()
    }
    function playNow(item, context) {
        var chosen = musicRef(item)
        if (!chosen) {
            notify("This item has no playable stream.", "warn")
            return
        }
        var list = MusicQueue.sanitizeList((context && context.length > 0) ? context : [chosen], 200)
        var idx = -1
        for (var i = 0; i < list.length; i++) if (list[i].id === chosen.id) idx = i
        if (idx < 0) {
            list.unshift(chosen)
            idx = 0
        }
        queue = list
        queueIndex = idx
        startCurrent()
        markOpened(chosen.id)
        logActivity("Playing: " + chosen.title)
    }
    function playAll(list, shuffled) {
        if (!list || list.length === 0) { notify("Nothing to play with the current filters.", "info"); return }
        var l = shuffled ? MusicQueue.shuffle(list, Math.random) : MusicQueue.sanitizeList(list, 200)
        if (l.length === 0) { notify("Nothing playable in this list.", "info"); return }
        playNow(l[0], l)
    }
    function playCurrentMusicList(shuffled) {
        var list = musicSource === "radio" ? filteredStations() : filteredTracks()
        if (list.length > 0) {
            playAll(list, shuffled)
            return
        }
        if (musicSource === "local") {
            notify(localLoading ? "The local library is still scanning." : "No local tracks match the current search.", "info")
            return
        }
        if (musicSource === "jamendo" && !jamendoConfigured) {
            notify("Add a Jamendo client ID to load a live mix.", "warn")
            return
        }
        if (musicView === "Favorites") {
            notify("No favorite " + (musicSource === "jamendo" ? "tracks" : "stations") + " yet.", "info")
            return
        }
        pendingMixPlay = true
        pendingMixShuffle = shuffled
        runMusicSearch()
        if (musicLoading) notify("Loading a live mix\u2026", "info")
    }
    function queueAdd(item, next) {
        var result = MusicQueue.queueAdd(queue, queueIndex, item, next)
        queue = result.queue
        queueIndex = result.index
        notify((next ? "Playing next: " : "Added to queue: ") + item.title, "ok")
    }
    function removeFromQueue(i) {
        var wasPlaying = playing
        var result = MusicQueue.removeAt(queue, i, queueIndex)
        queue = result.queue
        queueIndex = result.index
        if (!result.removedCurrent) return
        if (result.index < 0) {
            stopPlayer()
        } else if (wasPlaying) {
            startCurrent()
        } else {
            audioPlayer.stop()
            audioPlayer.source = ""
            playing = false
            playPos = 0
        }
    }
    function clearQueue() {
        if (queueIndex >= 0) {
            queue = [queue[queueIndex]]
            queueIndex = 0
        } else {
            queue = []
        }
    }
    function moveQueue(i, d) {
        var current = MusicQueue.movedIndex(queueIndex, i, d)
        queue = MusicQueue.move(queue, i, d)
        queueIndex = current
    }
    function jumpQueue(i) {
        if (i < 0 || i >= queue.length) return
        queueIndex = i
        startCurrent()
    }
    function skip(dir) {
        var n = queue.length
        if (n === 0) return
        var idx
        if (shuffleOn && n > 1) {
            do { idx = Math.floor(Math.random() * n) } while (idx === queueIndex)
        } else {
            idx = queueIndex + dir
        }
        if (idx < 0) idx = repeatOn ? n - 1 : 0
        if (idx >= n) {
            if (repeatOn) {
                idx = 0
            } else {
                audioPlayer.stop()
                audioPlayer.source = ""
                playing = false
                playPos = 0
                return
            }
        }
        queueIndex = idx
        startCurrent()
    }
    function togglePlay() {
        if (!nowPlaying && queue.length > 0) queueIndex = 0
        if (!nowPlaying) return
        if (audioPlayer.playbackState === MediaPlayer.PlayingState) {
            audioPlayer.pause()
        } else if (audioPlayer.playbackState === MediaPlayer.PausedState
                   && audioPlayer.source === nowPlaying.streamUrl) {
            audioPlayer.play()
        } else {
            startCurrent()
        }
    }
    function seekFrac(f) {
        if (!nowPlaying || nowPlaying.kind !== "track") return
        var value = Math.max(0, Math.min(1, f))
        var total = currentDuration > 0 ? currentDuration : nowPlaying.dur
        playPos = value * total
        audioPlayer.position = Math.round(playPos * 1000)
    }
    function stopPlayer() {
        audioPlayer.stop()
        audioPlayer.source = ""
        playing = false
        queueIndex = -1
        playPos = 0
        musicPlaybackError = ""
    }
    function notePlaybackError(message) {
        if (musicPlaybackError !== "") return
        musicPlaybackError = String(message || "Playback failed.")
        playing = false
        notify("Playback failed: " + musicPlaybackError, "warn")
        logActivity("Playback failed: " + musicPlaybackError)
    }
    function exploreMusicMood(name) {
        musicMood = name
        if (musicSource === "local") setMusicSource("jamendo")
        page = pgMusic
        vibeOpen = false
    }
    function playVibeMix() {
        var name = musicMoodFor(moodId)
        if (name === "") name = "Focus"
        musicMood = name
        if (musicSource === "local") setMusicSource("jamendo")
        playCurrentMusicList(false)
    }
    function openMusicSource(url) {
        var safe = MusicQueue.safeWebUrl(url)
        if (safe !== "") sourceLinkRequested(safe)
    }

    // ================================================================
    //  SHELL LAYOUT
    // ================================================================
    readonly property var navItems: [
        { name: "Home", icon: "home" },
        { name: "Wallpapers", icon: "wallpaper" },
        { name: "Anime", icon: "anime" },
        { name: "Manga & Manhwa", icon: "manga" },
        { name: "Music", icon: "music" },
        { name: "Downloads", icon: "download" },
        { name: "My Library", icon: "library" }
    ]
    readonly property var pageComponents: [homePage, wallPage, animePage, mangaPage, musicPage, dlPage, libPage]

    // tapping empty space drops keyboard focus (closes search results)
    TapHandler { onTapped: root.forceActiveFocus() }

    Rectangle {
        anchors.fill: parent
        color: pal.bg
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 280
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(root.accent, 0.10) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // ---------------------------------------------------------------- sidebar
    Rectangle {
        id: sidebar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: root.sidebarW
        color: pal.lowest
        z: 10
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            x: root.compact ? 19 : 16
            y: 18
            spacing: 10
            Rectangle {
                width: 30; height: 30; radius: 9; color: root.accent
                Ico { anchors.centerIn: parent; name: "surprise"; size: 15; tint: pal.onAcc }
            }
            Column {
                visible: !root.compact
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Lbl { text: "GPS HUB"; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0.6 }
                Lbl { text: "media hub"; mono: true; faint: true; font.pixelSize: 10 }
            }
        }

        Item {
            id: navBox
            x: 8; y: 74
            width: parent.width - 16
            height: root.navItems.length * 44
            Rectangle {
                id: navInd
                width: parent.width; height: 40; radius: 11
                y: root.page * 44
                color: Qt.alpha(root.accent, 0.15)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.35)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Rectangle { x: -1; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 18; radius: 2; color: root.accent }
            }
            Repeater {
                model: root.navItems
                delegate: Item {
                    id: ni
                    y: index * 44
                    width: navBox.width
                    height: 40
                    readonly property bool cur: root.page === index
                    HoverHandler { id: nh }
                    Rectangle {
                        anchors.fill: parent; radius: 11; color: pal.cont
                        opacity: (!ni.cur && nh.hovered) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.compact ? (ni.width - 18) / 2 : 14
                        spacing: 12
                        Ico { width: 18; name: modelData.icon; size: 15; tint: ni.cur ? root.accent : pal.dim; anchors.verticalCenter: parent.verticalCenter }
                        Lbl {
                            visible: !root.compact
                            text: modelData.name
                            font.weight: ni.cur ? Font.DemiBold : Font.Medium
                            color: ni.cur ? pal.text : pal.dim
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        visible: !root.compact && index === 5 && root.dlCount("downloading") > 0
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 20; height: 18; radius: 9
                        color: Qt.alpha("#7bd0ff", 0.2)
                        Lbl { anchors.centerIn: parent; text: root.dlCount("downloading"); mono: true; font.pixelSize: 10; color: "#7bd0ff" }
                    }
                    MouseArea {
                        id: nma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.go(index)
                    }
                    ToolTip.visible: root.compact && nma.containsMouse
                    ToolTip.text: modelData.name
                    ToolTip.delay: 350
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            spacing: 12
            IconBtn {
                visible: root.compact
                anchors.horizontalCenter: parent.horizontalCenter
                box: 40; icon: "vibe"; tip: "Vibe Studio"
                onClicked: root.vibeOpen = !root.vibeOpen
            }
            Rectangle {
                visible: !root.compact
                width: parent.width; height: 100; radius: 12; color: pal.low
                Lbl { x: 12; y: 10; text: "VIBE STUDIO"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                Grid {
                    x: 8; y: 32
                    columns: 2
                    spacing: 4
                    Repeater {
                        model: root.moods
                        delegate: Rectangle {
                            width: 82; height: 28; radius: 8
                            readonly property bool sel: root.moodId === modelData.id
                            color: sel ? Qt.alpha(modelData.accent, 0.18) : (mh.containsMouse ? pal.high : pal.cont)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 8; spacing: 6
                                Rectangle { width: 7; height: 7; radius: 3.5; color: modelData.accent; anchors.verticalCenter: parent.verticalCenter }
                                Lbl { text: modelData.name.split(" ")[0]; mono: true; font.pixelSize: 10; color: sel ? pal.text : pal.dim }
                            }
                            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setMood(modelData.id) }
                        }
                    }
                }
            }
            Column {
                visible: !root.compact
                width: parent.width
                spacing: 3
                RowLayout { width: parent.width
                    Lbl { text: "Wallhaven"; mono: true; faint: true; font.pixelSize: 10 }
                    Item { Layout.fillWidth: true }
                    Lbl { text: root.wallhavenConnected ? "Live" : "Offline"; mono: true; font.pixelSize: 10; color: root.wallhavenConnected ? "#86efac" : "#fde047" }
                }
                RowLayout { width: parent.width
                    Lbl { text: "Catalogue"; mono: true; faint: true; font.pixelSize: 10 }
                    Item { Layout.fillWidth: true }
                    Lbl { text: root.wallhavenUsingRemote ? "Wallhaven" : "Wallhaven samples"; mono: true; font.pixelSize: 10; dim: true }
                }
            }
        }
    }

    // ---------------------------------------------------------------- main area
    Item {
        id: mainArea
        anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom }

        Item {
            id: topbar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 62
            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                spacing: 10
                SearchField {
                    id: gsearch
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    Layout.maximumWidth: 520
                    Layout.preferredHeight: 38
                    accent: root.accent
                    placeholder: root.width < 700 ? "Search… or paste URL" : "Search wallpapers, anime, manga \u2014 or paste a URL"
                    onEdited: root.gq = text
                    onSubmitted: {
                        var r = root.globalResults(root.gq)
                        if (r.length > 0) root.openResult(r[0])
                    }
                }
                Item { Layout.fillWidth: true }
                Btn { label: root.width < 1100 ? "" : "Surprise Me"; icon: "surprise"; onClicked: root.surprise() }
                Btn {
                    label: root.width < 1100 ? "" : "Vibe Studio"
                    icon: "vibe"
                    accent: root.accent
                    kind: root.vibeOpen ? "primary" : "secondary"
                    onClicked: root.vibeOpen = !root.vibeOpen
                }
                Rectangle {
                    visible: root.width >= 1000
                    implicitHeight: 30
                    implicitWidth: strow.implicitWidth + 22
                    radius: 15
                    color: pal.low
                    border.width: 1
                    border.color: pal.line
                    Row {
                        id: strow
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle { width: 8; height: 8; radius: 4; color: root.wallhavenConnected ? "#86efac" : "#fde047"; anchors.verticalCenter: parent.verticalCenter }
                        Lbl { text: "Wallhaven \u00b7 AniList \u00b7 Radio"; mono: true; font.pixelSize: 11; dim: true }
                    }
                }
                IconBtn {
                    visible: root.showCloseButton
                    box: 32
                    icon: "close"
                    tip: "Close Media Hub"
                    onClicked: root.closeRequested()
                }
            }
        }

        Item {
            id: pageHost
            anchors { left: parent.left; right: parent.right; top: topbar.bottom; bottom: parent.bottom; bottomMargin: miniPlayer.height }
            Repeater {
                model: 7
                delegate: Item {
                    id: slot
                    anchors.fill: parent
                    readonly property bool current: root.page === index
                    property bool seen: false
                    onCurrentChanged: if (current) seen = true
                    Component.onCompleted: if (current) seen = true
                    opacity: current ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    transform: Translate {
                        y: slot.current ? 0 : 14
                        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                    Loader { anchors.fill: parent; active: slot.seen; sourceComponent: root.pageComponents[index] }
                }
            }
        }
    }

    // ---------------------------------------------------------------- global search results
    Rectangle {
        id: results
        readonly property var items: root.globalResults(root.gq)
        x: root.sidebarW + 24
        y: 56
        width: gsearch.width
        height: Math.min(items.length, 7) * 46 + 12
        z: 40
        radius: 14
        color: Qt.alpha(pal.low, 0.96)
        border.width: 1
        border.color: pal.line
        opacity: (root.gq.trim() !== "" && gsearch.focused) ? 1 : 0
        visible: opacity > 0.01 && items.length > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Column {
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: results.items
                delegate: Rectangle {
                    width: parent.width; height: 46; radius: 10
                    color: rh.containsMouse ? pal.high : "transparent"
                    Rectangle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 8; color: Qt.alpha(root.accent, 0.16)
                        Ico { anchors.centerIn: parent; size: 13; tint: root.accent
                              name: modelData.kind === "wallpaper" ? "wallpaper" : (modelData.kind === "anime" ? "anime" : (modelData.kind === "manga" ? "manga" : (modelData.kind === "url" ? "download" : "library"))) }
                    }
                    Column {
                        x: 46; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60
                        Lbl { width: parent.width; text: modelData.title; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Lbl { width: parent.width; text: modelData.sub; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 10 }
                    }
                    MouseArea { id: rh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openResult(modelData) }
                }
            }
        }
    }

    // ---------------------------------------------------------------- Vibe Studio panel
    Item {
        id: vibeLayer
        anchors.fill: parent
        z: 60
        opacity: root.vibeOpen ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: root.vibeOpen = false }
        Rectangle {
            id: vpanel
            anchors { top: parent.top; topMargin: 58; right: parent.right; rightMargin: 16 }
            width: Math.min(400, parent.width - 32)
            height: Math.min(parent.height - 80, vcol.implicitHeight + 36)
            radius: 18
            color: Qt.alpha(pal.low, 0.96)
            border.width: 1
            border.color: pal.line
            transform: Translate { y: root.vibeOpen ? 0 : -10; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: vcol
                x: 18; y: 18
                width: parent.width - 36
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Lbl { text: "Vibe Studio"; font.pixelSize: 16; font.weight: Font.Bold }
                    Item { Layout.fillWidth: true }
                    IconBtn { box: 28; icon: "close"; onClicked: root.vibeOpen = false }
                }
                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12
                      text: "Pick a mood to restyle this panel and browse matching wallpapers. Presets don't touch your desktop theme." }
                Repeater {
                    model: root.moods
                    delegate: Rectangle {
                        id: vrow
                        readonly property bool sel: root.moodId === modelData.id
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        radius: 12
                        color: vrh.containsMouse ? pal.high : pal.cont
                        border.width: sel ? 2 : 1
                        border.color: sel ? modelData.accent : pal.line
                        Art { x: 8; y: 8; width: 104; height: 68; radiusPx: 8; frameColor: vrow.color; src: root.artUrl(modelData.art); grad: modelData.grad; glyph: "vibe" }
                        MouseArea { id: vrh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setMood(modelData.id) }
                        Lbl { x: 124; y: 10; text: modelData.name; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Lbl { x: 124; y: 29; width: parent.width - 134; text: modelData.desc; elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
                        Row { x: 124; y: 52; spacing: 5
                            Repeater { model: modelData.palette; delegate: Rectangle { width: 12; height: 12; radius: 6; color: modelData; border.width: 1; border.color: "#33ffffff" } }
                        }
                        Btn { anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 8 } compact: true; label: "Explore"; onClicked: root.exploreMood(modelData.id) }
                    }
                }
                Btn { Layout.fillWidth: true; label: "Sync GPS Theme"; icon: "sync"; muted: true; onClicked: root.syncThemeUnavailable() }
                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                      text: "Unavailable until the GPS theme engine is connected to themeSyncRequested." }
            }
        }
    }

    // ---------------------------------------------------------------- Anime / Manga detail sheet
    Item {
        id: detailLayer
        anchors.fill: parent
        z: 70
        opacity: root.detailShown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Rectangle { anchors.fill: parent; color: Qt.alpha(pal.bg, 0.85); MouseArea { anchors.fill: parent; onClicked: root.closeDetail() } }
        Rectangle {
            id: dpanel
            anchors.centerIn: parent
            width: Math.min(860, parent.width - 64)
            height: Math.min(580, parent.height - 64)
            radius: 20
            color: pal.low
            border.width: 1
            border.color: pal.line
            scale: root.detailShown ? 1 : 0.97
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }
            Loader { anchors.fill: parent; active: root.detailShown !== null; sourceComponent: detailBody }
            IconBtn { anchors { top: parent.top; right: parent.right; margins: 14 } icon: "close"; tip: "Close"; onClicked: root.closeDetail() }
        }
    }

    FileDialog {
        id: localVideoDialog
        title: "Open a local video"
        fileMode: FileDialog.OpenFile
        nameFilters: [
            "Video files (*.mp4 *.mkv *.webm *.mov *.avi *.m4v *.ts *.m2ts *.ogv *.flv *.wmv)",
            "All files (*)"
        ]
        onAccepted: root.launchLocalVideo(selectedFile)
    }

    FolderDialog {
        id: localMusicFolderDialog
        title: "Choose a music folder"
        currentFolder: Qt.resolvedUrl(root.localMusicDir)
        onAccepted: root.setLocalMusicDirectory(selectedFolder.toLocalFile())
    }

    // ---------------------------------------------------------------- toast
    Rectangle {
        id: toast
        z: 100
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 + miniPlayer.height }
        width: Math.min(580, root.width - 48)
        height: Math.max(46, toastLbl.implicitHeight + 24)
        radius: 13
        color: Qt.alpha(pal.low, 0.96)
        border.width: 1
        border.color: root.toastKind === "warn" ? Qt.alpha(pal.warn, 0.45) : (root.toastKind === "ok" ? Qt.alpha(pal.ok, 0.45) : pal.line)
        opacity: root.toastShown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
        transform: Translate { y: root.toastShown ? 0 : 12; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }
        Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                    color: root.toastKind === "warn" ? pal.warn : (root.toastKind === "ok" ? pal.ok : "#7bd0ff") }
        Lbl { id: toastLbl; x: 36; y: 12; width: parent.width - 52; wrapMode: Text.WordWrap; text: root.toastText; font.pixelSize: 13 }
    }

    // ================================================================
    //  DETAIL SHEET CONTENT (anime + manga share it)
    // ================================================================
    Component {
        id: detailBody
        Item {
            id: db
            readonly property var d: root.detailShown
            readonly property bool isA: d.kind === "anime"
            readonly property int total: d.total
            readonly property int cur: root.progress[d.id] || 0
            readonly property string st: root.statuses[d.id] || ""
            readonly property var statusOpts: isA ? root.animeStatuses : root.mangaStatuses
            readonly property color tint: isA ? "#7bd0ff" : "#ddb8ff"
            readonly property string unit: isA ? "Ep" : "Ch"
            readonly property string metaLabel: isA
                ? (d.seasonLabel || (d.year > 0 ? String(d.year) : "Year unknown"))
                : (d.type + (d.countryLabel !== "" ? " \u00b7 " + d.countryLabel
                    : (d.year > 0 ? " \u00b7 " + d.year : "")))
            RowLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 24
                Art {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 330
                    Layout.alignment: Qt.AlignTop
                    radiusPx: 14
                    frameColor: pal.low
                    src: root.artUrl(db.d.cover)
                    grad: db.d.g
                    glyph: db.isA ? "anime" : "manga"
                }
                Flickable {
                    id: df
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: dcol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: VScroll {}
                    ColumnLayout {
                        id: dcol
                        width: df.width - 12
                        spacing: 12
                        Art {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            visible: db.d.banner !== ""
                            radiusPx: 12
                            frameColor: pal.low
                            src: root.artUrl(db.d.banner)
                            grad: db.d.g
                            glyph: db.isA ? "anime" : "manga"
                        }
                        Lbl { Layout.fillWidth: true; Layout.rightMargin: 40; text: db.d.title; wrapMode: Text.WordWrap; font.pixelSize: 26; font.weight: Font.Bold }
                        Lbl { Layout.fillWidth: true; visible: db.d.altTitles && db.d.altTitles.length > 0
                              text: db.d.altTitles ? db.d.altTitles.slice(0, 3).join(" \u00b7 ") : ""
                              wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12 }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 6
                            Tag { text: db.metaLabel; tint: db.tint }
                            Tag { text: db.d.statusLabel }
                            Tag { visible: db.d.score > 0; text: "\u2605 " + db.d.scoreLabel; tint: "#fde047" }
                            Tag { visible: db.isA && db.d.studios.length > 0; text: db.d.studios.join(", ") }
                            Tag { visible: !db.isA && db.d.author !== ""; text: db.d.author }
                            Tag { text: db.total > 0 ? db.total + (db.isA ? " episodes" : " chapters") : (db.isA ? "Episode count unknown" : "Chapter count unknown") }
                            Tag { visible: !db.isA && db.d.volumes > 0; text: db.d.volumes + " volumes" }
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater { model: db.d.genres; delegate: Tag { text: modelData; tint: "#a78bfa" } }
                        }
                        Lbl { Layout.fillWidth: true; text: db.d.description; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 13; lineHeight: 1.25 }
                        Lbl { text: db.isA ? "YOUR WATCH STATUS" : "YOUR READING STATUS"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: db.statusOpts
                                delegate: Chip { label: modelData; active: db.st === modelData; accent: db.tint; onClicked: root.setStatus(db.d.id, modelData) }
                            }
                            Btn { visible: db.st !== ""; compact: true; kind: "ghost"; label: "Remove from list"; icon: "close"; onClicked: root.toggleList(db.d.kind, db.d.id, db.d.title) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Lbl { text: db.isA ? "EPISODE PROGRESS" : "CHAPTER PROGRESS"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                            Item { Layout.fillWidth: true }
                            IconBtn { box: 28; icon: "minus"; tip: "One back"; onClicked: root.setProgress(db.d.id, db.cur - 1, db.total) }
                            Lbl { text: db.unit + " " + db.cur + " / " + (db.total > 0 ? db.total : "?"); mono: true; font.pixelSize: 12; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignHCenter }
                            IconBtn { box: 28; icon: "plus"; tip: "Mark next as done"; onClicked: root.setProgress(db.d.id, db.cur + 1, db.total) }
                        }
                        Bar { Layout.fillWidth: true; value: db.total > 0 ? db.cur / db.total : 0; tint: db.tint }
                        Wrap {
                            visible: db.total > 0 && db.total <= 26
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: db.total > 0 && db.total <= 26 ? db.total : 0
                                delegate: Rectangle {
                                    width: 34; height: 26; radius: 7
                                    color: (index + 1) <= db.cur ? Qt.alpha(db.tint, 0.28) : (eh.containsMouse ? pal.highest : pal.cont)
                                    border.width: 1
                                    border.color: (index + 1) <= db.cur ? Qt.alpha(db.tint, 0.6) : pal.line
                                    Lbl { anchors.centerIn: parent; text: index + 1; mono: true; font.pixelSize: 11; dim: true }
                                    MouseArea { id: eh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setProgress(db.d.id, index + 1, db.total) }
                                }
                            }
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 8
                            Btn { kind: "primary"; accent: db.tint; icon: "link"; label: "Open on AniList"
                                  onClicked: root.openSource(db.d) }
                            Btn { icon: root.favorites[db.d.id] ? "heart" : "heartO"; label: root.favorites[db.d.id] ? "Favorited" : "Favorite"
                                  onClicked: root.toggleFavorite(db.d.id, db.d.title) }
                            Btn { visible: db.st === ""; icon: "plus"; label: db.isA ? "Add to Watchlist" : "Add to Reading List"
                                  onClicked: root.toggleList(db.d.kind, db.d.id, db.d.title) }
                        }
                        ColumnLayout {
                            visible: db.isA
                            Layout.fillWidth: true
                            spacing: 8
                            Lbl { text: "WATCH & PLAYBACK"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: db.d.officialLinks || []
                                    delegate: Btn {
                                        icon: "link"
                                        label: "Watch on " + modelData.site
                                        onClicked: root.openExternalUrl(modelData.url, modelData.site)
                                    }
                                }
                            }
                            Lbl {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                faint: true
                                font.pixelSize: 11
                                text: db.d.officialLinks && db.d.officialLinks.length > 0
                                    ? "Provider links come from AniList. Availability and subscriptions are controlled by the provider."
                                    : "AniList did not provide an official streaming link for this title. Check the AniList page for current availability."
                            }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Btn {
                                    icon: "terminal"
                                    label: "Launch ani-cli"
                                    muted: !root.toolsStatusReady || !root.toolStatus.aniReady
                                    onClicked: root.launchAniCli()
                                }
                                Btn { icon: "folder"; label: "Open local video\u2026"; onClicked: root.chooseLocalVideo() }
                            }
                            Lbl {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                faint: true
                                font.pixelSize: 11
                                text: !root.toolsStatusReady
                                    ? "Checking optional playback tools\u2026"
                                    : (!root.toolStatus.aniCli
                                        ? "ani-cli is not installed. " + root.toolGuidance("aniCli")
                                        : (root.toolTerminals().length === 0
                                            ? "ani-cli is installed, but no supported terminal was found. " + root.toolGuidance("terminal")
                                            : "ani-cli and " + root.toolTerminals()[0].label + " are available. It opens an external interactive terminal menu; GPS does not scrape, download or claim playback started."))
                            }
                            Lbl {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                faint: true
                                font.pixelSize: 11
                                text: root.toolPlayers().length > 0
                                    ? "Local videos open in " + root.toolPlayers()[0].label + ". External-player progress is not reported back, so update episode progress manually."
                                    : "No supported local video player was found. " + root.toolGuidance("player") + " Progress remains manual."
                            }
                        }
                        Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                              text: "Catalogue data from AniList. GPS Media Hub doesn't stream episodes or host chapters; "
                                    + "provider links and the AniList page open in your browser. Local video playback uses an installed external player." }
                    }
                }
            }
        }
    }

    // ================================================================
    //  HOME
    // ================================================================
    Component {
        id: homePage
        Item {
            id: hp
            readonly property real cw: hf.width - 48
            readonly property var fw: root.wallpaperById(root.featuredId)
            readonly property real fwW: Math.min(640, cw * 0.56)
            readonly property int shelfCols: cw >= 900 ? 4 : 2
            readonly property var quick: [
                { name: "Wallpapers", icon: "wallpaper", go: 1, sub: (root.wallhavenUsingRemote ? "Wallhaven live" : "Bundled samples") + " \u00b7 " + root.favCount() + " favorites" },
                { name: "Anime", icon: "anime", go: 2, sub: root.countListed("anime") + " on watchlist" },
                { name: "Manga & Manhwa", icon: "manga", go: 3, sub: root.countListed("manga") + " on reading list" },
                { name: "Downloads", icon: "download", go: 5, sub: root.dlCount("downloading") + " active \u00b7 " + root.dlCount("queued") + " queued" },
                { name: "My Library", icon: "library", go: 6, sub: root.libraryItems().length + " items" },
                { name: "Music", icon: "music", go: 4, sub: "Online player \u00b7 " + root.musicFavorites.length + " saved" }
            ]
            readonly property var recent: root.libraryList("All", "Recently Opened", "").filter(function (it) { return it.opened > 0 }).slice(0, 4)

            Flickable {
                id: hf
                anchors.fill: parent
                contentWidth: width
                contentHeight: hcol.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}

                Column {
                    id: hcol
                    x: 24; y: 6
                    width: hf.width - 48
                    spacing: 18

                    // ---- A. hero
                    Rectangle {
                        width: parent.width; height: 224; radius: 18
                        color: pal.low
                        border.width: 1
                        border.color: pal.line
                        Art {
                            id: heroArt
                            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                            width: Math.max(260, parent.width * 0.52)
                            radiusPx: 18
                            frameColor: pal.bg
                            src: root.artUrl(root.mood.art)
                            grad: root.mood.grad
                            glyph: "wallpaper"
                        }
                        Rectangle {
                            anchors.fill: heroArt
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: pal.low }
                                GradientStop { position: 0.55; color: Qt.alpha(pal.low, 0.75) }
                                GradientStop { position: 1.0; color: Qt.alpha(pal.low, 0.15) }
                            }
                        }
                        Column {
                            x: 32
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(580, parent.width * 0.62)
                            spacing: 10
                            Row {
                                spacing: 8
                                Tag { text: "MEDIA HUB"; tint: root.accent }
                                Tag { text: "LIVE SOURCES"; tint: "#86efac" }
                            }
                            Lbl { text: "Find your next escape."; font.pixelSize: 34; font.weight: Font.Bold }
                            Lbl { width: parent.width; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 14
                                  text: "Discover wallpapers, anime, manga and media \u2014 then keep everything in one personal library." }
                            Row {
                                spacing: 10
                                Btn { kind: "primary"; accent: root.accent; icon: "surprise"; label: "Surprise Me"; onClicked: root.surprise() }
                                Btn { icon: "wallpaper"; label: "Discover Wallpapers"; onClicked: root.go(1) }
                            }
                            Row {
                                visible: root.surprisePick !== null
                                spacing: 10
                                Lbl { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; dim: true
                                      text: root.surprisePick ? ("\u2726 " + root.surprisePick.title + "  \u00b7  " + root.surprisePick.sub) : "" }
                                Btn { compact: true; kind: "ghost"; label: "Open"; icon: "chev"; onClicked: root.openSurprise() }
                            }
                        }
                    }

                    // ---- B. today's vibe
                    Card {
                        width: parent.width
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            ColumnLayout {
                                spacing: 2
                                Lbl { text: "TODAY'S VIBE"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1.2 }
                                Lbl { text: root.mood.name; font.pixelSize: 22; font.weight: Font.Bold }
                            }
                            Row {
                                spacing: 6
                                Repeater { model: root.mood.palette; delegate: Rectangle { width: 22; height: 22; radius: 11; color: modelData; border.width: 1; border.color: "#33ffffff" } }
                            }
                            Item { Layout.fillWidth: true }
                            Tag { visible: hp.cw > 760; text: "UNAVAILABLE"; tint: "#fde047" }
                            Btn { label: hp.cw > 760 ? "Play vibe music" : ""; icon: "music"; onClicked: root.playVibeMix() }
                            Btn { label: "Sync GPS Theme"; icon: "sync"; muted: true; onClicked: root.syncThemeUnavailable() }
                        }
                        Lbl { Layout.fillWidth: true; text: root.mood.desc; wrapMode: Text.WordWrap; dim: true }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: hp.cw >= 900 ? 4 : 2
                            columnSpacing: 14
                            rowSpacing: 14
                            Repeater {
                                model: root.moods
                                delegate: Rectangle {
                                    id: vc
                                    readonly property bool sel: root.moodId === modelData.id
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: 200
                                    radius: 14
                                    color: pal.cont
                                    border.width: sel ? 2 : 1
                                    border.color: sel ? modelData.accent : pal.line
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                    HoverHandler { id: vh }
                                    scale: vh.hovered ? 1.01 : 1
                                    Behavior on scale { NumberAnimation { duration: 180 } }
                                    Art { id: vArt; x: 6; y: 6; width: parent.width - 12; height: 108; radiusPx: 10; frameColor: vc.color
                                          src: root.artUrl(modelData.art); grad: modelData.grad; glyph: "vibe"; zoom: vh.hovered ? 1.05 : 1 }
                                    Tag { visible: vc.sel; x: 14; y: 14; text: "SELECTED"; tint: modelData.accent; px: 9 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setMood(modelData.id) }
                                    Lbl { x: 12; y: 122; text: modelData.name; font.pixelSize: 14; font.weight: Font.DemiBold }
                                    Row { x: 12; y: 146; spacing: 5
                                        Repeater { model: modelData.palette; delegate: Rectangle { width: 14; height: 14; radius: 7; color: modelData; border.width: 1; border.color: "#33ffffff" } }
                                    }
                                    Btn { x: 12; y: 164; width: parent.width - 24; compact: true; label: "Explore this vibe"; icon: "chev"; onClicked: root.exploreMood(modelData.id) }
                                }
                            }
                        }
                    }

                    // ---- C. featured wallpaper
                    Card {
                        width: parent.width
                        visible: hp.fw !== null
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 22
                            Art {
                                Layout.preferredWidth: hp.fwW
                                Layout.preferredHeight: hp.fwW / 1.6
                                Layout.alignment: Qt.AlignTop
                                radiusPx: 12
                                frameColor: pal.low
                                src: hp.fw ? root.artUrl(hp.fw.art) : ""
                                grad: hp.fw ? hp.fw.g : [pal.low, "#2a1b5e", "#0e4a6b"]
                                glyph: "wallpaper"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 10
                                Tag { text: "FEATURED WALLPAPER"; tint: root.accent }
                                Lbl { Layout.fillWidth: true; text: hp.fw ? hp.fw.title : ""; wrapMode: Text.WordWrap; font.pixelSize: 22; font.weight: Font.Bold }
                                Lbl { text: hp.fw ? (root.wallpaperSourceLabel(hp.fw) + (hp.fw.author ? " \u00b7 by " + hp.fw.author : "")) : ""; dim: true; font.pixelSize: 12 }
                                Wrap { Layout.fillWidth: true; spacing: 6
                                    Tag { text: hp.fw ? (hp.fw.res + " \u00b7 " + hp.fw.ratio) : ""; tint: "#7bd0ff" }
                                    Tag { text: hp.fw ? hp.fw.size : "" }
                                    Repeater { model: hp.fw ? hp.fw.tags : []; delegate: Tag { text: "#" + modelData; tint: "#cebdff" } }
                                }
                                Row { spacing: 6
                                    Repeater { model: hp.fw ? hp.fw.pal : []; delegate: Rectangle { width: 24; height: 24; radius: 7; color: modelData; border.width: 1; border.color: "#33ffffff" } }
                                }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 13; text: hp.fw ? hp.fw.desc : "" }
                                Item { Layout.preferredHeight: 2 }
                                Btn { Layout.fillWidth: true; icon: "eye"; label: "Preview"; onClicked: root.previewWallpaper(root.featuredId) }
                                Btn { Layout.fillWidth: true; icon: "desktop"; label: "Apply Wallpaper"; onClicked: root.requestApply(hp.fw, false) }
                                Btn { Layout.fillWidth: true; kind: "primary"; accent: root.accent; icon: "sync"; label: "Apply + Sync GPS Theme"; onClicked: root.requestApply(hp.fw, true) }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                                      text: hp.fw && hp.fw.isRemote
                                            ? "Apply downloads and caches the SFW image, sets it with awww, and can optionally regenerate the GPS theme."
                                            : "Bundled preview only. Open Wallpapers and search Wallhaven to download or apply a real image." }
                            }
                        }
                    }

                    // ---- D. continue
                    Column {
                        width: parent.width
                        spacing: 10
                        RowLayout {
                            width: parent.width
                            Lbl { text: "Jump back in"; font.pixelSize: 17; font.weight: Font.Bold }
                            Lbl { text: "  Continue Watching & Reading"; faint: true; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Btn { compact: true; kind: "ghost"; label: "Open Library"; icon: "chev"; onClicked: root.go(root.pgLibrary) }
                        }
                        Wrap {
                            width: parent.width
                            spacing: 14
                            Repeater {
                                model: root.continueAll()
                                delegate: ShelfCard {
                                    readonly property bool isA: modelData.kind === "anime"
                                    readonly property int cur: root.progress[modelData.id] || 0
                                    width: (hp.cw - 14 * (hp.shelfCols - 1)) / hp.shelfCols
                                    title: modelData.title
                                    sub: (isA ? "Episode " : "Chapter ") + cur + " of " + (modelData.total > 0 ? modelData.total : "?")
                                    badge: isA ? "Anime" : modelData.type
                                    src: root.artUrl(modelData.cover)
                                    grad: modelData.g
                                    glyph: isA ? "anime" : "manga"
                                    value: modelData.total > 0 ? cur / modelData.total : 0
                                    valueLabel: (modelData.total > 0 ? Math.round(cur / modelData.total * 100) + "% \u00b7 " : "") + (isA ? "Ep " : "Ch ") + cur + "/" + (modelData.total > 0 ? modelData.total : "?")
                                    btnLabel: "Open AniList"
                                    btnIcon: "link"
                                    accent: isA ? "#7bd0ff" : "#ddb8ff"
                                    onActivated: root.openDetail(modelData.kind, modelData.id)
                                    onCont: root.continueMedia(modelData)
                                }
                            }
                        }
                        Card {
                            width: parent.width
                            visible: root.continueAll().length === 0
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true
                                  text: "Nothing in progress yet. Set an anime to Watching or a manga to Reading and it will show up here." }
                        }
                    }

                    // ---- E. quick access + activity
                    RowLayout {
                        width: parent.width
                        spacing: 18
                        Card {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            Lbl { text: "Quick access"; font.pixelSize: 15; font.weight: Font.Bold }
                            Wrap {
                                id: qaWrap
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: hp.quick
                                    delegate: Rectangle {
                                        id: qt
                                        width: (qaWrap.width - 20) / 3
                                        height: 68
                                        radius: 12
                                        color: qh.containsMouse ? pal.high : pal.cont
                                        border.width: 1
                                        border.color: qh.containsMouse ? Qt.alpha(root.accent, 0.5) : pal.line
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; radius: 10; color: Qt.alpha(root.accent, 0.16)
                                                    Ico { anchors.centerIn: parent; name: modelData.icon; size: 16; tint: root.accent } }
                                        Column { x: 58; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 66; spacing: 2
                                            Lbl { width: parent.width; text: modelData.name; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            Lbl { width: parent.width; text: modelData.sub; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 10 }
                                        }
                                        MouseArea { id: qh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { if (modelData.go >= 0) root.go(modelData.go); else root.vibeOpen = true } }
                                    }
                                }
                            }
                        }
                        Card {
                            Layout.preferredWidth: 340
                            Layout.alignment: Qt.AlignTop
                            Lbl { text: "Recently opened"; font.pixelSize: 15; font.weight: Font.Bold }
                            Repeater {
                                model: hp.recent
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Art { Layout.preferredWidth: 52; Layout.preferredHeight: 34; radiusPx: 6; frameColor: pal.low; src: root.artUrl(modelData.art); grad: modelData.g; glyph: "library" }
                                    Lbl { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.pixelSize: 13 }
                                    Tag { text: root.kindLabel(modelData.kind).toUpperCase(); px: 9 }
                                }
                            }
                            Lbl { visible: hp.recent.length === 0; text: "Nothing opened yet."; faint: true; font.pixelSize: 12 }
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: pal.line }
                            Lbl { text: "This session"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Repeater {
                                model: root.activity
                                delegate: Lbl { Layout.fillWidth: true; text: "\u2022 " + modelData; elide: Text.ElideRight; dim: true; font.pixelSize: 12 }
                            }
                            Lbl { visible: root.activity.length === 0; text: "No activity yet \u2014 favorite or open something."; faint: true; font.pixelSize: 12 }
                        }
                    }
                }
            }
        }
    }

    // ================================================================
    //  WALLPAPERS
    // ================================================================
    Component {
        id: wallPage
        Item {
            id: wp
            readonly property bool wide: width >= 1020
            readonly property bool hasSel: root.wpSelectedId !== ""
            property real inspW: (wide && hasSel) ? 352 : 0
            Behavior on inspW { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
            property bool moreOpen: false
            readonly property var list: root.filteredWallpapers()
            readonly property var shown: list.slice(0, root.wpVisible)
            readonly property real gridW: gf.width - 48
            readonly property int cols: Math.max(1, Math.floor((gridW + 16) / 276))
            readonly property real cardW: (gridW - 16 * (cols - 1)) / cols
            readonly property var tagList: root.allTags()

            Flickable {
                id: gf
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: wp.inspW }
                contentWidth: width
                contentHeight: gcol.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}

                Column {
                    id: gcol
                    x: 24; y: 6
                    width: gf.width - 48
                    spacing: 16

                    RowLayout {
                        width: parent.width
                        spacing: 12
                        ColumnLayout {
                            spacing: 3
                            Lbl { text: "Wallpapers"; font.pixelSize: 26; font.weight: Font.Bold }
                            Lbl { text: "Live SFW Wallhaven search with local caching and optional theme sync."; dim: true; font.pixelSize: 13 }
                        }
                        Item { Layout.fillWidth: true }
                        Tag { visible: wp.gridW > 620; text: root.wallhavenUsingRemote ? "LIVE WALLHAVEN \u00b7 LOCAL CACHE" : "BUNDLED SAMPLE PREVIEW"; tint: root.wallhavenUsingRemote ? "#7bd0ff" : "#fde047" }
                        Tag { text: "SFW ONLY \u00b7 LOCKED"; tint: "#86efac" }
                    }

                    Card {
                        width: parent.width
                        tint: "#fde047"
                        visible: !root.wallhavenConnected && !root.wallhavenLoading && root.wallhavenError === ""
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "cloud"; size: 20; tint: "#fde047" }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 13; dim: true
                                  text: "Wallhaven isn't connected yet. Until the first search succeeds you're looking at "
                                        + root.wallpapers.length + " bundled sample wallpapers. Opening this page starts an SFW search automatically." }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: root.wallhavenLoading && !root.wallhavenLoaded
                        tint: root.accent
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "refresh"; size: 20; tint: root.accent }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 13; dim: true
                                  text: "Searching Wallhaven \u2014 SFW results only. Your current cards stay visible until the response arrives." }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: root.wallhavenError !== ""
                        tint: "#ef4444"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "warn"; size: 20; tint: "#fca5a5" }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Lbl { text: "Wallhaven search failed"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12
                                      text: root.wallhavenError }
                            }
                            Btn { compact: true; label: "Retry"; icon: "refresh"; onClicked: root.retryWallhaven() }
                        }
                    }

                    Card {
                        width: parent.width
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            SearchField {
                                Layout.fillWidth: true
                                accent: root.accent
                                placeholder: "Search Wallhaven by tag, colour or collection"
                                text: root.wpQuery
                                onEdited: { root.wpQuery = text; root.wpVisible = 6 }
                            }
                            Btn { compact: true; label: "Reset filters"; icon: "refresh"; muted: root.activeWpFilters() === 0; onClicked: root.resetWpFilters() }
                            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 22; color: "#2a303c" }
                            Tag { text: "SFW only"; tint: "#86efac" }
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: root.wpCategories
                                delegate: Chip { label: modelData; active: root.wpCategory === modelData; accent: root.accent
                                                 onClicked: { root.wpCategory = modelData; root.wpVisible = 6 } }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Sort"; mono: true; faint: true; font.pixelSize: 11 }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: root.wpSorts
                                    delegate: Chip { label: modelData; active: root.wpSort === modelData; accent: root.accent
                                                     onClicked: { root.wpSort = modelData } }
                                }
                            }
                            Btn { compact: true; kind: "ghost"; label: wp.moreOpen ? "Fewer filters" : "More filters"; icon: "list"; onClicked: wp.moreOpen = !wp.moreOpen }
                        }
                        Item {
                            id: more
                            Layout.fillWidth: true
                            Layout.preferredHeight: h
                            property real h: wp.moreOpen ? moreCol.implicitHeight : 0
                            Behavior on h { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            clip: true
                            opacity: wp.moreOpen ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            ColumnLayout {
                                id: moreCol
                                width: parent.width
                                spacing: 10
                                RowLayout { Layout.fillWidth: true; spacing: 10
                                    Lbl { text: "Colour"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 70 }
                                    Wrap { Layout.fillWidth: true; spacing: 8
                                        Repeater { model: root.wpColors
                                            delegate: Chip { label: modelData; active: root.wpColor === modelData; accent: root.accent
                                                             dot: root.colorDots[modelData] ? root.colorDots[modelData] : "transparent"
                                                             onClicked: { root.wpColor = modelData; root.wpVisible = 6 } } }
                                    }
                                }
                                RowLayout { Layout.fillWidth: true; spacing: 10
                                    Lbl { text: "Resolution"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 70 }
                                    Wrap { Layout.fillWidth: true; spacing: 8
                                        Repeater { model: root.wpResolutions
                                            delegate: Chip { label: modelData; active: root.wpRes === modelData; accent: root.accent
                                                             onClicked: { root.wpRes = modelData; root.wpVisible = 6 } } }
                                    }
                                }
                                RowLayout { Layout.fillWidth: true; spacing: 10
                                    Lbl { text: "Ratio"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 70 }
                                    Wrap { Layout.fillWidth: true; spacing: 8
                                        Repeater { model: root.wpAspects
                                            delegate: Chip { label: modelData; active: root.wpAspect === modelData; accent: root.accent
                                                             onClicked: { root.wpAspect = modelData; root.wpVisible = 6 } } }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: wp.tagList.length > 0
                            Lbl { text: "Tags"; mono: true; faint: true; font.pixelSize: 11 }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: wp.tagList
                                    delegate: Chip { label: "#" + modelData; active: root.wpTag === modelData; accent: "#cebdff"
                                                     onClicked: { root.wpTag = (root.wpTag === modelData) ? "" : modelData; root.wpVisible = 6 } }
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Lbl { mono: true; faint: true; font.pixelSize: 11
                              text: (root.wallhavenLoading ? "Refreshing \u00b7 " : "")
                                    + "Showing " + wp.shown.length + " of " + wp.list.length
                                    + (root.wallhavenUsingRemote ? " Wallhaven results" : " bundled samples")
                                    + (root.wallhavenUsingRemote && root.wallhavenPage > 0 ? "  \u00b7  page " + root.wallhavenPage + " of " + root.wallhavenLastPage : "")
                                    + (root.activeWpFilters() > 0 ? "  \u00b7  " + root.activeWpFilters() + " filter(s) active" : "") }
                        Item { Layout.fillWidth: true }
                    }

                    Wrap {
                        width: parent.width
                        spacing: 16
                        Repeater {
                            model: wp.shown
                            delegate: MediaCard {
                                width: wp.cardW
                                title: modelData.title
                                meta: modelData.res + " \u00b7 " + modelData.size
                                extra: root.wallpaperCardExtra(modelData)
                                corner: modelData.ratio
                                src: root.artUrl(modelData.art)
                                grad: modelData.g
                                glyph: "wallpaper"
                                aspect: 1.6
                                accent: root.accent
                                selected: root.wpSelectedId === modelData.id
                                fav: !!root.favorites[modelData.id]
                                showPreview: true
                                primaryLabel: "Apply"
                                primaryIcon: "check"
                                onActivated: root.wpSelectedId = modelData.id
                                onPreviewed: root.wpSelectedId = modelData.id
                                onPrimary: root.requestApply(modelData, false)
                                onFavToggled: root.toggleFavorite(modelData.id, modelData.title)
                            }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: wp.list.length === 0 && !root.wallhavenLoading && root.wallhavenError === ""
                        Lbl { text: root.wallhavenUsingRemote ? "No SFW wallpapers match these filters" : "No bundled samples match these filters"
                              font.pixelSize: 15; font.weight: Font.DemiBold }
                        Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true
                              text: root.wallhavenUsingRemote
                                    ? "Wallhaven returned an empty page. Try a broader query, another category, or fewer filters."
                                    : "The bundled set is intentionally small. Search Wallhaven or reset the filters." }
                        RowLayout {
                            spacing: 8
                            Btn { label: "Reset filters"; icon: "refresh"; onClicked: root.resetWpFilters() }
                            Btn { visible: !root.wallhavenUsingRemote; kind: "primary"; accent: root.accent; label: "Search Wallhaven"; icon: "search"; onClicked: root.retryWallhaven() }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 40
                        visible: wp.list.length > 0 || (root.wallhavenUsingRemote && root.wallhavenPage < root.wallhavenLastPage)
                        Btn {
                            anchors.centerIn: parent
                            visible: wp.list.length > root.wpVisible || (root.wallhavenUsingRemote && root.wallhavenPage < root.wallhavenLastPage)
                            label: wp.list.length > root.wpVisible
                                   ? "Load more  (" + (wp.list.length - root.wpVisible) + " more loaded)"
                                   : "Load more from Wallhaven"
                            icon: "plus"
                            onClicked: root.loadMoreWallhaven()
                        }
                        Lbl {
                            anchors.centerIn: parent
                            visible: wp.list.length > 0 && wp.list.length <= root.wpVisible
                                    && !(root.wallhavenUsingRemote && root.wallhavenPage < root.wallhavenLastPage)
                            text: root.wallhavenUsingRemote ? "End of the Wallhaven results." : "End of the bundled samples."
                            faint: true; font.pixelSize: 12
                        }
                    }
                }
            }

            // ---- inspector (wide: docked)
            Item {
                id: inspHost
                visible: wp.wide && opacity > 0.01
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 352
                opacity: wp.hasSel ? 1 : 0
                clip: true
                Behavior on opacity { NumberAnimation { duration: 200 } }
                transform: Translate { x: wp.hasSel ? 0 : 36; Behavior on x { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } } }
                Loader { anchors.fill: parent; anchors.rightMargin: 24; anchors.bottomMargin: 8; active: wp.wide && root.wpShownId !== ""; sourceComponent: wpInspectorC }
            }

            // ---- inspector (narrow: slide-over)
            Item {
                id: inspOverlay
                anchors.fill: parent
                visible: !wp.wide && opacity > 0.01
                opacity: wp.hasSel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Rectangle { anchors.fill: parent; color: Qt.alpha(pal.lowest, 0.6); MouseArea { anchors.fill: parent; onClicked: root.wpSelectedId = "" } }
                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: 8 }
                    width: Math.min(380, parent.width - 24)
                    radius: 16
                    color: pal.low
                    border.width: 1
                    border.color: pal.line
                    clip: true
                    MouseArea { anchors.fill: parent }
                    Loader { anchors.fill: parent; anchors.margins: 0; active: !wp.wide && root.wpShownId !== ""; sourceComponent: wpInspectorC }
                }
            }
        }
    }

    Component {
        id: wpInspectorC
        Rectangle {
            id: ins
            readonly property var w: root.wallpaperById(root.wpShownId)
            color: wallPageIsWide ? pal.low : "transparent"
            readonly property bool wallPageIsWide: root.width - root.sidebarW >= 1020
            radius: 16
            border.width: wallPageIsWide ? 1 : 0
            border.color: pal.line
            Flickable {
                id: inf
                anchors { fill: parent; margins: 16 }
                contentWidth: width
                contentHeight: icol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                ColumnLayout {
                    id: icol
                    width: inf.width - 6
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { width: 8; height: 8; radius: 4; color: root.accent }
                        Lbl { text: "INSPECTOR"; mono: true; font.pixelSize: 11; font.letterSpacing: 1.2; dim: true }
                        Item { Layout.fillWidth: true }
                        Lbl { text: ins.w ? ("#" + ins.w.id.toUpperCase()) : ""; mono: true; faint: true; font.pixelSize: 10 }
                        IconBtn { box: 26; icon: "close"; tip: "Close inspector"; onClicked: root.wpSelectedId = "" }
                    }
                    Art {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width / 1.6
                        radiusPx: 12
                        frameColor: ins.color.a > 0 ? pal.low : pal.bg
                        src: ins.w ? root.artUrl(ins.w.art) : ""
                        grad: ins.w ? ins.w.g : [pal.low, "#2a1b5e", "#0e4a6b"]
                        glyph: "wallpaper"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Lbl { Layout.fillWidth: true; text: ins.w ? ins.w.title : ""; wrapMode: Text.WordWrap; font.pixelSize: 17; font.weight: Font.Bold }
                        IconBtn { box: 32; icon: (ins.w && root.favorites[ins.w.id]) ? "heart" : "heartO"; active: ins.w ? !!root.favorites[ins.w.id] : false
                                  tip: "Favorite"; onClicked: root.toggleFavorite(ins.w.id, ins.w.title) }
                    }
                    Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12; text: ins.w ? ins.w.desc : "" }
                    Spec { Layout.fillWidth: true; k: "Resolution"; v: ins.w ? ins.w.res : "" }
                    Spec { Layout.fillWidth: true; k: "Aspect ratio"; v: ins.w ? ins.w.ratio : "" }
                    Spec { Layout.fillWidth: true; k: "File size"; v: ins.w ? ins.w.size : "" }
                    Spec { Layout.fillWidth: true; k: "Source"; v: root.wallpaperSourceLabel(ins.w) }
                    Spec { Layout.fillWidth: true; k: "Uploader"; v: ins.w ? ins.w.author : "" }
                    Lbl { text: "DOMINANT COLOURS"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ins.w ? ins.w.pal : []
                            delegate: Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 28; radius: 8; color: modelData; border.width: 1; border.color: "#33ffffff" }
                        }
                    }
                    Lbl { visible: ins.w && ins.w.tags && ins.w.tags.length > 0; text: "TAGS"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                    Wrap {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: ins.w && ins.w.tags && ins.w.tags.length > 0
                        Repeater {
                            model: ins.w && ins.w.tags ? ins.w.tags : []
                            delegate: Chip { label: "#" + modelData; accent: "#cebdff"; active: root.wpTag === modelData
                                             onClicked: { root.wpTag = (root.wpTag === modelData) ? "" : modelData; root.wpVisible = 6 } }
                        }
                    }
                    Item { Layout.preferredHeight: 2 }
                    Btn { Layout.fillWidth: true; kind: "primary"; accent: root.accent; icon: "sync"; label: "Apply + Sync GPS Theme"; onClicked: root.requestApply(ins.w, true) }
                    Btn { Layout.fillWidth: true; icon: "desktop"; label: "Apply Wallpaper"; onClicked: root.requestApply(ins.w, false) }
                    Btn { Layout.fillWidth: true; icon: "link"; label: "Open source page"; onClicked: root.openSource(ins.w) }
                    Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                          text: ins.w && ins.w.isRemote
                                ? "Apply downloads or reuses a cached copy, sets it with awww, and optionally runs the existing GPS theme extraction. Apply never enables adult content."
                                : "This card is bundled sample data. Search Wallhaven to select a real SFW wallpaper that can be downloaded and applied." }
                }
            }
        }
    }

    // ================================================================
    //  ANIME + MANGA — one shared browse page, configured by `kind`
    // ================================================================
    Component { id: animePage; Loader { anchors.fill: parent; sourceComponent: browseC; onLoaded: { item.kind = "anime"; item.startCatalogue() } } }
    Component { id: mangaPage; Loader { anchors.fill: parent; sourceComponent: browseC; onLoaded: { item.kind = "manga"; item.startCatalogue() } } }

    Component {
        id: browseC
        Item {
            id: bp
            property string kind: "anime"
            readonly property bool isA: kind === "anime"
            readonly property color tint: isA ? "#7bd0ff" : "#ddb8ff"
            readonly property real gw: bf.width - 48
            readonly property int cols: Math.max(2, Math.floor((gw + 14) / 190))
            readonly property real cardW: (gw - 14 * (cols - 1)) / cols
            readonly property int shelfCols: gw >= 900 ? 4 : 2
            readonly property var shelf: root.continueList(kind).slice(0, 4)
            readonly property var catalogue: isA ? root.animeModel : root.mangaModel

            function startCatalogue() {
                catalogue.activate()
            }
            function resetFilters() {
                catalogue.query = ""
                catalogue.genre = "All"
                catalogue.statusFilter = "All"
                catalogue.originFilter = "All regions"
            }

            Flickable {
                id: bf
                anchors.fill: parent
                contentWidth: width
                contentHeight: bcol.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                Column {
                    id: bcol
                    x: 24; y: 6
                    width: bf.width - 48
                    spacing: 16

                    RowLayout {
                        width: parent.width
                        spacing: 12
                        ColumnLayout {
                            spacing: 3
                            Lbl { text: bp.isA ? "Anime" : "Manga & Manhwa"; font.pixelSize: 26; font.weight: Font.Bold }
                            Lbl { dim: true; font.pixelSize: 13
                                  text: bp.isA ? "Live AniList discovery, tracking and a persistent watchlist." : "Live AniList discovery, tracking and a persistent reading list." }
                        }
                        Item { Layout.fillWidth: true }
                        Tag { visible: bp.gw > 640; tint: catalogue.localView ? "#86efac" : (catalogue.error !== "" ? "#fde047" : bp.tint)
                              text: catalogue.localView ? "LOCAL LIST \u00b7 OFFLINE"
                                    : (catalogue.error !== "" ? "ANILIST OFFLINE" : "LIVE ANILIST \u00b7 PUBLIC CATALOGUE") }
                    }

                    Card {
                        width: parent.width
                        SearchField {
                            Layout.fillWidth: true
                            accent: bp.tint
                            placeholder: bp.isA ? "Search anime by title" : "Search manga, manhwa or manhua by title"
                            text: catalogue.query
                            onEdited: catalogue.query = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: catalogue.viewOptions
                                    delegate: Chip {
                                        label: modelData
                                        accent: bp.tint
                                        active: catalogue.view === modelData
                                        badge: modelData === MediaCatalogue.listView(bp.kind) ? ("" + root.countListed(bp.kind)) : ""
                                        onClicked: catalogue.view = modelData
                                    }
                                }
                            }
                            Btn { compact: true; kind: "ghost"; label: "Reset"; icon: "refresh"
                                  onClicked: bp.resetFilters() }
                        }
                        Wrap {
                            visible: !bp.isA
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: catalogue.originOptions
                                delegate: Chip {
                                    label: modelData
                                    icon: "manga"
                                    accent: bp.tint
                                    active: catalogue.originFilter === modelData
                                    onClicked: catalogue.originFilter = modelData
                                }
                            }
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: catalogue.genreOptions
                                delegate: Chip { label: modelData; accent: "#a78bfa"; active: catalogue.genre === modelData; onClicked: catalogue.genre = modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Status"; mono: true; faint: true; font.pixelSize: 11 }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: catalogue.statusOptions
                                    delegate: Chip { label: modelData; accent: bp.tint; active: catalogue.statusFilter === modelData; onClicked: catalogue.statusFilter = modelData }
                                }
                            }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: catalogue.error !== ""
                        tint: "#ef4444"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "warn"; size: 20; tint: "#fca5a5" }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Lbl { text: "AniList search failed"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12
                                      text: catalogue.error
                                            + (catalogue.retryAfter > 0 ? " Try again in about " + catalogue.retryAfter + " seconds." : "")
                                            + (catalogue.errorCode !== "" ? " (" + catalogue.errorCode + ")" : "") }
                            }
                            Btn { compact: true; label: "Retry"; icon: "refresh"; onClicked: catalogue.retry() }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: catalogue.loading && catalogue.remoteResults.length === 0
                        tint: bp.tint
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "search"; size: 20; tint: bp.tint }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 13
                                  text: "Searching AniList \u2014 public catalogue data, no account required." }
                        }
                    }

                    // ---- continue shelf
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: bp.shelf.length > 0 && catalogue.query.trim() === "" && !catalogue.localView
                        Lbl { text: bp.isA ? "Continue Watching" : "Continue Reading"; font.pixelSize: 16; font.weight: Font.Bold }
                        Wrap {
                            width: parent.width
                            spacing: 14
                            Repeater {
                                model: bp.shelf
                                delegate: ShelfCard {
                                    readonly property int cur: modelData.progress || 0
                                    width: (bp.gw - 14 * (bp.shelfCols - 1)) / bp.shelfCols
                                    title: modelData.title
                                    sub: (bp.isA ? "Episode " : "Chapter ") + cur + " of " + (modelData.total > 0 ? modelData.total : "?")
                                    badge: modelData.type
                                    src: root.artUrl(modelData.cover)
                                    grad: modelData.g
                                    glyph: bp.isA ? "anime" : "manga"
                                    value: modelData.total > 0 ? cur / modelData.total : 0
                                    valueLabel: (modelData.total > 0 ? Math.round(cur / modelData.total * 100) + "% \u00b7 " : "") + (bp.isA ? "Ep " : "Ch ") + cur + "/" + (modelData.total > 0 ? modelData.total : "?")
                                    btnLabel: "Open AniList"
                                    btnIcon: "link"
                                    accent: bp.tint
                                    onActivated: root.openDetail(modelData.kind, modelData.id)
                                    onCont: root.continueMedia(modelData)
                                }
                            }
                        }
                    }

                    // ---- manga: local collections entry point
                    Card {
                        width: parent.width
                        visible: !bp.isA
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Rectangle { Layout.preferredWidth: 42; Layout.preferredHeight: 42; radius: 12; color: Qt.alpha("#ddb8ff", 0.15)
                                        Ico { anchors.centerIn: parent; name: "folder"; size: 18; tint: "#ddb8ff" } }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Lbl { text: "Local collections"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12
                                      text: "Bring your own CBZ, CBR and image-folder series. Nothing is scanned yet \u2014 no local collections are connected." }
                            }
                            Btn { compact: true; label: "Add CBZ / CBR"; icon: "plus"
                                  onClicked: root.notify("Local collection import isn't connected yet (CBZ / CBR). A backend indexer will handle this.", "warn") }
                            Btn { compact: true; label: "Add image folder"; icon: "folder"
                                  onClicked: root.notify("Local collection import isn't connected yet (image folders). A backend indexer will handle this.", "warn") }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Lbl { mono: true; faint: true; font.pixelSize: 11
                              text: (catalogue.loading && catalogue.remoteResults.length > 0 ? "Updating \u00b7 " : "")
                                    + catalogue.count + (catalogue.localView ? " saved title" : " title")
                                    + (catalogue.count === 1 ? "" : "s")
                                    + " \u00b7 " + catalogue.view
                                    + (catalogue.localView ? " \u00b7 offline" : " \u00b7 page " + catalogue.page) }
                        Item { Layout.fillWidth: true }
                        Tag { visible: catalogue.cached && !catalogue.localView; text: "CACHED"; tint: "#86efac" }
                    }

                    Wrap {
                        width: parent.width
                        spacing: 14
                        Repeater {
                            model: catalogue.entries
                            delegate: MediaCard {
                                width: bp.cardW
                                title: modelData.title
                                meta: bp.isA
                                    ? ((modelData.formatLabel || "Anime") + " \u00b7 " + (modelData.total > 0 ? modelData.total + " eps" : "? eps"))
                                    : (modelData.type + " \u00b7 " + (modelData.total > 0 ? modelData.total + " ch" : "? ch"))
                                extra: modelData.genres.slice(0, 2).join(" \u00b7 ")
                                badge: bp.isA ? modelData.statusLabel : modelData.type
                                corner: bp.isA ? (modelData.score > 0 ? "\u2605 " + modelData.scoreLabel : modelData.year) : modelData.statusLabel
                                userStatus: root.statuses[modelData.id] || ""
                                src: root.artUrl(modelData.cover)
                                grad: modelData.g
                                glyph: bp.isA ? "anime" : "manga"
                                aspect: 0.6667
                                accent: bp.tint
                                fav: !!root.favorites[modelData.id]
                                showList: true
                                listed: !!root.statuses[modelData.id]
                                primaryLabel: "Details"
                                primaryIcon: "info"
                                onActivated: root.openDetail(modelData.kind, modelData.id)
                                onPrimary: root.openDetail(modelData.kind, modelData.id)
                                onFavToggled: root.toggleFavorite(modelData.id, modelData.title)
                                onListToggled: root.toggleList(modelData.kind, modelData.id, modelData.title)
                            }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: catalogue.count === 0 && catalogue.error === ""
                                 && (catalogue.localView || (catalogue.hasLoaded && !catalogue.loading))
                        Lbl { font.pixelSize: 15; font.weight: Font.DemiBold; text: catalogue.emptyTitle }
                        Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; text: catalogue.emptyMessage }
                        Btn { label: "Reset filters"; icon: "refresh"; onClicked: bp.resetFilters() }
                    }

                    RowLayout {
                        width: parent.width
                        visible: !catalogue.localView && catalogue.hasLoaded && catalogue.error === "" && catalogue.count > 0
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Btn { compact: true; label: "Previous"; icon: "chev"; muted: catalogue.page <= 1 || catalogue.loading
                              onClicked: catalogue.previousPage() }
                        Lbl { text: "Page " + catalogue.page; mono: true; faint: true; font.pixelSize: 11 }
                        Btn { compact: true; label: "Next"; icon: "chev"; muted: !catalogue.hasNextPage || catalogue.loading
                              onClicked: catalogue.nextPage() }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    // ================================================================
    //  MUSIC
    // ================================================================
    component Seek: Item {
        id: sk
        property real value: 0
        property color tint: "#a78bfa"
        property bool interactive: true
        signal moved(real v)
        implicitHeight: 16
        readonly property real clamped: Math.max(0, Math.min(1, value))
        Rectangle {
            id: trk
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: 2
            color: "#2f3541"
            Rectangle { width: parent.width * sk.clamped; height: parent.height; radius: 2; color: sk.tint }
        }
        Rectangle {
            visible: sk.interactive && (sma.containsMouse || sma.pressed)
            width: 12; height: 12; radius: 6; color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: trk.width * sk.clamped - 6
        }
        MouseArea {
            id: sma
            anchors.fill: parent
            hoverEnabled: true
            enabled: sk.interactive
            cursorShape: Qt.PointingHandCursor
            onPressed: function (mouse) { sk.moved(Math.max(0, Math.min(1, mouse.x / width))) }
            onPositionChanged: function (mouse) { if (pressed) sk.moved(Math.max(0, Math.min(1, mouse.x / width))) }
        }
    }

    Component {
        id: musicPage
        Item {
            id: mp
            readonly property bool wide: width >= 1040
            property real dockW: (wide && root.queueOpen) ? 330 : 0
            Behavior on dockW { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
            readonly property string src: root.musicSource
            readonly property var srcInfo: root.findIn(root.musicSources, src)
            readonly property real cw: mf.width - 48
            readonly property string vibeMood: root.musicMoodFor(root.moodId)
            readonly property string activeMood: root.musicMood
            readonly property var trackList: root.filteredTracks()
            readonly property var stationList: root.filteredStations()
            readonly property var views: src === "radio" ? ["Popular", "Favorites"] : ["Discover", "Trending", "New", "Favorites"]
            readonly property int moodCols: cw >= 900 ? 6 : (cw >= 600 ? 3 : 2)
            readonly property real moodW: (cw - 12 * (moodCols - 1)) / moodCols
            readonly property int cols: Math.max(1, Math.floor((cw + 16) / 266))
            readonly property real cardW: (cw - 16 * (cols - 1)) / cols
            readonly property var mixList: src === "jamendo" ? trackList : (src === "radio" ? stationList : [])

            Flickable {
                id: mf
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: mp.dockW }
                contentWidth: width
                contentHeight: mcol.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                Column {
                    id: mcol
                    x: 24; y: 6
                    width: mf.width - 48
                    spacing: 16

                    RowLayout {
                        width: parent.width
                        spacing: 12
                        ColumnLayout {
                            spacing: 3
                            Lbl { text: "Music"; font.pixelSize: 26; font.weight: Font.Bold }
                            Lbl { text: "Free streaming from Jamendo and endless internet radio."; dim: true; font.pixelSize: 13 }
                        }
                        Item { Layout.fillWidth: true }
                        Btn { compact: true; icon: "list"; kind: root.queueOpen ? "primary" : "secondary"; accent: root.accent
                              label: (mp.wide ? (root.queueOpen ? "Hide queue" : "Show queue") : "Queue") + " (" + root.queue.length + ")"
                              onClicked: root.queueOpen = !root.queueOpen }
                    }

                    Card {
                        width: parent.width
                        visible: root.mprisPlayer !== null && root.mprisPlayer.trackTitle !== ""
                        tint: root.accent
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Art {
                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 58
                                radiusPx: 10
                                frameColor: pal.cont
                                src: root.mprisPlayer ? root.mprisPlayer.trackArtUrl : ""
                                grad: [pal.low, "#2a1b5e", "#0e4a6b"]
                                glyph: "music"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    Lbl { text: "NOW PLAYING"; mono: true; faint: true; font.pixelSize: 10 }
                                    Item { Layout.fillWidth: true }
                                    Lbl {
                                        text: root.mprisPlayer
                                            ? (root.mprisPlayer.isPlaying ? "PLAYING" : "PAUSED")
                                            : ""
                                        mono: true
                                        color: root.mprisPlayer && root.mprisPlayer.isPlaying ? "#86efac" : pal.dim
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: MediaNowPlaying.players
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool selected: root.mprisPlayer === modelData
                                            implicitWidth: playerName.implicitWidth + 18
                                            implicitHeight: 22
                                            radius: 11
                                            color: selected ? Qt.alpha(root.accent, 0.18) : pal.low
                                            border.width: selected ? 1 : 0
                                            border.color: Qt.alpha(root.accent, 0.5)
                                            Text {
                                                id: playerName
                                                anchors.centerIn: parent
                                                text: modelData.identity || modelData.desktopEntry || "Media player"
                                                color: parent.selected ? root.accent : pal.dim
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: MediaNowPlaying.choosePlayer(modelData)
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: MediaNowPlaying.preferredPlayerId !== ""
                                        implicitWidth: automaticLabel.implicitWidth + 18
                                        implicitHeight: 22
                                        radius: 11
                                        color: pal.low
                                        Text {
                                            id: automaticLabel
                                            anchors.centerIn: parent
                                            text: "Automatic"
                                            color: pal.dim
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: MediaNowPlaying.automaticPlayerSelection()
                                        }
                                    }
                                }
                                Lbl {
                                    Layout.fillWidth: true
                                    text: root.mprisPlayer ? root.mprisPlayer.trackTitle : ""
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Lbl {
                                    Layout.fillWidth: true
                                    text: root.mprisPlayer
                                        ? [root.mprisPlayer.trackArtist, root.mprisPlayer.trackAlbum].filter(function (value) { return value !== "" }).join(" \u00b7 ")
                                        : ""
                                    dim: true
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    radius: 3
                                    color: pal.low
                                    visible: root.mprisPlayer && root.mprisPlayer.length > 0
                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, root.mprisPlayer && root.mprisPlayer.length > 0
                                            ? root.mprisPosition / root.mprisPlayer.length : 0))
                                        height: parent.height
                                        radius: parent.radius
                                        color: root.accent
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.mprisPlayer && root.mprisPlayer.canSeek && root.mprisPlayer.length > 0
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: (mouse) => {
                                            if (!enabled) return
                                            const target = Math.max(0, Math.min(1, mouse.x / width)) * root.mprisPlayer.length
                                            if (typeof root.mprisPlayer.seekTo === "function")
                                                root.mprisPlayer.seekTo(target)
                                            else
                                                root.mprisPlayer.position = target
                                        }
                                    }
                                }
                            }
                            IconBtn {
                                box: 34
                                icon: "back"
                                tip: "Previous"
                                active: root.mprisPlayer && root.mprisPlayer.canGoPrevious
                                onClicked: if (active) root.mprisPlayer.previous()
                            }
                            IconBtn {
                                box: 38
                                icon: root.mprisPlayer && root.mprisPlayer.isPlaying ? "pause" : "play"
                                tip: root.mprisPlayer && root.mprisPlayer.isPlaying ? "Pause" : "Play"
                                active: root.mprisPlayer && (root.mprisPlayer.canTogglePlaying || root.mprisPlayer.canPlay || root.mprisPlayer.canPause)
                                onClicked: {
                                    if (!root.mprisPlayer) return
                                    if (root.mprisPlayer.canTogglePlaying) root.mprisPlayer.togglePlaying()
                                    else if (root.mprisPlayer.isPlaying && root.mprisPlayer.canPause) root.mprisPlayer.pause()
                                    else if (!root.mprisPlayer.isPlaying && root.mprisPlayer.canPlay) root.mprisPlayer.play()
                                }
                            }
                            IconBtn {
                                box: 34
                                icon: "chev"
                                tip: "Next"
                                active: root.mprisPlayer && root.mprisPlayer.canGoNext
                                onClicked: if (active) root.mprisPlayer.next()
                            }
                        }
                    }

                    ColumnLayout {
                        width: parent.width
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Btn {
                                compact: true
                                icon: root.mprisLyricsOpen ? "close" : "lyrics"
                                label: root.mprisLyricsOpen ? "Hide lyrics" : "Lyrics"
                                onClicked: {
                                    root.mprisLyricsOpen = !root.mprisLyricsOpen
                                    if (root.mprisLyricsOpen) root.lookupMprisLyrics()
                                }
                            }
                            Lbl {
                                Layout.fillWidth: true
                                text: root.mprisLyricsResult
                                    ? (root.mprisLyricsResult.status === "synced" ? "Synced lyrics"
                                        : (root.mprisLyricsResult.status === "plain" ? "Plain lyrics" : "No lyrics found"))
                                    : (MediaLyrics.loading && MediaLyrics.requestKey === root.mprisLyricsKey
                                        ? "Looking up lyrics\u2026"
                                        : (MediaLyrics.errorKey === root.mprisLyricsKey ? "Lyrics unavailable"
                                            : "LRCLIB lyrics"))
                                mono: true
                                faint: true
                                font.pixelSize: 10
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 154 : 0
                            visible: root.mprisLyricsOpen && root.mprisLyricsResult
                                && root.mprisLyricsResult.status === "synced"
                            clip: true
                            spacing: 4
                            model: visible ? root.mprisLyricsResult.lines : []
                            delegate: Lbl {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                text: modelData.s
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                                color: index === root.mprisLyricsLineIndex ? root.accent : pal.dim
                                font.weight: index === root.mprisLyricsLineIndex ? Font.DemiBold : Font.Normal
                            }
                        }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? Math.min(154, plainLyricsText.implicitHeight) : 0
                            visible: root.mprisLyricsOpen && root.mprisLyricsResult
                                && root.mprisLyricsResult.status === "plain"
                            contentWidth: width
                            contentHeight: plainLyricsText.implicitHeight
                            clip: true
                            Text {
                                id: plainLyricsText
                                width: parent.width
                                text: root.mprisLyricsResult ? root.mprisLyricsResult.plain : ""
                                color: pal.dim
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                        Lbl {
                            Layout.fillWidth: true
                            visible: root.mprisLyricsOpen && root.mprisLyricsResult
                                && root.mprisLyricsResult.status === "none"
                            text: "No lyrics found for this track."
                            wrapMode: Text.WordWrap
                            dim: true
                            font.pixelSize: 12
                        }
                        Lbl {
                            Layout.fillWidth: true
                            visible: root.mprisLyricsOpen && MediaLyrics.errorKey === root.mprisLyricsKey
                            text: MediaLyrics.error ? MediaLyrics.error.message : "The lyrics provider could not be reached."
                            wrapMode: Text.WordWrap
                            dim: true
                            font.pixelSize: 12
                        }
                    }

                    // ---- source selection
                    Wrap {
                        id: srcWrap
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: root.musicSources
                            delegate: Rectangle {
                                id: sc2
                                readonly property bool sel: root.musicSource === modelData.id
                                width: (srcWrap.width - 24) / 3 < 220 ? srcWrap.width : (srcWrap.width - 24) / 3
                                height: 84
                                radius: 14
                                color: sh.containsMouse ? pal.high : pal.cont
                                border.width: sel ? 2 : 1
                                border.color: sel ? modelData.accent : pal.line
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Rectangle { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 44; height: 44; radius: 12; color: Qt.alpha(modelData.accent, 0.16)
                                            Ico { anchors.centerIn: parent; name: modelData.icon; size: 20; tint: modelData.accent } }
                                Column {
                                    x: 70; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 84
                                    spacing: 3
                                    Lbl { width: parent.width; text: modelData.name; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Lbl { width: parent.width; text: modelData.sub; dim: true; font.pixelSize: 11; elide: Text.ElideRight }
                                    Tag { text: root.musicSourceState(modelData.id); tint: root.musicSourceTint(modelData.id); px: 9 }
                                }
                                MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setMusicSource(modelData.id) }
                            }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: (mp.src === "jamendo" && !root.jamendoConfigured)
                            || root.musicError !== ""
                        tint: root.musicError !== "" ? "#ffb4ab" : "#fde047"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico {
                                name: "warn"
                                size: 18
                                tint: root.musicError !== "" ? "#ffb4ab" : "#fde047"
                            }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 13
                                  text: mp.src === "local"
                                      ? root.localError
                                      : (root.musicError !== ""
                                          ? ("Search failed: " + root.musicError + (root.musicErrorCode !== "" ? " (" + root.musicErrorCode + ")" : ""))
                                          : ("Jamendo needs a client ID. Set JAMENDO_CLIENT_ID or add music.jamendoClientId to "
                                             + (root.jamendoConfigPath !== "" ? root.jamendoConfigPath : "~/.config/quickshell/rice-settings.json")
                                             + ". Radio Browser remains available without an account."
                                             + (root.musicStatusMessage !== "" ? " " + root.musicStatusMessage : ""))) }
                            Btn { visible: mp.src !== "local" && root.musicError !== ""; compact: true; icon: "refresh"; label: "Retry"
                                  onClicked: root.runMusicSearch() }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: root.musicLoading
                        tint: root.accent
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "search"; size: 18; tint: root.accent }
                            Lbl { Layout.fillWidth: true; dim: true; font.pixelSize: 13
                                  text: "Searching " + (mp.src === "radio" ? "Radio Browser" : "Jamendo") + " for live results\u2026" }
                        }
                    }

                    // ---- mood discovery
                    ColumnLayout {
                        width: parent.width
                        spacing: 10
                        visible: mp.src !== "local"
                        RowLayout {
                            Layout.fillWidth: true
                            Lbl { text: "Mood discovery"; font.pixelSize: 16; font.weight: Font.Bold }
                            Item { Layout.fillWidth: true }
                            Btn { compact: true; icon: "vibe"; label: "Match my GPS vibe"; onClicked: { root.musicMood = mp.vibeMood; root.notify("Matched " + root.mood.name + " \u2192 " + mp.vibeMood, "ok") } }
                            Btn { compact: true; kind: "ghost"; icon: "close"; label: "Clear"; visible: root.musicMood !== ""; onClicked: root.musicMood = "" }
                        }
                        Wrap {
                            id: moodWrap
                            Layout.fillWidth: true
                            spacing: 12
                            Repeater {
                                model: root.musicMoods
                                delegate: Rectangle {
                                    id: mood
                                    readonly property bool sel: root.musicMood === modelData.name
                                    width: mp.moodW
                                    height: 84
                                    radius: 14
                                    color: pal.cont
                                    border.width: sel ? 2 : 1
                                    border.color: sel ? modelData.accent : pal.line
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    HoverHandler { id: mh2 }
                                    scale: mh2.hovered ? 1.02 : 1
                                    Behavior on scale { NumberAnimation { duration: 160 } }
                                    Art { x: 4; y: 4; width: parent.width - 8; height: parent.height - 8; radiusPx: 11; frameColor: mood.color; grad: modelData.g; glyph: "music"; zoom: mh2.hovered ? 1.06 : 1 }
                                    Rectangle { x: 4; y: 4; width: parent.width - 8; height: parent.height - 8; radius: 11; color: mood.sel ? "#33000000" : "#55000000" }
                                    Column {
                                        x: 14; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24
                                        spacing: 2
                                        Lbl { width: parent.width; text: modelData.name; font.pixelSize: 14; font.weight: Font.Bold; elide: Text.ElideRight }
                                        Lbl { width: parent.width; text: modelData.desc; elide: Text.ElideRight; mono: true; font.pixelSize: 10; color: "#cfd6e6" }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.musicMood = mood.sel ? "" : modelData.name }
                                }
                            }
                        }
                    }

                    // ---- vibe mix hero
                    Card {
                        width: parent.width
                        visible: mp.src !== "local"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 18
                            Art {
                                Layout.preferredWidth: 150; Layout.preferredHeight: 94
                                radiusPx: 12; frameColor: pal.low
                                grad: (root.moodInfo(mp.activeMood) ? root.moodInfo(mp.activeMood).g : root.mood.grad)
                                glyph: "music"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Tag { text: mp.activeMood !== "" ? "MOOD MIX" : "LIVE CATALOGUE"; tint: root.accent }
                                Lbl { Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 19; font.weight: Font.Bold
                                      text: mp.activeMood !== "" ? (mp.activeMood + " mix") : "Everything mix" }
                                Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12
                                      text: (root.musicLoading ? "Loading" : mp.mixList.length + " live " + (mp.src === "radio" ? "station" : "track") + (mp.mixList.length === 1 ? "" : "s"))
                                            + (mp.vibeMood !== "" ? " \u00b7 GPS vibe suggests " + mp.vibeMood : "") }
                            }
                            Btn { kind: "primary"; accent: root.accent; icon: "play"; label: "Play mix"; muted: root.musicLoading; onClicked: root.playCurrentMusicList(false) }
                            Btn { icon: "sync"; label: mp.wide ? "Shuffle" : ""; muted: root.musicLoading; onClicked: root.playCurrentMusicList(true) }
                        }
                    }

                    // ---- web search shortcuts
                    Card {
                        width: parent.width
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Lbl { text: "Search music services"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Lbl { text: "Opens your browser"; mono: true; faint: true; font.pixelSize: 10 }
                            }
                            SearchField {
                                Layout.fillWidth: true
                                accent: root.accent
                                placeholder: "Search YouTube Music, JioSaavn or Spotify"
                                text: root.musicWebSearchQuery
                                onEdited: root.musicWebSearchQuery = text
                                onSubmitted: root.openMusicWebSearch("youtube")
                            }
                            Wrap {
                                width: parent.width
                                spacing: 8
                                Btn {
                                    compact: true
                                    icon: "search"
                                    label: "YouTube Music"
                                    onClicked: root.openMusicWebSearch("youtube")
                                }
                                Btn {
                                    compact: true
                                    icon: "search"
                                    label: "JioSaavn"
                                    onClicked: root.openMusicWebSearch("jiosaavn")
                                }
                                Btn {
                                    compact: true
                                    icon: "search"
                                    label: "Spotify"
                                    onClicked: root.openMusicWebSearch("spotify")
                                }
                            }
                        }
                    }

                    // ---- local library controls
                    Card {
                        width: parent.width
                        visible: mp.src === "local"
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Lbl { text: "Local library"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Btn {
                                    compact: true
                                    icon: "folder"
                                    label: "Choose folder"
                                    onClicked: localMusicFolderDialog.open()
                                }
                                Btn {
                                    compact: true
                                    icon: "refresh"
                                    label: "Rescan"
                                    muted: root.localLoading
                                    onClicked: root.reloadLocalLibrary()
                                }
                            }
                            Lbl {
                                Layout.fillWidth: true
                                text: root.localMusicDir
                                elide: Text.ElideMiddle
                                mono: true
                                faint: true
                                font.pixelSize: 10
                            }
                            SearchField {
                                Layout.fillWidth: true
                                accent: root.accent
                                placeholder: "Search local tracks, artists, albums or genres"
                                text: root.musicQuery
                                onEdited: root.musicQuery = text
                            }
                            Lbl {
                                Layout.fillWidth: true
                                text: root.localLoading
                                    ? "Scanning audio tags with ffprobe\u2026"
                                    : (root.localError !== "" ? root.localError
                                        : (root.localLoaded
                                            ? root.localIndexedCount + " tracks indexed"
                                                + (root.localSkippedCount > 0 ? " \u00b7 " + root.localSkippedCount + " files skipped" : "")
                                                + (root.localIndexedCount > 200 ? " \u00b7 showing up to 200; search to narrow" : "")
                                            : "Select Rescan to index this folder."))
                                color: root.localError !== "" ? "#ffb4ab" : pal.dim
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                            }
                        }
                    }

                    // ---- search + views
                    Card {
                        width: parent.width
                        visible: mp.src !== "local"
                        SearchField {
                            Layout.fillWidth: true
                            accent: root.accent
                            placeholder: mp.src === "radio" ? "Search stations or genres" : "Search tracks, artists or albums"
                            text: root.musicQuery
                            onEdited: root.musicQuery = text
                            onSubmitted: root.runMusicSearch()
                        }
                        SearchField {
                            visible: mp.src === "radio"
                            Layout.fillWidth: true
                            icon: "cloud"
                            accent: "#7bd0ff"
                            placeholder: "Filter by country (optional)"
                            text: root.radioCountry
                            onEdited: root.radioCountry = text
                            onSubmitted: root.runMusicSearch()
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: mp.views
                                delegate: Chip { label: modelData; accent: root.accent; active: root.musicView === modelData; onClicked: root.musicView = modelData }
                            }
                        }
                        Wrap {
                            visible: mp.src === "radio"
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.radioGenres
                                delegate: Chip { label: modelData; accent: "#7bd0ff"; active: root.radioGenre === modelData; onClicked: root.radioGenre = modelData }
                            }
                        }
                        Lbl {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            faint: true
                            font.pixelSize: 11
                            text: mp.src === "radio"
                                ? "Live directory data from Radio Browser. Stream quality and availability depend on each station."
                                : "Creative Commons tracks streamed from Jamendo. Artist and licence details come from the catalogue."
                        }
                    }

                    // ---- Jamendo tracks
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: mp.src === "jamendo"
                        Lbl { mono: true; faint: true; font.pixelSize: 11
                              text: (root.musicLoading ? "Searching Jamendo\u2026" : (mp.trackList.length + " live track" + (mp.trackList.length === 1 ? "" : "s")))
                                    + (root.musicMood !== "" ? " \u00b7 " + root.musicMood : "") }
                        Repeater {
                            model: mp.trackList
                            delegate: Rectangle {
                                id: row
                                readonly property bool cur: root.nowPlaying !== null && root.nowPlaying.id === modelData.id
                                width: parent.width
                                height: 58
                                radius: 12
                                color: rh2.containsMouse ? pal.high : (cur ? Qt.alpha(root.accent, 0.10) : pal.low)
                                border.width: 1
                                border.color: cur ? Qt.alpha(root.accent, 0.45) : pal.line
                                Behavior on color { ColorAnimation { duration: 140 } }
                                MouseArea { id: rh2; anchors.fill: parent; hoverEnabled: true; onDoubleClicked: root.playNow(modelData, mp.trackList) }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                    spacing: 12
                                    Lbl { Layout.preferredWidth: 22; horizontalAlignment: Text.AlignHCenter; mono: true; font.pixelSize: 11
                                          text: row.cur ? (root.playing ? "\u25B6" : "\u2016") : (index + 1); color: row.cur ? root.accent : pal.faint }
                                    Art { Layout.preferredWidth: 40; Layout.preferredHeight: 40; radiusPx: 8; frameColor: row.color; src: root.artUrl(modelData.art); grad: modelData.g; glyph: "music" }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Lbl { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold; color: row.cur ? root.accent : pal.text }
                                        Lbl { Layout.fillWidth: true; text: root.musicSub(modelData); elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
                                    }
                                    Tag { visible: mp.cw > 760 && modelData.genre !== ""; text: modelData.genre.toUpperCase(); px: 9 }
                                    Tag { visible: mp.cw > 640; text: modelData.license; tint: "#86efac"; px: 9 }
                                    Lbl { text: root.fmtTime(modelData.dur); mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
                                    IconBtn { visible: modelData.sourceUrl !== ""; box: 30; icon: "link"; tip: "Open on Jamendo"
                                              onClicked: root.openMusicSource(modelData.sourceUrl) }
                                    IconBtn { box: 30; icon: root.favorites[modelData.id] ? "heart" : "heartO"; active: !!root.favorites[modelData.id]; tip: "Favorite"
                                              onClicked: root.toggleFavorite(modelData.id, modelData.title) }
                                    IconBtn { box: 30; icon: "plus"; tip: "Add to queue"; onClicked: root.queueAdd(modelData, false) }
                                    IconBtn { box: 30; icon: "chev"; tip: "Play next"; onClicked: root.queueAdd(modelData, true) }
                                    IconBtn { box: 30; icon: "play"; tip: "Play"; tint: root.accent; onClicked: root.playNow(modelData, mp.trackList) }
                                }
                            }
                        }
                        Card {
                            width: parent.width
                            visible: mp.trackList.length === 0 && !root.musicLoading && root.musicError === "" && root.jamendoConfigured
                            Lbl { font.pixelSize: 15; font.weight: Font.DemiBold; text: root.musicView === "Favorites" ? "No favorite tracks yet" : "No tracks match" }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true
                                  text: root.musicView === "Favorites" ? "Heart a few live tracks to keep them in My Library and this view."
                                                                        : "Try a shorter search, clear the mood, or press Enter to retry the catalogue." }
                            Btn { label: "Clear mood & search"; icon: "refresh"; onClicked: { root.musicMood = ""; root.musicQuery = ""; root.musicView = "Discover" } }
                        }
                    }

                    // ---- local tracks
                    Column {
                        width: parent.width
                        spacing: 6
                        visible: mp.src === "local"
                        Lbl {
                            mono: true
                            faint: true
                            font.pixelSize: 11
                            text: root.localLoading ? "Indexing local music\u2026"
                                : (root.filteredTracks().length + " local track" + (root.filteredTracks().length === 1 ? "" : "s"))
                        }
                        Repeater {
                            model: root.filteredTracks()
                            delegate: Rectangle {
                                id: localTrackRow
                                readonly property bool cur: root.nowPlaying !== null && root.nowPlaying.id === modelData.id
                                width: parent.width
                                height: 58
                                radius: 12
                                color: localTrackHover.containsMouse ? pal.high : (cur ? Qt.alpha(root.accent, 0.10) : pal.low)
                                border.width: 1
                                border.color: cur ? Qt.alpha(root.accent, 0.45) : pal.line
                                MouseArea {
                                    id: localTrackHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onDoubleClicked: root.playNow(modelData, root.filteredTracks())
                                }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                    spacing: 12
                                    Lbl {
                                        Layout.preferredWidth: 22
                                        horizontalAlignment: Text.AlignHCenter
                                        mono: true
                                        font.pixelSize: 11
                                        text: localTrackRow.cur ? (root.playing ? "\u25B6" : "\u2016") : (index + 1)
                                        color: localTrackRow.cur ? root.accent : pal.faint
                                    }
                                    Art {
                                        Layout.preferredWidth: 40
                                        Layout.preferredHeight: 40
                                        radiusPx: 8
                                        frameColor: localTrackRow.color
                                        src: root.artUrl(modelData.art)
                                        grad: modelData.g
                                        glyph: "music"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Lbl {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            color: localTrackRow.cur ? root.accent : pal.text
                                        }
                                        Lbl {
                                            Layout.fillWidth: true
                                            text: root.musicSub(modelData)
                                            elide: Text.ElideRight
                                            dim: true
                                            font.pixelSize: 11
                                        }
                                    }
                                    Tag { visible: mp.cw > 760 && modelData.genre !== ""; text: modelData.genre.toUpperCase(); px: 9 }
                                    Lbl {
                                        text: root.fmtTime(modelData.dur)
                                        mono: true
                                        faint: true
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 38
                                        horizontalAlignment: Text.AlignRight
                                    }
                                    IconBtn {
                                        box: 30
                                        icon: root.favorites[modelData.id] ? "heart" : "heartO"
                                        active: !!root.favorites[modelData.id]
                                        tip: "Favorite"
                                        onClicked: root.toggleFavorite(modelData.id, modelData.title)
                                    }
                                    IconBtn { box: 30; icon: "plus"; tip: "Add to queue"; onClicked: root.queueAdd(modelData, false) }
                                    IconBtn { box: 30; icon: "chev"; tip: "Play next"; onClicked: root.queueAdd(modelData, true) }
                                    IconBtn { box: 30; icon: "play"; tip: "Play"; tint: root.accent; onClicked: root.playNow(modelData, root.filteredTracks()) }
                                }
                            }
                        }
                        Card {
                            width: parent.width
                            visible: root.filteredTracks().length === 0 && !root.localLoading
                            Lbl {
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                text: root.localError !== "" ? "Local library unavailable"
                                    : (root.musicView === "Favorites" ? "No local favorites yet" : "No local tracks found")
                            }
                            Lbl {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                dim: true
                                text: root.localError !== "" ? root.localError
                                    : (root.musicView === "Favorites" ? "Favorite a track to keep it in My Library."
                                        : "Choose a music folder containing audio files, then rescan.")
                            }
                        }
                    }

                    // ---- radio stations
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: mp.src === "radio"
                        Lbl { mono: true; faint: true; font.pixelSize: 11
                              text: root.musicLoading ? "Searching Radio Browser\u2026"
                                                      : (mp.stationList.length + " live station" + (mp.stationList.length === 1 ? "" : "s")
                                                         + " \u00b7 pick one and Next/Previous move through this list") }
                        Wrap {
                            width: parent.width
                            spacing: 16
                            Repeater {
                                model: mp.stationList
                                delegate: MediaCard {
                                    width: mp.cardW
                                    title: modelData.title
                                    meta: modelData.genre + " \u00b7 " + modelData.codec
                                          + (modelData.bitrate > 0 ? " \u00b7 " + modelData.bitrate + " kbps" : "")
                                    extra: modelData.votes.toLocaleString(Qt.locale("en_US"), "f", 0)
                                           + " community vote" + (modelData.votes === 1 ? "" : "s") + " \u00b7 " + modelData.country
                                    badge: "LIVE"
                                    corner: modelData.codec
                                    grad: modelData.g
                                    glyph: "music"
                                    aspect: 1.9
                                    accent: "#7bd0ff"
                                    selected: root.nowPlaying !== null && root.nowPlaying.id === modelData.id
                                    fav: !!root.favorites[modelData.id]
                                    showPreview: true
                                    previewIcon: "plus"
                                    previewTip: "Add to queue"
                                    showSource: modelData.sourceUrl !== ""
                                    primaryLabel: "Listen"
                                    primaryIcon: "play"
                                    onActivated: root.playNow(modelData, mp.stationList)
                                    onPrimary: root.playNow(modelData, mp.stationList)
                                    onPreviewed: root.queueAdd(modelData, false)
                                    onFavToggled: root.toggleFavorite(modelData.id, modelData.title)
                                    onSourceRequested: root.openMusicSource(modelData.sourceUrl)
                                }
                            }
                        }
                        Card {
                            width: parent.width
                            visible: mp.stationList.length === 0 && !root.musicLoading && root.musicError === ""
                            Lbl { font.pixelSize: 15; font.weight: Font.DemiBold; text: root.musicView === "Favorites" ? "No favorite stations yet" : "No stations match" }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true
                                  text: root.musicView === "Favorites" ? "Heart a live station to keep it here and in My Library."
                                                                        : "Try another genre or country, clear the mood, or adjust the search." }
                            Btn { label: "Reset"; icon: "refresh"; onClicked: { root.musicMood = ""; root.musicQuery = ""; root.radioGenre = "All"; root.radioCountry = ""; root.musicView = "Popular" } }
                        }
                    }

                    // ---- narrow layouts: queue sits below the content
                    Loader {
                        width: parent.width
                        height: item ? item.implicitHeight : 0
                        active: !mp.wide && root.queueOpen
                        sourceComponent: queuePanelC
                    }
                }
            }

            // ---- docked queue (wide)
            Item {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 330
                opacity: (mp.wide && root.queueOpen) ? 1 : 0
                visible: opacity > 0.01
                clip: true
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Loader { anchors.fill: parent; anchors.rightMargin: 24; anchors.bottomMargin: 10; anchors.topMargin: 6; active: mp.wide && (root.queueOpen || mp.dockW > 1); sourceComponent: queuePanelC }
            }
        }
    }

    Component {
        id: queuePanelC
        Rectangle {
            id: qp
            readonly property var np: root.nowPlaying
            color: pal.low
            radius: 16
            border.width: 1
            border.color: pal.line
            implicitHeight: Math.min(560, qcol.implicitHeight + 32)
            Flickable {
                id: qf
                anchors { fill: parent; margins: 16 }
                contentWidth: width
                contentHeight: qcol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                ColumnLayout {
                    id: qcol
                    width: qf.width - 6
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Lbl { text: "Queue"; font.pixelSize: 16; font.weight: Font.Bold }
                        Lbl { text: "  " + root.queue.length + " item" + (root.queue.length === 1 ? "" : "s"); mono: true; faint: true; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                        Btn { compact: true; kind: "ghost"; label: "Clear"; icon: "close"; muted: root.queue.length === 0; onClicked: root.clearQueue() }
                    }
                    Lbl { text: "NOW PLAYING"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        radius: 12
                        color: Qt.alpha(root.accent, 0.10)
                        border.width: 1
                        border.color: Qt.alpha(root.accent, 0.4)
                        visible: qp.np !== null
                        Art { x: 8; y: 8; width: 46; height: 46; radiusPx: 8; frameColor: pal.cont; src: qp.np ? root.artUrl(qp.np.art) : ""; grad: qp.np ? qp.np.g : [pal.low, "#2a1b5e", "#0e4a6b"]; glyph: "music" }
                        Column {
                            x: 64; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 76; spacing: 2
                            Lbl { width: parent.width; text: qp.np ? qp.np.title : ""; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Lbl { width: parent.width; text: qp.np ? root.musicSub(qp.np) : ""; elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
                        }
                    }
                    Lbl { visible: qp.np === null; Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 12; text: "Nothing playing. Press play on a track or station." }
                    Lbl { text: "UP NEXT"; mono: true; faint: true; font.pixelSize: 10; font.letterSpacing: 1 }
                    Repeater {
                        model: root.queue
                        delegate: Rectangle {
                            id: qr
                            readonly property var it: root.musicItem(modelData)
                            readonly property bool cur: index === root.queueIndex
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 10
                            color: qrh.containsMouse ? pal.high : (cur ? Qt.alpha(root.accent, 0.08) : pal.cont)
                            Behavior on color { ColorAnimation { duration: 130 } }
                            MouseArea { id: qrh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.jumpQueue(index) }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                spacing: 8
                                Lbl { Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter; mono: true; font.pixelSize: 10; text: qr.cur ? "\u25B6" : (index + 1); color: qr.cur ? root.accent : pal.faint }
                                Art { Layout.preferredWidth: 34; Layout.preferredHeight: 34; radiusPx: 6; frameColor: qr.color; src: qr.it ? root.artUrl(qr.it.art) : ""; grad: qr.it ? qr.it.g : [pal.low, "#2a1b5e", "#0e4a6b"]; glyph: "music" }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Lbl { Layout.fillWidth: true; text: qr.it ? qr.it.title : ""; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.DemiBold; color: qr.cur ? root.accent : pal.text }
                                    Lbl { Layout.fillWidth: true; text: qr.it ? (qr.it.kind === "station" ? "Live station" : qr.it.artist) : ""; elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
                                }
                                IconBtn { box: 24; icon: "chev"; tip: "Move down"; onClicked: root.moveQueue(index, 1) }
                                IconBtn { box: 24; icon: "back"; tip: "Move up"; onClicked: root.moveQueue(index, -1) }
                                IconBtn { box: 24; icon: "close"; tip: "Remove"; onClicked: root.removeFromQueue(index) }
                            }
                        }
                    }
                    Lbl { visible: root.queue.length === 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 12
                          text: "The queue is empty. Use + on a track, or play a mood mix." }
                    Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                          text: "Radio stations are endless streams: Next and Previous move between stations in the list you started from." }
                }
            }
        }
    }

    // ---------------------------------------------------------------- persistent mini-player
    Rectangle {
        id: miniPlayer
        anchors { left: sidebar.right; right: parent.right; bottom: parent.bottom }
        height: root.nowPlaying ? 76 : 0
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        visible: height > 1
        clip: true
        z: 30
        color: Qt.alpha(pal.lowest, 0.96)
        readonly property var np: root.nowPlaying
        readonly property bool live: np !== null && np.kind === "station"
        readonly property bool compactPlayer: (root.width - root.sidebarW) < 760
        readonly property real frac: (np !== null && np.kind === "track" && root.currentDuration > 0)
            ? Math.max(0, Math.min(1, root.playPos / root.currentDuration)) : 0
        readonly property string statusText: {
            if (root.musicPlaybackError !== "") return "Error: " + root.musicPlaybackError
            if (np === null) return ""
            if (live) return "LIVE \u00b7 " + (np.bitrate > 0 ? np.bitrate + " kbps \u00b7 " : "") + (np.codec || "audio")
            return (root.playing ? "Playing" : "Paused") + " \u00b7 " + root.fmtTime(root.playPos)
                   + " / " + root.fmtTime(root.currentDuration)
        }
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: pal.line }
        RowLayout {
            anchors { fill: parent; leftMargin: miniPlayer.compactPlayer ? 12 : 20; rightMargin: miniPlayer.compactPlayer ? 12 : 20; topMargin: 6; bottomMargin: 6 }
            spacing: miniPlayer.compactPlayer ? 10 : 14
            Art { Layout.preferredWidth: miniPlayer.compactPlayer ? 46 : 54; Layout.preferredHeight: miniPlayer.compactPlayer ? 46 : 54; radiusPx: 9; frameColor: pal.lowest
                  src: miniPlayer.np ? root.artUrl(miniPlayer.np.art) : ""; grad: miniPlayer.np ? miniPlayer.np.g : [pal.low, "#2a1b5e", "#0e4a6b"]; glyph: "music" }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: root.width < 1150 ? 150 : 230
                spacing: 2
                Lbl { Layout.fillWidth: true; text: miniPlayer.np ? miniPlayer.np.title : ""; elide: Text.ElideRight; font.pixelSize: 14; font.weight: Font.DemiBold }
                Lbl { Layout.fillWidth: true; text: miniPlayer.np ? root.musicSub(miniPlayer.np) : ""; elide: Text.ElideRight; dim: true; font.pixelSize: 11 }
                Lbl { visible: miniPlayer.compactPlayer; Layout.fillWidth: true; elide: Text.ElideRight; mono: true; font.pixelSize: 10
                      color: root.musicPlaybackError !== "" ? "#ffb4ab" : "#948e9d"
                      text: miniPlayer.statusText }
            }
            IconBtn { visible: !miniPlayer.compactPlayer && miniPlayer.np && miniPlayer.np.sourceUrl !== ""; box: 30; icon: "link"; tip: "Open source"
                      onClicked: { if (miniPlayer.np) root.openMusicSource(miniPlayer.np.sourceUrl) } }
            IconBtn { visible: !miniPlayer.compactPlayer; box: 30; icon: (miniPlayer.np && root.favorites[miniPlayer.np.id]) ? "heart" : "heartO"; active: miniPlayer.np ? !!root.favorites[miniPlayer.np.id] : false; tip: "Favorite"
                      onClicked: { if (miniPlayer.np) root.toggleFavorite(miniPlayer.np.id, miniPlayer.np.title) } }
            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                IconBtn { visible: root.width > 1000; box: 30; icon: "sync"; tip: "Shuffle"; active: root.shuffleOn; activeTint: root.accent; onClicked: root.shuffleOn = !root.shuffleOn }
                IconBtn { box: 34; icon: "back"; tip: "Previous"; onClicked: root.skip(-1) }
                Rectangle {
                    width: 42; height: 42; radius: 21
                    color: pph.containsMouse ? Qt.lighter(root.accent, 1.12) : root.accent
                    scale: pph.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                    Ico { anchors.centerIn: parent; name: root.playing ? "pause" : "play"; size: 16; tint: "#15112b" }
                    MouseArea { id: pph; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePlay() }
                }
                IconBtn { box: 34; icon: "chev"; tip: "Next"; onClicked: root.skip(1) }
                IconBtn { visible: root.width > 1000; box: 30; icon: "refresh"; tip: "Repeat queue"; active: root.repeatOn; activeTint: root.accent; onClicked: root.repeatOn = !root.repeatOn }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: !miniPlayer.compactPlayer && !miniPlayer.live
                RowLayout {
                    Layout.fillWidth: true
                    Lbl { text: miniPlayer.np ? root.fmtTime(root.playPos) : "0:00"; mono: true; faint: true; font.pixelSize: 11 }
                    Seek { Layout.fillWidth: true; value: miniPlayer.frac; tint: root.accent; onMoved: function (v) { root.seekFrac(v) } }
                    Lbl { text: root.currentDuration > 0 ? root.fmtTime(root.currentDuration) : "0:00"; mono: true; faint: true; font.pixelSize: 11 }
                }
                Lbl { Layout.fillWidth: true; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 10
                      color: root.musicPlaybackError !== "" ? "#ffb4ab" : "#948e9d"
                      text: root.musicPlaybackError !== "" ? ("Playback error: " + root.musicPlaybackError)
                                                           : ("Streaming \u00b7 " + (miniPlayer.np ? miniPlayer.np.license : "")) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: !miniPlayer.compactPlayer && miniPlayer.live
                Row { spacing: 8
                    Tag { text: "LIVE"; tint: "#ff7a8a" }
                    Lbl { anchors.verticalCenter: parent.verticalCenter
                          text: miniPlayer.np
                              ? ((miniPlayer.np.bitrate > 0 ? miniPlayer.np.bitrate + " kbps \u00b7 " : "")
                                 + (miniPlayer.np.codec || "audio") + " \u00b7 endless stream")
                              : ""
                          mono: true; faint: true; font.pixelSize: 11 }
                }
                Lbl { Layout.fillWidth: true; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 10
                      color: root.musicPlaybackError !== "" ? "#ffb4ab" : "#948e9d"
                      text: root.musicPlaybackError !== "" ? ("Playback error: " + root.musicPlaybackError)
                                                           : "Live radio \u00b7 no seeking or fixed duration" }
            }
            Row {
                visible: root.width > 1050
                spacing: 6
                Layout.alignment: Qt.AlignVCenter
                IconBtn { box: 28; icon: root.muted ? "close" : "music"; tip: root.muted ? "Unmute" : "Mute"; active: root.muted; activeTint: "#fde047"; onClicked: root.muted = !root.muted }
                Seek { width: 84; anchors.verticalCenter: parent.verticalCenter; value: root.muted ? 0 : root.volume; tint: "#cac4d4"; onMoved: function (v) { root.volume = v; root.muted = false } }
            }
            Btn { visible: !miniPlayer.compactPlayer; compact: true; icon: "list"; label: root.width > 1100 ? ("Queue (" + root.queue.length + ")") : ""; onClicked: { root.queueOpen = true; root.go(root.pgMusic) } }
            IconBtn { box: 28; icon: "close"; tip: "Stop and hide player"; onClicked: root.stopPlayer() }
        }
    }

    // ================================================================
    //  DOWNLOADS
    // ================================================================
    Component {
        id: dlPage
        Item {
            id: dp
            property string mode: "video"
            property string format: "MP4"
            property string quality: "1080p"
            property string dir: "~/Videos/GPS"
            property string urlText: ""
            property string err: ""
            property string filter: "All"
            readonly property var formats: mode === "video" ? ["MP4", "MKV", "WebM"] : ["MP3", "M4A", "FLAC", "Opus"]
            readonly property var qualities: mode === "video" ? ["Best", "1080p", "720p", "480p"] : ["320k", "256k", "192k", "128k"]
            readonly property var filters: ["All", "Downloading", "Queued", "Completed", "Failed"]
            readonly property var rows: root.downloads.filter(function (d) {
                if (dp.filter === "All") return true
                if (dp.filter === "Downloading") return d.status === "downloading" || d.status === "paused"
                return d.status === dp.filter.toLowerCase()
            })
            function countFor(f) {
                var n = 0
                for (var i = 0; i < root.downloads.length; i++) {
                    var s = root.downloads[i].status
                    if (f === "All" || (f === "Downloading" && (s === "downloading" || s === "paused")) || s === f.toLowerCase()) n++
                }
                return n
            }
            function setMode(m) {
                mode = m
                format = m === "video" ? "MP4" : "MP3"
                quality = m === "video" ? "1080p" : "320k"
                dir = m === "video" ? "~/Videos/GPS" : "~/Music/GPS"
            }
            function submit() {
                var u = urlText.trim()
                if (u === "") { err = "Paste a video or audio URL first."; return }
                if (!/^https?:\/\/[^\s\/$.?#][^\s]*$/i.test(u)) { err = "That doesn't look like a valid http(s) URL."; return }
                if (dir.trim() === "") { err = "Choose an output folder."; return }
                for (var i = 0; i < root.downloads.length; i++)
                    if (root.downloads[i].url === u) { err = "This URL is already in the queue."; return }
                err = ""
                root.enqueue(u, mode, format, quality, dir.trim())
                urlText = ""
            }
            function consumePending() {
                if (root.pendingUrl !== "") { urlText = root.pendingUrl; root.pendingUrl = ""; err = "" }
            }
            Component.onCompleted: consumePending()
            Connections { target: root; function onPendingUrlChanged() { dp.consumePending() } }

            Flickable {
                id: df2
                anchors.fill: parent
                contentWidth: width
                contentHeight: dcol2.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                Column {
                    id: dcol2
                    x: 24; y: 6
                    width: df2.width - 48
                    spacing: 16

                    RowLayout {
                        width: parent.width
                        ColumnLayout {
                            spacing: 3
                            Lbl { text: "Downloads"; font.pixelSize: 26; font.weight: Font.Bold }
                            Lbl { text: "Prepare video and audio downloads. Nothing starts without you pressing Add."; dim: true; font.pixelSize: 13 }
                        }
                        Item { Layout.fillWidth: true }
                        Tag { visible: df2.width > 700; text: "SAMPLE QUEUE"; tint: "#fde047" }
                    }

                    Card {
                        width: parent.width
                        visible: !root.downloadBackendConnected
                        tint: "#fde047"
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Ico { name: "warn"; size: 18; tint: "#fde047" }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; font.pixelSize: 13
                                  text: "Download backend not connected. yt-dlp and FFmpeg will run here in a future build. The records below are samples; progress does not advance, and pause, resume and retry only change the UI." }
                        }
                    }

                    Card {
                        width: parent.width
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            SearchField {
                                Layout.fillWidth: true
                                icon: "link"
                                accent: root.accent
                                placeholder: "Paste a video or audio URL (https://...)"
                                text: dp.urlText
                                onEdited: { dp.urlText = text; dp.err = "" }
                                onSubmitted: dp.submit()
                            }
                            Btn { kind: "primary"; accent: root.accent; icon: "plus"; label: "Add to Queue"; onClicked: dp.submit() }
                        }
                        Lbl { visible: dp.err !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: dp.err; color: "#ffb4ab"; font.pixelSize: 12 }
                        Lbl { visible: dp.err === ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; faint: true; font.pixelSize: 11
                              text: "Pasting or clipboard changes never start a download. Press Add to Queue (or Enter) deliberately." }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Mode"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
                            Chip { label: "Video"; icon: "video"; accent: root.accent; active: dp.mode === "video"; onClicked: dp.setMode("video") }
                            Chip { label: "Audio"; icon: "music"; accent: root.accent; active: dp.mode === "audio"; onClicked: dp.setMode("audio") }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Format"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
                            Wrap { Layout.fillWidth: true; spacing: 8
                                Repeater { model: dp.formats; delegate: Chip { label: modelData; accent: root.accent; active: dp.format === modelData; onClicked: dp.format = modelData } } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Quality"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
                            Wrap { Layout.fillWidth: true; spacing: 8
                                Repeater { model: dp.qualities; delegate: Chip { label: modelData; accent: root.accent; active: dp.quality === modelData; onClicked: dp.quality = modelData } } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Save to"; mono: true; faint: true; font.pixelSize: 11; Layout.preferredWidth: 60 }
                            SearchField { Layout.fillWidth: true; icon: "folder"; accent: root.accent; placeholder: "Output folder"; text: dp.dir; onEdited: dp.dir = text }
                            Btn { compact: true; label: "Browse\u2026"; onClicked: root.notify("A folder picker needs the host (e.g. a FolderDialog). Type a path for now.", "info") }
                        }
                    }

                    Wrap {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: dp.filters
                            delegate: Chip { label: modelData; accent: root.accent; active: dp.filter === modelData; badge: "" + dp.countFor(modelData); onClicked: dp.filter = modelData }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: dp.rows
                            delegate: Rectangle {
                                id: dr
                                readonly property bool failed: modelData.status === "failed"
                                width: parent.width
                                height: failed ? 98 : 80
                                radius: 12
                                color: pal.cont
                                border.width: 1
                                border.color: failed ? Qt.alpha(pal.err, 0.35) : pal.line
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
                                    spacing: 14
                                    Rectangle {
                                        Layout.preferredWidth: 42; Layout.preferredHeight: 42; radius: 11
                                        color: Qt.alpha(modelData.type === "video" ? "#7bd0ff" : "#ddb8ff", 0.15)
                                        Ico { anchors.centerIn: parent; name: modelData.type === "video" ? "video" : "music"; size: 16; tint: modelData.type === "video" ? "#7bd0ff" : "#ddb8ff" }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Lbl { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            Tag { px: 9
                                                  text: modelData.status.toUpperCase()
                                                  tint: modelData.status === "completed" ? "#86efac" : (modelData.status === "failed" ? "#ffb4ab" : (modelData.status === "downloading" ? "#7bd0ff" : (modelData.status === "paused" ? "#fde047" : "#cac4d4"))) }
                                        }
                                        Lbl { Layout.fillWidth: true; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 11
                                              text: modelData.format + " \u00b7 " + modelData.quality + " \u00b7 " + modelData.dest + " \u00b7 " + modelData.size }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: modelData.progress > 0 && modelData.status !== "queued"
                                            spacing: 10
                                            Bar { Layout.fillWidth: true; height: 5; value: modelData.progress; tint: modelData.status === "completed" ? "#86efac" : (dr.failed ? "#ffb4ab" : "#7bd0ff") }
                                            Lbl { text: Math.round(modelData.progress * 100) + "%"; mono: true; font.pixelSize: 11; dim: true }
                                        }
                                        Lbl { visible: dr.failed; Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.error; color: "#ffb4ab"; font.pixelSize: 12 }
                                    }
                                    Row {
                                        spacing: 6
                                        IconBtn { visible: modelData.status === "downloading"; icon: "pause"; tip: "Pause"; onClicked: root.dlAction(modelData, "pause") }
                                        IconBtn { visible: modelData.status === "paused"; icon: "play"; tip: "Resume"; onClicked: root.dlAction(modelData, "resume") }
                                        IconBtn { visible: dr.failed; icon: "refresh"; tip: "Retry"; onClicked: root.dlAction(modelData, "retry") }
                                        IconBtn { visible: modelData.status === "completed"; icon: "folder"; tip: "Open location"; onClicked: root.dlAction(modelData, "open") }
                                        IconBtn { icon: "close"; tip: (modelData.status === "completed" || dr.failed) ? "Remove" : "Cancel"
                                                  onClicked: root.dlAction(modelData, (modelData.status === "completed" || dr.failed) ? "remove" : "cancel") }
                                    }
                                }
                            }
                        }
                        Card {
                            width: parent.width
                            visible: dp.rows.length === 0
                            Lbl { font.pixelSize: 15; font.weight: Font.DemiBold; text: dp.filter === "All" ? "The queue is empty" : ("No " + dp.filter.toLowerCase() + " items") }
                            Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; text: "Add a URL above to prepare a download." }
                        }
                    }
                }
            }
        }
    }

    // ================================================================
    //  MY LIBRARY
    // ================================================================
    Component {
        id: libPage
        Item {
            id: lp
            property string filter: "All"
            property string sort: "Recently Opened"
            property bool grid: true
            property string q: ""
            readonly property var filters: ["All", "Videos", "Audio", "Music", "Wallpapers", "Anime", "Manga & Manhwa", "Favorites"]
            readonly property var sorts: ["Recently Added", "Recently Opened", "Alphabetical", "Favorites"]
            readonly property var items: root.libraryList(filter, sort, q)
            readonly property var recent: root.libraryList("All", "Recently Opened", "").filter(function (it) { return it.opened > 0 }).slice(0, 4)
            readonly property real gw: lf.width - 48
            readonly property int cols: Math.max(1, Math.floor((gw + 14) / 250))
            readonly property real cardW: (gw - 14 * (cols - 1)) / cols
            readonly property var empties: ({
                "All": "Your library is empty. Favorite a wallpaper, track or title to start filling it.",
                "Videos": "No local videos. A future scan of your video folders will list them here.",
                "Audio": "No local audio files yet.",
                "Music": "No favorite tracks or stations yet. Heart a few on the Music page.",
                "Wallpapers": "No saved wallpapers. Heart a wallpaper to save it here.",
                "Anime": "No anime on your list. Add one from the Anime page.",
                "Manga & Manhwa": "Your reading list is empty. Add a series from the Manga page.",
                "Favorites": "Nothing favorited yet."
            })
            function glyphFor(k) {
                return k === "wallpaper" ? "wallpaper" : (k === "anime" ? "anime" : (k === "manga" ? "manga" : (k === "video" ? "video" : "music")))
            }
            Flickable {
                id: lf
                anchors.fill: parent
                contentWidth: width
                contentHeight: lcol.height + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: VScroll {}
                Column {
                    id: lcol
                    x: 24; y: 6
                    width: lf.width - 48
                    spacing: 16

                    RowLayout {
                        width: parent.width
                        ColumnLayout {
                            spacing: 3
                            Lbl { text: "My Library"; font.pixelSize: 26; font.weight: Font.Bold }
                            Lbl { text: "Everything you've saved, in one place. Catalogue lists persist locally; local files aren't scanned."; dim: true; font.pixelSize: 13 }
                        }
                        Item { Layout.fillWidth: true }
                        Tag { visible: lf.width > 700; text: "NO FILES SCANNED"; tint: "#948e9d" }
                    }

                    Card {
                        width: parent.width
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            SearchField { Layout.fillWidth: true; accent: root.accent; placeholder: "Search your library"; text: lp.q; onEdited: lp.q = text }
                            IconBtn { box: 36; icon: "grid"; tip: "Grid view"; active: lp.grid; activeTint: root.accent; onClicked: lp.grid = true }
                            IconBtn { box: 36; icon: "list"; tip: "List view"; active: !lp.grid; activeTint: root.accent; onClicked: lp.grid = false }
                        }
                        Wrap {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: lp.filters
                                delegate: Chip { label: modelData; accent: root.accent; active: lp.filter === modelData
                                                 badge: "" + root.libraryList(modelData, "", "").length; onClicked: lp.filter = modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Lbl { text: "Sort"; mono: true; faint: true; font.pixelSize: 11 }
                            Wrap {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: lp.sorts
                                    delegate: Chip { label: modelData; accent: "#cebdff"; active: lp.sort === modelData; onClicked: lp.sort = modelData }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 10
                        visible: lp.filter === "All" && lp.q.trim() === "" && lp.recent.length > 0
                        Lbl { text: "Recently opened"; font.pixelSize: 16; font.weight: Font.Bold }
                        Wrap {
                            width: parent.width
                            spacing: 14
                            Repeater {
                                model: lp.recent
                                delegate: Rectangle {
                                    width: Math.min(260, (lp.gw - 14) / 2)
                                    height: 66
                                    radius: 12
                                    color: rrh.containsMouse ? pal.high : pal.cont
                                    border.width: 1
                                    border.color: pal.line
                                    Art { x: 8; y: 8; width: 76; height: 50; radiusPx: 8; frameColor: parent.color; src: root.artUrl(modelData.art); grad: modelData.g; glyph: lp.glyphFor(modelData.kind) }
                                    Column {
                                        x: 94; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 104; spacing: 2
                                        Lbl { width: parent.width; text: modelData.title; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        Lbl { width: parent.width; text: root.kindLabel(modelData.kind); mono: true; faint: true; font.pixelSize: 10 }
                                    }
                                    MouseArea { id: rrh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.libraryAction(modelData) }
                                }
                            }
                        }
                    }

                    Lbl { mono: true; faint: true; font.pixelSize: 11; text: lp.items.length + " item" + (lp.items.length === 1 ? "" : "s") + " \u00b7 " + lp.filter + " \u00b7 " + lp.sort }

                    Wrap {
                        width: parent.width
                        spacing: 14
                        visible: lp.grid
                        Repeater {
                            model: lp.grid ? lp.items : []
                            delegate: MediaCard {
                                width: lp.cardW
                                title: modelData.title
                                meta: modelData.sub
                                extra: root.kindLabel(modelData.kind)
                                badge: modelData.fav ? "\u2665 FAVORITE" : ""
                                src: root.artUrl(modelData.art)
                                grad: modelData.g
                                glyph: lp.glyphFor(modelData.kind)
                                aspect: 1.6
                                accent: root.accent
                                fav: modelData.fav
                                primaryLabel: root.libraryLabel(modelData.kind)
                                primaryIcon: modelData.kind === "wallpaper" ? "eye" : ((modelData.kind === "anime" || modelData.kind === "manga") ? "link" : "play")
                                onActivated: root.libraryActivate(modelData)
                                onPrimary: root.libraryAction(modelData)
                                onFavToggled: root.toggleFavorite(modelData.id, modelData.title)
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 8
                        visible: !lp.grid
                        Repeater {
                            model: lp.grid ? [] : lp.items
                            delegate: Rectangle {
                                id: lr
                                width: parent.width
                                height: 64
                                radius: 12
                                color: lrh.containsMouse ? pal.high : pal.cont
                                border.width: 1
                                border.color: pal.line
                                MouseArea { id: lrh; anchors.fill: parent; hoverEnabled: true; onClicked: root.libraryActivate(modelData) }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                                    spacing: 12
                                    Art { Layout.preferredWidth: 80; Layout.preferredHeight: 50; radiusPx: 8; frameColor: lr.color; src: root.artUrl(modelData.art); grad: modelData.g; glyph: lp.glyphFor(modelData.kind) }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Lbl { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        Lbl { Layout.fillWidth: true; text: modelData.sub; elide: Text.ElideRight; mono: true; faint: true; font.pixelSize: 11 }
                                    }
                                    Tag { visible: lf.width > 620; text: root.kindLabel(modelData.kind).toUpperCase(); px: 9 }
                                    IconBtn { box: 30; icon: modelData.fav ? "heart" : "heartO"; active: modelData.fav; tip: "Favorite"; onClicked: root.toggleFavorite(modelData.id, modelData.title) }
                                    Btn { compact: true; label: root.libraryLabel(modelData.kind); icon: modelData.kind === "wallpaper" ? "eye" : ((modelData.kind === "anime" || modelData.kind === "manga") ? "link" : "play"); onClicked: root.libraryAction(modelData) }
                                }
                            }
                        }
                    }

                    Card {
                        width: parent.width
                        visible: lp.items.length === 0
                        Lbl { text: "Nothing here yet"; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; dim: true; text: lp.q.trim() !== "" ? "No library items match that search." : lp.empties[lp.filter] }
                        Btn { visible: lp.filter !== "All" || lp.q !== ""; label: "Show everything"; icon: "refresh"; onClicked: { lp.filter = "All"; lp.q = "" } }
                    }
                }
            }
        }
    }
}
