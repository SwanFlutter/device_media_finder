# Device Media Finder

A Flutter plugin for accessing media files (videos and audio) on the device with support for various formats and thumbnails.

## Features

- Get videos from the device
- Get videos filtered by specific MIME types
- Get audio files from the device
- Generate thumbnails for videos
- Fetch videos with thumbnails in a single call

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  device_media_finder: ^0.0.1
```

## Usage

First, import the package:

```dart
import 'package:device_media_finder/device_media_finder.dart';
```

Then create an instance of `DeviceMediaFinder`:

```dart
final deviceMediaFinder = DeviceMediaFinder();
```

### Get All Videos

Retrieve all videos from the device:

```dart
Future<void> getAllVideos() async {
  try {
    final videos = await deviceMediaFinder.getVideos();
    print('Found ${videos.length} videos');

    // Access video properties
    for (final video in videos) {
      print('Video name: ${video.name}');
      print('Video size: ${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('Video duration: ${_formatDuration(video.duration)}');
      print('Video path: ${video.path}');
      print('Video MIME type: ${video.mimeType}');
    }
  } catch (e) {
    print('Error getting videos: $e');
  }
}

String _formatDuration(int milliseconds) {
  final seconds = (milliseconds / 1000).floor();
  final minutes = (seconds / 60).floor();
  final hours = (minutes / 60).floor();

  final remainingMinutes = minutes % 60;
  final remainingSeconds = seconds % 60;

  if (hours > 0) {
    return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  } else {
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
```

Example 2: Display videos in a ListView:

```dart
class VideoListScreen extends StatefulWidget {
  @override
  _VideoListScreenState createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  final deviceMediaFinder = DeviceMediaFinder();
  List<VideoFile> videos = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await deviceMediaFinder.getVideos();
      setState(() {
        videos = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading videos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Videos')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return ListTile(
                  title: Text(video.name),
                  subtitle: Text('${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
                  trailing: Text(_formatDuration(video.duration)),
                );
              },
            ),
    );
  }
}
```

### Get Videos by MIME Type

Filter videos by specific MIME types:

```dart
Future<void> getVideosByFormat() async {
  try {
    // Get only MP4 and 3GPP videos
    final videos = await deviceMediaFinder.getVideosByMimeType([
      'video/mp4',
      'video/3gpp',
       'video/*', // Fallback to catch any other video types
    ]);

    print('Found ${videos.length} MP4 and 3GPP videos');

    // Process the videos
    for (final video in videos) {
      print('Video name: ${video.name}');
      print('Video MIME type: ${video.mimeType}');
    }
  } catch (e) {
    print('Error getting videos by MIME type: $e');
  }
}
```

Example 2: Get videos of multiple formats:

```dart
Future<void> getAllVideoFormats() async {
  try {
    // Get videos of various formats
    final videos = await deviceMediaFinder.getVideosByMimeType([
      'video/mp4',
      'video/3gpp',
      'video/webm',
      'video/quicktime',
      'video/x-matroska',
      'video/avi',
      'video/mpeg',
      'video/x-ms-wmv',
      'video/*', // Fallback to catch any other video types
    ]);

    // Group videos by format
    final videosByFormat = <String, List<VideoFile>>{};

    for (final video in videos) {
      final format = video.mimeType;
      if (!videosByFormat.containsKey(format)) {
        videosByFormat[format] = [];
      }
      videosByFormat[format]!.add(video);
    }

    // Print summary
    videosByFormat.forEach((format, formatVideos) {
      print('Format: $format, Count: ${formatVideos.length}');
    });
  } catch (e) {
    print('Error getting videos by format: $e');
  }
}
```

### Get Audio Files

Retrieve audio files from the device:

```dart
Future<void> getAudioFiles() async {
  try {
    final audios = await deviceMediaFinder.getAudios();
    print('Found ${audios.length} audio files');

    // Access audio properties
    for (final audio in audios) {
      print('Audio name: ${audio.name}');
      print('Artist: ${audio.artist}');
      print('Album: ${audio.album}');
      print('Duration: ${_formatDuration(audio.duration)}');
      print('Size: ${(audio.size / (1024 * 1024)).toStringAsFixed(2)} MB');
    }
  } catch (e) {
    print('Error getting audio files: $e');
  }
}
```

Example 2: Display audio files in a ListView with artist and album information:

```dart
class AudioListScreen extends StatefulWidget {
  @override
  _AudioListScreenState createState() => _AudioListScreenState();
}

class _AudioListScreenState extends State<AudioListScreen> {
  final deviceMediaFinder = DeviceMediaFinder();
  List<AudioFile> audios = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAudios();
  }

  Future<void> _loadAudios() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await deviceMediaFinder.getAudios();
      setState(() {
        audios = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading audio files: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Music')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: audios.length,
              itemBuilder: (context, index) {
                final audio = audios[index];
                return ListTile(
                  leading: CircleAvatar(child: Icon(Icons.music_note)),
                  title: Text(audio.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Artist: ${audio.artist}'),
                      Text('Album: ${audio.album}'),
                    ],
                  ),
                  trailing: Text(_formatDuration(audio.duration)),
                );
              },
            ),
    );
  }
}
```

### Get Video Thumbnails

Generate thumbnails for videos:

```dart
Future<void> getVideoThumbnail(String videoId) async {
  try {
    // Get thumbnail with default size (128x128)
    final thumbnail = await deviceMediaFinder.getVideoThumbnail(videoId);

    if (thumbnail != null) {
      print('Thumbnail size: ${thumbnail.length} bytes');

      // Use the thumbnail in an Image widget
      final image = Image.memory(thumbnail);

      // Or save it to a file
      final file = File('path/to/save/thumbnail.jpg');
      await file.writeAsBytes(thumbnail);
    } else {
      print('Failed to generate thumbnail');
    }
  } catch (e) {
    print('Error getting thumbnail: $e');
  }
}
```

Example 2: Get a larger thumbnail:

```dart
Future<Widget> getVideoThumbnailWidget(String videoId) async {
  try {
    // Get a larger thumbnail (256x256)
    final thumbnail = await deviceMediaFinder.getVideoThumbnail(
      videoId,
      width: 256,
      height: 256,
    );

    if (thumbnail != null) {
      // Return an image widget with the thumbnail
      return Image.memory(
        thumbnail,
        fit: BoxFit.cover,
        width: 256,
        height: 256,
      );
    } else {
      // Return a placeholder if thumbnail generation failed
      return Container(
        width: 256,
        height: 256,
        color: Colors.grey,
        child: Icon(Icons.video_file, size: 64),
      );
    }
  } catch (e) {
    print('Error getting thumbnail: $e');
    // Return an error placeholder
    return Container(
      width: 256,
      height: 256,
      color: Colors.red.withOpacity(0.3),
      child: Icon(Icons.error, size: 64),
    );
  }
}
```

### Get Video with Thumbnail

Fetch a video and its thumbnail in a single call:

```dart
Future<void> getVideoWithThumbnail(String videoId) async {
  try {
    // Get the video with its thumbnail
    final video = await deviceMediaFinder.getVideoWithThumbnail(videoId);

    print('Video name: ${video.name}');
    print('Video duration: ${_formatDuration(video.duration)}');

    if (video.thumbnailData != null) {
      print('Thumbnail size: ${video.thumbnailData!.length} bytes');

      // Use the thumbnail in an Image widget
      final image = Image.memory(video.thumbnailData!);
    } else {
      print('No thumbnail available');
    }
  } catch (e) {
    print('Error getting video with thumbnail: $e');
  }
}
```

Example 2: Display a video with its thumbnail in a card:

```dart
class VideoDetailCard extends StatelessWidget {
  final String videoId;
  final DeviceMediaFinder deviceMediaFinder = DeviceMediaFinder();

  VideoDetailCard({required this.videoId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoFile>(
      future: deviceMediaFinder.getVideoWithThumbnail(
        videoId,
        width: 192,
        height: 108, // 16:9 aspect ratio
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Container(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Container(
              height: 200,
              child: Center(child: Text('Error loading video')),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Card(
            child: Container(
              height: 200,
              child: Center(child: Text('Video not found')),
            ),
          );
        }

        final video = snapshot.data!;

        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              video.thumbnailData != null
                  ? Image.memory(
                      video.thumbnailData!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 180,
                      width: double.infinity,
                      color: Colors.grey,
                      child: Icon(Icons.video_file, size: 64),
                    ),

              // Video details
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Duration: ${_formatDuration(video.duration)}'),
                        Spacer(),
                        Text('${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

### Get All Videos with Auto-Generated Thumbnails

Fetch all videos with their thumbnails in a single call:

```dart
Future<void> loadAllVideosWithThumbnails() async {
  try {
    // Get all videos with thumbnails (default thumbnail size: 128x128)
    final videos = await deviceMediaFinder.getVideosWithAutoThumbnails();

    print('Loaded ${videos.length} videos with thumbnails');

    // Count videos that have thumbnails
    final videosWithThumbnails = videos.where((v) => v.thumbnailData != null).length;
    print('$videosWithThumbnails videos have thumbnails');

    // Use the videos with thumbnails
    for (final video in videos) {
      if (video.thumbnailData != null) {
        // Use the thumbnail
        final thumbnailWidget = Image.memory(video.thumbnailData!);
      }
    }
  } catch (e) {
    print('Error loading videos with thumbnails: $e');
  }
}
```

Example 2: Display videos in a grid with custom thumbnail size:

```dart
class VideoGridScreen extends StatefulWidget {
  @override
  _VideoGridScreenState createState() => _VideoGridScreenState();
}

class _VideoGridScreenState extends State<VideoGridScreen> {
  final deviceMediaFinder = DeviceMediaFinder();
  bool isLoading = true;
  List<VideoFile> videos = [];

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Get videos with larger thumbnails for better quality in the grid
      final result = await deviceMediaFinder.getVideosWithAutoThumbnails(
        width: 256,
        height: 144, // 16:9 aspect ratio
      );

      setState(() {
        videos = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading videos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Gallery')),
      body: isLoading
        ? Center(child: CircularProgressIndicator())
        : videos.isEmpty
          ? Center(child: Text('No videos found'))
          : GridView.builder(
              padding: EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 16 / 9,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return GestureDetector(
                  onTap: () {
                    // Handle video tap (e.g., play the video)
                    print('Play video: ${video.path}');
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail
                      video.thumbnailData != null
                        ? Image.memory(
                            video.thumbnailData!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Colors.grey.shade300,
                            child: Icon(Icons.video_file, size: 48),
                          ),

                      // Video name overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.black.withOpacity(0.5),
                          padding: EdgeInsets.all(4),
                          child: Text(
                            video.name,
                            style: TextStyle(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // Play icon overlay
                      Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white.withOpacity(0.7),
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
```

### Generate Thumbnails for a List of Videos

Generate thumbnails for a list of videos you already have:

```dart
Future<void> getThumbnailsForFilteredVideos() async {
  try {
    // First get all videos
    final allVideos = await deviceMediaFinder.getVideos();

    // Filter videos (e.g., only MP4 videos)
    final mp4Videos = allVideos.where(
      (video) => video.mimeType == 'video/mp4'
    ).toList();

    print('Found ${mp4Videos.length} MP4 videos');

    // Generate thumbnails for the filtered videos
    final videosWithThumbnails = await deviceMediaFinder.generateThumbnailsForVideos(
      mp4Videos,
      width: 192,
      height: 108, // 16:9 aspect ratio
    );

    // Use the videos with thumbnails
    for (final video in videosWithThumbnails) {
      if (video.thumbnailData != null) {
        print('Video ${video.name} has a thumbnail');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

Example 2: Get thumbnails for recent videos:

```dart
Future<List<VideoFile>> getRecentVideosWithThumbnails() async {
  final deviceMediaFinder = DeviceMediaFinder();

  try {
    // Get all videos
    final allVideos = await deviceMediaFinder.getVideos();

    // Filter videos added in the last 7 days
    final now = DateTime.now();
    final oneWeekAgo = now.subtract(Duration(days: 7));

    final recentVideos = allVideos.where((video) {
      final dateAdded = DateTime.fromMillisecondsSinceEpoch(video.dateAdded * 1000);
      return dateAdded.isAfter(oneWeekAgo);
    }).toList();

    print('Found ${recentVideos.length} videos from the last 7 days');

    // Generate thumbnails for the recent videos
    final videosWithThumbnails = await deviceMediaFinder.generateThumbnailsForVideos(
      recentVideos,
    );

    return videosWithThumbnails;
  } catch (e) {
    print('Error getting recent videos with thumbnails: $e');
    return [];
  }
}
```

## Permissions

### Android

Add the following permissions to your `AndroidManifest.xml`:

```xml
<!-- For Android 13 and above -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- For devices with Android 12 or lower -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

### iOS

Add the following to your `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to your photo library to display your videos and generate thumbnails.</string>
```

## Supported Formats

### Video Formats
- MP4 (video/mp4)
- 3GPP (video/3gpp)
- WebM (video/webm)
- QuickTime (video/quicktime)
- Matroska (video/x-matroska)
- AVI (video/avi)
- MPEG (video/mpeg)
- WMV (video/x-ms-wmv)
- And others (using video/*)

### Audio Formats
- MP3
- AAC
- WAV
- FLAC
- OGG
- And others supported by the device

## Playing Media Files

### Playing Videos from Thumbnails

When you display thumbnails, you can use the video's path or URI to play it when the user taps on the thumbnail:

```dart
import 'package:video_player/video_player.dart';

class VideoThumbnailPlayer extends StatefulWidget {
  final VideoFile video;

  const VideoThumbnailPlayer({Key? key, required this.video}) : super(key: key);

  @override
  _VideoThumbnailPlayerState createState() => _VideoThumbnailPlayerState();
}

class _VideoThumbnailPlayerState extends State<VideoThumbnailPlayer> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // Initialize the controller with the video file path
    _controller = VideoPlayerController.file(File(widget.video.path))
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              if (_controller.value.isInitialized) {
                if (_isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                _isPlaying = !_isPlaying;
              }
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Show thumbnail until video is initialized
              if (!_controller.value.isInitialized && widget.video.thumbnailData != null)
                Image.memory(
                  widget.video.thumbnailData!,
                  width: 320,
                  height: 180,
                  fit: BoxFit.cover,
                )
              else if (_controller.value.isInitialized)
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              else
                Container(
                  width: 320,
                  height: 180,
                  color: Colors.black,
                  child: Center(child: CircularProgressIndicator()),
                ),

              // Show play/pause button overlay
              if (!_controller.value.isInitialized || !_isPlaying)
                Icon(
                  Icons.play_circle_fill,
                  size: 64,
                  color: Colors.white.withOpacity(0.7),
                ),
            ],
          ),
        ),

        // Video details
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.video.name,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Duration: ${_formatDuration(widget.video.duration)}'),
              Text('Path: ${widget.video.path}'),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final hours = (minutes / 60).floor();

    final remainingMinutes = minutes % 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }
}
```

### Using Video Thumbnails in a Grid with Playback

Here's an example of how to create a video gallery with thumbnails that can play videos when tapped:

```dart
class VideoGalleryScreen extends StatefulWidget {
  @override
  _VideoGalleryScreenState createState() => _VideoGalleryScreenState();
}

class _VideoGalleryScreenState extends State<VideoGalleryScreen> {
  final deviceMediaFinder = DeviceMediaFinder();
  List<VideoFile> videos = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Get videos with thumbnails
      final result = await deviceMediaFinder.getVideosWithAutoThumbnails(
        width: 256,
        height: 144,
      );

      setState(() {
        videos = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading videos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Gallery')),
      body: isLoading
        ? Center(child: CircularProgressIndicator())
        : GridView.builder(
            padding: EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 16 / 9,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              return GestureDetector(
                onTap: () {
                  // Navigate to a video player screen when thumbnail is tapped
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(video: video),
                    ),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Thumbnail
                    video.thumbnailData != null
                      ? Image.memory(
                          video.thumbnailData!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey.shade300,
                          child: Icon(Icons.video_file, size: 48),
                        ),

                    // Video name overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        padding: EdgeInsets.all(4),
                        child: Text(
                          video.name,
                          style: TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                    // Play icon overlay
                    Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        color: Colors.white.withOpacity(0.7),
                        size: 48,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}

// Video player screen that uses the video path to play the video
class VideoPlayerScreen extends StatefulWidget {
  final VideoFile video;

  const VideoPlayerScreen({Key? key, required this.video}) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize the controller with the video file path
    _controller = VideoPlayerController.file(File(widget.video.path))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          // Auto-play when ready
          _controller.play();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.video.name)),
      body: Column(
        children: [
          // Video player
          _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              ),

          // Video controls
          VideoProgressIndicator(
            _controller,
            allowScrubbing: true,
            padding: EdgeInsets.all(16),
          ),

          // Play/pause button
          IconButton(
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () {
              setState(() {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
              });
            },
          ),

          // Video details
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text('Name: ${widget.video.name}'),
                Text('Size: ${(widget.video.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
                Text('Duration: ${_formatDuration(widget.video.duration)}'),
                Text('Path: ${widget.video.path}'),
                Text('MIME Type: ${widget.video.mimeType}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final hours = (minutes / 60).floor();

    final remainingMinutes = minutes % 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }
}
```

### Playing Audio Files

Similarly, you can use the path or URI of audio files to play them:

```dart
import 'package:audioplayers/audioplayers.dart';

class AudioPlayerWidget extends StatefulWidget {
  final AudioFile audio;

  const AudioPlayerWidget({Key? key, required this.audio}) : super(key: key);

  @override
  _AudioPlayerWidgetState createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();

    // Listen to player state changes
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    // Listen to duration changes
    _audioPlayer.onDurationChanged.listen((newDuration) {
      setState(() {
        _duration = newDuration;
      });
    });

    // Listen to position changes
    _audioPlayer.onPositionChanged.listen((newPosition) {
      setState(() {
        _position = newPosition;
      });
    });

    // Set the source to the audio file path
    _audioPlayer.setSource(DeviceFileSource(widget.audio.path));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Audio info
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade200,
                  child: Icon(Icons.music_note),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.audio.name,
                        style: TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.audio.artist} • ${widget.audio.album}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 16),

            // Progress bar
            Slider(
              min: 0,
              max: _duration.inSeconds.toDouble(),
              value: _position.inSeconds.toDouble(),
              onChanged: (value) {
                final position = Duration(seconds: value.toInt());
                _audioPlayer.seek(position);
              },
            ),

            // Time indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position)),
                Text(_formatDuration(_duration)),
              ],
            ),

            SizedBox(height: 16),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.replay_10),
                  onPressed: () {
                    _audioPlayer.seek(Duration(seconds: _position.inSeconds - 10));
                  },
                ),
                IconButton(
                  iconSize: 48,
                  icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  onPressed: () {
                    if (_isPlaying) {
                      _audioPlayer.pause();
                    } else {
                      _audioPlayer.resume();
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.forward_10),
                  onPressed: () {
                    _audioPlayer.seek(Duration(seconds: _position.inSeconds + 10));
                  },
                ),
              ],
            ),

            SizedBox(height: 16),

            // File details
            Text('Path: ${widget.audio.path}'),
            Text('Size: ${(widget.audio.size / (1024 * 1024)).toStringAsFixed(2)} MB'),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return [
      if (duration.inHours > 0) hours,
      minutes,
      seconds,
    ].join(':');
  }
}
```

## Troubleshooting

If you're having trouble finding videos or audio files:

1. Make sure you've granted the necessary permissions
2. Try using the `getVideosByMimeType` method with specific formats
3. Check the logs for any error messages
4. Verify that the files exist on the device and are valid media files

