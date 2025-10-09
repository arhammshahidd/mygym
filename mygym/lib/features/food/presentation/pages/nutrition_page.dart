import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../domain/models/meal_plan.dart';
import '../controllers/nutrition_controller.dart';

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
    final Color green = const Color(0xFF2E7D32);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Nutrition'),
        bottom: TabBar(
          controller: _tabController,
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
          _SchedulesTab(green: green),
          _AiTab(green: green),
        ],
            );
          } catch (e) {
            // Fallback UI if there's a rendering error
            return const Center(
              child: Text('Loading...'),
            );
          }
        },
      ),
    );
  }
}

class _SchedulesTab extends StatelessWidget {
  final Color green;
  const _SchedulesTab({required this.green});

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
                Expanded(child: _metricCard(title: 'Daily Calories', value: assigned?.totalCaloriesPerDay.toString() ?? '—', color: green)),
                const SizedBox(width: 12),
                Expanded(
                  child: _macroCard(assigned, green),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Assigned Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (assigned == null)
              const Text('No plan assigned. Start a plan from below.')
            else
              _assignedPlanCard(assigned, c, green),
              // Show Today's Meal only when plan is active
              if (assigned != null && c.mealPlanActive.value) ...[
                const SizedBox(height: 16),
                const Text("Today's Meal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _todayMealsSection(assigned, c, green),
              ],
            // Removed dummy available plans list per requirement
          ],
          ),
        ),
      );
    });
  }

  Widget _metricCard({required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _macroCard(MealPlan? plan, Color color) {
    final DayMeals? day = plan?.days.isNotEmpty == true ? plan!.days.first : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Macronutrients', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Proteins: ${day?.totalProtein ?? '—'}g'),
        Text('Carbs: ${day?.totalCarbs ?? '—'}g'),
        Text('Fat: ${day?.totalFat ?? '—'}g'),
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
              OutlinedButton(onPressed: () => _showSchedulePlanDetails(Get.context!, plan, color), child: const Text('View')),
            ])
          ],
        ),
      ]),
    );
  }

  Widget _assignedPlanCard(MealPlan plan, NutritionController c, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(child: Text(plan.title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800))),
            Text('${plan.days.length} DAYS', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(plan.note),
        const SizedBox(height: 6),
        Text('${plan.totalCaloriesPerDay} cal/day', style: const TextStyle(fontWeight: FontWeight.w600)),
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
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
              child: Text(isActive ? 'Stop Meal Plan' : 'Start Meal Plan'),
            );
          }),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _showSchedulePlanDetails(Get.context!, plan, color), child: const Text('View Details')),
        ])
      ]),
    );
  }

  Widget _todayMealsSection(MealPlan plan, NutritionController c, Color color) {
    final int index = (c.activeDayIndex.value >= 0 && c.activeDayIndex.value < plan.days.length) ? c.activeDayIndex.value : 0;
    final day = plan.days[index];
    return Column(children: [
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Breakfast', items: day.breakfast, color: color),
      const SizedBox(height: 12),
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Lunch', items: day.lunch, color: color),
      const SizedBox(height: 12),
      _todayMealCard(dayLabel: 'Day ${day.dayNumber}', title: 'Dinner', items: day.dinner, color: color),
    ]);
  }

  Widget _todayMealCard({required String dayLabel, required String title, required List<MealItem> items, required Color color}) {
    final totalCalories = items.fold(0, (a, b) => a + b.calories);
    final totalProteins = items.fold(0.0, (a, b) => a + b.proteinGrams);
    final totalCarbs = items.fold(0.0, (a, b) => a + b.carbsGrams);
    final totalFats = items.fold(0.0, (a, b) => a + b.fatGrams);
    
    return Container(
      decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dayLabel, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (items.isNotEmpty)
                  Text(items.first.name, style: const TextStyle(color: Colors.black87)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('Logged', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          ...items.skip(1).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(e.name, style: const TextStyle(color: Colors.black87)),
              )),
          const SizedBox(height: 8),
          // Nutritional information row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNutritionInfo('Calories', '$totalCalories', Colors.orange),
              _buildNutritionInfo('Proteins', '${totalProteins.toInt()}g', Colors.blue),
              _buildNutritionInfo('Carbs', '${totalCarbs.toInt()}g', Colors.green),
              _buildNutritionInfo('Fats', '${totalFats.toInt()}g', Colors.red),
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
          style: TextStyle(
            fontSize: 10,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  void _showSchedulePlanDetails(BuildContext context, MealPlan plan, Color color) {
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
                color: color,
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
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
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
                      itemBuilder: (_, i) => _scheduleDayDetailCard(plan.days[i], color),
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
          const SizedBox(height: 6),
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
  final Color green;
  const _AiTab({required this.green});

  @override
  State<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<_AiTab> {
  final NutritionController c = Get.find<NutritionController>();
  PlanCategory? _category;

  MealPlan _convertToMealPlan(Map<String, dynamic> planDetails, Map<String, dynamic> planData) {
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
    final items = (data['items'] is List)
        ? List<Map<String, dynamic>>.from(data['items'].map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)))
        : (planDetails['items'] is List)
            ? List<Map<String, dynamic>>.from((planDetails['items'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)))
            : <Map<String, dynamic>>[];

    // Group items by date and meal type (Breakfast/Lunch/Dinner)
    final Map<String, Map<String, List<MealItem>>> groupedItems = {};
    for (final item in items) {
      final date = _toDateOnly(item['date']);
      final mealType = (item['meal_type']?.toString() ?? 'Breakfast');
      final foodName = item['food_item_name']?.toString() ?? 'Food';
      final calories = (item['calories'] is num) ? (item['calories'] as num).toInt() : int.tryParse('${item['calories']}') ?? 0;
      final protein = (item['proteins'] is num) ? (item['proteins'] as num).toInt() : int.tryParse('${item['proteins'] ?? item['protein']}') ?? 0;
      final carbs = (item['carbs'] is num) ? (item['carbs'] as num).toInt() : int.tryParse('${item['carbs']}') ?? 0;
      final fats = (item['fats'] is num) ? (item['fats'] as num).toInt() : int.tryParse('${item['fats'] ?? item['fat']}') ?? 0;
      final grams = (item['grams'] is num) ? (item['grams'] as num).toInt() : int.tryParse('${item['grams']}') ?? 0;

      groupedItems.putIfAbsent(date, () => {'Breakfast': [], 'Lunch': [], 'Dinner': []});
      groupedItems[date]![mealType]!.add(MealItem(
        name: foodName,
        calories: calories,
        proteinGrams: protein,
        carbsGrams: carbs,
        fatGrams: fats,
        grams: grams,
      ));
    }

    // Determine full expected date range
    List<String> expectedDates = [];
    try {
      final sd = data['start_date'] ?? planData['start_date'];
      final ed = data['end_date'] ?? planData['end_date'];
      if (sd != null && ed != null) {
        final start = DateTime.parse(sd.toString());
        final end = DateTime.parse(ed.toString());
        int days = end.difference(start).inDays;
        if (days <= 0) days = (data['total_days'] is num) ? (data['total_days'] as num).toInt() : 1;
        for (int i = 0; i < days; i++) {
          expectedDates.add(_toDateOnly(start.add(Duration(days: i)).toIso8601String()));
        }
      }
    } catch (_) {}

    // Build DayMeals in chronological order, filling missing dates with empty meals
    final List<String> sortedDates = expectedDates.isNotEmpty
        ? expectedDates
        : (groupedItems.keys.toList()..sort());

    final days = <DayMeals>[];
    int dayNumber = 1;
    for (final date in sortedDates) {
      final dayData = groupedItems[date] ?? {'Breakfast': <MealItem>[], 'Lunch': <MealItem>[], 'Dinner': <MealItem>[]};
      days.add(DayMeals(
        dayNumber: dayNumber++,
        breakfast: List<MealItem>.from(dayData['Breakfast'] ?? <MealItem>[]),
        lunch: List<MealItem>.from(dayData['Lunch'] ?? <MealItem>[]),
        dinner: List<MealItem>.from(dayData['Dinner'] ?? <MealItem>[]),
      ));
    }

    if (days.isEmpty) {
      days.add(DayMeals(
        dayNumber: 1,
        breakfast: [],
        lunch: [],
        dinner: [],
      ));
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
            Text('Total Days: ${planData['total_days']?.toString() ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            // Calculate per-day values
            Builder(builder: (context) {
              final totalDays = int.tryParse(planData['total_days']?.toString() ?? '1') ?? 1;
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
                        final planDetails = await c.getGeneratedPlanDetails(planId);
                        if (mounted && context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AiPlanDetailsPage(
                                plan: _convertToMealPlan(planDetails, planData),
                                color: color,
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error loading plan: $e')),
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
          decoration: BoxDecoration(color: widget.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text('Generate Meal Plans', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Personalized meal recommendations based on your goals and preferences.'),
              ]),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenerateAiPlanPage(green: widget.green)));
              },
              style: ElevatedButton.styleFrom(backgroundColor: widget.green, foregroundColor: Colors.white),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.green)),
                  const Spacer(),
                  IconButton(
                    onPressed: () async {
                      await c.loadGeneratedPlansFromBackend();
                    },
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh plans',
                  ),
                ],
              ),
              if (backendPlans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Text('No generated plans found. Create one using the form above.'),
                )
              else
                ...backendPlans.map((planData) => _buildGeneratedPlanCard(planData, widget.green)).toList(),
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
          const SizedBox(height: 6),
          Expanded(
            child: Column(children: [
              Expanded(child: meal('Breakfast', day.breakfast)),
              const SizedBox(height: 6),
              Expanded(child: meal('Lunch', day.lunch)),
              const SizedBox(height: 6),
              Expanded(child: meal('Dinner', day.dinner)),
            ]),
          ),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final int cols = width ~/ 180 >= 2 ? width ~/ 180 : 2;
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols.clamp(2, 3),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.45, // Increased height to show more content
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
    Widget meal(String title, List<MealItem> items) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text('${it.grams.toInt()}g', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                        Expanded(
                          child: Text('${it.calories.toInt()}cal', style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text('${it.proteinGrams.toInt()}g protein', style: const TextStyle(fontSize: 10, color: Colors.blue)),
                        ),
                        Expanded(
                          child: Text('${it.fatGrams.toInt()}g fats', style: const TextStyle(fontSize: 10, color: Colors.red)),
                        ),
                        Expanded(
                          child: Text('${it.carbsGrams.toInt()}g carbs', style: const TextStyle(fontSize: 10, color: Colors.green)),
                        ),
                      ],
                    ),
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
          const SizedBox(height: 6),
          Expanded(
            child: Column(children: [
              Expanded(child: meal('Breakfast', day.breakfast)),
              const SizedBox(height: 6),
              Expanded(child: meal('Lunch', day.lunch)),
              const SizedBox(height: 6),
              Expanded(child: meal('Dinner', day.dinner)),
            ]),
          ),
        ]),
      ),
    );
  }
}
class GenerateAiPlanPage extends StatefulWidget {
  final Color green;
  const GenerateAiPlanPage({super.key, required this.green});

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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Generate AI Plan', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: widget.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [widget.green.withOpacity(0.1), Colors.white],
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
                      color: widget.green,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: widget.green.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.restaurant_menu, color: Colors.white, size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'Personalized Meal Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tell us about yourself to create your perfect nutrition plan',
                          style: TextStyle(
                            color: Colors.white70,
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
                            color: widget.green.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                child: ElevatedButton(
                        onPressed: loading ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.green,
                          foregroundColor: Colors.white,
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
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Creating Plan...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_awesome, size: 24),
                                  SizedBox(width: 8),
                                  Text('Generate My Plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: widget.green,
        ),
      ),
    );
  }
  
  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: widget.green),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.green, width: 2),
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
      fillColor: Colors.white,
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
      style: const TextStyle(fontSize: 16, color: Colors.black87),
      dropdownColor: Colors.white,
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
                            
                            // Start AI generation after navigation is complete
                            try {
                              await c.createGeneratedPlan(form: form);
                            } catch (e) {
                              print('Error generating plan: $e');
                              // Show error message if needed
                            }
                          }
  }
}
