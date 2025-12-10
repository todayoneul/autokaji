import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autokaji/screens/friend_visit_screen.dart';

class FriendScreen extends StatefulWidget {
  const FriendScreen({super.key});

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  // [수정] 검색 결과를 리스트로 관리 (동명이인 처리)
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

  // [수정] 통합 검색 로직 (이메일 or 닉네임)
  Future<void> _searchUser() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = []; // 초기화
    });

    try {
      QuerySnapshot snapshot;

      // 1. '@'가 포함되어 있으면 이메일 검색
      if (query.contains('@')) {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: query)
            .get();
      } 
      // 2. 아니면 닉네임 검색
      else {
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('nickname', isEqualTo: query)
            .get();
      }

      final List<Map<String, dynamic>> results = [];

      for (var doc in snapshot.docs) {
        // 본인은 검색 결과에서 제외
        if (doc.id == _currentUser?.uid) continue;

        final data = doc.data() as Map<String, dynamic>;
        data['uid'] = doc.id; // UID 포함
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

  // 친구 요청 보내기
  Future<void> _sendFriendRequest(String targetUid, String targetNickname, String targetEmail) async {
    try {
      final myUid = _currentUser!.uid;

      // 1. 이미 친구인지 확인
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

      // 2. 이미 요청을 보냈는지 확인
      final sentCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: myUid)
          .where('toUid', isEqualTo: targetUid)
          .get();

      if (sentCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이미 요청을 보냈습니다.")));
        return;
      }

      // 3. 상대방이 이미 보냈는지 확인
      final receivedCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: myUid)
          .get();

      if (receivedCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("상대방이 이미 요청을 보냈습니다.")));
        return;
      }

      // 4. 요청 전송
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
        // 검색 결과 유지 (다른 사람도 추가할 수 있으므로)
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
      appBar: AppBar(
        title: const Text("친구 관리", style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          indicatorColor: Colors.black,
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
                    hintText: "이메일 또는 닉네임 검색", // [수정] 힌트 변경
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchUser, // [수정] 함수 연결
                    ),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              
              if (_isSearching) const LinearProgressIndicator(color: Colors.black),

              // [수정] 검색 결과 리스트 (여러 명일 수 있음)
              if (_searchResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200), // 결과창 높이 제한
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(user['nickname'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold)),
                        // [중요] 이메일을 함께 표시하여 구분
                        subtitle: Text(user['email'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        trailing: ElevatedButton(
                          onPressed: () => _sendFriendRequest(user['uid'], user['nickname'] ?? '이름 없음', user['email'] ?? ''),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text("신청", style: TextStyle(fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ),

              const Divider(),
              
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
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final friends = snapshot.data!.docs;

                    if (friends.isEmpty) {
                      return const Center(child: Text("아직 등록된 친구가 없습니다.", style: TextStyle(color: Colors.grey)));
                    }

                    return ListView.builder(
                      itemCount: friends.length,
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

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey[200],
                                child: const Icon(Icons.person, color: Colors.grey),
                              ),
                              title: Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(email),
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

          // 받은 요청 목록 (기존과 동일)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('friend_requests')
                .where('toUid', isEqualTo: _currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final requests = snapshot.data!.docs;

              if (requests.isEmpty) {
                return const Center(child: Text("받은 친구 요청이 없습니다.", style: TextStyle(color: Colors.grey)));
              }

              return ListView.builder(
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final reqDoc = requests[index];
                  final reqData = reqDoc.data() as Map<String, dynamic>;

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text("${reqData['fromNickname']}님의 친구 요청"),
                    subtitle: Text(reqData['fromEmail']),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => _acceptRequest(reqDoc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _rejectRequest(reqDoc.id),
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