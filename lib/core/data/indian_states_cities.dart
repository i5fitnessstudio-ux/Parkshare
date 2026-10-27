/// Indian states and cities data grouped by state.
/// Reusable data structure as per project requirements.
class IndianStatesCities {
  IndianStatesCities._();

  /// All 28 states and 8 union territories in alphabetical order
  static const List<String> states = [
    'Andaman and Nicobar Islands',
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chandigarh',
    'Chhattisgarh',
    'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jammu and Kashmir',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Ladakh',
    'Lakshadweep',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Puducherry',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
  ];

  /// Cities grouped by state
  static const Map<String, List<String>> citiesByState = {
    'Tamil Nadu': [
      'Chennai',
      'Chrompet',
      'Coimbatore',
      'Madurai',
      'Trichy',
      'Tiruchirappalli (Trichy)',
      'Salem',
      'Erode',
      'Tirunelveli',
      'Tiruppur',
      'Vellore',
      'Thoothukudi',
      'Nagercoil',
      'Thanjavur',
      'Kanchipuram',
      'Karur',
      'Namakkal',
      'Sivakasi',
      'Pollachi',
      'Cuddalore',
      'Tiruvannamalai',
      'Pudukkottai',
      'Virudhunagar',
      'Krishnagiri',
      'Dindigul',
      'Ranipet',
      'Perambalur',
      'Kumbakonam',
    ],
    'Andhra Pradesh': [
      'Visakhapatnam',
      'Vizag (Visakhapatnam)',
      'Vijayawada',
      'Guntur',
      'Nellore',
      'Kurnool',
      'Rajahmundry',
      'Tirupati',
      'Kakinada',
      'Anantapur',
      'Ongole',
      'Chittoor',
      'Vizianagaram',
      'Eluru',
      'Kadapa',
      'Machilipatnam',
    ],
    'Arunachal Pradesh': [
      'Itanagar',
      'Naharlagun',
      'Pasighat',
      'Tawang',
      'Bomdila',
    ],
    'Assam': [
      'Guwahati',
      'Silchar',
      'Dibrugarh',
      'Jorhat',
      'Tezpur',
      'Nagaon',
      'Bongaigaon',
    ],
    'Bihar': [
      'Patna',
      'Gaya',
      'Bhagalpur',
      'Muzaffarpur',
      'Purnia',
      'Darbhanga',
      'Bihar Sharif',
      'Arrah',
    ],
    'Chandigarh': ['Chandigarh'],
    'Chhattisgarh': [
      'Raipur',
      'Bhilai',
      'Bilaspur',
      'Korba',
      'Durg',
      'Jagdalpur',
      'Ambikapur',
    ],
    'Dadra and Nagar Haveli and Daman and Diu': ['Daman', 'Silvassa', 'Diu'],
    'Delhi': ['Delhi', 'New Delhi'],
    'Goa': ['Panaji', 'Margao', 'Vasco da Gama'],
    'Gujarat': [
      'Ahmedabad',
      'Surat',
      'Vadodara (Baroda)',
      'Rajkot',
      'Bhavnagar',
      'Jamnagar',
      'Gandhinagar',
      'Junagadh',
    ],
    'Haryana': [
      'Gurugram (Gurgaon)',
      'Faridabad',
      'Panipat',
      'Ambala',
      'Yamunanagar',
      'Rohtak',
      'Hisar',
    ],
    'Himachal Pradesh': ['Shimla', 'Solan', 'Dharamshala', 'Mandi', 'Kullu'],
    'Jammu and Kashmir': ['Srinagar', 'Jammu', 'Anantnag', 'Baramulla'],
    'Jharkhand': [
      'Ranchi',
      'Jamshedpur',
      'Dhanbad',
      'Bokaro Steel City',
      'Hazaribagh',
    ],
    'Karnataka': [
      'Bengaluru (Bangalore)',
      'Mangaluru (Mangalore)',
      'Mysuru (Mysore)',
      'Hubballi (Hubli)',
      'Belagavi (Belgaum)',
      'Kalaburagi',
      'Davanagere',
      'Ballari',
      'Shimoga',
    ],
    'Kerala': [
      'Kochi (Cochin)',
      'Thiruvananthapuram',
      'Kozhikode (Calicut)',
      'Thrissur',
      'Kollam',
      'Alappuzha',
      'Palakkad',
      'Kannur',
      'Ernakulam',
    ],
    'Ladakh': ['Leh', 'Kargil'],
    'Lakshadweep': ['Kavaratti'],
    'Madhya Pradesh': [
      'Indore',
      'Bhopal',
      'Jabalpur',
      'Gwalior',
      'Ujjain',
      'Sagar',
      'Satna',
    ],
    'Maharashtra': [
      'Mumbai',
      'Pune',
      'Nagpur',
      'Nashik',
      'Thane',
      'Pimpri-Chinchwad',
      'Chinchwad',
      'Kalyan-Dombivli',
      'Vasai-Virar',
      'Aurangabad',
      'Navi Mumbai',
      'Solapur',
      'Kolhapur',
      'Amravati',
    ],
    'Manipur': ['Imphal'],
    'Meghalaya': ['Shillong'],
    'Mizoram': ['Aizawl'],
    'Nagaland': ['Kohima', 'Dimapur'],
    'Odisha': ['Bhubaneswar', 'Cuttack', 'Rourkela', 'Berhampur', 'Sambalpur'],
    'Puducherry': ['Puducherry'],
    'Punjab': ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala', 'Bathinda'],
    'Rajasthan': [
      'Jaipur',
      'Jodhpur',
      'Kota',
      'Udaipur',
      'Ajmer',
      'Bikaner',
      'Alwar',
      'Bharatpur',
    ],
    'Sikkim': ['Gangtok'],
    'Telangana': [
      'Hyderabad',
      'Warangal',
      'Nizamabad',
      'Karimnagar',
      'Khammam',
    ],
    'Tripura': ['Agartala'],
    'Uttar Pradesh': [
      'Lucknow',
      'Kanpur',
      'Varanasi',
      'Allahabad (Prayagraj)',
      'Agra',
      'Meerut',
      'Ghaziabad',
      'Noida',
      'Aligarh',
      'Bareilly',
      'Gorakhpur',
      'Firozabad',
    ],
    'Uttarakhand': ['Dehradun', 'Haridwar', 'Roorkee', 'Haldwani'],
    'West Bengal': ['Kolkata', 'Asansol', 'Durgapur', 'Siliguri', 'Bardhaman'],
  };

  /// Case-insensitive match function
  static List<String> match(String query, List<String> source) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
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

  /// Get cities for a specific state
  static List<String> getCitiesForState(String state) {
    if (state.trim().isEmpty) {
      // Return all cities if no state is selected (backward compatibility)
      final allCities = <String>{};
      for (final cities in citiesByState.values) {
        allCities.addAll(cities);
      }
      return allCities.toList()..sort();
    }
    return citiesByState[state] ?? [];
  }
}
