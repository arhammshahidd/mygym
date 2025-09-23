class User {
  final int id;
  final String name;
  final String email;
  final String phone;
  final int? age;
  final double? heightCm;
  final double? weightKg;
  final bool prefWorkoutAlerts;
  final bool prefMealReminders;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.age,
    this.heightCm,
    this.weightKg,
    this.prefWorkoutAlerts = true,
    this.prefMealReminders = true,
  });

  factory User.fromJson(Map<String, dynamic> rawJson) {
    // Some APIs wrap payload under 'data', or 'data.user', or 'user'/'profile'
    Map<String, dynamic> json = rawJson;
    if (json['data'] is Map<String, dynamic>) {
      json = Map<String, dynamic>.from(json['data']);
    }
    if (json['user'] is Map<String, dynamic>) {
      json = Map<String, dynamic>.from(json['user']);
    } else if (json['profile'] is Map<String, dynamic>) {
      json = Map<String, dynamic>.from(json['profile']);
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String pickString(List<String> keys) {
      for (final key in keys) {
        // Try exact key
        dynamic value = json[key];
        // Try common case variants
        value ??= json[key.toLowerCase()];
        value ??= json[key.toUpperCase()];
        // Try camelCase vs snake_case
        final camel = key.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
        final snake = key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
        value ??= json[camel];
        value ??= json[snake];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      return '';
    }

    int id = parseInt(json['id'] ?? json['userId'] ?? json['uid'] ?? json['user_id']);
    // Build name from parts if needed
    String firstName = pickString(['first_name', 'firstName', 'firstname']);
    String lastName = pickString(['last_name', 'lastName', 'lastname']);
    String combined = [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();
    String name = combined.isNotEmpty
        ? combined
        : pickString(['name', 'full_name', 'fullName', 'username', 'display_name', 'displayName']);
    String email = pickString(['email', 'emailAddress', 'email_address', 'mail']);
    String phone = pickString(['phone', 'mobile', 'phoneNumber', 'phone_number']);

    return User(
      id: id,
      name: name,
      email: email,
      phone: phone,
      age: json['age'] is String ? int.tryParse(json['age']) : json['age'],
      heightCm: parseDouble(json['height_cm'] ?? json['heightCm'] ?? json['height']),
      weightKg: parseDouble(json['weight_kg'] ?? json['weightKg'] ?? json['weight']),
      prefWorkoutAlerts: json['pref_workout_alerts'] ?? json['prefWorkoutAlerts'] ?? true,
      prefMealReminders: json['pref_meal_reminders'] ?? json['prefMealReminders'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'age': age,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'pref_workout_alerts': prefWorkoutAlerts,
      'pref_meal_reminders': prefMealReminders,
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? email,
    String? phone,
    int? age,
    double? heightCm,
    double? weightKg,
    bool? prefWorkoutAlerts,
    bool? prefMealReminders,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      prefWorkoutAlerts: prefWorkoutAlerts ?? this.prefWorkoutAlerts,
      prefMealReminders: prefMealReminders ?? this.prefMealReminders,
    );
  }

  String get initials {
    final names = name.split(' ');
    if (names.length >= 2) {
      return '${names[0][0]}${names[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  String get formattedHeight {
    if (heightCm == null) return 'Not set';
    final feet = (heightCm! / 30.48).floor();
    final inches = ((heightCm! % 30.48) / 2.54).round();
    return '${feet}\'${inches}" (${heightCm!.toStringAsFixed(0)} cm)';
  }

  String get formattedWeight {
    if (weightKg == null) return 'Not set';
    return '${weightKg!.toStringAsFixed(1)} kg';
  }
}
