import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../onboarding/add_account.dart';

/// Surfaces account problems that need the user: revoked access and
/// long-running sync failures.
class StatusBanner extends ConsumerWidget {
  const StatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final reauth = accounts.where((a) => a.status == AccountStatus.needsReauth).toList();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedSize(
      duration: Spring.standard.duration,
      curve: Spring.standard.curve,
      child: reauth.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(96, 8, 16, 0),
              child: Material(
                color: scheme.errorContainer,
                shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(Symbols.key_off_rounded, color: scheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reauth.length == 1
                              ? 'Plume lost access to ${reauth.first.email}. Sign in again to keep getting mail.'
                              : 'Plume lost access to ${reauth.length} accounts. Sign in again to keep getting mail.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                      for (final account in reauth)
                        TextButton(
                          onPressed: () => signInAgain(context, ref, account),
                          child: Text(reauth.length == 1 ? 'Sign in' : 'Sign in to ${account.email}'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
