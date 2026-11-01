import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/plugins/bundled_examples.dart';
import 'package:photoframe/data/plugins/plugin_bundle.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled examples validate through the normal ZIP path', () async {
    final sources = await loadBundledExampleSources();
    expect(sources, hasLength(6));
    expect(
      sources.map((source) => source.id).toSet(),
      <String>{
        clockPluginId,
        weatherPluginId,
        metadataPluginId,
        calendarPluginId,
        playbackPluginId,
        imageInfoPluginId,
      },
    );

    final enabled = <String, bool>{
      for (final source in sources) source.id: source.defaultEnabled,
    };
    expect(enabled[clockPluginId], isTrue);
    expect(enabled[weatherPluginId], isTrue);
    expect(enabled[metadataPluginId], isTrue);
    expect(enabled[calendarPluginId], isFalse);
    expect(enabled[playbackPluginId], isFalse);
    expect(enabled[imageInfoPluginId], isFalse);

    final installed = <String>{};
    for (final source in sources) {
      final bundle = const PluginBundleValidator().validate(
        source.zipBytes,
        installedIds: installed,
        hostApiVersion: supportedPluginApiVersion,
        hostAppVersion: '2.0.0',
      );
      expect(bundle.manifest.id, source.id);
      final settings = bundle.manifest.settings
          .map((field) => field.key)
          .toSet();
      expect(
        settings,
        containsAll(<String>[
          'backgroundColor',
          'backgroundOpacity',
          'cornerRadius',
        ]),
        reason: source.id,
      );
      if (source.id == playbackPluginId) {
        expect(bundle.manifest.inputs, contains(PluginInput.media));
        expect(
          bundle.manifest.actions,
          containsAll(<PluginAction>[
            PluginAction.mediaPrevious,
            PluginAction.mediaPlayPause,
            PluginAction.mediaNext,
          ]),
        );
      }
      installed.add(bundle.manifest.id);
    }
  });
}
