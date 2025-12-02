import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TagNotificationScreen extends StatelessWidget {
  const TagNotificationScreen({super.key});

  Future<void> _acceptTag(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    try {
      // 1. 내 방문 기록으로 추가
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': myUid,
        'storeName': data['storeName'],
        'address': data['address'] ?? '',
        'foodType': data['foodType'],
        'visitDate': data['visitDate'],
        'createdAt': FieldValue.serverTimestamp(),
        'lat': data['lat'],
        'lng': data['lng'],
        'memo': "${data['fromNickname']}님과 함께 방문함", // 자동 메모
        'myRating': 0.0,
      });

      // 2. 요청 삭제
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
      appBar: AppBar(
        title: const Text("태그 알림", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tag_requests')
            .where('toUid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("받은 태그 요청이 없습니다.", style: TextStyle(color: Colors.grey)),
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

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black, fontSize: 16),
                        children: [
                          TextSpan(text: data['fromNickname'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: "님이 회원님을\n"),
                          TextSpan(text: data['storeName'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          const TextSpan(text: " 방문 기록에 태그했습니다."),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(DateFormat('yyyy.MM.dd').format(date), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _rejectTag(doc),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey,
                              side: const BorderSide(color: Colors.grey),
                            ),
                            child: const Text("거절"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _acceptTag(doc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("수락 (저장)"),
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