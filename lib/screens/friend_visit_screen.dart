import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendVisitScreen extends StatefulWidget {
  final String friendUid;
  final String friendNickname;

  const FriendVisitScreen({
    super.key,
    required this.friendUid,
    required this.friendNickname,
  });

  @override
  State<FriendVisitScreen> createState() => _FriendVisitScreenState();
}

class _FriendVisitScreenState extends State<FriendVisitScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  // 초기 위치 (서울)
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(37.5665, 126.9780),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // [기능] 내 DB로 데이터 복사 (퍼가기)
  Future<void> _copyToMyList(Map<String, dynamic> data) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': myUid,
        'storeName': data['storeName'],
        'address': data['address'] ?? '',
        'foodType': data['foodType'],
        'visitDate': FieldValue.serverTimestamp(), // 현재 시간으로 저장
        'createdAt': FieldValue.serverTimestamp(),
        'lat': data['lat'],
        'lng': data['lng'],
        'memo': "친구(${widget.friendNickname}) 추천으로 저장함",
        'imageUrl': data['imageUrl'],
        'myRating': 0.0, // 평점은 초기화
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("내 기록에 저장되었습니다!")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 실패: $e")),
      );
    }
  }

  // 친구 기록 상세 팝업
  void _showDetailDialog(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final String storeName = data['storeName'] ?? '이름 없음';
            final double rating = (data['myRating'] ?? 0).toDouble();
            final String memo = data['memo'] ?? '';
            final String? imageUrl = data['imageUrl'];

            return SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Image.network(
                        imageUrl,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(storeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            Text(" ${rating > 0 ? rating : '평가 없음'}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text("친구의 한마디:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(memo.isEmpty ? "남긴 메모가 없습니다." : memo, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 30),
                        
                        // [퍼가기 버튼]
                        ElevatedButton.icon(
                          onPressed: () => _copyToMyList(data),
                          icon: const Icon(Icons.bookmark_add),
                          label: const Text("나도 저장하기 (내 캘린더로 복사)"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.friendNickname}님의 맛집"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: "지도"),
            Tab(icon: Icon(Icons.list), text: "리스트"),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 친구의 UID로 방문 기록 조회
        stream: FirebaseFirestore.instance
            .collection('visits')
            .where('uid', isEqualTo: widget.friendUid)
            .orderBy('visitDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("오류: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("친구가 공유한 맛집이 아직 없어요."));
          }

          // 마커 생성
          _markers = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'] ?? 37.5, data['lng'] ?? 127.0),
              // [디자인] 친구 마커는 초록색
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(title: data['storeName']),
              onTap: () => _showDetailDialog(data),
            );
          }).toSet();

          return TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(), // 지도 제스처 충돌 방지
            children: [
              // [탭 1] 지도 보기
              GoogleMap(
                initialCameraPosition: _initialPosition,
                markers: _markers,
                onMapCreated: (controller) {
                  _mapController = controller;
                  // 데이터가 있으면 첫 번째 기록 위치로 이동
                  if (docs.isNotEmpty) {
                    final first = docs.first.data() as Map<String, dynamic>;
                    if (first['lat'] != null) {
                      controller.moveCamera(CameraUpdate.newLatLngZoom(
                        LatLng(first['lat'], first['lng']), 14,
                      ));
                    }
                  }
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
              ),

              // [탭 2] 리스트 보기
              ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final visitDate = (data['visitDate'] as Timestamp).toDate();

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      leading: data['imageUrl'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(data['imageUrl'], width: 50, height: 50, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.restaurant, color: Colors.grey),
                      title: Text(data['storeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('yyyy.MM.dd').format(visitDate)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showDetailDialog(data),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}