import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isListView = false;
  final ImagePicker _picker = ImagePicker();

  // 검색 관련
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _searchResults = []; 
  List<QueryDocumentSnapshot> _allDataCache = [];  

  // [신규] 리스트 필터 상태 ('All', 'Solo', 'Friends')
  Set<String> _historyFilter = {'All'};

  final List<String> _emptyMessages = [
    "이번 달은 다이어트 중이신가요? 🥗",
    "맛집 탐험을 떠날 완벽한 타이밍입니다! 🚀",
    "텅 빈 그릇... 텅 빈 기록... 😢\n맛있는 걸로 채워보세요!",
    "아직 발견되지 않은 맛집들이 기다리고 있어요 🕵️",
    "오늘 뭐 먹지? 고민될 땐 일단 나가보세요! 🏃‍♂️",
    "위장이 심심해하고 있어요... 꼬르륵 🥯",
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final lowercaseQuery = query.toLowerCase();
    
    setState(() {
      _searchResults = _allDataCache.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final storeName = (data['storeName'] ?? '').toString().toLowerCase();
        final memo = (data['memo'] ?? '').toString().toLowerCase();
        final foodType = (data['foodType'] ?? '').toString().toLowerCase();
        
        return storeName.contains(lowercaseQuery) || 
               memo.contains(lowercaseQuery) ||
               foodType.contains(lowercaseQuery);
      }).toList();
    });
  }

  List<QueryDocumentSnapshot> _getEventsForDay(
      DateTime day, List<QueryDocumentSnapshot> allVisits) {
    return allVisits.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final Timestamp? timestamp = data['visitDate'];
      if (timestamp == null) return false;
      DateTime visitDate = timestamp.toDate();
      return isSameDay(visitDate, day);
    }).toList();
  }

  List<QueryDocumentSnapshot> _getEventsForMonth(
      DateTime day, List<QueryDocumentSnapshot> allVisits) {
    return allVisits.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final Timestamp? timestamp = data['visitDate'];
      if (timestamp == null) return false;
      DateTime visitDate = timestamp.toDate();
      return visitDate.year == day.year && visitDate.month == day.month;
    }).toList();
  }

  String _getEmptyMessage() {
    return _emptyMessages[Random().nextInt(_emptyMessages.length)];
  }

  Future<void> _pickAndUploadImage(
      ImageSource source, StateSetter setSheetState, Function(String) onUrlReady) async {
    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (image == null) return;

      setSheetState(() {}); 

      final user = FirebaseAuth.instance.currentUser;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_images')
          .child(user!.uid)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(File(image.path));
      final String downloadUrl = await storageRef.getDownloadURL();
      onUrlReady(downloadUrl);
    } catch (e) {
      debugPrint("이미지 업로드 실패: $e");
    } finally {
      setSheetState(() {});
    }
  }

  void _showEditSheet(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String storeName = data['storeName'] ?? '이름 없음';
    String currentMemo = data['memo'] ?? '';
    double currentRating = (data['myRating'] ?? 0).toDouble();
    String? currentImageUrl = data['imageUrl'];
    // 태그된 친구 정보 가져오기
    final List<dynamic> taggedFriends = data['taggedFriends'] ?? [];

    final TextEditingController memoController = TextEditingController(text: currentMemo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 24, right: 24, top: 24
          ),
          child: StatefulBuilder(
            builder: (context, setStateSheet) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                storeName,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              // [신규] 함께한 친구 표시
                              if (taggedFriends.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "With: ${taggedFriends.join(", ")}",
                                    style: TextStyle(fontSize: 13, color: Colors.blue[700], fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("기록 삭제"),
                                content: const Text("정말로 이 기록을 삭제하시겠습니까?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("삭제", style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await FirebaseFirestore.instance.collection('visits').doc(doc.id).delete();
                              if (mounted) Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (currentImageUrl == null) {
                            _pickAndUploadImage(ImageSource.gallery, setStateSheet, (url) {
                              setStateSheet(() => currentImageUrl = url);
                            });
                          }
                        },
                        child: Container(
                          width: double.infinity, height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!),
                            image: currentImageUrl != null ? DecorationImage(image: NetworkImage(currentImageUrl!), fit: BoxFit.cover) : null,
                          ),
                          child: currentImageUrl == null
                              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height: 8), Text("사진 추가하기", style: TextStyle(color: Colors.grey))])
                              : Stack(children: [Positioned(right: 8, top: 8, child: CircleAvatar(backgroundColor: Colors.black.withOpacity(0.5), child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () { setStateSheet(() => currentImageUrl = null); }))) ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("나만의 평점", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(index < currentRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 40),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () { setStateSheet(() { currentRating = index + 1.0; }); },
                        );
                      }).expand((widget) => [widget, const SizedBox(width: 8)]).toList()..removeLast(),
                    ),
                    const SizedBox(height: 24),
                    const Text("메모", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: memoController,
                      maxLength: 100, maxLines: 4,
                      decoration: InputDecoration(
                        hintText: "방문 후기를 남겨보세요 (최대 100자)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(16), filled: true, fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text("취소", style: TextStyle(color: Colors.black)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance.collection('visits').doc(doc.id).update({
                                'myRating': currentRating, 'memo': memoController.text.trim(), 'imageUrl': currentImageUrl,
                              });
                              if (mounted) Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text("저장", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _selectYearMonth(BuildContext context) {
    DateTime tempPickedDate = _focusedDay;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(onTap: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.grey, fontSize: 16))),
                    const Text("날짜 선택", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    GestureDetector(onTap: () { setState(() { _focusedDay = tempPickedDate; }); Navigator.pop(context); }, child: const Text("확인", style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  initialDateTime: _focusedDay, mode: CupertinoDatePickerMode.monthYear,
                  minimumDate: DateTime(2000, 1), maximumDate: DateTime(2099, 12),
                  onDateTimeChanged: (DateTime newDate) { tempPickedDate = newDate; },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatisticsCard(List<QueryDocumentSnapshot> allVisits) {
    if (allVisits.isEmpty) return const SizedBox();
    final Map<String, int> foodCounts = {};
    double totalRating = 0;
    int ratingCount = 0;
    for (var doc in allVisits) {
      final data = doc.data() as Map<String, dynamic>;
      final String type = data['foodType'] ?? '기타';
      foodCounts[type] = (foodCounts[type] ?? 0) + 1;
      final double rating = (data['myRating'] ?? 0).toDouble();
      if (rating > 0) { totalRating += rating; ratingCount++; }
    }
    String topFood = '-';
    int maxCount = 0;
    foodCounts.forEach((key, value) { if (value > maxCount) { maxCount = value; topFood = key; } });
    String avgRating = ratingCount > 0 ? (totalRating / ratingCount).toStringAsFixed(1) : '0.0';
    return Container(
      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(Icons.emoji_events, "최애 음식", topFood, Colors.amber),
          Container(width: 1, height: 40, color: Colors.white24),
          _statItem(Icons.star, "평균 별점", avgRating, Colors.yellowAccent),
          Container(width: 1, height: 40, color: Colors.white24),
          _statItem(Icons.restaurant_menu, "누적 방문", "${allVisits.length}회", Colors.white),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24), const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildListItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String storeName = data['storeName'] ?? '이름 없음';
    final String foodType = data['foodType'] ?? '기타';
    final double myRating = (data['myRating'] ?? 0).toDouble();
    final String memo = data['memo'] ?? '';
    final Timestamp visitTime = data['visitDate'];
    final DateTime visitDate = visitTime.toDate();
    final String? imageUrl = data['imageUrl'];
    final List<dynamic> taggedFriends = data['taggedFriends'] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: imageUrl != null 
            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image)))
            : Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.restaurant, color: Colors.black54)),
        title: Row(
          children: [
            Expanded(child: Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
            if (myRating > 0)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.star, size: 14, color: Colors.amber), Text(" $myRating", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber))])),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(foodType, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(width: 8),
                Text(DateFormat('yy.MM.dd').format(visitDate), style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ],
            ),
            if (taggedFriends.isNotEmpty)
               Text("With: ${taggedFriends.join(", ")}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500)),
            if (memo.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(memo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ],
        ),
        onTap: () => _showEditSheet(doc),
      ),
    );
  }

  // [수정됨] 리스트 모드 화면 (필터 추가)
  Widget _buildAllHistoryList(List<QueryDocumentSnapshot> allVisits) {
    // 1. 필터링 로직
    final filteredVisits = allVisits.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> friends = data['taggedFriends'] ?? [];
      
      if (_historyFilter.contains('All')) return true;
      if (_historyFilter.contains('Solo')) return friends.isEmpty;
      if (_historyFilter.contains('Friends')) return friends.isNotEmpty;
      return true;
    }).toList();

    return Column(
      children: [
        _buildStatisticsCard(allVisits),
        
        // [신규] 필터 버튼 영역
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Text("전체 기록", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('전체')),
                  ButtonSegment(value: 'Solo', label: Text('혼자')),
                  ButtonSegment(value: 'Friends', label: Text('친구랑')),
                ],
                selected: _historyFilter,
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _historyFilter = newSelection;
                  });
                },
                style: ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: filteredVisits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.filter_list_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("해당하는 기록이 없어요.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filteredVisits.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildListItem(filteredVisits[index]),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || (user.isAnonymous && user.displayName == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('방문 기록')),
        body: const Center(child: Text('로그인 후 방문 기록을 확인해보세요!')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "가게 이름, 메모 검색...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.black),
                onChanged: _runSearch,
              )
            : const Text('방문 기록', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.black),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchResults = [];
                }
              });
            },
          ),
          if (!_isSearching) ...[
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  if (!_isListView)
                    TextButton(
                      onPressed: () { setState(() { _focusedDay = DateTime.now(); _selectedDay = DateTime.now(); }); },
                      style: TextButton.styleFrom(backgroundColor: Colors.grey[100], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      child: const Text("오늘", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () { setState(() { _isListView = !_isListView; }); },
                    icon: Icon(_isListView ? Icons.calendar_month : Icons.list_alt, color: Colors.black),
                    tooltip: _isListView ? "달력 보기" : "전체 목록 보기",
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('visits')
            .where('uid', isEqualTo: user.uid)
            .orderBy('visitDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('오류 발생: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final allVisits = snapshot.data!.docs;
          _allDataCache = allVisits;

          if (_isSearching) {
            if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
              return const Center(child: Text("검색 결과가 없습니다.", style: TextStyle(color: Colors.grey)));
            }
            if (_searchResults.isEmpty && _searchController.text.isEmpty) {
               return const Center(child: Text("검색어를 입력하세요.", style: TextStyle(color: Colors.grey)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _searchResults.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildListItem(_searchResults[index]),
            );
          }

          if (_isListView) {
            return _buildAllHistoryList(allVisits);
          } else {
            final monthVisits = _getEventsForMonth(_focusedDay, allVisits);
            return Column(
              children: [
                TableCalendar(
                  locale: 'ko_KR',
                  firstDay: DateTime.utc(2000, 1, 1),
                  lastDay: DateTime.utc(2099, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  eventLoader: (day) => _getEventsForDay(day, allVisits),
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() { _selectedDay = selectedDay; _focusedDay = focusedDay; });
                  },
                  onFormatChanged: (format) { if (_calendarFormat != format) setState(() => _calendarFormat = format); },
                  onPageChanged: (focusedDay) { setState(() { _focusedDay = focusedDay; }); },
                  onHeaderTapped: (_) => _selectYearMonth(context),
                  headerStyle: const HeaderStyle(titleCentered: true, formatButtonVisible: false, titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), rightChevronIcon: Icon(Icons.chevron_right, color: Colors.black), leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black)),
                  calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle), markerDecoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                ),
                const Divider(height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(DateFormat('yyyy년 M월', 'ko_KR').format(_focusedDay), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('의 맛집들', style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal)),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: Text('${monthVisits.length}곳', style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                Expanded(
                  child: monthVisits.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.no_meals_outlined, size: 64, color: Colors.grey), const SizedBox(height: 16), Text(_getEmptyMessage(), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 16))]))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          itemCount: monthVisits.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) => _buildListItem(monthVisits[index]),
                        ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}