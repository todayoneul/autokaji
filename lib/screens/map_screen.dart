import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:autokaji/screens/main_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  final TargetPlace? initialTarget;

  const MapScreen({super.key, this.initialTarget});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String get kGoogleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  late GoogleMapController _googleMapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<dynamic> _placePredictions = [];
  Timer? _debounce;
  
  List<QueryDocumentSnapshot> _allVisits = []; 
  Set<Marker> _savedMarkers = {}; 
  Marker? _searchMarker;          

  // 상태 변수
  bool _isFoodMode = true; 
  bool _showCategoryChips = true; 
  bool _areMarkersVisible = true; 

  final List<String> _foodCategories = ['전체', '한식', '중식', '일식', '양식', '디저트', '기타'];
  final List<String> _playCategories = ['전체', '실내', '실외', '테마파크', '영화/공연', '쇼핑', '기타'];
  
  String _selectedCategory = '전체';

  CameraPosition? _initialCameraPosition;
  bool _isMapLoading = true;

  static const CameraPosition _defaultCityHall = CameraPosition(
    target: LatLng(37.5665, 126.9780),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _loadSavedMarkers();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTarget != null && widget.initialTarget != oldWidget.initialTarget) {
      if (!_isMapLoading) {
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

  // [이모지 마커 생성]
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
      ..color = const ui.Color.fromARGB(255, 255, 255, 255)
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
                  'photos': [] // 저장된 데이터엔 사진 정보가 없을 수 있음
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

  // --- UI 구성 ---
  Widget _buildModeSelectButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _bigModeButton("🍚  뭐 먹지?", Colors.blueAccent, true),
          const SizedBox(width: 12),
          _bigModeButton("🎡  뭐 하지?", Colors.orangeAccent, false),
        ],
      ),
    );
  }

  Widget _bigModeButton(String text, Color color, bool isFood) {
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
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Center(
            child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: const Icon(Icons.arrow_back, size: 20, color: Colors.black),
              ),
            ),
          ),
          ...categories.map((category) {
            final isSelected = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedCategory = category;
                    });
                    _applyFilter();
                  }
                },
                backgroundColor: Colors.white.withOpacity(0.9),
                selectedColor: Colors.black,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? Colors.black : Colors.grey[300]!),
                ),
                checkmarkColor: Colors.white,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // --- 맵 초기화 ---
  Future<void> _initializeMap() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setDefaultLocation();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setDefaultLocation();
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _initialCameraPosition = CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.0,
          );
          _isMapLoading = false;
        });
      }
    } catch (e) {
      _setDefaultLocation();
    }
  }

  void _setDefaultLocation() {
    if (mounted) {
      setState(() {
        _initialCameraPosition = _defaultCityHall;
        _isMapLoading = false;
      });
    }
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

  void _loadSavedMarkers() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.isAnonymous && user.displayName == null)) return;
    FirebaseFirestore.instance.collection('visits').where('uid', isEqualTo: user.uid).snapshots().listen((snapshot) {
      _allVisits = snapshot.docs;
      if (mounted) _applyFilter();
    });
  }

  // --- 검색 로직 ---
  Future<void> _fetchSuggestions(String input) async {
    if (input.isEmpty) { setState(() => _placePredictions = []); return; }
    final String url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$kGoogleApiKey&language=ko&components=country:kr';
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

  // [수정된 핵심 함수] 장소 상세 정보 가져오기 -> 지도 이동 -> 팝업 띄우기
  Future<void> _getPlaceDetails(String placeId, String description) async {
    // 1. 검색창에 텍스트 채우기 & 리스트 닫기
    setState(() {
      _searchController.text = description;
      _placePredictions = []; // 리스트 즉시 제거
    });
    _dismissKeyboard(); // 키보드 내리기

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

          // 2. 지도 이동 및 마커 표시
          _moveCamera(lat, lng);
          _setSearchMarker(lat, lng, name);
          
          // 3. 저장 팝업 띄우기 (사진 포함)
          // 지도가 이동하는 동안 약간의 딜레이를 주어 자연스럽게 띄움
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

  // 맵 배경 터치 시
  void _onMapInteraction() {
    _dismissKeyboard();
    if (_placePredictions.isNotEmpty) {
      setState(() => _placePredictions = []);
    }
  }

  Future<void> _launchNaverMap(double lat, double lng, String name) async {
    final url = Uri.parse('nmap://route/public?dlat=$lat&dlng=$lng&dname=$name&appname=com.gyuhan.autokaji');
    try {
      if (await canLaunchUrl(url)) { await launchUrl(url); }
      else {
        if (Platform.isIOS) await launchUrl(Uri.parse('https://apps.apple.com/kr/app/naver-map-navigation/id311867728'));
        else await launchUrl(Uri.parse('market://details?id=com.nhn.android.nmap'));
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("네이버 지도 실행 오류: $e"))); }
  }

  // [저장/상세보기 다이얼로그]
  void _showSaveDialog(Map<String, dynamic> placeData, double lat, double lng) {
    final String name = placeData['name'];
    final String address = placeData['formatted_address'] ?? "";
    final double? rating = placeData['rating']?.toDouble();
    // 사진 URL 가져오기
    final String? photoUrl = _getPhotoUrl(placeData['photos']);

    String selectedFoodType = '한식';
    DateTime selectedDate = DateTime.now();
    final List<String> saveCategories = ['한식', '중식', '일식', '양식', '디저트', '실내', '실외', '테마파크', '영화/공연', '쇼핑', '기타'];
    final Map<String, String> selectedFriends = {};

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final user = FirebaseAuth.instance.currentUser;
            return DraggableScrollableSheet(
              initialChildSize: 0.75, // 사진이 있으므로 높이를 좀 더 확보
              minChildSize: 0.4, 
              maxChildSize: 0.95, 
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // [사진 표시 영역]
                      if (photoUrl != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), 
                          child: Image.network(
                            photoUrl, 
                            height: 220, 
                            fit: BoxFit.cover, 
                            errorBuilder: (ctx, err, stack) => Container(height: 180, color: Colors.grey[200], child: const Icon(Icons.broken_image))
                          )
                        )
                      else 
                        Container(
                          height: 100, 
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          child: const Center(child: Icon(Icons.store, size: 40, color: Colors.grey)),
                        ),
                      
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 이름 및 평점
                            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            if (rating != null) 
                              Row(children: [const Icon(Icons.star, color: Colors.amber, size: 20), Text(" $rating", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                            const SizedBox(height: 8),
                            Text(address, style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 20),
                            
                            // 길찾기 버튼
                            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => _launchNaverMap(lat, lng, name), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF03C75A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.map_outlined), label: const Text("네이버 지도로 길찾기"))),
                            
                            const SizedBox(height: 24),
                            const Text("종류 선택", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            Wrap(spacing: 8.0, children: saveCategories.map((type) => ChoiceChip(label: Text(type), selected: selectedFoodType == type, selectedColor: Colors.black, labelStyle: TextStyle(color: selectedFoodType == type ? Colors.white : Colors.black), onSelected: (sel) { if (sel) setSheetState(() => selectedFoodType = type); })).toList()),
                            
                            const SizedBox(height: 20),
                            const Text("방문 날짜", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            InkWell(onTap: () async { final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now()); if (picked != null) setSheetState(() => selectedDate = picked); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('yyyy년 MM월 dd일').format(selectedDate)), const Icon(Icons.calendar_today, size: 18, color: Colors.grey)]))),
                            
                            const SizedBox(height: 20),
                            if (user != null && !(user.isAnonymous && user.displayName == null)) ...[
                              const Text("함께한 친구", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('friends').snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Text("등록된 친구가 없습니다.", style: TextStyle(color: Colors.grey));
                                  return Wrap(spacing: 8.0, children: snapshot.data!.docs.map((doc) {
                                    final friendUid = doc.id;
                                    return StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance.collection('users').doc(friendUid).snapshots(),
                                      builder: (context, userSnapshot) {
                                        String dName = "로딩중...";
                                        if (userSnapshot.hasData && userSnapshot.data!.exists) dName = userSnapshot.data!['nickname'] ?? '알 수 없음';
                                        final isSelected = selectedFriends.containsKey(friendUid);
                                        return FilterChip(label: Text(dName), selected: isSelected, onSelected: (sel) => setSheetState(() => sel ? selectedFriends[friendUid] = dName : selectedFriends.remove(friendUid)));
                                      });
                                  }).toList());
                                }),
                              const SizedBox(height: 30),
                            ],
                            
                            ElevatedButton(
                              onPressed: () => _saveVisitToFirestore(name, address, selectedFoodType, selectedDate, lat, lng, selectedFriends), 
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), 
                              child: const Text("방문 기록 저장하기")
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
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("로그인 필요"), content: const Text("방문 기록을 저장하려면 로그인이 필요합니다."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': user.uid, 'storeName': name, 'address': address, 'foodType': foodType, 'visitDate': Timestamp.fromDate(date), 'createdAt': FieldValue.serverTimestamp(), 'lat': lat, 'lng': lng, 'taggedFriends': taggedFriends.values.toList(),
      });
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final myNickname = myDoc.data()?['nickname'] ?? user.email?.split('@')[0] ?? '친구';
      for (var entry in taggedFriends.entries) {
        await FirebaseFirestore.instance.collection('tag_requests').add({
          'fromUid': user.uid, 'fromNickname': myNickname, 'toUid': entry.key, 'storeName': name, 'address': address, 'foodType': foodType, 'visitDate': Timestamp.fromDate(date), 'lat': lat, 'lng': lng, 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _searchMarker = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$name' 저장 완료!")));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("저장 실패: $e"))); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. 구글 맵
          _isMapLoading ? const Center(child: CircularProgressIndicator()) : GoogleMap(
            onMapCreated: (controller) { 
              _googleMapController = controller; 
              if (widget.initialTarget != null) {
                 _updateTargetFromHome();
              }
            },
            initialCameraPosition: _initialCameraPosition!,
            myLocationEnabled: true, myLocationButtonEnabled: true, zoomControlsEnabled: true, mapToolbarEnabled: false, compassEnabled: true,
            padding: const EdgeInsets.only(top: 100, bottom: 20),
            markers: _savedMarkers.union(_searchMarker != null ? {_searchMarker!} : {}),
            // 맵 배경을 터치했을 때만 검색 리스트와 키보드를 닫음
            onTap: (_) => _onMapInteraction(),
            onCameraMoveStarted: () {
              _dismissKeyboard();
            },
          ),
          
          // 2. 검색 UI 오버레이
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 검색바
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController, focusNode: _searchFocusNode, onChanged: _onSearchChanged,
                            decoration: InputDecoration(hintText: "장소, 주소 검색", border: InputBorder.none, prefixIcon: const Icon(Icons.search, color: Colors.black54), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { _searchController.clear(); setState(() => _placePredictions = []); }) : null, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                        IconButton(
                          icon: Icon(_areMarkersVisible ? Icons.visibility : Icons.visibility_off, color: _areMarkersVisible ? Colors.black : Colors.grey),
                          onPressed: () {
                            setState(() { _areMarkersVisible = !_areMarkersVisible; });
                            _applyFilter();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  _showCategoryChips ? _buildCategoryChips() : _buildModeSelectButtons(),

                  // [중요] 검색 결과 리스트 (Listener 제거됨)
                  if (_placePredictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))]),
                      child: ListView.separated(
                        padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _placePredictions.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final prediction = _placePredictions[index];
                          return ListTile(
                            title: Text(prediction['structured_formatting']?['main_text'] ?? prediction['description'], overflow: TextOverflow.ellipsis),
                            subtitle: Text(prediction['structured_formatting']?['secondary_text'] ?? "", overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            leading: const Icon(Icons.location_on, color: Colors.grey),
                            // 클릭 시 상세 정보 가져오기 -> 지도 이동 -> 저장 팝업
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
}