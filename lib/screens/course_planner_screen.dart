import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/widgets/common_widgets.dart';
import 'package:autokaji/services/place_search_service.dart';
import 'package:url_launcher/url_launcher.dart';

class CoursePlannerScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String locationName;

  const CoursePlannerScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.locationName,
  });

  @override
  State<CoursePlannerScreen> createState() => _CoursePlannerScreenState();
}

class _CoursePlannerScreenState extends State<CoursePlannerScreen> {
  List<AICourse> _courses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    setState(() => _isLoading = true);
    final courses = await PlaceSearchService.generateAICourses(
      lat: widget.lat,
      lng: widget.lng,
    );
    if (mounted) {
      setState(() {
        _courses = courses;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.locationName} 코스', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchCourses,
            tooltip: '코스 다시 짜기',
          ),
        ],
      ),
      body: _isLoading ? _buildShimmerLoading() : _buildCourseList(),
    );
  }

  Widget _buildCourseList() {
    if (_courses.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.sentiment_dissatisfied_rounded,
        title: "코스를 생성하지 못했어요",
        subtitle: "주변에 충분한 장소가 없습니다. 다른 위치에서 시도해보세요.",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _courses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 32),
      itemBuilder: (context, index) {
        final course = _courses[index];
        return _buildCourseCard(course);
      },
    );
  }

  Widget _buildCourseCard(AICourse course) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(course.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(course.description, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 24),
          
          // 동적 단계 생성
          ...List.generate(course.steps.length, (i) {
            final place = course.steps[i];
            // 아이콘 및 색상 결정
            IconData icon = Icons.restaurant_rounded;
            Color color = Colors.orange;
            if (place.category.contains('카페') || place.category.contains('커피') || place.category.contains('디저트')) {
              icon = Icons.local_cafe_rounded;
              color = Colors.brown;
            } else if (place.category.contains('영화') || place.category.contains('놀거리') || place.category.contains('문화')) {
              icon = Icons.local_activity_rounded;
              color = Colors.blue;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineItem(place, '${i + 1}차', icon, color),
                if (i < course.steps.length - 1) _buildTimelineLine(),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
      child: Container(
        width: 2,
        height: 20,
        color: AppColors.border,
      ),
    );
  }

  Widget _buildTimelineItem(PlaceResult place, String step, IconData icon, Color color) {
    return InkWell(
      onTap: () async {
        if (place.placeUrl != null && place.placeUrl!.isNotEmpty) {
          final url = Uri.parse(place.placeUrl!);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        }
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                        child: Text(step, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(place.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(place.address, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(place.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(' (${place.reviewCount})', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      const SizedBox(width: 8),
                      Text(place.category, style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
            if (place.photoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(place.photoUrl!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_,__,___) => const SizedBox(width: 64)),
              )
          ],
        ),
      ),
    );
  }

  /// ─── 스켈레톤(Shimmer) 로딩 뷰 ───
  Widget _buildShimmerLoading() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 32),
      itemBuilder: (context, index) {
        return AppCard(
          padding: const EdgeInsets.all(20),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 200, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 12),
                Container(width: double.infinity, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 30),
                _buildShimmerItem(),
                _buildTimelineLine(),
                _buildShimmerItem(),
                _buildTimelineLine(),
                _buildShimmerItem(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerItem() {
    return Row(
      children: [
        Container(width: 42, height: 42, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 120, height: 18, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              Container(width: 180, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
      ],
    );
  }
}
