import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/utils/helpers.dart';
import 'package:parkshare_new/shared/models/booking.dart';
import 'package:parkshare_new/shared/models/parking.dart';
import 'package:parkshare_new/shared/models/vehicle.dart';

void main() {
  group('Helpers', () {
    test('formatRupees groups in Indian style', () {
      expect(Helpers.formatRupees(3000), '₹3,000');
      expect(Helpers.formatRupees(12345), '₹12,345');
      expect(Helpers.formatRupees(1234567), '₹12,34,567');
      expect(Helpers.formatRupees(99.5), '₹99.50');
    });

    test('formatDistance uses metres under 1 km', () {
      expect(Helpers.formatDistance(850), '850 m');
      expect(Helpers.formatDistance(1200), '1.2 km');
    });

    test('metersValid rejects non-metre-like inputs', () {
      expect(Helpers.metersValid(-1), 'Measurement must be greater than 0.');
      expect(Helpers.metersValid(0), 'Measurement must be greater than 0.');
      expect(Helpers.metersValid(null), 'Measurement is required.');
      expect(Helpers.metersValid(5.00), isNull);
    });
  });

  group('ParkingListing.fromJson', () {
    test('parses camelCase keys with amenities + photoUrls', () {
      final p = ParkingListing.fromJson({
        'id': 'p1',
        'ownerId': 'o1',
        'ownerName': 'Rahul',
        'parkingName': 'Greenview',
        'address': 'MG Road',
        'latitude': 19.076,
        'longitude': 72.8777,
        'parkingType': 'COVERED',
        'lengthM': 5.0,
        'widthM': 2.5,
        'heightM': 2.0,
        'vehicleType': 'BOTH',
        'monthlyEnabled': true,
        'monthlyRent': 3500,
        'yearlyEnabled': false,
        'photoUrls': ['http://localhost:8080/uploads/a.png'],
        'amenities': ['CCTV', 'Security'],
        'distanceKm': 1.2,
      });
      expect(p.parkingName, 'Greenview');
      expect(p.lengthM, 5.0);
      expect(p.cheapestRent, 3500);
      expect(p.amenities, containsAll(['CCTV', 'Security']));
      expect(p.thumbnailUrl, 'http://localhost:8080/uploads/a.png');
      expect(p.distanceKm, 1.2);
      expect(p.acceptsBikes, isTrue);
      expect(p.acceptsCars, isTrue);
    });
  });

  group('Vehicle.fromJson', () {
    test('parses vehicle fields', () {
      final v = Vehicle.fromJson({
        'id': 'v1',
        'userId': 'u1',
        'vehicleType': 'BIKE',
        'brand': 'Honda',
        'model': 'Activa 6G',
        'registrationNumber': 'MH12AB1234',
        'lengthM': 1.8,
        'widthM': 0.7,
        'heightM': 1.1,
        'isPrimary': true,
      });
      expect(v.displayName, 'Honda Activa 6G');
      expect(v.isBike, isTrue);
      expect(v.isPrimary, isTrue);
      expect(v.lengthM, 1.8);
    });
  });

  group('Booking.fromJson (joined payload)', () {
    test('parses nested user parking vehicle payment', () {
      final b = Booking.fromJson({
        'bookingId': 'b1',
        'parkingId': 'p1',
        'userId': 'u1',
        'ownerId': 'o1',
        'vehicleId': 'v1',
        'rentalType': 'MONTHLY',
        'startDate': '2026-10-01T00:00:00.000Z',
        'endDate': '2026-10-31T23:59:59.000Z',
        'amount': 3500,
        'status': 'CONFIRMED',
        'createdAt': '2026-09-23T10:00:00.000Z',
        'updatedAt': '2026-09-23T10:00:00.000Z',
        'user': {'id': 'u1', 'name': 'Aisha', 'phone': '9876543210'},
        'parking': {
          'id': 'p1',
          'name': 'Greenview',
          'address': 'MG Road',
          'photoUrls': ['http://localhost:8080/uploads/a.png'],
        },
        'vehicle': {
          'id': 'v1',
          'type': 'BIKE',
          'brand': 'Honda',
          'model': 'Activa',
          'registrationNumber': 'MH12AB1234',
        },
        'payment': {
          'id': 'pay1',
          'amount': 3500,
          'paymentMethod': 'UPI',
          'transactionId': 'TXN123',
          'paymentStatus': 'SUCCESS',
          'paidAt': '2026-09-23T10:05:00.000Z',
        },
      });
      expect(b.status, BookingStatus.confirmed);
      expect(b.canPay, isFalse);
      expect(b.user.name, 'Aisha');
      expect(b.vehicle.registrationNumber, 'MH12AB1234');
      expect(b.payment.transactionId, 'TXN123');
      expect(b.payment.paymentStatus, 'SUCCESS');
    });

    test('accepted booking canPay', () {
      final b = Booking.fromJson({
        'bookingId': 'b2',
        'parkingId': 'p1',
        'userId': 'u1',
        'ownerId': 'o1',
        'vehicleId': 'v1',
        'rentalType': 'MONTHLY',
        'startDate': '2026-10-01T00:00:00.000Z',
        'endDate': '2026-10-31T23:59:59.000Z',
        'amount': 3500,
        'status': 'ACCEPTED',
        'createdAt': '2026-09-23T10:00:00.000Z',
        'updatedAt': '2026-09-23T10:00:00.000Z',
      });
      expect(b.canPay, isTrue);
    });
  });
}
