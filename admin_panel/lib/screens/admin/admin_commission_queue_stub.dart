// lib/screens/admin/admin_commission_queue_stub.dart
//
// LEGACY STUB — now redirects to the fully built AdminCommissionQueueScreen.
// Kept for backward compatibility with any routes that reference this class.

import 'package:flutter/material.dart';
import 'admin_commission_queue_screen.dart';

class AdminCommissionQueueStubScreen extends StatelessWidget {
  const AdminCommissionQueueStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Delegate to the fully built screen
    return const AdminCommissionQueueScreen();
  }
}
