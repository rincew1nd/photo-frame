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
    if (_fullscreen != value.automation.fullscreen) {
      _fullscreen = value.automation.fullscreen;
      try {
        if (value.automation.fullscreen) {
          await platform.fullscreen.enable();
        } else {
          await platform.fullscreen.disable();
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
  }
}
