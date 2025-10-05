import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import '../../domain/models/meal_plan.dart';
import '../../data/services/ai_nutrition_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/services/food_menu_service.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';

class NutritionController extends GetxController {
  final RxList<MealPlan> schedules = <MealPlan>[].obs;
  final Rx<MealPlan?> assignedPlan = Rx<MealPlan?>(null);
  final RxInt activeDayIndex = 0.obs;
  final RxBool mealPlanActive = false.obs;

  // AI state
  final Rx<MealPlan?> aiGeneratedPlan = Rx<MealPlan?>(null);
  final Rx<AIPlanStatus> aiStatus = AIPlanStatus.draft.obs;
  final RxBool aiLoading = false.obs;
  final Rx<Map<String, dynamic>?> lastAiPayload = Rx<Map<String, dynamic>?>(null);
  final AiNutritionService _ai = AiNutritionService();
  final FoodMenuService _food = FoodMenuService();

  @override
  void onInit() {
    super.onInit();
    _seedDemoData();
    loadAssignedFromBackend();
    _loadCachedAiPlan();
  }

  void _seedDemoData() {
    final sampleDay = DayMeals(
      dayNumber: 1,
      breakfast: const [
        MealItem(name: 'Oatmeal with berries', calories: 250, proteinGrams: 8, carbsGrams: 45, fatGrams: 4),
        MealItem(name: 'Greek Yogurt', calories: 170, proteinGrams: 15, carbsGrams: 12, fatGrams: 5),
      ],
      lunch: const [
        MealItem(name: 'Grilled Chicken', calories: 300, proteinGrams: 35, carbsGrams: 0, fatGrams: 12),
        MealItem(name: 'Brown Rice', calories: 220, proteinGrams: 5, carbsGrams: 45, fatGrams: 2),
      ],
      dinner: const [
        MealItem(name: 'Salmon', calories: 320, proteinGrams: 30, carbsGrams: 0, fatGrams: 20),
        MealItem(name: 'Mixed Salad', calories: 120, proteinGrams: 3, carbsGrams: 12, fatGrams: 7),
      ],
    );

    final weightLoss = MealPlan(
      id: 'wl7',
      title: 'Weight Loss Plan',
      category: PlanCategory.weightLoss,
      note: 'Balanced nutrition for healthy weight loss',
      days: List.generate(7, (i) => sampleDay.copyWith(dayNumber: i + 1)),
    );

    final massGain = MealPlan(
      id: 'mg30',
      title: 'Mass Gain Plan',
      category: PlanCategory.muscleGain,
      note: 'Perfect for Muscle Building and recovery',
      days: List.generate(30, (i) => sampleDay.copyWith(dayNumber: i + 1)),
    );

    schedules.assignAll([weightLoss, massGain]);
  }

  Future<void> loadAssignedFromBackend() async {
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final userId = profile.user?.id;
      final list = await _food.listAssignments(userId: userId);
      if (list.isEmpty) return;
      final latest = list.first; // assume latest or server sorted

      List<Map<String, dynamic>> parseMeal(dynamic raw) {
        if (raw == null) return [];
        try {
          final dynamic decoded = (raw is String) ? jsonDecode(raw) : raw;
          final List<Map<String, dynamic>> normalized = [];

          void addWithDay(Map<String, dynamic> item, int indexFallback) {
            final hasDay = item.containsKey('day') || item.containsKey('dayNumber') || item.containsKey('day_number');
            if (!hasDay) {
              item['day'] = indexFallback + 1; // infer sequential day if missing
            } else if (!item.containsKey('day') && item.containsKey('dayNumber')) {
              item['day'] = item['dayNumber'];
            } else if (!item.containsKey('day') && item.containsKey('day_number')) {
              item['day'] = item['day_number'];
            }
            normalized.add(Map<String, dynamic>.from(item));
          }

          if (decoded is List) {
            for (int i = 0; i < decoded.length; i++) {
              final e = decoded[i];
              if (e is Map) {
                addWithDay(Map<String, dynamic>.from(e), i);
              } else if (e is List) {
                for (final inner in e) {
                  if (inner is Map) addWithDay(Map<String, dynamic>.from(inner), i);
                }
              }
            }
            return normalized;
          }
          if (decoded is Map) {
            final listLike = decoded['items'] ?? decoded['list'] ?? decoded['data'];
            if (listLike is List) {
              for (int i = 0; i < listLike.length; i++) {
                final e = listLike[i];
                if (e is Map) addWithDay(Map<String, dynamic>.from(e), i);
              }
              return normalized;
            }
          }
          return [];
        } catch (_) {
          return [];
        }
      }

      final breakfast = parseMeal(latest['breakfast']);
      final lunch = parseMeal(latest['lunch']);
      final dinner = parseMeal(latest['dinner']);

      MealItem toItem(Map<String, dynamic> m) => MealItem(
            name: (m['food_item_name'] ?? m['name'] ?? m['item'] ?? 'Food').toString(),
            calories: (m['calories'] is num)
                ? (m['calories'] as num).round()
                : int.tryParse('${m['calories'] ?? m['kcal']}') ?? 0,
            proteinGrams: (m['protein'] is num)
                ? (m['protein'] as num).round()
                : int.tryParse('${m['protein'] ?? m['protein_g'] ?? m['proteins']}') ?? 0,
            carbsGrams: (m['carbs'] is num)
                ? (m['carbs'] as num).round()
                : int.tryParse('${m['carbs'] ?? m['carbohydrates'] ?? m['carbs_g']}') ?? 0,
            fatGrams: (m['fats'] is num)
                ? (m['fats'] as num).round()
                : int.tryParse('${m['fats'] ?? m['fat'] ?? m['fat_g']}') ?? 0,
            grams: (m['grams'] is num) ? (m['grams'] as num).round() : int.tryParse('${m['grams']}') ?? 0,
          );

      // Group by day
      final Map<int, DayMeals> dayMap = {};
      void addItems(List<Map<String, dynamic>> list, MealType type) {
        for (final m in list) {
          final int day = (m['day'] is num) ? (m['day'] as num).toInt() : int.tryParse('${m['day']}') ?? 1;
          final existing = dayMap[day];
          final item = toItem(m);
          if (existing == null) {
            dayMap[day] = DayMeals(
              dayNumber: day,
              breakfast: type == MealType.breakfast ? [item] : <MealItem>[],
              lunch: type == MealType.lunch ? [item] : <MealItem>[],
              dinner: type == MealType.dinner ? [item] : <MealItem>[],
            );
          } else {
            if (type == MealType.breakfast) {
              existing.breakfast.add(item);
            } else if (type == MealType.lunch) {
              existing.lunch.add(item);
            } else {
              existing.dinner.add(item);
            }
          }
        }
      }

      addItems(breakfast, MealType.breakfast);
      addItems(lunch, MealType.lunch);
      addItems(dinner, MealType.dinner);

      // Compute total days from assignment dates; fill missing days
      int totalDays = 0;
      try {
        final String? sd = latest['start_date']?.toString();
        final String? ed = latest['end_date']?.toString();
        if (sd != null && ed != null && sd.isNotEmpty && ed.isNotEmpty) {
          final start = DateTime.parse(sd);
          final end = DateTime.parse(ed);
          // Use exclusive end difference to avoid off-by-one; minimum 1 day span
          totalDays = end.difference(start).inDays;
          if (totalDays <= 0) totalDays = 1;
        }
      } catch (_) {
        totalDays = 0;
      }

      // Ensure day entries exist for the whole span
      if (totalDays > 0) {
        final existingDaysSorted = dayMap.keys.toList()..sort();
        // If no template days exist, keep empty placeholders
        for (int d = 1; d <= totalDays; d++) {
          if (!dayMap.containsKey(d)) {
            if (existingDaysSorted.isNotEmpty) {
              // Repeat templates in order and shuffle items deterministically per day
              final int templateIndex = (d - 1) % existingDaysSorted.length;
              final DayMeals template = dayMap[existingDaysSorted[templateIndex]]!;
              List<MealItem> shuffledCopy(List<MealItem> src, int seed) {
                final list = List<MealItem>.from(src);
                list.shuffle(Random(seed));
                return list;
              }
              dayMap[d] = DayMeals(
                dayNumber: d,
                breakfast: shuffledCopy(template.breakfast, d * 31 + 1),
                lunch: shuffledCopy(template.lunch, d * 31 + 2),
                dinner: shuffledCopy(template.dinner, d * 31 + 3),
              );
            } else {
              dayMap[d] = DayMeals(dayNumber: d, breakfast: <MealItem>[], lunch: <MealItem>[], dinner: <MealItem>[]);
            }
          }
        }
      }

      final days = dayMap.keys.toList()..sort();
      final builtDays = days.map((d) => dayMap[d]!).toList();

      final title = (latest['menu_plan_category']?.toString().trim().isNotEmpty == true)
          ? latest['menu_plan_category'].toString()
          : 'Assigned Nutrition Plan';

      final plan = MealPlan(
        id: 'assign_${latest['id']}',
        title: title,
        category: title.toLowerCase().contains('weight') ? PlanCategory.weightLoss : PlanCategory.muscleGain,
        note: latest['notes']?.toString() ?? '',
        days: builtDays,
      );

      assignedPlan.value = plan;
      activeDayIndex.value = 0;
    } catch (e) {
      // silent fail; page can still show local plans
    }
  }
  void assignPlan(MealPlan plan) {
    assignedPlan.value = plan;
    activeDayIndex.value = 0;
  }

  void startPlan() {
    if (assignedPlan.value != null) {
      activeDayIndex.value = 0;
      mealPlanActive.value = true;
    }
  }

  void stopPlan() {
    mealPlanActive.value = false;
  }

  Future<void> deleteAiPlan() async {
    try {
      // Clear local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ai_meal_plan_cache');
      
      // Clear UI state
      aiGeneratedPlan.value = null;
      aiStatus.value = AIPlanStatus.draft;
      lastAiPayload.value = null;
      
      // TODO: If plan has database ID, call delete API endpoint
      // final planId = aiGeneratedPlan.value?.id;
      // if (planId != null && planId != 'ai_generated') {
      //   await _ai.deletePlan(planId);
      // }
    } catch (e) {
      // Silent fail - UI is already cleared
    }
  }

  void setActiveDay(int index) {
    activeDayIndex.value = index;
  }

  // AI generation mock
  Future<void> generateAiPlan({required PlanCategory category}) async {
    aiLoading.value = true;
    try {
      // For now we keep a local preview using the seeded plan
      final base = schedules.firstWhereOrNull((p) => p.category == category) ?? schedules.first;
      aiGeneratedPlan.value = base;
      aiStatus.value = AIPlanStatus.draft;
      await _saveAiCache();
    } finally {
      aiLoading.value = false;
    }
  }

  Future<void> createGeneratedPlan({required Map<String, dynamic> form}) async {
    aiLoading.value = true;
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      
      // Compute default date range (30 days) if not provided
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final DateTime start = () {
        final s = form['start_date']?.toString();
        if (s != null && s.isNotEmpty) {
          try { return DateTime.parse(s); } catch (_) {}
        }
        return DateTime.now();
      }();
      final DateTime end = () {
        final e = form['end_date']?.toString();
        if (e != null && e.isNotEmpty) {
          try { return DateTime.parse(e); } catch (_) {}
        }
        return start.add(const Duration(days: 30));
      }();
      
      final payload = {
        'user_id': user?.id,
        'gym_id': 1, // Default gym
        'menu_plan': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        'meal_category': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        'age': int.tryParse(form['age']?.toString() ?? '') ?? 0,
        'height_cm': int.tryParse(form['height']?.toString() ?? '') ?? 0,
        'weight_kg': int.tryParse(form['weight']?.toString() ?? '') ?? 0,
        'illness': form['illness']?.toString() ?? '',
        'gender': form['gender']?.toString() ?? '',
        'country': form['country']?.toString() ?? '',
        'goal': form['goal']?.toString() ?? '',
        'start_date': fmt(start),
        'end_date': fmt(end),
      };
      lastAiPayload.value = payload;
      final res = await _ai.createGenerated(payload);
      
      // Parse returned plan data
      final data = Map<String, dynamic>.from(res['data'] ?? res);
      if (data['days'] is List) {
        final List daysRaw = data['days'];
        final List<DayMeals> days = [];
        for (int i = 0; i < daysRaw.length; i++) {
          final d = daysRaw[i];
          List<MealItem> _toItems(List list) => list
              .map((m) => MealItem(
                    name: (m['name'] ?? m['food_item_name'] ?? 'Food').toString(),
                    calories: (m['calories'] is num) ? (m['calories'] as num).round() : int.tryParse('${m['calories']}') ?? 0,
                    proteinGrams: (m['protein'] is num) ? (m['protein'] as num).round() : int.tryParse('${m['protein']}') ?? 0,
                    carbsGrams: (m['carbs'] is num) ? (m['carbs'] as num).round() : int.tryParse('${m['carbs']}') ?? 0,
                    fatGrams: (m['fats'] is num) ? (m['fats'] as num).round() : int.tryParse('${m['fats']}') ?? 0,
                    grams: (m['grams'] is num) ? (m['grams'] as num).round() : int.tryParse('${m['grams']}') ?? 0,
                  ))
              .toList();
          days.add(DayMeals(
            dayNumber: i + 1,
            breakfast: _toItems(List.from(d['breakfast'] ?? [])),
            lunch: _toItems(List.from(d['lunch'] ?? [])),
            dinner: _toItems(List.from(d['dinner'] ?? [])),
          ));
        }
        aiGeneratedPlan.value = MealPlan(
          id: res['id']?.toString() ?? 'ai_generated',
          title: (data['title'] ?? 'AI Meal Plan').toString(),
          category: categoryFromString((form['category']?.toString() ?? 'weightLoss')),
          note: (data['note'] ?? '').toString(),
          days: days,
        );
      }
      aiStatus.value = AIPlanStatus.draft;
      await _saveAiCache();
    } finally {
      aiLoading.value = false;
    }
  }

  PlanCategory categoryFromString(String value) {
    final v = value.toLowerCase();
    if (v.contains('muscle')) return PlanCategory.muscleGain;
    return PlanCategory.weightLoss;
  }

  Future<void> _saveAiCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plan = aiGeneratedPlan.value;
      final status = aiStatus.value.name;
      if (plan != null) {
        final json = {
          'id': plan.id,
          'title': plan.title,
          'category': plan.category.name,
          'note': plan.note,
          'days': plan.days
              .map((d) => {
                    'day': d.dayNumber,
                    'breakfast': d.breakfast
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                    'lunch': d.lunch
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                    'dinner': d.dinner
                        .map((m) => {
                              'name': m.name,
                              'calories': m.calories,
                              'protein': m.proteinGrams,
                              'carbs': m.carbsGrams,
                              'fats': m.fatGrams,
                            })
                        .toList(),
                  })
              .toList(),
        };
        await prefs.setString('ai_meal_plan_cache', jsonEncode({'plan': json, 'status': status}));
      }
    } catch (_) {}
  }

  Future<void> _loadCachedAiPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ai_meal_plan_cache');
      if (raw == null || raw.isEmpty) return;
      final parsed = jsonDecode(raw);
      final plan = parsed['plan'];
      final days = List<DayMeals>.from((plan['days'] as List).map((d) => DayMeals(
            dayNumber: d['day'] ?? 1,
            breakfast: List<MealItem>.from((d['breakfast'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
            lunch: List<MealItem>.from((d['lunch'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
            dinner: List<MealItem>.from((d['dinner'] as List).map((m) => MealItem(
                  name: m['name'],
                  calories: m['calories'],
                  proteinGrams: m['protein'],
                  carbsGrams: m['carbs'],
                  fatGrams: m['fats'],
                ))),
          )));
      aiGeneratedPlan.value = MealPlan(
        id: plan['id'],
        title: plan['title'],
        category: categoryFromString(plan['category'] ?? ''),
        note: plan['note'] ?? '',
        days: days,
      );
      final statusStr = (parsed['status'] ?? 'draft').toString();
      aiStatus.value = AIPlanStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => AIPlanStatus.draft,
      );
    } catch (_) {}
  }

  Future<void> sendAiPlanForApproval({required Map<String, dynamic> form}) async {
    aiLoading.value = true;
    try {
      final profile = Get.find<ProfileController>();
      await profile.loadUserProfileIfNeeded();
      final user = profile.user;
      int? _toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is double) return v.round();
        return int.tryParse(v.toString());
      }
      // Compute default date range (30 days) if not provided
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final DateTime start = () {
        final s = form['start_date']?.toString();
        if (s != null && s.isNotEmpty) {
          try { return DateTime.parse(s); } catch (_) {}
        }
        return DateTime.now();
      }();
      final DateTime end = () {
        final e = form['end_date']?.toString();
        if (e != null && e.isNotEmpty) {
          try { return DateTime.parse(e); } catch (_) {}
        }
        return start.add(const Duration(days: 30));
      }();
      final payload = {
        'type': 'nutrition',
        'menu_plan': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        // Send alternate key some backends expect
        'meal_category': (form['category'] is Enum) ? (form['category'] as Enum).name : (form['category']?.toString() ?? 'weightLoss'),
        'age': _toInt(form['age']) ?? 0,
        'height_cm': _toInt(form['height']) ?? 0,
        'weight_kg': _toInt(form['weight']) ?? 0,
        'illness': form['illness']?.toString() ?? '',
        'gender': form['gender']?.toString() ?? '',
        'country': form['country']?.toString() ?? '',
        'goal': form['goal']?.toString() ?? '',
        'user_id': user?.id,
        'start_date': fmt(start),
        'end_date': fmt(end),
        // Keep nested user for display/backward compatibility
        'user': {
          'id': user?.id,
          'name': user?.name,
          'phone': user?.phone,
        },
      };
      lastAiPayload.value = payload;
      if (AppConfig.useAiRequests) {
        await _ai.createRequest(payload);
      } else {
        await _ai.createRequest(payload); // send to backend queue by default
      }
      aiStatus.value = AIPlanStatus.pendingApproval;
    } catch (_) {
      rethrow;
    } finally {
      aiLoading.value = false;
    }
  }

  void setApprovedByPortal() {
    aiStatus.value = AIPlanStatus.approved;
    if (aiGeneratedPlan.value != null) {
      assignPlan(aiGeneratedPlan.value!);
    }
  }
}

extension on DayMeals {
  DayMeals copyWith({int? dayNumber, List<MealItem>? breakfast, List<MealItem>? lunch, List<MealItem>? dinner}) {
    return DayMeals(
      dayNumber: dayNumber ?? this.dayNumber,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      dinner: dinner ?? this.dinner,
    );
  }
}


