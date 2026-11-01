import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/data/settings/app_settings.dart';

class DisplayModeController extends ConsumerStatefulWidget {
  const DisplayModeController({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DisplayModeController> createState() =>
      _DisplayModeControllerState();
}

class _DisplayModeControllerState extends ConsumerState<DisplayModeController> {
  bool? _fullscreen;
  bool? _keepAwake;
  bool? _startOnBoot;
  bool _kiosk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsControllerProvider, (previous, next) {
      _sync(next.value);
    });
    return widget.child;
  }

  Future<void> _sync([AppSettings? settings]) async {
    final value = settings ?? ref.read(settingsControllerProvider).value;
    if (value == null) {
      return;
    }
    final platform = ref.read(platformServicesProvider);
    final effectiveFullscreen =
        value.automation.fullscreen || value.automation.kiosk;
    if (_fullscreen != effectiveFullscreen) {
      _fullscreen = effectiveFullscreen;
      try {
        if (effectiveFullscreen) {
          await platform.fullscreen.enable();
        } else {
          await platform.fullscreen.disable();
        }
      } on Object {
        // Ignore a missing platform plugin instead of crashing the app.
      }
    }
    if (_kiosk != value.automation.kiosk) {
      _kiosk = value.automation.kiosk;
      try {
        if (value.automation.kiosk) {
          await platform.kiosk.enable();
        } else {
          await platform.kiosk.disable();
        }
      } on Object {
        // Ignore a missing platform plugin instead of crashing the app.
      }
    }
    if (_keepAwake != value.display.keepScreenOn) {
      _keepAwake = value.display.keepScreenOn;
      try {
        if (value.display.keepScreenOn) {
          await platform.keepAwake.enable();
        } else {
          await platform.keepAwake.disable();
        }
      } on Object {
        // Ignore a missing platform plugin instead of crashing the app.
      }
    }
    if (_startOnBoot != value.automation.startOnBoot) {
      _startOnBoot = value.automation.startOnBoot;
      try {
        await platform.autostart.setEnabled(value.automation.startOnBoot);
      } on Object {
        // Ignore a missing platform plugin instead of crashing the app.
      }
    }
  }
}
