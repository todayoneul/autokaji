import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';

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

  Future<void> _copyToMyList(Map<String, dynamic> data) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'uid': myUid,
        'storeName': data['storeName'],
        'address': data['address'] ?? '',
        'foodType': data['foodType'],
        'visitDate': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'lat': data['lat'],
        'lng': data['lng'],
        'memo': "친구(${widget.friendNickname}) 추천으로 저장함",
        'imageUrl': data['imageUrl'],
        'myRating': 0.0,
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

  void _showDetailDialog(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: Stack(
                        children: [
                          Image.network(
                            imageUrl,
                            height: 200,
                            fit: BoxFit.cover,
                            width: double.infinity,
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
                    ),
                  if (imageUrl == null) const BottomSheetHandle(),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(storeName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 10),
                        if (rating > 0)
                          Container(
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
                                Text("$rating", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
                              ],
                            ),
                          ),
                        if (rating == 0)
                          Text("평가 없음", style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("친구의 한마디", style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(memo.isEmpty ? "남긴 메모가 없습니다." : memo, style: const TextStyle(fontSize: 15, height: 1.5)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        
                        SizedBox(
                          width: double.infinity,
                          child: AppGradientButton(
                            text: "나도 저장하기",
                            icon: Icons.bookmark_add_rounded,
                            gradient: AppColors.warmGradient,
                            onPressed: () => _copyToMyList(data),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("${widget.friendNickname}님의 맛집"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.map_rounded), text: "지도"),
            Tab(icon: Icon(Icons.list_rounded), text: "리스트"),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('visits')
            .where('uid', isEqualTo: widget.friendUid)
            .orderBy('visitDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("오류: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.restaurant_menu_rounded,
              title: "친구가 공유한 맛집이 아직 없어요",
              subtitle: "맛집을 기록하면 여기에 표시돼요",
            );
          }

          _markers = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(data['lat'] ?? 37.5, data['lng'] ?? 127.0),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(title: data['storeName']),
              onTap: () => _showDetailDialog(data),
            );
          }).toSet();

          return TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              GoogleMap(
                initialCameraPosition: _initialPosition,
                markers: _markers,
                onMapCreated: (controller) {
                  _mapController = controller;
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

              ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final visitDate = (data['visitDate'] as Timestamp).toDate();

                  return AppCard(
                    onTap: () => _showDetailDialog(data),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          child: data['imageUrl'] != null
                              ? Image.network(data['imageUrl'], width: 52, height: 52, fit: BoxFit.cover)
                              : Container(
                                  width: 52, height: 52,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                  ),
                                  child: const Icon(Icons.restaurant_rounded, color: AppColors.textTertiary),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['storeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(DateFormat('yyyy.MM.dd').format(visitDate), style: const TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
                      ],
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