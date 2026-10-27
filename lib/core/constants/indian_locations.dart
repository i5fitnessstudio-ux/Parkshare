/// Predefined Indian city / state lists used by the searchable suggestions on
/// the owner "Details" step. Pure data — no network call, so the form works
/// offline and stays instant on mobile.
///
/// The lists are intentionally plain strings: the value the owner taps is
/// exactly what is stored on the draft (and sent to the API), and the owner
/// can still type a place that is missing from the list.
class IndianLocations {
  IndianLocations._();

  /// All 28 states and 8 union territories.
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

  /// Major cities across India — enough that typing the first letter narrows
  /// the list to a handful of tappable options (e.g. "C" -> Chennai,
  /// Coimbatore, Cuttack …).
  static const List<String> cities = [
    'Agra',
    'Ahmedabad',
    'Ajmer',
    'Aligarh',
    'Allahabad (Prayagraj)',
    'Amravati',
    'Amritsar',
    'Asansol',
    'Aurangabad',
    'Bareilly',
    'Belagavi (Belgaum)',
    'Bengaluru (Bangalore)',
    'Bhagalpur',
    'Bharatpur',
    'Bhavnagar',
    'Bhopal',
    'Bhubaneswar',
    'Bijapur',
    'Bikaner',
    'Bilaspur',
    'Chennai',
    'Chinchwad',
    'Coimbatore',
    'Cuttack',
    'Dehradun',
    'Delhi',
    'Dhanbad',
    'Dibrugarh',
    'Durgapur',
    'Ernakulam',
    'Erode',
    'Faridabad',
    'Firozabad',
    'Ghaziabad',
    'Gorakhpur',
    'Guntur',
    'Gurugram (Gurgaon)',
    'Guwahati',
    'Gwalior',
    'Hubballi (Hubli)',
    'Hyderabad',
    'Imphal',
    'Indore',
    'Jabalpur',
    'Jaipur',
    'Jalandhar',
    'Jamshedpur',
    'Jodhpur',
    'Jorhat',
    'Kalyan-Dombivli',
    'Kanpur',
    'Kochi (Cochin)',
    'Kolhapur',
    'Kolkata',
    'Kota',
    'Kozhikode (Calicut)',
    'Kurnool',
    'Lucknow',
    'Ludhiana',
    'Madurai',
    'Malegaon',
    'Mangaluru (Mangalore)',
    'Meerut',
    'Mumbai',
    'Mysuru (Mysore)',
    'Nagpur',
    'Nashik',
    'Navi Mumbai',
    'Noida',
    'Patna',
    'Pimpri-Chinchwad',
    'Pune',
    'Raipur',
    'Rajkot',
    'Ranchi',
    'Salem',
    'Solapur',
    'Srinagar',
    'Surat',
    'Thane',
    'Thiruvananthapuram',
    'Thrissur',
    'Tiruchirappalli (Trichy)',
    'Tirunelveli',
    'Tirupati',
    'Tiruppur',
    'Udaipur',
    'Ujjain',
    'Vadodara (Baroda)',
    'Varanasi',
    'Vasai-Virar',
    'Vijayawada',
    'Visakhapatnam',
    'Vizag (Visakhapatnam)',
    'Warangal',
    'Yamunanagar',
  ];

  /// Case-insensitive "starts with" match, then a "contains" match, so typing
  /// a letter lists the obvious options first without hiding the rest.
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
}
