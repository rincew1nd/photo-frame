import 'package:dio/dio.dart';
import 'package:photoframe/core/clock.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperature,
    required this.unit,
    required this.code,
    required this.description,
    required this.locationLabel,
    required this.fetchedAt,
  });

  final double temperature;
  final String unit;
  final int code;
  final String description;
  final String locationLabel;
  final DateTime fetchedAt;
}

class WeatherService {
  WeatherService({
    Dio? dio,
    this.baseUrl = 'https://api.open-meteo.com/v1/forecast',
    this.cacheTtl = const Duration(minutes: 15),
    Clock? clock,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
             ),
           ),
       _clock = clock ?? const SystemClock();

  final String baseUrl;
  final Duration cacheTtl;
  final Dio _dio;
  final Clock _clock;
  final Map<String, WeatherSnapshot> _cache = <String, WeatherSnapshot>{};

  Future<WeatherSnapshot?> current({
    required double latitude,
    required double longitude,
    String unit = 'celsius',
    String locationLabel = '',
  }) async {
    final normalizedUnit = unit.toLowerCase() == 'fahrenheit'
        ? 'fahrenheit'
        : 'celsius';
    final key = '$latitude:$longitude:$normalizedUnit';
    final now = _clock.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.fetchedAt) < cacheTtl) {
      return cached;
    }

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: <String, String>{
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
          'current': 'temperature_2m,weather_code',
          'temperature_unit': normalizedUnit,
        },
      );
      final response = await _dio.getUri<Map<String, dynamic>>(
        uri,
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final data = response.data;
      final current = data?['current'];
      if (current is! Map) {
        return null;
      }
      final temperature = _asDouble(current['temperature_2m']);
      final code = _asInt(current['weather_code']);
      if (temperature == null || code == null) {
        return null;
      }
      final snapshot = WeatherSnapshot(
        temperature: temperature,
        unit: normalizedUnit,
        code: code,
        description: descriptionForCode(code),
        locationLabel: locationLabel,
        fetchedAt: now,
      );
      _cache[key] = snapshot;
      return snapshot;
    } on Object {
      return null;
    }
  }

  static String descriptionForCode(int code) {
    return _descriptions[code] ?? 'Unknown';
  }

  static const Map<int, String> _descriptions = <int, String>{
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Fog',
    48: 'Rime fog',
    51: 'Light drizzle',
    53: 'Moderate drizzle',
    55: 'Dense drizzle',
    56: 'Light freezing drizzle',
    57: 'Dense freezing drizzle',
    61: 'Light rain',
    63: 'Moderate rain',
    65: 'Heavy rain',
    66: 'Light freezing rain',
    67: 'Heavy freezing rain',
    71: 'Light snow',
    73: 'Moderate snow',
    75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Light rain showers',
    81: 'Moderate rain showers',
    82: 'Violent rain showers',
    85: 'Light snow showers',
    86: 'Heavy snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm with light hail',
    99: 'Thunderstorm with heavy hail',
  };
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
