import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  bool _initialized = false;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _googleSignIn.initialize();
    _initialized = true;
  }

  Future<UserCredential> signInWithGoogle() async {
    await initialize();

    final googleUser = await _googleSignIn.authenticate();
    final googleAuthentication = googleUser.authentication;
    final idToken = googleAuthentication.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google Sign-In did not return an identity token.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);

    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await initialize();

    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
  }
}
