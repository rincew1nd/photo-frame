import 'package:flutter/services.dart';
import 'package:photoframe/data/plugins/plugin_seeder.dart';

const int bundledExamplesVersion = 6;

const String clockPluginId = 'com.rincew1nd.photoframe.clock';
const String weatherPluginId = 'com.rincew1nd.photoframe.weather';
const String metadataPluginId = 'com.rincew1nd.photoframe.metadata';
const String calendarPluginId = 'com.rincew1nd.photoframe.calendar';
const String playbackPluginId = 'com.rincew1nd.photoframe.playback';
const String imageInfoPluginId = 'com.rincew1nd.photoframe.image-info';

const Map<String, bool> _enabledByDefault = <String, bool>{
  clockPluginId: true,
  weatherPluginId: true,
  metadataPluginId: true,
  calendarPluginId: false,
  playbackPluginId: false,
  imageInfoPluginId: false,
};

/// Loads the bundled example ZIPs from app assets.
Future<List<BundledPluginSource>> loadBundledExampleSources() async {
  final sources = <BundledPluginSource>[];
  for (final entry in _enabledByDefault.entries) {
    final name = _assetName(entry.key);
    final data = await rootBundle.load('assets/plugins/$name.zip');
    sources.add(
      BundledPluginSource(
        id: entry.key,
        zipBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        defaultEnabled: entry.value,
      ),
    );
  }
  return sources;
}

String _assetName(String id) {
  return switch (id) {
    clockPluginId => 'clock',
    weatherPluginId => 'weather',
    metadataPluginId => 'metadata',
    calendarPluginId => 'calendar',
    playbackPluginId => 'playback',
    imageInfoPluginId => 'image-info',
    _ => id.split('.').last,
  };
}
