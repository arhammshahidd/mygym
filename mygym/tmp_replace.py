from pathlib import Path
p = Path('lib/features/trainings/presentation/controllers/schedules_controller.dart')
t = p.read_text(encoding='utf-8')
start = t.find('  // Get the last completed day from database by checking completed daily plans')
end = t.find('  // Submit daily training completion to API')
if start == -1 or end == -1 or end <= start:
    raise SystemExit('markers not found')
nb = '''  // Get the last completed day from database by checking completed daily plans (day_number-only)
  Future<int?> _getLastCompletedDayFromDatabase(int scheduleId) async {
    try {
      print('🔍 SchedulesController - Checking database for completed days (day_number) for schedule ');

      int? _dayNum(Map p) => int.tryParse(
          p['day_number']?.toString() ?? p['day']?.toString() ?? p['dayNumber']?.toString() ?? '');

      final allPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: 'web_assigned');
      final assignmentPlans = allPlans.where((plan) {
        final sourceAssignmentId = plan['source_assignment_id'] as int?;
        final sourcePlanId = plan['source_plan_id'] as int?;
        final planType = plan['plan_type'] as String?;
        final isStatsRecord = plan['is_stats_record'] as bool? ?? false;

        if (isStatsRecord) return false;
        final normalizedType = planType?.toLowerCase();
        if (normalizedType == 'manual' || normalizedType == 'ai_generated') return false;

        return sourceAssignmentId == scheduleId || sourcePlanId == scheduleId;
      }).toList();

      print('📅 SchedulesController - Found  plans for assignment ');

      final completedDayNumbers = <int>[];
      for (final plan in assignmentPlans) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        if (!isCompleted || completedAt == null || completedAt.isEmpty) continue;

        final dn = _dayNum(plan);
        if (dn != null && dn > 0) {
          completedDayNumbers.add(dn);
          print('📅 SchedulesController - Completed plan: id=, day_number=');
        }
      }

      if (completedDayNumbers.isEmpty) {
        print('📅 SchedulesController - No completed plans found for schedule ');
        return null;
      }

      completedDayNumbers.sort();
      int highestSequential = 0;
      for (final dn in completedDayNumbers.toSet().toList()..sort()) {
        if (dn == highestSequential + 1) {
          highestSequential = dn;
        } else if (dn > highestSequential + 1) {
          break;
        }
      }

      final result = highestSequential > 0 ? highestSequential : null;
      print('📅 SchedulesController - Last sequentially completed day: ');
      return result;
    } catch (e) {
      print('❌ SchedulesController - Error getting last completed day from database: ');
      print('❌ SchedulesController - Stack trace: ');
      return null;
    }
  }

'''
p.write_text(t[:start] + nb + t[end:], encoding='utf-8')
