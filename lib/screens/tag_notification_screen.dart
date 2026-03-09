import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

class TagNotificationScreen extends StatelessWidget {
  const TagNotificationScreen({super.key});

  Future<void> _acceptTag(DocumentSnapshot doc) async {
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

  Future<void> _rejectTag(DocumentSnapshot doc) async {
    await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("태그 알림"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tag_requests')
            .where('toUid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.notifications_none_rounded,
              title: "받은 태그 요청이 없습니다",
              subtitle: "친구가 태그하면 여기에 알림이 와요",
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['visitDate'] as Timestamp).toDate();

              return AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.local_offer_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontFamily: 'Pretendard', height: 1.5),
                              children: [
                                TextSpan(text: data['fromNickname'], style: const TextStyle(fontWeight: FontWeight.w800)),
                                const TextSpan(text: "님이 회원님을\n"),
                                TextSpan(text: data['storeName'], style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                                const TextSpan(text: " 방문 기록에 태그했습니다."),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 58.0),
                      child: Text(DateFormat('yyyy.MM.dd').format(date), style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _rejectTag(doc),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                            ),
                            child: const Text("거절"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _acceptTag(doc),
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text("수락"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}