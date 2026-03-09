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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/providers/visit_provider.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
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

  // 리스트 필터 상태
  String _statsFilter = 'All'; // 'All', 'Solo', 'Friends'
  String? _selectedFriend; // 친구별 필터

  // DraggableSheet 컨트롤러
  final DraggableScrollableController _sheetController = DraggableScrollableController();

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
    _sheetController.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    if (query.isEmpty) {
      setState(() { _searchResults = []; });
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
    final List<dynamic> taggedFriends = data['taggedFriends'] ?? [];

    final TextEditingController memoController = TextEditingController(text: currentMemo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 24, right: 24, top: 8
          ),
          child: StatefulBuilder(
            builder: (context, setStateSheet) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BottomSheetHandle(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                storeName,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (taggedFriends.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.people_rounded, size: 14, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          taggedFriends.join(", "),
                                          style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
                                  title: const Text("기록 삭제", style: TextStyle(fontWeight: FontWeight.w800)),
                                  content: const Text("정말로 이 기록을 삭제하시겠습니까?"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소", style: TextStyle(color: AppColors.textSecondary))),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("삭제", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(visitRepositoryProvider).deleteVisit(doc.id);
                                if (mounted) Navigator.pop(context);
                              }
                            },
                          ),
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
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                            border: Border.all(color: AppColors.border),
                            image: currentImageUrl != null ? DecorationImage(image: NetworkImage(currentImageUrl!), fit: BoxFit.cover) : null,
                          ),
                          child: currentImageUrl == null
                              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_rounded, size: 40, color: AppColors.textTertiary), const SizedBox(height: 8), Text("사진 추가하기", style: TextStyle(color: AppColors.textTertiary))])
                              : Stack(children: [Positioned(right: 8, top: 8, child: Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(AppTheme.radiusFull)), child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20), onPressed: () { setStateSheet(() => currentImageUrl = null); })))]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text("나만의 평점", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setStateSheet(() { currentRating = index + 1.0; }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              index < currentRating ? Icons.star_rounded : Icons.star_outline_rounded, 
                              color: AppColors.accent, 
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    const Text("메모", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: memoController,
                      maxLength: 100, maxLines: 4,
                      decoration: InputDecoration(
                        hintText: "방문 후기를 남겨보세요 (최대 100자)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(16), 
                        filled: true, 
                        fillColor: AppColors.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            child: const Text("취소", style: TextStyle(color: AppColors.textPrimary)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppGradientButton(
                            text: "저장",
                            height: 52,
                            onPressed: () async {
                              await ref.read(visitRepositoryProvider).updateVisit(doc.id, {
                                'myRating': currentRating, 'memo': memoController.text.trim(), 'imageUrl': currentImageUrl,
                              });
                              if (mounted) Navigator.pop(context);
                            },
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
      context: context, backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              const BottomSheetHandle(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(onTap: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: AppColors.textTertiary, fontSize: 16))),
                    const Text("날짜 선택", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    GestureDetector(onTap: () { setState(() { _focusedDay = tempPickedDate; }); Navigator.pop(context); }, child: const Text("확인", style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider),
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

  // ─── 통계 카드 (필터 포함) ───

  List<QueryDocumentSnapshot> _filterVisits(List<QueryDocumentSnapshot> visits) {
    return visits.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> friends = data['taggedFriends'] ?? [];
      
      if (_statsFilter == 'All') return true;
      if (_statsFilter == 'Solo') return friends.isEmpty;
      if (_statsFilter == 'Friends') {
        if (_selectedFriend != null) {
          return friends.contains(_selectedFriend);
        }
        return friends.isNotEmpty;
      }
      return true;
    }).toList();
  }

  // 모든 친구 목록 추출
  List<String> _getAllFriends(List<QueryDocumentSnapshot> allVisits) {
    final Set<String> friends = {};
    for (var doc in allVisits) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> taggedFriends = data['taggedFriends'] ?? [];
      for (var f in taggedFriends) {
        friends.add(f.toString());
      }
    }
    return friends.toList()..sort();
  }

  Map<String, dynamic> _computeStats(List<QueryDocumentSnapshot> visits) {
    final Map<String, int> foodCounts = {};
    double totalRating = 0;
    int ratingCount = 0;
    for (var doc in visits) {
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
    return {'topFood': topFood, 'avgRating': avgRating, 'count': visits.length};
  }

  Widget _buildStatisticsCard(List<QueryDocumentSnapshot> allVisits) {
    if (allVisits.isEmpty) return const SizedBox();
    
    final filtered = _filterVisits(allVisits);
    final stats = _computeStats(filtered);
    final allFriends = _getAllFriends(allVisits);

    return Column(
      children: [
        // 필터 탭
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _filterTab('전체', 'All'),
              const SizedBox(width: 8),
              _filterTab('혼자', 'Solo'),
              const SizedBox(width: 8),
              _filterTab('친구랑', 'Friends'),
            ],
          ),
        ),
        
        // 친구 선택 칩 (친구 필터 활성화 시)
        if (_statsFilter == 'Friends' && allFriends.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFriend = null),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: _selectedFriend == null ? AppColors.primaryGradient : null,
                        color: _selectedFriend == null ? null : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        '전체 친구',
                        style: TextStyle(
                          color: _selectedFriend == null ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                ...allFriends.map((friend) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFriend = friend),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: _selectedFriend == friend ? AppColors.primaryGradient : null,
                        color: _selectedFriend == friend ? null : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        friend,
                        style: TextStyle(
                          color: _selectedFriend == friend ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),

        // 통계 카드
        Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.secondaryGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl), 
            boxShadow: AppTheme.shadowLg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(Icons.emoji_events_rounded, "최애 음식", stats['topFood'], AppColors.accent),
              Container(width: 1, height: 40, color: Colors.white24),
              _statItem(Icons.star_rounded, "평균 별점", stats['avgRating'], AppColors.accentLight),
              Container(width: 1, height: 40, color: Colors.white24),
              _statItem(Icons.restaurant_menu_rounded, "누적 방문", "${stats['count']}회", Colors.white),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterTab(String label, String value) {
    final bool isActive = _statsFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _statsFilter = value;
          if (value != 'Friends') _selectedFriend = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.primaryGradient : null,
          color: isActive ? null : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          boxShadow: isActive
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24), const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500)), const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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

    return AppCard(
      onTap: () => _showEditSheet(doc),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: imageUrl != null 
                ? Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon())
                : _buildPlaceholderIcon(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3), overflow: TextOverflow.ellipsis)),
                    if (myRating > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), 
                        decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)), 
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: AppColors.accent), 
                            const SizedBox(width: 2),
                            Text("$myRating", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(6)),
                      child: Text(foodType, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Text(DateFormat('yy.MM.dd').format(visitDate), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
                if (taggedFriends.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.people_rounded, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(child: Text(taggedFriends.join(", "), style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                if (memo.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(memo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      width: 56, height: 56, 
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(AppTheme.radiusMd)), 
      child: const Icon(Icons.restaurant_rounded, color: AppColors.textTertiary),
    );
  }

  // 리스트 모드 (필터 포함)
  Widget _buildAllHistoryList(List<QueryDocumentSnapshot> allVisits) {
    final filteredVisits = _filterVisits(allVisits);

    return Column(
      children: [
        _buildStatisticsCard(allVisits),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                _statsFilter == 'All' ? '전체 기록' : _statsFilter == 'Solo' ? '혼자 방문' : _selectedFriend != null ? '$_selectedFriend님과' : '친구와 방문',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                child: Text('${filteredVisits.length}건', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),

        Expanded(
          child: filteredVisits.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.filter_list_off_rounded,
                  title: "해당하는 기록이 없어요",
                  subtitle: "필터 조건을 변경해보세요",
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: filteredVisits.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _buildListItem(filteredVisits[index]),
                ),
        ),
      ],
    );
  }

  // ─── 캘린더 모드 ───

  Widget _buildCalendarView(List<QueryDocumentSnapshot> allVisits) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // 캘린더 (상단 고정)
            Column(
              children: [
                TableCalendar(
                  locale: 'ko_KR',
                  firstDay: DateTime.utc(2000, 1, 1),
                  lastDay: DateTime.utc(2099, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  availableCalendarFormats: const {
                    CalendarFormat.month: '월',
                  },
                  eventLoader: (day) => _getEventsForDay(day, allVisits),
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() { 
                      _selectedDay = selectedDay; 
                      _focusedDay = focusedDay; 
                    });
                    // 선택한 날짜에 기록이 있으면 시트를 중간으로
                    final dayVisits = _getEventsForDay(selectedDay, allVisits);
                    if (dayVisits.isNotEmpty) {
                      _sheetController.animateTo(0.45, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                    }
                  },
                  onFormatChanged: (format) { if (_calendarFormat != format) setState(() => _calendarFormat = format); },
                  onPageChanged: (focusedDay) { setState(() { _focusedDay = focusedDay; }); },
                  onHeaderTapped: (_) => _selectYearMonth(context),
                  rowHeight: 52,
                  daysOfWeekHeight: 32,
                  headerStyle: const HeaderStyle(
                    titleCentered: true, 
                    formatButtonVisible: false, 
                    titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3), 
                    rightChevronIcon: Icon(Icons.chevron_right_rounded, color: AppColors.textPrimary), 
                    leftChevronIcon: Icon(Icons.chevron_left_rounded, color: AppColors.textPrimary),
                    headerPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  calendarStyle: CalendarStyle(
                    cellMargin: const EdgeInsets.all(4),
                    todayDecoration: BoxDecoration(color: AppColors.primary.withOpacity(0.3), shape: BoxShape.circle), 
                    selectedDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), 
                    markerDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    markerSize: 6,
                    markersMaxCount: 3,
                    todayTextStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                    selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    defaultTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    weekendTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.error),
                  ),
                  daysOfWeekStyle: const DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
                    weekendStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.error),
                  ),
                ),
              ],
            ),

            // DraggableScrollableSheet (기본: 중간)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.45,
              minChildSize: 0.06,
              maxChildSize: 0.85,
              snap: true,
              snapSizes: const [0.06, 0.45, 0.85],
              builder: (context, scrollController) {
                // 선택한 날짜 방문 기록
                final dayVisits = _selectedDay != null
                    ? _getEventsForDay(_selectedDay!, allVisits)
                    : <QueryDocumentSnapshot>[];
                // 해당 월 방문 기록
                final monthVisits = _getEventsForMonth(_focusedDay, allVisits);

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -4)),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      // 드래그 핸들
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // 선택한 날짜가 있고 방문 기록이 있으면 해당 날짜 표시
                      if (dayVisits.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('M월 d일', 'ko_KR').format(_selectedDay!),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                                child: Text('${dayVisits.length}곳', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                        ...dayVisits.map((doc) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          child: _buildListItem(doc),
                        )),
                        const Divider(height: 24, indent: 16, endIndent: 16, color: AppColors.divider),
                      ],

                      // "YYYY년 M월의 맛집들" — 원래 스타일
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Text(DateFormat('yyyy년 M월', 'ko_KR').format(_focusedDay), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                            const Text('의 맛집들', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), 
                              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusFull)), 
                              child: Text('${monthVisits.length}곳', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                      if (monthVisits.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(Icons.no_meals_rounded, size: 48, color: AppColors.textTertiary.withOpacity(0.4)),
                              const SizedBox(height: 12),
                              Text(
                                _getEmptyMessage(),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      else
                        ...monthVisits.map((doc) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          child: _buildListItem(doc),
                        )),
                      const SizedBox(height: 100),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || (user.isAnonymous && user.displayName == null)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('방문 기록')),
        body: EmptyStateWidget(
          icon: Icons.login_rounded,
          title: "로그인 후 방문 기록을 확인해보세요!",
          subtitle: "맛집 방문 기록을 캘린더로 관리해요",
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "가게 이름, 메모 검색...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  fillColor: Colors.transparent,
                  filled: true,
                ),
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: _runSearch,
              )
            : const Text('방문 기록'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded, color: AppColors.textPrimary),
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
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primarySurface, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusFull)), 
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text("오늘", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () { setState(() { _isListView = !_isListView; }); },
                    icon: Icon(_isListView ? Icons.calendar_month_rounded : Icons.list_alt_rounded, color: AppColors.textPrimary),
                    tooltip: _isListView ? "달력 보기" : "전체 목록 보기",
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
      body: ref.watch(userVisitsProvider).when(
        data: (allVisits) {
          _allDataCache = allVisits;

          if (_isSearching) {
            if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
              return EmptyStateWidget(icon: Icons.search_off_rounded, title: "검색 결과가 없습니다");
            }
            if (_searchResults.isEmpty && _searchController.text.isEmpty) {
              return EmptyStateWidget(icon: Icons.search_rounded, title: "검색어를 입력하세요");
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _searchResults.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _buildListItem(_searchResults[index]),
            );
          }

          if (_isListView) {
            return _buildAllHistoryList(allVisits);
          } else {
            return _buildCalendarView(allVisits);
          }
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (error, stack) => Center(child: Text('오류 발생: $error')),
      ),
    );
  }
}