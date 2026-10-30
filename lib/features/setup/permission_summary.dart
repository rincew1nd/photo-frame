import 'package:flutter/material.dart';
import 'package:photoframe/data/immich/models.dart';
import 'package:photoframe/l10n/app_localizations.dart';

class PermissionSummary extends StatelessWidget {
  const PermissionSummary({super.key, required this.report});

  final PermissionReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.permissions, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final permission in ImmichPermission.apiKeyDefaults)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _icon(report.statusOf(permission)),
                      color: _color(theme, report.statusOf(permission)),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(permission.jsonName)),
                    Text(_statusLabel(l, report.statusOf(permission))),
                  ],
                ),
              ),
            if (report.statusOf(ImmichPermission.assetDownload) ==
                PermissionStatus.denied) ...[
              const SizedBox(height: 8),
              Text(
                l.videosUnavailable,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _icon(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted => Icons.check_circle_outline,
      PermissionStatus.denied => Icons.block,
      PermissionStatus.error => Icons.error_outline,
      PermissionStatus.notTested => Icons.help_outline,
    };
  }

  Color _color(ThemeData theme, PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted => Colors.green,
      PermissionStatus.denied => theme.colorScheme.error,
      PermissionStatus.error => theme.colorScheme.error,
      PermissionStatus.notTested => theme.colorScheme.outline,
    };
  }

  String _statusLabel(AppLocalizations l, PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted => l.granted,
      PermissionStatus.denied => l.denied,
      PermissionStatus.error => l.errorLabel,
      PermissionStatus.notTested => l.notTested,
    };
  }
}
