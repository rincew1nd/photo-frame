import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photoframe/core/clock.dart';
import 'package:photoframe/data/weather/weather_service.dart';

class _FixedClock implements Clock {
  _FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

void main() {
  late HttpServer server;
  late List<Uri> requests;
  late _FixedClock clock;
  late WeatherService service;
  late int status;
  late Map<String, dynamic> body;

  setUp(() async {
    requests = <Uri>[];
    status = HttpStatus.ok;
    body = <String, dynamic>{
      'current': <String, dynamic>{
        'temperature_2m': 21.5,
        'weather_code': 3,
      },
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      await request.drain<void>();
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    clock = _FixedClock(DateTime.utc(2026, 1, 1, 12));
    service = WeatherService(
      baseUrl: 'http://127.0.0.1:${server.port}/v1/forecast',
      clock: clock,
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('parses a current weather response', () async {
    final snapshot = await service.current(
      latitude: 52.52,
      longitude: 13.41,
      locationLabel: 'Berlin',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.temperature, 21.5);
    expect(snapshot.unit, 'celsius');
    expect(snapshot.code, 3);
    expect(snapshot.description, 'Overcast');
    expect(snapshot.locationLabel, 'Berlin');
    expect(snapshot.fetchedAt, clock.now());
    expect(requests, hasLength(1));
    expect(
      requests.single.queryParameters['current'],
      'temperature_2m,weather_code',
    );
    expect(
      requests.single.queryParameters['temperature_unit'],
      'celsius',
    );
    expect(requests.single.queryParameters['latitude'], '52.52');
    expect(requests.single.queryParameters['longitude'], '13.41');
  });

  test('serves subsequent calls from cache until the ttl expires', () async {
    await service.current(latitude: 1, longitude: 2);
    await service.current(latitude: 1, longitude: 2);
    expect(requests, hasLength(1));

    clock.value = clock.value.add(const Duration(minutes: 14));
    await service.current(latitude: 1, longitude: 2);
    expect(requests, hasLength(1));

    clock.value = clock.value.add(const Duration(minutes: 2));
    await service.current(latitude: 1, longitude: 2);
    expect(requests, hasLength(2));
  });

  test('returns null on a server error', () async {
    status = HttpStatus.internalServerError;

    final snapshot = await service.current(latitude: 1, longitude: 2);

    expect(snapshot, isNull);
  });

  test('returns null on a malformed response', () async {
    body = <String, dynamic>{
      'current': <String, dynamic>{'temperature_2m': 'not-a-number'},
    };

    final snapshot = await service.current(latitude: 1, longitude: 2);

    expect(snapshot, isNull);
  });

  test('maps wmo weather codes to short descriptions', () {
    expect(WeatherService.descriptionForCode(0), 'Clear sky');
    expect(WeatherService.descriptionForCode(3), 'Overcast');
    expect(WeatherService.descriptionForCode(61), 'Light rain');
    expect(WeatherService.descriptionForCode(95), 'Thunderstorm');
    expect(WeatherService.descriptionForCode(1234), 'Unknown');
  });

  test('requests fahrenheit when configured', () async {
    final snapshot = await service.current(
      latitude: 1,
      longitude: 2,
      unit: 'fahrenheit',
    );

    expect(snapshot?.unit, 'fahrenheit');
    expect(
      requests.single.queryParameters['temperature_unit'],
      'fahrenheit',
    );
  });
}
