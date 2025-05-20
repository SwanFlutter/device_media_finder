import 'package:device_media_finder/src/models/media_file.dart';
import 'package:device_media_finder/src/models/videofile.dart';

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
    required super.folderPath,
    required this.artist,
    required this.album,
  });

  /// Create an AudioFile from a map
  factory AudioFile.fromMap(Map<String, dynamic> map) {
    final String path = map['path'] as String;
    // Extract folder path from the file path using the same method as VideoFile
    final String folderPath = VideoFile.extractFolderPath(path);

    return AudioFile(
      id: map['id'] as String,
      name: map['name'] as String,
      size: map['size'] as int,
      path: path,
      uri: map['uri'] as String,
      dateAdded: map['dateAdded'] as int,
      mimeType: map['mimeType'] as String,
      duration: map['duration'] as int,
      folderPath: folderPath,
      artist: map['artist'] as String,
      album: map['album'] as String,
    );
  }
}
