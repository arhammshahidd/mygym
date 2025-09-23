class AppConfig {
  // Backend base URL for mobile app
  static const String baseApiUrl = 'http://localhost:5000';

  // API paths
  static const String loginPath = '/api/auth/mobileuser/login';
  static const String trainingsPath = '/api/trainings';
  
  // Profile endpoints
  static const String profilePath = '/api/appProfile';
  static const String notificationsPath = '/api/appProfile';
  // Users endpoint not used (profile covers all)
}

class StorageKeys {
  static const String authToken = 'auth_token';
}

