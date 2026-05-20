class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  factory LatLng.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'] ?? json['latitude'];
    final lng = json['lng'] ?? json['longitude'];

    return LatLng(
      (lat as num).toDouble(),
      (lng as num).toDouble(),
    );
  }

  Map<String, double> toJson() => {
        'lat': latitude,
        'lng': longitude,
      };

  LatLng copyWith({
    double? latitude,
    double? longitude,
  }) {
    return LatLng(
      latitude ?? this.latitude,
      longitude ?? this.longitude,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LatLng &&
            runtimeType == other.runtimeType &&
            latitude == other.latitude &&
            longitude == other.longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}
