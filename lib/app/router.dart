import 'package:go_router/go_router.dart';
import 'package:photoframe/features/albums/albums_screen.dart';
import 'package:photoframe/features/media_selection/media_selection_screen.dart';
import 'package:photoframe/features/settings/about_settings_screen.dart';
import 'package:photoframe/features/settings/automation_settings_screen.dart';
import 'package:photoframe/features/settings/cache_settings_screen.dart';
import 'package:photoframe/features/settings/connection_settings_screen.dart';
import 'package:photoframe/features/settings/customizations_screen.dart';
import 'package:photoframe/features/settings/playback_settings_screen.dart';
import 'package:photoframe/features/settings/plugin_settings_screen.dart';
import 'package:photoframe/features/settings/plugins_settings_screen.dart';
import 'package:photoframe/features/settings/settings_shell.dart';
import 'package:photoframe/features/settings/slideshow_settings_screen.dart';
import 'package:photoframe/features/setup/setup_screen.dart';
import 'package:photoframe/features/slideshow/slideshow_screen.dart';

GoRouter createAppRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/albums',
        builder: (context, state) => const AlbumsScreen(),
      ),
      GoRoute(
        path: '/slideshow',
        builder: (context, state) => const SlideshowScreen(),
      ),
      GoRoute(
        path: '/media-selection',
        builder: (context, state) => const MediaSelectionScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsShell(),
        routes: <RouteBase>[
          GoRoute(
            path: 'connection',
            builder: (context, state) => const ConnectionSettingsScreen(),
          ),
          GoRoute(
            path: 'cache',
            builder: (context, state) => const CacheSettingsScreen(),
          ),
          GoRoute(
            path: 'playback',
            builder: (context, state) => const PlaybackSettingsScreen(),
          ),
          GoRoute(
            path: 'slideshow',
            builder: (context, state) => const SlideshowSettingsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'customizations',
                builder: (context, state) => const CustomizationsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => CustomizationEditorScreen(
                      customizationId: state.pathParameters['id'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'plugins',
            builder: (context, state) => const PluginsSettingsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (context, state) => PluginSettingsScreen(
                  pluginId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'automation',
            builder: (context, state) => const AutomationSettingsScreen(),
          ),
          GoRoute(
            path: 'about',
            builder: (context, state) => const AboutSettingsScreen(),
          ),
        ],
      ),
    ],
  );
}
