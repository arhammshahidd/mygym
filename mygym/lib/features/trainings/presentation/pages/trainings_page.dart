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

class _TrainingsPageState extends State<TrainingsPage> with SingleTickerProviderStateMixin {
  late final TrainingsController _controller;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Use existing controller to keep state across hot reloads and navigation
    _controller = Get.find<TrainingsController>();
    _tabController = TabController(length: 2, vsync: this);
    // Trigger load only if we haven't loaded yet
    if (!_controller.hasLoadedOnce.value && !_controller.isLoading.value) {
      _controller.loadData();
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
      appBar: AppBar(
        title: const Text('TRAINING'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2E7D32),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF2E7D32)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF2E7D32),
                indicator: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(24),
                ),
                tabs: const [
                  Tab(text: 'Schedules'),
                  Tab(text: 'Plans'),
                ],
              ),
            ),
          ),
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
      if (_controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      // Placeholder list styled like the screenshot
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _controller.plans.length,
        itemBuilder: (context, index) {
          final plan = _controller.plans[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E7D32)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              title: Text(
                plan['name']?.toString() ?? 'Workout',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              subtitle: const Text(
                '3 sets × 12 reps • 50 minutes • Strength',
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80),
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('View'),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildPlansTab() {
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Workout Plans',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  try {
                    Get.to(() => const CreatePlanPage());
                  } catch (e) {
                    // fallback to Navigator if GetX routing is not available
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatePlanPage()),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Create'),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Plan Generator',
              style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Get a personalized workout plan based on your goals, experience, and available time.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: () {
                        try {
                          Get.to(() => const AiGeneratePlanPage());
                        } catch (e) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AiGeneratePlanPage()),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Generate AI Plan'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Manual Plans list
            Obx(() {
              final items = _controller.plans;
              print('🎨 UI Update - Plans count: ${items.length}, isLoading: ${_controller.isLoading.value}, hasLoadedOnce: ${_controller.hasLoadedOnce.value}');
              if (items.isNotEmpty) {
                print('🎨 First plan data: ${items.first}');
                print('🎨 First plan ID: ${items.first['id']}');
              }
              
              if (_controller.isLoading.value && !_controller.hasLoadedOnce.value) {
                print('🎨 Showing loading spinner');
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                );
              }
              if (items.isEmpty && _controller.hasLoadedOnce.value) {
                print('🎨 Showing "No plans yet"');
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No Manual plans yet'),
                );
              }
              print('🎨 Showing ${items.length} plan cards');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ...items.map((plan) => _buildPlanCard(source: 'manual', data: plan)).toList(),
                ],
              );
            }),

            // AI Generated list
            Obx(() {
              final items = _controller.aiGenerated;
              if (_controller.isLoading.value && !_controller.hasLoadedOnce.value) {
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                );
              }
              if (items.isEmpty && _controller.hasLoadedOnce.value) {
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No AI generated plans yet'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ...items.map((plan) => _buildPlanCard(source: 'ai', data: plan)).toList(),
                ],
              );
            }),
          ],
        ),
      );
  }

  Widget _buildPlanCard({required String source, required Map<String, dynamic> data}) {
    final title = (data['name'] ?? data['exercise_plan'] ?? data['exercise_plan_category'] ?? data['title'] ?? 'Fitness Plan').toString();
    final category = (data['exercise_plan_category'] ?? data['exercise_plan'] ?? data['category'] ?? data['level'] ?? 'GENERAL').toString();
    // Derive total days from start/end if not provided
    String totalDaysStr;
    final sd = data['start_date']?.toString();
    final ed = data['end_date']?.toString();
    if (sd != null && ed != null) {
      final start = DateTime.tryParse(sd);
      final end = DateTime.tryParse(ed);
      if (start != null && end != null) {
        totalDaysStr = (end.difference(start).inDays + 1).toString();
      } else {
        totalDaysStr = (data['total_days'] ?? 0).toString();
      }
    } else {
      totalDaysStr = (data['total_days'] ?? 0).toString();
    }
    final totalWorkouts = (data['total_workouts'] ?? (data['items'] is List ? (data['items'] as List).length : 0)).toString();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  category.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.black54),
              const SizedBox(width: 6),
              Text('$totalDaysStr Days', style: const TextStyle(color: Colors.black87)),
              const SizedBox(width: 16),
              const Icon(Icons.fitness_center, size: 14, color: Colors.black54),
              const SizedBox(width: 6),
              Text('$totalWorkouts Workouts', style: const TextStyle(color: Colors.black87)),
            ],
          ),
          if (data['user_level']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person, size: 14, color: Colors.black54),
                const SizedBox(width: 6),
                Text('Level: ${data['user_level']}', style: const TextStyle(color: Colors.black87)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _controller.sendForApproval(source: source, payload: data);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sent for approval')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Send Plan for Approval'),
              ),
              OutlinedButton(
                onPressed: () {
                  print('🔍 Edit button clicked for plan: ${data['id']}');
                  print('🔍 Plan data: $data');
                  try {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditPlanPage(plan: data, isAi: source == 'ai'),
                      ),
                    );
                    print('🔍 Navigation to EditPlanPage successful');
                  } catch (e) {
                    print('❌ Error navigating to EditPlanPage: $e');
                  }
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF2E7D32))),
                child: const Text('Edit'),
              ),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlanDetailPage(plan: data, isAi: source == 'ai'),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF2E7D32))),
                child: const Text('View'),
              ),
              // Delete button - show for both manual and AI plans
              OutlinedButton.icon(
                onPressed: () => _showDeleteConfirmation(context, data, source),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  foregroundColor: Colors.red,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Map<String, dynamic> plan, String source) {
    final planName = plan['name']?.toString() ?? plan['exercise_plan']?.toString() ?? 'this plan';
    final planId = int.tryParse(plan['id']?.toString() ?? '');
    
    if (planId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid plan ID')),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Plan'),
          content: Text('Are you sure you want to delete "$planName"? This action cannot be undone.'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  if (source == 'ai') {
                    await _controller.deleteAiGeneratedPlan(planId);
                  } else {
                    await _controller.deleteManualPlan(planId);
                  }
                  // Use the original context for showing snackbar
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Plan deleted successfully')),
                    );
                  }
                } catch (e) {
                  // Use the original context for showing snackbar
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete plan: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
