# Media Hub provider contract

Media Hub backends are independent command-line providers. A provider accepts
validated command-line arguments, prints exactly one UTF-8 JSON document to
stdout, and exits with status `0` on success or non-zero on failure. Diagnostics
may go to stderr, but stdout must not contain logs or progress text.

New providers should import shared transport, cache, state, and validation
helpers from `scripts/hub_common.py`. They must not persist application state
inside this repository.

## Success and error envelopes

Successful commands return an object with `ok: true` and a command-specific
result. Failures use this shape and a non-zero process exit:

```json
{
  "ok": false,
  "error": {
    "kind": "network",
    "message": "The provider could not be reached."
  }
}
```

`error.kind` is one of `network`, `rate_limited`, `unavailable`, or `invalid`.
`retryAfter` may be included as a non-negative number of seconds when a
provider has a meaningful retry delay. Messages are short, user-safe, and do
not include credentials or local absolute paths.

## Normalized entities

Providers return normalized entities rather than raw upstream API responses.
Fields marked required must be present. Additional provider-specific fields
may be included.

### Track

```json
{
  "kind": "track",
  "id": "jamendo:123",
  "title": "Track title",
  "artist": "Artist",
  "album": "Album",
  "dur": 214,
  "streamUrl": "https://media.example/track.mp3",
  "art": "https://media.example/cover.jpg",
  "sourceUrl": "https://catalogue.example/track/123"
}
```

`id`, `title`, and `streamUrl` are required. `artist`, `album`, `art`, and
`sourceUrl` may be empty or omitted. `dur` is a non-negative integer in
seconds; streaming URLs may use HTTP or HTTPS where the provider requires it.

### Lyrics

The LRCLIB provider returns a normalized lyrics object inside the standard
`{"ok": true, "lyrics": ...}` success envelope. Synced lines use seconds from
the start of the track and are sorted by timestamp:

```json
{
  "status": "synced",
  "lines": [
    {"t": 12.3, "s": "A lyric line"},
    {"t": 15.0, "s": "The next line"}
  ]
}
```

When LRCLIB has no timed lyrics, `status` is `plain` with a non-empty `plain`
string, or `none` when it has no usable lyrics. Lookup uses
`GET /api/get` with track, artist, album and duration metadata, then falls back
to `GET /api/search` when there is no exact match. Requests use the shared
`GPS-Desktop/<version>` User-Agent and normalized results, including no-match
results, are cached for 24 hours under the shared media cache.

### Anime and Manga

```json
{
  "kind": "anime",
  "id": "anime-123",
  "title": "Title",
  "siteUrl": "https://catalogue.example/anime/123",
  "cover": "https://images.example/cover.jpg"
}
```

`kind` is `anime` or `manga`; `id`, `title`, and an absolute `siteUrl` are
required. `cover` may be omitted or empty. Providers may add normalized
catalogue fields such as alternate titles, description, genres, year, status,
format, chapter/episode counts, score, or author. The current AniList
integration already returns this normalized catalogue family.

### Chapter

```json
{
  "title": "Chapter 1",
  "pageCount": 2,
  "pages": ["file:///library/page-001.jpg", "file:///library/page-002.jpg"]
}
```

`title`, positive integer `pageCount`, and an equally sized `pages` URL array
are required. Page URLs may use `https`, `http`, or `file`.

### PageList

```json
{
  "title": "Chapter 1",
  "pageCount": 2,
  "pages": ["https://images.example/page-001.jpg", "https://images.example/page-002.jpg"]
}
```

`PageList` is the page-delivery view of a chapter and uses the same count and
URL constraints. Its `title` identifies the chapter or page group.

## Runtime and persistence

`hub_common.request()` identifies itself as `GPS-Desktop/<version>`, applies
timeouts, exponential retry delays, `Retry-After` handling for HTTP 429, and
per-host pacing. `DiskCache` stores TTL-bound entries under
`~/.cache/gps/media/` (respecting `XDG_CACHE_HOME`) and removes expired or
least-recently-used entries to stay within its configured byte limit.
`fetch_and_cache()` only accepts HTTPS remote files, validates content type and
size, and writes cache data atomically.

`PersistentState` stores JSON under `~/.local/state/gps/` (respecting
`XDG_STATE_HOME`). Writes are atomic; malformed state is preserved under a
`.corrupt-<timestamp>.json` name and `load()` returns the caller's default with
the cause available in `last_error`.

The QML singleton `qs.config.HubProvider` runs only provider script names
matching `media-hub-*.py`, without a shell. A newer request or `cancel()` stops
the previous process and ignores stale output. It exposes `loading`, `error`,
and `succeeded`, `failed`, and `cancelled` signals; callers should supply
arguments as a string array and use the emitted request ID to correlate results.
`qs.config.MediaLyrics` applies the same cancellation and stale-response rules
while adapting LRCLIB results for Hub, Dashboard, and Island consumers.

## Reuse in the existing Hub

- Music providers can normalize into the fields already accepted by
  `components/MusicQueue.js` and keep using its queue/favorites operations.
- Anime and manga catalogue data can use the existing AniList normalization
  family and `components/MediaCatalogue.js` filtering/sanitization.
- Local manga page/chapter data can use the existing
  `components/MangaReader.js` collection/progress helpers.
- Existing favorite, queue, and media-library state is currently owned by
  `components/MediaHub.qml` and stored via `FileView` below the user's config
  directory in `quickshell/media-hub-music.json` and
  `quickshell/media-hub-library.json`. The new helper does not migrate or alter
  that state.

Existing Jamendo, Radio Browser, AniList, MangaReader, and Media Hub component
behavior is intentionally unchanged by this shared service layer.
