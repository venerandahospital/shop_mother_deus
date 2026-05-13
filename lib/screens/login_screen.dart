import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/subscription_service.dart';
import '../navigation/app_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _rememberedEmailKey = 'rememberedLoginEmail';
  static const String _rememberPasswordKey = 'rememberLoginPassword';
  static const String _rememberedPasswordKey = 'rememberedLoginPassword';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _db = LocalDbService.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showError = false;
  String _errorMessage = 'Email or password incorrect. Please try again.';
  bool _emailDirty = false;
  bool _passwordDirty = false;
  bool _rememberPassword = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = (prefs.getString(_rememberedEmailKey) ?? '').trim();
    final rememberPassword = prefs.getBool(_rememberPasswordKey) ?? false;
    final rememberedPassword = rememberPassword
        ? (prefs.getString(_rememberedPasswordKey) ?? '')
        : '';
    if (!mounted) return;
    setState(() {
      _emailController.text = rememberedEmail;
      _rememberPassword = rememberPassword;
      _passwordController.text = rememberedPassword;
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedEmailKey, _emailController.text.trim());
    await prefs.setBool(_rememberPasswordKey, _rememberPassword);
    if (_rememberPassword) {
      await prefs.setString(_rememberedPasswordKey, _passwordController.text);
    } else {
      await prefs.remove(_rememberedPasswordKey);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _emailDirty = true;
        _passwordDirty = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = 'Email or password incorrect. Please try again.';
    });

    final result = await _authService.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true && mounted) {
      await _persistRememberedCredentials();
      if (!mounted) return;
      final userType = (result['userType'] ?? '').toString().toUpperCase();
      if (userType == 'REMOTE') {
        // Same shell as mother: bottom nav + dashboard tab (child has no Settings tab).
        Navigator.of(context).pushReplacementNamed(AppRouter.main);
        return;
      }
      final hasBusiness = await _db.hasBusinessProfile();
      if (!mounted) return;
      if (!hasBusiness) {
        Navigator.of(context).pushReplacementNamed(AppRouter.businessSetup);
        return;
      }
      final status = await SubscriptionService.instance.getStatus();
      if (!mounted) return;
      if (status.expired) {
        Navigator.of(context).pushReplacementNamed(AppRouter.subscriptionActivation);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRouter.main);
      }
    } else {
      setState(() {
        _showError = true;
        _errorMessage =
            (result['message'] ?? 'Email or password incorrect. Please try again.')
                .toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final isSmallHeight = MediaQuery.of(context).size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: [
                  SizedBox(
                    height: isSmallHeight ? 110 : 150,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/dashboard_hero.png',
                          fit: BoxFit.cover,
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x1A000000),
                                Color(0x80000000),
                              ],
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 22,
                          right: 22,
                          bottom: 12,
                          child: Text(
                            'Run your shop smarter',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            22,
                            20,
                            22,
                            20 + viewInsets,
                          ),
                          children: [
                            const Text(
                              'Welcome',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Sign in to continue',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildEmailField(),
                            _buildPasswordField(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _rememberPassword = !_rememberPassword;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 2,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Checkbox(
                                              value: _rememberPassword,
                                              onChanged: (v) {
                                                setState(() {
                                                  _rememberPassword = v ?? false;
                                                });
                                              },
                                              visualDensity: VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            const SizedBox(width: 2),
                                            const Text(
                                              'Remember password',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed(AppRouter.forgotPassword);
                                  },
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            if (_showError && !_isLoading)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _errorMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        Navigator.of(context).pushReplacementNamed(
                                          AppRouter.preLoginRestore,
                                        );
                                      },
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('Restore backup'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: const [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    'Or continue with',
                                    style: TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _socialButton(
                                    icon: const Icon(
                                      Icons.facebook_rounded,
                                      size: 20,
                                      color: Color(0xFF1877F2),
                                    ),
                                    label: 'Facebook',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _socialButton(
                                    icon: const _GoogleLogoIcon(size: 20),
                                    label: 'Google',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'No account yet? ',
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pushReplacementNamed(
                                      AppRouter.signup,
                                    );
                                  },
                                  child: const Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

            final centered = Center(
              child: Padding(
                padding: kIsWeb
                    ? const EdgeInsets.symmetric(horizontal: 20, vertical: 14)
                    : EdgeInsets.zero,
                child: content,
              ),
            );

            return centered;
          },
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    final emailError = _emailDirty
        ? (_emailController.text.isEmpty
              ? '*Email is required'
              : (!RegExp(
                  r'^[^@]+@[^@]+\.[^@]+',
                ).hasMatch(_emailController.text))
              ? '*Please enter a valid email'
              : null)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '*Email is required';
            }
            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
              return '*Please enter a valid email';
            }
            return null;
          },
          onChanged: (_) {
            setState(() {
              _emailDirty = true;
            });
          },
          style: const TextStyle(fontSize: 15, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
            ),
            prefixIcon:
                const Icon(Icons.email_outlined, color: Color(0xFF6B7280)),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.4),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        if (emailError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              emailError,
              style: const TextStyle(color: Color(0xFFdc3545), fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildPasswordField() {
    final passwordError = _passwordDirty && _passwordController.text.isEmpty
        ? '*Password is required'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '*Password is required';
            }
            return null;
          },
          onChanged: (_) {
            setState(() {
              _passwordDirty = true;
            });
          },
          style: const TextStyle(fontSize: 15, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
            ),
            prefixIcon:
                const Icon(Icons.lock_outline, color: Color(0xFF6B7280)),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: const Color(0xFF6B7280),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.4),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        if (passwordError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              passwordError,
              style: const TextStyle(color: Color(0xFFdc3545), fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _socialButton({required Widget icon, required String label}) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: icon,
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF374151),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      ),
    );
  }
}

class _GoogleLogoIcon extends StatelessWidget {
  final double size;

  const _GoogleLogoIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    ringPaint.color = const Color(0xFFEA4335); // Red
    canvas.drawArc(rect, -0.15, 1.52, false, ringPaint);

    ringPaint.color = const Color(0xFFFBBC05); // Yellow
    canvas.drawArc(rect, 1.37, 1.05, false, ringPaint);

    ringPaint.color = const Color(0xFF34A853); // Green
    canvas.drawArc(rect, 2.42, 1.18, false, ringPaint);

    ringPaint.color = const Color(0xFF4285F4); // Blue
    canvas.drawArc(rect, 3.60, 1.55, false, ringPaint);

    final barPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4285F4);

    final y = center.dy;
    canvas.drawLine(
      Offset(center.dx + radius * 0.06, y),
      Offset(center.dx + radius * 0.80, y),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
