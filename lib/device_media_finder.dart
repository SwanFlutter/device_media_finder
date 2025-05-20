import 'package:flutter/foundation.dart';

import 'device_media_finder_platform_interface.dart';
import 'models/media_file.dart';

/// Main plugin class for accessing media files (videos and audio) on the device
/// with support for various formats and thumbnails.
class DeviceMediaFinder {
  /// Get the platform version
  ///
  /// Returns the Android or iOS version as a string.
  ///
  /// Example 1:
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final platformVersion = await deviceMediaFinder.getPlatformVersion();
  /// print('Running on: $platformVersion');
  /// ```
  ///
  /// Example 2:
  /// ```dart
  /// try {
  ///   final deviceMediaFinder = DeviceMediaFinder();
  ///   final platformVersion = await deviceMediaFinder.getPlatformVersion();
  ///   print('Running on: $platformVersion');
  /// } catch (e) {
  ///   print('Failed to get platform version: $e');
  /// }
  /// ```
  Future<String?> getPlatformVersion() {
    return DeviceMediaFinderPlatform.instance.getPlatformVersion();
  }

  /// Get a list of videos from the device
  ///
  /// Returns a list of [VideoFile] objects representing all videos found on the device.
  ///
  /// Example 1: Get all videos and print their names
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final videos = await deviceMediaFinder.getVideos();
  ///
  /// print('Found ${videos.length} videos');
  /// for (final video in videos) {
  ///   print('Video: ${video.name}, Size: ${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB');
  /// }
  /// ```
  ///
  /// Example 2: Get videos and display in a ListView
  /// ```dart
  /// class VideoScreen extends StatefulWidget {
  ///   @override
  ///   _VideoScreenState createState() => _VideoScreenState();
  /// }
  ///
  /// class _VideoScreenState extends State<VideoScreen> {
  ///   final deviceMediaFinder = DeviceMediaFinder();
  ///   List<VideoFile> videos = [];
  ///   bool isLoading = true;
  ///
  ///   @override
  ///   void initState() {
  ///     super.initState();
  ///     _loadVideos();
  ///   }
  ///
  ///   Future<void> _loadVideos() async {
  ///     try {
  ///       final result = await deviceMediaFinder.getVideos();
  ///       setState(() {
  ///         videos = result;
  ///         isLoading = false;
  ///       });
  ///     } catch (e) {
  ///       setState(() {
  ///         isLoading = false;
  ///       });
  ///       print('Error loading videos: $e');
  ///     }
  ///   }
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     return Scaffold(
  ///       appBar: AppBar(title: Text('Videos')),
  ///       body: isLoading
  ///         ? Center(child: CircularProgressIndicator())
  ///         : ListView.builder(
  ///             itemCount: videos.length,
  ///             itemBuilder: (context, index) {
  ///               final video = videos[index];
  ///               return ListTile(
  ///                 title: Text(video.name),
  ///                 subtitle: Text('${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
  ///               );
  ///             },
  ///           ),
  ///     );
  ///   }
  /// }
  /// ```
  Future<List<VideoFile>> getVideos() {
    return DeviceMediaFinderPlatform.instance.getVideos();
  }

  /// Get a list of videos from the device filtered by MIME types
  ///
  /// [mimeTypes] is a list of MIME types to filter by (e.g. ["video/mp4", "video/3gpp"])
  /// You can also use wildcards like "video/*" to get all videos of a certain type
  ///
  /// Example 1: Get only MP4 videos
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final mp4Videos = await deviceMediaFinder.getVideosByMimeType(['video/mp4']);
  ///
  /// print('Found ${mp4Videos.length} MP4 videos');
  /// for (final video in mp4Videos) {
  ///   print('MP4 Video: ${video.name}');
  /// }
  /// ```
  ///
  /// Example 2: Get videos of multiple formats
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final videos = await deviceMediaFinder.getVideosByMimeType([
  ///   'video/mp4',
  ///   'video/3gpp',
  ///   'video/webm',
  ///   'video/quicktime',
  ///   'video/x-matroska',
  /// ]);
  ///
  /// // Group videos by format
  /// final videosByFormat = <String, List<VideoFile>>{};
  ///
  /// for (final video in videos) {
  ///   final format = video.mimeType;
  ///   if (!videosByFormat.containsKey(format)) {
  ///     videosByFormat[format] = [];
  ///   }
  ///   videosByFormat[format]!.add(video);
  /// }
  ///
  /// // Print summary
  /// videosByFormat.forEach((format, formatVideos) {
  ///   print('Format: $format, Count: ${formatVideos.length}');
  /// });
  /// ```
  Future<List<VideoFile>> getVideosByMimeType(List<String> mimeTypes) {
    return DeviceMediaFinderPlatform.instance.getVideosByMimeType(mimeTypes);
  }

  /// Get a list of audio files from the device
  ///
  /// Returns a list of [AudioFile] objects representing all audio files found on the device.
  ///
  /// Example 1: Get all audio files and print their details
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final audioFiles = await deviceMediaFinder.getAudios();
  ///
  /// print('Found ${audioFiles.length} audio files');
  /// for (final audio in audioFiles) {
  ///   print('Audio: ${audio.name}');
  ///   print('  Artist: ${audio.artist}');
  ///   print('  Album: ${audio.album}');
  ///   print('  Duration: ${audio.duration} ms');
  /// }
  /// ```
  ///
  /// Example 2: Get audio files and filter by artist
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final allAudioFiles = await deviceMediaFinder.getAudios();
  ///
  /// // Filter audio files by a specific artist
  /// final artistName = 'Favorite Artist';
  /// final artistSongs = allAudioFiles.where(
  ///   (audio) => audio.artist.toLowerCase() == artistName.toLowerCase()
  /// ).toList();
  ///
  /// print('Found ${artistSongs.length} songs by $artistName');
  /// for (final song in artistSongs) {
  ///   print('Song: ${song.name}, Album: ${song.album}');
  /// }
  /// ```
  Future<List<AudioFile>> getAudios() {
    return DeviceMediaFinderPlatform.instance.getAudios();
  }

  /// Get a thumbnail for a video
  ///
  /// [videoId] is the ID of the video
  /// [width] and [height] are the dimensions of the thumbnail (default: 128x128)
  ///
  /// Returns a [Uint8List] containing the thumbnail image data, or null if the thumbnail
  /// could not be generated.
  ///
  /// Example 1: Get a thumbnail and display it
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final videoId = 'your_video_id';
  ///
  /// final thumbnail = await deviceMediaFinder.getVideoThumbnail(videoId);
  /// if (thumbnail != null) {
  ///   // Display the thumbnail in an Image widget
  ///   return Image.memory(thumbnail);
  /// } else {
  ///   // Show a placeholder if thumbnail generation failed
  ///   return Icon(Icons.video_file);
  /// }
  /// ```
  ///
  /// Example 2: Get a custom-sized thumbnail and save it to a file
  /// ```dart
  /// import 'dart:io';
  ///
  /// Future<void> saveThumbnail(String videoId, String outputPath) async {
  ///   final deviceMediaFinder = DeviceMediaFinder();
  ///
  ///   // Get a larger thumbnail (256x256)
  ///   final thumbnail = await deviceMediaFinder.getVideoThumbnail(
  ///     videoId,
  ///     width: 256,
  ///     height: 256,
  ///   );
  ///
  ///   if (thumbnail != null) {
  ///     // Save the thumbnail to a file
  ///     final file = File(outputPath);
  ///     await file.writeAsBytes(thumbnail);
  ///     print('Thumbnail saved to: $outputPath');
  ///   } else {
  ///     print('Failed to generate thumbnail');
  ///   }
  /// }
  /// ```
  Future<Uint8List?> getVideoThumbnail(
    String videoId, {
    int width = 128,
    int height = 128,
  }) {
    return DeviceMediaFinderPlatform.instance.getVideoThumbnail(
      videoId,
      width: width,
      height: height,
    );
  }

  /// Get a video with its thumbnail
  ///
  /// This is a convenience method that fetches a video and its thumbnail in one call.
  ///
  /// [videoId] is the ID of the video
  /// [width] and [height] are the dimensions of the thumbnail (default: 128x128)
  ///
  /// Returns a [VideoFile] with the thumbnailData property populated if the thumbnail
  /// was successfully generated.
  ///
  /// Example 1: Get a video with its thumbnail and display both
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  /// final videoId = 'your_video_id';
  ///
  /// try {
  ///   final video = await deviceMediaFinder.getVideoWithThumbnail(videoId);
  ///
  ///   return Column(
  ///     children: [
  ///       // Display the thumbnail
  ///       video.thumbnailData != null
  ///         ? Image.memory(video.thumbnailData!)
  ///         : Icon(Icons.video_file),
  ///
  ///       // Display video details
  ///       Text('Name: ${video.name}'),
  ///       Text('Duration: ${video.duration} ms'),
  ///       Text('Size: ${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
  ///     ],
  ///   );
  /// } catch (e) {
  ///   return Text('Error: $e');
  /// }
  /// ```
  ///
  /// Example 2: Create a video player with thumbnail preview
  /// ```dart
  /// class VideoPlayerWithThumbnail extends StatelessWidget {
  ///   final String videoId;
  ///   final DeviceMediaFinder deviceMediaFinder = DeviceMediaFinder();
  ///
  ///   VideoPlayerWithThumbnail({required this.videoId});
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     return FutureBuilder<VideoFile>(
  ///       future: deviceMediaFinder.getVideoWithThumbnail(
  ///         videoId,
  ///         width: 320,
  ///         height: 180,
  ///       ),
  ///       builder: (context, snapshot) {
  ///         if (snapshot.connectionState == ConnectionState.waiting) {
  ///           return Center(child: CircularProgressIndicator());
  ///         }
  ///
  ///         if (snapshot.hasError) {
  ///           return Center(child: Text('Error: ${snapshot.error}'));
  ///         }
  ///
  ///         if (!snapshot.hasData) {
  ///           return Center(child: Text('Video not found'));
  ///         }
  ///
  ///         final video = snapshot.data!;
  ///
  ///         return Column(
  ///           children: [
  ///             // Thumbnail as preview
  ///             GestureDetector(
  ///               onTap: () {
  ///                 // Launch video player with video.path or video.uri
  ///                 print('Play video: ${video.path}');
  ///               },
  ///               child: Stack(
  ///                 alignment: Alignment.center,
  ///                 children: [
  ///                   // Thumbnail
  ///                   video.thumbnailData != null
  ///                     ? Image.memory(
  ///                         video.thumbnailData!,
  ///                         width: 320,
  ///                         height: 180,
  ///                         fit: BoxFit.cover,
  ///                       )
  ///                     : Container(
  ///                         width: 320,
  ///                         height: 180,
  ///                         color: Colors.grey,
  ///                       ),
  ///
  ///                   // Play button overlay
  ///                   Icon(
  ///                     Icons.play_circle_fill,
  ///                     size: 64,
  ///                     color: Colors.white.withOpacity(0.8),
  ///                   ),
  ///                 ],
  ///               ),
  ///             ),
  ///
  ///             // Video details
  ///             Padding(
  ///               padding: EdgeInsets.all(8.0),
  ///               child: Text(
  ///                 video.name,
  ///                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  ///               ),
  ///             ),
  ///           ],
  ///         );
  ///       },
  ///     );
  ///   }
  /// }
  /// ```
  Future<VideoFile> getVideoWithThumbnail(
    String videoId, {
    int width = 128,
    int height = 128,
  }) async {
    final videos = await getVideos();
    final video = videos.firstWhere((v) => v.id == videoId);
    final thumbnail = await getVideoThumbnail(
      videoId,
      width: width,
      height: height,
    );
    video.thumbnailData = thumbnail;
    return video;
  }

  /// Get all videos with auto-generated thumbnails
  ///
  /// This method fetches all videos and automatically generates thumbnails for each one.
  /// It's a convenient way to get a complete list of videos with thumbnails in one call.
  ///
  /// [width] and [height] are the dimensions of the thumbnails (default: 128x128)
  ///
  /// Returns a list of [VideoFile] objects with thumbnailData properties populated.
  ///
  /// Example 1: Get all videos with thumbnails and display in a grid
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  ///
  /// Widget buildVideoGrid() {
  ///   return FutureBuilder<List<VideoFile>>(
  ///     future: deviceMediaFinder.getVideosWithAutoThumbnails(),
  ///     builder: (context, snapshot) {
  ///       if (snapshot.connectionState == ConnectionState.waiting) {
  ///         return Center(child: CircularProgressIndicator());
  ///       }
  ///
  ///       if (snapshot.hasError) {
  ///         return Center(child: Text('Error: ${snapshot.error}'));
  ///       }
  ///
  ///       if (!snapshot.hasData || snapshot.data!.isEmpty) {
  ///         return Center(child: Text('No videos found'));
  ///       }
  ///
  ///       final videos = snapshot.data!;
  ///
  ///       return GridView.builder(
  ///         gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
  ///           crossAxisCount: 2,
  ///           childAspectRatio: 16 / 9,
  ///           crossAxisSpacing: 8,
  ///           mainAxisSpacing: 8,
  ///         ),
  ///         itemCount: videos.length,
  ///         itemBuilder: (context, index) {
  ///           final video = videos[index];
  ///           return GestureDetector(
  ///             onTap: () {
  ///               // Handle video tap (e.g., play the video)
  ///               print('Play video: ${video.path}');
  ///             },
  ///             child: Stack(
  ///               fit: StackFit.expand,
  ///               children: [
  ///                 // Thumbnail
  ///                 video.thumbnailData != null
  ///                   ? Image.memory(
  ///                       video.thumbnailData!,
  ///                       fit: BoxFit.cover,
  ///                     )
  ///                   : Container(
  ///                       color: Colors.grey.shade300,
  ///                       child: Icon(Icons.video_file, size: 48),
  ///                     ),
  ///
  ///                 // Video name overlay at bottom
  ///                 Positioned(
  ///                   bottom: 0,
  ///                   left: 0,
  ///                   right: 0,
  ///                   child: Container(
  ///                     color: Colors.black.withOpacity(0.5),
  ///                     padding: EdgeInsets.all(4),
  ///                     child: Text(
  ///                       video.name,
  ///                       style: TextStyle(color: Colors.white),
  ///                       maxLines: 1,
  ///                       overflow: TextOverflow.ellipsis,
  ///                     ),
  ///                   ),
  ///                 ),
  ///
  ///                 // Play icon overlay
  ///                 Center(
  ///                   child: Icon(
  ///                     Icons.play_circle_outline,
  ///                     color: Colors.white.withOpacity(0.7),
  ///                     size: 48,
  ///                   ),
  ///                 ),
  ///               ],
  ///             ),
  ///           );
  ///         },
  ///       );
  ///     },
  ///   );
  /// }
  /// ```
  ///
  /// Example 2: Get videos with thumbnails and filter by duration
  /// ```dart
  /// Future<List<VideoFile>> getLongVideosWithThumbnails() async {
  ///   final deviceMediaFinder = DeviceMediaFinder();
  ///
  ///   // Get all videos with thumbnails
  ///   final allVideos = await deviceMediaFinder.getVideosWithAutoThumbnails();
  ///
  ///   // Filter videos longer than 5 minutes (300000 milliseconds)
  ///   final longVideos = allVideos.where((video) => video.duration > 300000).toList();
  ///
  ///   print('Found ${longVideos.length} videos longer than 5 minutes');
  ///
  ///   return longVideos;
  /// }
  /// ```
  Future<List<VideoFile>> getVideosWithAutoThumbnails({
    int width = 128,
    int height = 128,
  }) async {
    // Get all videos
    final videos = await getVideos();

    // Process videos in batches to avoid overwhelming the device
    const int batchSize = 5;

    for (int i = 0; i < videos.length; i += batchSize) {
      final end =
          (i + batchSize < videos.length) ? i + batchSize : videos.length;
      final batch = videos.sublist(i, end);

      // Process each video in the current batch in parallel
      await Future.wait(
        batch.map((video) async {
          try {
            final thumbnail = await getVideoThumbnail(
              video.id,
              width: width,
              height: height,
            );
            video.thumbnailData = thumbnail;
          } catch (e) {
            // If thumbnail generation fails for a video, continue with the others
            debugPrint(
              'Failed to generate thumbnail for video ${video.id}: $e',
            );
          }
        }),
      );
    }

    return videos;
  }

  /// Generate thumbnails for a list of videos
  ///
  /// This method takes a list of videos and generates thumbnails for each one.
  /// It's useful when you already have a list of videos and want to add thumbnails to them.
  ///
  /// [videos] is the list of videos to generate thumbnails for
  /// [width] and [height] are the dimensions of the thumbnails (default: 128x128)
  ///
  /// Returns the same list of [VideoFile] objects with thumbnailData properties populated.
  ///
  /// Example 1: Get thumbnails for filtered videos
  /// ```dart
  /// final deviceMediaFinder = DeviceMediaFinder();
  ///
  /// Future<List<VideoFile>> getRecentVideosWithThumbnails() async {
  ///   // Get all videos
  ///   final allVideos = await deviceMediaFinder.getVideos();
  ///
  ///   // Filter videos added in the last 7 days
  ///   final now = DateTime.now();
  ///   final oneWeekAgo = now.subtract(Duration(days: 7));
  ///
  ///   final recentVideos = allVideos.where((video) {
  ///     final dateAdded = DateTime.fromMillisecondsSinceEpoch(video.dateAdded * 1000);
  ///     return dateAdded.isAfter(oneWeekAgo);
  ///   }).toList();
  ///
  ///   // Generate thumbnails for the filtered videos
  ///   final videosWithThumbnails = await deviceMediaFinder.generateThumbnailsForVideos(
  ///     recentVideos,
  ///     width: 192,
  ///     height: 108, // 16:9 aspect ratio
  ///   );
  ///
  ///   return videosWithThumbnails;
  /// }
  /// ```
  ///
  /// Example 2: Get thumbnails for videos of a specific format
  /// ```dart
  /// Future<List<VideoFile>> getMp4VideosWithThumbnails() async {
  ///   final deviceMediaFinder = DeviceMediaFinder();
  ///
  ///   // Get MP4 videos
  ///   final mp4Videos = await deviceMediaFinder.getVideosByMimeType(['video/mp4']);
  ///
  ///   // Generate thumbnails for the MP4 videos
  ///   final videosWithThumbnails = await deviceMediaFinder.generateThumbnailsForVideos(mp4Videos);
  ///
  ///   return videosWithThumbnails;
  /// }
  /// ```
  Future<List<VideoFile>> generateThumbnailsForVideos(
    List<VideoFile> videos, {
    int width = 128,
    int height = 128,
  }) async {
    // Process videos in batches to avoid overwhelming the device
    const int batchSize = 5;

    for (int i = 0; i < videos.length; i += batchSize) {
      final end =
          (i + batchSize < videos.length) ? i + batchSize : videos.length;
      final batch = videos.sublist(i, end);

      // Process each video in the current batch in parallel
      await Future.wait(
        batch.map((video) async {
          try {
            final thumbnail = await getVideoThumbnail(
              video.id,
              width: width,
              height: height,
            );
            video.thumbnailData = thumbnail;
          } catch (e) {
            // If thumbnail generation fails for a video, continue with the others
            debugPrint(
              'Failed to generate thumbnail for video ${video.id}: $e',
            );
          }
        }),
      );
    }

    return videos;
  }
}
