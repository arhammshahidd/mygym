import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/stats_controller.dart';
import '../../../trainings/domain/models/daily_training_plan.dart';
import '../../../trainings/presentation/controllers/schedules_controller.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late StatsController _statsController;

  @override
  void initState() {
    super.initState();
    _statsController = Get.find<StatsController>();
    // Check for active plan and refresh stats when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always refresh stats when stats page is opened to ensure latest data
      _statsController.refreshStats(forceSync: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training Stats'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              // Retry failed API submissions
              try {
                final schedulesController = Get.find<SchedulesController>();
                await schedulesController.retryFailedSubmissions();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Retrying failed submissions...')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error retrying submissions: $e')),
                );
              }
            },
            tooltip: 'Retry Failed Submissions',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _statsController.refreshStats(forceSync: true);
            },
          ),
        ],
      ),
      body: Obx(() {
        // Watch userStats to trigger rebuild when it changes (including when set to null)
        // These are intentionally accessed to trigger reactivity in Obx
        _statsController.userStats.value;
        _statsController.trainingStats.value;
        _statsController.dailyPlansRaw.length;
        
        if (_statsController.isLoading.value && !_statsController.hasLoadedOnce.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () async {
            await _statsController.refreshStats(forceSync: true);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'Training Statistics',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Stats Cards
                _buildQuickStatsCards(),
                const SizedBox(height: 24),

                // Training Stats Overview
                if (_statsController.trainingStats.value != null)
                  _buildTrainingStatsOverview(),
                const SizedBox(height: 24),

                // Recent Workouts
                _buildRecentWorkoutsSection(),
                const SizedBox(height: 24),

                // Weekly Progress
                _buildWeeklyProgressSection(),
                const SizedBox(height: 24),

                // Monthly Progress
                _buildMonthlyProgressSection(),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildQuickStatsCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      // Reduce aspect ratio (width/height) to increase tile height and prevent overflow
      childAspectRatio: 1.0,
      children: [
        _buildStatCard(
          title: 'Today',
          value: '${_statsController.getTodaysCompletedWorkouts()}',
          subtitle: 'Workouts',
          icon: Icons.today,
          color: AppTheme.primaryColor,
        ),
        _buildStatCard(
          title: 'This Week',
          value: '${_statsController.getWeeklyCompletedWorkouts()}',
          subtitle: 'Workouts',
          icon: Icons.date_range,
          color: Colors.blue,
        ),
        _buildStatCard(
          title: 'This Month',
          value: '${_statsController.getMonthlyCompletedWorkouts()}',
          subtitle: 'Workouts',
          icon: Icons.calendar_month,
          color: Colors.green,
        ),
        _buildStatCard(
          title: 'Current Streak',
          value: '${_statsController.getCurrentStreak()}',
          subtitle: 'Days',
          icon: Icons.local_fire_department,
          color: Colors.orange,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingStatsOverview() {
    // Get overall progress data
    final totalWorkouts = _statsController.getTotalWorkouts();
    final totalMinutes = _statsController.getTotalMinutes();
    final longestStreak = _statsController.getLongestStreak();
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overall Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Workouts',
                    '$totalWorkouts',
                    Icons.fitness_center,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Total Minutes',
                    '$totalMinutes',
                    Icons.timer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Longest Streak',
                    '$longestStreak days',
                    Icons.local_fire_department,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentWorkoutsSection() {
    // Get recent workouts (last 6 days) - returns List<Map<String, dynamic>> with workout names
    final recentWorkouts = _statsController.getRecentWorkouts(days: 6);
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Workouts (Last 6 Days)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            if (recentWorkouts.isEmpty)
              const Center(
                child: Text(
                  'No recent workouts',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...recentWorkouts.map((workout) => _buildWorkoutItemFromMap(workout)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutItemFromMap(Map<String, dynamic> workout) {
    // Support both new format (grouped by day) and old format (individual workouts)
    final dayLabel = workout['day_label'] as String?; // "Day 1", "Day 2", etc.
    final workoutNamesStr = workout['workout_names_str'] as String?; // "Chest, Back"
    final workoutName = workout['workout_name'] ?? workout['name'] ?? 'Unknown Workout';
    final date = workout['date'] ?? '';
    
    // If we have day_label and workout_names_str, use new format
    if (dayLabel != null && workoutNamesStr != null) {
      // Get count from workout map, or calculate from workout_names list
      final workoutNamesList = workout['workout_names'] as List<String>?;
      final workoutCount = workout['workout_count'] as int? ?? workoutNamesList?.length ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dayLabel: $workoutNamesStr ($workoutCount)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppTheme.textColor,
                    ),
                  ),
                  if (date.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
          ],
        ),
      );
    }
    
    // Fallback to old format (individual workouts)
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                  ),
                ),
                if (date.isNotEmpty)
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 20,
          ),
        ],
      ),
    );
  }
  
  Widget _buildWorkoutItem(DailyTrainingPlan workout) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.workoutName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                  ),
                ),
                Text(
                  '${workout.planCategory} • ${workout.planDate}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutsByCategorySection() {
    final categoryStats = _statsController.getWorkoutsByCategory();
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Workouts by Category',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            if (categoryStats.isEmpty)
              const Center(
                child: Text(
                  'No category data available',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...categoryStats.entries.map((entry) => _buildCategoryItem(entry.key, entry.value)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String category, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            category,
            style: const TextStyle(
              color: AppTheme.textColor,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyProgressSection() {
    final weeklyProgress = _statsController.getWeeklyProgress();
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            
            // Progress overview
            Row(
              children: [
                Expanded(
                  child: _buildProgressItem(
                    'Completed',
                    weeklyProgress['completed_workouts'] as int,
                    weeklyProgress['total_planned_workouts'] as int,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildProgressItem(
                    'Remaining',
                    weeklyProgress['incomplete_workouts'] as int,
                    weeklyProgress['total_planned_workouts'] as int,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Completion rate
            _buildCompletionRateIndicator(
              'Weekly Completion Rate',
              weeklyProgress['completion_rate'] as double,
            ),
            const SizedBox(height: 12),
            
            // Additional stats
            Row(
              children: [
                Expanded(
                  child: _buildStatDetail(
                    'Total Minutes',
                    '${weeklyProgress['total_minutes']}',
                    Icons.timer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressItem(String label, int current, int target, Color color) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        const SizedBox(height: 4),
        Text(
          '$current / $target',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyProgressSection() {
    final monthlyProgress = _statsController.getMonthlyProgress();
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            
            // Progress overview
            Row(
              children: [
                Expanded(
                  child: _buildProgressItem(
                    'Completed',
                    monthlyProgress['completed_workouts'] as int,
                    monthlyProgress['total_planned_workouts'] as int,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildProgressItem(
                    'Remaining',
                    monthlyProgress['incomplete_workouts'] as int,
                    monthlyProgress['total_planned_workouts'] as int,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Completion rate
            _buildCompletionRateIndicator(
              'Monthly Completion Rate',
              monthlyProgress['completion_rate'] as double,
            ),
            const SizedBox(height: 12),
            
            // Additional stats - Grid layout for Days Passed and Total Minutes
            Row(
              children: [
                Expanded(
                  child: _buildStatDetail(
                    'Days Passed',
                    '${monthlyProgress['days_passed']}/${monthlyProgress['days_in_month']}',
                    Icons.calendar_today,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatDetail(
                    'Total Minutes',
                    '${monthlyProgress['total_minutes']}',
                    Icons.timer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalProgressSection() {
    final goalProgress = _statsController.getGoalProgress();
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Goal Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 16),
            
            // Weekly Goal
            _buildGoalItem(
              'Weekly Goal',
              goalProgress['weekly']['completed'] as int,
              goalProgress['weekly']['goal'] as int,
              goalProgress['weekly']['progress'] as double,
              goalProgress['weekly']['achieved'] as bool,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            
            // Monthly Goal
            _buildGoalItem(
              'Monthly Goal',
              goalProgress['monthly']['completed'] as int,
              goalProgress['monthly']['goal'] as int,
              goalProgress['monthly']['progress'] as double,
              goalProgress['monthly']['achieved'] as bool,
              Colors.green,
            ),
            const SizedBox(height: 12),
            
            // Streak Goal
            _buildGoalItem(
              'Streak Goal',
              goalProgress['streak']['current'] as int,
              goalProgress['streak']['goal'] as int,
              goalProgress['streak']['progress'] as double,
              goalProgress['streak']['achieved'] as bool,
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCompletionRateIndicator(String label, double rate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${rate.toStringAsFixed(1)}%',
              style: TextStyle(
                color: rate >= 80 ? Colors.green : rate >= 60 ? Colors.orange : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: rate / 100,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            rate >= 80 ? Colors.green : rate >= 60 ? Colors.orange : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDetail(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildGoalItem(String label, int current, int goal, double progress, bool achieved, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                if (achieved)
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                Text(
                  '$current / $goal',
                  style: TextStyle(
                    color: achieved ? Colors.green : AppTheme.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress / 100,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }
}