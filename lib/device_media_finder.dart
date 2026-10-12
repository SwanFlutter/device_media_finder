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
  DeviceMediaFinderPlatform get _platform => DeviceMediaFinderPlatform.instance;

  /// Returns the native platform version string, e.g. `Android 14`.
  ///
  /// ```dart
  /// final version = await finder.getPlatformVersion();
  /// print(version); // Android 14
  /// ```
  Future<String?> getPlatformVersion() => _platform.getPlatformVersion();

  // ── Generic paginated API ────────────────────────────────────────────────

  /// Returns the number of items of [type], optionally narrowed by file
  /// [extensions].
  ///
  /// Useful for driving an infinite-scroll list: fetch the count once, then
  /// page through with [getMediaPage].
  ///
  /// ```dart
  /// final count = await finder.getMediaCount(
  ///   type: MediaType.video,
  ///   extensions: ['mp4', 'mkv'],
  /// );
  /// print('Found $count videos');
  /// ```
  Future<int> getMediaCount({
    required MediaType type,
    List<String> extensions = const [],
  }) => _platform.getMediaCount(type: type, extensions: extensions);

  /// Returns a single page of media.
  ///
  /// [page] is zero-based and [pageSize] is the number of items requested
  /// (clamped to 1..500 natively). [extensions] optionally filters by file
  /// extension.
  ///
  /// ```dart
  /// // Second page of 50 images, filtered to JPEG/PNG files.
  /// final items = await finder.getMediaPage(
  ///   type: MediaType.image,
  ///   page: 1,
  ///   pageSize: 50,
  ///   extensions: ['jpg', 'png'],
  /// );
  /// for (final item in items) {
  ///   print(item.displayName);
  /// }
  /// ```
  Future<List<MediaItem>> getMediaPage({
    required MediaType type,
    required int page,

    /// Maximum number of items to return in this page.
    ///
    /// Clamped to the range 1..500 by the native side.
    required int pageSize,
    List<String> extensions = const [],
  }) => _platform.getMediaPage(
    type: type,
    page: page,
    pageSize: pageSize,
    extensions: extensions,
  );

  /// Eagerly loads **every** item of [type] by paging until exhausted.
  ///
  /// Convenient for small libraries; prefer [getMediaPage] with lazy loading
  /// for large ones. [pageSize] controls the batch size of each round-trip.
  ///
  /// ```dart
  /// final audios = await finder.getAllMedia(
  ///   type: MediaType.audio,
  ///   pageSize: 100,
  /// );
  /// print('Loaded ${audios.length} audio tracks');
  /// ```
  Future<List<MediaItem>> getAllMedia({
    required MediaType type,
    List<String> extensions = const [],

    /// Number of items requested per native call while paging through results.
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

  /// Returns one page of videos (any size/format), newest first.
  ///
  /// ```dart
  /// final videos = await finder.getVideos(page: 0, pageSize: 60);
  /// ```
  Future<List<MediaItem>> getVideos({
    int page = 0,

    /// Maximum number of videos to return in this page.
    int pageSize = 100,
  }) => getMediaPage(type: MediaType.video, page: page, pageSize: pageSize);

  /// Returns every video on the device. See [getAllMedia] for the paging note.
  ///
  /// ```dart
  /// final allVideos = await finder.getAllVideos();
  /// print('Total videos: ${allVideos.length}');
  /// ```
  Future<List<MediaItem>> getAllVideos({
    /// Number of videos requested per native call while paging through results.
    int pageSize = 200,
  }) => getAllMedia(type: MediaType.video, pageSize: pageSize);

  /// Returns videos filtered client-side to the given [mimeTypes].
  ///
  /// Comparison is case-insensitive.
  ///
  /// ```dart
  /// final mp4Videos = await finder.getVideosByMimeType([
  ///   'video/mp4',
  ///   'video/x-matroska',
  /// ]);
  /// ```
  Future<List<MediaItem>> getVideosByMimeType(
    List<String> mimeTypes, {

    /// Number of videos requested per native call while paging through results.
    int pageSize = 200,
  }) async {
    final wanted = mimeTypes.map((e) => e.toLowerCase()).toSet();
    final all = await getAllVideos(pageSize: pageSize);
    return all
        .where((v) => wanted.contains((v.mimeType ?? '').toLowerCase()))
        .toList(growable: false);
  }

  // ── Audio convenience ──────────────────────────────────────────────────

  /// Returns one page of audio tracks (any size/format), newest first.
  ///
  /// ```dart
  /// final tracks = await finder.getAudios(page: 0, pageSize: 50);
  /// ```
  Future<List<MediaItem>> getAudios({
    int page = 0,

    /// Maximum number of audio tracks to return in this page.
    int pageSize = 100,
  }) => getMediaPage(type: MediaType.audio, page: page, pageSize: pageSize);

  /// Returns every audio track on the device.
  ///
  /// ```dart
  /// final allTracks = await finder.getAllAudios();
  /// ```
  Future<List<MediaItem>> getAllAudios({
    /// Number of audio tracks requested per native call while paging.
    int pageSize = 200,
  }) => getAllMedia(type: MediaType.audio, pageSize: pageSize);

  // ── Thumbnails ───────────────────────────────────────────────────────────

  /// Generates (or returns from cache) a thumbnail for [uriOrPath] and returns
  /// its on-disk JPEG path.
  ///
  /// Pass `item.dateModified` as [dateModified] so the cache invalidates when
  /// the file changes. [kind] is a strategy hint such as `image`, `video` or
  /// `audio`.
  ///
  /// ```dart
  /// final thumbPath = await finder.getThumbnail(
  ///   uriOrPath: item.uri,
  ///   width: 240,
  ///   dateModified: item.dateModified,
  ///   kind: 'image',
  /// );
  /// ```
  Future<String?> getThumbnail({
    required String uriOrPath,
    int width = 200,
    int? height,
    int dateModified = 0,
    String kind = 'image',
  }) => _platform.getThumbnail(
    uriOrPath: uriOrPath,
    width: width,
    height: height,
    dateModified: dateModified,
    kind: kind,
  );

  /// Convenience wrapper around [getThumbnail] that reads the strategy hint
  /// from [MediaItem.kind].
  ///
  /// ```dart
  /// final items = await finder.getVideos();
  /// final thumb = await finder.getThumbnailFor(items.first, width: 300);
  /// ```
  Future<String?> getThumbnailFor(MediaItem item, {int width = 200}) =>
      getThumbnail(
        uriOrPath: item.uri,
        width: width,
        dateModified: item.dateModified,
        kind: item.kind,
      );

  /// Returns a video frame thumbnail for [uriOrPath] as an on-disk path.
  ///
  /// ```dart
  /// final frame = await finder.getVideoThumbnail(
  ///   video.uri,
  ///   width: 320,
  ///   dateModified: video.dateModified,
  /// );
  /// ```
  Future<String?> getVideoThumbnail(
    String uriOrPath, {
    int width = 200,
    int? height,
    int dateModified = 0,
  }) => getThumbnail(
    uriOrPath: uriOrPath,
    width: width,
    height: height,
    dateModified: dateModified,
    kind: 'video',
  );

  /// Returns embedded album art for an audio [uriOrPath] as an on-disk path.
  ///
  /// Returns `null` when the track has no embedded artwork.
  ///
  /// ```dart
  /// final art = await finder.getAudioThumbnail(track.uri, width: 128);
  /// ```
  Future<String?> getAudioThumbnail(
    String uriOrPath, {
    int width = 200,
    int? height,
    int dateModified = 0,
  }) => getThumbnail(
    uriOrPath: uriOrPath,
    width: width,
    height: height,
    dateModified: dateModified,
    kind: 'audio',
  );

  /// Removes every cached thumbnail from disk. Returns `true` on success.
  ///
  /// ```dart
  /// final cleared = await finder.clearThumbnailCache();
  /// ```
  Future<bool> clearThumbnailCache() => _platform.clearThumbnailCache();

  // ── Permissions ──────────────────────────────────────────────────────────

  /// Returns whether the app currently holds a media/storage read permission.
  ///
  /// ```dart
  /// if (await finder.hasStoragePermission()) {
  ///   // Safe to query media.
  /// }
  /// ```
  Future<bool> hasStoragePermission() => _platform.hasStoragePermission();

  /// Prompts for the appropriate media/storage read permission and resolves to
  /// whether it was granted.
  ///
  /// ```dart
  /// final granted = await finder.requestStoragePermission();
  /// if (!granted) print('Permission denied');
  /// ```
  Future<bool> requestStoragePermission() =>
      _platform.requestStoragePermission();

  /// Returns whether the app has "All files access" (`MANAGE_EXTERNAL_STORAGE`).
  ///
  /// This is needed for the document/archive file-system fallback scan on
  /// Android 11+.
  ///
  /// ```dart
  /// if (!await finder.hasAllFilesAccess()) {
  ///   await finder.openAllFilesAccessSettings();
  /// }
  /// ```
  Future<bool> hasAllFilesAccess() => _platform.hasAllFilesAccess();

  /// Opens the system "All files access" settings screen for this app.
  ///
  /// ```dart
  /// final opened = await finder.openAllFilesAccessSettings();
  /// ```
  Future<bool> openAllFilesAccessSettings() =>
      _platform.openAllFilesAccessSettings();

  // ── Directory browsing ───────────────────────────────────────────────────

  /// Returns well-known public storage roots (Internal Storage, DCIM, Movies,
  /// ...). Each map contains string keys and values describing a root.
  ///
  /// ```dart
  /// final dirs = await finder.getDirectories();
  /// for (final dir in dirs) {
  ///   print(dir);
  /// }
  /// ```
  Future<List<Map<String, String>>> getDirectories() =>
      _platform.getDirectories();

  /// Returns files and folders directly inside [path], paginated and sorted
  /// with folders first.
  ///
  /// ```dart
  /// final entries = await finder.getDirectoryContents(
  ///   path: '/storage/emulated/0/DCIM',
  ///   page: 0,
  ///   pageSize: 100,
  /// );
  /// ```
  Future<List<Map<String, dynamic>>> getDirectoryContents({
    required String path,
    int page = 0,

    /// Maximum number of files and folders to return in this page.
    int pageSize = 200,
  }) => _platform.getDirectoryContents(
    path: path,
    page: page,
    pageSize: pageSize,
  );
}
