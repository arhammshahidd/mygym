import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/trainings_controller.dart';
import 'create_plan_page.dart';
import 'plan_detail_page.dart';
import 'ai_generate_plan_page.dart';
import 'edit_plan_page.dart';

class TrainingsPage extends StatefulWidget {
  const TrainingsPage({super.key});

  @override
  State<TrainingsPage> createState() => _TrainingsPageState();
}

class _TrainingsPageState extends State<TrainingsPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final TrainingsController _controller = Get.find<TrainingsController>();
  final Map<int, bool> _startedPlans = {};
  Map<String, dynamic>? _activePlan;
  final Map<String, bool> _completedWorkouts = {};
  final Map<String, bool> _workoutTimers = {};
  final Map<String, int> _currentDay = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild when tab changes
      
      // Refresh plans when switching to Plans tab (index 1)
      if (_tabController.index == 1) {
        print('🔄 Switched to Plans tab, refreshing plans...');
        _controller.refreshPlans();
      }
    });
      _controller.loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _checkDayCompletion(Map<String, dynamic> plan, int dayIndex) {
    final planId = plan['id']?.toString() ?? '';
    final dayItems = _getDayItems(plan, dayIndex);
    
    // Check if all workouts for this day are completed
    bool allCompleted = true;
    for (int i = 0; i < dayItems.length; i++) {
      final workoutKey = '${planId}_${dayIndex}_$i';
      if (!(_completedWorkouts[workoutKey] ?? false)) {
        allCompleted = false;
        break;
      }
    }
    
    if (allCompleted) {
      // Move to next day
      setState(() {
        _currentDay[planId] = dayIndex + 1;
      });
      
      // Show completion message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Day ${dayIndex + 1} completed! Moving to Day ${dayIndex + 2}'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    }
  }

  Future<void> _sendPlanForApproval(Map<String, dynamic> plan) async {
    try {
      // Get user information from the controller
      final userId = _controller.userId;
      final user = _controller.user;
      final userName = user?.name ?? user?.username ?? 'User $userId';
      final userPhone = user?.phone ?? user?.phoneNumber ?? '';
      
      print('🔍 User info - ID: $userId, Name: $userName, Phone: $userPhone');
      
      // Determine plan type
      final aiPlans = _controller.aiGenerated;
      final isAiPlan = aiPlans.any((aiPlan) => aiPlan['id'] == plan['id']);
      final planType = isAiPlan ? 'ai_generated' : 'manual';
      
      print('🔍 Plan type determined: $planType (isAiPlan: $isAiPlan)');
      
      // Ensure we have the full plan data with exercises
      Map<String, dynamic> fullPlan = Map<String, dynamic>.from(plan);
      if (plan['items'] == null || (plan['items'] as List).isEmpty) {
        print('🔍 Plan missing items, fetching full plan data...');
        try {
          if (isAiPlan) {
            fullPlan = await _controller.getAiGeneratedPlan(plan['id']);
          } else {
            fullPlan = await _controller.getManualPlan(plan['id']);
          }
          print('🔍 Full plan fetched: ${fullPlan.keys}');
          print('🔍 Full plan items: ${fullPlan['items']}');
        } catch (e) {
          print('❌ Failed to fetch full plan: $e');
          // Continue with original plan data
        }
      }
      
      // Handle exercises_details if items is still empty
      if ((fullPlan['items'] == null || (fullPlan['items'] as List).isEmpty) && 
          fullPlan['exercises_details'] != null) {
        print('🔍 Plan has exercises_details, parsing...');
        try {
          if (fullPlan['exercises_details'] is String) {
            final String exercisesJson = fullPlan['exercises_details'] as String;
            print('🔍 Parsing exercises_details JSON: $exercisesJson');
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            fullPlan['items'] = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            print('🔍 Parsed exercises_details into items: ${fullPlan['items']}');
          } else if (fullPlan['exercises_details'] is List) {
            fullPlan['items'] = List<Map<String, dynamic>>.from(fullPlan['exercises_details'] as List);
            print('🔍 Converted exercises_details to items: ${fullPlan['items']}');
          }
        } catch (e) {
          print('❌ Failed to parse exercises_details: $e');
        }
      }
      
      // Prepare the payload according to the API specification
      // Use the same structure as manual plan creation but keep functionality separate
      final payload = {
        // User information
        "user_id": userId,
        "user_name": userName,
        "user_phone": userPhone,
        
        // Plan information - same structure as manual plan creation
        "plan_id": fullPlan['id'], // Add plan ID for tracking
        "plan_type": planType, // Add plan type (manual or ai_generated)
        "exercise_plan_category": fullPlan['exercise_plan_category'] ?? fullPlan['exercise_plan'] ?? fullPlan['category'] ?? 'General',
        "start_date": fullPlan['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
        "end_date": fullPlan['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T')[0],
        "total_workouts": fullPlan['total_workouts'] ?? (fullPlan['items'] is List ? (fullPlan['items'] as List).length : 0),
        "training_minutes": fullPlan['total_training_minutes'] ?? fullPlan['training_minutes'] ?? 60,
        "items": fullPlan['items'] ?? [],
        
        // Day-by-day plan distribution
        "daily_plans": _createDailyPlans(fullPlan),
        
        // Additional fields for approval tracking - use actual plan data, not dummy data
        "workout_name": fullPlan['name'] ?? fullPlan['exercise_plan'] ?? fullPlan['exercise_plan_category'] ?? 'Custom Workout Plan',
        "category": fullPlan['exercise_plan_category'] ?? fullPlan['exercise_plan'] ?? fullPlan['category'] ?? 'Custom',
        "sets": fullPlan['sets'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['sets'] : null),
        "reps": fullPlan['reps'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['reps'] : null),
        "weight_kg": fullPlan['weight_kg'] ?? fullPlan['weight'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['weight_kg'] : null),
        "total_training_minutes": fullPlan['total_training_minutes'] ?? fullPlan['training_minutes'] ?? 60,
        "minutes": fullPlan['minutes'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['minutes'] : null),
        "exercise_types": fullPlan['exercise_types'] ?? (fullPlan['items'] is List ? (fullPlan['items'] as List).map((item) => item['exercise_types'] ?? item['workout_name'] ?? item['exercise_name']).join(', ') : null),
        "user_level": fullPlan['user_level'] ?? 'Intermediate',
        "notes": fullPlan['notes'] ?? 'Custom workout plan created by user',
        
        // AI-specific fields (if available)
        if (isAiPlan) ...{
          "goal": fullPlan['goal'] ?? fullPlan['future_goal'] ?? '',
          "age": fullPlan['age'],
          "height_cm": fullPlan['height_cm'],
          "weight_kg": fullPlan['weight_kg'] ?? fullPlan['weight'],
          "gender": fullPlan['gender'],
        }
      };

      print('🔍 Sending plan for approval with payload: $payload');
      print('🔍 Payload keys: ${payload.keys.toList()}');
      print('🔍 Payload values: ${payload.values.toList()}');
      print('🔍 Original plan data: $plan');
      print('🔍 Full plan data: $fullPlan');
      print('🔍 Plan name: ${fullPlan['name']}');
      print('🔍 Plan exercise_plan: ${fullPlan['exercise_plan']}');
      print('🔍 Plan exercise_plan_category: ${fullPlan['exercise_plan_category']}');
      print('🔍 Plan items: ${fullPlan['items']}');
      print('🔍 Plan items count: ${(fullPlan['items'] as List?)?.length ?? 0}');
      
      // Debug individual items
      if (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty) {
        final items = fullPlan['items'] as List;
        for (int i = 0; i < items.length; i++) {
          print('🔍 Item $i: ${items[i]}');
          print('🔍 Item $i keys: ${(items[i] as Map).keys.toList()}');
          print('🔍 Item $i exercise_types: ${(items[i] as Map)['exercise_types']}');
          print('🔍 Item $i workout_name: ${(items[i] as Map)['workout_name']}');
          print('🔍 Item $i exercise_name: ${(items[i] as Map)['exercise_name']}');
        }
      }
      
      print('🔍 Final workout_name: ${payload['workout_name']}');
      print('🔍 Final category: ${payload['category']}');
      print('🔍 Final items count: ${(payload['items'] as List?)?.length ?? 0}');
      print('🔍 Final exercise_types: ${payload['exercise_types']}');
      
      // Print complete payload for backend reference
      print('🔍 ===== COMPLETE PAYLOAD FOR BACKEND =====');
      print('🔍 Payload JSON: ${jsonEncode(payload)}');
      print('🔍 ===== END PAYLOAD =====');

      // Call the approval API
      await _controller.sendPlanForApproval(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan sent for approval successfully!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to send plan for approval: $e');
      print('❌ Error type: ${e.runtimeType}');
      if (mounted) {
        String errorMessage = 'Failed to send plan for approval';
        if (e.toString().contains('500')) {
          errorMessage = 'Server error: The backend could not process the request. Please check the plan data.';
        } else if (e.toString().contains('400')) {
          errorMessage = 'Invalid request: Please check the plan data format.';
        } else if (e.toString().contains('401')) {
          errorMessage = 'Authentication error: Please login again.';
        } else {
          errorMessage = 'Failed to send plan for approval: $e';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildApprovalButton(Map<String, dynamic> plan) {
    final planId = plan['id'] ?? DateTime.now().millisecondsSinceEpoch;
    
    return Obx(() {
      // Proactively verify approval via REST using web_plan_id/approval_id
      _controller.ensureApprovalCheckedForPlan(plan);
      final approvalStatus = _controller.getPlanApprovalStatus(planId);
      
      print('🔍 Building approval button for plan $planId with status: $approvalStatus');
      
      switch (approvalStatus) {
        case 'pending':
          return ElevatedButton(
            onPressed: null, // Disabled
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[400],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Pending'),
          );
        case 'approved':
          return ElevatedButton(
            onPressed: () {
              // Start the plan - move it to schedules
              _startPlan(plan);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Start Plan'),
          );
        default: // 'none'
          return ElevatedButton(
            onPressed: () async {
              await _sendPlanForApproval(plan);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Send Plan'),
          );
      }
    });
  }

  void _startPlan(Map<String, dynamic> plan) {
    // Move the plan to schedules by adding it to assignments
    // This is a simplified approach - in a real app, you might want to call an API
    print('🔍 Starting plan: ${plan['name']}');
    
    // For now, just show a success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Plan "${plan['name']}" started successfully!'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
    
    // You could also switch to the Schedules tab to show the started plan
    _controller.selectedTabIndex.value = 0;
  }

  // Method to create daily plans distribution
  List<Map<String, dynamic>> _createDailyPlans(Map<String, dynamic> fullPlan) {
    final items = fullPlan['items'] as List? ?? [];
    if (items.isEmpty) return [];
    
    // Calculate total days from start and end date
    final startDate = DateTime.tryParse(fullPlan['start_date']?.toString() ?? '') ?? DateTime.now();
    final endDate = DateTime.tryParse(fullPlan['end_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 7));
    final totalDays = endDate.difference(startDate).inDays + 1;
    
    print('🔍 Creating daily plans for $totalDays days with ${items.length} exercises');
    
    // Calculate workouts per day
    final totalMinutes = items.fold<int>(0, (sum, item) => sum + (item['minutes'] as int? ?? 0));
    final workoutsPerDay = totalMinutes < 80 ? 2 : 1;
    
    print('🔍 Workouts per day: $workoutsPerDay (total minutes: $totalMinutes)');
    
    List<Map<String, dynamic>> dailyPlans = [];
    
    for (int day = 0; day < totalDays; day++) {
      final dayDate = startDate.add(Duration(days: day));
      final dayItems = <Map<String, dynamic>>[];
      
      // Distribute exercises for this day
      for (int workout = 0; workout < workoutsPerDay; workout++) {
        final exerciseIndex = (day * workoutsPerDay + workout) % items.length;
        if (exerciseIndex < items.length) {
          dayItems.add(Map<String, dynamic>.from(items[exerciseIndex]));
        }
      }
      
      if (dayItems.isNotEmpty) {
        dailyPlans.add({
          'day': day + 1,
          'date': dayDate.toIso8601String().split('T')[0],
          'workouts': dayItems,
          'total_workouts': dayItems.length,
          'total_minutes': dayItems.fold<int>(0, (sum, item) => sum + (item['minutes'] as int? ?? 0)),
        });
      }
    }
    
    print('🔍 Created ${dailyPlans.length} daily plans');
    return dailyPlans;
  }

  // Helper method to show the exact payload that would be sent
  Future<void> _showPayloadForPlan(Map<String, dynamic> plan) async {
    try {
      // Get user information from the controller
      final userId = _controller.userId;
      final user = _controller.user;
      final userName = user?.name ?? user?.username ?? 'User $userId';
      final userPhone = user?.phone ?? user?.phoneNumber ?? '';
      
      // Determine plan type
      final aiPlans = _controller.aiGenerated;
      final isAiPlan = aiPlans.any((aiPlan) => aiPlan['id'] == plan['id']);
      final planType = isAiPlan ? 'ai_generated' : 'manual';
      
      // Ensure we have the full plan data with exercises
      Map<String, dynamic> fullPlan = Map<String, dynamic>.from(plan);
      if (plan['items'] == null || (plan['items'] as List).isEmpty) {
        try {
          if (isAiPlan) {
            fullPlan = await _controller.getAiGeneratedPlan(plan['id']);
          } else {
            fullPlan = await _controller.getManualPlan(plan['id']);
          }
        } catch (e) {
          print('❌ Failed to fetch full plan: $e');
        }
      }
      
      // Handle exercises_details if items is still empty
      if ((fullPlan['items'] == null || (fullPlan['items'] as List).isEmpty) && 
          fullPlan['exercises_details'] != null) {
        try {
          if (fullPlan['exercises_details'] is String) {
            final String exercisesJson = fullPlan['exercises_details'] as String;
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            fullPlan['items'] = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else if (fullPlan['exercises_details'] is List) {
            fullPlan['items'] = List<Map<String, dynamic>>.from(fullPlan['exercises_details'] as List);
          }
        } catch (e) {
          print('❌ Failed to parse exercises_details: $e');
        }
      }
      
      // Create the exact payload that would be sent
      final payload = {
        // User information
        "user_id": userId,
        "user_name": userName,
        "user_phone": userPhone,
        
        // Plan information - same structure as manual plan creation
        "plan_id": fullPlan['id'],
        "plan_type": planType,
        "exercise_plan_category": fullPlan['exercise_plan_category'] ?? fullPlan['exercise_plan'] ?? fullPlan['category'] ?? 'General',
        "start_date": fullPlan['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
        "end_date": fullPlan['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T')[0],
        "total_workouts": fullPlan['total_workouts'] ?? (fullPlan['items'] is List ? (fullPlan['items'] as List).length : 0),
        "training_minutes": fullPlan['total_training_minutes'] ?? fullPlan['training_minutes'] ?? 60,
        "items": fullPlan['items'] ?? [],
        
        // Day-by-day plan distribution
        "daily_plans": _createDailyPlans(fullPlan),
        
        // Additional fields for approval tracking
        "workout_name": fullPlan['name'] ?? fullPlan['exercise_plan'] ?? fullPlan['exercise_plan_category'] ?? 'Custom Workout Plan',
        "category": fullPlan['exercise_plan_category'] ?? fullPlan['exercise_plan'] ?? fullPlan['category'] ?? 'Custom',
        "sets": fullPlan['sets'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['sets'] : null),
        "reps": fullPlan['reps'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['reps'] : null),
        "weight_kg": fullPlan['weight_kg'] ?? fullPlan['weight'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['weight_kg'] : null),
        "total_training_minutes": fullPlan['total_training_minutes'] ?? fullPlan['training_minutes'] ?? 60,
        "minutes": fullPlan['minutes'] ?? (fullPlan['items'] is List && (fullPlan['items'] as List).isNotEmpty ? (fullPlan['items'] as List).first['minutes'] : null),
        "exercise_types": fullPlan['exercise_types'] ?? (fullPlan['items'] is List ? (fullPlan['items'] as List).map((item) => item['exercise_types'] ?? item['workout_name'] ?? item['exercise_name']).join(', ') : null),
        "user_level": fullPlan['user_level'] ?? 'Intermediate',
        "notes": fullPlan['notes'] ?? 'Custom workout plan created by user',
        
        // AI-specific fields (if available)
        if (isAiPlan) ...{
          "goal": fullPlan['goal'] ?? fullPlan['future_goal'] ?? '',
          "age": fullPlan['age'],
          "height_cm": fullPlan['height_cm'],
          "weight_kg": fullPlan['weight_kg'] ?? fullPlan['weight'],
          "gender": fullPlan['gender'],
        }
      };
      
      // Show the payload in a dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Muscle Building Plan Payload'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Complete JSON Payload:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    jsonEncode(payload),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Key Fields:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Plan ID: ${payload['plan_id']}'),
                Text('Plan Type: ${payload['plan_type']}'),
                Text('Workout Name: ${payload['workout_name']}'),
                Text('Category: ${payload['category']}'),
                Text('Total Workouts: ${payload['total_workouts']}'),
                Text('Training Minutes: ${payload['training_minutes']}'),
                Text('Items Count: ${(payload['items'] as List).length}'),
                Text('Exercise Types: ${payload['exercise_types']}'),
                Text('User Level: ${payload['user_level']}'),
                Text('Daily Plans Count: ${(payload['daily_plans'] as List).length}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                // Copy to clipboard
                Clipboard.setData(ClipboardData(text: jsonEncode(payload)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payload copied to clipboard!')),
                );
                Navigator.pop(context);
              },
              child: const Text('Copy'),
            ),
          ],
        ),
      );
      
    } catch (e) {
      print('❌ Error showing payload: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _extractUserLevel(Map<String, dynamic> plan) {
    String? level;
    
    // Check direct keys first
    if (plan['user_level'] != null) {
      level = plan['user_level'].toString();
    } else if (plan['userLevel'] != null) {
      level = plan['userLevel'].toString();
    } else if (plan['level'] != null) {
      level = plan['level'].toString();
    } else {
      // Deep search function
      String? deepFind(Map<String, dynamic> obj, String key) {
        for (final entry in obj.entries) {
          if (entry.key == key && entry.value != null) {
            return entry.value.toString();
          }
          if (entry.value is Map<String, dynamic>) {
            final result = deepFind(entry.value as Map<String, dynamic>, key);
            if (result != null) return result;
          }
        }
        return null;
      }
      
      // Check for assignment object
      if (plan['assignment'] is Map<String, dynamic>) {
        final assignment = plan['assignment'] as Map<String, dynamic>;
        level = deepFind(assignment, 'user_level') ?? deepFind(assignment, 'userLevel') ?? deepFind(assignment, 'level');
      }
      
      // Deep search in the entire plan object
      if (level == null) {
        level = deepFind(plan, 'user_level') ?? deepFind(plan, 'userLevel') ?? deepFind(plan, 'level');
      }
    }
    // If no level found, provide a default
    final finalLevel = level ?? 'Intermediate';
    print('🔍 Final user level: $finalLevel');
    return finalLevel;
  }

  int _calculateTotalDays(Map<String, dynamic> plan) {
    try {
      // Try to get total days from various possible fields
      final totalDays = plan['total_days'] ?? plan['days'] ?? plan['duration_days'] ?? plan['plan_duration'];
      if (totalDays != null) {
        return int.tryParse(totalDays.toString()) ?? 0;
      }
      
      // If no direct days field, try to calculate from start/end dates
      final startDate = plan['start_date']?.toString();
      final endDate = plan['end_date']?.toString();
      if (startDate != null && endDate != null && startDate.isNotEmpty && endDate.isNotEmpty) {
        try {
          final start = DateTime.parse(startDate);
          final end = DateTime.parse(endDate);
          final days = end.difference(start).inDays + 1;
          return days > 0 ? days : 0;
        } catch (e) {
          // Date parsing failed
        }
      }
      
      // If no dates, try to count from exercises_details/items
      final exercisesData = plan['exercises_details'] ?? plan['items'];
      if (exercisesData != null) {
        List<dynamic> exercises = [];
        if (exercisesData is String) {
          try {
            exercises = jsonDecode(exercisesData);
          } catch (e) {
            // JSON parsing failed
          }
        } else if (exercisesData is List) {
          exercises = exercisesData;
        }
        
        if (exercises.isNotEmpty) {
          // Count unique days from exercises
          final uniqueDays = <int>{};
          for (final exercise in exercises) {
            if (exercise is Map) {
              final day = exercise['day'] ?? exercise['day_number'] ?? exercise['dayNumber'];
              if (day != null) {
                final dayNum = int.tryParse(day.toString());
                if (dayNum != null) uniqueDays.add(dayNum);
              }
            }
          }
          return uniqueDays.length;
        }
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }

  List<String> _getExerciseTypes(Map<String, dynamic> plan) {
    try {
      final exercisesData = plan['exercises_details'] ?? plan['items'];
      if (exercisesData == null) return [];
      
      List<dynamic> exercises = [];
      if (exercisesData is String) {
        try {
          exercises = jsonDecode(exercisesData);
        } catch (e) {
          return [];
        }
      } else if (exercisesData is List) {
        exercises = exercisesData;
      }
      
      if (exercises.isEmpty) return [];
      
      // Extract unique exercise types
      final Set<String> types = {};
      for (final exercise in exercises) {
        if (exercise is Map) {
          // Try different possible field names for exercise type
          final type = exercise['exercise_type'] ?? 
                      exercise['type'] ?? 
                      exercise['category'] ?? 
                      exercise['muscle_group'] ?? 
                      exercise['body_part'] ??
                      exercise['exercise_category'];
          
          if (type != null && type.toString().trim().isNotEmpty) {
            types.add(type.toString().trim());
          }
        }
      }
      
      return types.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  List<Map<String, dynamic>> _getDayItems(Map<String, dynamic> plan, int dayIndex) {
    try {
      print('🔍 _getDayItems called for day $dayIndex');
      print('🔍 Plan ID: ${plan['id']}');
      print('🔍 Plan items: ${plan['items']}');
      print('🔍 Plan items type: ${plan['items'].runtimeType}');
      print('🔍 Plan exercises_details: ${plan['exercises_details']}');
      print('🔍 Plan exercises_details type: ${plan['exercises_details'].runtimeType}');
      
      // Align with PlanDetailPage rules: if total minutes < 80 and there are
      // multiple items, show 2 workouts per day; otherwise 1 per day.
      // First try items, then exercises_details
      List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    
      if (plan['items'] is List && (plan['items'] as List).isNotEmpty) {
        items = List<Map<String, dynamic>>.from(plan['items'] as List);
        print('🔍 Using plan items: ${items.length} items');
        for (int i = 0; i < items.length; i++) {
          print('🔍 Item $i: ${items[i]}');
        }
      } else if (plan['exercises_details'] != null) {
        print('🔍 Found exercises_details: ${plan['exercises_details']}');
        print('🔍 exercises_details type: ${plan['exercises_details'].runtimeType}');
        
        try {
          if (plan['exercises_details'] is List) {
            // Already parsed as List
            items = List<Map<String, dynamic>>.from(plan['exercises_details'] as List);
            print('🔍 Using exercises_details as List: ${items.length} items');
            for (int i = 0; i < items.length; i++) {
              print('🔍 Exercise $i: ${items[i]}');
            }
          } else if (plan['exercises_details'] is String) {
            // Parse JSON string
            final String exercisesJson = plan['exercises_details'] as String;
            print('🔍 Parsing exercises_details JSON string: $exercisesJson');
            final List<dynamic> parsedList = jsonDecode(exercisesJson);
            items = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            print('🔍 Parsed exercises_details: ${items.length} items');
            for (int i = 0; i < items.length; i++) {
              print('🔍 Parsed Exercise $i: ${items[i]}');
            }
          }
        } catch (e) {
          print('❌ Failed to parse exercises_details: $e');
          print('❌ Raw exercises_details: ${plan['exercises_details']}');
        }
      } else {
        print('🔍 No items or exercises_details found');
      }
      
      print('🔍 Processed items count: ${items.length}');
      if (items.isEmpty) {
        print('🔍 No items found, returning empty list');
        return const <Map<String, dynamic>>[];
      }
      final int totalMinutes = items.fold<int>(0, (sum, it) {
        final String? m = (it['minutes']?.toString() ?? it['training_minutes']?.toString());
        return sum + (int.tryParse(m ?? '0') ?? 0);
      });
      final int avg = items.isEmpty ? 0 : (totalMinutes / items.length).floor();
      print('🔍 Total minutes: $totalMinutes, Average: $avg');
      int perDay;
      if (avg < 50 && items.length > 2) {
        perDay = 3;
      } else if (avg < 80 && items.length > 1) {
        perDay = 2;
      } else {
        perDay = 1;
      }
      print('🔍 Workouts per day: $perDay');
      final int start = dayIndex * perDay;
      final int end = (start + perDay).clamp(0, items.length);
      print('🔍 Day $dayIndex: start=$start, end=$end, returning ${end - start} items');
      final result = items.sublist(start, end);
      for (int i = 0; i < result.length; i++) {
        print('🔍 Returning item $i: ${result[i]}');
      }
      return result;
    } catch (e) {
      print('❌ _getDayItems - Exception caught: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  Widget _buildDailySchedule(Map<String, dynamic> plan, {int dayIndex = 0}) {
    try {
      print('🔍 _buildDailySchedule called for day $dayIndex');
      final dayItems = _getDayItems(plan, dayIndex);
      print('🔍 Day items count: ${dayItems.length}');
      if (dayItems.isEmpty) {
        print('🔍 No day items, showing message');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'No workout details available. Please check if the plan has been properly assigned.',
            style: TextStyle(color: Colors.orange),
          ),
        );
      }
      final level = _extractUserLevel(plan);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('Daily Schedule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...dayItems.asMap().entries.map((entry) {
            final ex = entry.value;
            print('🔍 Exercise data: $ex');
            final workoutName = (ex['workout_name'] ?? ex['name'] ?? 'Workout').toString();
            final sets = ex['sets']?.toString() ?? '-';
            final reps = ex['reps']?.toString() ?? '-';
            final minutes = (ex['minutes'] ?? ex['training_minutes'])?.toString() ?? '0';
            final weight = (ex['weight_kg'] ?? ex['weight'])?.toString();
            final exTypes = ex['exercise_types']?.toString();
            print('🔍 Mapped values - Name: $workoutName, Sets: $sets, Reps: $reps, Minutes: $minutes, Weight: $weight, Types: $exTypes');
            
            // Check if this workout is completed
            final workoutKey = '${plan['id']}_${dayIndex}_${entry.key}';
            final isCompleted = _completedWorkouts[workoutKey] ?? false;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF2E7D32)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2E7D32)),
                        ),
                        child: Text('Day ${dayIndex + 1}', style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
                      ),
                      const Spacer(),
                      if (exTypes != null) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: Text('$exTypes Exercises', style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(workoutName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (level.isNotEmpty) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: Text(level, style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text('$minutes minutes', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fitness_center, size: 16, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text('$sets sets x $reps reps', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      if (weight != null) Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.monitor_weight, size: 16, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text('$weight kg', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.emoji_emotions_outlined, size: 16, color: Colors.black54),
                      SizedBox(width: 6),
                      Text('You can do it', style: TextStyle(color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (isCompleted) return; // Don't allow restart if completed
                            
                            // Start workout timer
                            final workoutKey = '${plan['id']}_${dayIndex}_${entry.key}';
                            final minutesInt = int.tryParse(minutes) ?? 0;
                            
                            if (minutesInt > 0) {
                              // Show loading state
                              setState(() {
                                _workoutTimers[workoutKey] = true;
                              });
                              
                              // Simulate workout completion after the specified minutes
                              await Future.delayed(Duration(minutes: minutesInt));
                              
                              // Mark as completed
                              setState(() {
                                _completedWorkouts[workoutKey] = true;
                                _workoutTimers[workoutKey] = false;
                              });
                              
                              // Check if all workouts for this day are completed
                              _checkDayCompletion(plan, dayIndex);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCompleted ? Colors.grey : const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Text(
                            _workoutTimers['${plan['id']}_${dayIndex}_${entry.key}'] == true 
                                ? 'Working Out...' 
                                : isCompleted 
                                    ? 'Completed' 
                                    : 'Start Workout'
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          })
        ],
      );
    } catch (e) {
      print('❌ _buildDailySchedule - Exception caught: $e');
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Error building daily schedule: $e',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light green background
      body: Column(
        children: [
          // Header
          Container(
            height: 60,
                  color: const Color(0xFF2E7D32),
            child: const Center(
              child: Text(
                'TRAINING',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          // Tab Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _tabController.animateTo(0);
                    },
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                        color: _tabController.index == 0 ? const Color(0xFF2E7D32) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF2E7D32),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Schedules',
                          style: TextStyle(
                            color: _tabController.index == 0 ? Colors.white : const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _tabController.animateTo(1);
                    },
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: _tabController.index == 1 ? const Color(0xFF2E7D32) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                  color: const Color(0xFF2E7D32),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Plans',
                          style: TextStyle(
                            color: _tabController.index == 1 ? Colors.white : const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
            ),
          ),
        ),
      ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: TabBarView(
        controller: _tabController,
        children: [
          _buildSchedulesTab(),
          _buildPlansTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulesTab() {
    return Obx(() {
      if (_controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      // Get assigned plans from assignments table
      final approvedPlans = _controller.assignments.toList();
      if (approvedPlans.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No scheduled workouts yet'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _controller.loadData();
                },
                child: const Text('Refresh Data'),
              ),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          _controller.planUserLevels.clear();
          _startedPlans.clear();
          _activePlan = null;
          await _controller.loadData();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
          children: [
            // Header
            const Text(
              'Scheduled Workouts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // Build all plan cards
            ...approvedPlans.asMap().entries.map((entry) {
              final index = entry.key;
              final plan = entry.value;
              
              return Column(
                children: [
                  _buildPlanCard(source: 'schedule', data: plan),
                  // Add daily schedule right after the active plan
                  if (_activePlan != null && 
                      (plan['id']?.toString() ?? '') == (_activePlan!['id']?.toString() ?? '')) ...[
                    const SizedBox(height: 16),
                    _buildDailyScheduleWidget(),
                  ],
                ],
              );
            }).toList(),
          ],
        ),
      );
    });
  }

  Widget _buildDailyScheduleWidget() {
    if (_activePlan == null) return const SizedBox.shrink();
    
    print('🔍 Building daily schedule for active plan: ${_activePlan!['id']}');
    print('🔍 Active plan items: ${_activePlan!['items']}');
    
    // Force fetch real data if items are missing (async operation)
    if (_activePlan!['items'] == null || (_activePlan!['items'] as List).isEmpty) {
      final assignmentId = _activePlan!['assignment_id'] ?? _activePlan!['id'];
      print('🔍 Fetching assignment details for daily schedule: $assignmentId');
      
      // Use FutureBuilder to handle async operation with error boundary
      return FutureBuilder<Map<String, dynamic>>(
        future: _controller.getAssignmentDetails(assignmentId),
        builder: (context, snapshot) {
          try {
            // Add safety check for mounted state
            if (!mounted) {
              return const SizedBox.shrink();
            }
            print('🔍 FutureBuilder - Connection state: ${snapshot.connectionState}');
            print('🔍 FutureBuilder - Has data: ${snapshot.hasData}');
            print('🔍 FutureBuilder - Has error: ${snapshot.hasError}');
            if (snapshot.hasError) {
              print('🔍 FutureBuilder - Error: ${snapshot.error}');
            }
            if (snapshot.hasData) {
              print('🔍 FutureBuilder - Data: ${snapshot.data}');
              print('🔍 FutureBuilder - Data items: ${snapshot.data!['items']}');
            }
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasData) {
              dynamic exercisesData = snapshot.data!['exercises_details'] ?? snapshot.data!['items'];
              
              // Handle JSON string parsing
              if (exercisesData is String) {
                try {
                  final List<dynamic> parsedList = jsonDecode(exercisesData);
                  exercisesData = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  print('🔍 FutureBuilder - Parsed exercises_details JSON string: ${exercisesData.length} items');
                } catch (e) {
                  print('❌ FutureBuilder - Failed to parse exercises_details JSON: $e');
                  exercisesData = snapshot.data!['items'] ?? [];
                }
              }
              
              // Create a copy of the plan with updated data to avoid mutation during build
              final updatedPlan = Map<String, dynamic>.from(_activePlan!);
              updatedPlan['items'] = exercisesData;
              updatedPlan['exercises_details'] = exercisesData;
              
              print('🔍 FutureBuilder - Created updated plan with items: ${updatedPlan['items']}');
              print('🔍 FutureBuilder - Items type: ${updatedPlan['items'].runtimeType}');
              print('🔍 FutureBuilder - Items length: ${(updatedPlan['items'] as List?)?.length ?? 'null'}');
              
              // Verify the data is properly set
              if (updatedPlan['items'] is List && (updatedPlan['items'] as List).isNotEmpty) {
                print('✅ FutureBuilder - Updated plan items successfully set with ${(updatedPlan['items'] as List).length} items');
              } else {
                print('❌ FutureBuilder - Updated plan items not properly set');
              }
              
              final planId = updatedPlan['id']?.toString() ?? '';
              final currentDay = _currentDay[planId] ?? 0;
              return _buildDailySchedule(updatedPlan, dayIndex: currentDay);
            } else {
              print('❌ Failed to fetch assignment details for daily schedule: ${snapshot.error}');
              final planId = _activePlan!['id']?.toString() ?? '';
              final currentDay = _currentDay[planId] ?? 0;
              return _buildDailySchedule(_activePlan!, dayIndex: currentDay);
            }
          } catch (e) {
            print('❌ FutureBuilder - Exception caught: $e');
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Error loading workout details: $e',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
        },
      );
    }
    
    final planId = _activePlan!['id']?.toString() ?? '';
    final currentDay = _currentDay[planId] ?? 0;
    return _buildDailySchedule(_activePlan!, dayIndex: currentDay);
  }

  Widget _buildPlansTab() {
    return RefreshIndicator(
      onRefresh: () async {
        print('🔄 Refreshing Plans tab...');
        await _controller.refreshPlans();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Create Plan button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Workout Plans',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
              ElevatedButton(
                onPressed: () {
                    Navigator.push(
                      context,
                    MaterialPageRoute(
                      builder: (context) => const CreatePlanPage(),
                    ),
                    );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                ),
              ),
                child: const Text('Create Plan'),
              ),
            ],
            ),
            const SizedBox(height: 16),
          
          // AI Plan Generator Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
              color: const Color(0xFFE8F5E8), // Light green background
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Plan Generator',
              style: TextStyle(
                    fontSize: 18,
                      fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Get a personalized workout plan based on your goals, experience, and available time.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                    child: ElevatedButton(
                      onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AiGeneratePlanPage(),
                        ),
                      );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      ),
                      child: const Text('Generate AI Plan'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

          // Manual Plans Section
            Obx(() {
            final manualPlans = _controller.plans;
              
              if (_controller.isLoading.value && !_controller.hasLoadedOnce.value) {
              return const Center(child: CircularProgressIndicator());
            }
            
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Manual Plans Header
                if (manualPlans.isNotEmpty) ...[
                  const Text(
                    'Manual Plans',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Manual Plans List
                  ...manualPlans.map((plan) => _buildPlanCard(source: 'manual', data: plan)).toList(),
                  const SizedBox(height: 24),
                ],
                ],
              );
            }),

          // AI Generated Plans Section
            Obx(() {
            final aiPlans = _controller.aiGenerated;
            
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // AI Plans Header
                if (aiPlans.isNotEmpty) ...[
                  const Text(
                    'AI Generated Plans',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // AI Plans List
                  ...aiPlans.map((plan) => _buildPlanCard(source: 'ai', data: plan)).toList(),
                  const SizedBox(height: 24),
                ],
                ],
              );
            }),
          
          // No Plans Message
          Obx(() {
            final manualPlans = _controller.plans;
            final aiPlans = _controller.aiGenerated;
            final hasAnyPlans = manualPlans.isNotEmpty || aiPlans.isNotEmpty;
            
            if (!hasAnyPlans && _controller.hasLoadedOnce.value) {
              return const Center(
                child: Text(
                  'No plans created yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }
            return const SizedBox.shrink();
            }),
          ],
        ),
        ),
      );
  }

  Widget _buildPlanCard({required String source, required Map<String, dynamic> data}) {
    // For schedule tab, show the assignment card design
    if (source == 'schedule') {
      return _buildScheduleCard(data);
    }
    
    // For manual plans, show manual plan card design
    if (source == 'manual') {
      return _buildManualPlanCard(data);
    }
    
    // For AI plans, show AI plan card design
    if (source == 'ai') {
      return _buildAiPlanCard(data);
    }
    
    // Fallback for other sources
    return _buildPlansTabCard(data);
  }

  Widget _buildManualPlanCard(Map<String, dynamic> data) {
    final planName = (data['name'] ?? data['exercise_plan'] ?? data['exercise_plan_category'] ?? data['title'] ?? 'Manual Plan').toString();
    
    // Calculate total days
    String totalDaysStr;
    final sd = data['start_date']?.toString();
    final ed = data['end_date']?.toString();
    if (sd != null && ed != null) {
      try {
        final start = DateTime.parse(sd);
        final end = DateTime.parse(ed);
        totalDaysStr = '${end.difference(start).inDays} Days';
      } catch (e) {
        totalDaysStr = '${data['total_days'] ?? 0} Days';
      }
    } else {
      totalDaysStr = '${data['total_days'] ?? 0} Days';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'MANUAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                totalDaysStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Plan Name
          Text(
            planName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Plan Details
          Row(
            children: [
              _buildInfoChip('Level', _extractUserLevel(data)),
            ],
          ),
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildApprovalButton(data),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    print('🔍 Manual Plan - Edit button clicked');
                    print('🔍 Manual Plan - Plan data: $data');
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditPlanPage(plan: data, isAi: false),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    foregroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                onPressed: () async {
                    print('🔍 Manual Plan - View button clicked');
                    print('🔍 Manual Plan - Plan data: $data');
                    
                    try {
                      await Get.to(() => PlanDetailPage(plan: data, isAi: false));
                  } catch (e) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: data, isAi: false),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    foregroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('View'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Payload button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
                onPressed: () {
                _showPayloadForPlan(data);
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                foregroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Show Payload for Backend'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiPlanCard(Map<String, dynamic> data) {
    final planName = (data['name'] ?? data['exercise_plan'] ?? data['exercise_plan_category'] ?? data['title'] ?? 'AI Plan').toString();
    
    // Calculate total days
    String totalDaysStr;
    final sd = data['start_date']?.toString();
    final ed = data['end_date']?.toString();
    if (sd != null && ed != null) {
      try {
        final start = DateTime.parse(sd);
        final end = DateTime.parse(ed);
        totalDaysStr = '${end.difference(start).inDays} Days';
      } catch (e) {
        totalDaysStr = '${data['total_days'] ?? 0} Days';
      }
    } else {
      totalDaysStr = '${data['total_days'] ?? 0} Days';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50)), // Different color for AI plans
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50), // Different color for AI
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AI GENERATED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                totalDaysStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Plan Name
          Text(
            planName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Plan Details
          Row(
            children: [
              _buildInfoChip('Level', _extractUserLevel(data)),
            ],
          ),
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildApprovalButton(data),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                onPressed: () {
                    print('🔍 AI Plan - Edit button clicked');
                    print('🔍 AI Plan - Plan data: $data');
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditPlanPage(plan: data, isAi: true),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF4CAF50)),
                    foregroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    print('🔍 AI Plan - View button clicked');
                    print('🔍 AI Plan - Plan data: $data');
                    
                    try {
                      await Get.to(() => PlanDetailPage(plan: data, isAi: true));
                  } catch (e) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: data, isAi: true),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF4CAF50)),
                    foregroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('View'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlansTabCard(Map<String, dynamic> data) {
    final planName = (data['name'] ?? data['exercise_plan'] ?? data['exercise_plan_category'] ?? data['title'] ?? 'Fitness Plan').toString();
    
    // Calculate total days
    String totalDaysStr;
    final sd = data['start_date']?.toString();
    final ed = data['end_date']?.toString();
    if (sd != null && ed != null) {
      try {
        final start = DateTime.parse(sd);
        final end = DateTime.parse(ed);
        totalDaysStr = '${end.difference(start).inDays} Days';
      } catch (e) {
        totalDaysStr = '${data['total_days'] ?? 0} Days';
      }
    } else {
      totalDaysStr = '${data['total_days'] ?? 0} Days';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Name
          Text(
            planName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          
          // Days and motivational text
          Row(
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(
                    totalDaysStr,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  const Icon(Icons.fitness_center, size: 16, color: Colors.black54),
                  const SizedBox(width: 4),
                  const Text(
                    'You can do it',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildApprovalButton(data),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                onPressed: () {
                    // Determine if this is an AI plan or manual plan
                    // Check if this plan exists in the AI generated list
                    final aiPlans = _controller.aiGenerated;
                    final isAi = aiPlans.any((aiPlan) => aiPlan['id'] == data['id']);
                    
                    print('🔍 Edit button clicked - Plan: ${data['name']}, isAi: $isAi');
                    print('🔍 Plan ID: ${data['id']}, AI Plans count: ${aiPlans.length}');
                    print('🔍 Plan data: $data');
                    
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => EditPlanPage(plan: data, isAi: isAi),
                    ),
                  );
                },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    foregroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    print('🔍 Plans Tab - View button clicked');
                    print('🔍 Plans Tab - Plan data: $data');
                    print('🔍 Plans Tab - Plan ID: ${data['id']}');
                    print('🔍 Plans Tab - Plan items: ${data['items']}');
                    print('🔍 Plans Tab - Plan exercises_details: ${data['exercises_details']}');
                    
                    try {
                      await Get.to(() => PlanDetailPage(plan: data, isAi: false));
                    } catch (e) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: data, isAi: false),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    foregroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('View'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> plan) {
    final category = (plan['category'] ?? plan['exercise_plan_category'] ?? plan['exercise_plan'] ?? plan['name'] ?? 'Workout').toString();
    final level = _extractUserLevel(plan);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
        color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (level.isNotEmpty) Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: Text(level, style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12)),
                  ),
                  // Add total days display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_calculateTotalDays(plan)} DAYS',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Show exercise types if available
          if (_getExerciseTypes(plan).isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _getExerciseTypes(plan).map((type) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
                ),
                child: Text(
                  type,
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.emoji_emotions_outlined, size: 16, color: Colors.black54),
              SizedBox(width: 6),
              Text('You can do it', style: TextStyle(color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                onPressed: () async {
                    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
                    if (planId == null) return;
                    
                    print('🔍 Start Plan clicked for plan ID: $planId');
                    
                    // Force fetch assignment details to get real items
                    try {
                      final assignmentId = plan['assignment_id'] ?? plan['id'];
                      print('🔍 Fetching assignment details for ID: $assignmentId');
                      
                      final assignmentDetails = await _controller.getAssignmentDetails(assignmentId);
                      print('🔍 Assignment details received: $assignmentDetails');
                      
                      // Update the plan with real data - map exercises_details to items
                      dynamic exercisesData = assignmentDetails['exercises_details'] ?? assignmentDetails['items'];
                      
                      // Handle JSON string parsing
                      if (exercisesData is String) {
                        try {
                          final List<dynamic> parsedList = jsonDecode(exercisesData);
                          exercisesData = parsedList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                          print('🔍 Parsed exercises_details JSON string: ${exercisesData.length} items');
                        } catch (e) {
                          print('❌ Failed to parse exercises_details JSON: $e');
                          exercisesData = assignmentDetails['items'] ?? [];
                        }
                      }
                      
                      plan['items'] = exercisesData;
                      plan['exercises_details'] = exercisesData;
                      plan['exercise_plan_category'] = assignmentDetails['exercise_plan_category'] ?? assignmentDetails['category'];
                      plan['user_level'] = assignmentDetails['user_level'];
                      
                      print('🔍 Plan updated with real data: $plan');
                  } catch (e) {
                      print('❌ Failed to fetch assignment details: $e');
                      await _controller.ensureItemsForPlan(plan);
                    }
                    
                    setState(() {
                      final current = _startedPlans[planId] ?? false;
                      _startedPlans[planId] = !current;
                      _activePlan = _startedPlans[planId]! ? plan : null;
                      
                      // Reset current day when starting a new plan
                      if (_startedPlans[planId]!) {
                        _currentDay[planId.toString()] = 0;
                        // Clear completed workouts for this plan
                        _completedWorkouts.removeWhere((key, value) => key.startsWith('${planId}_'));
                        _workoutTimers.removeWhere((key, value) => key.startsWith('${planId}_'));
                      }
                    });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(_startedPlans[int.tryParse(plan['id']?.toString() ?? '') ?? 0] == true ? 'Stop Plan' : 'Start Plan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    print('🔍 View Plan clicked - Plan data: $plan');
                    print('🔍 View Plan - Plan keys: ${plan.keys.toList()}');
                    print('🔍 View Plan - Plan items: ${plan['items']}');
                    print('🔍 View Plan - Plan exercises_details: ${plan['exercises_details']}');
                    
                    try {
                      await Get.to(() => PlanDetailPage(plan: plan, isAi: false));
                    } catch (e) {
                      await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: plan, isAi: false),
                        ),
                      );
                    }
                    _controller.planUserLevels.clear();
                    await _controller.loadData();
                    if (!mounted) return;
                    setState(() {});
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    foregroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('View Plan'),
                ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black26),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Map<String, dynamic> data, String source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
          title: const Text('Delete Plan'),
        content: const Text('Are you sure you want to delete this plan?'),
          actions: [
            TextButton(
            onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          TextButton(
              onPressed: () async {
              Navigator.pop(context);
              final planId = data['id'];
              if (mounted) {
                try {
                  if (source == 'ai') {
                    await _controller.deleteAiGeneratedPlan(planId);
                  } else {
                  await _controller.deleteManualPlan(planId);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Plan deleted successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete plan: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}