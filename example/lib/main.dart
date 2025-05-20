import 'dart:async';

import 'package:device_media_finder/device_media_finder.dart';
import 'package:device_media_finder/models/media_file.dart';
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
  bool _isLoading = false;
  bool _hasSearchedVideos = false;
  bool _hasSearchedAudios = false;
  late TabController _tabController;

  final Map<String, Uint8List?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    initPlatformState();
  }

  @override
  void dispose() {
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
                        subtitle: Text(_formatDuration(video.duration)),
                        trailing: Text(
                          '${(video.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                        ),
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
                          children: [Text(audio.artist), Text(audio.album)],
                        ),
                        trailing: Text(_formatDuration(audio.duration)),
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}
