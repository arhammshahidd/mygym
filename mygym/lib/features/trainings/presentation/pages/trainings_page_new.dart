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

class _TrainingsPageState extends State<TrainingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final SchedulesController _schedulesController =
      Get.find<SchedulesController>();
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

    // Load initial data for both tabs
    _schedulesController.loadSchedulesData();
    _plansController.loadPlansData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
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
        children: [_buildSchedulesTab(), _buildPlansTab()],
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
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No scheduled workouts yet'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _schedulesController.loadSchedulesData();
                },
                child: const Text('Refresh Data'),
              ),
            ],
          ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scheduled Workouts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: () {
                    _schedulesController.loadSchedulesData();
                  },
                  child: const Text('Refresh'),
                ),
              ],
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
                    const Text(
                      'Manual Plans',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...manualPlans
                        .map((plan) => _buildManualPlanCard(plan))
                        .toList(),
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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

  Widget _buildScheduleCard(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
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
                        'Workout Plan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                    backgroundColor: isStarted
                        ? Colors.red
                        : AppTheme.primaryColor,
                    foregroundColor: AppTheme.textColor,
                  ),
                  child: Text(isStarted ? 'Stop Plan' : 'Start Plan'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Plan ID: ${plan['id']}'),
            if (plan['web_plan_id'] != null)
              Text('Web Plan ID: ${plan['web_plan_id']}'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PlanDetailPage(plan: plan, isAi: false),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildApprovalButton(plan, approvalStatus),
              ],
            ),
            const SizedBox(height: 8),
            Text('Plan ID: ${plan['id']}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PlanDetailPage(plan: plan, isAi: false),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
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
                          builder: (context) =>
                              PlanDetailPage(plan: plan, isAi: true),
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
                          builder: (context) => EditPlanPage(plan: plan, isAi: true),
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

  Widget _buildApprovalButton(
    Map<String, dynamic> plan,
    String approvalStatus,
  ) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;

    switch (approvalStatus) {
      case 'pending':
        return ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.textColor,
            foregroundColor: AppTheme.textColor,
          ),
          child: const Text('Pending'),
        );
      case 'approved':
        return ElevatedButton(
          onPressed: () {
            _plansController.startPlan(plan);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.textColor,
          ),
          child: const Text('Start Plan'),
        );
      default:
        return ElevatedButton(
          onPressed: () async {
            // Send plan for approval
            if (_scaffoldMessenger != null) {
              _scaffoldMessenger!.showSnackBar(
                const SnackBar(
                  content: Text('Plan sent for approval'),
                  backgroundColor: Color(0xFF2E7D32),
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: AppTheme.textColor,
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

  void _showDeleteConfirmation(Map<String, dynamic> plan, bool isAi) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final planName = plan['exercise_plan_category']?.toString() ?? (isAi ? 'AI Generated Plan' : 'Manual Plan');
    
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
                        backgroundColor: AppTheme.primaryColor,
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
              style: TextButton.styleFrom(foregroundColor: AppTheme.textColor),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveScheduleDisplay() {
    final activeSchedule = _schedulesController.activeSchedule!;
    final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
    final currentDay = _schedulesController.getCurrentDay(planId);

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Schedule - Day ${currentDay + 1}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Plan: ${activeSchedule['exercise_plan_category'] ?? 'Workout Plan'}',
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                _schedulesController.stopSchedule(activeSchedule);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: AppTheme.textColor,
              ),
              child: const Text('Stop Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
