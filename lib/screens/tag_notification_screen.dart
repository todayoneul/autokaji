import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';
import 'package:autokaji/screens/friend_visit_screen.dart';

class TagNotificationScreen extends StatelessWidget {
  const TagNotificationScreen({super.key});

  /// 방문 기록 태그 수락
  Future<void> _acceptVisitTag(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': myUid,
        'storeName': data['storeName'],
        'address': data['address'] ?? '',
        'foodType': data['foodType'],
        'visitDate': data['visitDate'],
        'createdAt': FieldValue.serverTimestamp(),
        'lat': data['lat'],
        'lng': data['lng'],
        'memo': "${data['fromNickname']}님과 함께 방문함",
        'myRating': 0.0,
      });

      await doc.reference.delete();
    } catch (e) {
      debugPrint("수락 오류: $e");
    }
  }

  /// 친구 요청 수락
  Future<void> _acceptFriendRequest(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final String fromUid = data['fromUid'];
    final String fromNickname = data['fromNickname'];
    final String fromEmail = data['fromEmail'] ?? '';
    final String toUid = data['toUid'];

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 내 친구 목록에 추가
      DocumentReference myFriendRef = FirebaseFirestore.instance.collection('users').doc(toUid).collection('friends').doc(fromUid);
      batch.set(myFriendRef, {'uid': fromUid, 'createdAt': FieldValue.serverTimestamp(), 'initialNickname': fromNickname, 'email': fromEmail});

      // 상대방 친구 목록에 나를 추가하기 위해 내 정보 가져오기
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(toUid).get();
      final myNickname = myDoc.data()?['nickname'] ?? '알 수 없음';
      final myEmail = myDoc.data()?['email'] ?? '';

      DocumentReference otherFriendRef = FirebaseFirestore.instance.collection('users').doc(fromUid).collection('friends').doc(toUid);
      batch.set(otherFriendRef, {'uid': toUid, 'createdAt': FieldValue.serverTimestamp(), 'initialNickname': myNickname, 'email': myEmail});

      // 알림 삭제
      batch.delete(doc.reference);
      await batch.commit();
    } catch (e) {
      debugPrint("친구 수락 오류: $e");
    }
  }

  /// 알림 삭제 (거절/삭제 공통)
  Future<void> _deleteNotification(DocumentSnapshot doc) async {
    await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("알림", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.notifications_none_rounded,
              title: "새로운 알림이 없습니다",
              subtitle: "친구가 나를 태그하거나 요청을 보내면 여기에 표시됩니다",
            );
          }

          return _buildNotificationList(snapshot.data!.docs);
        },
      ),
    );
  }

  Widget _buildNotificationList(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final String type = data['type'] ?? 'visit_tag';
        final DateTime date = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        switch (type) {
          case 'wishlist_tag':
            return _buildWishlistTagCard(context, doc, data, date);
          case 'friend_request':
            return _buildFriendRequestCard(context, doc, data, date);
          case 'visit_tag':
          default:
            return _buildVisitTagCard(context, doc, data, date);
        }
      },
    );
  }

  /// 친구 요청 카드
  Widget _buildFriendRequestCard(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data, DateTime date) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(color: Color(0xFFE3F2FD), shape: BoxShape.circle),
                child: const Icon(Icons.person_add_rounded, color: Colors.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'Pretendard'),
                        children: [
                          TextSpan(text: data['fromNickname'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: "님이 "),
                          const TextSpan(text: "친구 요청", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          const TextSpan(text: "을 보냈습니다."),
                        ],
                      ),
                    ),
                    Text(DateFormat('MM.dd HH:mm').format(date), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _deleteNotification(doc),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("거절"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptFriendRequest(doc),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("수락"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// 찜 목록 태그 카드
  Widget _buildWishlistTagCard(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data, DateTime date) {
    return AppCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FriendVisitScreen(
              friendUid: data['fromUid'],
              friendNickname: data['fromNickname'],
            ),
          ),
        );
      },
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: Color(0xFFFFEBEF), shape: BoxShape.circle),
              child: const Icon(Icons.favorite_rounded, color: Colors.red, size: 22),
            ),
            title: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'Pretendard'),
                children: [
                  TextSpan(text: data['fromNickname'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: "님이 "),
                  TextSpan(text: data['storeName'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const TextSpan(text: " 장소를 같이 가고 싶어해요!"),
                ],
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(DateFormat('MM.dd HH:mm').format(date), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
              onPressed: () => _deleteNotification(doc),
            ),
          ),
        ],
      ),
    );
  }

  /// 방문 기록 태그 카드
  Widget _buildVisitTagCard(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data, DateTime date) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.primarySurface, shape: BoxShape.circle),
                child: const Icon(Icons.local_offer_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'Pretendard'),
                        children: [
                          TextSpan(text: data['fromNickname'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: "님이 "),
                          TextSpan(text: data['storeName'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          const TextSpan(text: " 방문 기록에 태그했습니다."),
                        ],
                      ),
                    ),
                    Text(DateFormat('MM.dd HH:mm').format(date), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _deleteNotification(doc),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("거절"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptVisitTag(doc),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("수락"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
