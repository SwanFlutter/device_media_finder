// ignore_for_file: unnecessary_getters_setters

import 'package:device_media_finder/src/models/media_file.dart';
import 'package:flutter/foundation.dart';

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
    required super.folderPath,
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
    final String path = map['path'] as String;
    // Extract folder path from the file path
    final String folderPath = extractFolderPath(path);

    return VideoFile(
      id: map['id'] as String,
      name: map['name'] as String,
      size: map['size'] as int,
      path: path,
      uri: map['uri'] as String,
      dateAdded: map['dateAdded'] as int,
      mimeType: map['mimeType'] as String,
      duration: map['duration'] as int,
      folderPath: folderPath,
    );
  }

  /// Extract the folder path from a file path
  static String extractFolderPath(String filePath) {
    try {
      final lastSeparatorIndex = filePath.lastIndexOf('/');
      if (lastSeparatorIndex != -1) {
        return filePath.substring(0, lastSeparatorIndex);
      }
    } catch (e) {
      // If there's any error, return the original path
      debugPrint('Error extracting folder path: $e');
    }
    return filePath; // Return the original path if we can't extract the folder
  }
}
