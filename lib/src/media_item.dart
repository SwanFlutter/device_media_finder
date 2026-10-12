import 'media_type.dart';

/// A single media entry returned by the native scanner.
///
/// Every field the platform can supply is exposed here, so a video/audio
/// player built on top of this plugin has everything it needs (duration,
/// resolution, size, MIME type, on-disk path and a `content://` [uri]) without
/// a second round-trip to the platform.
class MediaItem {
  /// `MediaStore` row id, or a negative synthetic id for files discovered by
  /// the file-system fallback scan (documents/archives on OEM ROMs).
  final int id;

  /// A `content://` or `file://` URI that can be handed to a player, an
  /// `Image`/`VideoPlayer` widget, or [DeviceMediaFinder.getThumbnail].
  final String uri;

  /// Display name including extension (e.g. `holiday.mp4`).
  final String name;

  /// File size in bytes. There is no upper limit — large files are returned.
  final int size;

  /// Last-modified time in **milliseconds** since epoch.
  final int dateModified;

  /// MIME type reported by MediaStore, or `null` when unknown.
  final String? mimeType;

  /// Raw `MediaStore.Files.FileColumns.MEDIA_TYPE` value
  /// (0 none, 1 image, 2 audio, 3 video, 6 document).
  final int mediaType;

  /// Absolute file-system path when available (`DATA` column / FS scan).
  ///
  /// May be `null` on scoped-storage devices where only [uri] is accessible.
  final String? path;

  /// Pixel width for images/videos, else `0`.
  final int width;

  /// Pixel height for images/videos, else `0`.
  final int height;

  /// Duration in **milliseconds** for audio/video, else `0`.
  final int duration;

  /// Cached thumbnail path, populated lazily by the UI once a thumbnail has
  /// been generated. Not sent by the platform.
  String? thumbnailPath;

  MediaItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.size,
    required this.dateModified,
    required this.mimeType,
    required this.mediaType,
    required this.path,
    required this.width,
    required this.height,
    required this.duration,
    this.thumbnailPath,
  });

  /// Builds a [MediaItem] from the raw map delivered over the method channel.
  factory MediaItem.fromMap(Map<dynamic, dynamic> map) {
    int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return MediaItem(
      id: asInt(map['id']),
      uri: (map['uri'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      size: asInt(map['size']),
      dateModified: asInt(map['dateModified']),
      mimeType: map['mimeType'] as String?,
      mediaType: asInt(map['mediaType']),
      path: map['path'] as String?,
      width: asInt(map['width']),
      height: asInt(map['height']),
      duration: asInt(map['duration']),
    );
  }

  /// Coarse thumbnail strategy hint passed to [DeviceMediaFinder.getThumbnail]:
  /// `'video'`, `'audio'` or `'image'`.
  ///
  /// Derived from [mediaType] first (fast, exact for indexed media) and falls
  /// back to [mimeType] for file-system entries with `MEDIA_TYPE_NONE`.
  String get kind {
    switch (mediaType) {
      case 3:
        return 'video';
      case 2:
        return 'audio';
      case 1:
        return 'image';
    }
    final m = mimeType ?? '';
    if (m.startsWith('video/')) return 'video';
    if (m.startsWith('audio/')) return 'audio';
    if (m.startsWith('image/')) return 'image';
    return 'image';
  }

  /// True for a row whose [mediaType]/[mimeType] identifies it as a video.
  bool get isVideo => kind == 'video';

  /// True for a row whose [mediaType]/[mimeType] identifies it as audio.
  bool get isAudio => kind == 'audio';

  /// The [MediaType] this item belongs to (best effort).
  MediaType get type {
    switch (kind) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      case 'image':
        return MediaType.image;
      default:
        return MediaType.any;
    }
  }

  /// File extension without the leading dot, lower-cased (e.g. `mp4`).
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  @override
  String toString() =>
      'MediaItem(name: $name, kind: $kind, size: $size, duration: $duration, uri: $uri)';
}

/// Back-compat alias. A video is just a [MediaItem] whose [MediaItem.kind] is
/// `'video'`.
typedef VideoFile = MediaItem;

/// Back-compat alias. An audio track is a [MediaItem] whose [MediaItem.kind]
/// is `'audio'`.
typedef AudioFile = MediaItem;
