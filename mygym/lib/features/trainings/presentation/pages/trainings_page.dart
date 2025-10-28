import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/schedules_controller.dart';
import '../controllers/plans_controller.dart';
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
  final SchedulesController _schedulesController = Get.find<SchedulesController>();
  final PlansController _plansController = Get.find<PlansController>();
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild when tab changes
      
      // Load data for the appropriate tab
      if (_tabController.index == 0) {
        print('🔄 Switched to Schedules tab, loading schedules data...');
        _schedulesController.loadSchedulesData();
      } else if (_tabController.index == 1) {
        print('🔄 Switched to Plans tab, loading plans data...');
        _plansController.loadPlansData();
      }
    });
    
    // Load initial data for both tabs and refresh automatically
    _loadInitialData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  Future<void> _loadInitialData() async {
    // Load schedules data
    await _schedulesController.loadSchedulesData();
    
    // Load plans data
    await _plansController.loadPlansData();
    
    // Refresh data to ensure we have the latest information
    if (mounted) {
    await _schedulesController.refreshSchedules();
    await _plansController.refreshPlans();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Training'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.textColor,
          unselectedLabelColor: AppTheme.textColor,
          tabs: const [
            Tab(text: 'Schedules'),
            Tab(text: 'Plans'),
              ],
            ),
          ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSchedulesTab(),
          _buildPlansTab(),
        ],
      ),
    );
  }

  Widget _buildSchedulesTab() {
    return Obx(() {
      if (_schedulesController.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      
      final approvedPlans = _schedulesController.assignments.toList();
      if (approvedPlans.isEmpty) {
        return const Center(
          child: Text('No scheduled workouts yet', style: TextStyle(color: AppTheme.textColor)),
        );
      }
      
      return RefreshIndicator(
        onRefresh: () async {
          if (mounted) {
          await _schedulesController.refreshSchedules();
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
          children: [
            // Header
            const Text(
              'Scheduled Workouts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
                    const SizedBox(height: 16),
            
            // Schedule Cards
            ...approvedPlans.map((plan) => _buildScheduleCard(plan)).toList(),
            
            // Active Schedule Display
            if (_schedulesController.activeSchedule != null)
              _buildActiveScheduleDisplay(),
          ],
        ),
      );
    });
  }

  Widget _buildPlansTab() {
    return RefreshIndicator(
      onRefresh: () async {
        print('🔄 Refreshing Plans tab...');
        if (mounted) {
        await _plansController.refreshPlans();
        }
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor),
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
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: AppTheme.textColor,
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
            _buildAiGeneratorCard(),
            const SizedBox(height: 16),

          // Manual Plans Section
            Obx(() {
              final manualPlans = _plansController.manualPlans;
              if (manualPlans.isNotEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Manual Plans',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
            TextButton.icon(
              onPressed: () async {
                await _plansController.manualRefreshApprovalStatus();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Status refreshed')),
                  );
                }
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh Status'),
            ),
          ],
                  ),
                  const SizedBox(height: 12),
                    ...manualPlans.map((plan) => _buildManualPlanCard(plan)).toList(),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            }),

          // Active Plan Daily Workouts Section
          Obx(() {
            final activePlan = _plansController.activePlan;
            print('🔍 TrainingsPage - Active plan check: $activePlan');
            if (activePlan != null) {
              print('🔍 TrainingsPage - Building active plan daily view for: ${activePlan['name'] ?? activePlan['exercise_plan_category']}');
              return _buildActivePlanDailyView(activePlan);
            }
            print('🔍 TrainingsPage - No active plan, showing empty');
              return const SizedBox.shrink();
            }),

          // AI Generated Plans Section
            Obx(() {
              final aiPlans = _plansController.aiGeneratedPlans;
              if (aiPlans.isNotEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                  const Text(
                    'AI Generated Plans',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            _plansController.clearAiGeneratedPlans();
                            _plansController.refreshAiGeneratedPlans();
                            await _plansController.manualRefreshApprovalStatus();
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh'),
                        ),
                      ],
                  ),
                  const SizedBox(height: 12),
                    ...aiPlans.map((plan) => _buildAiPlanCard(plan)).toList(),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            }),
          
          // No Plans Message
          Obx(() {
              final manualPlans = _plansController.manualPlans;
              final aiPlans = _plansController.aiGeneratedPlans;
            final hasAnyPlans = manualPlans.isNotEmpty || aiPlans.isNotEmpty;
            
              if (!hasAnyPlans && _plansController.hasLoadedOnce.value) {
              return const Center(
                child: Text(
                  'No plans created yet',
                  style: TextStyle(fontSize: 16, color: AppTheme.textColor),
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

  Widget _buildActivePlanDailyView(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final currentDay = _plansController.getCurrentDay(planId);
    
    print('🔍 TrainingsPage - _buildActivePlanDailyView called for plan $planId, day $currentDay');
    print('🔍 TrainingsPage - Plan data: $plan');
    
    final dayWorkouts = _getDayWorkouts(plan, currentDay);
    print('🔍 TrainingsPage - Day workouts count: ${dayWorkouts.length}');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Active Plan: ${plan['exercise_plan_category'] ?? plan['name'] ?? 'Workout Plan'}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 8),
        
        // Day Navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Day ${currentDay + 1}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textColor,
              ),
            ),
            Row(
              children: [
                if (currentDay > 0)
                  IconButton(
                    onPressed: () {
                      _plansController.setCurrentDay(planId, currentDay - 1);
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                if (currentDay < (_getTotalDays(plan) - 1))
                  IconButton(
                    onPressed: () {
                      _plansController.setCurrentDay(planId, currentDay + 1);
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Daily Workouts
        ..._getDayWorkouts(plan, currentDay).map((workout) => _buildPlanWorkoutItem(workout, planId, currentDay)).toList(),
        
        const SizedBox(height: 16),
      ],
    );
  }

  int _getTotalDays(Map<String, dynamic> plan) {
    if (plan['start_date'] != null && plan['end_date'] != null) {
      final start = DateTime.tryParse(plan['start_date']);
      final end = DateTime.tryParse(plan['end_date']);
      if (start != null && end != null) {
        return max(1, end.difference(start).inDays + 1);
      }
    }
    return max(1, (plan['total_days'] ?? 1) as int);
  }

  List<Map<String, dynamic>> _getDayWorkouts(Map<String, dynamic> plan, int dayIndex) {
    try {
      List<Map<String, dynamic>> workouts = [];
      
      print('🔍 TrainingsPage - _getDayWorkouts: plan keys: ${plan.keys.toList()}');
      print('🔍 TrainingsPage - _getDayWorkouts: plan[items]: ${plan['items']}');
      print('🔍 TrainingsPage - _getDayWorkouts: plan[exercises_details]: ${plan['exercises_details']}');
      print('🔍 TrainingsPage - _getDayWorkouts: plan[items] type: ${plan['items'].runtimeType}');
      print('🔍 TrainingsPage - _getDayWorkouts: plan[exercises_details] type: ${plan['exercises_details'].runtimeType}');
      
      // Get items from the plan
      if (plan['items'] is List) {
        workouts = (plan['items'] as List).cast<Map<String, dynamic>>();
        print('🔍 TrainingsPage - Found ${workouts.length} items in plan[items]');
        if (workouts.isNotEmpty) {
          print('🔍 TrainingsPage - First item keys: ${workouts.first.keys.toList()}');
        }
      } else if (plan['exercises_details'] is List) {
        workouts = (plan['exercises_details'] as List).cast<Map<String, dynamic>>();
        print('🔍 TrainingsPage - Found ${workouts.length} items in plan[exercises_details]');
        if (workouts.isNotEmpty) {
          print('🔍 TrainingsPage - First exercise keys: ${workouts.first.keys.toList()}');
        }
      } else {
        print('🔍 TrainingsPage - No items or exercises_details found in plan');
        print('🔍 TrainingsPage - Available keys: ${plan.keys.toList()}');
        // Check for other possible workout data keys
        for (String key in plan.keys) {
          if (plan[key] is List && (plan[key] as List).isNotEmpty) {
            print('🔍 TrainingsPage - Found list in key "$key": ${(plan[key] as List).length} items');
            if ((plan[key] as List).first is Map) {
              print('🔍 TrainingsPage - First item in "$key" keys: ${((plan[key] as List).first as Map).keys.toList()}');
            }
          }
        }
      }
      
      if (workouts.isEmpty) {
        print('🔍 TrainingsPage - No workouts found, returning empty list');
        return [];
      }
      
      // Apply distribution logic similar to schedules
      final distributed = _distributeWorkoutsForPlan(workouts, _getTotalDays(plan), dayIndex);
      print('🔍 TrainingsPage - After distribution: ${distributed.length} workouts for day $dayIndex');
      return distributed;
    } catch (e) {
      print('❌ Error getting day workouts: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _distributeWorkoutsForPlan(List<Map<String, dynamic>> workouts, int totalDays, int dayIndex) {
    if (workouts.isEmpty) return [];
    
    print('🔍 Plans Tab Distribution - Day ${dayIndex + 1}:');
    print('🔍   - Input workouts: ${workouts.length}');
    
    // Apply the same 80-minute rule as the controller's _generateDailyPlans method
    final List<Map<String, dynamic>> workoutsForDay = [];
    
    if (workouts.isNotEmpty) {
      // Add first workout
      final Map<String, dynamic> first = Map<String, dynamic>.from(workouts[0]);
      final int m1 = _extractWorkoutMinutes(first);
      workoutsForDay.add(first);
      
      print('🔍   - First workout: ${first['name'] ?? 'Unknown'} (${m1} min)');
      
      // Check if we can add a second workout (80-minute rule)
      if (workouts.length > 1) {
        final Map<String, dynamic> second = Map<String, dynamic>.from(workouts[1]);
        final int m2 = _extractWorkoutMinutes(second);
        final int totalMinutes = m1 + m2;
        
        print('🔍   - Second workout: ${second['name'] ?? 'Unknown'} (${m2} min)');
        print('🔍   - Total minutes: $totalMinutes');
        print('🔍   - 80-minute rule: ${totalMinutes <= 80 ? 'PASS' : 'FAIL'}');
        
        if (totalMinutes <= 80) {
          workoutsForDay.add(second);
          print('✅ Added 2 workouts for Day ${dayIndex + 1} (${totalMinutes} min total)');
        } else {
          print('⚠️ Skipped second workout for Day ${dayIndex + 1} (would exceed 80 min: ${totalMinutes} min)');
        }
      }
    }
    
    print('🔍   - Final workouts for day: ${workoutsForDay.length}');
    return workoutsForDay;
  }

  Widget _buildPlanWorkoutItem(Map<String, dynamic> item, int planId, int currentDay) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day and Workout Name
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Day ${currentDay + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                  ),
                ),
                if (item['exercise_types'] != null)
                  Text(
                    '${item['exercise_types']} Exercises',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Workout Name
            Text(
              item['name']?.toString() ?? item['workout_name']?.toString() ?? 'Exercise',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            
            // Workout Details
            Row(
              children: [
                Expanded(
                  child: _buildDetailChip('Sets', '${item['sets'] ?? 0}'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailChip('Reps', '${item['reps'] ?? 0}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailChip('Weight', '${_safeParseDouble(item['weight'] ?? item['weight_kg'] ?? 0)} kg'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailChip('Minutes', '${item['minutes'] ?? 0}'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Start Workout Button
            Obx(() {
              final workoutKey = '${planId}_${currentDay}_${item['name']}';
              final isStarted = _plansController.isWorkoutStarted(workoutKey);
              final isCompleted = _plansController.isWorkoutCompleted(workoutKey);
              final remainingMinutes = _plansController.getWorkoutRemainingMinutes(workoutKey);
              
              String buttonText;
              Color buttonColor;
              VoidCallback? onPressed;
              
              if (isCompleted) {
                buttonText = 'Completed';
                buttonColor = Colors.green;
                onPressed = null;
              } else if (isStarted) {
                buttonText = 'In Progress - $remainingMinutes minutes remaining';
                buttonColor = Colors.orange;
                onPressed = null;
              } else {
                buttonText = 'Start Workout';
                buttonColor = AppTheme.primaryColor;
                onPressed = () {
                  final totalMinutes = int.tryParse(item['minutes']?.toString() ?? '0') ?? 0;
                  _plansController.startWorkout(workoutKey, totalMinutes);
                };
              }
              
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(buttonText),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? 0.0;
  }

  // Helper function to calculate total days from start_date and end_date
  int _calculateTotalDays(Map<String, dynamic> plan) {
    try {
      final startDateStr = plan['start_date']?.toString();
      final endDateStr = plan['end_date']?.toString();
      
      if (startDateStr == null || endDateStr == null) {
        print('🔍 Calculate Total Days - Missing dates: start_date=$startDateStr, end_date=$endDateStr');
        return 0;
      }
      
      // Parse dates - handle different formats
      DateTime? startDate;
      DateTime? endDate;
      
      // Try parsing start_date
      try {
        startDate = DateTime.parse(startDateStr);
      } catch (e) {
        // Try alternative formats
        if (startDateStr.contains('/')) {
          final parts = startDateStr.split('/');
          if (parts.length == 3) {
            startDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        }
      }
      
      // Try parsing end_date
      try {
        endDate = DateTime.parse(endDateStr);
      } catch (e) {
        // Try alternative formats
        if (endDateStr.contains('/')) {
          final parts = endDateStr.split('/');
          if (parts.length == 3) {
            endDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        }
      }
      
      if (startDate == null || endDate == null) {
        print('🔍 Calculate Total Days - Failed to parse dates: start_date=$startDateStr, end_date=$endDateStr');
        return 0;
      }
      
      // Calculate difference in days
      final difference = endDate.difference(startDate).inDays;
      final totalDays = difference + 1; // Include both start and end days
      
      print('🔍 Calculate Total Days - Start: $startDate, End: $endDate, Total Days: $totalDays');
      return totalDays;
    } catch (e) {
      print('❌ Calculate Total Days - Error: $e');
      return 0;
    }
  }

  Widget _buildScheduleCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    
    // Debug: Print all available fields in the plan
    print('🔍 Schedule Card - Plan data: $plan');
    print('🔍 Schedule Card - Available fields: ${plan.keys.toList()}');
    
    // Debug: Check for total days fields specifically
    print('🔍 Schedule Card - Total Days Debug:');
    print('🔍   - total_days: ${plan['total_days']}');
    print('🔍   - days: ${plan['days']}');
    print('🔍   - duration: ${plan['duration']}');
    print('🔍   - plan_duration: ${plan['plan_duration']}');
    print('🔍   - total_duration: ${plan['total_duration']}');
    print('🔍   - workout_days: ${plan['workout_days']}');
    print('🔍   - training_days: ${plan['training_days']}');
    print('🔍   - start_date: ${plan['start_date']}');
    print('🔍   - end_date: ${plan['end_date']}');
    print('🔍   - assigned_at: ${plan['assigned_at']}');
    print('🔍   - created_at: ${plan['created_at']}');
    
    return Obx(() {
      final isStarted = _schedulesController.isScheduleStarted(planId);
      
      return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Expanded(
                  child: Text(
                    plan['exercise_plan_category']?.toString() ?? 
                    plan['category']?.toString() ?? 
                    plan['plan_category']?.toString() ?? 
                    plan['workout_name']?.toString() ?? 
                    'Training Plan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (isStarted) {
                      _schedulesController.stopSchedule(plan);
                    } else {
                      _schedulesController.startSchedule(plan);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isStarted ? Colors.red : AppTheme.primaryColor,
                    foregroundColor: AppTheme.textColor,
                  ),
                  child: Text(isStarted ? 'Stop Plan' : 'Start Plan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
            // Plan Category Name - try multiple field names
            if (plan['exercise_plan_category'] != null)
              Text('Plan Category: ${plan['exercise_plan_category']}', style: const TextStyle(color: AppTheme.textColor))
            else if (plan['category'] != null)
              Text('Plan Category: ${plan['category']}', style: const TextStyle(color: AppTheme.textColor))
            else if (plan['plan_category'] != null)
              Text('Plan Category: ${plan['plan_category']}', style: const TextStyle(color: AppTheme.textColor))
            else if (plan['workout_name'] != null)
              Text('Plan Category: ${plan['workout_name']}', style: const TextStyle(color: AppTheme.textColor)),
            // Total Days - calculate from start_date and end_date
            Builder(
              builder: (context) {
                // First try to calculate from plan data
                int calculatedDays = _calculateTotalDays(plan);
                
                if (calculatedDays > 0) {
                  return Text(
                    'Total Days: $calculatedDays',
                    style: const TextStyle(color: AppTheme.textColor)
                  );
                }
                
                // If no dates in plan data, try to fetch from assignment details
                return FutureBuilder<Map<String, dynamic>>(
                  future: _schedulesController.getAssignmentDetails(planId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Total Days: Loading...', style: TextStyle(color: AppTheme.textColor, fontStyle: FontStyle.italic));
                    }
                    
                    if (snapshot.hasError) {
                      // Fallback to direct field checking
                      final totalDays = plan['total_days'] ?? plan['days'] ?? plan['duration'] ?? 
                                      plan['plan_duration'] ?? plan['total_duration'] ?? 
                                      plan['workout_days'] ?? plan['training_days'];
                      return Text(
                        totalDays != null ? 'Total Days: $totalDays' : 'Total Days: Not specified',
                        style: const TextStyle(color: AppTheme.textColor, fontStyle: FontStyle.italic)
                      );
                    }
                    
                    final assignmentDetails = snapshot.data ?? {};
                    
                    // Try to calculate from assignment details
                    int assignmentCalculatedDays = _calculateTotalDays(assignmentDetails);
                    if (assignmentCalculatedDays > 0) {
                      return Text(
                        'Total Days: $assignmentCalculatedDays',
                        style: const TextStyle(color: AppTheme.textColor)
                      );
                    }
                    
                    // Fallback to direct field checking
                    final totalDays = assignmentDetails['total_days'] ?? assignmentDetails['days'] ?? 
                                    assignmentDetails['duration'] ?? assignmentDetails['plan_duration'] ?? 
                                    assignmentDetails['total_duration'] ?? assignmentDetails['workout_days'] ?? 
                                    assignmentDetails['training_days'] ?? plan['total_days'] ?? 
                                    plan['days'] ?? plan['duration'] ?? plan['plan_duration'] ?? 
                                    plan['total_duration'] ?? plan['workout_days'] ?? plan['training_days'];
                    
                    return Text(
                      totalDays != null ? 'Total Days: $totalDays' : 'Total Days: Not specified',
                      style: const TextStyle(color: AppTheme.textColor, fontStyle: FontStyle.italic)
                    );
                  },
                );
              },
            ),
            // User Level
            if (plan['user_level'] != null)
              Text('User Level: ${plan['user_level']}', style: const TextStyle(color: AppTheme.textColor)),
            
            // Motivational line with icon
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.fitness_center,
                  color: AppTheme.primaryColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'You can do it!',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => PlanDetailPage(plan: plan, isAi: false),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: const BorderSide(color: AppTheme.primaryColor),
            ),
            child: const Text('View Plan'),
          ),
          ],
        ),
      ),
    );
    });
  }

  Widget _buildManualPlanCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final isStarted = _plansController.isPlanStarted(planId);
    final approvalStatus = _plansController.getPlanApprovalStatus(planId);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Expanded(
                  child: Text(
                    // Use plan category as title instead of generic name
                    plan['exercise_plan_category']?.toString() ?? 'Manual Plan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildApprovalButton(plan, approvalStatus),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showDeleteConfirmation(plan, false),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Delete Plan',
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
            
            // Plan Details Row
            Row(
              children: [
            // Total Days
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'Total Days: ${_getTotalDays(plan)}',
                        style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
                      ),
                    ],
                  ),
                ),
                // User Level
                if (plan['user_level'] != null)
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          'Level: ${plan['user_level']}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // User Level
            if (plan['user_level'] != null)
              Text('User Level: ${plan['user_level']}'),
            const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: plan, isAi: false),
                      ),
                    );
                  },
                    child: const Text('View Plan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditPlanPage(plan: plan),
                        ),
                      );
                    },
                    child: const Text('Edit Plan'),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildAiPlanCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final isStarted = _plansController.isPlanStarted(planId);
    final approvalStatus = _plansController.getPlanApprovalStatus(planId);
    
    // Debug: Check what user_level data we're receiving
    print('🔍 AI Plan Card - Plan ID: $planId');
    print('🔍 AI Plan Card - User Level: "${plan['user_level']}"');
    print('🔍 AI Plan Card - Plan keys: ${plan.keys.toList()}');
    
    // Calculate total days from start and end dates
    int totalDays = 0;
    if (plan['start_date'] != null && plan['end_date'] != null) {
      try {
        final startDate = DateTime.parse(plan['start_date'].toString());
        final endDate = DateTime.parse(plan['end_date'].toString());
        totalDays = endDate.difference(startDate).inDays + 1;
      } catch (e) {
        totalDays = plan['total_days'] ?? plan['plan_duration_days'] ?? 0;
      }
    } else {
      totalDays = plan['total_days'] ?? plan['plan_duration_days'] ?? 0;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Expanded(
                  child: Text(
                    // Use plan category as title instead of generic name
                    plan['exercise_plan_category']?.toString() ?? 'AI Generated Plan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildApprovalButton(plan, approvalStatus),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showDeleteConfirmation(plan, true),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Delete Plan',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Plan Details Row
          Row(
            children: [
            // Total Days
              Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '$totalDays Days',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                ),
              ),
              const SizedBox(width: 8),
                
            // User Level
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          plan['user_level']?.toString() ?? 'Beginner',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Motivational "You can do it" line with icon
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.1),
                    AppTheme.primaryColor.withOpacity(0.05),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'You can do it! 💪',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                          builder: (context) => PlanDetailPage(plan: plan, isAi: true),
                    ),
                  );
                },
                    child: const Text('View Plan'),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildApprovalButton(Map<String, dynamic> plan, String approvalStatus) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    
    switch (approvalStatus) {
      case 'pending':
        return ElevatedButton(
          onPressed: () async {
            // Allow resending pending plans after editing
            try {
              // Determine if this is an AI or manual plan
              final planType = plan['plan_type']?.toString().toLowerCase();
              bool isAiPlan = false;
              
              // Proper plan type detection - use the same logic as PlansController
              if (planType == 'ai_generated') {
                isAiPlan = true;
              } else if (planType == 'manual') {
                isAiPlan = false;
              } else {
                // Check for explicit AI plan indicators (more specific)
                final hasExplicitAiIndicators = plan.containsKey('request_id') || // AI plans have request_id
                                             plan.containsKey('ai_generated') || 
                                             plan.containsKey('gemini_generated') ||
                                             plan.containsKey('ai_plan_id');
                
                // Check for explicit manual plan indicators
                final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                                 plan['assigned_by'] == null && 
                                                 plan['assignment_id'] == null && 
                                                 plan['web_plan_id'] == null &&
                                                 !plan.containsKey('request_id'); // Manual plans don't have request_id
                
                print('🔍 Button Logic - Plan ID: $planId');
                print('🔍 Button Logic - Plan Type: $planType');
                print('🔍 Button Logic - Has AI Indicators: $hasExplicitAiIndicators');
                print('🔍 Button Logic - Has Manual Indicators: $hasExplicitManualIndicators');
                print('🔍 Button Logic - Has request_id: ${plan.containsKey('request_id')}');
                print('🔍 Button Logic - Has created_by: ${plan.containsKey('created_by')}');
                
                // If we have explicit manual indicators, it's definitely a manual plan
                if (hasExplicitManualIndicators) {
                  isAiPlan = false;
                  print('🔍 Button Logic - Detected as MANUAL plan');
                }
                // If we have explicit AI indicators and no manual indicators, it's an AI plan
                else if (hasExplicitAiIndicators && !hasExplicitManualIndicators) {
                  isAiPlan = true;
                  print('🔍 Button Logic - Detected as AI plan');
                }
                // Default to manual plan if unclear
                else {
                  isAiPlan = false;
                  print('🔍 Button Logic - Defaulting to MANUAL plan');
                }
              }
              
              Map<String, dynamic> result;
              if (isAiPlan) {
                result = await _plansController.sendAiPlanForApproval(plan);
              } else {
                result = await _plansController.sendManualPlanForApproval(plan);
              }
              
              if (mounted && _scaffoldMessenger != null) {
                _scaffoldMessenger!.showSnackBar(
                  const SnackBar(
                    content: Text('Plan resent for approval successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              
              // Refresh the plans to update the approval status
              if (mounted) {
                await _plansController.refreshPlans();
              }
              
            } catch (e) {
              if (mounted && _scaffoldMessenger != null) {
                _scaffoldMessenger!.showSnackBar(
                  SnackBar(
                    content: Text('Failed to resend plan for approval: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.textColor,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh, size: 18),
              const SizedBox(width: 8),
              const Text('Resend Plan'),
            ],
          ),
        );
      case 'approved':
        // Check if plan has been modified since approval
        final hasBeenModified = _plansController.hasPlanBeenModifiedSinceApproval(planId);
        
        // Debug: Check modification status
        print('🔍 Button Logic - Plan ID: $planId');
        print('🔍 Button Logic - Approval Status: $approvalStatus');
        print('🔍 Button Logic - Has Been Modified: $hasBeenModified');
        print('🔍 Button Logic - Plan Type: ${plan['plan_type']}');
        print('🔍 Button Logic - Exercise Category: ${plan['exercise_plan_category']}');
        print('🔍 Button Logic - Modification Map: ${_plansController.planModifiedSinceApproval}');
        
        // Determine if this is an AI or manual plan
        final planType = plan['plan_type']?.toString().toLowerCase();
        bool isAiPlan = false;
        
        // Proper plan type detection - use the same logic as PlansController
        if (planType == 'ai_generated') {
          isAiPlan = true;
        } else if (planType == 'manual') {
          isAiPlan = false;
        } else {
          // Check for explicit AI plan indicators (more specific)
          final hasExplicitAiIndicators = plan.containsKey('request_id') || // AI plans have request_id
                                       plan.containsKey('ai_generated') || 
                                       plan.containsKey('gemini_generated') ||
                                       plan.containsKey('ai_plan_id');
          
          // Check for explicit manual plan indicators
          final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                           plan['assigned_by'] == null && 
                                           plan['assignment_id'] == null && 
                                           plan['web_plan_id'] == null &&
                                           !plan.containsKey('request_id'); // Manual plans don't have request_id
          
          // If we have explicit manual indicators, it's definitely a manual plan
          if (hasExplicitManualIndicators) {
            isAiPlan = false;
          }
          // If we have explicit AI indicators and no manual indicators, it's an AI plan
          else if (hasExplicitAiIndicators && !hasExplicitManualIndicators) {
            isAiPlan = true;
          }
          // Default to manual plan if unclear
          else {
            isAiPlan = false;
          }
        }
        
        if (isAiPlan) {
          // For AI plans: Show only one button that changes based on modification status
          if (hasBeenModified) {
            // Show only Resend button if AI plan has been modified
            return ElevatedButton(
              onPressed: () async {
                try {
                  final result = await _plansController.sendAiPlanForApproval(plan);
                  
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      const SnackBar(
                        content: Text('AI plan resent for approval successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  // Refresh the plans to update the approval status
                  if (mounted) {
                    await _plansController.refreshPlans();
                  }
                  
                } catch (e) {
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('Failed to resend AI plan for approval: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh, size: 18),
                  const SizedBox(width: 8),
                  const Text('Resend'),
                ],
              ),
            );
          } else {
            // Show Start/Stop button if AI plan hasn't been modified
            final isStarted = _plansController.isPlanStarted(planId);
            if (isStarted) {
        return ElevatedButton(
          onPressed: () {
                  _plansController.stopPlan(plan);
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Stop Plan'),
              );
            }
            return ElevatedButton(
              onPressed: () async {
            _plansController.startPlan(plan);
                setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.textColor,
          ),
          child: const Text('Start Plan'),
            );
          }
        } else {
          // For manual plans: Show only Resend button if modified (convert Start Plan to Resend)
          print('🔍 Button Logic - Manual Plan - Has Been Modified: $hasBeenModified');
          if (hasBeenModified) {
            return ElevatedButton(
              onPressed: () async {
                try {
                  final result = await _plansController.sendManualPlanForApproval(plan);
                  
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      const SnackBar(
                        content: Text('Manual plan resent for approval successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  
                  // Refresh the plans to update the approval status
                  if (mounted) {
                    await _plansController.refreshPlans();
                  }
                  
                } catch (e) {
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('Failed to resend manual plan for approval: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh, size: 16),
                  const SizedBox(width: 4),
                  const Text('Resend Plan'),
                ],
              ),
            );
          } else {
            // Show only Start Plan button if manual plan hasn't been modified
            final isStarted = _plansController.isPlanStarted(planId);
            if (isStarted) {
              return ElevatedButton(
                onPressed: () {
                  _plansController.stopPlan(plan);
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Stop Plan'),
              );
            }
            return ElevatedButton(
              onPressed: () async {
                _plansController.startPlan(plan);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: AppTheme.textColor,
              ),
              child: const Text('Start Plan'),
            );
          }
        }
      case 'rejected':
        // If the plan was edited after rejection, allow resending
        final hasBeenModified = _plansController.hasPlanBeenModifiedSinceApproval(planId);
        if (hasBeenModified) {
          return ElevatedButton(
            onPressed: () async {
              try {
                // Determine plan type - use the same logic as PlansController
                final planType = plan['plan_type']?.toString().toLowerCase();
                bool isAiPlan = false;
                if (planType == 'ai_generated') {
                  isAiPlan = true;
                } else if (planType == 'manual') {
                  isAiPlan = false;
                } else {
                  // Check for explicit AI plan indicators (more specific)
                  final hasExplicitAiIndicators = plan.containsKey('request_id') || // AI plans have request_id
                                               plan.containsKey('ai_generated') || 
                                               plan.containsKey('gemini_generated') ||
                                               plan.containsKey('ai_plan_id');
                  
                  // Check for explicit manual plan indicators
                  final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                                   plan['assigned_by'] == null && 
                                                   plan['assignment_id'] == null && 
                                                   plan['web_plan_id'] == null &&
                                                   !plan.containsKey('request_id'); // Manual plans don't have request_id
                  
                  // If we have explicit manual indicators, it's definitely a manual plan
                  if (hasExplicitManualIndicators) {
                    isAiPlan = false;
                  }
                  // If we have explicit AI indicators and no manual indicators, it's an AI plan
                  else if (hasExplicitAiIndicators && !hasExplicitManualIndicators) {
                    isAiPlan = true;
                  }
                  // Default to manual plan if unclear
                  else {
                    isAiPlan = false;
                  }
                }
                if (isAiPlan) {
                  await _plansController.sendAiPlanForApproval(plan);
                } else {
                  await _plansController.sendManualPlanForApproval(plan);
                }
                if (mounted && _scaffoldMessenger != null) {
                  _scaffoldMessenger!.showSnackBar(
                    const SnackBar(content: Text('Plan resent for approval'), backgroundColor: Colors.green),
                  );
                }
                if (mounted) await _plansController.refreshPlans();
              } catch (e) {
                if (mounted && _scaffoldMessenger != null) {
                  _scaffoldMessenger!.showSnackBar(
                    SnackBar(content: Text('Failed to resend: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Resend'),
          );
        }
        // Not modified: show rejected indicator only
        return ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Rejected'),
        );
      default:
        return ElevatedButton(
                  onPressed: () async {
            // Send plan for approval
            try {
              // Determine if this is an AI or manual plan
              final planType = plan['plan_type']?.toString().toLowerCase();
              bool isAiPlan = false;
              
              // Proper plan type detection - use the same logic as PlansController
              if (planType == 'ai_generated') {
                isAiPlan = true;
              } else if (planType == 'manual') {
                isAiPlan = false;
              } else {
                // Check for explicit AI plan indicators (more specific)
                final hasExplicitAiIndicators = plan.containsKey('request_id') || // AI plans have request_id
                                             plan.containsKey('ai_generated') || 
                                             plan.containsKey('gemini_generated') ||
                                             plan.containsKey('ai_plan_id');
                
                // Check for explicit manual plan indicators
                final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                                 plan['assigned_by'] == null && 
                                                 plan['assignment_id'] == null && 
                                                 plan['web_plan_id'] == null &&
                                                 !plan.containsKey('request_id'); // Manual plans don't have request_id
                
                // If we have explicit manual indicators, it's definitely a manual plan
                if (hasExplicitManualIndicators) {
                  isAiPlan = false;
                }
                // If we have explicit AI indicators and no manual indicators, it's an AI plan
                else if (hasExplicitAiIndicators && !hasExplicitManualIndicators) {
                  isAiPlan = true;
                }
                // Default to manual plan if unclear
                else {
                  isAiPlan = false;
                }
              }
              
              print('🔍 Plan type detection:');
              print('🔍   - plan_type: $planType');
              print('🔍   - exercise_plan_category: ${plan['exercise_plan_category']}');
              print('🔍   - user_level: ${plan['user_level']}');
              print('🔍   - created_by: ${plan['created_by']}');
              print('🔍   - assigned_by: ${plan['assigned_by']}');
              print('🔍   - isAiPlan: $isAiPlan');
              
              Map<String, dynamic> result;
              if (isAiPlan) {
                print('🔍 Sending AI plan for approval...');
                result = await _plansController.sendAiPlanForApproval(plan);
              } else {
                print('🔍 Sending manual plan for approval...');
                result = await _plansController.sendManualPlanForApproval(plan);
              }
              
              if (mounted && _scaffoldMessenger != null) {
              _scaffoldMessenger!.showSnackBar(
                const SnackBar(
                    content: Text('Plan sent for approval successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              
              // Refresh the plans to update the approval status
              if (mounted) {
                await _plansController.refreshPlans();
              }
              
            } catch (e) {
              if (mounted && _scaffoldMessenger != null) {
                _scaffoldMessenger!.showSnackBar(
                  SnackBar(
                    content: Text('Failed to send plan for approval: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.textColor,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send, size: 18),
              const SizedBox(width: 8),
              const Text('Send Plan'),
            ],
          ),
        );
    }
  }

  Widget _buildAiGeneratorCard() {
    return Card(
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            const Text(
              'AI Plan Generator',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get a personalized workout plan based on your goals, experience, and available time.',
              style: TextStyle(color: AppTheme.textColor),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                        context,
                        MaterialPageRoute(
                    builder: (context) => const AiGeneratePlanPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: AppTheme.textColor,
              ),
              child: const Text('Generate AI Plan'),
              ),
            ],
          ),
      ),
    );
  }

  Widget _buildActiveScheduleDisplay() {
    final activeSchedule = _schedulesController.activeSchedule!;
    print('🔍 Active Schedule Data: $activeSchedule');
    print('🔍 Available keys: ${activeSchedule.keys}');
    
    // Use assignment_id if available, otherwise fall back to id
    final planId = int.tryParse(activeSchedule['assignment_id']?.toString() ?? activeSchedule['id']?.toString() ?? '') ?? 0;
    print('🔍 Using planId: $planId for assignment details');
    final currentDay = _schedulesController.getCurrentDay(planId);
    
    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    'Active Schedule - Day ${currentDay + 1}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _schedulesController.stopSchedule(activeSchedule);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: AppTheme.textColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
            Text('Plan: ${activeSchedule['exercise_plan_category'] ?? 'Workout Plan'}', style: const TextStyle(color: AppTheme.textColor)),
            const SizedBox(height: 16),
            
            // Day Plan Content
            FutureBuilder<Map<String, dynamic>>(
              future: _schedulesController.getAssignmentDetails(planId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Text('Error loading plan details: ${snapshot.error}');
                }
                
                final planDetails = snapshot.data ?? activeSchedule;
                final dayItems = _getDayItems(planDetails, currentDay);
                
                if (dayItems.isEmpty) {
                  return const Text('No workouts for this day', style: TextStyle(color: AppTheme.textColor));
                }
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Workouts (${dayItems.length} workouts)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
            const SizedBox(height: 8),
                    ...dayItems.map((item) => _buildWorkoutItem(item)).toList(),
                  ],
                );
              },
                ),
            ],
          ),
      ),
    );
  }

  List<Map<String, dynamic>> _getDayItems(Map<String, dynamic> plan, int dayIndex) {
    try {
      print('🔍 Getting day items for day $dayIndex');
      print('🔍 Plan keys: ${plan.keys}');
      
      // Check if this is an API response with nested data
      Map<String, dynamic> actualPlan = plan;
      if (plan.containsKey('success') && plan.containsKey('data')) {
        print('🔍 Detected API response format, extracting data field');
        actualPlan = plan['data'] ?? {};
        print('🔍 Actual plan keys: ${actualPlan.keys}');
      }
      
      // Try to get daily plans first
      final dailyPlans = actualPlan['daily_plans'];
      if (dailyPlans is List && dailyPlans.isNotEmpty && dayIndex < dailyPlans.length) {
        final dayPlan = dailyPlans[dayIndex];
        if (dayPlan is Map<String, dynamic>) {
          final workouts = dayPlan['workouts'];
          if (workouts is List) {
            print('🔍 Found ${workouts.length} workouts in daily_plans');
            return _applySchedulesDistributionLogic(workouts.cast<Map<String, dynamic>>());
          }
        }
      }
      
      // Fallback to exercises_details
      final exercisesDetails = actualPlan['exercises_details'];
      print('🔍 exercises_details type: ${exercisesDetails.runtimeType}');
      print('🔍 exercises_details value: $exercisesDetails');
      
      List<Map<String, dynamic>> workouts = [];
      
      if (exercisesDetails is List && exercisesDetails.isNotEmpty) {
        print('🔍 Found ${exercisesDetails.length} exercises in exercises_details');
        workouts = exercisesDetails.cast<Map<String, dynamic>>();
      } else if (exercisesDetails is String) {
        // Handle JSON string format
        try {
          final List<dynamic> parsed = jsonDecode(exercisesDetails);
          print('🔍 Parsed ${parsed.length} exercises from JSON string');
          workouts = parsed.cast<Map<String, dynamic>>();
                        } catch (e) {
          print('❌ Error parsing exercises_details JSON: $e');
        }
      }
      
      // Fallback to items
      if (workouts.isEmpty) {
        final items = actualPlan['items'];
        if (items is List && items.isNotEmpty) {
          print('🔍 Found ${items.length} items in items');
          workouts = items.cast<Map<String, dynamic>>();
        }
      }
      
      // Apply workout distribution logic
      if (workouts.isNotEmpty) {
        return _applySchedulesDistributionLogic(workouts);
      }
      
      // If no data found, return empty list
      print('🔍 No workout data found');
      return [];
                  } catch (e) {
      print('Error getting day items: $e');
      return [];
    }
  }

  // SCHEDULES TAB: Assigned plans - limit to 2 workouts per day
  List<Map<String, dynamic>> _applySchedulesDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 SCHEDULES TAB DISTRIBUTION - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Schedules Tab Workout $i: ${workout['name']} - ${_extractWorkoutMinutes(workout)} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = _extractWorkoutMinutes(workout);
      totalMinutes += minutes;
      print('🔍 Schedules Tab Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 SCHEDULES TAB Total workout minutes: $totalMinutes');
    print('🔍 SCHEDULES TAB Number of workouts: ${workouts.length}');
    
    // SCHEDULES TAB: Per-day pair rule – try 2 consecutive workouts; if combined > 80, show only 1
    if (workouts.length >= 2) {
      // Use day 0 pairing here; actual day pairing is handled in controller for active schedule.
      final int m1 = _extractWorkoutMinutes(workouts[0]);
      final int m2 = _extractWorkoutMinutes(workouts[1]);
      final int combined = m1 + m2;
      if (combined > 80) {
        print('🔍 SCHEDULES TAB ✅ LIMIT (combined > 80): showing 1');
        return [workouts[0]];
      }
      print('🔍 SCHEDULES TAB ✅ LIMIT (combined <= 80): showing 2');
      return workouts.take(2).toList();
    }
    
    print('🔍 SCHEDULES TAB ✅ APPLYING: showing all ${workouts.length} workouts');
      return workouts;
    }

  // PLANS TAB: Manual plans - apply same limiting logic as Schedules
  List<Map<String, dynamic>> _applyPlansDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 PLANS TAB DISTRIBUTION - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Plans Tab Workout $i: ${workout['name']} - ${_extractWorkoutMinutes(workout)} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = _extractWorkoutMinutes(workout);
      totalMinutes += minutes;
      print('🔍 Plans Tab Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 PLANS TAB Total workout minutes: $totalMinutes');
    print('🔍 PLANS TAB Number of workouts: ${workouts.length}');
    
    // PLANS TAB: Per-day pair rule – try 2; if combined > 80, show only 1
    if (workouts.length >= 2) {
      final int m1 = _extractWorkoutMinutes(workouts[0]);
      final int m2 = _extractWorkoutMinutes(workouts[1]);
      final int combined = m1 + m2;
      if (combined > 80) {
        print('🔍 PLANS TAB ✅ LIMIT (combined > 80): showing 1');
        return [workouts[0]];
      }
      print('🔍 PLANS TAB ✅ LIMIT (combined <= 80): showing 2');
      return workouts.take(2).toList();
    }
    
    print('🔍 PLANS TAB ✅ APPLYING: showing all ${workouts.length} workouts');
    return workouts;
  }

  // Extract minutes from various possible keys safely
  int _extractWorkoutMinutes(Map<String, dynamic> workout) {
    final dynamic raw = workout['minutes'] ?? workout['training_minutes'] ?? workout['trainingMinutes'] ?? workout['duration'];
    if (raw == null) return 0;
    final String s = raw.toString();
    final int? i = int.tryParse(s);
    if (i != null) return i;
    final double? d = double.tryParse(s);
    return d?.round() ?? 0;
  }


  Widget _buildWorkoutItem(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day and Workout Name
            Obx(() {
              final activeSchedule = _schedulesController.activeSchedule;
              if (activeSchedule == null) return const SizedBox.shrink();
              
              final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
              final currentDay = _schedulesController.getCurrentDay(planId);
              
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Day ${currentDay + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textColor,
                    ),
                  ),
                  if (item['exercise_types'] != null)
                    Text(
                      '${item['exercise_types']} Exercises',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textColor,
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            
            // Workout Name
            Text(
              item['name']?.toString() ?? item['workout_name']?.toString() ?? 'Exercise',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            
            // Sets & Reps
            if (item['sets'] != null || item['reps'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.fitness_center, size: 16, color: AppTheme.textColor),
                  const SizedBox(width: 8),
                  Text(
                    '${item['sets'] ?? 'N/A'} sets x ${item['reps'] ?? 'N/A'} reps',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
                ),
            ],
          ),
              const SizedBox(height: 8),
            ],
            
            // Weight
            if (item['weight_kg'] != null || item['weight_min_kg'] != null || item['weight_max_kg'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.sports_gymnastics, size: 16, color: AppTheme.textColor),
                  const SizedBox(width: 8),
                  Text(
                    _formatWeightDisplay(item),
                    style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
          ),
        ],
      ),
              const SizedBox(height: 8),
            ],
            
            // Duration
            if (item['minutes'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: AppTheme.textColor),
                  const SizedBox(width: 8),
                  Text(
                    '${item['minutes']} minutes',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            
            // Motivational text
            Row(
              children: [
                const Icon(Icons.emoji_emotions, size: 16, color: AppTheme.textColor),
                const SizedBox(width: 8),
                const Text(
                  'You can do it',
                  style: TextStyle(fontSize: 14, color: AppTheme.textColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // User Level
            if (item['user_level'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: AppTheme.textColor),
                  const SizedBox(width: 8),
                  Text(
                    'User Level: ${item['user_level']}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
            
            // Start Workout Button
            Obx(() {
              final activeSchedule = _schedulesController.activeSchedule;
              if (activeSchedule == null) return const SizedBox.shrink();
              
              final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
              final currentDay = _schedulesController.getCurrentDay(planId);
              final workoutKey = '${planId}_${currentDay}_${item['name']}';
              
              final isStarted = _schedulesController.isWorkoutStarted(workoutKey);
              final isCompleted = _schedulesController.isWorkoutCompleted(workoutKey);
              final remainingMinutes = _schedulesController.getWorkoutRemainingMinutes(workoutKey);
              
              String buttonText;
              Color buttonColor;
              VoidCallback? onPressed;
              
              if (isCompleted) {
                buttonText = 'Completed';
                buttonColor = AppTheme.cardBackgroundColor;
                onPressed = null;
              } else if (isStarted) {
                buttonText = 'Plan Started - $remainingMinutes minutes remaining';
                buttonColor = Colors.orange;
                onPressed = null;
                  } else {
                buttonText = 'Start Workout';
                buttonColor = AppTheme.primaryColor;
                onPressed = () {
                  final totalMinutes = int.tryParse(item['minutes']?.toString() ?? '0') ?? 0;
                  _schedulesController.startWorkout(workoutKey, totalMinutes);
                };
              }
              
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: AppTheme.textColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatWeightDisplay(Map<String, dynamic> item) {
    // Safely convert to double, handling both string and numeric inputs
    final weightMin = _safeParseDouble(item['weight_min_kg']);
    final weightMax = _safeParseDouble(item['weight_max_kg']);
    final weight = _safeParseDouble(item['weight_kg']);
    
    // If we have min and max, show range
    if (weightMin != null && weightMax != null) {
      return '${weightMin.toStringAsFixed(0)}-${weightMax.toStringAsFixed(0)} kg';
    }
    // If we only have min or max, show that with a dash
    else if (weightMin != null) {
      return '${weightMin.toStringAsFixed(0)}+ kg';
    }
    else if (weightMax != null) {
      return 'up to ${weightMax.toStringAsFixed(0)} kg';
    }
    // Fallback to single weight value
    else if (weight != null) {
      return '${weight.toStringAsFixed(0)} kg';
    }
    
    return 'N/A';
  }


  void _showDeleteConfirmation(Map<String, dynamic> plan, bool isAi) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final planName = plan['name']?.toString() ?? (isAi ? 'AI Generated Plan' : 'Manual Plan');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Plan'),
          content: Text('Are you sure you want to delete "$planName"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  if (isAi) {
                    await _plansController.deleteAiGeneratedPlan(planId);
                  } else {
                    await _plansController.deleteManualPlan(planId);
                  }
                  
                  // Show success message
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('${isAi ? 'AI Generated' : 'Manual'} plan deleted successfully'),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                    );
                  }
                } catch (e) {
                  // Show error message
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete plan: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.textColor),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
