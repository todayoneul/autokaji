import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:autokaji/screens/main_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autokaji/providers/location_provider.dart';
import 'package:autokaji/providers/visit_provider.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

class MapScreen extends ConsumerStatefulWidget {
  final TargetPlace? initialTarget;

  const MapScreen({super.key, this.initialTarget});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  String get kGoogleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  late GoogleMapController _googleMapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<dynamic> _placePredictions = [];
  Timer? _debounce;
  
  List<QueryDocumentSnapshot> _allVisits = []; 
  Set<Marker> _savedMarkers = {}; 
  Marker? _searchMarker;          

  bool _isFoodMode = true; 
  bool _showCategoryChips = true; 
  bool _areMarkersVisible = true; 

  final List<String> _foodCategories = ['전체', '한식', '중식', '일식', '양식', '디저트', '기타'];
  final List<String> _playCategories = ['전체', '실내', '실외', '테마파크', '영화/공연', '쇼핑', '기타'];
  
  String _selectedCategory = '전체';

  bool _isMapCreated = false;

  static const CameraPosition _defaultCityHall = CameraPosition(
    target: LatLng(37.5665, 126.9780),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTarget != null && widget.initialTarget != oldWidget.initialTarget) {
      if (_isMapCreated) {
        _updateTargetFromHome();
      }
    }
  }

  @override
  void dispose() {
    _googleMapController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<BitmapDescriptor> _createEmojiMarkerBitmap(String category) async {
    String emoji;
    switch (category) {
      case '한식': emoji = '🍚'; break;
      case '중식': emoji = '🥟'; break;
      case '일식': emoji = '🍣'; break;
      case '양식': emoji = '🍝'; break;
      case '디저트': emoji = '☕'; break;
      case '실내': emoji = '🎮'; break;
      case '실외': emoji = '🌳'; break;
      case '테마파크': emoji = '🎡'; break;
      case '영화/공연': emoji = '🎬'; break;
      case '쇼핑': emoji = '🛍️'; break;
      default:   emoji = '🍴'; break;
    }

    const Color bgColor = ui.Color.fromARGB(255, 255, 255, 255);
    final int size = 95; 
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    final ui.Paint paint = ui.Paint()..color = bgColor;
    final double radius = size / 2.0;

    canvas.drawCircle(Offset(radius, radius), radius, paint);

    final ui.Paint borderPaint = ui.Paint()
      ..color = const ui.Color.fromARGB(255, 255, 107, 107) // Coral border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(Offset(radius, radius), radius - 2, borderPaint);

    TextPainter painter = TextPainter(textDirection: ui.TextDirection.ltr);
    painter.text = TextSpan(text: emoji, style: TextStyle(fontSize: size * 0.7));
    painter.layout();
    painter.paint(canvas, Offset(radius - painter.width / 2, radius - painter.height / 2));

    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _applyFilter() async {
    if (!_areMarkersVisible) {
      if (mounted) setState(() => _savedMarkers = {});
      return;
    }

    final Set<Marker> newMarkers = {};

    for (var doc in _allVisits) {
      final data = doc.data() as Map<String, dynamic>;
      final String itemCategory = data['foodType'] ?? '기타';
      
      if (_isFoodMode) {
        if (_playCategories.contains(itemCategory) && itemCategory != '기타') continue;
      } else {
        if (_foodCategories.contains(itemCategory) && itemCategory != '기타') continue;
      }

      if (_selectedCategory == '전체' || _selectedCategory == itemCategory) {
        if (data['lat'] != null && data['lng'] != null) {
          final BitmapDescriptor icon = await _createEmojiMarkerBitmap(itemCategory);

          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'], data['lng']),
              icon: icon,
              onTap: () {
                _moveCamera(data['lat'], data['lng']);
                _showSaveDialog({
                  'name': data['storeName'],
                  'formatted_address': data['address'] ?? '',
                  'rating': null,
                  'photos': []
                }, data['lat'], data['lng']);
              },
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _savedMarkers = newMarkers;
      });
    }
  }

  Widget _buildModeSelectButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          _bigModeButton("🍚  뭐 먹지?", true),
          const SizedBox(width: 4),
          _bigModeButton("🎡  뭐 하지?", false),
        ],
      ),
    );
  }

  Widget _bigModeButton(String text, bool isFood) {
    final bool isSelected = _isFoodMode == isFood;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isFoodMode = isFood;
            _showCategoryChips = true; 
            _selectedCategory = '전체';  
          });
          _applyFilter();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: 44,
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))] : [],
          ),
          child: Center(
            child: Text(text, style: TextStyle(
              fontSize: 14, 
              fontWeight: FontWeight.w700, 
              color: isSelected ? Colors.white : AppColors.textSecondary,
            )),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final List<String> categories = _isFoodMode ? _foodCategories : _playCategories;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showCategoryChips = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppTheme.shadowSm,
                ),
                child: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textPrimary),
              ),
            ),
          ),
          ...categories.map((category) {
            final isSelected = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = category;
                  });
                  _applyFilter();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.primaryGradient : null,
                    color: isSelected ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : AppColors.border,
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))]
                        : AppTheme.shadowSm,
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _updateTargetFromHome() {
    final target = widget.initialTarget!;
    _moveCamera(target.lat, target.lng);
    _setSearchMarker(target.lat, target.lng, target.name);
    
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _showSaveDialog({
          'name': target.name,
          'formatted_address': '',
          'rating': 0.0,
          'photos': []
        }, target.lat, target.lng);
      }
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.isEmpty) { setState(() => _placePredictions = []); return; }
    
    String url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$kGoogleApiKey&language=ko&components=country:kr';
    
    try {
      final locationAsync = ref.read(locationProvider);
      if (locationAsync.hasValue && locationAsync.value != null) {
        final lat = locationAsync.value!.latitude;
        final lng = locationAsync.value!.longitude;
        url += '&location=$lat,$lng&radius=10000';
      }
    } catch (e) {
      debugPrint("위치 정보 로드 실패: $e");
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && mounted) setState(() => _placePredictions = data['predictions']);
      }
    } catch (e) { debugPrint("검색 오류: $e"); }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () { _fetchSuggestions(query); });
  }



  Future<void> _getPlaceDetails(String placeId, String description) async {
    setState(() {
      _searchController.text = description;
      _placePredictions = [];
    });
    _dismissKeyboard();

    final String url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name,rating,photos,formatted_address&key=$kGoogleApiKey';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && mounted) {
          final result = data['result'];
          final location = result['geometry']['location'];
          final double lat = location['lat'];
          final double lng = location['lng'];
          final String name = result['name'] ?? description;

          _moveCamera(lat, lng);
          _setSearchMarker(lat, lng, name);
          
          Future.delayed(const Duration(milliseconds: 500), () {
             if (mounted) _showSaveDialog(result, lat, lng);
          });
        }
      }
    } catch (e) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("장소 정보를 가져오지 못했습니다: $e")));
    }
  }

  String? _getPhotoUrl(List<dynamic>? photos) {
    if (photos == null || photos.isEmpty) return null;
    final String photoReference = photos[0]['photo_reference'];
    return 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$kGoogleApiKey';
  }

  void _moveCamera(double lat, double lng) {
    _googleMapController.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
  }

  void _setSearchMarker(double lat, double lng, String name) {
    setState(() {
      _searchMarker = Marker(
        markerId: const MarkerId("selected_place"),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: name),
        icon: BitmapDescriptor.defaultMarker,
      );
    });
  }

  void _dismissKeyboard() {
    if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _onMapInteraction() {
    _dismissKeyboard();
    if (_placePredictions.isNotEmpty) {
      setState(() => _placePredictions = []);
    }
  }


  void _showSaveDialog(Map<String, dynamic> placeData, double lat, double lng) {
    final String name = placeData['name'];
    final String address = placeData['formatted_address'] ?? "";
    final double? rating = placeData['rating']?.toDouble();
    final String? photoUrl = _getPhotoUrl(placeData['photos']);

    String selectedFoodType = '한식';
    DateTime selectedDate = DateTime.now();
    final List<String> saveCategories = ['한식', '중식', '일식', '양식', '디저트', '실내', '실외', '테마파크', '영화/공연', '쇼핑', '기타'];
    final Map<String, String> selectedFriends = {};

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final user = FirebaseAuth.instance.currentUser;
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4, 
              maxChildSize: 0.95, 
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (photoUrl != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), 
                          child: Stack(
                            children: [
                              Image.network(
                                photoUrl, 
                                height: 220, 
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (ctx, err, stack) => Container(height: 180, color: AppColors.surfaceVariant, child: const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary)),
                              ),
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else 
                        Column(
                          children: [
                            const BottomSheetHandle(),
                            Container(
                              height: 80, 
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                              ),
                              child: Center(child: Icon(Icons.store_rounded, size: 40, color: AppColors.textTertiary)),
                            ),
                          ],
                        ),
                      
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                            if (rating != null) 
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSurface,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                                      const SizedBox(width: 4),
                                      Text("$rating", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.accent)),
                                    ],
                                  ),
                                ),
                              ),
                            if (address.isNotEmpty) 
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(address, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ),
                            const SizedBox(height: 20),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _launchNaverWalk(lat, lng, name), 
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.naver, 
                                      foregroundColor: Colors.white, 
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                                    ), 
                                    icon: const Icon(Icons.directions_walk_rounded, size: 20), 
                                    label: const Text("네이버 도보", style: TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _launchNaverTransit(lat, lng, name), 
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.secondary, 
                                      foregroundColor: Colors.white, 
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                                    ), 
                                    icon: const Icon(Icons.directions_bus_rounded, size: 20), 
                                    label: const Text("대중교통", style: TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 28),
                            const Text("종류 선택", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8.0, runSpacing: 8.0, children: saveCategories.map((type) {
                              final isSelected = selectedFoodType == type;
                              return ChoiceChip(
                                label: Text(type),
                                selected: isSelected,
                                selectedColor: AppColors.primary,
                                backgroundColor: AppColors.surfaceVariant,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                                ),
                                checkmarkColor: Colors.white,
                                onSelected: (sel) { if (sel) setSheetState(() => selectedFoodType = type); },
                              );
                            }).toList()),
                            
                            const SizedBox(height: 24),
                            const Text("방문 날짜", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () async { 
                                final picked = await showDatePicker(
                                  context: context, 
                                  initialDate: selectedDate, 
                                  firstDate: DateTime(2020), 
                                  lastDate: DateTime.now(),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.light(primary: AppColors.primary),
                                      ),
                                      child: child!,
                                    );
                                  },
                                ); 
                                if (picked != null) setSheetState(() => selectedDate = picked); 
                              }, 
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16), 
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                ), 
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                  children: [
                                    Text(DateFormat('yyyy년 MM월 dd일').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            if (user != null && !(user.isAnonymous && user.displayName == null)) ...[
                              const Text("함께한 친구", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 10),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('friends').snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Text("등록된 친구가 없습니다.", style: TextStyle(color: AppColors.textTertiary, fontSize: 13));
                                  return Wrap(spacing: 8.0, runSpacing: 8.0, children: snapshot.data!.docs.map((doc) {
                                    final friendUid = doc.id;
                                    return StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance.collection('users').doc(friendUid).snapshots(),
                                      builder: (context, userSnapshot) {
                                        String dName = "로딩중...";
                                        if (userSnapshot.hasData && userSnapshot.data!.exists) dName = userSnapshot.data!['nickname'] ?? '알 수 없음';
                                        final isSelected = selectedFriends.containsKey(friendUid);
                                        return FilterChip(
                                          label: Text(dName),
                                          selected: isSelected,
                                          selectedColor: AppColors.primarySurface,
                                          backgroundColor: AppColors.surfaceVariant,
                                          labelStyle: TextStyle(
                                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                          checkmarkColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                                          ),
                                          onSelected: (sel) => setSheetState(() => sel ? selectedFriends[friendUid] = dName : selectedFriends.remove(friendUid)),
                                        );
                                      });
                                  }).toList());
                                }),
                              const SizedBox(height: 30),
                            ],
                            
                            SizedBox(
                              width: double.infinity,
                              child: AppGradientButton(
                                text: "방문 기록 저장하기",
                                icon: Icons.check_rounded,
                                onPressed: () => _saveVisitToFirestore(name, address, selectedFoodType, selectedDate, lat, lng, selectedFriends),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveVisitToFirestore(String name, String address, String foodType, DateTime date, double lat, double lng, Map<String, String> taggedFriends) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.isAnonymous && user.displayName == null)) {
      if (!mounted) return;
      showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXxl)),
          title: const Text("로그인 필요", style: TextStyle(fontWeight: FontWeight.w800)), 
          content: const Text("방문 기록을 저장하려면 로그인이 필요합니다."), 
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인", style: TextStyle(color: AppColors.primary)))],
        ),
      );
      return;
    }
    try {
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final myNickname = myDoc.data()?['nickname'] ?? user.email?.split('@')[0] ?? '친구';
      
      await ref.read(visitRepositoryProvider).saveVisit(
        uid: user.uid,
        userNickname: myNickname,
        storeName: name,
        address: address,
        foodType: foodType,
        visitDate: date,
        lat: lat,
        lng: lng,
        taggedFriends: taggedFriends,
      );

      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _searchMarker = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$name' 저장 완료!")));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("저장 실패: $e"))); }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<QueryDocumentSnapshot>>>(userVisitsProvider, (previous, next) {
      if (next.hasValue) {
        _allVisits = next.value!;
        _applyFilter();
      }
    });

    final locationAsync = ref.watch(locationProvider);

    CameraPosition initialCameraPosition = _defaultCityHall;
    if (locationAsync.hasValue && locationAsync.value != null) {
      initialCameraPosition = CameraPosition(
        target: LatLng(locationAsync.value!.latitude, locationAsync.value!.longitude),
        zoom: 16.0,
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          locationAsync.isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) 
              : GoogleMap(
            onMapCreated: (controller) { 
              _googleMapController = controller; 
              _isMapCreated = true;
              if (widget.initialTarget != null) {
                 _updateTargetFromHome();
              }
            },
            initialCameraPosition: initialCameraPosition,
            myLocationEnabled: true, myLocationButtonEnabled: true, zoomControlsEnabled: true, mapToolbarEnabled: false, compassEnabled: true,
            padding: const EdgeInsets.only(top: 100, bottom: 20),
            markers: _savedMarkers.union(_searchMarker != null ? {_searchMarker!} : {}),
            onTap: (_) => _onMapInteraction(),
            onCameraMoveStarted: () {
              _dismissKeyboard();
            },
          ),
          
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.95), 
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl), 
                      boxShadow: AppTheme.shadowMd,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController, 
                            focusNode: _searchFocusNode, 
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: "장소, 주소 검색", 
                              border: InputBorder.none, 
                              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary), 
                              suffixIcon: _searchController.text.isNotEmpty 
                                  ? IconButton(icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary), onPressed: () { _searchController.clear(); setState(() => _placePredictions = []); }) 
                                  : null, 
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              filled: false,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: _areMarkersVisible ? AppColors.primarySurface : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: IconButton(
                            icon: Icon(_areMarkersVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded, 
                              color: _areMarkersVisible ? AppColors.primary : AppColors.textTertiary, size: 22),
                            onPressed: () {
                              setState(() { _areMarkersVisible = !_areMarkersVisible; });
                              _applyFilter();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),
                  _showCategoryChips ? _buildCategoryChips() : _buildModeSelectButtons(),

                  if (_placePredictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.98), 
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg), 
                        boxShadow: AppTheme.shadowLg,
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _placePredictions.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (context, index) {
                          final prediction = _placePredictions[index];
                          return ListTile(
                            title: Text(
                              prediction['structured_formatting']?['main_text'] ?? prediction['description'], 
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: Text(
                              prediction['structured_formatting']?['secondary_text'] ?? "", 
                              overflow: TextOverflow.ellipsis, 
                              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                            ),
                            leading: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                              ),
                              child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
                            ),
                            onTap: () {
                              _getPlaceDetails(prediction['place_id'], prediction['description']);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  Future<void> _launchNaverWalk(double lat, double lng, String name) async {
    final locationAsync = ref.read(locationProvider);
    if (!locationAsync.hasValue || locationAsync.value == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')));
      return;
    }

    final Uri url = Uri(
      scheme: 'nmap',
      host: 'route',
      path: '/walk',
      queryParameters: {
        'slat': '${locationAsync.value!.latitude}',
        'slng': '${locationAsync.value!.longitude}',
        'sname': '현재 위치',
        'dlat': '$lat',
        'dlng': '$lng',
        'dname': name,
        'appname': 'com.gyuhan.autokaji',
      },
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (Platform.isIOS) await launchUrl(Uri.parse('https://apps.apple.com/kr/app/naver-map-navigation/id311867728'));
        else await launchUrl(Uri.parse('market://details?id=com.nhn.android.nmap'));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('네이버 지도 실행 오류: $e')));
    }
  }

  Future<void> _launchNaverTransit(double lat, double lng, String name) async {
    final locationAsync = ref.read(locationProvider);
    if (!locationAsync.hasValue || locationAsync.value == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')));
      return;
    }

    final Uri url = Uri(
      scheme: 'nmap',
      host: 'route',
      path: '/public',
      queryParameters: {
        'slat': '${locationAsync.value!.latitude}',
        'slng': '${locationAsync.value!.longitude}',
        'sname': '현재 위치',
        'dlat': '$lat',
        'dlng': '$lng',
        'dname': name,
        'appname': 'com.gyuhan.autokaji',
      },
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (Platform.isIOS) await launchUrl(Uri.parse('https://apps.apple.com/kr/app/naver-map-navigation/id311867728'));
        else await launchUrl(Uri.parse('market://details?id=com.nhn.android.nmap'));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('네이버 지도 실행 오류: $e')));
    }
  }
}