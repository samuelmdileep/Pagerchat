import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with TickerProviderStateMixin {
  String msg = "";
  bool verified = false;

  // timers
  Timer? _autoCheckTimer;
  Timer? _resendTimer;
  int resendSeconds = 30;

  // animations
  late AnimationController _logoController;
  late AnimationController _successController;

  @override
  void initState() {
    super.initState();

    // 🔄 logo pulse
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // ✅ success animation
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 🔁 auto-check every 5 seconds
    _autoCheckTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => checkVerified());

    // ⏱ resend countdown
    _startResendTimer();
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _resendTimer?.cancel();
    _logoController.dispose();
    _successController.dispose();
    super.dispose();
  }

  // ===================== LOGIC =====================

  Future<void> checkVerified() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && user.emailVerified) {
      _autoCheckTimer?.cancel();
      setState(() {
        verified = true;
        msg = "";
      });

      _successController.forward();

      // small delay before leaving screen
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _startResendTimer() {
    resendSeconds = 30;
    _resendTimer?.cancel();

    _resendTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => resendSeconds--);
      }
    });
  }

  Future<void> resendEmail() async {
    await AuthService.resendVerification();
    _startResendTimer();
    setState(() => msg = "Verification email resent.");
  }

Future<void> openMailApp() async {
  // Try Gmail first (Android)
  final gmailUri = Uri.parse("googlegmail://");

  if (await canLaunchUrl(gmailUri)) {
    await launchUrl(
      gmailUri,
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  // Fallback: any mail app
  final mailUri = Uri(scheme: 'mailto');

  if (await canLaunchUrl(mailUri)) {
    await launchUrl(
      mailUri,
      mode: LaunchMode.externalApplication,
    );
  } else {
    setState(() {
      msg = "No email app found. Please open your mail app manually.";
    });
  }
}


  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: verified
                ? _buildSuccess()
                : _buildVerifyUI(),
          ),
        ),
      ),
    );
  }

  // ===================== VERIFY UI =====================

Widget _buildVerifyUI() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // ================= LOGO =================
      FadeTransition(
        opacity: Tween(begin: 0.7, end: 1.0).animate(_logoController),
        child: const Text(
          "PAGER",
          style: TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
            fontSize: 28,
            letterSpacing: 5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      const SizedBox(height: 14),

      // ================= TITLE =================
      const Text(
        "VERIFY YOUR EMAIL",
        style: TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'monospace',
          letterSpacing: 2.2,
          fontSize: 16,
        ),
      ),

      const SizedBox(height: 16),

      // ================= INFO =================
      const Text(
        "We’ve sent a verification link to your email.\n"
        "This screen will update automatically once verified.",
        style: TextStyle(
          color: Colors.green,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),

      const SizedBox(height: 10),

      // ================= SPAM HINT =================
      Text(
        "Didn’t receive it? Check Spam or Promotions.",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.greenAccent.withOpacity(0.55),
          fontSize: 12,
          fontFamily: 'monospace',
          letterSpacing: 0.6,
        ),
      ),

      // ================= STATUS MESSAGE =================
      if (msg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13,
            ),
          ),
        ),

      const SizedBox(height: 26),

      // ================= PRIMARY ACTION =================
      Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.25),
              blurRadius: 10,
            ),
          ],
        ),
        child: OutlinedButton(
          onPressed: openMailApp,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.greenAccent, width: 1.4),
            foregroundColor: Colors.greenAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            "OPEN MAIL APP",
            style: TextStyle(
              letterSpacing: 1.4,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),

      const SizedBox(height: 14),

      // ================= SECONDARY ACTION =================
      TextButton(
        onPressed: resendSeconds == 0 ? resendEmail : null,
        child: Text(
          resendSeconds == 0
              ? "RESEND EMAIL"
              : "RESEND IN ${resendSeconds}s",
          style: TextStyle(
            color: resendSeconds == 0
                ? Colors.greenAccent
                : Colors.green,
            letterSpacing: 1.1,
            fontFamily: 'monospace',
          ),
        ),
      ),

      const SizedBox(height: 4),

      // ================= TERTIARY =================
      TextButton(
        onPressed: () async {
          await AuthService.logout();
          if (!mounted) return;
        },
        child: const Text(
          "CHANGE EMAIL",
          style: TextStyle(
            color: Colors.green,
            fontFamily: 'monospace',
            letterSpacing: 0.8,
          ),
        ),
      ),
    ],
  );
}

  // ===================== SUCCESS UI =====================

  Widget _buildSuccess() {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _successController,
        curve: Curves.elasticOut,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.check_circle,
            color: Colors.greenAccent,
            size: 72,
          ),
          SizedBox(height: 12),
          Text(
            "EMAIL VERIFIED",
            style: TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
