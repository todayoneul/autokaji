import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
  
  // [필터] 원본 데이터와 표시 마커 분리
  List<QueryDocumentSnapshot> _allVisits = []; 
  Set<Marker> _savedMarkers = {}; 
  Marker? _searchMarker;

  final List<String> _categories = ['전체', '한식', '중식', '일식', '양식', '디저트', '기타'];
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
      _updateTargetFromHome();
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

  // [필터] 마커 색상 반환
  double _getMarkerHue(String foodType) {
    switch (foodType) {
      case '한식': return BitmapDescriptor.hueAzure;
      case '중식': return BitmapDescriptor.hueRed;
      case '일식': return BitmapDescriptor.hueOrange;
      case '양식': return BitmapDescriptor.hueGreen;
      case '디저트': return BitmapDescriptor.hueViolet;
      default: return BitmapDescriptor.hueYellow;
    }
  }

  // [필터] 필터링 로직
  void _applyFilter() {
    final Set<Marker> newMarkers = {};

    for (var doc in _allVisits) {
      final data = doc.data() as Map<String, dynamic>;
      final String foodType = data['foodType'] ?? '기타';

      if (_selectedCategory == '전체' || _selectedCategory == foodType) {
        if (data['lat'] != null && data['lng'] != null) {
          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'], data['lng']),
              infoWindow: InfoWindow(
                title: data['storeName'],
                snippet: foodType,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(_getMarkerHue(foodType)),
              onTap: () {
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

    setState(() {
      _savedMarkers = newMarkers;
    });
  }

  Future<void> _initializeMap() async {
    if (widget.initialTarget != null) {
      _setInitialTarget(widget.initialTarget!);
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('위치 서비스 꺼짐');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('권한 거부');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('영구 거부');

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
      if (mounted) {
        setState(() {
          _initialCameraPosition = _defaultCityHall;
          _isMapLoading = false;
        });
      }
      debugPrint("위치 초기화 오류: $e");
    }
  }

  void _setInitialTarget(TargetPlace target) {
    setState(() {
      _initialCameraPosition = CameraPosition(
        target: LatLng(target.lat, target.lng),
        zoom: 16.0,
      );
      _searchMarker = Marker(
        markerId: const MarkerId("selected_place"),
        position: LatLng(target.lat, target.lng),
        infoWindow: InfoWindow(title: target.name),
        icon: BitmapDescriptor.defaultMarker,
      );
      _isMapLoading = false;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
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

  void _updateTargetFromHome() {
    final target = widget.initialTarget!;
    _moveCamera(target.lat, target.lng);
    _setSearchMarker(target.lat, target.lng, target.name);
    
    Future.delayed(const Duration(milliseconds: 500), () {
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
    if (user == null || user.isAnonymous) return;

    FirebaseFirestore.instance
        .collection('visits')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      
      _allVisits = snapshot.docs;
      if (mounted) {
        _applyFilter();
      }
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() => _placePredictions = []);
      return;
    }
    final String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$kGoogleApiKey&language=ko&components=country:kr';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && mounted) {
          setState(() {
            _placePredictions = data['predictions'];
          });
        }
      }
    } catch (e) {
      debugPrint("검색 오류: $e");
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _getPlaceDetails(String placeId, String description) async {
    setState(() {
      _searchController.text = description;
    });

    final String url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name,rating,photos,formatted_address&key=$kGoogleApiKey';

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
          _showSaveDialog(result, lat, lng);
        }
      }
    } catch (e) {
      debugPrint("상세 정보 오류: $e");
    }
  }

  String? _getPhotoUrl(List<dynamic>? photos) {
    if (photos == null || photos.isEmpty) return null;
    final String photoReference = photos[0]['photo_reference'];
    return 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$kGoogleApiKey';
  }

  void _moveCamera(double lat, double lng) {
    _googleMapController.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
    );
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

  // [터치 로직] 지도 누를 때만 닫기 (리스트 클릭 시엔 안 닫힘)
  void _onMapInteraction() {
    _dismissKeyboard();
    if (_placePredictions.isNotEmpty) {
      setState(() {
        _placePredictions = [];
      });
    }
  }

  Future<void> _launchNaverMap(double lat, double lng, String name) async {
    final url = Uri.parse(
        'nmap://route/public?dlat=$lat&dlng=$lng&dname=$name&appname=com.gyuhan.autokaji');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (Platform.isIOS) {
          await launchUrl(Uri.parse('https://apps.apple.com/kr/app/naver-map-navigation/id311867728'));
        } else {
          await launchUrl(Uri.parse('market://details?id=com.nhn.android.nmap'));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("네이버 지도 실행 중 오류: $e")),
        );
      }
    }
  }

  Future<void> _saveVisitToFirestore(
      String name, String address, String foodType, DateTime date, double lat, double lng, Map<String, String> taggedFriends) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("로그인 필요"),
          content: const Text("방문 기록을 저장하려면 로그인이 필요합니다.\n설정 탭에서 로그인 해주세요."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("확인", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': user.uid,
        'storeName': name,
        'address': address,
        'foodType': foodType,
        'visitDate': Timestamp.fromDate(date),
        'createdAt': FieldValue.serverTimestamp(),
        'lat': lat,
        'lng': lng,
        'taggedFriends': taggedFriends.values.toList(),
      });

      final myDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final myNickname = myDoc.data()?['nickname'] ?? user.email?.split('@')[0] ?? '친구';

      for (var entry in taggedFriends.entries) {
        final friendUid = entry.key;
        await FirebaseFirestore.instance.collection('tag_requests').add({
          'fromUid': user.uid,
          'fromNickname': myNickname,
          'toUid': friendUid,
          'storeName': name,
          'address': address,
          'foodType': foodType,
          'visitDate': Timestamp.fromDate(date),
          'lat': lat,
          'lng': lng,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
      
      setState(() {
        _searchMarker = null;
      });
      
      String msg = "'$name' 저장 완료!";
      if (taggedFriends.isNotEmpty) {
        msg += "\n친구에게 태그 요청을 보냈습니다.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 실패: $e")),
      );
    }
  }

  void _showSaveDialog(Map<String, dynamic> placeData, double lat, double lng) {
    final String name = placeData['name'];
    final String address = placeData['formatted_address'] ?? "";
    final double? rating = placeData['rating']?.toDouble();
    final String? photoUrl = _getPhotoUrl(placeData['photos']);

    String selectedFoodType = '한식';
    DateTime selectedDate = DateTime.now();
    final List<String> foodTypes = ['한식', '중식', '일식', '양식', '디저트', '기타'];
    
    final Map<String, String> selectedFriends = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final user = FirebaseAuth.instance.currentUser;
            
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (photoUrl != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: Image.network(
                            photoUrl,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => Container(
                                height: 150, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                          ),
                        ),
                      
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            if (rating != null)
                              Row(children: [
                                const Icon(Icons.star, color: Colors.amber, size: 18),
                                Text(" $rating", style: const TextStyle(fontWeight: FontWeight.bold)),
                              ]),
                            const SizedBox(height: 20),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _launchNaverMap(lat, lng, name);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF03C75A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text("네이버 지도로 길찾기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 24),

                            const Text("음식 종류", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8.0,
                              children: foodTypes.map((type) {
                                return ChoiceChip(
                                  label: Text(type),
                                  selected: selectedFoodType == type,
                                  selectedColor: Colors.black,
                                  labelStyle: TextStyle(
                                    color: selectedFoodType == type ? Colors.white : Colors.black,
                                  ),
                                  onSelected: (selected) {
                                    if (selected) {
                                      setSheetState(() {
                                        selectedFoodType = type;
                                      });
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            const Text("방문 날짜", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null && picked != selectedDate) {
                                  setSheetState(() {
                                    selectedDate = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      DateFormat('yyyy년 MM월 dd일').format(selectedDate),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            if (user != null && !user.isAnonymous) ...[
                              const Text("함께한 친구 (태그)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .collection('friends')
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return const Text("등록된 친구가 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 13));
                                  }
                                  
                                  final friends = snapshot.data!.docs;
                                  return Wrap(
                                    spacing: 8.0,
                                    children: friends.map((doc) {
                                      final friendUid = doc.id;
                                      
                                      return StreamBuilder<DocumentSnapshot>(
                                        stream: FirebaseFirestore.instance.collection('users').doc(friendUid).snapshots(),
                                        builder: (context, userSnapshot) {
                                          String displayName = "로딩중...";
                                          if (userSnapshot.hasData && userSnapshot.data!.exists) {
                                            final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                                            displayName = userData['nickname'] ?? '알 수 없음';
                                          } else {
                                            final friendData = doc.data() as Map<String, dynamic>;
                                            displayName = friendData['nickname'] ?? '친구';
                                          }

                                          final isSelected = selectedFriends.containsKey(friendUid);

                                          return FilterChip(
                                            label: Text(displayName),
                                            selected: isSelected,
                                            selectedColor: Colors.blue[100],
                                            checkmarkColor: Colors.blue,
                                            onSelected: (selected) {
                                              setSheetState(() {
                                                if (selected) {
                                                  selectedFriends[friendUid] = displayName;
                                                } else {
                                                  selectedFriends.remove(friendUid);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 30),
                            ],
                            
                            ElevatedButton(
                              onPressed: () {
                                _saveVisitToFirestore(
                                  name, 
                                  address, 
                                  selectedFoodType, 
                                  selectedDate, 
                                  lat, 
                                  lng, 
                                  selectedFriends
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text("방문 기록 저장하기"),
                            )
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. 지도 영역 (여기를 누를 때만 리스트 닫힘)
          GestureDetector(
            onTap: _onMapInteraction,
            child: _isMapLoading
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    onMapCreated: (controller) {
                      _googleMapController = controller;
                    },
                    initialCameraPosition: _initialCameraPosition!,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: true,
                    compassEnabled: true,
                    padding: const EdgeInsets.only(
                      top: 100,
                      bottom: 20,
                    ),
                    markers: _savedMarkers.union(
                      _searchMarker != null ? {_searchMarker!} : {},
                    ),
                    // 지도 움직일 때도 리스트 닫기
                    onCameraMoveStarted: () => _onMapInteraction(),
                    onTap: (_) => _onMapInteraction(),
                  ),
          ),

          // 2. 상단 검색창 및 필터 (여기는 터치해도 안 닫힘)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: "장소, 주소 검색",
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search, color: Colors.black54),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _placePredictions = []);
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  // 필터 칩
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: _categories.map((category) {
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
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                            checkmarkColor: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  if (_placePredictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _placePredictions.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final prediction = _placePredictions[index];
                          final String mainText = prediction['structured_formatting']?['main_text'] ?? prediction['description'];
                          final String secondaryText = prediction['structured_formatting']?['secondary_text'] ?? "";

                          return ListTile(
                            title: Text(mainText, overflow: TextOverflow.ellipsis),
                            subtitle: secondaryText.isNotEmpty ? Text(secondaryText, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)) : null,
                            leading: const Icon(Icons.location_on, color: Colors.grey),
                            // [터치 로직 핵심] 키보드만 내리고, 리스트는 유지한 채 로딩
                            onTap: () async {
                              _dismissKeyboard();
                              await _getPlaceDetails(
                                prediction['place_id'],
                                prediction['description'],
                              );
                              // 로딩 완료 후 리스트 닫기
                              setState(() {
                                _placePredictions = [];
                              });
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