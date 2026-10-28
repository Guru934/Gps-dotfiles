import QtQuick
import Quickshell
import "MediaCatalogue.js" as MediaCatalogue

// One live AniList catalogue page. Remote results are transient; the saved
// watchlist/reading-list entries remain available in the local views.
Item {
    id: cat
    visible: false
    width: 0
    height: 0

    property string kind: "anime"
    property bool active: false
    property var savedEntries: []
    property string view: "Trending"
    property string query: ""
    property string genre: "All"
    property string statusFilter: "All"
    property string originFilter: "All regions"
    property int page: 1

    property var remoteResults: []
    property bool loading: false
    property bool hasLoaded: false
    property bool hasNextPage: false
    property bool cached: false
    property string error: ""
    property string errorCode: ""
    property int retryAfter: 0
    property var rateLimit: ({})
    property int requestSeq: 0

    readonly property bool localView: MediaCatalogue.isLocalView(view)
    readonly property var viewOptions: MediaCatalogue.viewOptions(kind)
    readonly property var genreOptions: MediaCatalogue.genreOptions(kind)
    readonly property var statusOptions: MediaCatalogue.statusFilterOptions(kind)
    readonly property var originOptions: MediaCatalogue.originOptions()
    readonly property var localEntries: buildLocalEntries()
    readonly property var entries: localView ? localEntries : remoteResults
    readonly property int count: entries.length
    readonly property string currentRequestKey: {
        var request = MediaCatalogue.makeRequest(kind, view, query, genre, statusFilter, originFilter, page, 24)
        return request ? MediaCatalogue.requestKey(request) : ""
    }
    readonly property bool localFiltered: localView
        && (query.trim() !== "" || genre !== "All" || statusFilter !== "All" || originFilter !== "All regions")
    readonly property string emptyTitle: localView
        ? (localFiltered ? "No saved titles match these filters"
                         : (kind === "anime" ? "Your watchlist is empty" : "Your reading list is empty"))
        : "No titles match these filters"
    readonly property string emptyMessage: localView
        ? (localFiltered ? "Try a broader search or fewer filters."
                         : "Add a title from the catalogue and choose a status. Saved entries stay available offline.")
        : "Try a broader search, another genre or fewer filters."

    function buildLocalEntries() {
        var out = []
        var list = savedEntries || []
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            if (!item || item.kind !== kind || !item.userStatus) continue
            if (query.trim() !== "" && MediaCatalogue.searchableText(item).indexOf(query.trim().toLowerCase()) < 0) continue
            if (genre !== "All" && (item.genres || []).indexOf(genre) < 0) continue
            if (!MediaCatalogue.catalogueStatusMatches(item, statusFilter)) continue
            if (!MediaCatalogue.originMatches(item, originFilter)) continue
            out.push(item)
        }
        out.sort(function (a, b) {
            return (b.openedAt || 0) - (a.openedAt || 0)
                || (b.savedAt || 0) - (a.savedAt || 0)
                || a.title.localeCompare(b.title)
        })
        return out
    }

    function activate() {
        active = true
        page = 1
        error = ""
        errorCode = ""
        retryAfter = 0
        if (localView) {
            loading = false
            hasNextPage = false
            cached = false
        } else {
            runSearch()
        }
    }

    function refresh() {
        if (!active) return
        page = 1
        error = ""
        errorCode = ""
        retryAfter = 0
        if (localView) {
            loading = false
            hasNextPage = false
            cached = false
            return
        }
        loading = true
        schedule()
    }

    function schedule() {
        if (localView) return
        debounce.restart()
    }

    function runSearch() {
        if (localView) return
        var request = MediaCatalogue.makeRequest(kind, view, query, genre, statusFilter, originFilter, page, 24)
        if (!request) {
            loading = false
            error = "This catalogue request is not valid."
            errorCode = "invalid_request"
            return
        }
        requestSeq += 1
        request.seq = requestSeq
        request.key = MediaCatalogue.requestKey(request)
        loading = true
        error = ""
        errorCode = ""
        retryAfter = 0
        if (!backend.search(request)) {
            loading = false
            error = "Could not start the AniList search."
            errorCode = "invalid_request"
        }
    }

    function retry() {
        if (localView) return
        runSearch()
    }

    function nextPage() {
        if (localView || !hasNextPage || loading) return
        page = Math.min(500, page + 1)
        runSearch()
    }

    function previousPage() {
        if (localView || page <= 1 || loading) return
        page = Math.max(1, page - 1)
        runSearch()
    }

    function findMedia(id) {
        for (var i = 0; i < remoteResults.length; i++)
            if (remoteResults[i].id === id) return remoteResults[i]
        for (var j = 0; j < savedEntries.length; j++)
            if (savedEntries[j] && savedEntries[j].id === id) return savedEntries[j]
        return null
    }

    function handleSuccess(payload, request) {
        if (!request || request.seq !== requestSeq) return
        if (localView || !request.key || request.key !== currentRequestKey) return
        remoteResults = MediaCatalogue.sanitizeMediaList(kind, payload.results, 50)
        page = MediaCatalogue.pageClamp(payload.page)
        hasNextPage = payload.hasNextPage === true
        cached = payload.cached === true
        rateLimit = payload.rateLimit && typeof payload.rateLimit === "object" ? payload.rateLimit : ({})
        loading = false
        hasLoaded = true
        error = ""
        errorCode = ""
        retryAfter = 0
    }

    function handleFailure(message, code, request, waitSeconds) {
        if (!request || request.seq !== requestSeq) return
        if (localView) {
            loading = false
            return
        }
        if (!request.key || request.key !== currentRequestKey) return
        loading = false
        error = String(message || "AniList search failed.")
        errorCode = String(code || "unknown")
        retryAfter = Math.max(0, Math.min(86400, Number(waitSeconds) || 0))
        hasLoaded = true
    }

    onKindChanged: refresh()
    onViewChanged: refresh()
    onQueryChanged: refresh()
    onGenreChanged: refresh()
    onStatusFilterChanged: refresh()
    onOriginFilterChanged: refresh()

    Timer {
        id: debounce
        interval: 500
        repeat: false
        onTriggered: cat.runSearch()
    }

    MediaHubAniList {
        id: backend
        onSearchSucceeded: (payload, request) => cat.handleSuccess(payload, request)
        onSearchFailed: (message, code, request, retryAfter) => cat.handleFailure(message, code, request, retryAfter)
    }
}
