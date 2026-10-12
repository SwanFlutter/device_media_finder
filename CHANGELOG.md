## 0.2.0

* **iOS support (iOS 15+).** Native PhotoKit backend that lists the Photos
  library (images and videos) with full metadata, paginated loading and
  disk-cached thumbnails (`PHImageManager`), mirroring the Android method
  channel. `audio`/`document`/`archive` are not reachable on iOS and return an
  empty list. Requires `NSPhotoLibraryUsageDescription` in the host app.
* **macOS support (macOS 10.15+).** Native file-system backend that walks the
  user's Movies/Music/Pictures/Downloads/Documents/Desktop folders for all six
  media types (of any size/format), with real directory browsing and
  `CGImageSource`/`AVAssetImageGenerator`-based cached thumbnails. Honours
  sandbox read-only asset/file entitlements.
* Both Apple backends run heavy work off the platform thread and reply exactly
  once on the main thread (`SafeResult`), matching the Android backend.
* No Dart/API changes — the same `MediaItem` model and methods work across all
  three platforms.

## 0.1.0

* Rewrote the Android backend in **Java** (`ExecutorService` +
  `Semaphore`-bounded workers) so all scanning and thumbnail work runs off the
  platform thread.
* Lists **videos and audio of any size and any format** — no size or format
  allow-list; if the OS can see the file, it is listed.
* Rich `MediaItem` model exposing full per-file metadata: id, `content://` URI,
  name, size, duration, width/height, MIME type, absolute path, date modified
  and raw MediaStore media type.
* **Real SQL-level pagination** via `getMediaCount` / `getMediaPage`
  (`QUERY_ARG_LIMIT`/`OFFSET` on API 30+, `LIMIT`/`OFFSET` clause below),
  plus `getAllMedia` / `getAllVideos` / `getAllAudios` helpers.
* Background-generated, disk-cached **thumbnails** (LRU capped at 128 MB, MD5
  keys, bounded `Semaphore(4)` worker pool) for video frames and audio album
  art; `getThumbnail` / `getThumbnailFor` / `clearThumbnailCache`.
* Runtime **permission helpers**: Android 13+ granular media permissions,
  Android 11+ "All files access" (`MANAGE_EXTERNAL_STORAGE`) and legacy storage.
* Directory browsing (`getDirectories` / `getDirectoryContents`) and a
  file-system fallback scan for documents/archives.
* Example app rewritten with an optimized, infinite-scroll `OptimizedMediaTab`
  and a `MemoryManager` for thumbnail lifecycle.
* `VideoFile` / `AudioFile` kept as `MediaItem` type aliases for backward
  compatibility.

## 0.0.2

* add support path directory

## 0.0.1

* initial release.
* added support for videos and audio.
* added support for video thumbnails.
* added support for filtering videos by MIME type.
