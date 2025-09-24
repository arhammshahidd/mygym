import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class OpenAIService {
  final Dio _dio;

  OpenAIService._internal(this._dio);

  factory OpenAIService() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.openAIBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppConfig.openAIApiKey}',
      },
    ));
    return OpenAIService._internal(dio);
  }

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
  }) async {
    if (AppConfig.openAIApiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    final system = 'You are a fitness planning assistant. Produce ONLY valid JSON.';
    final user = {
      'user_id': userId,
      'start_date': startDate,
      'end_date': endDate,
      'exercise_plan': exercisePlan,
      'total_workouts': 4,
      'total_training_minutes': 180,
      'age': age,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'gender': gender,
      'future_goal': futureGoal,
    };

    final res = await _dio.post('/chat/completions', data: {
      'model': AppConfig.openAIModel,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': 'Generate AI plan JSON matching this schema exactly: '
              '{"user_id": number, "start_date": string, "end_date": string, "exercise_plan": string, '
              '"total_workouts": number, "total_training_minutes": number, '
              '"items": [{"name": string, "sets": number, "reps": number, "weight": number, "training_minutes": number, "exercise_types": string}]}. '
              'Here are the inputs: ${jsonEncode(user)}.'
        }
      ],
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
    });

    if (res.statusCode == 200) {
      final msg = res.data['choices'][0]['message']['content'];
      final parsed = jsonDecode(msg);
      return Map<String, dynamic>.from(parsed);
    }
    throw Exception('OpenAI generation failed: ${res.statusCode}');
  }
}


