import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/repositories/visit_repository.dart';
import 'package:autokaji/providers/auth_provider.dart';

// Repository 인스턴스 제공
final visitRepositoryProvider = Provider<VisitRepository>((ref) {
  return VisitRepository();
});

// 현재 로그인한 유저의 방문 기록을 실시간으로 가져오는 Provider
final userVisitsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  final authState = ref.watch(authStateProvider);
  final visitRepo = ref.watch(visitRepositoryProvider);

  return authState.when(
    data: (user) {
      if (user == null || user.isAnonymous) {
        return Stream.value([]);
      }
      return visitRepo.getUserVisitsStream(user.uid);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

// 친구들의 방문 기록을 실시간으로 가져오는 Provider
final friendsVisitsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  final authState = ref.watch(authStateProvider);
  final visitRepo = ref.watch(visitRepositoryProvider);

  return authState.when(
    data: (user) {
      if (user == null || user.isAnonymous) return Stream.value([]);
      
      // 1. 친구 목록 가져오기
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('friends')
          .snapshots()
          .asyncMap((friendsSnapshot) async {
            final friendUids = friendsSnapshot.docs.map((doc) => doc.id).toList();
            if (friendUids.isEmpty) return <QueryDocumentSnapshot>[];

            // 2. 친구들의 방문 기록 쿼리 (Firestore where-in 제한 10개 고려)
            // 실제 상용 서비스에선 복수 쿼리가 필요할 수 있으나, 일단 단순 구현
            final visitsSnapshot = await FirebaseFirestore.instance
                .collection('visits')
                .where('uid', whereIn: friendUids.take(10).toList())
                .orderBy('visitDate', descending: true)
                .get();
            
            return visitsSnapshot.docs;
          });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
