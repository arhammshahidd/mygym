import 'package:flutter/foundation.dart';

enum MealType { breakfast, lunch, dinner }

@immutable
class MealItem {
  final String name;
  final int calories;
  final int proteinGrams;
  final int carbsGrams;
  final int fatGrams;
  final int grams;
  final String notes;

  const MealItem({
    required this.name,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.grams = 0,
    this.notes = '',
  });
}

@immutable
class DayMeals {
  final int dayNumber;
  final List<MealItem> breakfast;
  final List<MealItem> lunch;
  final List<MealItem> dinner;

  const DayMeals({
    required this.dayNumber,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });

  int get totalCalories =>
      [...breakfast, ...lunch, ...dinner].fold(0, (a, b) => a + b.calories);

  int get totalProtein =>
      [...breakfast, ...lunch, ...dinner].fold(0, (a, b) => a + b.proteinGrams);

  int get totalCarbs =>
      [...breakfast, ...lunch, ...dinner].fold(0, (a, b) => a + b.carbsGrams);

  int get totalFat =>
      [...breakfast, ...lunch, ...dinner].fold(0, (a, b) => a + b.fatGrams);
}

enum PlanCategory { muscleGain, weightLoss }

@immutable
class MealPlan {
  final String id;
  final String title;
  final PlanCategory category;
  final String note;
  final List<DayMeals> days;

  const MealPlan({
    required this.id,
    required this.title,
    required this.category,
    required this.note,
    required this.days,
  });

  int get totalCaloriesPerDay => days.isEmpty ? 0 : days.first.totalCalories;
}

enum AIPlanStatus { draft, pendingApproval, approved }


