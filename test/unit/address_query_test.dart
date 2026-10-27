// Unit tests for the address-query normalisation + Step-2 address builder
// used by the geocoding flow (ISSUE 7 / ISSUE 3).

import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/services/location_search_service.dart';
import 'package:parkshare_new/modules/owner/add_parking/parking_draft.dart';

void main() {
  group('normalizeAddressQuery', () {
    test('bare Chennai locality gains the Tamil Nadu region', () {
      expect(
        LocationSearchService.normalizeAddressQuery('Chennai'),
        'Chennai, Tamil Nadu, India',
      );
    });

    test('bare locality gains the Tamil Nadu region', () {
      expect(
        LocationSearchService.normalizeAddressQuery('Anna Nagar'),
        'Anna Nagar, Tamil Nadu, India',
      );
    });

    test('locality + city gains the region without duplication', () {
      expect(
        LocationSearchService.normalizeAddressQuery('Anna Nagar, Chennai'),
        'Anna Nagar, Chennai, Tamil Nadu, India',
      );
    });

    test('full address with state only gains India', () {
      expect(
        LocationSearchService.normalizeAddressQuery(
          '12/14/1 Nelson Manickam Road, Chennai, Tamil Nadu',
        ),
        '12/14/1 Nelson Manickam Road, Chennai, Tamil Nadu, India',
      );
    });

    test('full address with Tamil Nadu + pincode gains India once', () {
      expect(
        LocationSearchService.normalizeAddressQuery(
          '12/14/1 Nelson Manickam Road, Aminjikarai, Chennai, '
          'Tamil Nadu 600029',
        ),
        '12/14/1 Nelson Manickam Road, Aminjikarai, Chennai, '
        'Tamil Nadu 600029, India',
      );
    });

    test('already complete India address is never duplicated', () {
      expect(
        LocationSearchService.normalizeAddressQuery(
          '12/14/1 Nelson Manickam Road, Chennai, Tamil Nadu, India',
        ),
        '12/14/1 Nelson Manickam Road, Chennai, Tamil Nadu, India',
      );
    });

    test('6-digit pincode alone gains the Tamil Nadu region', () {
      expect(
        LocationSearchService.normalizeAddressQuery('600029'),
        '600029, Tamil Nadu, India',
      );
    });

    test('non-Tamil-Nadu query is left untouched', () {
      expect(LocationSearchService.normalizeAddressQuery('Mumbai'), 'Mumbai');
      expect(
        LocationSearchService.normalizeAddressQuery('Connaught Place, Delhi'),
        'Connaught Place, Delhi',
      );
    });

    test('non-Tamil-Nadu query with a pincode is still left untouched', () {
      // Regression: a bare 6-digit pincode used to be enough to append
      // "Tamil Nadu, India" to a Mumbai address, mislabelling the state.
      expect(
        LocationSearchService.normalizeAddressQuery(
          'Pipe Road, Kurla West, Mumbai, Maharashtra 400070',
        ),
        'Pipe Road, Kurla West, Mumbai, Maharashtra 400070',
      );
      expect(
        LocationSearchService.normalizeAddressQuery(
          'Bandra West, Mumbai 400050',
        ),
        'Bandra West, Mumbai 400050',
      );
      expect(
        LocationSearchService.normalizeAddressQuery(
          'MG Road, Bengaluru, Karnataka 560001',
        ),
        'MG Road, Bengaluru, Karnataka 560001',
      );
      expect(
        LocationSearchService.normalizeAddressQuery(
          'Marine Drive, Kochi 682031',
        ),
        'Marine Drive, Kochi 682031',
      );
    });

    test('Tamil Nadu pincode still gains the region', () {
      expect(
        LocationSearchService.normalizeAddressQuery(
          'Anna Nagar, Chennai, Tamil Nadu 600040',
        ),
        'Anna Nagar, Chennai, Tamil Nadu 600040, India',
      );
    });

    test('a non-Tamil-Nadu token must not fire as a substring', () {
      // "goatee" contains "goa" but is not Goa: the Tamil Nadu default must
      // still apply.
      expect(
        LocationSearchService.normalizeAddressQuery('Goatee Street, Chennai'),
        'Goatee Street, Chennai, Tamil Nadu, India',
      );
    });

    test('empty / whitespace-only query stays empty', () {
      expect(LocationSearchService.normalizeAddressQuery(''), '');
      expect(LocationSearchService.normalizeAddressQuery('   '), '');
    });

    test('messy spacing and trailing commas are cleaned', () {
      expect(
        LocationSearchService.normalizeAddressQuery(
          '  Chennai ,, Tamil Nadu  ,',
        ),
        'Chennai, Tamil Nadu, India',
      );
    });
  });

  group('ParkingDraft.addressQuery', () {
    test('address + city + state + pincode (no landmark)', () {
      final d = ParkingDraft()
        ..address = '12/14/1 Nelson Manickam Road'
        ..city = 'Chennai'
        ..state = 'Tamil Nadu'
        ..pincode = '600029'
        ..landmark = 'Near Skywalk';
      expect(
        d.addressQuery,
        '12/14/1 Nelson Manickam Road, Chennai, Tamil Nadu, 600029',
      );
    });

    test('partial address still builds a query', () {
      final d = ParkingDraft()
        ..address = 'Nelson Manickam Road'
        ..city = 'Chennai'
        ..state = 'Tamil Nadu';
      expect(d.addressQuery, 'Nelson Manickam Road, Chennai, Tamil Nadu');
    });

    test('landmark used only when it adds street-level context', () {
      final noAddress = ParkingDraft()..landmark = 'Near Skywalk';
      expect(noAddress.addressQuery, 'Near Skywalk');

      final onlyPincode = ParkingDraft()
        ..pincode = '600029'
        ..landmark = 'Near Skywalk';
      expect(onlyPincode.addressQuery, 'Near Skywalk, 600029');
    });
  });
}
