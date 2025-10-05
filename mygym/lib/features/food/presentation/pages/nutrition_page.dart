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
  final NutritionController _c = Get.put(NutritionController(), permanent: true);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _SchedulesTab(green: green),
          _AiTab(green: green),
        ],
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
          await c.loadAssignedFromBackend();
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
    final total = items.fold(0, (a, b) => a + b.calories);
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('$total Cal', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ]),
      ),
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
                      '${items[i].calories} cal   ${items[i].proteinGrams}g protein   ${items[i].carbsGrams}g carbs',
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
        const SizedBox(height: 12),
        Obx(() {
          final plan = c.aiGeneratedPlan.value;
          if (plan == null) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: widget.green), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(child: Text(plan.title, style: TextStyle(color: widget.green, fontSize: 16, fontWeight: FontWeight.w800))),
                  IconButton(
                    onPressed: () => _showDeleteDialog(context, plan),
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(plan.note),
              const SizedBox(height: 4),
              Text('${plan.totalCaloriesPerDay} cal/day', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Obx(() {
                final status = c.aiStatus.value;
                final loading = c.aiLoading.value;
                final List<Widget> actions = [];
                if (status == AIPlanStatus.draft) {
                  actions.add(OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenerateAiPlanPage(green: widget.green)));
                    },
                    child: const Text('Edit'),
                  ));
                  actions.add(const SizedBox(width: 8));
                  actions.add(ElevatedButton(
                    onPressed: loading
                        ? null
                        : () {
                            // Open edit to confirm/send or directly send last payload if available
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => GenerateAiPlanPage(green: widget.green)));
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: widget.green, foregroundColor: Colors.white),
                    child: Text(loading ? 'Sending…' : 'Send for Approval'),
                  ));
                } else if (status == AIPlanStatus.pendingApproval) {
                  actions.add(OutlinedButton(onPressed: null, child: const Text('Pending Approval')));
                } else {
                  actions.add(ElevatedButton(
                    onPressed: () => c.setApprovedByPortal(),
                    style: ElevatedButton.styleFrom(backgroundColor: widget.green, foregroundColor: Colors.white),
                    child: const Text('Start Meal Plan'),
                  ));
                }
                actions.add(OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiPlanDetailsPage(plan: plan, color: widget.green),
                      ),
                    );
                  },
                  child: const Text('View Plan'),
                ));
                return Wrap(spacing: 8, runSpacing: 8, children: actions);
              })
              ,
              const SizedBox(height: 12),
              Obx(() {
                final p = c.lastAiPayload.value;
                if (p == null) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                  child: Text(
                    JsonEncoder.withIndent('  ').convert(p),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                );
              })
            ]),
          );
        })
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
                    Text('${it.grams} g   ${it.calories} cal   ${it.proteinGrams}g protein   ${it.fatGrams}g fats   ${it.carbsGrams}g carbs', style: const TextStyle(fontSize: 10)),
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
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.6,
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
                    Text('${it.grams} g   ${it.calories} cal   ${it.proteinGrams}g protein   ${it.fatGrams}g fats   ${it.carbsGrams}g carbs', style: const TextStyle(fontSize: 10)),
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
      appBar: AppBar(title: const Text('Generate AI Plan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            DropdownButtonFormField<PlanCategory>(
              decoration: const InputDecoration(labelText: 'Select Plan'),
              value: _category,
              items: const [
                DropdownMenuItem(value: PlanCategory.muscleGain, child: Text('Muscle Gain')),
                DropdownMenuItem(value: PlanCategory.weightLoss, child: Text('Weight Loss')),
              ],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            TextFormField(controller: _age, decoration: const InputDecoration(labelText: 'Age')),
            TextFormField(controller: _height, decoration: const InputDecoration(labelText: 'Height')),
            TextFormField(controller: _weight, decoration: const InputDecoration(labelText: 'Weight')),
            TextFormField(controller: _illness, decoration: const InputDecoration(labelText: 'Any Illness')),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Gender'),
              value: _gender,
              items: const [DropdownMenuItem(value: 'Male', child: Text('Male')), DropdownMenuItem(value: 'Female', child: Text('Female'))],
              onChanged: (v) => setState(() => _gender = v),
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Country'),
              value: _country,
              items: const [DropdownMenuItem(value: 'USA', child: Text('USA')), DropdownMenuItem(value: 'Pakistan', child: Text('Pakistan'))],
              onChanged: (v) => setState(() => _country = v),
            ),
            TextFormField(controller: _goal, decoration: const InputDecoration(labelText: 'Future Goal')),
            const SizedBox(height: 20),
            Obx(() {
              final loading = c.aiLoading.value;
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : () {
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
                            c.createGeneratedPlan(form: form);
                            Navigator.pop(context);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: widget.green, foregroundColor: Colors.white),
                  child: Text(loading ? 'Sending…' : 'Create Plan'),
                ),
              );
            })
          ]),
        ),
      ),
    );
  }
}
