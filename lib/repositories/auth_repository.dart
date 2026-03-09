import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 로그인 상태 변화를 감지하는 Stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 로그인한 사용자 정보 반환
  User? get currentUser => _auth.currentUser;

  // 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }
}