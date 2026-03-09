import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/repositories/wishlist_repository.dart';
import 'package:autokaji/services/place_search_service.dart';

final wishlistRepositoryProvider = Provider((ref) => WishlistRepository());

// 유저의 찜 목록을 실시간으로 가져오는 스트림 프로바이더
final wishlistProvider = StreamProvider<List<PlaceResult>>((ref) {
  final repo = ref.watch(wishlistRepositoryProvider);
  return repo.getWishlistStream();
});

// 전체 태그 목록 스트림
final wishlistTagsProvider = StreamProvider<List<String>>((ref) {
  final repo = ref.watch(wishlistRepositoryProvider);
  return repo.getAllWishlistTags();
});

// 친구 목록 가져오기
final friendsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(wishlistRepositoryProvider);
  return repo.getFriends();
});

// 선택된 필터 태그 (null이면 전체)
final selectedWishlistTagProvider = StateProvider<String?>((ref) => null);

// 필터링된 찜 목록
final filteredWishlistProvider = Provider<AsyncValue<List<PlaceResult>>>((ref) {
  final wishlistAsync = ref.watch(wishlistProvider);
  final selectedTag = ref.watch(selectedWishlistTagProvider);

  return wishlistAsync.whenData((places) {
    if (selectedTag == null) return places;
    return places.where((p) => p.tags.contains(selectedTag)).toList();
  });
});

// 특정 장소가 찜 목록에 있는지 확인하기 위한 Family 프로바이더
final isWishlistedProvider = Provider.family<bool, String>((ref, uniqueId) {
  final wishlistAsync = ref.watch(wishlistProvider);
  return wishlistAsync.when(
    data: (places) => places.any((p) => p.uniqueId == uniqueId),
    loading: () => false,
    error: (_, __) => false,
  );
});

// 장소의 현재 태그를 가져오는 프로바이더
final placeTagsProvider = Provider.family<List<String>, String>((ref, uniqueId) {
  final wishlistAsync = ref.watch(wishlistProvider);
  return wishlistAsync.when(
    data: (places) {
      final place = places.where((p) => p.uniqueId == uniqueId).toList();
      return place.isNotEmpty ? place.first.tags : [];
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// 찜하기 토글 및 태그 업데이트 기능
final wishlistToggleProvider = Provider((ref) {
  final repo = ref.watch(wishlistRepositoryProvider);
  return (PlaceResult place, bool isWishlisted, {List<String>? tags, List<String>? taggedUserIds}) async {
    if (isWishlisted && tags == null && taggedUserIds == null) {
      await repo.removeWishlist(place.uniqueId);
    } else {
      await repo.addWishlist(place, tags: tags, taggedUserIds: taggedUserIds);
    }
  };
});
