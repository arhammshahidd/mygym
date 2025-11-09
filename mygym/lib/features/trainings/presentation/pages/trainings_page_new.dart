import 'dart:math';
import 'dart:convert';
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
    // Refresh approval status when Plans tab is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _plansController.refreshApprovalStatusFromBackend();
    });
    
    return RefreshIndicator(
      onRefresh: () async {
        print('🔄 Refreshing Plans tab...');
        await _plansController.refreshPlans();
        await _plansController.refreshApprovalStatusFromBackend();
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
              // Trigger approval status refresh when manual plans are displayed
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _plansController.refreshApprovalStatusFromBackend();
              });
              
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
                          label: const Text('Refresh'),
                        ),
                        IconButton(
                          onPressed: () async {
                            try {
                              await _plansController.resetManualPlanCache();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Manual plan cache cleared')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to clear cache: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.cleaning_services, size: 18),
                          tooltip: 'Reset Cache',
                          color: AppTheme.primaryColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...manualPlans
                        .map((plan) => Obx(() => _buildManualPlanCard(plan)))
                        .toList(),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            }),

          // Active Plan Daily Workouts Section
          Obx(() {
            // Touch uiTick so this section rebuilds on day changes
            final _ = _plansController.uiTick.value;
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
    
    // Get approval status - ALWAYS prefer plan data first (most up-to-date source)
    String approvalStatus = 'none';
    
    // First, check plan data directly for approval_status (most reliable source)
    if (plan['approval_status'] != null) {
      final planStatus = plan['approval_status'].toString().toLowerCase();
      if (planStatus.isNotEmpty && planStatus != 'none' && planStatus != 'null') {
        approvalStatus = planStatus;
        print('📝 UI - _buildManualPlanCard: Using approval_status from plan data: $planStatus for plan $planId');
      }
    }
    
    // Fallback to controller cache if plan data doesn't have status
    if (approvalStatus == 'none' || approvalStatus.isEmpty) {
      approvalStatus = _plansController.getPlanApprovalStatus(planId);
      print('📝 UI - _buildManualPlanCard: Using approval_status from controller cache: $approvalStatus for plan $planId');
    }
    
    print('📝 UI - _buildManualPlanCard: Final approvalStatus=$approvalStatus for plan $planId');

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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Delete Icon Button
                    IconButton(
                      onPressed: () async {
                        // Show confirmation dialog
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Plan'),
                            content: Text(
                              'Are you sure you want to delete "${plan['exercise_plan_category']?.toString() ?? 'Manual Plan'}"? This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true && mounted) {
                          try {
                            await _plansController.deleteManualPlan(planId);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Plan deleted successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              // Refresh plans list
                              await _plansController.refreshPlans();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete plan: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Delete Plan',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    _buildApprovalButton(plan, approvalStatus),
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
    // Handle both JSON string and parsed List formats (backend may return either)
    List<dynamic>? dailyPlans;
    final dailyPlansRaw = plan['daily_plans'];
    if (dailyPlansRaw is List) {
      dailyPlans = dailyPlansRaw;
    } else if (dailyPlansRaw is String && dailyPlansRaw.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(dailyPlansRaw);
        if (parsed is List) {
          dailyPlans = parsed;
        }
      } catch (e) {
        print('⚠️ AI Plan Card - Failed to parse daily_plans JSON string: $e');
      }
    }
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
    
    // Also check plan data directly for approval_status (most up-to-date source)
    if (plan['approval_status'] != null) {
      final planStatus = plan['approval_status'].toString().toLowerCase();
      if (planStatus.isNotEmpty && planStatus != 'none' && planStatus != 'null') {
        approvalStatus = planStatus;
        print('🔍 UI - _buildApprovalButton: Using approval_status from plan data: $planStatus for plan $planId');
      }
    }
    
    print('🔍 UI - _buildApprovalButton: planId=$planId, approvalStatus=$approvalStatus');
    
    // Check if plan has been sent for approval (has approval_id)
    final approvalId = _plansController.getApprovalIdForPlan(planId);
    final hasBeenSentForApproval = approvalId != null || plan['approval_id'] != null;
    
    // If status is 'pending' but plan hasn't been sent, treat it as 'none' to show Send Plan button
    final effectiveStatus = (approvalStatus == 'pending' && !hasBeenSentForApproval) 
        ? 'none' 
        : approvalStatus;
    
    print('🔍 UI - _buildApprovalButton: effectiveStatus=$effectiveStatus, hasBeenSentForApproval=$hasBeenSentForApproval');

    switch (effectiveStatus) {
      case 'pending':
        return ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
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
          onPressed: () async {
                  await _plansController.stopPlan(plan);
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
          // For manual plans: enforce approval flow before starting
          // Since we're in the 'approved' case, we know the plan is approved
          // Check if plan has been modified since approval - if so, show Resend Plan
          print('🔍 UI - Manual plan approved, hasBeenModified=$hasBeenModified');
          if (hasBeenModified) {
            print('🔍 UI - Showing Resend Plan button for modified approved plan');
            return ElevatedButton(
              onPressed: () async {
                try {
                  await _plansController.sendManualPlanForApproval(plan);
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      const SnackBar(
                        content: Text('Manual plan resent for approval successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  // Refresh plans and approval status to update UI
                  if (mounted) {
                    await _plansController.refreshPlans();
                    await _plansController.refreshApprovalStatusFromBackend();
                    setState(() {}); // Force UI update
                  }
                } catch (e) {
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('Failed to resend for approval: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Resend Plan'),
            );
          }
          
          // Plan is approved and not modified - show Start/Stop Plan button
          print('🔍 UI - Showing Start/Stop Plan button for approved plan');
          final isStarted = _plansController.isPlanStarted(planId);
          if (isStarted) {
            return ElevatedButton(
              onPressed: () async {
                await _plansController.stopPlan(plan);
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
    final int planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    final int backendId = int.tryParse(plan['plan_id']?.toString() ?? plan['id']?.toString() ?? '') ?? planId;
    final planName = plan['exercise_plan_category']?.toString() ?? (isAi ? 'AI Generated Plan' : 'Manual Plan');
    
    print('🗑️ Delete Confirmation - Plan ID: $planId, Backend ID: $backendId');
    print('🗑️ Delete Confirmation - Plan data: ${plan.keys.toList()}');
    print('🗑️ Delete Confirmation - plan[\'id\']: ${plan['id']}, plan[\'plan_id\']: ${plan['plan_id']}');
    
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
                    await _plansController.deleteAiGeneratedPlan(backendId);
                  } else {
                    await _plansController.deleteManualPlan(backendId);
                  }
                  
                  // Show success message using saved scaffold messenger
                  if (mounted && _scaffoldMessenger != null) {
                    _scaffoldMessenger!.showSnackBar(
                      SnackBar(
                        content: Text('${isAi ? 'AI Generated' : 'Manual'} plan deleted successfully'),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                    );
                  }
                } catch (e) {
                  // Show error message using saved scaffold messenger
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

  Widget _buildActiveScheduleDisplay() {
    return Obx(() {
      final activeSchedule = _schedulesController.activeSchedule!;
      print('🔍 Active Schedule Data: $activeSchedule');
      print('🔍 Available keys: ${activeSchedule.keys}');
      
      // IMPORTANT: Use the same identifier the controller uses to track day state.
      // The controller persists and increments current day against `id`, not `assignment_id`.
      // Using `assignment_id` here causes day index to reset/repeat visually.
      final planId = int.tryParse(activeSchedule['id']?.toString() ?? '') ?? 0;
      print('🔍 Using planId: $planId for assignment details (must match controller id)');
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
                      'Active Schedule - Day $currentDay',
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
                  // Use the schedules controller's workout distribution logic instead of _getDayItems
                  final dayWorkouts = _schedulesController.getActiveDayWorkouts();
                  
                  if (dayWorkouts.isEmpty) {
                    return const Text('No workouts for this day', style: TextStyle(color: AppTheme.textColor));
                  }
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Workouts (${dayWorkouts.length} workouts)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                      ),
                      const SizedBox(height: 8),
                      ...dayWorkouts.map((item) => _buildWorkoutItem(item)).toList(),
                      const SizedBox(height: 16),
                      // Completed days stacked below
                      // currentDay is now 1-based, so show days 1 to currentDay-1
                      if (currentDay > 1) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Completed Days',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                        ),
                        const SizedBox(height: 8),
                        for (int d = currentDay - 1; d >= 1; d--) ...[
                          _buildCompletedDaySummary(planDetails, d),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  // Compact summary card for a completed day shown below the current day
  // dayIndex is now 1-based (Day 1, Day 2, etc.)
  Widget _buildCompletedDaySummary(Map<String, dynamic> planDetails, int dayIndex) {
    // Use schedules controller's getDayWorkoutsForDay to get correct workouts for this day
    final activeSchedule = _schedulesController.activeSchedule;
    if (activeSchedule == null) {
      return const SizedBox.shrink();
    }
    
    // Use schedules controller's method which properly distributes workouts by day
    // dayIndex is 1-based (Day 1, Day 2, etc.)
    final items = _schedulesController.getDayWorkoutsForDay(activeSchedule, dayIndex);
    
    return Card(
      color: AppTheme.cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.primaryColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Day $dayIndex',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textColor),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.take(2).map((w) {
                final name = w['name']?.toString() ?? w['workout_name']?.toString() ?? 'Workout';
                final minutes = w['minutes'] ?? w['training_minutes'];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryColor.withOpacity(0.6)),
                  ),
                  child: Text(
                    '$name • ${minutes ?? 0} min',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
                  ),
                );
              }).toList(),
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
                    'Day $currentDay',
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
            
            // Weight - Always show weight row (even if 0, to show proper display)
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
    // Check multiple possible field names for weight
    final weightMinRaw = item['weight_min_kg'] ?? item['weight_min'] ?? item['min_weight'] ?? item['min_weight_kg'];
    final weightMaxRaw = item['weight_max_kg'] ?? item['weight_max'] ?? item['max_weight'] ?? item['max_weight_kg'];
    final weightRaw = item['weight_kg'] ?? item['weight'] ?? 0;
    
    // Check if weight_kg is stored as a string range like "20-40"
    String? parsedRange;
    if (weightRaw != null && weightRaw is String && weightRaw.contains('-')) {
      // weight_kg is stored as a string range (e.g., "20-40")
      final parts = weightRaw.split('-');
      if (parts.length == 2) {
        final minStr = parts[0].trim();
        final maxStr = parts[1].trim();
        final minVal = _safeParseDouble(minStr);
        final maxVal = _safeParseDouble(maxStr);
        // Always display the range if it's stored as a string range
        parsedRange = '${minVal.toStringAsFixed(0)}-${maxVal.toStringAsFixed(0)} kg';
      }
    }
    
    final weightMin = _safeParseDouble(weightMinRaw);
    final weightMax = _safeParseDouble(weightMaxRaw);
    final weight = weightRaw is String && weightRaw.contains('-') ? null : _safeParseDouble(weightRaw);
    
    print('🔍 Format Weight Display - item keys: ${item.keys.toList()}');
    print('🔍 Format Weight Display - weight_min_kg: $weightMinRaw (parsed: $weightMin)');
    print('🔍 Format Weight Display - weight_max_kg: $weightMaxRaw (parsed: $weightMax)');
    print('🔍 Format Weight Display - weight_kg: $weightRaw (parsed: $weight, range: $parsedRange)');
    
    // If weight_kg was a string range, return it directly
    if (parsedRange != null) {
      return parsedRange;
    }
    
    // If we have min and max, show range (even if one is 0)
    if (weightMin != null && weightMax != null) {
      if (weightMin == 0 && weightMax == 0) {
        // Both are 0, check if single weight exists
        if (weight != null && weight > 0) {
          return '${weight.toStringAsFixed(0)} kg';
        }
        return '0 kg';
      }
      return '${weightMin.toStringAsFixed(0)}-${weightMax.toStringAsFixed(0)} kg';
    }
    // If we only have min or max, show that with a dash
    else if (weightMin != null && weightMin > 0) {
      return '${weightMin.toStringAsFixed(0)}+ kg';
    }
    else if (weightMax != null && weightMax > 0) {
      return 'up to ${weightMax.toStringAsFixed(0)} kg';
    }
    // Fallback to single weight value (even if 0, show it)
    else if (weight != null) {
      return '${weight.toStringAsFixed(0)} kg';
    }
    
    return '0 kg';
  }

  Widget _buildActivePlanDailyView(Map<String, dynamic> plan) {
    final planId = int.tryParse(plan['id']?.toString() ?? '') ?? 0;
    // Use Obx to make currentDay reactive to uiTick changes
    return Obx(() {
      final currentDay = _plansController.getCurrentDay(planId);
      // Touch uiTick to ensure rebuild when day changes
      final _ = _plansController.uiTick.value;
      
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
        
        // Daily Workouts - Directly use controller's resolved workouts (uses backend daily_plans)
        Obx(() {
          final reactiveCurrentDay = _plansController.getCurrentDay(planId);
          final workouts = _plansController.getActiveDayWorkouts();
          print('🔍 PlansPage - Building workouts for Day ${reactiveCurrentDay + 1} from controller: ${workouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
          if (workouts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No workouts for this day', style: TextStyle(color: AppTheme.textColor)),
            );
          }
          return Column(
            children: workouts.map((workout) => _buildPlanWorkoutItem(workout, planId, reactiveCurrentDay)).toList(),
          );
        }),
        
        const SizedBox(height: 16),
      ],
    );
    });
  }

  int _getTotalDays(Map<String, dynamic> plan) {
    if (plan['start_date'] != null && plan['end_date'] != null) {
      final start = DateTime.tryParse(plan['start_date']);
      final end = DateTime.tryParse(plan['end_date']);
      if (start != null && end != null) {
        return max(1, end.difference(start).inDays + 1);
      }
    }
    final dynamic explicitDays = plan['total_days'];
    if (explicitDays is int && explicitDays > 0) return explicitDays;
    if (explicitDays is String) {
      final parsed = int.tryParse(explicitDays);
      if (parsed != null && parsed > 0) return parsed;
    }
    // Fallback: derive from items using same distribution rule
    List<Map<String, dynamic>> workouts = [];
    if (plan['items'] is List) {
      workouts = (plan['items'] as List).whereType<Map<String, dynamic>>().toList();
    } else if (plan['exercises_details'] is List) {
      workouts = (plan['exercises_details'] as List).whereType<Map<String, dynamic>>().toList();
    }
    if (workouts.isEmpty) return 1;
    final int totalMinutes = workouts.fold(0, (sum, w) => sum + _itemMinutes(w));
    if (totalMinutes >= 80 && workouts.length > 2) {
      return ((workouts.length + 1) / 2).ceil();
    }
    // All workouts can fit in a single day
    return 1;
  }

  List<Map<String, dynamic>> _getDayWorkouts(Map<String, dynamic> plan, int dayIndex) {
    try {
      print('🔍 PlansPage - _getDayWorkouts called for day $dayIndex');
      print('🔍 PlansPage - Plan keys: ${plan.keys}');
      
      // Check if this is an API response with nested data (same as schedules)
      Map<String, dynamic> actualPlan = plan;
      if (plan.containsKey('success') && plan.containsKey('data')) {
        print('🔍 PlansPage - Detected API response format, extracting data field');
        actualPlan = plan['data'] ?? {};
        print('🔍 PlansPage - Actual plan keys: ${actualPlan.keys}');
      }
      
      // 1) Prefer backend daily_plans when present (List or JSON string)
      final dailyPlansRaw = actualPlan['daily_plans'];
      List<Map<String, dynamic>>? dailyPlansList;
      if (dailyPlansRaw is List) {
        if (dailyPlansRaw.isNotEmpty) {
          dailyPlansList = dailyPlansRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } else if (dailyPlansRaw is String && dailyPlansRaw.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(dailyPlansRaw);
          if (parsed is List) {
            dailyPlansList = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (e) {
          print('⚠️ PlansPage - Failed to parse daily_plans string: $e');
        }
      }
      if (dailyPlansList != null && dailyPlansList.isNotEmpty) {
        try {
          Map<String, dynamic>? dayEntry = dailyPlansList.firstWhereOrNull((dp) {
            final d = int.tryParse(dp['day']?.toString() ?? '');
            return d != null && d == dayIndex + 1;
          });
          dayEntry ??= (dayIndex < dailyPlansList.length ? dailyPlansList[dayIndex] : null);
          List<Map<String, dynamic>>? resultList;
          if (dayEntry != null && dayEntry['workouts'] is List) {
            resultList = (dayEntry['workouts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else if (dayEntry != null && dayEntry['workouts'] is String) {
            try {
              final parsedW = jsonDecode(dayEntry['workouts'] as String);
              if (parsedW is List) {
                resultList = parsedW.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              }
            } catch (e) {
              print('⚠️ PlansPage - Failed to parse workouts string for day ${dayIndex + 1}: $e');
            }
          }
          if (resultList != null) {
            print('🔍 PlansPage - Using daily_plans for day ${dayIndex + 1}: ${resultList.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
            return resultList;
          }
        } catch (e) {
          print('⚠️ PlansPage - Failed to use daily_plans for day ${dayIndex + 1}: $e');
        }
      }

      List<Map<String, dynamic>> workouts = [];
      
      // Get items from the plan (same priority as schedules)
      if (actualPlan['items'] is List) {
        workouts = (actualPlan['items'] as List).cast<Map<String, dynamic>>();
        print('🔍 PlansPage - Found ${workouts.length} workouts in items');
      } else if (actualPlan['exercises_details'] is List) {
        workouts = (actualPlan['exercises_details'] as List).cast<Map<String, dynamic>>();
        print('🔍 PlansPage - Found ${workouts.length} workouts in exercises_details (List)');
      } else if (actualPlan['exercises_details'] is String) {
        // Handle JSON string format (same as schedules)
        try {
          final List<dynamic> parsed = jsonDecode(actualPlan['exercises_details'] as String);
          workouts = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          print('🔍 PlansPage - Parsed ${workouts.length} workouts from exercises_details (JSON String)');
        } catch (e) {
          print('❌ PlansPage - Error parsing exercises_details JSON: $e');
        }
      }
      
      if (workouts.isEmpty) {
        print('⚠️ PlansPage - No workouts found for plan');
        return [];
      }
      
      // Calculate total days (same as schedules and controller)
      int totalDays = 1;
      if (actualPlan['start_date'] != null && actualPlan['end_date'] != null) {
        final start = DateTime.tryParse(actualPlan['start_date'].toString());
        final end = DateTime.tryParse(actualPlan['end_date'].toString());
        if (start != null && end != null) {
          totalDays = max(1, end.difference(start).inDays + 1);
        }
      } else {
        totalDays = max(1, int.tryParse(actualPlan['total_days']?.toString() ?? '1') ?? 1);
      }
      
      print('🔍 PlansPage - Total days: $totalDays, Requesting day: $dayIndex');
      
      // 2) Fallback to client rotation (same as schedules)
      return _distributeWorkoutsForPlan(workouts, totalDays, dayIndex);
    } catch (e) {
      print('❌ PlansPage - Error getting day workouts: $e');
      print('❌ PlansPage - Error stack: ${e.toString()}');
      return [];
    }
  }

  List<Map<String, dynamic>> _distributeWorkoutsForPlan(List<Map<String, dynamic>> workouts, int totalDays, int dayIndex) {
    if (workouts.isEmpty) return [];
    
    print('🔍 PlansPage - _distributeWorkoutsForPlan: ${workouts.length} workouts across $totalDays days, requesting day $dayIndex');
    
    // Use EXACT same logic as schedules controller and plans controller
    // If only one workout, return it for all days
    if (workouts.length == 1) {
      final single = Map<String, dynamic>.from(workouts.first);
      print('🔍 PlansPage - Only one workout available: ${single['name'] ?? single['workout_name'] ?? 'Unknown'}');
      return [single];
    }

    // Day-based distribution using rotation offset for ALL cases (same as backend)
    // Backend: dayRotationOffset = ((day - 1) * workoutsPerDay) % exercises.length
    // Frontend: dayRotationOffset = (dayIndex * workoutsPerDay) % workouts.length (0-based dayIndex)
    // Rotation always applies for all cases (as per backend fix)
    const int workoutsPerDay = 2;
    final int dayRotationOffset = (dayIndex * workoutsPerDay) % workouts.length;
    final int firstIdx = dayRotationOffset;
    final int secondIdx = (dayRotationOffset + 1) % workouts.length;
    
    final Map<String, dynamic> first = Map<String, dynamic>.from(workouts[firstIdx]);
    final Map<String, dynamic> second = Map<String, dynamic>.from(workouts[secondIdx]);
    final int m1 = _itemMinutes(first);
    final int m2 = _itemMinutes(second);
    int combined = m1 + m2;
    
    print('🔍 PlansPage - dayRotationOffset: $dayRotationOffset (dayIndex: $dayIndex, workoutsPerDay: $workoutsPerDay, totalWorkouts: ${workouts.length})');
    print('🔍 PlansPage - Pair indices: $firstIdx & $secondIdx → ${first['name'] ?? first['workout_name'] ?? 'Unknown'}($m1) + ${second['name'] ?? second['workout_name'] ?? 'Unknown'}($m2) = $combined');
    
    List<Map<String, dynamic>> selectedWorkouts = [];
    
    // Updated distribution logic:
    // - If total minutes > 80: show only 1 workout
    // - If total minutes <= 80: show 2 workouts
    // - If total minutes < 50: try to add a third workout if available
    if (combined > 80) {
      // More than 80 minutes: show only first workout
      selectedWorkouts = [first];
      print('🔍 PlansPage - Total minutes ($combined) > 80, showing only 1 workout');
    } else if (combined < 50) {
      // Less than 50 minutes: try to add a third workout
      selectedWorkouts = [first, second];
      
      if (workouts.length > 2) {
        final int thirdIdx = (dayRotationOffset + 2) % workouts.length;
        final Map<String, dynamic> third = Map<String, dynamic>.from(workouts[thirdIdx]);
        final int m3 = _itemMinutes(third);
        final int totalWithThird = combined + m3;
        
        // Only add third workout if it doesn't exceed 80 minutes
        if (totalWithThird <= 80) {
          selectedWorkouts.add(third);
          combined = totalWithThird;
          print('🔍 PlansPage - Total minutes ($combined) < 50, added third workout: ${third['name'] ?? third['workout_name'] ?? 'Unknown'}($m3)');
        } else {
          print('🔍 PlansPage - Total minutes would be $totalWithThird with third workout, keeping 2 workouts');
        }
      } else {
        print('🔍 PlansPage - Total minutes ($combined) < 50, but only ${workouts.length} workouts available');
      }
    } else {
      // Between 50 and 80 minutes: show 2 workouts
      selectedWorkouts = [first, second];
      print('🔍 PlansPage - Total minutes ($combined) between 50-80, showing 2 workouts');
    }

    print('🔍 PlansPage - Day $dayIndex selected workouts: ${selectedWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()} (total: ${selectedWorkouts.fold<int>(0, (sum, w) => sum + _itemMinutes(w))} minutes)');
    return selectedWorkouts;
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
                  child: _buildDetailChip('Weight', _formatWeightDisplay(item)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDetailChip('Minutes', '${_itemMinutes(item)}'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Start Workout Button
            Obx(() {
              final String safeName = (item['name'] ?? item['workout_name'] ?? item['muscle_group'] ?? 'Workout').toString().replaceAll(' ', '_');
              final int minutesVal = _itemMinutes(item);
              final workoutKey = '${planId}_${currentDay}_${safeName}_${minutesVal}';
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
                  final int totalMinutes = _itemMinutes(item);
                  _plansController.startWorkout(workoutKey, totalMinutes);
                };
              }
              
              return SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
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
                    if (!isStarted && !isCompleted)
                      TextButton(
                        onPressed: () {
                          final int totalMinutes = _itemMinutes(item);
                          _plansController.startWorkout(workoutKey, totalMinutes);
                          _plansController.forceCompleteWorkout(workoutKey);
                        },
                        child: const Text('Mark Completed'),
                      ),
                  ],
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

  int _itemMinutes(Map<String, dynamic> item) {
    dynamic m = item['minutes'] ?? item['training_minutes'] ?? item['trainingMinutes'] ??
               item['duration'] ?? item['time_minutes'] ?? item['time_mins'] ??
               item['time'] ?? item['mins'] ?? item['minute'];
    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.round();
      final s = v.toString().replaceAll(RegExp(r'[^0-9\.-]'), '');
      return int.tryParse(s) ?? 0;
    }
    final val = toInt(m);
    if (val == 0) {
      // Debug: log keys once when minutes cannot be found
      // ignore: avoid_print
      print('⚠️ Minutes not found on item. Keys: ${item.keys} Values: ${item}');
    }
    return val;
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


