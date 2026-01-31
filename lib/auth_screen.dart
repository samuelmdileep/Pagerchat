import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'verify_email_screen.dart';
import 'reset_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool showPassword = false;
  String error = "";

  late AnimationController _logoController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    // 🔄 Logo pulse animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // ❌ Error shake animation
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeAnim = Tween<double>(begin: 0, end: 16).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _shakeController.dispose();
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      error = "";
      isLoading = true;
    });

    try {
      if (isLogin) {
        await AuthService.login(
          _idCtrl.text.trim(),
          _passCtrl.text.trim(),
        );
      } else {
        await AuthService.signUp(
          _idCtrl.text.trim(),
          _passCtrl.text.trim(),
        );

        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        );
      }
    }catch (e) {
  _shakeController.forward(from: 0);

  _passCtrl.clear(); // ✅ clear only on error

  if (e.toString().contains('EMAIL_NOT_VERIFIED')) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
    );
  } else if (e.toString().contains('INVALID_PAGER_ID')) {
    setState(() => error = "Pager ID does not exist.");
  } else {
    setState(() => error = e.toString());
  }
} finally {
  setState(() => isLoading = false);
}
  }

  InputDecoration _inputDecoration(String hint,
      {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.green),
      filled: true,
      fillColor: Colors.black,
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.green),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(error.isNotEmpty ? _shakeAnim.value : 0, 0),
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(22),
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🔰 Animated Logo
                  FadeTransition(
                    opacity: Tween(begin: 0.6, end: 1.0)
                        .animate(_logoController),
                    child: const Text(
                      "PAGER",
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 28,
                        letterSpacing: 4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  Text(
                    isLogin ? "SECURE LOGIN" : "CREATE ACCOUNT",
                    style: TextStyle(
                      color: Colors.greenAccent.withOpacity(0.7),
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ID FIELD
                  TextField(
                    controller: _idCtrl,
                    style: const TextStyle(color: Colors.greenAccent),
                    decoration: _inputDecoration(
                      isLogin ? "EMAIL or PAGER ID" : "EMAIL",
                    ),
                  ),

                  const SizedBox(height: 14),

                  // PASSWORD FIELD
                  TextField(
                    controller: _passCtrl,
                    obscureText: !showPassword,
                    style: const TextStyle(color: Colors.greenAccent),
                    decoration: _inputDecoration(
                      "PASSWORD",
                      suffixIcon: IconButton(
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.greenAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            showPassword = !showPassword;
                          });
                        },
                      ),
                    ),
                  ),

                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),

                  const SizedBox(height: 22),
if (isLogin) ...[
  const SizedBox(height: 10),
  Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ResetPasswordScreen(),
          ),
        );
      },
      child: const Text(
        "FORGOT PASSWORD?",
        style: TextStyle(
          color: Colors.greenAccent,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    ),
  ),
],
const SizedBox(height: 12),

                  // 🔘 BUTTON WITH LOADING
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              isLogin ? "LOGIN" : "SIGN UP",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        isLogin = !isLogin;
                        error = "";
                      });
                    },
                    child: Text(
                      isLogin
                          ? "CREATE ACCOUNT"
                          : "HAVE AN ACCOUNT? LOGIN",
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
