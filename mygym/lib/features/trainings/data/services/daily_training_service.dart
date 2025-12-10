import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/api_client.dart';
import '../../../auth/data/services/auth_service.dart';

class DailyTrainingService {
  final AuthService _authService = AuthService();

  Future<Dio> _authedDio() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) throw Exception('No authentication token');
    return ApiClient(authToken: token).dio;
  }

  /// Get user's daily training plans
  /// Optional date parameter to get plans for specific date
  /// Optional planType parameter to filter by plan type (web_assigned, manual, ai_generated)
  /// Backend defaults to web_assigned if planType is not specified
  /// 
  /// BACKEND BEHAVIOR (getDailyPlans):
  /// - Finds the first incomplete day (or today's plan if it exists)
  /// - Returns only plans starting from that date
  /// - Filters out completed past days
  /// - Use this for displaying current/future plans in the UI
  /// 
  /// NOTE: For resume logic and stats, use getDailyTrainingPlans() instead to get ALL plans including completed ones
  Future<List<Map<String, dynamic>>> getDailyPlans({String? date, String? planType}) async {
    try {
      final dio = await _authedDio();
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['date'] = date;
      }
      if (planType != null && planType.isNotEmpty) {
        queryParams['plan_type'] = planType;
        print('📊 DailyTrainingService - Fetching daily plans for planType: $planType');
      }
      
      final res = await dio.get('/api/dailyTraining/mobile/plans', queryParameters: queryParams);
      print('🔍 Daily Training Plans API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          final plans = data['data'] as List<dynamic>? ?? [];
          return plans.cast<Map<String, dynamic>>();
        } else if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      throw Exception('Failed to fetch daily training plans: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to access daily training plans');
        print('💡 This is likely a backend permissions issue. Using local data only.');
      }
      rethrow;
    }
  }

  /// Get specific daily training plan by ID
  Future<Map<String, dynamic>> getDailyPlan(int planId) async {
    final dio = await _authedDio();
    final res = await dio.get('/api/dailyTraining/mobile/plans/$planId');
    print('🔍 Daily Training Plan API Response for ID $planId:');
    print('Status: ${res.statusCode}');
    print('Data: ${res.data}');
    
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map<String, dynamic> && data['success'] == true) {
        return data['data'] as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        return data;
      }
    }
    throw Exception('Failed to fetch daily training plan: ${res.statusMessage}');
  }

  /// Submit daily plan completion (training or nutrition) using new daily-plans API
  Future<void> updateDailyPlanCompletion({
    required String planId,
    required String planType, // "training" | "nutrition"
    bool isCompleted = true,
    String? completionNotes,
  }) async {
    final dio = await _authedDio();
    final payload = <String, dynamic>{
      'plan_id': planId,
      'plan_type': planType,
      'is_completed': isCompleted,
      if (completionNotes != null) 'completion_notes': completionNotes,
    };
    print('📤 DailyTrainingService - POST /daily-plans/complete payload: $payload');
    final res = await dio.post('/daily-plans/complete', data: payload);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to update daily plan completion: ${res.statusMessage}');
    }
  }

  /// Fetch today's plans (next incomplete day per source) for a user via new API
  Future<Map<String, dynamic>> getTodaysPlansForUser(String userId) async {
    final dio = await _authedDio();
    final res = await dio.get('/daily-plans/$userId/today');
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return data['data'] as Map<String, dynamic>;
      }
    }
    throw Exception('Failed to fetch today plans: ${res.statusMessage}');
  }

  /// Get training statistics (legacy endpoint - kept for backward compatibility)
  Future<Map<String, dynamic>> getTrainingStats({int? userId}) async {
    try {
      final dio = await _authedDio();
      final res = await dio.get('/api/dailyTraining/mobile/stats', queryParameters: {
        if (userId != null) 'user_id': userId,
      });
      print('🔍 Training Stats API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to fetch training statistics: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to access training stats');
        print('💡 This is likely a backend permissions issue. Using local data only.');
      }
      rethrow;
    }
  }

  /// Get user statistics from /api/stats/mobile endpoint
  /// This is the new endpoint based on the daily_training_plans table stats record
  /// Backend now supports planType parameter to get stats for a specific plan type
  Future<Map<String, dynamic>> getStats({bool refresh = false, String? planType}) async {
    try {
      final dio = await _authedDio();
      final queryParams = <String, dynamic>{};
      if (refresh) {
        queryParams['refresh'] = true;
      }
      if (planType != null && planType.isNotEmpty) {
        queryParams['planType'] = planType;
        print('📊 DailyTrainingService - Fetching stats for planType: $planType');
      } else {
        print('⚠️ DailyTrainingService - WARNING: planType is null or empty! Backend may return stats for wrong plan type.');
        print('⚠️ DailyTrainingService - This can cause stats to show data from web_assigned plans instead of ai_generated/manual plans.');
      }
      
      print('📊 DailyTrainingService - GET /api/stats/mobile');
      print('📊 DailyTrainingService - Query parameters: $queryParams');
      final res = await dio.get('/api/stats/mobile', queryParameters: queryParams);
      print('🔍 User Stats API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to fetch user statistics: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to access user stats');
        print('💡 This is likely a backend permissions issue. Using local data only.');
      } else if (e is DioException && e.response?.statusCode == 404) {
        print('⚠️ 404 Not Found: Stats record not found. Will auto-create on first sync.');
      }
      rethrow;
    }
  }

  /// Sync/refresh user statistics manually
  /// Calls POST /api/stats/mobile/sync to trigger stats recalculation
  /// Backend now supports planType parameter to sync stats for a specific plan type
  Future<Map<String, dynamic>> syncStats({String? planType}) async {
    try {
      final dio = await _authedDio();
      
      final payload = <String, dynamic>{};
      if (planType != null && planType.isNotEmpty) {
        payload['planType'] = planType;
        print('📊 DailyTrainingService - Syncing stats for planType: $planType');
      } else {
        print('⚠️ DailyTrainingService - WARNING: planType is null or empty! Backend may sync stats for wrong plan type.');
        print('⚠️ DailyTrainingService - This can cause stats to show data from web_assigned plans instead of ai_generated/manual plans.');
      }
      
      print('📊 DailyTrainingService - POST /api/stats/mobile/sync');
      print('📊 DailyTrainingService - Request payload: $payload');
      final res = await dio.post('/api/stats/mobile/sync', data: payload);
      print('🔍 Sync Stats API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          final responseData = data['data'];
          // Handle case where backend returns null data (no stats record exists yet)
          if (responseData == null) {
            print('⚠️ DailyTrainingService - Sync response has null data (no stats record exists yet)');
            return <String, dynamic>{}; // Return empty map instead of throwing error
          }
          if (responseData is Map<String, dynamic>) {
            return responseData;
          }
          // If data is not a Map, return empty map
          print('⚠️ DailyTrainingService - Sync response data is not a Map: ${responseData.runtimeType}');
          return <String, dynamic>{};
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to sync user statistics: ${res.statusMessage}');
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 403) {
        print('🚫 403 Forbidden: User does not have permission to sync stats');
        print('💡 This is likely a backend permissions issue.');
      }
      rethrow;
    }
  }

  /// Get today's training plans
  Future<List<Map<String, dynamic>>> getTodaysPlans() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    return await getDailyPlans(date: today);
  }

  /// Create completion data for a single exercise
  static Map<String, dynamic> createCompletionItem({
    required int itemId,
    required int setsCompleted,
    required int repsCompleted,
    required double weightUsed,
    required int minutesSpent,
    String? notes,
  }) {
    return {
      'item_id': itemId,
      'sets_completed': setsCompleted,
      'reps_completed': repsCompleted,
      'weight_used': weightUsed,
      'minutes_spent': minutesSpent,
      if (notes != null) 'notes': notes,
    };
  }

  /// Store daily training plan data when a plan is started
  // Get daily training plans for mobile
  /// Optional planType parameter to filter by plan type (web_assigned, manual, ai_generated)
  /// Backend defaults to web_assigned if planType is not specified
  /// Backend also filters out is_stats_record: true plans at SQL level
  /// 
  /// BACKEND BEHAVIOR (getDailyTrainingPlans):
  /// - Returns ALL plans (completed and incomplete) for the specified plan type
  /// - Does NOT filter out completed past days (unlike getDailyPlans)
  /// - Use this for resume logic and stats calculations
  /// 
  /// NOTE: This is the preferred method for resume logic and stats, as it includes completed plans
  /// 
  /// NOTE: Backend behavior is determined by query parameters:
  /// - When user_id is present → Backend returns ALL plans (completed + incomplete)
  /// - When user_id is NOT present → Backend filters out completed past days (returns only incomplete/future plans)
  Future<List<Map<String, dynamic>>> getDailyTrainingPlans({int? userId, String? planType}) async {
    try {
      final dio = await _authedDio();
      
      final queryParams = <String, dynamic>{};
      if (userId != null) {
        queryParams['user_id'] = userId;
      }
      if (planType != null && planType.isNotEmpty) {
        queryParams['plan_type'] = planType;
        print('📊 DailyTrainingService - Fetching daily training plans for planType: $planType');
      }
      // Add parameter to request all plans including completed ones
      // Backend may use this to distinguish from getDailyPlans() which filters completed days
      queryParams['include_completed'] = true;
      
      final res = await dio.get('/api/dailyTraining/mobile/plans', queryParameters: queryParams);
      
      print('🔍 DailyTrainingService - Get daily plans response status: ${res.statusCode}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        
        // Handle schema-compliant response: { "success": true, "data": [...] }
        if (data is Map<String, dynamic>) {
          // Validate success field (schema requirement)
          if (data.containsKey('success') && data['success'] == true) {
            if (data['data'] is List) {
              return List<Map<String, dynamic>>.from(data['data']);
            }
          } else if (data['data'] is List) {
            // Fallback: if success field is missing but data exists, still parse it
            return List<Map<String, dynamic>>.from(data['data']);
          }
        } else if (data is List) {
          // Handle direct array response (backward compatibility)
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return [];
    } catch (e) {
      print('❌ DailyTrainingService - Error getting daily training plans: $e');
      return [];
    }
  }

  // Get specific daily training plan
  Future<Map<String, dynamic>> getDailyTrainingPlan(int planId) async {
    try {
      final dio = await _authedDio();
      
      final res = await dio.get('/api/dailyTraining/mobile/plans/$planId');
      
      print('🔍 DailyTrainingService - Get daily plan $planId response status: ${res.statusCode}');
      
      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map) {
          // Handle API response format {success: true, data: {...}}
          if (data.containsKey('success') && data.containsKey('data')) {
            return Map<String, dynamic>.from(data['data'] ?? {});
          }
          return Map<String, dynamic>.from(data);
        }
      }
      return {};
    } catch (e) {
      print('❌ DailyTrainingService - Error getting daily training plan $planId: $e');
      return {};
    }
  }

  // Submit daily training completion
  Future<Map<String, dynamic>> submitDailyTrainingCompletion({
    required int planId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    try {
      final dio = await _authedDio();
      
      // Transform any lightweight completion entries into the expected schema
      final List<Map<String, dynamic>> normalizedItems = completionData.map((e) {
        final int itemId = int.tryParse((e['item_id'] ?? '0').toString()) ?? 0;
        final int sets = int.tryParse((e['sets_completed'] ?? e['sets'] ?? '0').toString()) ?? 0;
        final int reps = int.tryParse((e['reps_completed'] ?? e['reps'] ?? '0').toString()) ?? 0;
        final double weight = double.tryParse((e['weight_used'] ?? e['weight'] ?? '0').toString()) ?? 0.0;
        final int minutes = int.tryParse((e['minutes_spent'] ?? e['minutes'] ?? '0').toString()) ?? 0;
        final dynamic day = e['day'];
        final String workoutName = (e['workout_name'] ?? e['name'] ?? '').toString();
        final String? notes = e['notes']?.toString();
        final String composedNotes = [
          if (notes != null && notes.isNotEmpty) notes,
          if (workoutName.isNotEmpty) 'Workout: $workoutName',
          if (day != null) 'Day: ${int.tryParse(day.toString()) != null ? (int.parse(day.toString()) + 1) : day}',
          'Source: Plans tab'
        ].where((s) => s.isNotEmpty).join(' | ');
        return {
          'item_id': itemId,
          'sets_completed': sets,
          'reps_completed': reps,
          'weight_used': weight,
          'minutes_spent': minutes,
          if (composedNotes.isNotEmpty) 'notes': composedNotes,
        };
      }).toList();
      
      final payload = {
        // Backend expects daily_plan_id here
        'daily_plan_id': planId,
        'completion_data': normalizedItems,
        'completed_at': DateTime.now().toIso8601String(),
      };
      
      final res = await dio.post('/api/dailyTraining/mobile/complete', data: payload);
      
      print('🔍 DailyTrainingService - Submit completion response status: ${res.statusCode}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data);
      }
      throw Exception('Failed to submit daily training completion: ${res.statusMessage}');
    } catch (e) {
      print('❌ DailyTrainingService - Error submitting daily training completion: $e');
      rethrow;
    }
  }


  Future<Map<String, dynamic>> storeDailyTrainingPlan({
    required int planId,
    required String planType, // 'manual' or 'ai_generated'
    required List<Map<String, dynamic>> dailyPlans,
    required int userId,
    String? planCategory,
    String? userLevel,
  }) async {
    try {
      final dio = await _authedDio();

      // Normalize daily plans to backend schema
      List<Map<String, dynamic>> normalizedDays = [];
      final DateTime baseDate = DateTime.now();
      for (int i = 0; i < dailyPlans.length; i++) {
        final day = dailyPlans[i];
        final List rawWorkouts = (day['workouts'] ?? day['items'] ?? []) as List;
        final List<Map<String, dynamic>> exercises = [];
        int totalMinutes = 0;
        int totalSets = 0;
        int totalReps = 0;
        double totalWeight = 0.0;

        for (int workoutIndex = 0; workoutIndex < rawWorkouts.length; workoutIndex++) {
          final w = rawWorkouts[workoutIndex];
          final Map<String, dynamic> m = Map<String, dynamic>.from(w as Map);
          final String exerciseName = (m['name'] ?? m['workout_name'] ?? m['muscle_group'] ?? 'Workout').toString();
          final int sets = int.tryParse(m['sets']?.toString() ?? '0') ?? 0;
          final int reps = int.tryParse(m['reps']?.toString() ?? '0') ?? 0;
          
          // Extract weight - handle string ranges like "20-40"
          double weight = 0.0;
          double? parsedWeightMin;
          double? parsedWeightMax;
          
          if (m['weight_kg'] is String && (m['weight_kg'] as String).contains('-')) {
            // Parse string range like "20-40"
            final parts = (m['weight_kg'] as String).split('-');
            if (parts.length == 2) {
              parsedWeightMin = double.tryParse(parts[0].trim());
              parsedWeightMax = double.tryParse(parts[1].trim());
              weight = parsedWeightMin ?? 0.0;
            }
          } else {
            weight = double.tryParse(m['weight_kg']?.toString() ?? m['weight']?.toString() ?? '0') ?? 0.0;
          }
          
          final int minutes = int.tryParse(m['minutes']?.toString() ?? m['training_minutes']?.toString() ?? '0') ?? 0;
          final int exerciseType = int.tryParse(m['exercise_types']?.toString() ?? m['exercise_type']?.toString() ?? '0') ?? 0;

          // Extract weight_min_kg and weight_max_kg if available
          if (parsedWeightMin == null || parsedWeightMax == null) {
            final double? weightMinKg = m['weight_min_kg'] != null 
                ? double.tryParse(m['weight_min_kg'].toString()) 
                : null;
            final double? weightMaxKg = m['weight_max_kg'] != null 
                ? double.tryParse(m['weight_max_kg'].toString()) 
                : null;
            
            if (weightMinKg != null) parsedWeightMin = weightMinKg;
            if (weightMaxKg != null) parsedWeightMax = weightMaxKg;
          }
          
          // item_id is now the 1-based index in the exercises_details array
          // Since daily_training_plan_items table is removed, item_id is the 1-based array index
          final int itemId = workoutIndex + 1; // Use 1-based index as item_id (backend expects 1-based)
          
          final exerciseData = {
            'id': itemId, // Include ID so it can be used for completion
            'item_id': itemId, // 1-based index in exercises_details array
            'exercise_name': exerciseName,
            'workout_name': m['workout_name'] ?? exerciseName,
            'name': exerciseName,
            'sets': sets,
            'reps': reps,
            'weight_kg': weight,
            'minutes': minutes,
            'training_minutes': minutes,
            'exercise_type': exerciseType,
            'exercise_types': exerciseType,
          };
          
          // Add weight_min_kg and weight_max_kg if available
          if (parsedWeightMin != null) {
            exerciseData['weight_min_kg'] = parsedWeightMin;
          }
          if (parsedWeightMax != null) {
            exerciseData['weight_max_kg'] = parsedWeightMax;
          }
          
          exercises.add(exerciseData);

          totalMinutes += minutes;
          totalSets += sets;
          totalReps += reps;
          totalWeight += weight;
        }

        final String dayName = (day['workout_name']?.toString()) ?? 'Day ${day['day'] ?? (i + 1)}';
        // Use day_number as primary identifier (1-based: Day 1, Day 2, etc.)
        final int dayNumber = int.tryParse(day['day_number']?.toString() ?? day['day']?.toString() ?? '') ?? (i + 1);
        // Keep date for backward compatibility/display if available
        final String? date = day['date']?.toString();
        final String dayCategory = day['plan_category'] ?? day['exercise_plan_category'] ?? planCategory ?? 'Training Plan';
        final String dayUserLevel = day['user_level'] ?? userLevel ?? 'Beginner';
        
        normalizedDays.add({
          'day_number': dayNumber, // Primary identifier for day-based system
          if (date != null && date.isNotEmpty) 'date': date, // Keep date for display if available
          'workout_name': dayName,
          'plan_category': dayCategory,
          'user_level': dayUserLevel,
          'exercises_details': exercises,
          // Note: Server computes these totals from exercises_details
          // We include them for reference, but backend will recalculate
          'training_minutes': totalMinutes,
          'total_exercises': exercises.length,
          'total_sets': totalSets,
          'total_reps': totalReps,
          'total_weight_kg': totalWeight,
        });
      }

      final payload = {
        'plan_type': planType,
        'user_id': userId,
        'source_plan_id': planId,
        'daily_plans': normalizedDays,
        // Note: plan_category and user_level are now in each daily_plan entry
      };

      final res = await dio.post('/api/dailyTraining/mobile/plans/store', data: payload);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return Map<String, dynamic>.from(res.data is Map ? res.data : {'success': true, 'data': res.data});
      }
      throw Exception('Failed to store daily training plans: HTTP ${res.statusCode}');
    } catch (e) {
      print('❌ DailyTrainingService - Error storing daily training plan: $e');
      rethrow;
    }
  }

  /// Create daily plan from training approval or assignment
  /// This uses the new endpoint that creates daily plans from training approvals/assignments
  /// The endpoint accepts approval_id (for AI/Manual plans), assignment_id (for assigned plans), or web_plan_id
  Future<Map<String, dynamic>> createDailyPlanFromApproval({
    int? approvalId,
    int? assignmentId,
    int? dayNumber,
    int? webPlanId,
  }) async {
    try {
      final dio = await _authedDio();
      
      final payload = <String, dynamic>{};
      
      // For assigned plans, send assignment_id (prioritized by backend)
      if (assignmentId != null) {
        payload['assignment_id'] = assignmentId;
      }
      // For AI/Manual plans, send approval_id
      else if (approvalId != null) {
        payload['approval_id'] = approvalId;
      }
      
      // Add web_plan_id if provided - backend can use this for lookup in either table
      if (webPlanId != null) {
        payload['web_plan_id'] = webPlanId;
      }
      
      // Add day_number if provided
      if (dayNumber != null) {
        payload['day_number'] = dayNumber;
      }
      
      // Validate that at least one ID is provided
      if (payload.isEmpty || (!payload.containsKey('assignment_id') && !payload.containsKey('approval_id') && !payload.containsKey('web_plan_id'))) {
        throw Exception('At least one of assignment_id, approval_id, or web_plan_id must be provided');
      }
      
      print('📤 Creating daily plan from training approval/assignment:');
      print('Endpoint: /api/dailyTraining/mobile/plans/create-from-approval');
      print('Payload: $payload');
      if (assignmentId != null) {
        print('📤 Using assignment_id (for assigned plans from training_plan_assignments)');
      } else if (approvalId != null) {
        print('📤 Using approval_id (for AI/Manual plans from training_approvals)');
      }
      if (webPlanId != null) {
        print('📤 Also including web_plan_id: $webPlanId');
      }
      
      final res = await dio.post('/api/dailyTraining/mobile/plans/create-from-approval', data: payload);
      
      print('🔍 Create Daily Plan From Approval API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      throw Exception('Failed to create daily plan from approval: ${res.statusMessage}');
    } on DioException catch (e) {
      print('❌ DailyTrainingService - Error creating daily plan from approval: $e');
      print('❌ DailyTrainingService - Request URL: ${e.requestOptions.uri}');
      print('❌ DailyTrainingService - Request Payload: ${e.requestOptions.data}');
      print('❌ DailyTrainingService - Status Code: ${e.response?.statusCode}');
      print('❌ DailyTrainingService - Response Data: ${e.response?.data}');
      
      // Provide helpful error message for 404
      if (e.response?.statusCode == 404) {
        print('⚠️ DailyTrainingService - 404 Error: The endpoint may not be available yet.');
        print('⚠️ DailyTrainingService - This usually means:');
        print('⚠️   1. Backend server needs to be restarted for route ordering fix to take effect');
        print('⚠️   2. The route /api/dailyTraining/mobile/plans/create-from-approval should be defined');
        print('⚠️   3. Route should be ordered BEFORE /api/dailyTraining/mobile/plans/:id');
      }
      
      // Provide helpful error message for 400 (Bad Request)
      if (e.response?.statusCode == 400) {
        print('⚠️ DailyTrainingService - 400 Bad Request Error: Invalid request format or parameters.');
        print('⚠️ DailyTrainingService - This usually means:');
        print('⚠️   1. Request payload format is incorrect (check approval_id, web_plan_id, day_number)');
        print('⚠️   2. Backend validation failed (check backend error message above)');
        print('⚠️   3. Missing required fields or invalid field values');
        
        // Try to extract and display backend error message
        if (e.response?.data != null) {
          try {
            final responseData = e.response!.data;
            if (responseData is Map) {
              final message = responseData['message'] ?? responseData['error'] ?? responseData['msg'];
              if (message != null) {
                print('⚠️ DailyTrainingService - Backend Error Message: $message');
              }
            } else if (responseData is String) {
              print('⚠️ DailyTrainingService - Backend Error Response: $responseData');
            }
          } catch (_) {
            print('⚠️ DailyTrainingService - Could not parse backend error message');
          }
        }
      }
      
      rethrow;
    } catch (e) {
      print('❌ DailyTrainingService - Unexpected error creating daily plan from approval: $e');
      rethrow;
    }
  }

  /// Find daily plan by source (assignment_id/approval_id) and date
  /// This is useful when you need to look up a daily plan after creation
  Future<Map<String, dynamic>?> findDailyPlanBySource({
    int? assignmentId,
    int? approvalId,
    int? webPlanId,
    int? sourcePlanId,
    int? dayNumber,
  }) async {
    try {
      final dio = await _authedDio();

      final queryParams = <String, dynamic>{};
      if (assignmentId != null) {
        queryParams['assignment_id'] = assignmentId;
      }
      if (approvalId != null) {
        queryParams['approval_id'] = approvalId;
      }
      if (webPlanId != null) {
        queryParams['web_plan_id'] = webPlanId;
      }
      if (sourcePlanId != null) {
        queryParams['source_plan_id'] = sourcePlanId;
      }
      if (dayNumber != null) {
        queryParams['day_number'] = dayNumber;
      }

      // Validate that at least one ID is provided
      if (queryParams.isEmpty) {
        throw Exception('At least one of assignment_id, approval_id, web_plan_id, or source_plan_id must be provided');
      }

      print('📤 Finding daily plan by source:');
      print('Endpoint: /api/dailyTraining/mobile/plans/find');
      print('Query params: $queryParams');

      final res = await dio.get('/api/dailyTraining/mobile/plans/find', queryParameters: queryParams);

      print('🔍 Find Daily Plan API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');

      if (res.statusCode == 200) {
        final data = res.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data['data'] as Map<String, dynamic>?;
        } else if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return null;
    } on DioException catch (e) {
      print('❌ DailyTrainingService - Error finding daily plan by source: $e');
      print('❌ DailyTrainingService - Request URL: ${e.requestOptions.uri}');
      print('❌ DailyTrainingService - Status Code: ${e.response?.statusCode}');
      print('❌ DailyTrainingService - Response Data: ${e.response?.data}');
      return null;
    } catch (e) {
      print('❌ DailyTrainingService - Unexpected error finding daily plan by source: $e');
      return null;
    }
  }

  /// Sync a manual training plan into daily_training_plans (day_number-based)
  Future<Map<String, dynamic>> syncManualTrainingPlanToDaily({
    required String planId,
    required String userId,
  }) async {
    final dio = await _authedDio();
    final res = await dio.post(
      '/app/manual/training-plans/$planId/sync-to-daily',
      data: {'user_id': userId},
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return res.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(res.data)
          : {'data': res.data};
    }
    throw Exception('Failed to sync manual training plan: ${res.statusMessage}');
  }

  /// Sync a manual nutrition plan into daily_nutrition_plans (day_number-based)
  Future<Map<String, dynamic>> syncManualNutritionPlanToDaily({
    required String planId,
    required String userId,
  }) async {
    final dio = await _authedDio();
    final res = await dio.post(
      '/app/manual/meal-plans/$planId/sync-to-daily',
      data: {'user_id': userId},
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return res.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(res.data)
          : {'data': res.data};
    }
    throw Exception('Failed to sync manual nutrition plan: ${res.statusMessage}');
  }

  /// Get all daily plans for a user, optionally filtered by source_plan_id and plan_type
  Future<List<Map<String, dynamic>>> getUserDailyPlans({
    required String userId,
    String? sourcePlanId,
    String? planType, // "training" | "nutrition" | other backend-supported types
  }) async {
    final dio = await _authedDio();
    final query = <String, dynamic>{'user_id': userId};
    if (sourcePlanId != null && sourcePlanId.isNotEmpty) {
      query['source_plan_id'] = sourcePlanId;
    }
    if (planType != null && planType.isNotEmpty) {
      query['plan_type'] = planType;
    }
    final res = await dio.get('/daily-plans', queryParameters: query);
    if (res.statusCode == 200) {
      final data = res.data;
      if (data is Map<String, dynamic> && data['data'] is List) {
        return (data['data'] as List).cast<Map<String, dynamic>>();
      }
      if (data is List) return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to fetch user daily plans: ${res.statusMessage}');
  }

  /// Delete daily training plans by source (approval_id, assignment_id, etc.)
  /// This is used to clean up daily plans when a parent plan is deleted
  Future<void> deleteDailyPlansBySource({
    int? approvalId,
    int? assignmentId,
    int? sourcePlanId,
  }) async {
    try {
      final dio = await _authedDio();

      final queryParams = <String, dynamic>{};
      if (approvalId != null) {
        queryParams['approval_id'] = approvalId;
      }
      if (assignmentId != null) {
        queryParams['assignment_id'] = assignmentId;
      }
      if (sourcePlanId != null) {
        queryParams['source_plan_id'] = sourcePlanId;
      }

      // Validate that at least one ID is provided
      if (queryParams.isEmpty) {
        throw Exception('At least one of approval_id, assignment_id, or source_plan_id must be provided');
      }

      print('🗑️ Deleting daily plans by source:');
      print('Endpoint: /api/dailyTraining/mobile/plans/delete-by-source');
      print('Query params: $queryParams');

      final res = await dio.delete('/api/dailyTraining/mobile/plans/delete-by-source', queryParameters: queryParams);

      print('🗑️ Delete Daily Plans API Response:');
      print('Status: ${res.statusCode}');
      print('Data: ${res.data}');

      if (res.statusCode == 200 || res.statusCode == 204) {
        print('✅ Daily plans deleted successfully from database');
        return;
      }
      throw Exception('Failed to delete daily plans: HTTP ${res.statusCode}');
    } on DioException catch (e) {
      // If endpoint doesn't exist (404), log warning but don't fail
      // Backend should handle cascading deletes when parent plan is deleted
      if (e.response?.statusCode == 404) {
        print('⚠️ Delete daily plans endpoint not found (404). Backend should handle cascading deletes.');
        return;
      }
      print('❌ DailyTrainingService - Error deleting daily plans by source: $e');
      print('❌ DailyTrainingService - Request URL: ${e.requestOptions.uri}');
      print('❌ DailyTrainingService - Status Code: ${e.response?.statusCode}');
      print('❌ DailyTrainingService - Response Data: ${e.response?.data}');
      // Don't throw - backend should handle cascading deletes
      return;
    } catch (e) {
      print('❌ DailyTrainingService - Unexpected error deleting daily plans by source: $e');
      // Don't throw - backend should handle cascading deletes
      return;
    }
  }
}
