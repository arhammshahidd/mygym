import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../trainings/presentation/controllers/schedules_controller.dart';
import '../../../trainings/presentation/controllers/plans_controller.dart';
import '../../../food/presentation/controllers/nutrition_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final ProfileController _profileController;
  late final SchedulesController _schedulesController;
  late final PlansController _plansController;
  late final NutritionController _nutritionController;

  // Daily counters (reset at midnight)
  int _caloriesTargetPerDay = 900; // placeholder until tied to profile/goals
  int _workoutsCompletedToday = 0;
  int _mealsLoggedToday = 0;
  DateTime _lastResetDate = DateTime.now();

  // Training state pulled from persisted storage created by Trainings UI
  int? _activeTrainingPlanId;
  int _activeTrainingDayIndex = 0; // 0-based

  @override
  void initState() {
    super.initState();
    _profileController = Get.find<ProfileController>();
    _schedulesController = Get.find<SchedulesController>();
    _plansController = Get.find<PlansController>();
    _nutritionController = Get.find<NutritionController>();
    _profileController.loadUserProfileIfNeeded();
    // Ensure training data is loaded so active plan can be resolved
    _schedulesController.loadSchedulesData();
    _plansController.loadPlansData();
    _loadDashboardState();
  }

  String _greeting() {
    final hour = DateTime.now().toLocal().hour;
    if (hour >= 5 && hour < 12) return 'Good morning,';
    if (hour >= 12 && hour < 17) return 'Good afternoon,';
    if (hour >= 17 && hour < 21) return 'Good evening,';
    return 'Good evening,';
  }

  Future<void> _loadDashboardState() async {
    final prefs = await SharedPreferences.getInstance();

    // Reset daily counters at midnight
    final last = prefs.getString('dashboard_last_reset');
    final nowDateStr = DateTime.now().toIso8601String().substring(0, 10);
    if (last == null || last != nowDateStr) {
      await prefs.setString('dashboard_last_reset', nowDateStr);
      await prefs.setInt('dashboard_workouts_completed', 0);
      await prefs.setInt('dashboard_meals_logged', 0);
    }

    _workoutsCompletedToday = prefs.getInt('dashboard_workouts_completed') ?? 0;
    _mealsLoggedToday = prefs.getInt('dashboard_meals_logged') ?? 0;
    _lastResetDate = DateTime.tryParse(prefs.getString('dashboard_last_reset') ?? nowDateStr) ?? DateTime.now();

    // Read started training plan mapping from both Plans and Schedules
    final userId = Get.find<ProfileController>().user?.id ?? 0;
    
    // First check Plans tab
    final rawStartedPlans = prefs.getString('startedPlans_user_$userId');
    if (rawStartedPlans != null && rawStartedPlans.isNotEmpty) {
      try {
        final Map<String, dynamic> map = jsonDecode(rawStartedPlans);
        final entry = map.entries.cast<MapEntry<String, dynamic>>()
            .firstWhere((e) => e.value == true, orElse: () => const MapEntry<String, dynamic>('-1', false));
        final id = int.tryParse(entry.key);
        if (id != null && id > 0) _activeTrainingPlanId = id;
      } catch (_) {}
    }
    
    // Then check Schedules tab
    if (_activeTrainingPlanId == null) {
      final rawStartedSchedules = prefs.getString('startedSchedules_user_$userId');
      if (rawStartedSchedules != null && rawStartedSchedules.isNotEmpty) {
        try {
          final Map<String, dynamic> map = jsonDecode(rawStartedSchedules);
          final entry = map.entries.cast<MapEntry<String, dynamic>>()
              .firstWhere((e) => e.value == true, orElse: () => const MapEntry<String, dynamic>('-1', false));
          final id = int.tryParse(entry.key);
          if (id != null && id > 0) _activeTrainingPlanId = id;
        } catch (_) {}
      }
    }

    // Track current day index per plan
    if (_activeTrainingPlanId != null) {
      _activeTrainingDayIndex = prefs.getInt('training_day_index_${_activeTrainingPlanId}') ?? 0;
    }

    if (mounted) setState(() {});
  }

  Future<void> _incrementWorkoutCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    _workoutsCompletedToday += 1;
    await prefs.setInt('dashboard_workouts_completed', _workoutsCompletedToday);

    // Advance training day index for active plan
    if (_activeTrainingPlanId != null) {
      _activeTrainingDayIndex += 1;
      await prefs.setInt('training_day_index_${_activeTrainingPlanId}', _activeTrainingDayIndex);
    }
    if (mounted) setState(() {});
  }

  Future<void> _incrementMealsLogged() async {
    final prefs = await SharedPreferences.getInstance();
    _mealsLoggedToday += 1;
    await prefs.setInt('dashboard_meals_logged', _mealsLoggedToday);
    if (mounted) setState(() {});
  }

  // Helpers to extract today's workouts summary from a plan map
  List<Map<String, dynamic>> _extractTodayWorkouts(Map<String, dynamic>? plan) {
    if (plan == null) return const [];
    try {
      final List<dynamic>? daily = _normalizeDailyPlans(plan['daily_plans']);
      if (daily != null && daily.isNotEmpty) {
        final int dayIdx = _activeTrainingDayIndex.clamp(0, daily.length - 1);
        final Map<String, dynamic> day = Map<String, dynamic>.from(daily[dayIdx]);
        final List items = (day['workouts'] ?? day['items'] ?? const []) as List;
        return List<Map<String, dynamic>>.from(items.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      // Fallback - use SchedulesController's distribution logic
      List<Map<String, dynamic>> workouts = [];
      if (plan['exercises_details'] is List) {
        workouts = List<Map<String, dynamic>>.from((plan['exercises_details'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (plan['exercises_details'] is String) {
        try {
          final List<dynamic> parsed = jsonDecode(plan['exercises_details'] as String) as List<dynamic>;
          workouts = List<Map<String, dynamic>>.from(parsed.map((e) => Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
      
      // Apply the same distribution logic as SchedulesController
      return _applyWorkoutDistributionLogic(workouts);
    } catch (_) {}
    return const [];
  }

  // Apply workout distribution logic (same as SchedulesController)
  List<Map<String, dynamic>> _applyWorkoutDistributionLogic(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) return workouts;
    
    // FORCE TEST: Always apply filtering if we have more than 2 workouts
    if (workouts.length > 2) {
      return workouts.take(2).toList();
    }
    
    // Apply distribution logic
    int totalMinutes = 0;
    for (var workout in workouts) {
      final minutes = int.tryParse(workout['minutes']?.toString() ?? workout['training_minutes']?.toString() ?? '0') ?? 0;
      totalMinutes += minutes;
    }
    
    if (totalMinutes > 80 && workouts.length > 2) {
      return workouts.take(2).toList();
    } else {
      return workouts;
    }
  }

  List<dynamic>? _normalizeDailyPlans(dynamic source) {
    if (source == null) return null;
    if (source is String && source.trim().isNotEmpty) {
      try {
        return jsonDecode(source) as List<dynamic>;
      } catch (_) {
        return null;
      }
    }
    if (source is List) return source;
    return null;
  }

  Widget _statTile({required IconData icon, required String label, required String value, required double width}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: const Color(0xFF2E7D32)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.today, size: 18, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _workoutCard() {
    Map<String, dynamic>? activePlan;
    
    // First check if there's an active schedule from SchedulesController
    final activeSchedule = _schedulesController.activeSchedule;
    if (activeSchedule != null) {
      activePlan = activeSchedule;
      _activeTrainingPlanId = int.tryParse(activeSchedule['id']?.toString() ?? '');
    }
    
    // If no active schedule, check Plans tab data
    if (activePlan == null && _activeTrainingPlanId != null) {
      activePlan = _plansController.manualPlans.firstWhereOrNull((p) => int.tryParse(p['id']?.toString() ?? '') == _activeTrainingPlanId);
      activePlan ??= _plansController.aiGeneratedPlans.firstWhereOrNull((p) => int.tryParse(p['id']?.toString() ?? '') == _activeTrainingPlanId);
      
      // If not found in Plans, check in Schedules tab data
      activePlan ??= _schedulesController.assignments.firstWhereOrNull((p) => int.tryParse(p['id']?.toString() ?? '') == _activeTrainingPlanId);
      
      // If still not found, try to load from persisted snapshot
      if (activePlan == null) {
        SharedPreferences.getInstance().then((prefs) {
          final userId = Get.find<ProfileController>().user?.id ?? 0;
          // Check for active training plan snapshot
          final raw = prefs.getString('activeTrainingPlan_user_$userId');
          if (raw != null && raw.isNotEmpty) {
            try {
              final Map<String, dynamic> snap = jsonDecode(raw) as Map<String, dynamic>;
              if ((snap['id']?.toString() ?? '') == _activeTrainingPlanId.toString()) {
                setState(() {
                  activePlan = snap;
                });
              }
            } catch (_) {}
          }
          // Also check for active schedule snapshot
          final scheduleRaw = prefs.getString('activeSchedule_user_$userId');
          if (scheduleRaw != null && scheduleRaw.isNotEmpty) {
            try {
              final Map<String, dynamic> scheduleSnap = jsonDecode(scheduleRaw) as Map<String, dynamic>;
              if ((scheduleSnap['id']?.toString() ?? '') == _activeTrainingPlanId.toString()) {
                setState(() {
                  activePlan = scheduleSnap;
                });
              }
            } catch (_) {}
          }
        });
      }
    }

    final workouts = activePlan != null ? _extractTodayWorkouts(activePlan) : const <Map<String, dynamic>>[];
    final hasActive = activePlan != null && workouts.isNotEmpty;
    
    // Get current day from SchedulesController if it's an active schedule
    int currentDay = _activeTrainingDayIndex;
    if (activeSchedule != null && _activeTrainingPlanId != null) {
      currentDay = _schedulesController.getCurrentDay(_activeTrainingPlanId!);
    }

    return _sectionCard(
      title: hasActive ? (activePlan!['exercise_plan_category']?.toString() ?? 'Muscle Building') : 'No Active Training Plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Day ${currentDay + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          if (hasActive)
            Column(
              children: [
                // Grid layout for workout cards
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: workouts.length,
                  itemBuilder: (context, index) {
                    final w = workouts[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E7D32), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (w['name'] ?? 'Workout').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildWorkoutDetail('Sets', w['sets']?.toString() ?? '-'),
                                _buildWorkoutDetail('Reps', w['reps']?.toString() ?? '-'),
                                _buildWorkoutDetail('Weight', '${w['weight_kg']?.toString() ?? w['weight']?.toString() ?? '-'} kg'),
                                _buildWorkoutDetail('Minutes', '${w['training_minutes'] ?? w['minutes'] ?? '-'}'),
                                if (w['exercise_types'] != null)
                                  _buildWorkoutDetail('Exercise Types', w['exercise_types']?.toString() ?? '-'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            )
          else
            const Text('Start a plan from Schedules or Plans to see today\'s workout', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _mealCard() {
    // Choose started/active meal plan (Schedules assigned or AI started)
    final bool mealActive = _nutritionController.mealPlanActive.value;
    final plan = _nutritionController.assignedPlan.value;
    final snapshot = _nutritionController.todayMealsSnapshot;
    final hasMeals = mealActive && snapshot != null;
    final int dayIdx = (snapshot?['day'] ?? 1) - 1;

    return _sectionCard(
      title: hasMeals ? (snapshot!['title']?.toString() ?? 'Meal Plan') : 'No Active Meal Plan',
      child: hasMeals
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Day ${dayIdx + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                // Modern grid layout for meal cards
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    final entries = [
                      {'label': 'BREAKFAST', 'items': (snapshot?['breakfast'] as List? ?? const []), 'icon': Icons.wb_sunny, 'color': const Color(0xFFFF9800)},
                      {'label': 'LUNCH', 'items': (snapshot?['lunch'] as List? ?? const []), 'icon': Icons.wb_sunny_outlined, 'color': const Color(0xFF4CAF50)},
                      {'label': 'DINNER', 'items': (snapshot?['dinner'] as List? ?? const []), 'icon': Icons.nights_stay, 'color': const Color(0xFF2196F3)},
                    ];
                    final entry = entries[index];
                    
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: entry['color'] as Color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: (entry['color'] as Color).withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (entry['color'] as Color).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  entry['icon'] as IconData,
                                  color: entry['color'] as Color,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry['label']!.toString(), 
                                  style: TextStyle(
                                    fontSize: 14, 
                                    fontWeight: FontWeight.bold, 
                                    color: entry['color'] as Color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final m in (entry['items'] as List))
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (entry['color'] as Color).withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m['name']?.toString() ?? 'Food Item',
                                          maxLines: 1, 
                                          overflow: TextOverflow.ellipsis, 
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 2,
                                          children: [
                                            _buildNutritionBadge('${m['cal'] ?? m['calories'] ?? 0}', 'cal', Colors.orange),
                                            _buildNutritionBadge('${m['protein'] ?? m['proteinGrams'] ?? m['proteins'] ?? 0}', 'g', Colors.blue),
                                            _buildNutritionBadge('${m['carbs'] ?? m['carbsGrams'] ?? m['carbohydrates'] ?? 0}', 'g', Colors.green),
                                            _buildNutritionBadge('${m['fats'] ?? m['fatGrams'] ?? m['fat'] ?? 0}', 'g', Colors.red),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _incrementMealsLogged,
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2E7D32), side: const BorderSide(color: Color(0xFF2E7D32)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Log Meals'),
                  ),
                ),
              ],
            )
          : const Text('Start a meal plan from Schedules or AI Suggestions to see today\'s meals', style: TextStyle(color: Colors.black54)),
    );
  }

  String _firstLetter(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    return trimmed[0].toUpperCase();
  }

  Widget _buildWorkoutDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2E7D32),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWorkoutDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2E7D32),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionBadge(String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        '$value$unit',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildModernStatTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF2E7D32),
      ),
      body: Obx(() {
        final user = _profileController.user;
        final fullName = user?.name.isNotEmpty == true ? user!.name : 'User';
        final initial = _firstLetter(fullName);

        // Touch reactive training/nutrition observables so Dashboard rebuilds when they change
        // ignore: unused_local_variable
        final int _reactiveTick = _plansController.manualPlans.length + _plansController.aiGeneratedPlans.length + _schedulesController.assignments.length + (_nutritionController.mealPlanActive.value ? 1 : 0);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF2E7D32),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Modern grid layout for stats
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8,
                children: [
                  _buildModernStatTile(
                    icon: Icons.local_fire_department,
                    label: 'Calories',
                    value: '${_caloriesTargetPerDay}/day',
                    color: const Color(0xFFFF6B35),
                  ),
                  _buildModernStatTile(
                    icon: Icons.fitness_center,
                    label: 'Workouts',
                    value: '$_workoutsCompletedToday',
                    color: const Color(0xFF2E7D32),
                  ),
                  _buildModernStatTile(
                    icon: Icons.restaurant,
                    label: 'Meals',
                    value: '$_mealsLoggedToday',
                    color: const Color(0xFF1976D2),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Training block
              _workoutCard(),
              const SizedBox(height: 6),

              // Meal block
              _mealCard(),
            ],
          ),
        );
      }),
    );
  }
}
