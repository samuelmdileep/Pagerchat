import 'package:flutter/material.dart';
import 'auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final emailCtrl = TextEditingController();

  bool isLoading = false;
  int countdown = 0;
  String message = "";

  late AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> sendResetLink() async {
    if (emailCtrl.text.trim().isEmpty) return;

    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      await AuthService.sendPasswordReset(emailCtrl.text.trim());
      setState(() {
        message = "Reset link sent. Check your email.";
        countdown = 30;
      });
      _startCountdown();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _startCountdown() async {
    while (countdown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      setState(() => countdown--);
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    emailCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.green),
        filled: true,
        fillColor: Colors.black,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.green),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Colors.greenAccent, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
                FadeTransition(
                  opacity: Tween(begin: 0.6, end: 1.0)
                      .animate(_logoController),
                  child: const Text(
                    "PAGER",
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 26,
                      letterSpacing: 4,
                    ),
                  ),
                ),

                const SizedBox(height: 6),
                Text(
                  "RESET PASSWORD",
                  style: TextStyle(
                    color: Colors.greenAccent.withOpacity(0.7),
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 24),

                TextField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.greenAccent),
                  decoration: _decoration("EMAIL"),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed:
                        (isLoading || countdown > 0) ? null : sendResetLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            countdown > 0
                                ? "RESEND IN $countdown"
                                : "SEND RESET LINK",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                  ),
                ),

                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "BACK TO LOGIN",
                    style: TextStyle(
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
    );
  }
}
