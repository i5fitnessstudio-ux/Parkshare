/// Vehicle brands and models data grouped by vehicle type.
/// Reusable data structure as per project requirements.
class VehicleData {
  VehicleData._();

  /// Vehicle types
  static const List<String> vehicleTypes = ['Car', 'Bike', 'Scooty'];

  /// Models grouped by vehicle type
  static const Map<String, List<String>> modelsByType = {
    'Car': [
      'Alto',
      'Baleno',
      'Swift',
      'Wagon R',
      'Ertiga',
      'Dzire',
      'Ciaz',
      'Ignis',
      'S-Cross',
      'Vitara Brezza',
      'Hyundai Creta',
      'Hyundai i20',
      'Hyundai Venue',
      'Hyundai Verna',
      'Hyundai Aura',
      'Hyundai Grand i10',
      'Kia Seltos',
      'Kia Sonet',
      'Kia Carens',
      'Tata Nexon',
      'Tata Harrier',
      'Tata Punch',
      'Tata Tiago',
      'Tata Altroz',
      'Mahindra XUV700',
      'Mahindra Scorpio',
      'Mahindra Thar',
      'Mahindra Bolero',
      'Honda City',
      'Honda Amaze',
      'Honda WR-V',
      'Toyota Innova',
      'Toyota Fortuner',
      'Toyota Glanza',
      'Toyota Urban Cruiser',
      'Renault Kwid',
      'Renault Triber',
      'Renault Kiger',
      'Maruti Alto 800',
      'Maruti Ertiga',
      'Maruti Brezza',
      'Ford EcoSport',
      'Ford Endeavour',
      'Skoda Slavia',
      'Skoda Kushaq',
      'Volkswagen Virtus',
      'Volkswagen Taigun',
      'Nissan Magnite',
      'MG Hector',
      'Others',
    ],
    'Bike': [
      'Splendor',
      'Splendor Plus',
      'HF Deluxe',
      'Passion',
      'Glamour',
      'Super Splendor',
      'XPulse',
      'CT100',
      'Pulsar 125',
      'Pulsar 150',
      'Pulsar 180',
      'Pulsar 220F',
      'Pulsar NS125',
      'Pulsar NS160',
      'Pulsar NS200',
      'Pulsar RS200',
      'Dominar 250',
      'Dominar 400',
      'KTM 125 Duke',
      'KTM 200 Duke',
      'KTM 390 Duke',
      'Apache RTR 160',
      'Apache RTR 180',
      'Apache RTR 200',
      'Apache RR 310',
      'Radeon',
      'Star City',
      'Unicorn',
      'Hornet 2.0',
      'CB Shine',
      'CB Unicorn',
      'CB Hornet',
      'SP 125',
      'Activa (Bike variant not usual, see Scooty)',
      'Royal Enfield Classic 350',
      'Royal Enfield Bullet 350',
      'Royal Enfield Meteor 350',
      'Royal Enfield Hunter 350',
      'Royal Enfield Himalayan',
      'Royal Enfield Interceptor',
      'Royal Enfield Continental GT',
      'Yamaha FZ-S',
      'Yamaha FZ-X',
      'Yamaha MT-15',
      'Yamaha R15',
      'Bajaj Avenger',
      'Bajaj Platina',
      'Bajaj CT125X',
      'Suzuki Gixxer',
      'Suzuki Access (see Scooty)',
      'TVS Raider',
      'TVS Jupiter (see Scooty)',
      'Others',
    ],
    'Scooty': [
      'Activa 6G',
      'Activa 125',
      'Activa 3G',
      'Activa 5G',
      'Dio',
      'Grazia',
      'Aviator',
      'Clavius',
      'Jupiter',
      'Jupiter 125',
      'NTorq',
      'NTorq 125',
      'Zest 110',
      'Pep',
      'Pep Plus',
      'Maestro',
      'Maestro Edge',
      'Access 125',
      'Burgman Street',
      'Burgman 125',
      'RayZR',
      'Fascino',
      'Cygnus',
      'Vectra',
      'Pleasure',
      'Scooty Zest',
      'Nexon EV (not scooty)',
      'iQube',
      'Chetak',
      'Others',
    ],
  };

  /// Brands list (common)
  static const List<String> brands = [
    'Hero',
    'Honda',
    'TVS',
    'Bajaj',
    'Suzuki',
    'Yamaha',
    'Royal Enfield',
    'KTM',
    'Hyundai',
    'Maruti Suzuki',
    'Tata',
    'Mahindra',
    'Toyota',
    'Kia',
    'Ford',
    'Volkswagen',
    'Skoda',
    'Renault',
    'Nissan',
    'MG',
    'Others',
  ];

  /// Get models for vehicle type
  static List<String> getModelsForType(String type) {
    if (type == 'scooty' || type == 'Scooty') {
      return modelsByType['Scooty'] ?? [];
    }
    return modelsByType[type] ?? [];
  }

  /// Case-insensitive match function for vehicle models
  static List<String> match(String query, List<String> source) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source.take(20).toList();
    final starts = <String>[];
    final contains = <String>[];
    for (final option in source) {
      final lower = option.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(option);
      } else if (lower.contains(q)) {
        contains.add(option);
      }
    }
    return [...starts, ...contains];
  }
}
