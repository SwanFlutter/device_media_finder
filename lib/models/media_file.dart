// ignore_for_file: unnecessary_getters_setters

import 'dart:typed_data';

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

  MediaFile({
    required this.id,
    required this.name,
    required this.size,
    required this.path,
    required this.uri,
    required this.dateAdded,
    required this.mimeType,
    required this.duration,
  });
}

/// Represents a video file on the device
class VideoFile extends MediaFile {
  /// Cached thumbnail data
  Uint8List? _thumbnailData;

  VideoFile({
    required super.id,
    required super.name,
    required super.size,
    required super.path,
    required super.uri,
    required super.dateAdded,
    required super.mimeType,
    required super.duration,
    Uint8List? thumbnailData,
  }) : _thumbnailData = thumbnailData;

  /// Get the thumbnail data if it's already cached
  Uint8List? get thumbnailData => _thumbnailData;

  /// Set the thumbnail data
  set thumbnailData(Uint8List? data) {
    _thumbnailData = data;
  }

  /// Create a VideoFile from a map
  factory VideoFile.fromMap(Map<String, dynamic> map) {
    return VideoFile(
      id: map['id'] as String,
      name: map['name'] as String,
      size: map['size'] as int,
      path: map['path'] as String,
      uri: map['uri'] as String,
      dateAdded: map['dateAdded'] as int,
      mimeType: map['mimeType'] as String,
      duration: map['duration'] as int,
    );
  }
}

/// Represents an audio file on the device
class AudioFile extends MediaFile {
  /// Artist of the audio file
  final String artist;

  /// Album of the audio file
  final String album;

  AudioFile({
    required super.id,
    required super.name,
    required super.size,
    required super.path,
    required super.uri,
    required super.dateAdded,
    required super.mimeType,
    required super.duration,
    required this.artist,
    required this.album,
  });

  /// Create an AudioFile from a map
  factory AudioFile.fromMap(Map<String, dynamic> map) {
    return AudioFile(
      id: map['id'] as String,
      name: map['name'] as String,
      size: map['size'] as int,
      path: map['path'] as String,
      uri: map['uri'] as String,
      dateAdded: map['dateAdded'] as int,
      mimeType: map['mimeType'] as String,
      duration: map['duration'] as int,
      artist: map['artist'] as String,
      album: map['album'] as String,
    );
  }
}
