import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/meal_plan.dart';
import '../controllers/nutrition_controller.dart';
import '../../data/services/ai_nutrition_service.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final NutritionController _c;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _c = Get.put(NutritionController(), permanent: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Don't dispose the controller since it's permanent
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Food Nutrition'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.textColor,
          unselectedLabelColor: AppTheme.textColor,
          tabs: const [
            Tab(text: 'Schedules'),
            Tab(text: 'AI Suggestions'),
          ],
        ),
      ),
      body: Builder(
        builder: (context) {
          try {
            return TabBarView(
        controller: _tabController,
        children: [
          const _SchedulesTab(),
          const _AiTab(),
        ],
            );
          } catch (e) {
            // Fallback UI if there's a rendering error
            return const Center(
              child: Text('Loading...', style: TextStyle(color: AppTheme.textColor)),
            );
          }
        },
      ),
    );
  }
}

class _SchedulesTab extends StatelessWidget {
  const _SchedulesTab();

  @override
  Widget build(BuildContext context) {
    final NutritionController c = Get.find<NutritionController>();
    return Obx(() {
      final assigned = c.assignedPlan.value;
      return RefreshIndicator(
        onRefresh: () async {
          try {
          await c.loadAssignedFromBackend();
          } catch (e) {
            print('Error refreshing: $e');
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _metricCard(title: 'Daily Calories', value: assigned?.totalCaloriesPerDay.toString() ?? '—')),
                const SizedBox(width: 12),
                Expanded(
                  child: _macroCard(assigned),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Assigned Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textColor)),
            const SizedBox(height: 8),
            if (assigned == null)
              const Text('No plan assigned. Start a plan from below.', style: TextStyle(color: AppTheme.textColor))
            else
              _assignedPlanCard(assigned, c),
              // Show Today's Meal only when plan is active
              if (assigned != null && c.mealPlanActive.value) ...[
                const SizedBox(height: 16),
                const Text("Today's Meal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textColor)),
                const SizedBox(height: 8),
                _todayMealsSection(assigned, c),
              ],
            // Removed dummy available plans list per requirement
          ],
          ),
        ),
      );
    });
  }

  Widget _metricCard({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppTheme.textColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: AppTheme.textColor, fontSize: 28, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _macroCard(MealPlan? plan) {
    final DayMeals? day = plan?.days.isNotEmpty == true ? plan!.days.first : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Macronutrients', style: TextStyle(color: AppTheme.textColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Proteins: ${day?.totalProtein ?? '—'}g', style: const TextStyle(color: AppTheme.textColor)),
        Text('Carbs: ${day?.totalCarbs ?? '—'}g', style: const TextStyle(color: AppTheme.textColor)),
        Text('Fat: ${day?.totalFat ?? '—'}g', style: const TextStyle(color: AppTheme.textColor)),
      ]),
    );
  }

  Widget _planCard(MealPlan plan, NutritionController c, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(plan.note, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                Text('${plan.totalCaloriesPerDay} cal/day', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
            Column(children: [
              ElevatedButton(
                onPressed: () => c.assignPlan(plan),
                style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                child: const Text('Start Plan'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => _showSchedulePlanDetails(Get.context!, plan), child: const Text('View')),
            ])
          ],
        ),
      ]),
    );
  }

  Widget _assignedPlanCard(MealPlan plan, NutritionController c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        border: Border.all(color: AppTheme.primaryColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(child: Text(plan.title, style: const TextStyle(color: AppTheme.textColor, fontSize: 16, fontWeight: FontWeight.w800))),
            Text('${plan.days.length} DAYS', style: const TextStyle(color: AppTheme.textColor, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(plan.note, style: const TextStyle(color: AppTheme.textColor)),
        const SizedBox(height: 6),
        Text('${plan.totalCaloriesPerDay} cal/day', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textColor)),
        const SizedBox(height: 8),
        Row(children: [
          Obx(() {
            final isActive = c.mealPlanActive.value;
            return ElevatedButton(
              onPressed: () {
                if (isActive) {
                  c.stopPlan();
                } else {
                  c.assignPlan(plan);
                  c.startPlan();
                }
              },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: AppTheme.textColor),
              child: Text(isActive ? 'Stop Meal Plan' : 'Start Meal Plan'),
            );
          }),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _showSchedulePlanDetails(Get.context!, plan),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryColor, side: const BorderSide(color: AppTheme.primaryColor)),
            child: const Text('View Details'),
          ),
        ])
      ]),
    );
  }

  Widget _todayMealsSection(MealPlan plan, NutritionController c) {
    final int index = (c.activeDayIndex.value >= 0 && c.activeDayIndex.value < plan.days.length) ? c.activeDayIndex.value : 0;
    final day = plan.days[index];
    return Column(children: [
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Breakfast', items: day.breakfast),
      const SizedBox(height: 12),
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Lunch', items: day.lunch),
      const SizedBox(height: 12),
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Dinner', items: day.dinner),
    ]);
  }

  Widget _todayMealCard({required String dayLabel, required String title, required List<MealItem> items}) {
    final totalCalories = items.fold(0, (a, b) => a + b.calories);
    final totalProteins = items.fold(0.0, (a, b) => a + b.proteinGrams);
    final totalCarbs = items.fold(0.0, (a, b) => a + b.carbsGrams);
    final totalFats = items.fold(0.0, (a, b) => a + b.fatGrams);
    
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        border: Border.all(color: AppTheme.primaryColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dayLabel, style: const TextStyle(fontSize: 12, color: AppTheme.textColor)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: AppTheme.textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (items.isNotEmpty)
                  Text(items.first.name, style: const TextStyle(color: AppTheme.textColor)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('Logged', style: TextStyle(color: AppTheme.textColor, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          ...items.skip(1).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(e.name, style: const TextStyle(color: AppTheme.textColor)),
              )),
          const SizedBox(height: 8),
          // Nutritional information row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNutritionInfo('Calories', '$totalCalories', AppTheme.textColor),
              _buildNutritionInfo('Proteins', '${totalProteins.toInt()}g', AppTheme.textColor),
              _buildNutritionInfo('Carbs', '${totalCarbs.toInt()}g', AppTheme.textColor),
              _buildNutritionInfo('Fats', '${totalFats.toInt()}g', AppTheme.textColor),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildNutritionInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.textColor,
          ),
        ),
      ],
    );
  }

  void _showSchedulePlanDetails(BuildContext context, MealPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Schedule Details (${plan.days.length} Days)',
                    style: const TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textColor),
                  ),
                ],
              ),
            ),
            // Grid content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Responsive columns: ~180px per tile, at least 2 columns
                    final int cols = width ~/ 180 >= 2 ? width ~/ 180 : 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols.clamp(2, 3),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                        // Slightly taller tiles to avoid overflow
                        childAspectRatio: 0.6,
                  ),
                  itemCount: plan.days.length,
                      itemBuilder: (_, i) => _scheduleDayDetailCard(plan.days[i], AppTheme.primaryColor),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDailyCards(BuildContext context, MealPlan plan, Color color, NutritionController c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DailyMealPlanView(plan: plan, color: color, controller: c),
    );
  }

  Widget _dayCard(DayMeals day, Color color) {
    Widget mealTile(String title, List<MealItem> items) {
      final total = items.fold(0, (a, b) => a + b.calories);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (_, i) => Text(
                  items[i].name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('$total cal', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DAY ${day.dayNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Expanded(
            child: Column(children: [
              Expanded(child: mealTile('Breakfast', day.breakfast)),
              const SizedBox(height: 8),
              Expanded(child: mealTile('Lunch', day.lunch)),
              const SizedBox(height: 8),
              Expanded(child: mealTile('Dinner', day.dinner)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _compactDayCard(DayMeals day, Color color) {
    final totalCalories = day.totalCalories;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'DAY ${day.dayNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compactMealRow('B', day.breakfast, color),
                  const SizedBox(height: 2),
                  _compactMealRow('L', day.lunch, color),
                  const SizedBox(height: 2),
                  _compactMealRow('D', day.dinner, color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$totalCalories cal',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactMealRow(String label, List<MealItem> items, Color color) {
    final total = items.fold(0, (a, b) => a + b.calories);
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$total',
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }


  Widget _scheduleCompactDayCard(DayMeals day, Color color) {
    final totalCalories = day.totalCalories;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'DAY ${day.dayNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _scheduleCompactMealRow('B', day.breakfast, color),
                  const SizedBox(height: 2),
                  _scheduleCompactMealRow('L', day.lunch, color),
                  const SizedBox(height: 2),
                  _scheduleCompactMealRow('D', day.dinner, color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$totalCalories cal',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleCompactMealRow(String label, List<MealItem> items, Color color) {
    final total = items.fold(0, (a, b) => a + b.calories);
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$total',
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _scheduleDayDetailCard(DayMeals day, Color color) {
    Widget mealTile(String title, List<MealItem> items) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            const SizedBox(height: 6),
            // Use Flexible with ListView shrinkWrap to avoid overflow in small tiles
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(items[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${items[i].calories} cal   ${items[i].proteinGrams}g protein   ${items[i].carbsGrams}g carbs   ${items[i].fatGrams}g fats',
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DAY ${day.dayNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          // Avoid nested Expanded overflow by using Flexible tiles
          Expanded(
            child: Column(children: [
              Flexible(child: mealTile('Breakfast', day.breakfast)),
              const SizedBox(height: 6),
              Flexible(child: mealTile('Lunch', day.lunch)),
              const SizedBox(height: 6),
              Flexible(child: mealTile('Dinner', day.dinner)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DailyMealPlanView extends StatefulWidget {
  final MealPlan plan;
  final Color color;
  final NutritionController controller;

  const _DailyMealPlanView({
    required this.plan,
    required this.color,
    required this.controller,
  });

  @override
  State<_DailyMealPlanView> createState() => _DailyMealPlanViewState();
}

class _DailyMealPlanViewState extends State<_DailyMealPlanView> {
  late PageController _pageController;
  int _currentDay = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextDay() {
    if (_currentDay < widget.plan.days.length - 1) {
      setState(() {
        _currentDay++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousDay() {
    if (_currentDay > 0) {
      setState(() {
        _currentDay--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(
        children: [
          // Header with day navigation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _currentDay > 0 ? _previousDay : null,
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                ),
                Text(
                  'DAY ${_currentDay + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _currentDay < widget.plan.days.length - 1 ? _nextDay : null,
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                ),
              ],
            ),
          ),
          // Day content
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentDay = index;
                });
                widget.controller.setActiveDay(index);
              },
              itemCount: widget.plan.days.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildDayContent(widget.plan.days[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayContent(DayMeals day) {
    return Column(
      children: [
        // Breakfast
        _buildMealSection('Breakfast', day.breakfast, Icons.wb_sunny),
        const SizedBox(height: 16),
        // Lunch
        _buildMealSection('Lunch', day.lunch, Icons.wb_sunny_outlined),
        const SizedBox(height: 16),
        // Dinner
        _buildMealSection('Dinner', day.dinner, Icons.nights_stay),
        const SizedBox(height: 16),
        // Next Day Button
        if (_currentDay < widget.plan.days.length - 1)
          ElevatedButton(
            onPressed: _nextDay,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Next Day'),
          ),
      ],
    );
  }

  Widget _buildMealSection(String title, List<MealItem> items, IconData icon) {
    final total = items.fold(0, (a, b) => a + b.calories);
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: widget.color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.color,
                  ),
                ),
                const Spacer(),
                Text(
                  '$total cal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: widget.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Text(
                    '${item.calories} cal',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
}

class _AiTab extends StatefulWidget {
  const _AiTab();

  @override
  State<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<_AiTab> {
  final NutritionController c = Get.find<NutritionController>();
  PlanCategory? _category;

  MealPlan _convertToMealPlan(Map<String, dynamic> planDetails, Map<String, dynamic> planData) {
    print('🔍 DEBUG: _convertToMealPlan called with planDetails keys: ${planDetails.keys.toList()}');
    print('🔍 DEBUG: _convertToMealPlan called with planData keys: ${planData.keys.toList()}');
    print('🔍 DEBUG: Full planDetails structure: $planDetails');
    
    // Extract plan data for use throughout the function
    final extractedPlanData = planDetails['data'] ?? planDetails;
    
    // Check if data is already in frontend format (has 'days' key)
    if (planDetails.containsKey('days') && planDetails['days'] is List) {
      print('🔍 DEBUG: Data already in frontend format, converting days directly');
      final daysList = planDetails['days'] as List;
      print('🔍 DEBUG: Days list length: ${daysList.length}');
      print('🔍 DEBUG: Days list content: $daysList');
      
      final days = <DayMeals>[];
      
      for (int i = 0; i < daysList.length; i++) {
        final dayData = daysList[i] as Map<String, dynamic>;
        print('🔍 DEBUG: Processing day $i: ${dayData.keys.toList()}');
        
        final breakfast = _convertMealItems(dayData['breakfast'] as List? ?? []);
        final lunch = _convertMealItems(dayData['lunch'] as List? ?? []);
        final dinner = _convertMealItems(dayData['dinner'] as List? ?? []);
        
        print('🔍 DEBUG: Day $i - Breakfast: ${breakfast.length}, Lunch: ${lunch.length}, Dinner: ${dinner.length}');
        
        days.add(DayMeals(
          dayNumber: i + 1,
          breakfast: breakfast,
          lunch: lunch,
          dinner: dinner,
        ));
      }
      
      print('🔍 DEBUG: Converted ${days.length} days from frontend format');
      
      return MealPlan(
        id: planData['id']?.toString() ?? planDetails['id']?.toString() ?? 'generated',
        title: planData['meal_category']?.toString() ?? planDetails['meal_category']?.toString() ?? 'AI Generated Plan',
        category: (planData['meal_category'] ?? planDetails['meal_category'] ?? '').toString().toLowerCase().contains('weight')
            ? PlanCategory.weightLoss
            : PlanCategory.muscleGain,
        note: 'AI Generated Meal Plan',
        days: days,
      );
    }
    
    // Fallback to original logic for backend format
    print('🔍 DEBUG: Data in backend format, using original conversion logic');
    print('🔍 DEBUG: planDetails structure: $planDetails');
    
    // Check if we have daily_plans or items
    print('🔍 DEBUG: Using extractedPlanData section: ${extractedPlanData.keys.toList()}');
    
    // Normalize helpers
    String _toDateOnly(dynamic v) {
      final s = v?.toString() ?? '';
      if (s.isEmpty) return DateTime.now().toIso8601String().split('T').first;
      try {
        return DateTime.parse(s).toIso8601String().split('T').first;
      } catch (_) {
        return s.split('T').first;
      }
    }

    // Extract items from nested data if present, else root
    final data = (planDetails['data'] is Map) ? Map<String, dynamic>.from(planDetails['data']) : planDetails;
    print('🔍 DEBUG: Data keys: ${data.keys.toList()}');
    print('🔍 DEBUG: Data structure: $data');
    
    // Check for different possible item locations
    List<Map<String, dynamic>> items = [];
    
    if (data['items'] is List) {
      print('🔍 DEBUG: Found items in data.items with ${(data['items'] as List).length} entries');
      items = List<Map<String, dynamic>>.from(data['items'].map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)));
    } else if (planDetails['items'] is List) {
      print('🔍 DEBUG: Found items in planDetails.items with ${(planDetails['items'] as List).length} entries');
      items = List<Map<String, dynamic>>.from((planDetails['items'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)));
    } else if (data['daily_plans'] is List) {
      print('🔍 DEBUG: Found daily_plans with ${(data['daily_plans'] as List).length} entries');
      for (final dp in data['daily_plans']) {
        if (dp is Map && dp['items'] is List) {
          print('🔍 DEBUG: Daily plan has ${(dp['items'] as List).length} items');
          items.addAll((dp['items'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)));
        }
      }
    } else if (data['food_items'] is List) {
      print('🔍 DEBUG: Found food_items with ${(data['food_items'] as List).length} entries');
      items = List<Map<String, dynamic>>.from(data['food_items'].map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)));
    } else {
      print('⚠️ DEBUG: No items found in any expected location');
      print('⚠️ DEBUG: Available keys in data: ${data.keys.toList()}');
      
      // Try to find any list that might contain meal items
      for (final key in data.keys) {
        final value = data[key];
        if (value is List && value.isNotEmpty) {
          print('🔍 DEBUG: Found list under key "$key" with ${value.length} items');
          if (value.first is Map) {
            final firstItem = value.first as Map<String, dynamic>;
            print('🔍 DEBUG: First item in "$key": ${firstItem.keys.toList()}');
            if (firstItem.containsKey('food_item_name') || firstItem.containsKey('meal_type') || firstItem.containsKey('name')) {
              print('🔍 DEBUG: Key "$key" appears to contain meal items, using it');
              items = List<Map<String, dynamic>>.from(value.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)));
              break;
            }
          }
        }
      }
    }

    print('🔍 DEBUG: Total items collected: ${items.length}');
    if (items.isNotEmpty) {
      print('🔍 DEBUG: First item structure: ${items.first.keys.toList()}');
      print('🔍 DEBUG: First item: ${items.first}');
    }

    // Group items by date and meal type (Breakfast/Lunch/Dinner)
    final Map<String, Map<String, List<MealItem>>> groupedItems = {};
    print('🔍 DEBUG: Starting to group ${items.length} items');
    
    // Track all unique dates found in items
    final Set<String> allDates = {};
    
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final date = _toDateOnly(item['date']);
      final mealType = (item['meal_type']?.toString() ?? 'Breakfast');
      final foodName = item['food_item_name']?.toString() ?? 'Food';
      final calories = (item['calories'] is num) ? (item['calories'] as num).toInt() : int.tryParse('${item['calories']}') ?? 0;
      final protein = (item['proteins'] is num) ? (item['proteins'] as num).toInt() : int.tryParse('${item['proteins'] ?? item['protein']}') ?? 0;
      final carbs = (item['carbs'] is num) ? (item['carbs'] as num).toInt() : int.tryParse('${item['carbs']}') ?? 0;
      final fats = (item['fats'] is num) ? (item['fats'] as num).toInt() : int.tryParse('${item['fats'] ?? item['fat']}') ?? 0;
      final grams = (item['grams'] is num) ? (item['grams'] as num).toInt() : int.tryParse('${item['grams']}') ?? 0;

      print('🔍 DEBUG: Item $i - Date: $date, Meal: $mealType, Food: $foodName');
      print('🔍 DEBUG: Item $i - Calories: $calories, Protein: $protein, Carbs: $carbs, Fats: $fats, Grams: $grams');

      // Track this date
      allDates.add(date);

      // Normalize meal type to standard format
      String normalizedMealType = 'Breakfast';
      if (mealType.toLowerCase().contains('lunch')) {
        normalizedMealType = 'Lunch';
      } else if (mealType.toLowerCase().contains('dinner')) {
        normalizedMealType = 'Dinner';
      }

      groupedItems.putIfAbsent(date, () => {'Breakfast': [], 'Lunch': [], 'Dinner': []});
      groupedItems[date]![normalizedMealType]!.add(MealItem(
        name: foodName,
        calories: calories,
        proteinGrams: protein,
        carbsGrams: carbs,
        fatGrams: fats,
        grams: grams,
        notes: (item['notes'] ?? '').toString(),
      ));
    }
    
    print('🔍 DEBUG: Found ${allDates.length} unique dates in items: ${allDates.toList()..sort()}');
    
    print('🔍 DEBUG: Grouped items into ${groupedItems.length} dates: ${groupedItems.keys.toList()}');

    // Determine full expected date range - use ALL available data sources
    List<String> expectedDates = [];
    try {
      // Strategy: Use the largest set of dates available
      final sd = data['start_date'] ?? extractedPlanData['start_date'];
      final ed = data['end_date'] ?? extractedPlanData['end_date'];
      final totalDays = data['total_days'] ?? extractedPlanData['total_days'];
      
      print('🔍 DEBUG: Date sources - Start: $sd, End: $ed, Total Days: $totalDays, Items dates: ${allDates.length}');
      
      // Calculate dates from start/end if available
      List<String> calculatedDates = [];
      if (sd != null && ed != null) {
        final start = DateTime.parse(sd.toString());
        final end = DateTime.parse(ed.toString());
        int days = end.difference(start).inDays;
        if (days <= 0) days = (totalDays is num) ? (totalDays as num).toInt() : 1;
        
        print('🔍 DEBUG: Calculated days from date range: $days');
        
        for (int i = 0; i < days; i++) {
          calculatedDates.add(_toDateOnly(start.add(Duration(days: i)).toIso8601String()));
        }
        } else if (totalDays != null) {
          // If no date range but we have total days, create dates based on total days
          final startDate = DateTime.now();
          final actualTotalDays = totalDays is num ? (totalDays as num).toInt() : 90; // Use actual total_days
          print('🔍 DEBUG: Using total_days: $actualTotalDays, starting from: $startDate');
          
          for (int i = 0; i < actualTotalDays; i++) {
            calculatedDates.add(_toDateOnly(startDate.add(Duration(days: i)).toIso8601String()));
          }
        }
      
      // Use the larger set of dates (calculated vs actual items)
      if (calculatedDates.length >= allDates.length) {
        expectedDates = calculatedDates;
        print('🔍 DEBUG: Using calculated dates: ${expectedDates.length} days');
      } else {
        expectedDates = allDates.toList()..sort();
        print('🔍 DEBUG: Using actual item dates: ${expectedDates.length} days');
      }
      
      print('🔍 DEBUG: Final expected dates count: ${expectedDates.length}');
      if (expectedDates.isNotEmpty) {
        print('🔍 DEBUG: First few expected dates: ${expectedDates.take(5).toList()}');
        print('🔍 DEBUG: Last few expected dates: ${expectedDates.length > 5 ? expectedDates.skip(expectedDates.length - 5).toList() : expectedDates}');
      }
    } catch (e) {
      print('⚠️ DEBUG: Error calculating expected dates: $e');
      // Fallback to actual dates from items
      expectedDates = allDates.toList()..sort();
    }

    // Collect all meal items for distribution across all days
    final allMealItems = <String, List<MealItem>>{
      'Breakfast': [],
      'Lunch': [],
      'Dinner': [],
    };
    
    // Collect all meal items from grouped data
    for (final dayData in groupedItems.values) {
      for (final mealType in ['Breakfast', 'Lunch', 'Dinner']) {
        final items = dayData[mealType] ?? <MealItem>[];
        allMealItems[mealType]!.addAll(items);
      }
    }
    
    print('🔍 DEBUG: Collected meal items - Breakfast: ${allMealItems['Breakfast']!.length}, Lunch: ${allMealItems['Lunch']!.length}, Dinner: ${allMealItems['Dinner']!.length}');
    
    // Build DayMeals with distributed meals across all expected days
    final List<String> sortedDates = expectedDates.isNotEmpty
        ? expectedDates
        : (groupedItems.keys.toList()..sort());

    print('🔍 DEBUG: Building days from ${sortedDates.length} dates');
    print('🔍 DEBUG: First 5 dates: ${sortedDates.take(5).toList()}');
    print('🔍 DEBUG: Last 5 dates: ${sortedDates.length > 5 ? sortedDates.skip(sortedDates.length - 5).toList() : sortedDates}');

    final days = <DayMeals>[];
    int dayNumber = 1;
    for (final date in sortedDates) {
      // Check if this date has actual meal data
      final dayData = groupedItems[date];
      List<MealItem> breakfastItems;
      List<MealItem> lunchItems;
      List<MealItem> dinnerItems;
      
      if (dayData != null) {
        // Use actual meal data for this date
        breakfastItems = List<MealItem>.from(dayData['Breakfast'] ?? <MealItem>[]);
        lunchItems = List<MealItem>.from(dayData['Lunch'] ?? <MealItem>[]);
        dinnerItems = List<MealItem>.from(dayData['Dinner'] ?? <MealItem>[]);
      } else {
        // Distribute meals using rotation strategy for missing dates
        breakfastItems = [];
        lunchItems = [];
        dinnerItems = [];
        
        if (allMealItems['Breakfast']!.isNotEmpty) {
          final breakfastIndex = (dayNumber - 1) % allMealItems['Breakfast']!.length;
          breakfastItems.add(allMealItems['Breakfast']![breakfastIndex]);
        }
        
        if (allMealItems['Lunch']!.isNotEmpty) {
          final lunchIndex = (dayNumber - 1) % allMealItems['Lunch']!.length;
          lunchItems.add(allMealItems['Lunch']![lunchIndex]);
        }
        
        if (allMealItems['Dinner']!.isNotEmpty) {
          final dinnerIndex = (dayNumber - 1) % allMealItems['Dinner']!.length;
          dinnerItems.add(allMealItems['Dinner']![dinnerIndex]);
        }
      }
      
      print('🔍 DEBUG: Day $dayNumber ($date) - Breakfast: ${breakfastItems.length}, Lunch: ${lunchItems.length}, Dinner: ${dinnerItems.length}');
      
      days.add(DayMeals(
        dayNumber: dayNumber++,
        breakfast: breakfastItems,
        lunch: lunchItems,
        dinner: dinnerItems,
      ));
    }
    
    print('🔍 DEBUG: Created ${days.length} total days (including empty days)');
    print('🔍 DEBUG: Total meal items processed: ${items.length}');
    print('🔍 DEBUG: Unique dates found: ${allDates.length}');
    print('🔍 DEBUG: Days with actual meal data: ${groupedItems.length}');

    if (days.isEmpty) {
      print('⚠️ DEBUG: No days created - returning empty plan');
      // Don't create dummy days - return empty plan
    }

    return MealPlan(
      id: planData['id']?.toString() ?? (data['id']?.toString() ?? 'generated'),
      title: planData['meal_category']?.toString() ?? (data['meal_category']?.toString() ?? 'AI Generated Plan'),
      category: (planData['meal_category'] ?? data['meal_category'] ?? '').toString().toLowerCase().contains('weight')
          ? PlanCategory.weightLoss
          : PlanCategory.muscleGain,
      note: 'AI Generated Meal Plan',
      days: days,
    );
  }

  /// Convert list of meal item maps to MealItem objects
  List<MealItem> _convertMealItems(List<dynamic> items) {
    return items.map((item) {
      final itemMap = item as Map<String, dynamic>;
      return MealItem(
        name: itemMap['name']?.toString() ?? 'Food',
        calories: (itemMap['calories'] is num) ? (itemMap['calories'] as num).toInt() : int.tryParse('${itemMap['calories']}') ?? 0,
        proteinGrams: (itemMap['protein'] is num) ? (itemMap['protein'] as num).toInt() : int.tryParse('${itemMap['protein']}') ?? 0,
        carbsGrams: (itemMap['carbs'] is num) ? (itemMap['carbs'] as num).toInt() : int.tryParse('${itemMap['carbs']}') ?? 0,
        fatGrams: (itemMap['fats'] is num) ? (itemMap['fats'] as num).toInt() : int.tryParse('${itemMap['fats']}') ?? 0,
        grams: (itemMap['grams'] is num) ? (itemMap['grams'] as num).toInt() : int.tryParse('${itemMap['grams']}') ?? 0,
        notes: (itemMap['notes'] ?? '').toString(),
      );
    }).toList();
  }

  Widget _buildGeneratedPlanCard(Map<String, dynamic> planData, Color color) {
    final planId = planData['id']?.toString() ?? '';
    final mealCategory = planData['meal_category']?.toString() ?? 'Meal Plan';
    final totalCalories = planData['total_calories']?.toString() ?? '0';
    final totalProteins = planData['total_proteins']?.toString() ?? '0';
    final totalFats = planData['total_fats']?.toString() ?? '0';
    final totalCarbs = planData['total_carbs']?.toString() ?? '0';
    final approvalStatus = planData['approval_status']?.toString() ?? 'PENDING';
    final startDate = planData['start_date']?.toString() ?? '';
    final endDate = planData['end_date']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mealCategory,
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete plan',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Plan'),
                        content: const Text('Are you sure you want to delete this plan?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await c.deleteGeneratedPlan(planId);
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan deleted')));
                        }
                      } catch (e) {
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: approvalStatus == 'APPROVED' ? Colors.green : 
                           approvalStatus == 'PENDING' ? Colors.orange : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    approvalStatus,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Plan ID: $planId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Total Days: ${planData['days']?.length ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            // Calculate per-day values
            Builder(builder: (context) {
              final totalDays = planData['days']?.length ?? 1; // Use actual days count
              final dailyCalories = (double.tryParse(totalCalories) ?? 0) / totalDays;
              final dailyProteins = (double.tryParse(totalProteins) ?? 0) / totalDays;
              final dailyFats = (double.tryParse(totalFats) ?? 0) / totalDays;
              final dailyCarbs = (double.tryParse(totalCarbs) ?? 0) / totalDays;
              
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Calories: ${dailyCalories.toStringAsFixed(0)}/day', style: const TextStyle(fontSize: 14))),
                      Expanded(child: Text('Protein: ${dailyProteins.toStringAsFixed(1)}g/day', style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Fats: ${dailyFats.toStringAsFixed(1)}g/day', style: const TextStyle(fontSize: 14))),
                      Expanded(child: Text('Carbs: ${dailyCarbs.toStringAsFixed(1)}g/day', style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      // Load plan details and show them
                      try {
                        print('🔍 View button clicked for plan ID: $planId');
                        final planDetails = await c.getGeneratedPlanDetails(planId);
                        print('🔍 Plan details received: ${planDetails.keys.toList()}');
                        
                        final convertedPlan = _convertToMealPlan(planDetails, planData);
                        print('🔍 Converted plan has ${convertedPlan.days.length} days');
                        
                        if (convertedPlan.days.isEmpty) {
                          print('⚠️ Plan has no days - showing error message');
                          if (mounted && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('This plan has no meal data. Please regenerate the plan.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                          return;
                        }
                        
                        if (mounted && context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AiPlanDetailsPage(
                                plan: convertedPlan,
                                color: color,
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        print('❌ Error loading plan details: $e');
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error loading plan: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('View'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // TODO: Implement edit plan
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Edit plan $planId')),
                      );
                    },
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                if (approvalStatus == 'PENDING')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: Implement send for approval
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Send plan $planId for approval')),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                      child: const Text('Send Plan'),
                    ),
                  )
                else if (approvalStatus == 'APPROVED')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: Implement start plan
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Start plan $planId')),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      child: const Text('Start Plan'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryColor, width: 1),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text('Generate Meal Plans', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textColor)),
                SizedBox(height: 4),
                Text('Personalized meal recommendations based on your goals and preferences.', style: TextStyle(color: AppTheme.textColor)),
              ]),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GenerateAiPlanPage()));
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: AppTheme.textColor),
              child: const Text('Generate Plan'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Show generated plans from backend
        Obx(() {
          final backendPlans = c.generatedPlans;
          return Column(
            children: [
              Row(
                children: [
                  Text('Generated Plans (${backendPlans.length})', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
                  const Spacer(),
                  IconButton(
                    onPressed: () async {
                      await c.loadGeneratedPlansFromBackend();
                    },
                    icon: const Icon(Icons.refresh, color: AppTheme.textColor),
                    tooltip: 'Refresh plans',
                  ),
                ],
              ),
              if (backendPlans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryColor),
                  ),
                  child: const Text('No generated plans found. Create one using the form above.', style: TextStyle(color: AppTheme.textColor)),
                )
              else
                ...backendPlans.map((planData) => _buildGeneratedPlanCard(planData, AppTheme.primaryColor)).toList(),
            ],
          );
        }),
              const SizedBox(height: 12),
      ]),
    );
  }

  void _showDeleteDialog(BuildContext context, MealPlan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Meal Plan'),
        content: Text('Are you sure you want to delete "${plan.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              c.deleteAiPlan();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Replaced modal with full screen page to avoid overflows

  Widget _dayCard(DayMeals day, Color color) {
    Widget mealTile(String title, List<MealItem> items) {
      final total = items.fold(0, (a, b) => a + b.calories);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (_, i) => Text(
                  items[i].name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('$total cal', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DAY ${day.dayNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Expanded(
            child: Column(children: [
              Expanded(child: mealTile('Breakfast', day.breakfast)),
              const SizedBox(height: 8),
              Expanded(child: mealTile('Lunch', day.lunch)),
              const SizedBox(height: 8),
              Expanded(child: mealTile('Dinner', day.dinner)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _aiCompactDayCard(DayMeals day, Color color) {
    final totalCalories = day.totalCalories;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'DAY ${day.dayNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _aiCompactMealRow('B', day.breakfast, color),
                  const SizedBox(height: 2),
                  _aiCompactMealRow('L', day.lunch, color),
                  const SizedBox(height: 2),
                  _aiCompactMealRow('D', day.dinner, color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$totalCalories cal',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCompactMealRow(String label, List<MealItem> items, Color color) {
    final total = items.fold(0, (a, b) => a + b.calories);
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$total',
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _aiDetailedDayCard(DayMeals day, Color color) {
    Widget meal(String title, List<MealItem> items) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    Text('${it.grams.toInt()}g  ${it.calories.toInt()}cal  ${it.proteinGrams.toInt()}g protein  ${it.fatGrams.toInt()}g fats  ${it.carbsGrams.toInt()}g carbs', style: const TextStyle(fontSize: 10)),
                  ]),
                );
              },
            ),
          ),
        ]),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DAY ${day.dayNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          // Remove Expanded to allow content to expand naturally
          Column(children: [
            meal('Breakfast', day.breakfast),
            const SizedBox(height: 4),
            meal('Lunch', day.lunch),
            const SizedBox(height: 4),
            meal('Dinner', day.dinner),
          ]),
        ]),
      ),
    );
  }
}


class AiPlanDetailsPage extends StatelessWidget {
  final MealPlan plan;
  final Color color;
  const AiPlanDetailsPage({super.key, required this.plan, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI Plan Distribution (${plan.days.length} Days)'),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: plan.days.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No meal data available',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This plan was created but contains no meal items.\nPlease regenerate the plan to get meal recommendations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final int cols = width ~/ 180 >= 2 ? width ~/ 180 : 2;
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // 2 columns for better space utilization
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.4, // Decreased aspect ratio for shorter boxes
                    ),
                    itemCount: plan.days.length,
                    itemBuilder: (_, i) => AiDetailedDayCard(day: plan.days[i], color: color),
                  );
                },
              ),
      ),
    );
  }
}

class AiDetailedDayCard extends StatelessWidget {
  final DayMeals day;
  final Color color;
  const AiDetailedDayCard({super.key, required this.day, required this.color});

  @override
  Widget build(BuildContext context) {
    Widget meal(String title, List<MealItem> items, IconData icon) {
      return Container(
            margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
          color: const Color(0xFFF58220), // Vibrant orange like Schedule Details
          borderRadius: BorderRadius.circular(6), // Small rounded corners
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
                children: [
            // Meal type header
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            if (items.isNotEmpty) ...[
              // Food item name
              Text(
                items.first.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const SizedBox(height: 1),
              // Nutritional details in Schedule Details format
              Text(
                '${items.first.calories} cal ${items.first.proteinGrams}g protein ${items.first.carbsGrams}g carbs ${items.first.fatGrams}g fats',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ] else ...[
              Text(
                'No items',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Day header - Light orange/yellowish text on dark background
          Text(
            'DAY ${day.dayNumber}',
            style: const TextStyle(
              color: Color(0xFFFFD700), // Light orange/yellowish text
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // Meals - Orange cards directly on dark background
          Column(
            children: [
              meal('Breakfast', day.breakfast, Icons.wb_sunny),
          const SizedBox(height: 4),
              meal('Lunch', day.lunch, Icons.wb_sunny_outlined),
            const SizedBox(height: 4),
              meal('Dinner', day.dinner, Icons.nights_stay),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2), // Semi-transparent white background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white, // White text
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
class GenerateAiPlanPage extends StatefulWidget {
  const GenerateAiPlanPage({super.key});

  @override
  State<GenerateAiPlanPage> createState() => _GenerateAiPlanPageState();
}

class _GenerateAiPlanPageState extends State<GenerateAiPlanPage> {
  final NutritionController c = Get.find<NutritionController>();
  final _formKey = GlobalKey<FormState>();
  PlanCategory? _category;
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _illness = TextEditingController();
  String? _gender;
  String? _country;
  final _goal = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Generate AI Plan', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.primaryColor.withOpacity(0.1), AppTheme.appBackgroundColor],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.restaurant_menu, color: AppTheme.textColor, size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'Personalized Meal Plan',
                          style: const TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tell us about yourself to create your perfect nutrition plan',
                          style: const TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Form Fields
                  _buildSectionTitle('Plan Type'),
                  _buildDropdownField<PlanCategory>(
              value: _category,
                    decoration: _buildInputDecoration('Select Plan Type', Icons.fitness_center),
              items: const [
                      DropdownMenuItem(value: PlanCategory.muscleGain, child: Text('💪 Muscle Gain')),
                      DropdownMenuItem(value: PlanCategory.weightLoss, child: Text('🔥 Weight Loss')),
              ],
              onChanged: (v) => setState(() => _category = v),
                    validator: (v) => v == null ? 'Please select a plan type' : null,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  _buildSectionTitle('Personal Information'),
                  _buildTextField(
                    controller: _age,
                    decoration: _buildInputDecoration('Age', Icons.cake),
                    keyboardType: TextInputType.number,
                    validator: (value) => value?.isEmpty == true ? 'Age is required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildDropdownField<String>(
              value: _gender,
                    decoration: _buildInputDecoration('Gender', Icons.person),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('👨 Male')),
                      DropdownMenuItem(value: 'Female', child: Text('👩 Female')),
                    ],
              onChanged: (v) => setState(() => _gender = v),
                    validator: (value) => value == null ? 'Gender is required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _height,
                    decoration: _buildInputDecoration('Height (cm)', Icons.height),
                    keyboardType: TextInputType.number,
                    validator: (value) => value?.isEmpty == true ? 'Height is required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _weight,
                    decoration: _buildInputDecoration('Weight (kg)', Icons.monitor_weight),
                    keyboardType: TextInputType.number,
                    validator: (value) => value?.isEmpty == true ? 'Weight is required' : null,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  _buildSectionTitle('Preferences'),
                  _buildDropdownField<String>(
              value: _country,
                    decoration: _buildInputDecoration('Country', Icons.public),
                    items: const [
                      DropdownMenuItem(value: 'Pakistan', child: Text('🇵🇰 Pakistan')),
                      DropdownMenuItem(value: 'USA', child: Text('🇺🇸 USA')),
                    ],
              onChanged: (v) => setState(() => _country = v),
                    validator: (value) => value == null ? 'Country is required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _goal,
                    decoration: _buildInputDecoration('Future Goal', Icons.flag),
                    maxLines: 2,
                    validator: (value) => value?.isEmpty == true ? 'Future goal is required' : null,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildTextField(
                    controller: _illness,
                    decoration: _buildInputDecoration('Any Illness (Optional)', Icons.medical_services),
                    maxLines: 2,
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Submit Button
            Obx(() {
              final loading = c.aiLoading.value;
                    return Container(
                width: double.infinity,
                      height: 56,
                        decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                child: ElevatedButton(
                        onPressed: loading ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: AppTheme.textColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: loading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.textColor),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  const Text('Creating Plan...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_awesome, size: 24),
                                  SizedBox(width: 8),
                                  const Text('Generate My Plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor)),
                                ],
                              ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textColor,
        ),
      ),
    );
  }
  
  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppTheme.textColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      filled: true,
      fillColor: AppTheme.cardBackgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
  
  Widget _buildTextField({
    required TextEditingController controller,
    required InputDecoration decoration,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: decoration,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontSize: 16),
    );
  }
  
  Widget _buildDropdownField<T>({
    required T? value,
    required InputDecoration decoration,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: decoration,
      items: items,
      onChanged: onChanged,
      validator: validator,
      style: const TextStyle(fontSize: 16, color: AppTheme.textColor),
      dropdownColor: AppTheme.cardBackgroundColor,
      borderRadius: BorderRadius.circular(12),
    );
  }
  
  void _submitForm() async {
                          if (_formKey.currentState?.validate() == true && _category != null) {
                            final form = {
                              'category': _category!,
                              'age': _age.text,
                              'height': _height.text,
                              'weight': _weight.text,
                              'illness': _illness.text,
                              'gender': _gender,
                              'country': _country,
                              'goal': _goal.text,
                            };
      
      // Debug: Print essential form data
      print('Form submission: age=${_age.text}, height=${_height.text}, weight=${_weight.text}');
      
                            // Close the form first, then start the AI generation
                            if (mounted) {
                            Navigator.pop(context);
                          }
                            
                            // Small delay to ensure navigation completes
                            await Future.delayed(const Duration(milliseconds: 100));
                            
      // Show progress dialog while generating
      if (mounted && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBackgroundColor,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Generating Your Meal Plan...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This may take up to 90 seconds',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }
      
      // Start AI generation after showing progress dialog
                            try {
                              await c.createGeneratedPlan(form: form);
        
        // Close progress dialog and show success
        if (mounted && context.mounted) {
          Navigator.of(context).pop(); // Close progress dialog
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Meal plan generated successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } on GeminiAIException catch (e) {
        print('❌ Gemini AI Exception in form: ${e.errorCode} - ${e.errorMessage}');
        
        // Close progress dialog
        if (mounted && context.mounted) {
          Navigator.of(context).pop(); // Close progress dialog
        }
        
        // Handle different error types
        if (e.isServiceUnavailable) {
          _showServiceUnavailableDialog(e.errorMessage, e.retryAfter);
        } else {
          _showErrorSnackBar(e.errorMessage);
        }
                            } catch (e) {
        print('❌ Error generating plan: $e');
        
        // Close progress dialog
        if (mounted && context.mounted) {
          Navigator.of(context).pop(); // Close progress dialog
        }
        
        _showErrorSnackBar('Network error. Please check your connection.');
      } finally {
        // Ensure progress dialog is always dismissed
        if (mounted && context.mounted) {
          try {
            Navigator.of(context).pop();
          } catch (_) {
            // Dialog might already be dismissed, ignore error
          }
        }
      }
    }
  }

  /// Show service unavailable dialog with retry information
  void _showServiceUnavailableDialog(String message, int? retryAfter) {
    final retryMinutes = retryAfter != null ? (retryAfter / 60).ceil() : 5;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Service Temporarily Unavailable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              'Please try again in $retryMinutes minutes.',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar with user-friendly message
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
                          }
  }
}
