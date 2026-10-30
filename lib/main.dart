import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:photoframe/app/app.dart';
import 'package:photoframe/app/bootstrap.dart';
import 'package:photoframe/app/providers.dart';
import 'package:photoframe/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  Bootstrap? bootstrap;
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      MediaKit.ensureInitialized();
      if (Platform.isWindows || Platform.isLinux) {
        await WindowManager.instance.ensureInitialized();
      }
      final instance = await Bootstrap.initialize();
      bootstrap = instance;
      runApp(
        ProviderScope(
          overrides: [
            bootstrapProvider.overrideWithValue(instance),
          ],
          child: const PhotoFrameApp(),
        ),
      );
    } on Object catch (error, stackTrace) {
      bootstrap?.logger.error(
        'Bootstrap failed',
        error: error,
        stackTrace: stackTrace,
      );
      runApp(const BootstrapErrorApp());
    }
  }, (error, stackTrace) {
    bootstrap?.logger.error(
      'Uncaught zone error',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(AppLocalizations.of(context).appName),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => exit(1),
                  child: Text(AppLocalizations.of(context).retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
