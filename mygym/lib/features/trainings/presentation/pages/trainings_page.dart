import 'dart:convert';
import 'package:flutter/material.dart';
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
      
      // Prepare the payload according to the API specification
      final payload = {
        // User information
        "user_id": userId,
        "user_name": userName,
        "user_phone": userPhone,
        
        // Plan information
        "start_date": plan['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
        "end_date": plan['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String().split('T')[0],
        "workout_name": plan['name'] ?? plan['exercise_plan'] ?? plan['exercise_plan_category'] ?? 'Workout Plan',
        "category": plan['exercise_plan_category'] ?? plan['exercise_plan'] ?? plan['category'] ?? 'General',
        "sets": plan['sets'] ?? 3,
        "reps": plan['reps'] ?? 12,
        "weight_kg": plan['weight_kg'] ?? plan['weight'] ?? 25.5,
        "total_training_minutes": plan['total_training_minutes'] ?? plan['training_minutes'] ?? 60,
        "total_workouts": plan['total_workouts'] ?? (plan['items'] is List ? (plan['items'] as List).length : 4),
        "minutes": plan['minutes'] ?? 45,
        "exercise_types": plan['exercise_types'] ?? "8, 6, 5",
        "user_level": plan['user_level'] ?? 'Intermediate',
        "notes": plan['notes'] ?? 'Focus on progressive overload this week'
      };

      print('🔍 Sending plan for approval with payload: $payload');
      print('🔍 Payload keys: ${payload.keys.toList()}');
      print('🔍 Payload values: ${payload.values.toList()}');

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
    return level ?? '';
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
    return SingleChildScrollView(
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

          // Manual Plans List
            Obx(() {
            final manualPlans = _controller.plans;
            final aiPlans = _controller.aiGenerated;
            final allPlans = [...manualPlans, ...aiPlans];
              
              if (_controller.isLoading.value && !_controller.hasLoadedOnce.value) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (allPlans.isEmpty && _controller.hasLoadedOnce.value) {
              return const Center(
                child: Text(
                  'No plans created yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }
            
              return Column(
              children: allPlans.map((plan) => _buildPlanCard(source: 'plans', data: plan)).toList(),
              );
            }),
          ],
        ),
      );
  }

  Widget _buildPlanCard({required String source, required Map<String, dynamic> data}) {
    // For schedule tab, show the assignment card design
    if (source == 'schedule') {
      return _buildScheduleCard(data);
    }
    
    // For plans tab, show the exact design from image
    if (source == 'plans') {
      return _buildPlansTabCard(data);
    }
    
    // Fallback for other sources
    return _buildPlansTabCard(data);
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
                child: ElevatedButton(
                  onPressed: () async {
                    await _sendPlanForApproval(data);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Send Plan for Approval'),
                ),
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
              if (level.isNotEmpty) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E7D32)),
                ),
                child: Text(level, style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12)),
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