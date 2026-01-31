import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<String> _generatePagerId() async {
    final rand = Random();
    while (true) {
      final id = (100000 + rand.nextInt(900000)).toString();
      final snap = await _db
          .collection('users')
          .where('pagerId', isEqualTo: id)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return id;
    }
  }

  // ✅ SIGN UP
  static Future<void> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await cred.user!.sendEmailVerification();

    final pagerId = await _generatePagerId();

    await _db.collection('users').doc(cred.user!.uid).set({
      'email': email,
      'pagerId': pagerId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ✅ LOGIN
  static Future<void> login(String input, String password) async {
    String email = input;

    if (!input.contains('@')) {
      final snap = await _db
          .collection('users')
          .where('pagerId', isEqualTo: input)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) throw 'INVALID_PAGER_ID';
      email = snap.docs.first['email'];
    }

    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (!cred.user!.emailVerified) {
      await _auth.signOut();
      throw 'EMAIL_NOT_VERIFIED';
    }
  }

  static Future<String> getPagerId() async {
    final uid = _auth.currentUser!.uid;
    final doc = await _db.collection('users').doc(uid).get();
    return doc['pagerId'];
  }

  static Future<void> resendVerification() async {
    await _auth.currentUser!.sendEmailVerification();
  }

  static Future<void> logout() async {
    await _auth.signOut();
  }
  // ✅ CURRENT USER UID (REQUIRED)
static String get uid {
  final user = _auth.currentUser;
  if (user == null) {
    throw Exception("User not logged in");
  }
  return user.uid;
}

// 🔐 PASSWORD RESET
static Future<void> sendPasswordReset(String email) async {
  if (email.isEmpty) {
    throw Exception("Email required");
  }

  try {
    await _auth.sendPasswordResetEmail(email: email);
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      throw Exception("Email not registered");
    }
    throw Exception("Password reset failed");
  }
}


}
