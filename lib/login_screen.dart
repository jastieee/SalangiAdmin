import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db/DBResult.dart';
import 'screens/dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ── Brand palette ──────────────────────────────────────────────
  static const Color kPurple     = Color(0xFF6A3FA0);
  static const Color kPurpleDark = Color(0xFF4E2D78);
  static const Color kPurpleSoft = Color(0xFF8A5FC0);
  static const Color kGold       = Color(0xFFF5A623);
  static const Color kGoldDark   = Color(0xFFD48A10);
  static const Color kWhite      = Colors.white;
  // ──────────────────────────────────────────────────────────────

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool get isWindows {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final result = await DBService.instance.login(
      username: username,
      password: password,
    );

    if (result.success) {
      print('=== RAW result.data ===');
      print(result.data);
      print('=== admin_modules ===');
      print(result.data?['admin_modules']);
      print('=== user key (if nested) ===');
      print(result.data?['user']);
      // ── Admin guard ───────────────────────────────────────
      final adminModules = List<Map<String, dynamic>>.from(
        result.data?['admin_modules'] ?? [],
      );

      final accessibleAdminModules = adminModules.where((m) {
        return m['can_access'] == true || m['can_access'] == 1;
      }).toList();

      result.data?['accessible_admin_modules'] = accessibleAdminModules;
      // ─────────────────────────────────────────────────────

      if (mounted) {
        final displayName = result.data?['full_name'] ?? username;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, $displayName!'),
            backgroundColor: kPurple,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardScreen(user: result.data),
          ),
        );
      }
    } else {
      setState(() {
        _errorMessage = result.message;
      });
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Light, brand-tinted background
      backgroundColor: const Color(0xFFF6F2FB),
      // resizeToAvoidBottomInset lets the keyboard push content rather than overflow
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Decorative gradient blobs ──────────────────────────
          Positioned(
            top: -100,
            left: -100,
            child: _GlowBlob(
              color: kPurple.withOpacity(0.22),
              size: 340,
            ),
          ),
          Positioned(
            bottom: -90,
            right: -90,
            child: _GlowBlob(
              color: kGold.withOpacity(0.20),
              size: 300,
            ),
          ),
          Positioned(
            top: 120,
            right: -40,
            child: _GlowBlob(
              color: kPurpleSoft.withOpacity(0.12),
              size: 160,
            ),
          ),

          // ── Main content ───────────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  // Avoid overflow on small screens & when keyboard opens
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Center(
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: _buildLoginCard(context, constraints),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context, BoxConstraints constraints) {
    final screenW = MediaQuery.of(context).size.width;

    // Responsive card width:
    // - Windows / wide desktop: 440 px fixed
    // - Tablet: 480 px max
    // - Mobile: 92% of width, capped at 420
    final double cardWidth = isWindows
        ? 440.0
        : screenW >= 700
        ? 480.0
        : (screenW * 0.92).clamp(280.0, 420.0);

    // Tighter padding on small phones
    final bool isCompact = screenW < 360;
    final EdgeInsets cardPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 24 : 32,
      vertical: isCompact ? 32 : 40,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: cardWidth,
        padding: cardPadding,
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kPurple.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: kPurple.withOpacity(0.18),
              blurRadius: 40,
              spreadRadius: 0,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo / Icon Badge ────────────────────────────
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kPurple, kPurpleDark],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: kPurple.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: kWhite,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── Title ─────────────────────────────────────────
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kPurpleDark,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Sign in to your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kPurpleDark.withOpacity(0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Username field ───────────────────────────────
              const _FieldLabel(label: 'Username'),
              const SizedBox(height: 8),
              _StyledTextField(
                controller: _usernameController,
                hintText: 'Enter your username',
                prefixIcon: Icons.person_outline_rounded,
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Username is required' : null,
              ),
              const SizedBox(height: 18),

              // ── Password field ───────────────────────────────
              const _FieldLabel(label: 'Password'),
              const SizedBox(height: 8),
              _StyledTextField(
                controller: _passwordController,
                hintText: 'Enter your password',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: kPurple.withOpacity(0.55),
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
                onFieldSubmitted: (_) => _handleLogin(),
              ),

              // ── Error message ────────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFD93025),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFD93025),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── Sign-in button ───────────────────────────────
              SizedBox(
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _isLoading
                        ? null
                        : const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [kPurple, kPurpleDark],
                    ),
                    color: _isLoading ? kPurple.withOpacity(0.5) : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _isLoading
                        ? []
                        : [
                      BoxShadow(
                        color: kPurple.withOpacity(0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: kWhite,
                      disabledBackgroundColor: Colors.transparent,
                      disabledForegroundColor: kWhite.withOpacity(0.85),
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kWhite,
                      ),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: kGold,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: kPurpleDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Footer accent ────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: kGoldDark.withOpacity(0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Secure access',
                      style: TextStyle(
                        color: kPurpleDark.withOpacity(0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Helper Widgets
// ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _LoginScreenState.kPurpleDark,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _StyledTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    const purple     = _LoginScreenState.kPurple;
    const purpleDark = _LoginScreenState.kPurpleDark;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: purpleDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: purple,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: purpleDark.withOpacity(0.35),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(
          prefixIcon,
          color: purple.withOpacity(0.6),
          size: 20,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8F5FC),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: purple.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: purple.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD93025)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD93025),
            width: 1.5,
          ),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFD93025),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}