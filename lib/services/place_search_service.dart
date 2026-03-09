import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// 통합 장소 결과 모델
class PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final int reviewCount;
  final String category;
  final String source; // 'google', 'naver', 'kakao'
  final String? photoUrl;
  final String? placeUrl; // 네이버/카카오 상세 URL
  final String? placeId; // 구글 place_id
  final Map<String, dynamic>? rawData; // 원본 데이터
  final List<String> tags; // 찜한 폴더(태그) 목록

  /// 고유 식별자 (ID가 없으면 이름+좌표 조합)
  String get uniqueId => placeId ?? "${name}_${lat}_${lng}";

  PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.rating = 0,
    this.reviewCount = 0,
    this.category = '기타',
    required this.source,
    this.photoUrl,
    this.placeUrl,
    this.placeId,
    this.rawData,
    this.tags = const [],
  });

  /// 통합 점수 산출: (평점 × log10(리뷰수+1)) + 출처 보너스
  double get score {
    double base = rating * _log10(reviewCount + 1);
    if (source == 'naver') base += 0.5;
    if (source == 'kakao') base += 0.3;
    return base;
  }

  static double _log10(num x) {
    if (x <= 0) return 0;
    return math.log(x.toDouble()) / math.ln10;
  }

  /// Google Places API 형식으로 변환 (기존 다이얼로그와 호환)
  Map<String, dynamic> toGoogleFormat() {
    return rawData ?? {
      'name': name,
      'vicinity': address,
      'rating': rating,
      'user_ratings_total': reviewCount,
      'geometry': {
        'location': {'lat': lat, 'lng': lng}
      },
      'place_id': placeId,
      'source': source,
      'place_url': placeUrl,
    };
  }
}

/// 하이브리드 장소 검색 서비스
class PlaceSearchService {
  static String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static String get _naverClientId => dotenv.env['NAVER_CLIENT_ID'] ?? '';
  static String get _naverClientSecret => dotenv.env['NAVER_CLIENT_SECRET'] ?? '';
  static String get _kakaoRestApiKey => dotenv.env['KAKAO_REST_API_KEY'] ?? '';

  /// ─── 네이버 지역 검색 ───
  static Future<List<PlaceResult>> searchNaver({
    required String query,
    int display = 5,
    String sort = 'comment',
  }) async {
    if (_naverClientId.isEmpty || _naverClientSecret.isEmpty) {
      debugPrint('⚠️ 네이버 API 키 누락! ClientId: ${_naverClientId.isEmpty ? "비어있음" : "OK"}, Secret: ${_naverClientSecret.isEmpty ? "비어있음" : "OK"}');
      return [];
    }

    try {
      debugPrint('🟢 네이버 검색 시작: "$query"');
      final uri = Uri.parse(
        'https://openapi.naver.com/v1/search/local.json'
        '?query=${Uri.encodeComponent(query)}'
        '&display=$display'
        '&sort=$sort'
      );

      final response = await http.get(uri, headers: {
        'X-Naver-Client-Id': _naverClientId,
        'X-Naver-Client-Secret': _naverClientSecret,
      });

      debugPrint('🟢 네이버 응답: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['items'] ?? [];
        debugPrint('🟢 네이버 결과: ${items.length}건');

        return items.map((item) {
          final String title = _cleanHtml(item['title'] ?? '');
          final String address = item['roadAddress'] ?? item['address'] ?? '';
          final String category = item['category'] ?? '기타';
          final String link = item['link'] ?? '';
          
          // 네이버 mapx/mapy → WGS84 좌표 변환
          double lat = 0, lng = 0;
          final rawMapx = item['mapx'];
          final rawMapy = item['mapy'];
          if (rawMapx != null && rawMapy != null) {
            final mapxStr = rawMapx.toString();
            final mapyStr = rawMapy.toString();
            // 네이버 좌표: 정수형 (예: 1270640483 → 127.0640483)
            final mapx = double.tryParse(mapxStr) ?? 0;
            final mapy = double.tryParse(mapyStr) ?? 0;
            if (mapx > 1000) {
              lng = mapx / 10000000;
              lat = mapy / 10000000;
            } else {
              lng = mapx;
              lat = mapy;
            }
          }
          
          debugPrint('  🟢 $title (lat:$lat, lng:$lng)');

          return PlaceResult(
            name: title,
            address: address,
            lat: lat,
            lng: lng,
            rating: 0,
            reviewCount: 0,
            category: category,
            source: 'naver',
            placeUrl: link,
          );
        }).toList();
      } else {
        debugPrint('❌ 네이버 HTTP 에러: ${response.statusCode}');
        debugPrint('❌ 네이버 응답: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
      }
    } catch (e) {
      debugPrint('❌ 네이버 검색 예외: $e');
    }
    return [];
  }

  /// ─── 카카오 키워드 장소 검색 ───
  static Future<List<PlaceResult>> searchKakao({
    required String query,
    required double lat,
    required double lng,
    int radius = 2000,
    int size = 15,
    String? categoryGroupCode,
  }) async {
    if (_kakaoRestApiKey.isEmpty) {
      debugPrint('⚠️ 카카오 REST API 키 누락!');
      return [];
    }

    try {
      debugPrint('🟡 카카오 검색 시작: "$query" (lat: $lat, lng: $lng, radius: $radius)');
      String url = 'https://dapi.kakao.com/v2/local/search/keyword.json'
          '?query=${Uri.encodeComponent(query)}'
          '&x=$lng&y=$lat'
          '&radius=$radius'
          '&size=$size'
          '&sort=accuracy';

      if (categoryGroupCode != null) {
        url += '&category_group_code=$categoryGroupCode';
      }

      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'KakaoAK $_kakaoRestApiKey',
      });

      debugPrint('🟡 카카오 응답: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> documents = data['documents'] ?? [];
        debugPrint('🟡 카카오 결과: ${documents.length}건');

        return documents.map((doc) {
          return PlaceResult(
            name: doc['place_name'] ?? '',
            address: doc['road_address_name'] ?? doc['address_name'] ?? '',
            lat: double.tryParse(doc['y'] ?? '0') ?? 0,
            lng: double.tryParse(doc['x'] ?? '0') ?? 0,
            rating: 0,
            reviewCount: 0,
            category: doc['category_name'] ?? '기타',
            source: 'kakao',
            placeUrl: doc['place_url'],
          );
        }).toList();
      } else {
        debugPrint('❌ 카카오 HTTP 에러: ${response.statusCode}');
        debugPrint('❌ 카카오 응답: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
      }
    } catch (e) {
      debugPrint('❌ 카카오 검색 예외: $e');
    }
    return [];
  }

  /// ─── 카카오 좌표 검색 (주소→좌표) ───
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    if (_kakaoRestApiKey.isEmpty || address.isEmpty) return null;

    try {
      final url = 'https://dapi.kakao.com/v2/local/search/address.json'
          '?query=${Uri.encodeComponent(address)}';

      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'KakaoAK $_kakaoRestApiKey',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final docs = data['documents'] as List?;
        if (docs != null && docs.isNotEmpty) {
          return {
            'lat': double.tryParse(docs[0]['y'] ?? '0') ?? 0,
            'lng': double.tryParse(docs[0]['x'] ?? '0') ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('지오코딩 오류: $e');
    }
    return null;
  }

  /// ─── 구글 Places API (기존 로직) ───
  static Future<List<PlaceResult>> searchGoogle({
    required double lat,
    required double lng,
    required int radius,
    required String type,
    String keyword = '',
  }) async {
    if (_googleApiKey.isEmpty) return [];

    try {
      String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=$lat,$lng'
          '&radius=$radius'
          '&type=$type'
          '&language=ko'
          '&key=$_googleApiKey';

      if (keyword.isNotEmpty) {
        url += '&keyword=${Uri.encodeComponent(keyword)}';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'] ?? [];

          return results.map((place) {
            final geo = place['geometry']['location'];
            String? photoUrl;
            if (place['photos'] != null && (place['photos'] as List).isNotEmpty) {
              final photoRef = place['photos'][0]['photo_reference'];
              photoUrl = 'https://maps.googleapis.com/maps/api/place/photo'
                  '?maxwidth=400&photoreference=$photoRef&key=$_googleApiKey';
            }

            return PlaceResult(
              name: place['name'] ?? '',
              address: place['vicinity'] ?? '',
              lat: (geo['lat'] as num).toDouble(),
              lng: (geo['lng'] as num).toDouble(),
              rating: (place['rating'] ?? 0).toDouble(),
              reviewCount: place['user_ratings_total'] ?? 0,
              category: (place['types'] != null && (place['types'] as List).isNotEmpty)
                  ? place['types'][0]
                  : '기타',
              source: 'google',
              photoUrl: photoUrl,
              placeId: place['place_id'],
              rawData: Map<String, dynamic>.from(place),
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('구글 검색 오류: $e');
    }
    return [];
  }

  /// ─── 하이브리드 검색 (3개 API 병렬 호출 + 병합) ───
  static Future<List<PlaceResult>> hybridSearch({
    required double lat,
    required double lng,
    required int radius,
    required String googleType,
    required String keyword,
    double minRating = 0.0,
  }) async {
    // 카카오 카테고리 코드 매핑
    String? kakaoCategoryCode;
    if (googleType == 'restaurant') kakaoCategoryCode = 'FD6';
    if (googleType == 'cafe') kakaoCategoryCode = 'CE7';

    // 검색 쿼리 생성
    String searchQuery = keyword.isNotEmpty ? keyword : '맛집';
    if (googleType == 'cafe') searchQuery = keyword.isNotEmpty ? keyword : '카페';
    if (googleType == 'bar') searchQuery = keyword.isNotEmpty ? keyword : '바';

    // 3개 API 동시 호출 — 네이버는 역 이름 기반
    final stations = await _getNearbyStations(lat, lng);
    debugPrint('🚉 검색 역: ${stations.join(", ")}');
    final stationQuery = '${stations.first} $searchQuery';

    final results = await Future.wait([
      searchGoogle(lat: lat, lng: lng, radius: radius, type: googleType, keyword: keyword),
      searchKakao(query: searchQuery, lat: lat, lng: lng, radius: radius, categoryGroupCode: kakaoCategoryCode),
      searchNaver(query: stationQuery, display: 5, sort: 'comment'),
    ]);

    final List<PlaceResult> googleResults = results[0];
    final List<PlaceResult> kakaoResults = results[1];
    final List<PlaceResult> naverResults = results[2];

    debugPrint('━━━ 하이브리드 검색 결과 ━━━');
    debugPrint('🔵 구글: ${googleResults.length}건');
    debugPrint('🟡 카카오: ${kakaoResults.length}건');
    debugPrint('🟢 네이버: ${naverResults.length}건');

    // 통합 병합 + 중복 제거
    final merged = _mergeAndDeduplicate(googleResults, kakaoResults, naverResults);

    debugPrint('🔀 병합 후 (중복 제거): ${merged.length}건');

    // 필터링 (평점 기준 — 완화)
    final filtered = merged.where((p) {
      // 네이버/카카오는 평점 데이터가 없으므로 무조건 포함
      if (p.source != 'google') return true;
      return p.rating >= minRating;
    }).toList();

    debugPrint('✅ 최종 결과: ${filtered.length}건 (구글: ${filtered.where((p) => p.source == "google").length}, 카카오: ${filtered.where((p) => p.source == "kakao").length}, 네이버: ${filtered.where((p) => p.source == "naver").length})');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━');

    // 통합 점수로 정렬
    filtered.sort((a, b) => b.score.compareTo(a.score));

    return filtered;
  }

   /// ─── 핫플레이스 전용 하이브리드 검색 ───
  static Future<List<PlaceResult>> hybridHotPlaces({
    required double lat,
    required double lng,
    required int radius,
    required bool isFoodMode,
    Set<String> selectedCats = const {},
    int limit = 35,
  }) async {
    final String googleType = isFoodMode ? 'restaurant' : 'point_of_interest';
    String? kakaoCategory = isFoodMode ? 'FD6' : null;

    final stations = await _getNearbyStations(lat, lng);
    debugPrint('🚉 핫플 검색 역: ${stations.join(", ")}');

    // ─── 네이버 다양성: 역 × 카테고리 멀티 쿼리 ───
    List<String> naverQueries = [];
    if (selectedCats.isNotEmpty) {
      // 선택된 카테고리 × 역 조합
      for (var station in stations) {
        for (var cat in selectedCats) {
          naverQueries.add('$station $cat 맛집');
        }
      }
    } else {
      // 기본: 각 역별 맛집 검색
      for (var station in stations) {
        if (isFoodMode) {
          naverQueries.add('$station 맛집');
          naverQueries.add('$station 맛집 추천');
        } else {
          naverQueries.add('$station 핫플');
          naverQueries.add('$station 카페');
        }
      }
    }

    // 구글 키워드 생성 (카테고리 반영)
    String googleKeyword = '';
    if (selectedCats.isNotEmpty) {
      googleKeyword = selectedCats.join(' ');
    }

    // 카카오 쿼리 생성
    String kakaoQuery = isFoodMode ? '맛집' : '핫플';
    if (selectedCats.isNotEmpty) {
      kakaoQuery = selectedCats.first; // 카카오는 첫 카테고리로
    }

    // 네이버 병렬 멀티 쿼리 실행
    final naverFutures = naverQueries.map(
      (q) => searchNaver(query: q, display: 5, sort: 'comment')
    ).toList();

    // 전체 병렬 실행
    final allFutures = await Future.wait([
      searchGoogle(lat: lat, lng: lng, radius: radius, type: googleType, keyword: googleKeyword),
      searchKakao(query: kakaoQuery, lat: lat, lng: lng, radius: radius, categoryGroupCode: kakaoCategory, size: 15),
      ...naverFutures,
    ]);

    final googleResults = allFutures[0];
    final kakaoResults = allFutures[1];
    // 네이버 결과 전부 합산
    final List<PlaceResult> allNaverResults = [];
    for (int i = 2; i < allFutures.length; i++) {
      allNaverResults.addAll(allFutures[i]);
    }
    // 네이버 내부 중복 제거
    final Map<String, PlaceResult> naverDedup = {};
    for (var p in allNaverResults) {
      final key = _normalizeKey(p.name);
      naverDedup.putIfAbsent(key, () => p);
    }
    final naverResults = naverDedup.values.toList();

    debugPrint('━━━ 핫플레이스 검색 결과 ━━━');
    debugPrint('🔵 구글: ${googleResults.length}건');
    debugPrint('🟡 카카오: ${kakaoResults.length}건');
    debugPrint('🟢 네이버: ${naverResults.length}건 (${naverQueries.length}개 쿼리)');

    final merged = _mergeAndDeduplicate(googleResults, kakaoResults, naverResults);

    debugPrint('🔀 병합 후: ${merged.length}건');

    // 핫플레이스 필터
    final filtered = merged.where((p) {
      if (p.source == 'google') {
        return p.rating >= 3.5 && p.reviewCount >= 5;
      }
      return true;
    }).toList();

    // 출처별 분리 + 각각 정렬
    final googleFiltered = filtered.where((p) => p.source == 'google').toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final naverFiltered = filtered.where((p) => p.source == 'naver').toList();
    final kakaoFiltered = filtered.where((p) => p.source == 'kakao').toList();

    // 출처 균형 병합
    final List<PlaceResult> balanced = [];
    balanced.addAll(naverFiltered);
    balanced.addAll(kakaoFiltered);
    final remaining = limit - balanced.length;
    if (remaining > 0) {
      balanced.addAll(googleFiltered.take(remaining));
    }
    balanced.shuffle();

    debugPrint('✅ 핫플 최종: ${balanced.length}건 (구글: ${balanced.where((p) => p.source == "google").length}, 카카오: ${balanced.where((p) => p.source == "kakao").length}, 네이버: ${balanced.where((p) => p.source == "naver").length})');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━');

    return balanced;
  }


  /// ─── 결과 병합 + 중복 제거 + 프랜차이즈 제외 ───
  static const _excludedFranchises = [
    '뚜레쥬르', '파리바게뜨', '세븐일레븐', 'GS25', 'CU',
    '이마트', '홈플러스', '다이소', '롯데리아', '스타벅스',
    '맥도날드', '버거킹', '롭리아', '달콤커피',
    '메가MGC커피', '투썸플레이스', '이디야', 'EDIYA',
    '미니스톱', '올리브영', '이마트에브리데이',
  ];

  static List<PlaceResult> _mergeAndDeduplicate(
      List<PlaceResult> google, List<PlaceResult> kakao, List<PlaceResult> naver) {
    final Map<String, PlaceResult> seen = {};

    // 구글 결과 우선 (사진+평점 데이터 가장 풍부)
    for (var p in google) {
      final key = _normalizeKey(p.name);
      seen[key] = p;
    }

    // 카카오 결과 병합 (좌표 데이터 정확)
    for (var p in kakao) {
      final key = _normalizeKey(p.name);
      if (!seen.containsKey(key)) {
        seen[key] = p;
      } else {
        // 기존 구글 결과에 카카오 URL 보완
        final existing = seen[key]!;
        if (existing.placeUrl == null && p.placeUrl != null) {
          seen[key] = PlaceResult(
            name: existing.name,
            address: existing.address,
            lat: existing.lat,
            lng: existing.lng,
            rating: existing.rating,
            reviewCount: existing.reviewCount,
            category: existing.category,
            source: existing.source,
            photoUrl: existing.photoUrl,
            placeUrl: p.placeUrl,
            placeId: existing.placeId,
            rawData: existing.rawData,
          );
        }
      }
    }

    // 네이버 결과 병합 (좌표 없어도 포함)
    for (var p in naver) {
      final key = _normalizeKey(p.name);
      if (!seen.containsKey(key)) {
        seen[key] = p;
      }
    }

    return seen.values.where((p) {
      // 프랜차이즈 제외
      final nameLower = p.name.toLowerCase();
      return !_excludedFranchises.any((f) => nameLower.contains(f.toLowerCase()));
    }).toList();
  }

  /// 가게 이름 정규화 (중복 판별용)
  static String _normalizeKey(String name) {
    return name
        .replaceAll(RegExp(r'<[^>]*>'), '') // HTML 태그 제거
        .replaceAll(RegExp(r'\s+'), '') // 공백 제거
        .replaceAll(RegExp(r'[^\w가-힣]'), '') // 특수문자 제거
        .toLowerCase();
  }

  /// HTML 태그 정리 (네이버 결과용)
  static String _cleanHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// 구글 Places API로 가장 가까운 지하철역 3개 검색 (이름 5글자 이하)
  static Future<List<String>> _getNearbyStations(double lat, double lng) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=$lat,$lng'
          '&radius=2000'
          '&type=subway_station'
          '&language=ko'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final List<dynamic> results = data['results'] ?? [];
          final stationNames = <String>[];

          for (var place in results) {
            String name = place['name'] ?? '';
            // "노원역 6호선" → "노원역"
            name = name.replaceAll(RegExp(r'\s+\d+호선.*'), '');
            name = name.replaceAll(RegExp(r'\s+\(.*\)'), '');
            name = name.trim();
            if (!name.endsWith('역')) name = '$name역';

            // 5글자 초과 역명 제외 (예: "수유리방배나라역" → 건너뛰)
            if (name.length > 5) {
              debugPrint('⚠️ 역명 제외 (길이 ${name.length}): $name');
              continue;
            }

            if (!stationNames.contains(name)) {
              stationNames.add(name);
            }
            if (stationNames.length >= 3) break;
          }

          if (stationNames.isNotEmpty) {
            debugPrint('🚉 발견된 역: $stationNames');
            return stationNames;
          }
        }
      }
    } catch (e) {
      debugPrint('지하철역 검색 오류: $e');
    }
    final areaName = await _getLocalAreaName(lat, lng);
    return [areaName];
  }

  /// 구글 역지오코딩으로 구/동 추출 (폴백용)
  static Future<String> _getLocalAreaName(double lat, double lng) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng'
          '&language=ko'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          String gu = '';
          String dong = '';

          for (var result in results) {
            final components = result['address_components'] as List?;
            if (components == null) continue;

            for (var comp in components) {
              final types = (comp['types'] as List).cast<String>();
              final name = comp['long_name'] as String;
              if (types.contains('sublocality_level_1') && gu.isEmpty) gu = name;
              if (types.contains('sublocality_level_2') && dong.isEmpty) dong = name;
              if (types.contains('neighborhood') && dong.isEmpty) dong = name;
            }
            if (gu.isNotEmpty) break;
          }

          if (gu.isNotEmpty && dong.isNotEmpty) return '$gu $dong';
          if (gu.isNotEmpty) return gu;
          if (dong.isNotEmpty) return dong;
        }
      }
    } catch (e) {
      debugPrint('역지오코딩 오류: $e');
    }
    return _getFallbackAreaName(lat, lng);
  }

  /// 폴백 지역명
  static String _getFallbackAreaName(double lat, double lng) {
    if (lat > 37.4 && lat < 37.7 && lng > 126.8 && lng < 127.2) return '서울';
    if (lat > 35.0 && lat < 35.3 && lng > 128.9 && lng < 129.2) return '부산';
    if (lat > 35.1 && lat < 35.3 && lng > 126.8 && lng < 127.0) return '광주';
    if (lat > 35.8 && lat < 36.0 && lng > 128.5 && lng < 128.8) return '대구';
    if (lat > 36.3 && lat < 36.4 && lng > 127.3 && lng < 127.5) return '대전';
    if (lat > 35.4 && lat < 35.6 && lng > 129.2 && lng < 129.5) return '울산';
    if (lat > 37.3 && lat < 37.6 && lng > 126.5 && lng < 126.8) return '인천';
    return '주변';
  }
}
