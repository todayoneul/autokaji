import 'package:cloud_firestore/cloud_firestore.dart';

class VisitRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. 방문 기록 실시간 스트림 가져오기 (특정 유저)
  Stream<List<QueryDocumentSnapshot>> getUserVisitsStream(String uid) {
    return _firestore
        .collection('visits')
        .where('uid', isEqualTo: uid)
        .orderBy('visitDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  // 2. 방문 기록 저장하기 (친구 태그 포함)
  Future<void> saveVisit({
    required String uid,
    required String userNickname,
    required String storeName,
    required String address,
    required String foodType,
    required DateTime visitDate,
    required double lat,
    required double lng,
    required Map<String, String> taggedFriends,
  }) async {
    // 1) 방문 기록 저장
    await _firestore.collection('visits').add({
      'uid': uid,
      'storeName': storeName,
      'address': address,
      'foodType': foodType,
      'visitDate': Timestamp.fromDate(visitDate),
      'createdAt': FieldValue.serverTimestamp(),
      'lat': lat,
      'lng': lng,
      'taggedFriends': taggedFriends.values.toList(),
    });

    // 2) 태그된 친구들에게 알림(요청) 보내기
    for (var entry in taggedFriends.entries) {
      await _firestore.collection('tag_requests').add({
        'fromUid': uid,
        'fromNickname': userNickname,
        'toUid': entry.key,
        'storeName': storeName,
        'address': address,
        'foodType': foodType,
        'visitDate': Timestamp.fromDate(visitDate),
        'lat': lat,
        'lng': lng,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // 3. 기록 업데이트 (평점, 메모, 사진 등)
  Future<void> updateVisit(String docId, Map<String, dynamic> data) async {
    await _firestore.collection('visits').doc(docId).update(data);
  }

  // 4. 기록 삭제
  Future<void> deleteVisit(String docId) async {
    await _firestore.collection('visits').doc(docId).delete();
  }
}
