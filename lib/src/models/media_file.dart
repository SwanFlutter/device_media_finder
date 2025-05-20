// ignore_for_file: unnecessary_getters_setters

/// Base class for media files
abstract class MediaFile {
  /// Unique identifier for the media file
  final String id;

  /// Display name of the media file
  final String name;

  /// Size of the media file in bytes
  final int size;

  /// Path to the media file on the device
  final String path;

  /// URI for accessing the media file
  final String uri;

  /// Date when the media file was added to the device (Unix timestamp)
  final int dateAdded;

  /// MIME type of the media file
  final String mimeType;

  /// Duration of the media file in milliseconds
  final int duration;

  /// Folder path where the media file is stored
  final String folderPath;

  MediaFile({
    required this.id,
    required this.name,
    required this.size,
    required this.path,
    required this.uri,
    required this.dateAdded,
    required this.mimeType,
    required this.duration,
    required this.folderPath,
  });
}
