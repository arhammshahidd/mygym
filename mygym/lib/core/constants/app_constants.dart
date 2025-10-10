class AppConfig {
  // Backend base URL for mobile app (override with --dart-define=BASE_API_URL=http://IP:PORT)
  static const String baseApiUrl = String.fromEnvironment('BASE_API_URL', defaultValue: 'http://localhost:5000');
  // OpenAI configuration (for training services only)
  static const String openAIApiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  static const String openAIBaseUrl = 'https://api.openai.com/v1';
  static const String openAIModel = String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4o-mini');
  
  // Local AI Nutrition System - No external API keys needed
  // Toggle to route through backend /requests first (backend does AI), else app generates and posts to /generated
  static const bool useAiRequests = bool.fromEnvironment('USE_AI_REQUESTS', defaultValue: false);

  // API paths
  static const String loginPath = '/api/auth/mobileuser/login';
  static const String trainingsPath = '/api/trainings';
  
  // Profile endpoints
  static const String profilePath = '/api/profile';
  static const String notificationsPath = '/api/appProfile'; // Keep notifications on old endpoint
  // Users endpoint not used (profile covers all)
  // Training approvals
  static const String trainingApprovalsPath = '/api/trainingApprovals';
  // Nutrition (Food Menu)
  static const String foodMenuAssignmentsPath = '/api/foodMenu/assignments';
  static const String foodMenuAssignPath = '/api/foodMenu/assign';

  // Realtime (WebSocket) configuration
  // For Flutter web, prefer ws:// or wss:// reachable from the browser
  static const String wsBaseUrl = String.fromEnvironment('WS_BASE_URL', defaultValue: 'ws://localhost:5000');
  static const String wsApprovalsPath = '/ws/approvals';
}

class StorageKeys {
  static const String authToken = 'auth_token';
}

