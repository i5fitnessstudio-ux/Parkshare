import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/constants/api_constants.dart';

/// The query-string builders must append with the separator the path does not
/// already have. Two callers (nearby + availability) bake a `?...` prefix into
/// the path, and a blind `?` used to swallow every later value into the
/// preceding one — `radiusKm=5.0?vehicleId=…` on the map, and a mangled
/// `endDate` that made the availability probe 400 with "startDate and endDate
/// query parameters are required".
void main() {
  group('ApiConstants query building', () {
    test('a bare path gets a ? separator', () {
      final url = ApiConstants.parkingById(
        'p1',
        vehicleId: 'v1',
        startDate: DateTime(2026, 9, 29),
        endDate: DateTime(2026, 10, 28),
      );
      expect(url, startsWith('/api/parkings/p1?'));
      expect(url, contains('vehicleId=v1'));
      expect(url, contains('startDate=2026-09-29'));
      expect(url, contains('endDate=2026-10-28'));
    });

    test('nearby keeps its own params and joins vehicleId with &', () {
      final url = ApiConstants.nearbyParkings(
        lat: 19.076,
        lng: 72.8777,
        radiusKm: 5,
        vehicleId: 'v1',
        startDate: DateTime(2026, 9, 29),
        endDate: DateTime(2026, 10, 28),
      );
      expect(
        url,
        startsWith('/api/parkings/nearby?lat=19.076&lng=72.8777&radiusKm=5.0&'),
      );
      expect(url, contains('&vehicleId=v1&'));
      expect(url, contains('startDate=2026-09-29'));
      expect(url, contains('endDate=2026-10-28'));
      expect(url.contains('?vehicleId='), isFalse);
    });

    test('availability keeps its baked-in dates intact', () {
      final url = ApiConstants.parkingAvailability(
        id: 'p1',
        startDate: '2026-09-29',
        endDate: '2026-10-28',
        vehicleId: 'v1',
        vehicleType: 'CAR',
      );
      expect(
        url,
        startsWith(
          '/api/parkings/p1/availability?startDate=2026-09-29&endDate=2026-10-28&',
        ),
      );
      expect(url, contains('&vehicleId=v1'));
      expect(url, contains('&vehicleType=CAR'));
      // The dates must never be glued to a following parameter.
      expect(url.contains('2026-10-28?'), isFalse);
    });

    test('no optional params leaves the path untouched', () {
      expect(ApiConstants.parkingById('p1'), '/api/parkings/p1');
      expect(
        ApiConstants.nearbyParkings(lat: 1, lng: 2),
        '/api/parkings/nearby?lat=1.0&lng=2.0&radiusKm=5.0',
      );
    });
  });
}
