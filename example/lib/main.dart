import 'package:device_media_finder/device_media_finder.dart';
import 'package:flutter/material.dart';

import 'optimized_media_tab.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Device Media Finder',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _finder = DeviceMediaFinder();

  bool _checking = true;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    setState(() => _checking = true);
    var granted = await _finder.hasStoragePermission();
    if (!granted) granted = await _finder.requestStoragePermission();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Media Finder')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Media permission is required'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _ensurePermission,
                child: const Text('Grant permission'),
              ),
              TextButton(
                onPressed: _finder.openAllFilesAccessSettings,
                child: const Text('Open "All files access" settings'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device Media Finder'),
          actions: [
            IconButton(
              tooltip: 'Clear thumbnail cache',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await _finder.clearThumbnailCache();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Thumbnail cache cleared')),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.video_library), text: 'Videos'),
              Tab(icon: Icon(Icons.library_music), text: 'Audio'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OptimizedMediaTab(
              mediaManager: _finder,
              mediaType: MediaType.video,
            ),
            OptimizedMediaTab(
              mediaManager: _finder,
              mediaType: MediaType.audio,
            ),
          ],
        ),
      ),
    );
  }
}
