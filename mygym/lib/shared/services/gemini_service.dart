import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class GeminiService {
  final Dio _dio;

  GeminiService() : _dio = Dio(BaseOptions(
    baseUrl: AppConfig.geminiBaseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  Future<Map<String, dynamic>> generatePlanJson({
    required int userId,
    required String exercisePlan,
    required String startDate,
    required String endDate,
    required int age,
    required int heightCm,
    required int weightKg,
    required String gender,
    required String futureGoal,
    String? userLevel,
  }) async {
    print('🤖 GeminiService.generatePlanJson called');
    print('🤖 Gemini API Key length: ${AppConfig.geminiApiKey.length}');
    print('🤖 Gemini API Key value: "${AppConfig.geminiApiKey}"');
    if (AppConfig.geminiApiKey.isEmpty) {
      print('❌ Gemini API key is missing!');
      throw Exception('Gemini API key is missing');
    }

    final String model = AppConfig.geminiModel;
    final String path = '/models/$model:generateContent?key=${Uri.encodeComponent(AppConfig.geminiApiKey)}';

    final prompt = _buildPrompt(
      userId: userId,
      exercisePlan: exercisePlan,
      startDate: startDate,
      endDate: endDate,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      gender: gender,
      futureGoal: futureGoal,
      userLevel: userLevel,
    );

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    };

    final res = await _dio.post(path, data: jsonEncode(body));

    if (res.statusCode == 200) {
      final data = res.data as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates.first['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        final text = (parts != null && parts.isNotEmpty) ? parts.first['text']?.toString() ?? '' : '';
        if (text.isEmpty) throw Exception('Gemini returned empty content');
        // Expect the model to return valid JSON string
        print('🤖 Gemini response text: $text');
        final Map<String, dynamic> json = jsonDecode(text) as Map<String, dynamic>;
        print('🤖 Gemini parsed JSON: ${json.toString()}');
        print('🤖 Gemini items count: ${json['items']?.length ?? 0}');
        return json;
      }
      throw Exception('No candidates returned from Gemini');
    }

    throw Exception('Gemini request failed: ${res.statusCode}');
  }

  String _buildPrompt({
    required int userId,
    required String exercisePlan,
    required String startDate,
    required String endDate,
    required int age,
    required int heightCm,
    required int weightKg,
    required String gender,
    required String futureGoal,
    String? userLevel,
  }) {
    // Calculate plan duration in days
    final start = DateTime.parse(startDate);
    final end = DateTime.parse(endDate);
    final durationDays = end.difference(start).inDays;
    
    return '''
You are a fitness planning assistant. Generate a comprehensive training plan JSON for a ${durationDays}-day program strictly in this schema:
{
  "user_id": number,
  "exercise_plan_category": string,
  "start_date": "YYYY-MM-DD",
  "end_date": "YYYY-MM-DD",
  "training_minutes": number,
  "total_workouts": number,
  "items": [
    {
      "workout_name": string,            // primary muscle group: Chest | Back | Shoulders | Legs | Arms | Core
      "exercise_types": number,          // count of distinct exercise types for this workout (6-12)
      "sets": number,
      "reps": number,
      "weight_kg": number,
      "weight_min_kg": number,            // minimum weight in kg (optional, use same as weight_kg if not specified)
      "weight_max_kg": number,            // maximum weight in kg (optional, use same as weight_kg if not specified)
      "minutes": number
    }
  ]
}

Rules:
- Generate a comprehensive ${durationDays}-day training plan with multiple workout variations
- Create at least ${(durationDays / 7).ceil() * 2} workout items to cover the full duration
- Ensure realistic volumes for age $age, height $heightCm cm, weight $weightKg kg, gender $gender
- Goal: $futureGoal
- Category: $exercisePlan
- User Level: ${userLevel ?? 'Not specified'}
- Dates: $startDate to $endDate
- Use meaningful workout_name values like Chest, Back, Shoulders, Legs, Arms, Core (no placeholders like "Test Workout").
- Set exercise_types as an integer count (6-12) representing the number of different exercises (for GIF selection).
- Vary workout types throughout the plan (strength, cardio, flexibility, etc.)
- For weight ranges: set weight_min_kg and weight_max_kg based on user level and exercise type. For beginners, use a range (e.g., 5-10 kg), for intermediate/advanced use wider ranges. If weight_min_kg equals weight_max_kg, it represents a fixed weight.
- Return ONLY valid JSON, no markdown, no commentary.
- training_minutes must equal the sum of items.minutes

User ID: $userId
''';
  }
}


