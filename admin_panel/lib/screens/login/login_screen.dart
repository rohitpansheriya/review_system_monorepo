// lib/screens/login/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_animated_loader.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;
  String? _loginError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
      _loginError = null;
    });

    if (!_formKey.currentState!.validate()) {
      if (_emailCtrl.text.trim().isEmpty) {
        _emailFocus.requestFocus();
      } else if (_passwordCtrl.text.isEmpty) {
        _passwordFocus.requestFocus();
      }
      return;
    }

    final auth = context.read<AppAuthProvider>();
    final err  = await auth.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (err != null && mounted) {
      final errLower = err.toLowerCase();
      setState(() {
        _loginError = err;
        if (errLower.contains('password')) {
          _passwordError = err;
          _passwordFocus.requestFocus();
        } else if (errLower.contains('email') || errLower.contains('user') || errLower.contains('account')) {
          _emailError = err;
          _emailFocus.requestFocus();
        }
      });
    } else if (mounted) {
      if (auth.isAdmin) {
        context.go('/admin');
      } else if (auth.isOwner) {
        context.go('/owner');
      } else {
        context.go('/businesses');
      }
    }
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
                      'Review System Portal',
                      style: GoogleFonts.inter(
                        fontSize:   26,
                        fontWeight: FontWeight.w700,
                        color:      Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Employee & Business Owner Sign In',
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
                                  'Enter your credentials to continue.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: AppSpacing.lg),

                                // Access-denied or Login Error banner
                                if (auth.status == AuthStatus.accessDenied || _loginError != null) ...[
                                  _AlertBanner(
                                    icon:    Icons.error_outline,
                                    message: _loginError ?? auth.error ??
                                        'Access denied: this account does not have access to this portal.',
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
                                  focusNode:    _emailFocus,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText:   'Email address',
                                    prefixIcon:  const Icon(Icons.email_outlined),
                                    errorText:   _emailError,
                                  ),
                                  onChanged: (_) {
                                    if (_emailError != null || _loginError != null) {
                                      setState(() {
                                        _emailError = null;
                                        _loginError = null;
                                      });
                                    }
                                  },
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                                ),
                                const SizedBox(height: AppSpacing.md),

                                // Password
                                TextFormField(
                                  controller:  _passwordCtrl,
                                  focusNode:   _passwordFocus,
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText:  'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    errorText:  _passwordError,
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    if (_passwordError != null || _loginError != null) {
                                      setState(() {
                                        _passwordError = null;
                                        _loginError = null;
                                      });
                                    }
                                  },
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Password is required' : null,
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                                const SizedBox(height: 8),

                                // Forgot / Set Password action
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _showForgotPasswordDialog(context),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: Text(
                                      'Forgot or set password?',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),

                                // Sign in button
                                ElevatedButton(
                                  onPressed: auth.loading ? null : _submit,
                                  child: auth.loading
                                      ? AppAnimatedLoader.inline(
                                          size: 18,
                                          color: scheme.onPrimary,
                                        )
                                      : const Text('Sign in'),
                                ),

                                const SizedBox(height: AppSpacing.md),

                                // First-time business owner guidance banner
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            text: 'First time logging in as a Business Owner? ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: scheme.onSurface,
                                              height: 1.4,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'Use "Forgot or set password?" above to create your password. A setup link will be sent to your registered email address.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w400,
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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

  void _showForgotPasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ForgotPasswordDialog(
        initialEmail: _emailCtrl.text.trim(),
      ),
    );
  }
}

// ── Forgot / Set Password Dialog ──────────────────────────────────────────────
class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;

  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AppAuthProvider>();
    final err = await auth.sendPasswordResetEmail(_emailCtrl.text.trim());

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
    } else {
      setState(() {
        _loading = false;
        _sent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          const Text('Set / Reset Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: _sent
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.activeBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, color: AppColors.activeFg, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Password link sent to ${_emailCtrl.text.trim()}! Please check your inbox (and spam folder) to set or reset your password.',
                            style: const TextStyle(fontSize: 13, color: AppColors.activeFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your registered email address. We will send a secure link to create or reset your password.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: scheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Registered Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Email is required' : null,
                      onFieldSubmitted: (_) => _send(),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        if (_sent)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          )
        else ...[
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _loading ? null : _send,
            child: _loading
                ? const AppAnimatedLoader.inline(
                    size: 16,
                    color: Colors.white,
                  )
                : const Text('Send Link'),
          ),
        ],
      ],
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
