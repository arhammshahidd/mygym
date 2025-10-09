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
    
    // Load initial data for both tabs
    _schedulesController.loadSchedulesData();
    _plansController.loadPlansData();
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
                    plan['exercise_plan_category']?.toString() ?? 'Workout Plan',
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
            Text('Plan ID: ${plan['id']}'),
            if (plan['web_plan_id'] != null)
              Text('Web Plan ID: ${plan['web_plan_id']}'),
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
            Text('Plan: ${activeSchedule['exercise_plan_category'] ?? 'Workout Plan'}'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                _schedulesController.stopSchedule(activeSchedule);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
