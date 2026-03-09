import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autokaji/screens/friend_visit_screen.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

class FriendScreen extends StatefulWidget {
  const FriendScreen({super.key});

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _searchResults = [];
  
  bool _isSearching = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      QuerySnapshot snapshot;

      if (query.contains('@')) {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: query)
            .get();
      } 
      else {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('nickname', isEqualTo: query)
            .get();
      }

      final List<Map<String, dynamic>> results = [];

      for (var doc in snapshot.docs) {
        if (doc.id == _currentUser?.uid) continue;

        final data = doc.data() as Map<String, dynamic>;
        data['uid'] = doc.id;
        results.add(data);
      }

      setState(() {
        _searchResults = results;
      });

      if (results.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사용자를 찾을 수 없습니다.")));
      }

    } catch (e) {
      debugPrint("검색 오류: $e");
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _sendFriendRequest(String targetUid, String targetNickname, String targetEmail) async {
    try {
      final myUid = _currentUser!.uid;

      final friendCheck = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('friends')
          .doc(targetUid)
          .get();

      if (friendCheck.exists) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이미 친구 사이입니다.")));
        return;
      }

      final sentCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: myUid)
          .where('toUid', isEqualTo: targetUid)
          .get();

      if (sentCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이미 요청을 보냈습니다.")));
        return;
      }

      final receivedCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: myUid)
          .get();

      if (receivedCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("상대방이 이미 요청을 보냈습니다.")));
        return;
      }

      final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final myNickname = myDoc.data()?['nickname'] ?? '알 수 없음';

      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUid': myUid,
        'fromEmail': _currentUser!.email,
        'fromNickname': myNickname,
        'toUid': targetUid,
        'toEmail': targetEmail,
        'toNickname': targetNickname,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("친구 요청을 보냈습니다!")));
      }
    } catch (e) {
      debugPrint("요청 오류: $e");
    }
  }

  Future<void> _acceptRequest(DocumentSnapshot requestDoc) async {
    final data = requestDoc.data() as Map<String, dynamic>;
    final String fromUid = data['fromUid'];
    final String fromNickname = data['fromNickname'];
    final String fromEmail = data['fromEmail'];
    final String toUid = data['toUid'];

    WriteBatch batch = FirebaseFirestore.instance.batch();

    DocumentReference myFriendRef = FirebaseFirestore.instance.collection('users').doc(toUid).collection('friends').doc(fromUid);
    batch.set(myFriendRef, {'uid': fromUid, 'createdAt': FieldValue.serverTimestamp(), 'initialNickname': fromNickname, 'email': fromEmail});

    final myDoc = await FirebaseFirestore.instance.collection('users').doc(toUid).get();
    final myNickname = myDoc.data()?['nickname'] ?? '알 수 없음';
    final myEmail = myDoc.data()?['email'] ?? '';

    DocumentReference otherFriendRef = FirebaseFirestore.instance.collection('users').doc(fromUid).collection('friends').doc(toUid);
    batch.set(otherFriendRef, {'uid': toUid, 'createdAt': FieldValue.serverTimestamp(), 'initialNickname': myNickname, 'email': myEmail});

    batch.delete(requestDoc.reference);
    await batch.commit();
  }

  Future<void> _rejectRequest(String docId) async {
    await FirebaseFirestore.instance.collection('friend_requests').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("친구 관리"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "내 친구"),
            Tab(text: "받은 요청"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // [탭 1] 내 친구 목록 + 검색
          Column(
            children: [
              // 검색 영역
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "이메일 또는 닉네임 검색",
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded, color: AppColors.primary),
                      onPressed: _searchUser,
                    ),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              
              if (_isSearching) const LinearProgressIndicator(color: AppColors.primary),

              if (_searchResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: AppTheme.shadowMd,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return ListTile(
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 22),
                        ),
                        title: Text(user['nickname'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(user['email'] ?? '', style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                        trailing: ElevatedButton(
                          onPressed: () => _sendFriendRequest(user['uid'], user['nickname'] ?? '이름 없음', user['email'] ?? ''),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                          ),
                          child: const Text("신청", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 8),
              
              // 내 친구 리스트
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_currentUser!.uid)
                      .collection('friends')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    final friends = snapshot.data!.docs;

                    if (friends.isEmpty) {
                      return EmptyStateWidget(
                        icon: Icons.people_outline_rounded,
                        title: "아직 등록된 친구가 없습니다",
                        subtitle: "위 검색창에서 친구를 찾아보세요!",
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final friendRelData = friends[index].data() as Map<String, dynamic>;
                        final String friendUid = friendRelData['uid'];

                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(friendUid).snapshots(),
                          builder: (context, userSnapshot) {
                            if (!userSnapshot.hasData) return const SizedBox();
                            
                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                            final String nickname = userData?['nickname'] ?? '알 수 없음';
                            final String email = userData?['email'] ?? '';

                            return AppCard(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FriendVisitScreen(
                                      friendUid: friendUid,
                                      friendNickname: nickname,
                                    ),
                                  ),
                                );
                              },
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Text(email, style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // 받은 요청 목록
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('friend_requests')
                .where('toUid', isEqualTo: _currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              final requests = snapshot.data!.docs;

              if (requests.isEmpty) {
                return EmptyStateWidget(
                  icon: Icons.mail_outline_rounded,
                  title: "받은 친구 요청이 없습니다",
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final reqDoc = requests[index];
                  final reqData = reqDoc.data() as Map<String, dynamic>;

                  return AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${reqData['fromNickname']}님의 친구 요청", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(reqData['fromEmail'] ?? '', style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _rejectRequest(reqDoc.id),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  side: const BorderSide(color: AppColors.border),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                                ),
                                child: const Text("거절"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _acceptRequest(reqDoc),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                                ),
                                child: const Text("수락"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}