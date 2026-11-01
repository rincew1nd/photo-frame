import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/data/plugins/plugin_manifest.dart';

import 'plugin_test_support.dart';

void main() {
  group('PluginManifest', () {
    test('parses a full manifest', () {
      final manifest = PluginManifest.fromJson(
        sampleManifest(
          icon: 'icon.png',
          screenshots: <String>['screenshots/clock.png'],
          inputs: <Object?>['time', 'config', 'weather'],
          actions: <String>['next', 'pause'],
          updateTriggers: <String>['timeTick', 'imageChange'],
          placement: <String, dynamic>{
            'anchor': 'top-start',
            'x': 0.05,
            'y': 0.25,
            'width': 320,
            'height': 160,
            'zOrder': 10,
            'showDuringNight': true,
          },
          settings: <String, dynamic>{
            'text': <String, dynamic>{
              'type': 'text',
              'label': 'Text',
              'default': 'hello',
              'help': 'Some help.',
              'maxLength': 10,
              'pattern': r'^[a-z]+$',
            },
            'multiline': <String, dynamic>{
              'type': 'multiline',
              'label': 'Multiline',
              'default': 'a\nb',
              'rows': 3,
            },
            'number': <String, dynamic>{
              'type': 'number',
              'label': 'Number',
              'default': 0.4,
              'min': 0,
              'max': 1,
              'step': 0.05,
            },
            'boolean': <String, dynamic>{
              'type': 'boolean',
              'label': 'Boolean',
              'default': true,
            },
            'select': <String, dynamic>{
              'type': 'select',
              'label': 'Select',
              'default': '24h',
              'options': <Map<String, String>>[
                <String, String>{'value': '24h', 'label': '24-hour'},
                <String, String>{'value': '12h', 'label': '12-hour'},
              ],
            },
            'color': <String, dynamic>{
              'type': 'color',
              'label': 'Color',
              'default': '#FFFFFFFF',
            },
            'url': <String, dynamic>{
              'type': 'url',
              'label': 'URL',
              'default': 'https://example.com',
              'pattern': '^https://',
            },
          },
        ),
      );

      expect(manifest.id, 'com.example.test');
      expect(manifest.version.value, '1.0.0');
      expect(manifest.minAppVersion.value, '1.0.0');
      expect(manifest.apiVersion, 1);
      expect(manifest.entry, 'index.html');
      expect(manifest.icon, 'icon.png');
      expect(manifest.screenshots, <String>{'screenshots/clock.png'});
      expect(manifest.permissions.network, isFalse);
      expect(
        manifest.inputs,
        <PluginInput>{PluginInput.time, PluginInput.config, PluginInput.weather},
      );
      expect(
        manifest.actions,
        <PluginAction>{PluginAction.next, PluginAction.pause},
      );
      expect(manifest.updateTriggers, <String>{'timeTick', 'imageChange'});
      expect(manifest.placement?.anchor, PluginAnchor.topStart);
      expect(manifest.placement?.x, 0.05);
      expect(manifest.placement?.y, 0.25);
      expect(manifest.placement?.width, 320);
      expect(manifest.placement?.height, 160);
      expect(manifest.placement?.zOrder, 10);
      expect(manifest.placement?.showDuringNight, isTrue);
      expect(manifest.settings, hasLength(7));

      final number = manifest.settings.firstWhere(
        (field) => field.key == 'number',
      );
      expect(number.type, PluginSettingType.number);
      expect(number.defaultValue, 0.4);
      expect(number.min, 0);
      expect(number.max, 1);
      expect(number.step, 0.05);

      final select = manifest.settings.firstWhere(
        (field) => field.key == 'select',
      );
      expect(select.options, hasLength(2));
      expect(select.options.first.value, '24h');
    });

    test('allows omitted inputs and updateTriggers', () {
      final manifest = PluginManifest.fromJson(sampleManifest());

      expect(manifest.inputs, isEmpty);
      expect(manifest.updateTriggers, isEmpty);
      expect(manifest.actions, isEmpty);
      expect(manifest.screenshots, isEmpty);
      expect(manifest.icon, isNull);
      expect(manifest.placement, isNull);
      expect(manifest.settings, isEmpty);
    });

    test('rejects unknown inputs', () {
      expect(
        () => PluginManifest.fromJson(
          sampleManifest(inputs: <Object?>['secrets']),
        ),
        throwsA(
          isA<PluginValidationException>().having(
            (error) => error.message,
            'message',
            contains('Unknown input'),
          ),
        ),
      );
    });

    test('rejects invalid path-like ids', () {
      for (final id in <String>[
        '',
        'clock',
        '../evil',
        'com.example/evil',
        '.com.example',
        'com..example',
        'com.example.',
        'com.example evil',
      ]) {
        expect(
          () => PluginManifest.fromJson(sampleManifest(id: id)),
          throwsA(isA<PluginValidationException>()),
          reason: 'id "$id" should be rejected',
        );
      }
    });

    test('rejects invalid semantic versions', () {
      expect(
        () => PluginManifest.fromJson(sampleManifest(version: '1.0')),
        throwsA(isA<PluginValidationException>()),
      );
      expect(
        () => PluginManifest.fromJson(
          sampleManifest(minAppVersion: 'v1.0.0'),
        ),
        throwsA(isA<PluginValidationException>()),
      );
    });

    test('validates placement', () {
      final invalidPlacements = <Map<String, dynamic>>[
        <String, dynamic>{'anchor': 'top-left', 'width': 10, 'height': 10},
        <String, dynamic>{'x': 1.5, 'width': 10, 'height': 10},
        <String, dynamic>{'y': -0.1, 'width': 10, 'height': 10},
        <String, dynamic>{'width': 0, 'height': 10},
        <String, dynamic>{'width': 10, 'height': -1},
        <String, dynamic>{'width': 10, 'height': 10, 'zOrder': 1.5},
        <String, dynamic>{
          'width': 10,
          'height': 10,
          'showDuringNight': 'yes',
        },
      ];

      for (final placement in invalidPlacements) {
        expect(
          () => PluginManifest.fromJson(
            sampleManifest(placement: placement),
          ),
          throwsA(isA<PluginValidationException>()),
          reason: 'placement $placement should be rejected',
        );
      }
    });

    test('validates the settings schema', () {
      final invalidSettings = <Map<String, dynamic>>[
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'range',
            'label': 'Range',
            'default': 1,
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{'type': 'text', 'label': 'Text'},
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'boolean',
            'label': 'Boolean',
            'default': 'true',
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'number',
            'label': 'Number',
            'default': 5,
            'min': 0,
            'max': 1,
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'number',
            'label': 'Number',
            'default': 0,
            'min': 2,
            'max': 1,
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'select',
            'label': 'Select',
            'default': 'missing',
            'options': <Map<String, String>>[
              <String, String>{'value': 'a', 'label': 'A'},
            ],
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'color',
            'label': 'Color',
            'default': 'red',
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'url',
            'label': 'URL',
            'default': 'not a url',
          },
        },
        <String, dynamic>{
          'field': <String, dynamic>{
            'type': 'text',
            'label': 'Text',
            'default': 'hello',
            'pattern': '[',
          },
        },
      ];

      for (final settings in invalidSettings) {
        expect(
          () => PluginManifest.fromJson(
            sampleManifest(settings: settings),
          ),
          throwsA(isA<PluginValidationException>()),
          reason: 'settings $settings should be rejected',
        );
      }
    });

    test('reports compatibility', () {
      final manifest = PluginManifest.fromJson(
        sampleManifest(minAppVersion: '1.2.0'),
      );

      expect(
        manifest.isCompatible(
          hostApiVersion: supportedPluginApiVersion,
          hostAppVersion: '1.2.0',
        ),
        isTrue,
      );
      expect(
        manifest.isCompatible(
          hostApiVersion: supportedPluginApiVersion,
          hostAppVersion: '1.1.9',
        ),
        isFalse,
      );
      expect(
        manifest.isCompatible(hostApiVersion: 2, hostAppVersion: '2.0.0'),
        isFalse,
      );
      expect(
        manifest.compatibilityIssue(
          hostApiVersion: supportedPluginApiVersion,
          hostAppVersion: '1.1.9',
        ),
        contains('requires app version'),
      );

      final futureApi = PluginManifest.fromJson(
        sampleManifest(apiVersion: 2),
      );
      expect(
        futureApi.isCompatible(
          hostApiVersion: supportedPluginApiVersion,
          hostAppVersion: '2.0.0',
        ),
        isFalse,
      );
    });
  });
}
