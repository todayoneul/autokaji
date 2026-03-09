import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:autokaji/theme/app_colors.dart';
import 'package:autokaji/theme/app_theme.dart';
import 'package:autokaji/services/place_search_service.dart';
import 'package:autokaji/providers/wishlist_provider.dart';

/// 핫플레이스 카드용 스켈레톤 로딩 위젯
class HotPlaceShimmer extends StatelessWidget {
  const HotPlaceShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이미지 영역
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
            const SizedBox(width: 16),
            // 정보 영역
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 120, height: 18, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: double.infinity, height: 14, color: Colors.white),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(width: 40, height: 14, color: Colors.white),
                      const SizedBox(width: 12),
                      Container(width: 60, height: 14, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 전체에서 사용하는 공통 그라데이션 버튼
class AppGradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onPressed; // Alias for onTap
  final bool isLoading;
  final double? width;
  final double height;
  final IconData? icon;
  final Gradient? gradient;

  const AppGradientButton({
    super.key,
    required this.text,
    this.onTap,
    this.onPressed,
    this.isLoading = false,
    this.width,
    this.height = 56,
    this.icon,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTap = onTap ?? onPressed;
    
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: (gradient?.colors.first ?? AppColors.primary).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : effectiveTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 통일된 카드 위젯
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? backgroundColor;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.backgroundColor,
    this.border,
    this.boxShadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(AppTheme.spacing16),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.cardBackground,
          borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusXl),
          border: border ?? Border.all(color: AppColors.borderLight),
          boxShadow: boxShadow ?? AppTheme.shadowSm,
        ),
        child: child,
      ),
    );
  }
}

/// 선택 가능한 칩 위젯 (애니메이션 토글)
class AppSelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const AppSelectableChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.border,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppTheme.shadowSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 통일된 바텀시트 드래그 핸들
class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 글래스모피즘 효과 컨테이너
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final double blur;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blur = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusLg),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 빈 상태 위젯
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppColors.primary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: AppTheme.spacing20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.spacing8),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 섹션 헤더 위젯
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

/// 찜하기 폴더 선택 다이얼로그
class WishlistFolderDialog extends ConsumerStatefulWidget {
  final PlaceResult place;

  const WishlistFolderDialog({super.key, required this.place});

  @override
  ConsumerState<WishlistFolderDialog> createState() => _WishlistFolderDialogState();
}

class _WishlistFolderDialogState extends ConsumerState<WishlistFolderDialog> {
  late List<String> _selectedTags;
  late List<String> _selectedFriendIds;
  final TextEditingController _tagController = TextEditingController();
  final List<String> _defaultFolders = ['데이트 후보', '나의 또간집', '가고싶은곳', '회식장소'];

  @override
  void initState() {
    super.initState();
    _selectedTags = List<String>.from(widget.place.tags);
    _selectedFriendIds = [];
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _toggleFriend(String uid) {
    setState(() {
      if (_selectedFriendIds.contains(uid)) {
        _selectedFriendIds.remove(uid);
      } else {
        _selectedFriendIds.add(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allTagsAsync = ref.watch(wishlistTagsProvider);
    final friendsAsync = ref.watch(friendsProvider);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXl)),
      title: const Text('찜하기 설정', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.place.name,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 20),
              
              // 1. 폴더 선택
              const Text('폴더 선택', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              allTagsAsync.when(
                data: (tags) {
                  final combinedTags = {..._defaultFolders, ...tags}.toList()..sort();
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: combinedTags.map((tag) => FilterChip(
                      label: Text(tag),
                      selected: _selectedTags.contains(tag),
                      onSelected: (_) => _toggleTag(tag),
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _selectedTags.contains(tag) ? AppColors.primary : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: _selectedTags.contains(tag) ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: AppColors.cardBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        side: BorderSide(color: _selectedTags.contains(tag) ? AppColors.primary : AppColors.borderLight),
                      ),
                    )).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) {
                  debugPrint("태그 로딩 에러: $err");
                  // 에러 발생 시 기본 태그만이라도 표시
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _defaultFolders.map((tag) => FilterChip(
                      label: Text(tag),
                      selected: _selectedTags.contains(tag),
                      onSelected: (_) => _toggleTag(tag),
                      backgroundColor: AppColors.cardBackground,
                    )).toList(),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      decoration: InputDecoration(
                        hintText: '새 폴더 이름',
                        hintStyle: TextStyle(color: AppColors.textTertiary.withOpacity(0.6), fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          _toggleTag(val.trim());
                          _tagController.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      if (_tagController.text.trim().isNotEmpty) {
                        _toggleTag(_tagController.text.trim());
                        _tagController.clear();
                      }
                    },
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              
              // 2. 친구 태그
              const Text('같이 가고 싶은 친구 태그', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              friendsAsync.when(
                data: (friends) {
                  if (friends.isEmpty) {
                    return const Text('등록된 친구가 없습니다.', style: TextStyle(fontSize: 12, color: AppColors.textTertiary));
                  }
                  return SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: friends.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final bool isSelected = _selectedFriendIds.contains(friend['uid']);
                        
                        return GestureDetector(
                          onTap: () => _toggleFriend(friend['uid']),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isSelected ? AppColors.primary : AppColors.borderLight,
                                    backgroundImage: friend['photoUrl'] != null 
                                        ? NetworkImage(friend['photoUrl']) 
                                        : null,
                                    child: friend['photoUrl'] == null 
                                        ? const Icon(Icons.person, color: Colors.white) 
                                        : null,
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                        child: const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                friend['nickname'],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('친구를 불러올 수 없습니다.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () {
            ref.read(wishlistToggleProvider)(
              widget.place, 
              false, 
              tags: _selectedTags,
              taggedUserIds: _selectedFriendIds,
            );
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${widget.place.name}"이(가) 저장되었습니다.'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.primary,
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          ),
          child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
