import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPlace with ClusterItem {
  final String id;
  final String name;
  final LatLng latLng;
  final String foodType;
  final Map<String, dynamic> data; // 팝업에 띄울 원본 데이터

  MapPlace({
    required this.id,
    required this.name,
    required this.latLng,
    required this.foodType,
    required this.data,
  });

  @override
  LatLng get location => latLng;
}