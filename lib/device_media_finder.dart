import 'device_media_finder_platform_interface.dart';
import 'src/media_item.dart';
import 'src/media_type.dart';

export 'src/media_item.dart';
export 'src/media_type.dart';

/// High-level entry point for discovering media on the device.
///
/// The backend loads pages lazily with real SQL-level pagination and generates
/// thumbnails on a bounded background thread pool with an on-disk cache, so a
/// grid of thousands of videos or audio tracks stays smooth and cheap to
/// scroll. Files of **any size and any format** are returned — nothing is
/// filtered out by size.
///
/// ```dart
/// final finder = DeviceMediaFinder();
/// if (!await finder.hasStoragePermission()) {
///   await finder.requestStoragePermission();
/// }
/// final firstPage = await finder.getVideos(page: 0, pageSize: 60);
/// ```
class DeviceMediaFinder {
  DeviceMediaFinderPlatform get _platform =>
      DeviceMediaFinderPlatform.instance;

  /// The native platform version string, e.g. `Android 14`.
  Future<String?> getPlatformVersion() => _platform.getPlatformVersion();

  // ── Generic paginated API ────────────────────────────────────────────────

  /// Number of items of [type] (optionally narrowed by file [extensions]).
  ///
  /// Useful for driving an infinite-scroll list: fetch the count once, then
  /// page through with [getMediaPage].
  Future<int> getMediaCount({
    required MediaType type,
    List<String> extensions = const [],
  }) =>
      _platform.getMediaCount(type: type, extensions: extensions);

  /// A single page of media. [page] is zero-based; [pageSize] items are
  /// returned (clamped to 1..500 natively).
  Future<List<MediaItem>> getMediaPage({
    required MediaType type,
    required int page,
    required int pageSize,
    List<String> extensions = const [],
  }) =>
      _platform.getMediaPage(
        type: type,
        page: page,
        pageSize: pageSize,
        extensions: extensions,
      );

  /// Eagerly loads **every** item of [type] by paging until exhausted.
  ///
  /// Convenient for small libraries; prefer [getMediaPage] with lazy loading
  /// for large ones. [pageSize] controls the batch size of each round-trip.
  Future<List<MediaItem>> getAllMedia({
    required MediaType type,
    List<String> extensions = const [],
    int pageSize = 200,
  }) async {
    final total = await getMediaCount(type: type, extensions: extensions);
    final out = <MediaItem>[];
    var page = 0;
    while (out.length < total) {
      final batch = await getMediaPage(
        type: type,
        page: page,
        pageSize: pageSize,
        extensions: extensions,
      );
      if (batch.isEmpty) break;
      out.addAll(batch);
      page++;
    }
    return out;
  }

  // ── Video convenience ──────────────────────────────────────────────────

  /// One page of videos (any size/format), newest first.
  Future<List<MediaItem>> getVideos({int page = 0, int pageSize = 100}) =>
      getMediaPage(type: MediaType.video, page: page, pageSize: pageSize);

  /// Every video on the device. See [getAllMedia] for the paging note.
  Future<List<MediaItem>> getAllVideos({int pageSize = 200}) =>
      getAllMedia(type: MediaType.video, pageSize: pageSize);

  /// Videos filtered client-side to the given [mimeTypes]
  /// (e.g. `['video/mp4', 'video/x-matroska']`).
  Future<List<MediaItem>> getVideosByMimeType(
    List<String> mimeTypes, {
    int pageSize = 200,
  }) async {
    final wanted = mimeTypes.map((e) => e.toLowerCase()).toSet();
    final all = await getAllVideos(pageSize: pageSize);
    return all
        .where((v) => wanted.contains((v.mimeType ?? '').toLowerCase()))
        .toList(growable: false);
  }

  // ── Audio convenience ──────────────────────────────────────────────────

  /// One page of audio tracks (any size/format), newest first.
  Future<List<MediaItem>> getAudios({int page = 0, int pageSize = 100}) =>
      getMediaPage(type: MediaType.audio, page: page, pageSize: pageSize);

  /// Every audio track on the device.
  Future<List<MediaItem>> getAllAudios({int pageSize = 200}) =>
      getAllMedia(type: MediaType.audio, pageSize: pageSize);

  // ── Thumbnails ───────────────────────────────────────────────────────────

  /// Generates (or returns from cache) a thumbnail for [uriOrPath] and returns
  /// its on-disk JPEG path. Pass [item.dateModified] as [dateModified] so the
  /// cache invalidates when the file changes.
  Future<String?> getThumbnail({
    required String uriOrPath,
    int width = 200,
    int? height,
    int dateModified = 0,
    String kind = 'image',
  }) =>
      _platform.getThumbnail(
        uriOrPath: uriOrPath,
        width: width,
        height: height,
        dateModified: dateModified,
        kind: kind,
      );

  /// Convenience wrapper that reads the strategy hint from [item.kind].
  Future<String?> getThumbnailFor(MediaItem item, {int width = 200}) =>
      getThumbnail(
        uriOrPath: item.uri,
        width: width,
        dateModified: item.dateModified,
        kind: item.kind,
      );

  /// A video frame thumbnail for [uriOrPath], returned as an on-disk path.
  Future<String?> getVideoThumbnail(
    String uriOrPath, {
    int width = 200,
    int? height,
    int dateModified = 0,
  }) =>
      getThumbnail(
        uriOrPath: uriOrPath,
        width: width,
        height: height,
        dateModified: dateModified,
        kind: 'video',
      );

  /// Embedded album art for an audio [uriOrPath], returned as an on-disk path.
  Future<String?> getAudioThumbnail(
    String uriOrPath, {
    int width = 200,
    int? height,
    int dateModified = 0,
  }) =>
      getThumbnail(
        uriOrPath: uriOrPath,
        width: width,
        height: height,
        dateModified: dateModified,
        kind: 'audio',
      );

  /// Removes every cached thumbnail from disk.
  Future<bool> clearThumbnailCache() => _platform.clearThumbnailCache();

  // ── Permissions ──────────────────────────────────────────────────────────

  /// Whether the app currently holds a media/storage read permission.
  Future<bool> hasStoragePermission() => _platform.hasStoragePermission();

  /// Prompts for the appropriate media/storage read permission and resolves to
  /// whether it was granted.
  Future<bool> requestStoragePermission() =>
      _platform.requestStoragePermission();

  /// Whether the app has "All files access" (`MANAGE_EXTERNAL_STORAGE`), needed
  /// for the document/archive file-system fallback scan on Android 11+.
  Future<bool> hasAllFilesAccess() => _platform.hasAllFilesAccess();

  /// Opens the system "All files access" settings screen for this app.
  Future<bool> openAllFilesAccessSettings() =>
      _platform.openAllFilesAccessSettings();

  // ── Directory browsing ───────────────────────────────────────────────────

  /// Well-known public storage roots (Internal Storage, DCIM, Movies, ...).
  Future<List<Map<String, String>>> getDirectories() =>
      _platform.getDirectories();

  /// Files and folders directly inside [path], paginated and sorted with
  /// folders first.
  Future<List<Map<String, dynamic>>> getDirectoryContents({
    required String path,
    int page = 0,
    int pageSize = 200,
  }) =>
      _platform.getDirectoryContents(
        path: path,
        page: page,
        pageSize: pageSize,
      );
}
