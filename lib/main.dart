import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'auth_screen.dart';
import 'chat_list_screen.dart';
import 'auth_service.dart';
import 'verify_email_screen.dart';

// ✅ CONDITIONAL IMPORT (THIS IS THE KEY)
import 'web_context_menu.dart'
    if (dart.library.html) 'web_context_menu_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔥 Disable browser right-click (WEB ONLY, SAFE)
  disableWebContextMenu();

  runApp(const PagerChatApp());
}

class PagerChatApp extends StatelessWidget {
  const PagerChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}

/// 🔁 AUTH + EMAIL VERIFICATION GATE
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        // ⏳ Checking auth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(
                color: Colors.greenAccent,
              ),
            ),
          );
        }

        // ❌ Not logged in
        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

        final user = snapshot.data!;

        // ⚠ Email not verified
        if (!user.emailVerified) {
          return const VerifyEmailScreen();
        }

        // ✅ Logged in + verified
        return FutureBuilder<String>(
          future: AuthService.getPagerId(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: CircularProgressIndicator(
                    color: Colors.greenAccent,
                  ),
                ),
              );
            }

            return ChatListScreen(myId: snap.data!);
          },
        );
      },
    );
  }
}
