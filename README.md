# Device Media Finder

A fast Flutter plugin for listing **videos and audio** on an Android device —
of **any size and any format** — with full per-file metadata, SQL-level
pagination and cached, background-generated thumbnails.

It is designed to be the data layer behind a **video player** or **audio
player**: every item comes back with the duration, resolution, size, MIME type,
on-disk path and a `content://` URI you can hand straight to a player widget.

## Features

- 🎞️ List **videos** and 🎵 **audio** of any size/codec/container — nothing is
  filtered out by size.
- 🧾 Rich metadata per item: name, size, duration, width/height, MIME type,
  `content://` URI, absolute path and last-modified time.
- ⚡ **Real SQL pagination** — only the page you ask for is loaded, so a library
  of tens of thousands of files scrolls smoothly.
- 🧵 Native work runs on a **background thread pool** (Kotlin coroutines on
  `Dispatchers.IO`), keeping the platform thread — and your UI — free.
- 🖼️ **Thumbnails** for video frames and audio album art, generated on a bounded
  worker pool and cached on disk (LRU, size-capped) so repeat scrolls are free.
- 🔐 Built-in runtime **permission** helpers, including Android 13+ granular
  media permissions and Android 11+ "All files access".
- 📁 Also exposes images, documents, archives and raw directory browsing.

## Platform support

| Platform | Media listing & thumbnails | Backend |
| -------- | -------------------------- | ------- |
| Android  | ✅ (API 24+)                | `MediaStore` + file-system fallback |
| iOS      | ✅ (iOS 15+)                | Photos library (PhotoKit) |
| macOS    | ✅ (macOS 10.15+)           | User media directories (file system) |

Each platform maps to the OS's native media catalogue, so the behaviour differs
where the platforms themselves differ:

- **Android** — full model: `image`, `video`, `audio`, `document`, `archive`
  and `any`, plus arbitrary directory browsing.
- **iOS** — sandboxed, so `image`/`video`/`any` resolve against the **Photos
  library** (the only user-media catalogue an app may read). `audio`,
  `document` and `archive` return an empty list, because iOS has no
  app-readable index for them. `getThumbnail` uses PhotoKit; the `uri` field is
  the asset's `localIdentifier`. Directory browsing is limited to the app's own
  sandbox (Documents/Downloads).
  Add an `NSPhotoLibraryUsageDescription` string to your app's `Info.plist`.
- **macOS** — file-system backed, so it mirrors Android's model: all six types
  (by extension) across the user's Movies/Music/Pictures/Downloads/Documents/
  Desktop folders, plus real directory browsing. A sandboxed build needs the
  relevant read-only entitlements (`com.apple.security.assets.*.read-only`,
  `com.apple.security.files.user-selected.read-only`); a non-sandboxed build
  sees everything the user account can read. There is no runtime storage
  prompt, so the permission helpers report `true`.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  device_media_finder: ^0.1.0
```

Then:

```dart
import 'package:device_media_finder/device_media_finder.dart';

final finder = DeviceMediaFinder();
```

## Permissions

The plugin's `AndroidManifest.xml` already declares every permission it needs;
they are merged into your app automatically. You still have to **request** them
at runtime:

```dart
if (!await finder.hasStoragePermission()) {
  final granted = await finder.requestStoragePermission();
  if (!granted) {
    // Guide the user to settings, or degrade gracefully.
  }
}
```

What is requested depends on the OS version:

- **Android 13+ (API 33+):** granular `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` /
  `READ_MEDIA_IMAGES`.
- **Android 6–12:** classic `READ_EXTERNAL_STORAGE`.

For the **document/archive** file-system fallback scan on Android 11+ you also
need "All files access" (`MANAGE_EXTERNAL_STORAGE`), a special permission granted
from system settings:

```dart
if (!await finder.hasAllFilesAccess()) {
  await finder.openAllFilesAccessSettings(); // opens the system screen
}
```

> Listing **videos and audio** only needs the normal media permission — "All
> files access" is only required for documents/archives.

## Quick start

```dart
final finder = DeviceMediaFinder();

// Newest videos, one page at a time.
final videos = await finder.getVideos(page: 0, pageSize: 60);
for (final v in videos) {
  print('${v.name} • ${v.width}x${v.height} • ${v.duration}ms • ${v.size} B');
}

// Newest audio tracks.
final tracks = await finder.getAudios(page: 0, pageSize: 60);
```

## Core concepts

### `MediaType`

```dart
enum MediaType { image, video, audio, document, archive, any }
```

### `MediaItem`

Every list method returns `MediaItem`s. All fields the platform can supply are
exposed, so a player has everything it needs without a second call:

| Field           | Type      | Notes                                             |
| --------------- | --------- | ------------------------------------------------- |
| `id`            | `int`     | MediaStore id (negative = file-system fallback).  |
| `uri`           | `String`  | `content://`/`file://` — feed to a player widget. |
| `name`          | `String`  | Display name incl. extension.                     |
| `size`          | `int`     | Bytes. No upper limit.                            |
| `duration`      | `int`     | Milliseconds (audio/video).                       |
| `width`/`height`| `int`     | Pixels (image/video), else `0`.                   |
| `mimeType`      | `String?` | e.g. `video/mp4`.                                 |
| `path`          | `String?` | Absolute path when available.                     |
| `dateModified`  | `int`     | Milliseconds since epoch.                         |
| `mediaType`     | `int`     | Raw MediaStore `MEDIA_TYPE`.                       |
| `thumbnailPath` | `String?` | Filled in by the UI once generated.               |

Helpers: `item.kind` (`'video'`/`'audio'`/`'image'`), `item.isVideo`,
`item.isAudio`, `item.extension`, `item.type`.

`VideoFile` and `AudioFile` are kept as type aliases of `MediaItem` for
backward compatibility.

## API reference

### Listing & pagination

```dart
// Total number of items of a type (for building a scrollbar / count badge).
final total = await finder.getMediaCount(type: MediaType.video);

// One page. `page` is zero-based; only this slice is read from MediaStore.
final page0 = await finder.getMediaPage(
  type: MediaType.audio,
  page: 0,
  pageSize: 100,
);

// Everything, fetched page-by-page under the hood.
final all = await finder.getAllMedia(type: MediaType.video, pageSize: 200);
```

Convenience wrappers for the two player use-cases:

| Method                              | Returns                                  |
| ----------------------------------- | ---------------------------------------- |
| `getVideos({page, pageSize})`       | One page of videos.                      |
| `getAllVideos({pageSize})`          | Every video.                             |
| `getVideosByMimeType(List<String>)` | Videos filtered by MIME (client-side).   |
| `getAudios({page, pageSize})`       | One page of audio.                       |
| `getAllAudios({pageSize})`          | Every audio track.                       |

You can also pass `extensions: ['mkv', 'flac']` to `getMediaCount` /
`getMediaPage` to filter at the SQL level by file extension. Nothing is ever
filtered by **size** — a 20 GB movie is listed the same as a 2 MB clip.

### Thumbnails

Thumbnails are generated natively on a bounded worker pool and cached on disk,
so scrolling back over an item is instant.

```dart
// Generic: works for a content:// URI or an absolute path.
final path = await finder.getThumbnail(
  uriOrPath: item.uri,
  width: 300,
  dateModified: item.dateModified, // used as a cache-busting key
  kind: item.kind,                 // 'video' | 'audio' | 'image'
);

// Or, straight from a MediaItem:
final p = await finder.getThumbnailFor(item, width: 300);

// Type-specific helpers:
await finder.getVideoThumbnail(uriOrPath: item.uri, width: 300);
await finder.getAudioThumbnail(uriOrPath: item.uri, width: 300);

// Wipe the on-disk cache (e.g. from a settings screen).
await finder.clearThumbnailCache();
```

The returned value is an absolute file path to a cached JPEG, ready for
`Image.file(File(path))`. `getThumbnailFor` returns `null` when no frame or
album art is available.

### Directory browsing

```dart
final dirs = await finder.getDirectories();
final contents = await finder.getDirectoryContents(
  path: dirs.first.path!,
  page: 0,
  pageSize: 100,
);
```

## Performance & architecture

- **SQL-level pagination.** Each page is a `LIMIT`/`OFFSET` query against
  MediaStore (`QUERY_ARG_LIMIT` / `QUERY_ARG_OFFSET` on API 30+, an appended
  `LIMIT ? OFFSET ?` clause below that). The cursor is never fully materialised,
  so memory stays flat regardless of library size.
- **Background execution.** All native work runs on Kotlin coroutines over
  `Dispatchers.IO` with a `SupervisorJob`; the platform thread returns
  immediately, keeping your UI thread free — the isolate-style model the
  reference sample was built around.
- **Bounded thumbnail pool.** Thumbnail generation is gated by a
  `Semaphore(4)`, so a fast scroll can't spawn hundreds of `MediaMetadataRetriever`
  instances at once.
- **Two-tier cache.** Native side: a disk LRU capped at 128 MB, keyed by an MD5
  of URI + size + `dateModified`. Dart side: an in-memory LRU of resolved
  thumbnail paths plus a de-duplicating request queue, so the same item is never
  decoded twice.

## Example: an infinite-scroll grid

The bundled example app ships `OptimizedMediaTab` — a reusable widget that pages
through a `MediaType`, lazily requests thumbnails as tiles scroll into view, and
releases them under memory pressure. See
[`example/lib/optimized_media_tab.dart`](example/lib/optimized_media_tab.dart)
and [`example/lib/memory_manager.dart`](example/lib/memory_manager.dart).

```dart
OptimizedMediaTab(
  mediaManager: DeviceMediaFinder(),
  mediaType: MediaType.video,
);
```

## Feeding a player

Every `MediaItem` already carries what a player needs — hand `item.uri`
straight to your video/audio player widget:

```dart
final videos = await finder.getVideos();
final first = videos.first;

// e.g. with the `video_player` package:
// VideoPlayerController.networkUrl(Uri.parse(first.uri));
// Duration is known up-front, no probing needed:
final total = Duration(milliseconds: first.duration);
```

## Supported formats

Anything the device's MediaStore and codecs recognise — `mp4`, `mkv`, `webm`,
`avi`, `mov`, `3gp`, `flv`, … for video and `mp3`, `flac`, `aac`, `m4a`, `ogg`,
`wav`, `opus`, … for audio. There is **no size or format allow-list** in the
plugin; if the OS can see the file, it is listed.

## Troubleshooting

- **Empty list even with permission granted.** On Android 13+ make sure you
  requested the *granular* media permission for the type you're listing
  (`READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO`), not just `READ_MEDIA_IMAGES`.
- **Documents/archives missing.** Those come from a file-system fallback scan
  that needs "All files access" on Android 11+ — call
  `openAllFilesAccessSettings()`.
- **`audio`/`document`/`archive` empty on iOS.** Expected — iOS has no
  app-readable index for them; only the Photos library (images/videos) is
  reachable. Use `image`, `video` or `any` on iOS.
- **Nothing listed on macOS.** A sandboxed build needs the read-only asset/file
  entitlements (see *Platform support*); without them the sandbox hides the
  user's folders.

## Migration from 0.0.x

The API was reworked in `0.1.0` around `MediaItem` and SQL pagination. The old
`VideoFile` / `AudioFile` names remain as type aliases, and `getVideos()` /
`getAudios()` keep working, so most call sites compile unchanged.


