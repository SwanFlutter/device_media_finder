import 'dart:async';

import 'package:device_media_finder/device_media_finder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  String platformVersions = 'Unknown';
  final _deviceMediaFinderPlugin = DeviceMediaFinder();
  List<VideoFile> _videos = [];
  List<AudioFile> _audios = [];
  Map<String, int> _videoFolders = {};
  bool _isLoading = false;
  bool _hasSearchedVideos = false;
  bool _hasSearchedAudios = false;
  bool _hasSearchedFolders = false;
  late TabController _tabController;

  final Map<String, Uint8List?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    initPlatformState();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      return;
    }

    // Load data for the selected tab if it hasn't been loaded yet
    switch (_tabController.index) {
      case 0: // Videos tab
        if (_videos.isEmpty && !_hasSearchedVideos && !_isLoading) {
          _loadVideos();
        }
        break;
      case 1: // Music tab
        if (_audios.isEmpty && !_hasSearchedAudios && !_isLoading) {
          _loadAudios();
        }
        break;
      case 2: // Folders tab
        if (_videoFolders.isEmpty && !_hasSearchedFolders && !_isLoading) {
          _loadVideoFolders();
        }
        break;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _deviceMediaFinderPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      platformVersions = platformVersion;
    });
  }

  Future<void> _loadVideos() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use the new method to get videos by MIME type
      // This includes all common video formats
      final videos = await _deviceMediaFinderPlugin.getVideosByMimeType([
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

      if (!mounted) return;
      setState(() {
        _videos = videos;
        _isLoading = false;
        _hasSearchedVideos = true;
      });

      // Log the found video formats for debugging
      if (videos.isNotEmpty) {
        final formats = videos.map((v) => v.mimeType).toSet().toList();
        debugPrint('Found videos with formats: $formats');
      } else {
        debugPrint('No videos found');
      }
    } catch (e) {
      debugPrint('Error loading videos: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasSearchedVideos = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading videos: $e')));
    }
  }

  Future<void> _loadAudios() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final audios = await _deviceMediaFinderPlugin.getAudios();
      if (!mounted) return;
      setState(() {
        _audios = audios;
        _isLoading = false;
        _hasSearchedAudios = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasSearchedAudios = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading audios: $e')));
    }
  }

  Future<void> _loadVideoFolders() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final folders = await _deviceMediaFinderPlugin.getVideoFolders();
      if (!mounted) return;
      setState(() {
        _videoFolders = folders;
        _isLoading = false;
        _hasSearchedFolders = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasSearchedFolders = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading video folders: $e')),
      );
    }
  }

  Future<Uint8List?> _getThumbnail(String videoId) async {
    if (_thumbnailCache.containsKey(videoId)) {
      return _thumbnailCache[videoId];
    }

    try {
      final thumbnail = await _deviceMediaFinderPlugin.getVideoThumbnail(
        videoId,
      );
      _thumbnailCache[videoId] = thumbnail;
      return thumbnail;
    } catch (e) {
      debugPrint('Error loading thumbnail: $e');
      return null;
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Device Media Finder'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Videos', icon: Icon(Icons.video_library)),
              Tab(text: 'Music', icon: Icon(Icons.music_note)),
              Tab(text: 'Folders', icon: Icon(Icons.folder)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Videos Tab
            _videos.isEmpty
                ? Center(
                  child:
                      _isLoading
                          ? const CircularProgressIndicator()
                          : _hasSearchedVideos
                          ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'No videos found',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadVideos,
                                child: const Text('Try Again'),
                              ),
                            ],
                          )
                          : ElevatedButton(
                            onPressed: _loadVideos,
                            child: const Text('Load Videos'),
                          ),
                )
                : ListView.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        leading: FutureBuilder<Uint8List?>(
                          future: _getThumbnail(video.id),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                width: 64,
                                height: 64,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (snapshot.hasData && snapshot.data != null) {
                              return Image.memory(
                                snapshot.data!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              );
                            }

                            return const SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(Icons.video_file),
                            );
                          },
                        ),
                        title: Text(video.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_formatDuration(video.duration)),
                            Text(
                              'Path: ${video.folderPath}',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Text(
                          '${(video.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                        ),
                        onTap: () {
                          // Show a dialog with video details including the path
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: Text(video.name),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Duration: ${_formatDuration(video.duration)}',
                                      ),
                                      Text(
                                        'Size: ${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                                      ),
                                      Text('MIME Type: ${video.mimeType}'),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Full Path:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        video.path,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Folder Path:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        video.folderPath,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'This path can be used to play the video with any video player plugin.',
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        // Copy path to clipboard
                                        Clipboard.setData(
                                          ClipboardData(text: video.path),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Video path copied to clipboard',
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text('Copy Path'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        // Navigate to the folder containing this video
                                        Navigator.pop(context);

                                        // Switch to the Folders tab
                                        _tabController.animateTo(
                                          2,
                                        ); // Index 2 is the Folders tab

                                        // Load folders if not already loaded
                                        if (_videoFolders.isEmpty &&
                                            !_isLoading) {
                                          _loadVideoFolders();
                                        }
                                      },
                                      child: const Text('Go to Folder'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                          );
                        },
                      ),
                    );
                  },
                ),

            // Music Tab
            _audios.isEmpty
                ? Center(
                  child:
                      _isLoading
                          ? const CircularProgressIndicator()
                          : _hasSearchedAudios
                          ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'No music found',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadAudios,
                                child: const Text('Try Again'),
                              ),
                            ],
                          )
                          : ElevatedButton(
                            onPressed: _loadAudios,
                            child: const Text('Load Music'),
                          ),
                )
                : ListView.builder(
                  itemCount: _audios.length,
                  itemBuilder: (context, index) {
                    final audio = _audios[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.music_note),
                        ),
                        title: Text(audio.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(audio.artist),
                            Text(audio.album),
                            Text(
                              'Path: ${audio.folderPath}',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Text(_formatDuration(audio.duration)),
                        onTap: () {
                          // Show a dialog with audio details including the path
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: Text(audio.name),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Artist: ${audio.artist}'),
                                      Text('Album: ${audio.album}'),
                                      Text(
                                        'Duration: ${_formatDuration(audio.duration)}',
                                      ),
                                      Text(
                                        'Size: ${(audio.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Full Path:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        audio.path,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Folder Path:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        audio.folderPath,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'This path can be used to play the audio with any audio player plugin.',
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        // Copy path to clipboard
                                        Clipboard.setData(
                                          ClipboardData(text: audio.path),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Audio path copied to clipboard',
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text('Copy Path'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                          );
                        },
                      ),
                    );
                  },
                ),

            // Folders Tab
            _videoFolders.isEmpty
                ? Center(
                  child:
                      _isLoading
                          ? const CircularProgressIndicator()
                          : _hasSearchedFolders
                          ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'No video folders found',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadVideoFolders,
                                child: const Text('Try Again'),
                              ),
                            ],
                          )
                          : ElevatedButton(
                            onPressed: _loadVideoFolders,
                            child: const Text('Load Video Folders'),
                          ),
                )
                : Builder(
                  builder: (context) {
                    // Sort folders by video count (descending)
                    final sortedFolders =
                        _videoFolders.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));

                    return ListView.builder(
                      itemCount: sortedFolders.length,
                      itemBuilder: (context, index) {
                        final folder = sortedFolders[index];
                        final folderName = folder.key.split('/').last;

                        return Card(
                          margin: const EdgeInsets.all(8.0),
                          child: ListTile(
                            leading: const Icon(Icons.folder, size: 48),
                            title: Text(folderName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${folder.value} videos'),
                                Text(
                                  folder.key,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            onTap: () async {
                              // Show loading dialog
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder:
                                    (context) => const AlertDialog(
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text('Loading videos from folder...'),
                                        ],
                                      ),
                                    ),
                              );

                              try {
                                // Get videos from this folder
                                final folderVideos =
                                    await _deviceMediaFinderPlugin
                                        .getVideosFromFolder(folder.key);

                                // Close loading dialog
                                if (context.mounted) Navigator.pop(context);

                                if (folderVideos.isEmpty) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No videos found in this folder',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                // Show videos in a dialog or navigate to a new screen
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: Text('Videos in $folderName'),
                                          content: SizedBox(
                                            width: double.maxFinite,
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: folderVideos.length,
                                              itemBuilder: (context, index) {
                                                final video =
                                                    folderVideos[index];
                                                return ListTile(
                                                  title: Text(video.name),
                                                  subtitle: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        _formatDuration(
                                                          video.duration,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Path: ${video.path}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                  trailing: Text(
                                                    '${(video.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                                  ),
                                                  onTap: () {
                                                    // Show a dialog with video details and playback options
                                                    showDialog(
                                                      context: context,
                                                      builder:
                                                          (
                                                            context,
                                                          ) => AlertDialog(
                                                            title: Text(
                                                              video.name,
                                                            ),
                                                            content: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  'Duration: ${_formatDuration(video.duration)}',
                                                                ),
                                                                Text(
                                                                  'Size: ${(video.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                                                                ),
                                                                Text(
                                                                  'MIME Type: ${video.mimeType}',
                                                                ),
                                                                const SizedBox(
                                                                  height: 8,
                                                                ),
                                                                const Text(
                                                                  'Full Path:',
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  video.path,
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            14,
                                                                      ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 16,
                                                                ),
                                                                const Text(
                                                                  'This path can be used to play the video with any video player plugin.',
                                                                ),
                                                              ],
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () {
                                                                  // Copy path to clipboard
                                                                  Clipboard.setData(
                                                                    ClipboardData(
                                                                      text:
                                                                          video
                                                                              .path,
                                                                    ),
                                                                  );
                                                                  ScaffoldMessenger.of(
                                                                    context,
                                                                  ).showSnackBar(
                                                                    const SnackBar(
                                                                      content: Text(
                                                                        'Video path copied to clipboard',
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                                child: const Text(
                                                                  'Copy Path',
                                                                ),
                                                              ),
                                                              TextButton(
                                                                onPressed:
                                                                    () => Navigator.pop(
                                                                      context,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'Close',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(context),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        ),
                                  );
                                }
                              } catch (e) {
                                // Close loading dialog
                                if (context.mounted) Navigator.pop(context);

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error loading videos: $e'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}
