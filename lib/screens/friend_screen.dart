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
  
  Map<String, dynamic>? _searchResult;
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

  // 이메일로 유저 검색
  Future<void> _searchUserByEmail() async {
    final email = _searchController.text.trim();
    
    // 1. 자기 자신 검색 방지
    if (email == _currentUser?.email) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("본인은 검색할 수 없습니다.")));
      return;
    }
    if (email.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResult = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _searchResult = snapshot.docs.first.data();
          _searchResult!['uid'] = snapshot.docs.first.id;
        });
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사용자를 찾을 수 없습니다.")));
      }
    } catch (e) {
      debugPrint("검색 오류: $e");
    } finally {
      setState(() => _isSearching = false);
    }
  }

  // [수정됨] 친구 요청 보내기 (중복 체크 강화)
  Future<void> _sendFriendRequest(String targetUid, String targetNickname) async {
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

      // 2. 내가 이미 요청을 보냈는지 확인
      final sentCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: myUid)
          .where('toUid', isEqualTo: targetUid)
          .get();

      if (sentCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이미 요청을 보냈습니다. 수락을 기다리세요.")));
        return;
      }

      // 3. 상대방이 나에게 이미 요청을 보냈는지 확인
      final receivedCheck = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: myUid)
          .get();

      if (receivedCheck.docs.isNotEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("상대방이 이미 요청을 보냈습니다. [받은 요청]을 확인하세요.")));
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
        'toEmail': _searchResult!['email'],
        'toNickname': targetNickname,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("친구 요청을 보냈습니다!")));
        setState(() => _searchResult = null);
        _searchController.clear();
        FocusScope.of(context).unfocus(); // 키보드 내림
      }
    } catch (e) {
      debugPrint("요청 오류: $e");
    }
  }

  Future<void> _acceptRequest(DocumentSnapshot requestDoc) async {
    final data = requestDoc.data() as Map<String, dynamic>;
    final String fromUid = data['fromUid'];
    // 닉네임은 여기서 저장하지 않고 UID만 연결 (실시간 조회를 위해)
    // 하지만 초기 데이터 구성을 위해 일단 저장하고, 읽을 때 갱신함.
    final String fromNickname = data['fromNickname']; 
    final String fromEmail = data['fromEmail'];
    final String toUid = data['toUid'];

    WriteBatch batch = FirebaseFirestore.instance.batch();

    // 1. 내 친구 목록에 상대방 추가
    DocumentReference myFriendRef = FirebaseFirestore.instance
        .collection('users')
        .doc(toUid)
        .collection('friends')
        .doc(fromUid);
    
    batch.set(myFriendRef, {
      'uid': fromUid,
      'createdAt': FieldValue.serverTimestamp(),
      // 닉네임은 굳이 저장 안 해도 되지만, 백업용으로 저장
      'initialNickname': fromNickname, 
      'email': fromEmail,
    });

    // 2. 상대방 친구 목록에 나 추가
    final myDoc = await FirebaseFirestore.instance.collection('users').doc(toUid).get();
    final myNickname = myDoc.data()?['nickname'] ?? '알 수 없음';
    final myEmail = myDoc.data()?['email'] ?? '';

    DocumentReference otherFriendRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fromUid)
        .collection('friends')
        .doc(toUid);

    batch.set(otherFriendRef, {
      'uid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
      'initialNickname': myNickname,
      'email': myEmail,
    });

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
          // 내 친구 목록
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "이메일로 친구 검색",
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _searchUserByEmail,
                          ),
                        ),
                        onSubmitted: (_) => _searchUserByEmail(),
                      ),
                    ),
                  ],
                ),
              ),
              
              if (_isSearching) const LinearProgressIndicator(color: Colors.black),
              if (_searchResult != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.person)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_searchResult!['nickname'] ?? '이름 없음', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_searchResult!['email'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _sendFriendRequest(_searchResult!['uid'], _searchResult!['nickname'] ?? '이름 없음'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                        child: const Text("친구 신청"),
                      )
                    ],
                  ),
                ),

              const Divider(),
              
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_currentUser!.uid)
                      .collection('friends')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final friendDocs = snapshot.data!.docs;

                    if (friendDocs.isEmpty) {
                      return const Center(child: Text("아직 등록된 친구가 없습니다.", style: TextStyle(color: Colors.grey)));
                    }

                    return ListView.builder(
                      itemCount: friendDocs.length,
                      itemBuilder: (context, index) {
                        final friendRelData = friendDocs[index].data() as Map<String, dynamic>;
                        final String friendUid = friendRelData['uid'];

                        // [핵심 수정] 친구의 실시간 정보를 가져오기 위해 StreamBuilder 중첩 사용
                        // (친구 목록에 저장된 옛날 닉네임이 아니라, 실제 유저 테이블의 최신 닉네임을 가져옴)
                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(friendUid).snapshots(),
                          builder: (context, userSnapshot) {
                            if (!userSnapshot.hasData) return const SizedBox(); // 로딩 중엔 빈 공간
                            
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

          // 받은 요청 목록
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