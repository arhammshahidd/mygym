import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  Future<void> _loadInitialData() async {
    // Load schedules data
    await _schedulesController.loadSchedulesData();
    
    // Load plans data
    await _plansController.loadPlansData();
    
    // Refresh data to ensure we have the latest information
    await _schedulesController.refreshSchedules();
    await _plansController.refreshPlans();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
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
          child: Text('No scheduled workouts yet'),
        );
      }
      
      return RefreshIndicator(
        onRefresh: () async {
          await _schedulesController.refreshSchedules();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
          children: [
            // Header
            const Text(
              'Scheduled Workouts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
        await _plansController.refreshPlans();
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
            _buildAiGeneratorCard(),
            const SizedBox(height: 16),

          // Manual Plans Section
            Obx(() {
              final manualPlans = _plansController.manualPlans;
              if (manualPlans.isNotEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manual Plans',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                    ...manualPlans.map((plan) => _buildManualPlanCard(plan)).toList(),
                    const SizedBox(height: 16),
                  ],
                );
              }
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _plansController.clearAiGeneratedPlans();
                            _plansController.refreshAiGeneratedPlans();
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Clear Cache'),
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

  Widget _buildScheduleCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    
    // Debug: Print all available fields in the plan
    print('🔍 Schedule Card - Plan data: $plan');
    print('🔍 Schedule Card - Available fields: ${plan.keys.toList()}');
    
    return Obx(() {
      final isStarted = _schedulesController.isScheduleStarted(planId);
      
      return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    backgroundColor: isStarted ? Colors.red : const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isStarted ? 'Stop Plan' : 'Start Plan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
            // Plan Category Name - try multiple field names
            if (plan['exercise_plan_category'] != null)
              Text('Plan Category: ${plan['exercise_plan_category']}')
            else if (plan['category'] != null)
              Text('Plan Category: ${plan['category']}')
            else if (plan['plan_category'] != null)
              Text('Plan Category: ${plan['plan_category']}')
            else if (plan['workout_name'] != null)
              Text('Plan Category: ${plan['workout_name']}'),
            // Total Days - try multiple field names
            if (plan['total_days'] != null)
              Text('Total Days: ${plan['total_days']}')
            else if (plan['days'] != null)
              Text('Total Days: ${plan['days']}')
            else if (plan['duration'] != null)
              Text('Total Days: ${plan['duration']}'),
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
    });
  }

  Widget _buildManualPlanCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final isStarted = _plansController.isPlanStarted(planId);
    final approvalStatus = _plansController.getPlanApprovalStatus(planId);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    plan['name']?.toString() ?? 'Manual Plan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 8),
            // Plan Category Name
            if (plan['exercise_plan_category'] != null)
              Text('Plan Category: ${plan['exercise_plan_category']}'),
            // Total Days
            if (plan['total_days'] != null)
              Text('Total Days: ${plan['total_days']}'),
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
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    plan['name']?.toString() ?? 'AI Generated Plan',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 8),
            // Plan Category Name
            if (plan['exercise_plan_category'] != null)
              Text('Plan Category: ${plan['exercise_plan_category']}'),
            // Total Days
            if (plan['total_days'] != null)
              Text('Total Days: ${plan['total_days']}'),
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
                          builder: (context) => PlanDetailPage(plan: plan, isAi: true),
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

  Widget _buildApprovalButton(Map<String, dynamic> plan, String approvalStatus) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    
    switch (approvalStatus) {
      case 'pending':
        return ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[400],
            foregroundColor: Colors.white,
          ),
          child: const Text('Pending'),
        );
      case 'approved':
        return ElevatedButton(
          onPressed: () {
            _plansController.startPlan(plan);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
          ),
          child: const Text('Start Plan'),
        );
      default:
        return ElevatedButton(
                  onPressed: () async {
            // Send plan for approval
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Plan sent for approval'),
                backgroundColor: Color(0xFF2E7D32),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
          ),
          child: const Text('Send Plan'),
        );
    }
  }

  Widget _buildAiGeneratorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            const Text(
              'AI Plan Generator',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get a personalized workout plan based on your goals, experience, and available time.',
              style: TextStyle(color: Colors.grey),
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
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _schedulesController.stopSchedule(activeSchedule);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
            Text('Plan: ${activeSchedule['exercise_plan_category'] ?? 'Workout Plan'}'),
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
                  return const Text('No workouts for this day');
                }
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Workouts (${dayItems.length} exercises)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            return _applyWorkoutDistributionLogic(workouts.cast<Map<String, dynamic>>());
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
        return _applyWorkoutDistributionLogic(workouts);
      }
      
      // If no data found, return empty list
      print('🔍 No workout data found');
      return [];
                  } catch (e) {
      print('Error getting day items: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _applyWorkoutDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    print('🔍 DISTRIBUTION LOGIC - Input workouts: ${workouts.length}');
    for (int i = 0; i < workouts.length; i++) {
      final workout = workouts[i];
      print('🔍 Workout $i: ${workout['name']} - ${workout['minutes']} minutes');
    }
    
    // Calculate total minutes for all workouts
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0;
      totalMinutes += minutes;
      print('🔍 Adding ${workout['name']}: $minutes minutes (total: $totalMinutes)');
    }
    
    print('🔍 FINAL Total workout minutes: $totalMinutes');
    print('🔍 FINAL Number of workouts: ${workouts.length}');
    
    // FORCE TEST: Always apply filtering if we have more than 2 workouts
    if (workouts.length > 2) {
      print('🔍 🚨 FORCE TEST: More than 2 workouts detected, applying filtering regardless of minutes');
      final filteredWorkouts = workouts.take(2).toList();
      print('🔍 🚨 FORCE FILTERED: Showing ${filteredWorkouts.length} workouts: ${filteredWorkouts.map((w) => w['name']).toList()}');
      return filteredWorkouts;
    }
    
    // Apply distribution logic
    if (totalMinutes > 80 && workouts.length > 2) {
      // If total minutes > 80 and we have more than 2 workouts, show only 2 workouts
      print('🔍 ✅ APPLYING LOGIC: Total minutes ($totalMinutes) > 80, showing only 2 workouts');
      final filteredWorkouts = workouts.take(2).toList();
      print('🔍 ✅ FILTERED: Showing ${filteredWorkouts.length} workouts: ${filteredWorkouts.map((w) => w['name']).toList()}');
      return filteredWorkouts;
    } else {
      // If total minutes <= 80 or we have 2 or fewer workouts, show all workouts
      print('🔍 ✅ APPLYING LOGIC: Total minutes ($totalMinutes) <= 80 or <= 2 workouts, showing all ${workouts.length} workouts');
      return workouts;
    }
  }


  Widget _buildWorkoutItem(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFE8F5E8), // Light green background
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2E7D32), width: 2),
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
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  if (item['exercise_types'] != null)
                    Text(
                      '${item['exercise_types']} Exercises',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E7D32),
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
                color: Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(height: 12),
            
            // Sets & Reps
            if (item['sets'] != null || item['reps'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.fitness_center, size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text(
                    '${item['sets'] ?? 'N/A'} sets x ${item['reps'] ?? 'N/A'} reps',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
                ),
            ],
          ),
              const SizedBox(height: 8),
            ],
            
            // Weight
            if (item['weight_kg'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.sports_gymnastics, size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text(
                    '${item['weight_kg']} kg',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
          ),
        ],
      ),
              const SizedBox(height: 8),
            ],
            
            // Duration
            if (item['minutes'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text(
                    '${item['minutes']} minutes',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            
            // Motivational text
            Row(
              children: [
                const Icon(Icons.emoji_emotions, size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                const Text(
                  'You can do it',
                  style: TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // User Level
            if (item['user_level'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text(
                    'User Level: ${item['user_level']}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
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
                buttonColor = Colors.grey;
                onPressed = null;
              } else if (isStarted) {
                buttonText = 'Plan Started - $remainingMinutes minutes remaining';
                buttonColor = Colors.orange;
                onPressed = null;
                  } else {
                buttonText = 'Start Workout';
                buttonColor = const Color(0xFF2E7D32);
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
                    foregroundColor: Colors.white,
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${isAi ? 'AI Generated' : 'Manual'} plan deleted successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  // Show error message
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete plan: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
