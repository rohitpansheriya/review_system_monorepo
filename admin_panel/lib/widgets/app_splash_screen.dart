// lib/widgets/app_splash_screen.dart
//
// Seamless dark splash screen displayed while Flutter engine & Firebase Auth
// session are initialising. Matches index.html style to eliminate any white flash
// or "Access Denied" role-check flickers on page refresh.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_animated_loader.dart';

class AppSplashScreen extends StatelessWidget {
  final String message;
  const AppSplashScreen({super.key, this.message = 'Loading AppNexa…'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppAnimatedLoader(
              variant: AppLoaderVariant.card,
              size: 56,
              color: Color(0xFF4F46E5),
              secondaryColor: Color(0xFF06B6D4),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
