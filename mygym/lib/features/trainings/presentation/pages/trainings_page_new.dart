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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Manual Plans',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await _plansController.manualRefreshApprovalStatus();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Status refreshed')),
                            );
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh Status'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await _plansController.debugCheckPlanStatus(34);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Debug check completed - see console')),
                            );
                          },
                          icon: const Icon(Icons.bug_report, size: 16),
                          label: const Text('Debug Plan 34'),
                        ),
                      ],
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

          // Active Plan Daily Workouts Section
          Obx(() {
            final activePlan = _plansController.activePlan;
            if (activePlan != null) {
              return _buildActivePlanDailyView(activePlan);
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
                    // Use plan category as title instead of generic name
                    plan['exercise_plan_category']?.toString() ?? 'Manual Plan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                ),
                _buildApprovalButton(plan, approvalStatus),
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

    // Prefer daily_plans from plan if present to match portal distribution
    final List<dynamic>? dailyPlans = plan['daily_plans'] as List<dynamic>?;
    // If daily_plans exists, override totalDays for card badge
    if (dailyPlans != null && dailyPlans.isNotEmpty) {
      totalDays = dailyPlans.length;
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
        // Check if plan has been modified since approval
        final hasBeenModified = _plansController.hasPlanBeenModifiedSinceApproval(planId);
        
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
            // Show only Start Plan button if AI plan hasn't been modified
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
                setState(() {}); // reflect started state immediately
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
                setState(() {}); // reflect started state immediately
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
        // If plan was edited after rejection, allow resending
        final hasBeenModified = _plansController.hasPlanBeenModifiedSinceApproval(planId);
        if (hasBeenModified) {
          return ElevatedButton(
            onPressed: () async {
              try {
                // Determine if this is an AI or manual plan
                final planType = plan['plan_type']?.toString().toLowerCase();
                bool isAiPlan = planType == 'ai_generated';
                if (planType != 'ai_generated' && planType != 'manual') {
                  // Check for explicit AI plan indicators
                  final hasExplicitAiIndicators = plan.containsKey('ai_generated') || 
                                               plan.containsKey('gemini_generated') ||
                                               plan.containsKey('ai_plan_id') ||
                                               (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
                  
                  // Check for explicit manual plan indicators
                  final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                                   plan['assigned_by'] == null && 
                                                   plan['assignment_id'] == null && 
                                                   plan['web_plan_id'] == null;
                  
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
                if (_scaffoldMessenger != null) {
                  _scaffoldMessenger!.showSnackBar(
                    const SnackBar(content: Text('Plan resent for approval'), backgroundColor: Colors.green),
                  );
                }
                await _plansController.refreshPlans();
              } catch (e) {
                if (_scaffoldMessenger != null) {
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
        // Not modified yet: show rejected indicator
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
              print('🔍 Sending plan for approval: ${plan['id']}');
              
              // Determine if this is an AI or manual plan - use the same logic as PlansController
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
              print('🔍   - isAiPlan: $isAiPlan');
              print('🔍   - Full plan data: $plan');
              print('🔍   - Plan keys: ${plan.keys.toList()}');
              
              // Additional checks for manual plan indicators
              print('🔍 Manual plan indicators:');
              print('🔍   - created_by: ${plan['created_by']}');
              print('🔍   - assigned_by: ${plan['assigned_by']}');
              print('🔍   - assignment_id: ${plan['assignment_id']}');
              print('🔍   - web_plan_id: ${plan['web_plan_id']}');
              
              Map<String, dynamic> result;
              if (isAiPlan) {
                result = await _plansController.sendAiPlanForApproval(plan);
              } else {
                result = await _plansController.sendManualPlanForApproval(plan);
              }
              
              print('✅ Plan sent for approval successfully: $result');
              
            if (_scaffoldMessenger != null) {
              _scaffoldMessenger!.showSnackBar(
                const SnackBar(
                    content: Text('Plan sent for approval successfully!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              
              // Refresh the plans to update the approval status
              await _plansController.refreshPlans();
              
            } catch (e) {
              print('❌ Failed to send plan for approval: $e');
              if (_scaffoldMessenger != null) {
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

  Widget _buildActivePlanDailyView(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final currentDay = _plansController.getCurrentDay(planId);
    
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
      
      // Get items from the plan
      if (plan['items'] is List) {
        workouts = (plan['items'] as List).cast<Map<String, dynamic>>();
      } else if (plan['exercises_details'] is List) {
        workouts = (plan['exercises_details'] as List).cast<Map<String, dynamic>>();
      }
      
      if (workouts.isEmpty) return [];
      
      // Apply distribution logic similar to schedules
      return _distributeWorkoutsForPlan(workouts, _getTotalDays(plan), dayIndex);
    } catch (e) {
      print('❌ Error getting day workouts: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _distributeWorkoutsForPlan(List<Map<String, dynamic>> workouts, int totalDays, int dayIndex) {
    if (workouts.isEmpty) return [];
    
    // Calculate total minutes for distribution logic
    int totalMinutes = workouts.fold(0, (sum, workout) {
      return sum + (int.tryParse(workout['minutes']?.toString() ?? '0') ?? 0);
    });
    
    // Apply the same logic as schedules: if total minutes >= 80 and more than 2 workouts, limit to 2 per day
    if (totalMinutes >= 80 && workouts.length > 2) {
      // Distribute 2 workouts per day
      final workoutsPerDay = 2;
      final startIndex = dayIndex * workoutsPerDay;
      final endIndex = min(startIndex + workoutsPerDay, workouts.length);
      
      if (startIndex < workouts.length) {
        return workouts.sublist(startIndex, endIndex);
      }
    } else {
      // Show all workouts for this day (for shorter plans)
      return workouts;
    }
    
    return [];
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
}


