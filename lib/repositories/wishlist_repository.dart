import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autokaji/services/place_search_service.dart';

class WishlistRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  CollectionReference get _wishlistRef {
    if (uid == null) throw Exception('No user logged in');
    return _firestore.collection('users').doc(uid).collection('wishlist');
  }

  /// 찜 목록 실시간 스트림
  Stream<List<PlaceResult>> getWishlistStream() {
    if (uid == null) return Stream.value([]);
    return _wishlistRef
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return PlaceResult(
          name: data['name'] ?? '',
          address: data['address'] ?? '',
          lat: (data['lat'] ?? 0).toDouble(),
          lng: (data['lng'] ?? 0).toDouble(),
          rating: (data['rating'] ?? 0).toDouble(),
          reviewCount: data['reviewCount'] ?? 0,
          category: data['category'] ?? '기타',
          source: data['source'] ?? 'google',
          photoUrl: data['photoUrl'],
          placeUrl: data['placeUrl'],
          placeId: doc.id, 
          rawData: data['rawData'],
          tags: List<String>.from(data['tags'] ?? []),
        );
      }).toList();
    });
  }

  /// 친구 목록 가져오기 (태그용)
  Future<List<Map<String, dynamic>>> getFriends() async {
    if (uid == null) return [];
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('friends')
          .get();
      
      final List<Map<String, dynamic>> friendsData = [];
      
      for (var doc in snapshot.docs) {
        final friendUid = doc.id; // 문서 ID가 친구의 UID임
        final userDoc = await _firestore.collection('users').doc(friendUid).get();
        
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          friendsData.add({
            'uid': friendUid,
            'nickname': userData['nickname'] ?? '알 수 없음',
            'photoUrl': userData['photoUrl'],
          });
        }
      }
      return friendsData;
    } catch (e) {
      debugPrint("친구 목록 가져오기 오류: $e");
      return [];
    }
  }

  /// 찜 추가/업데이트 (태그 및 태그된 친구 포함)
  Future<void> addWishlist(PlaceResult place, {List<String>? tags, List<String>? taggedUserIds}) async {
    if (uid == null) return;
    
    final docId = place.uniqueId;
    final myNickname = (await _firestore.collection('users').doc(uid).get()).data()?['nickname'] ?? '친구';

    await _wishlistRef.doc(docId).set({
      'name': place.name,
      'address': place.address,
      'lat': place.lat,
      'lng': place.lng,
      'rating': place.rating,
      'reviewCount': place.reviewCount,
      'category': place.category,
      'source': place.source,
      'photoUrl': place.photoUrl,
      'placeUrl': place.placeUrl,
      'rawData': place.rawData,
      'tags': tags ?? place.tags,
      'taggedUserIds': taggedUserIds ?? [],
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 태그된 친구들에게 알림 전송 (공용 알림 컬렉션 사용)
    if (taggedUserIds != null && taggedUserIds.isNotEmpty) {
      for (var targetUid in taggedUserIds) {
        await _firestore.collection('notifications').add({
          'type': 'wishlist_tag',
          'fromUid': uid,
          'toUid': targetUid,
          'fromNickname': myNickname,
          'storeName': place.name,
          'placeId': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
    }
  }

  /// 장소의 태그만 업데이트
  Future<void> updateWishlistTags(String placeUniqueId, List<String> tags) async {
    if (uid == null) return;
    await _wishlistRef.doc(placeUniqueId).update({
      'tags': tags,
    });
  }

  /// 전체 찜 목록에서 사용 중인 고유 태그 목록 추출 스트림
  Stream<List<String>> getAllWishlistTags() {
    if (uid == null) return Stream.value([]);
    try {
      return _wishlistRef.snapshots().map((snapshot) {
        final Set<String> tags = {};
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          
          final List<dynamic>? docTags = data['tags'] as List<dynamic>?;
          if (docTags != null) {
            for (var t in docTags) {
              if (t != null) tags.add(t.toString());
            }
          }
        }
        return tags.toList()..sort();
      }).handleError((error) {
        debugPrint("태그 스트림 오류: $error");
        return <String>[];
      });
    } catch (e) {
      debugPrint("태그 리포지토리 예외: $e");
      return Stream.value([]);
    }
  }

  /// 찜 삭제
  Future<void> removeWishlist(String placeUniqueId) async {
    if (uid == null) return;
    await _wishlistRef.doc(placeUniqueId).delete();
  }
}
