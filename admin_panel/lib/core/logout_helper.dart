// lib/core/logout_helper.dart
//
// Shared logout helper function with confirmation dialog gate.
// Ensures every logout entry point in the employee panel routes through
// a consistent, themed confirmation dialog before performing sign-out.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Shows a themed confirmation dialog ("Log out?") before signing out.
///
/// Returns true if the user explicitly confirmed and signed out,
/// or false if cancelled / dismissed.
Future<bool> confirmAndSignOut(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await context.read<AppAuthProvider>().signOut();
    return true;
  }
  return false;
}
