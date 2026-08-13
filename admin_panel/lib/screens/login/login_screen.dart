// lib/screens/login/login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AppAuthProvider>();
    final err  = await auth.signIn(_emailCtrl.text, _passwordCtrl.text);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    // On success, GoRouter redirect handles navigation.
  }

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AppAuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final size   = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: size.height, minWidth: size.width),
          child: Column(
            children: [
              // ── Branded gradient hero strip ─────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.reviews_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Review System',
                      style: GoogleFonts.inter(
                        fontSize:   26,
                        fontWeight: FontWeight.w700,
                        color:      Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Employee & Admin Panel',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color:    Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Login card ───────────────────────────────────────────────
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    child: Transform.translate(
                      offset: const Offset(0, -28),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg + 8),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize:        MainAxisSize.min,
                              crossAxisAlignment:  CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Sign in',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enter your employee credentials to continue.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: AppSpacing.lg),

                                // Access-denied banner
                                if (auth.status == AuthStatus.accessDenied) ...[
                                  _AlertBanner(
                                    icon:    Icons.lock_outline,
                                    message: auth.error ??
                                        'Access denied: this account does not have employee or admin access.',
                                    backgroundColor: scheme.errorContainer,
                                    borderColor:     scheme.error.withValues(alpha: 0.3),
                                    iconColor:       scheme.error,
                                    textColor:       scheme.onErrorContainer,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                ],

                                // Email
                                TextFormField(
                                  controller:   _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText:   'Email address',
                                    prefixIcon:  Icon(Icons.email_outlined),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                                ),
                                const SizedBox(height: AppSpacing.md),

                                // Password
                                TextFormField(
                                  controller:  _passwordCtrl,
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText:  'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Password is required' : null,
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                                const SizedBox(height: AppSpacing.xl - 4),

                                // Sign in button
                                ElevatedButton(
                                  onPressed: auth.loading ? null : _submit,
                                  child: auth.loading
                                      ? SizedBox(
                                          height: 18, width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: scheme.onPrimary,
                                          ),
                                        )
                                      : const Text('Sign in'),
                                ),

                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'Credentials are created by an admin.\nContact your admin if you cannot sign in.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared alert banner ───────────────────────────────────────────────────────
class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final String   message;
  final Color    backgroundColor;
  final Color    borderColor;
  final Color    iconColor;
  final Color    textColor;

  const _AlertBanner({
    required this.icon,
    required this.message,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        backgroundColor,
      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      border:       Border.all(color: borderColor),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
