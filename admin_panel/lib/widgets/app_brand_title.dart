// lib/widgets/app_brand_title.dart
//
// Standard AppBar brand header featuring the AppNexa icon, company name,
// and screen/role context subtitle.

import 'package:flutter/material.dart';

class AppBrandTitle extends StatelessWidget {
  final String? subtitle;
  final Widget? trailing;

  const AppBrandTitle({
    super.key,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/appnexa-icon-white.png',
          height: 24,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        const Text(
          'AppNexa',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.3,
            color: Colors.white,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: Text(
              subtitle!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
        if (trailing != null) trailing!,
      ],
    );
  }
}
