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

enum MapDisplayMode { mine, friends, all }

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
  
  List<QueryDocumentSnapshot> _myVisits = []; 
  List<QueryDocumentSnapshot> _friendVisits = []; 
  Set<Marker> _savedMarkers = {}; 
  Marker? _searchMarker;          

  MapDisplayMode _displayMode = MapDisplayMode.all;
  bool _isFoodMode = true; 
  bool _showCategoryChips = true; 
  bool _areMarkersVisible = true; 
  bool _showFilters = false; // 필터 UI 표시 여부

  final List<String> _foodCategories = ['전체', '한식', '중식', '일식', '양식', '디저트', '기타'];
  final List<String> _playCategories = ['전체', '실내', '실외', '테마파크', '영화/공연', '쇼핑', '기타'];
  
  String _selectedCategory = '전체';
  bool _isMapCreated = false;
  double _currentZoom = 16.0; // 현재 줌 레벨 추적

  static const CameraPosition _defaultCityHall = CameraPosition(
    target: LatLng(37.5665, 126.9780),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  void _loadInitialData() {
    final myVisitsAsync = ref.read(userVisitsProvider);
    final friendVisitsAsync = ref.read(friendsVisitsProvider);

    if (myVisitsAsync.hasValue) {
      setState(() => _myVisits = myVisitsAsync.value!);
    }
    if (friendVisitsAsync.hasValue) {
      setState(() => _friendVisits = friendVisitsAsync.value!);
    }
    _applyFilter();
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
    if (_isMapCreated) _googleMapController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// 줌 레벨에 따라 동적으로 마커 크기 계산 (더 작게 조정)
  int _getDynamicMarkerSize() {
    if (_currentZoom >= 16) return 40; // 45 -> 40
    if (_currentZoom >= 14) return 34; // 38 -> 34
    if (_currentZoom >= 12) return 28; // 30 -> 28
    return 22; // 24 -> 22
  }

  Future<BitmapDescriptor> _createEmojiMarkerBitmap(String category, {bool isFriend = false}) async {
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

    final int size = _getDynamicMarkerSize();
    final double radius = size / 2.0;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    
    // 배경 그림자
    if (size > 25) {
      canvas.drawCircle(
        Offset(radius, radius + 1), 
        radius - 1, 
        ui.Paint()
          ..color = Colors.black.withOpacity(0.12)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.5)
      );
    }
    
    // 배경 흰색 원
    canvas.drawCircle(Offset(radius, radius), radius - 1, ui.Paint()..color = Colors.white);

    // 테두리
    final ui.Paint borderPaint = ui.Paint()
      ..color = isFriend ? const Color(0xFF9C27B0) : const Color(0xFFFF5252)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size > 35 ? 2.0 : 1.5;
    canvas.drawCircle(Offset(radius, radius), radius - 1.5, borderPaint);

    // 이모지 텍스트 페인터
    TextPainter painter = TextPainter(textDirection: ui.TextDirection.ltr);
    painter.text = TextSpan(
      text: emoji, 
      style: TextStyle(
        fontSize: size * 0.55, 
        height: 1.0,
      )
    );
    painter.layout();

    // 중앙 정렬 계산 (이모지 특성상 미세하게 위로 조정)
    final double xOffset = radius - (painter.width / 2);
    final double yOffset = radius - (painter.height / 2);
    painter.paint(canvas, Offset(xOffset, yOffset));

    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  Future<void> _applyFilter() async {
    if (!_areMarkersVisible) {
      if (mounted) setState(() => _savedMarkers = {});
      return;
    }

    final Set<Marker> newMarkers = {};
    final String? myUid = FirebaseAuth.instance.currentUser?.uid;
    
    List<QueryDocumentSnapshot> displayData = [];
    if (_displayMode == MapDisplayMode.mine || _displayMode == MapDisplayMode.all) {
      displayData.addAll(_myVisits);
    }
    if (_displayMode == MapDisplayMode.friends || _displayMode == MapDisplayMode.all) {
      displayData.addAll(_friendVisits);
    }

    for (var doc in displayData) {
      final data = doc.data() as Map<String, dynamic>;
      final String itemCategory = data['foodType'] ?? '기타';
      final String itemUid = data['uid'] ?? '';
      final bool isFriendMarker = itemUid != myUid;
      
      if (_isFoodMode) {
        if (_playCategories.contains(itemCategory) && itemCategory != '기타') continue;
      } else {
        if (_foodCategories.contains(itemCategory) && itemCategory != '기타') continue;
      }

      if (_selectedCategory == '전체' || _selectedCategory == itemCategory) {
        if (data['lat'] != null && data['lng'] != null) {
          final BitmapDescriptor icon = await _createEmojiMarkerBitmap(itemCategory, isFriend: isFriendMarker);

          newMarkers.add(
            Marker(
              markerId: MarkerId("${doc.id}_${isFriendMarker ? 'f' : 'm'}"),
              position: LatLng(data['lat'], data['lng']),
              icon: icon,
              onTap: () {
                _moveCamera(data['lat'], data['lng']);
                _showPlaceDetail(data, isFriend: isFriendMarker);
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

  void _showPlaceDetail(Map<String, dynamic> data, {bool isFriend = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          boxShadow: AppTheme.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFriend ? Colors.purple.withOpacity(0.1) : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isFriend ? "${data['userNickname'] ?? '친구'}의 추천" : "나의 기록",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isFriend ? Colors.purple : AppColors.primary),
                  ),
                ),
                const Spacer(),
                Text(
                  data['visitDate'] != null 
                    ? DateFormat('yyyy.MM.dd').format((data['visitDate'] as Timestamp).toDate())
                    : '',
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(data['storeName'] ?? '장소명 없음', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(data['address'] ?? '', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            if (data['memo'] != null && data['memo'].toString().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                child: Text("💬 ${data['memo']}", style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppGradientButton(
                    text: "길찾기",
                    height: 50,
                    onPressed: () => _launchNaverWalk(data['lat'], data['lng'], data['storeName']),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayModeToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildModeChip("🏠 모두 보기", MapDisplayMode.all),
          const SizedBox(width: 8),
          _buildModeChip("👤 나의 기록", MapDisplayMode.mine),
          const SizedBox(width: 8),
          _buildModeChip("👫 친구 기록", MapDisplayMode.friends),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, MapDisplayMode mode) {
    final isSelected = _displayMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _displayMode = mode);
        _applyFilter();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)] : AppTheme.shadowSm,
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.borderLight),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13),
          ),
        ),
      ),
    );
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
                            if (user != null && !user.isAnonymous) ...[
                              const Text("함께한 친구", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 10),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('friends').snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Text("등록된 친구가 없습니다.", style: TextStyle(color: AppColors.textTertiary, fontSize: 13));
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
    if (user == null || user.isAnonymous) {
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
        setState(() => _myVisits = next.value!);
        _applyFilter();
      }
    });
    
    ref.listen<AsyncValue<List<QueryDocumentSnapshot>>>(friendsVisitsProvider, (previous, next) {
      if (next.hasValue) {
        setState(() => _friendVisits = next.value!);
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
              _loadInitialData();
              if (widget.initialTarget != null) {
                 _updateTargetFromHome();
              }
            },
            initialCameraPosition: initialCameraPosition,
            myLocationEnabled: true, myLocationButtonEnabled: true, zoomControlsEnabled: true, mapToolbarEnabled: false, compassEnabled: true,
            padding: const EdgeInsets.only(top: 140, bottom: 20),
            markers: _savedMarkers.union(_searchMarker != null ? {_searchMarker!} : {}),
            onTap: (_) => _onMapInteraction(),
            onCameraMove: (position) {
              // 줌 레벨이 정수 단위로 크게 변할 때만 마커 갱신 (성능 고려)
              if ((position.zoom - _currentZoom).abs() > 0.5) {
                _currentZoom = position.zoom;
                _applyFilter();
              }
            },
            onCameraMoveStarted: () => _dismissKeyboard(),
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
                          margin: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            icon: Icon(
                              _showFilters ? Icons.tune_rounded : Icons.filter_list_rounded, 
                              color: _showFilters ? AppColors.primary : AppColors.textSecondary,
                              size: 22,
                            ),
                            onPressed: () {
                              setState(() { _showFilters = !_showFilters; });
                            },
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

                  if (_showFilters) ...[
                    _buildDisplayModeToggle(),
                    const SizedBox(height: 4),
                    _showCategoryChips ? _buildCategoryChips() : _buildModeSelectButtons(),
                  ],

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
                            title: Text(prediction['structured_formatting']?['main_text'] ?? prediction['description'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: Text(prediction['structured_formatting']?['secondary_text'] ?? "", overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                            leading: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                              child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
                            ),
                            onTap: () => _getPlaceDetails(prediction['place_id'], prediction['description']),
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
    if (!locationAsync.hasValue || locationAsync.value == null) return;
    final Uri url = Uri(scheme: 'nmap', host: 'route', path: '/walk', queryParameters: {
      'slat': '${locationAsync.value!.latitude}', 'slng': '${locationAsync.value!.longitude}', 'sname': '현재 위치',
      'dlat': '$lat', 'dlng': '$lng', 'dname': name, 'appname': 'com.gyuhan.autokaji',
    });
    try {
      if (await canLaunchUrl(url)) await launchUrl(url);
      else await launchUrl(Uri.parse(Platform.isIOS ? 'https://apps.apple.com/kr/app/naver-map-navigation/id311867728' : 'market://details?id=com.nhn.android.nmap'));
    } catch (_) {}
  }

  Future<void> _launchNaverTransit(double lat, double lng, String name) async {
    final locationAsync = ref.read(locationProvider);
    if (!locationAsync.hasValue || locationAsync.value == null) return;
    final Uri url = Uri(scheme: 'nmap', host: 'route', path: '/public', queryParameters: {
      'slat': '${locationAsync.value!.latitude}', 'slng': '${locationAsync.value!.longitude}', 'sname': '현재 위치',
      'dlat': '$lat', 'dlng': '$lng', 'dname': name, 'appname': 'com.gyuhan.autokaji',
    });
    try {
      if (await canLaunchUrl(url)) await launchUrl(url);
      else await launchUrl(Uri.parse(Platform.isIOS ? 'https://apps.apple.com/kr/app/naver-map-navigation/id311867728' : 'market://details?id=com.nhn.android.nmap'));
    } catch (_) {}
  }
}
