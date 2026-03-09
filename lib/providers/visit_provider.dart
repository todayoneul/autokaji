import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/repositories/visit_repository.dart';
import 'package:autokaji/providers/auth_provider.dart';

// Repository 인스턴스 제공
final visitRepositoryProvider = Provider<VisitRepository>((ref) {
  return VisitRepository();
});

// [핵심] 현재 로그인한 유저의 방문 기록을 실시간으로 가져오는 Provider
// authStateProvider에 의존하여, 유저가 바뀌거나 로그아웃하면 자동으로 스트림이 갱신/해제됩니다.
final userVisitsProvider = StreamProvider<List<QueryDocumentSnapshot>>((ref) {
  final authState = ref.watch(authStateProvider);
  final visitRepo = ref.watch(visitRepositoryProvider);

  return authState.when(
    data: (user) {
      if (user == null || user.isAnonymous) {
        // 비로그인 상태이거나 익명 유저면 빈 리스트 스트림 반환
        return Stream.value([]);
      }
      // 로그인된 유저라면 해당 UID로 스트림 구독
      return visitRepo.getUserVisitsStream(user.uid);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
