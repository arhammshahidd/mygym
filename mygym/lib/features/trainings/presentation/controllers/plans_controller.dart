import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../stats/presentation/controllers/stats_controller.dart';
import '../controllers/schedules_controller.dart';
import '../../data/services/manual_training_service.dart';
import '../../data/services/ai_training_service.dart';
import '../../data/services/training_approval_service.dart';
import '../../data/services/daily_training_service.dart';
import '../../../../shared/services/realtime_service.dart';
import '../../../auth/data/services/auth_service.dart';

class PlansController extends GetxController {
  final ManualTrainingService _manualService = ManualTrainingService();
  final AiTrainingService _aiService = AiTrainingService();
  final TrainingApprovalService _approvalService = TrainingApprovalService();
  final DailyTrainingService _dailyTrainingService = DailyTrainingService();
  final RealtimeService _realtime = RealtimeService();
  final AuthService _authService = AuthService();
  final ProfileController _profileController = Get.find<ProfileController>();
  bool _socketSubscribed = false;

  // Plans-specific data
  final RxBool isLoading = false.obs;
  final RxBool hasLoadedOnce = false.obs;
  final RxList<Map<String, dynamic>> manualPlans = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> aiGeneratedPlans = <Map<String, dynamic>>[].obs;
  
  // Plans-specific state management
  final RxMap<int, bool> _startedPlans = <int, bool>{}.obs;
  final Rx<Map<String, dynamic>?> _activePlan = Rx<Map<String, dynamic>?>(null);
  final Map<String, bool> _completedWorkouts = {};
  final Map<String, int> _currentDay = {};
  
  // Plans-specific approval tracking
  final RxMap<int, String> planApprovalStatus = <int, String>{}.obs;
  final RxMap<int, int> planToApprovalId = <int, int>{}.obs;
  final RxMap<int, bool> planModifiedSinceApproval = <int, bool>{}.obs;
  bool _approvalCacheLoaded = false;

  @override
  void onInit() {
    super.onInit();
    _loadStartedPlansFromCache();
    _loadActivePlanSnapshot();
    _loadModificationFlags();
    _subscribeToRealtimeUpdates();
  }

  @override
  void onClose() {
    _realtime.disconnect();
    super.onClose();
  }

  Future<void> _subscribeToRealtimeUpdates() async {
    if (_socketSubscribed) return;
    
    try {
      _realtime.connectApprovals();
      _realtime.events.listen((data) {
        print('📡 Plans - Real-time update: $data');
        // Handle real-time updates for plans
        _handleRealtimeUpdate(data);
      });
      _socketSubscribed = true;
      print('✅ Plans - Connected to real-time updates');
    } catch (e) {
      print('❌ Plans - Failed to connect to real-time updates: $e');
    }
  }

  void _handleRealtimeUpdate(Map<String, dynamic> data) {
    // Handle real-time updates specific to plans
    final planId = data['plan_id'];
    final status = data['status'];
    
    if (planId != null && status != null) {
      // Update plan approval status
      planApprovalStatus[int.tryParse(planId.toString()) ?? 0] = status.toLowerCase();
    }
  }

  Future<void> loadPlansData() async {
    try {
      print('🚀 Plans - Starting loadPlansData...');
      isLoading.value = true;
      
      await _loadApprovalIdCacheIfNeeded();
      await _cleanupInvalidApprovalMappings();
      
      // Ensure profile is loaded
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      print('👤 Plans - User ID: $userId');
      
      if (userId == null) {
        print('❌ Plans - User ID is null! Cannot fetch plans.');
        return;
      }
      
      print('👤 Plans - User profile loaded successfully');
      print('👤 Plans - User name: ${_profileController.user?.name}');
      print('👤 Plans - User email: ${_profileController.user?.email}');
      
      // Test API connectivity
      await _manualService.testApiConnectivity();
      
      // Fetch manual training plans (Plans-specific)
      try {
        print('📝 Plans - Fetching manual training plans...');
        print('📝 Plans - API Endpoint: /api/appManualTraining/');
        final manualRes = await _manualService.listPlans();
        print('📝 Plans - Manual plans result: ${manualRes.length} items');
        
        if (manualRes.isEmpty) {
          print('⚠️ Plans - No manual plans returned from API!');
          print('⚠️ Plans - This could mean:');
          print('⚠️ Plans - 1. No manual plans exist in the database');
          print('⚠️ Plans - 2. API endpoint is incorrect');
          print('⚠️ Plans - 3. User has no manual plans');
          print('⚠️ Plans - 4. Backend is returning empty list');
          
          // Try alternative endpoint as fallback
          print('🔄 Plans - Trying alternative endpoint: /api/trainingPlans/');
          try {
            final dio = await _manualService.getAuthedDio();
            final altRes = await dio.get('/api/trainingPlans/');
            print('🔄 Plans - Alternative endpoint response: ${altRes.statusCode}');
            print('🔄 Plans - Alternative endpoint data: ${altRes.data}');
            
            if (altRes.statusCode == 200) {
              final altData = altRes.data;
              List<dynamic> altPlans = [];
              
              if (altData is List) {
                altPlans = altData;
              } else if (altData is Map && altData['data'] is List) {
                altPlans = altData['data'];
              }
              
              print('🔄 Plans - Alternative endpoint returned ${altPlans.length} plans');
              if (altPlans.isNotEmpty) {
                print('🔄 Plans - First alternative plan: ${altPlans.first}');
                // Use alternative data if manual endpoint is empty
                manualRes.addAll(altPlans);
                print('🔄 Plans - Added ${altPlans.length} plans from alternative endpoint');
              }
            }
          } catch (e) {
            print('⚠️ Plans - Alternative endpoint failed: $e');
          }
        }
        
        // DEBUG: Print all manual plan data to understand structure
        print('🔍 DEBUG: Total manual plans received: ${manualRes.length}');
        for (int i = 0; i < manualRes.length; i++) {
          final plan = manualRes[i];
          print('🔍 DEBUG Manual Plan $i:');
          print('🔍   - Keys: ${plan.keys.toList()}');
          print('🔍   - Full Data: $plan');
          print('🔍   - ID: ${plan['id']}');
          print('🔍   - Name: ${plan['name']}');
          print('🔍   - Plan Category: ${plan['exercise_plan_category']}');
          print('🔍   - Plan Type: ${plan['plan_type']}');
          print('🔍   - Created By: ${plan['created_by']}');
          print('🔍   - User ID: ${plan['user_id']}');
          print('🔍   - Assigned By: ${plan['assigned_by']}');
          print('🔍   - Assignment ID: ${plan['assignment_id']}');
          print('🔍   - Web Plan ID: ${plan['web_plan_id']}');
        }
        
        // Filter to show ONLY manual plans created by the user (not assigned plans)
        final uniquePlans = <Map<String, dynamic>>[];
        final seenIds = <int>{};
        
        for (final plan in manualRes) {
          final planMap = Map<String, dynamic>.from(plan);
          final planId = int.tryParse(planMap['id']?.toString() ?? '');
          final planType = planMap['plan_type']?.toString().toLowerCase();
          final createdBy = planMap['created_by'];
          final assignedBy = planMap['assigned_by'];
          final assignmentId = planMap['assignment_id'];
          final webPlanId = planMap['web_plan_id'];
          
          // Check if this is an assigned plan (exclude these)
          final isAssignedPlan = planType == 'assigned' || 
                                assignedBy != null || 
                                assignmentId != null ||
                                webPlanId != null ||
                                planType == 'ai_generated' ||
                                planType == 'daily' ||
                                planType == 'schedule';
          
          // Include manual plans created by the user, including approved ones
          // Also include plans that don't have explicit plan_type but are created by user
          // Be more permissive to avoid filtering out valid plans
          // Handle cases where createdBy might be null but plan is still valid
          final isManualPlan = (planType == 'manual' || planType == null || planType == '') && 
                              (createdBy == null || createdBy == userId); // Allow null createdBy or match userId
                              // Removed strict checks for assignedBy, assignmentId, webPlanId
                              // as these might be set by the backend during updates
          
          print('🔍 Plans - Plan ${planMap['id']}:');
          print('🔍   - plan_type: $planType');
          print('🔍   - created_by: $createdBy (type: ${createdBy.runtimeType})');
          print('🔍   - userId: $userId (type: ${userId.runtimeType})');
          print('🔍   - assigned_by: $assignedBy');
          print('🔍   - assignment_id: $assignmentId');
          print('🔍   - web_plan_id: $webPlanId');
          print('🔍   - isManualPlan: $isManualPlan');
          print('🔍   - isAssignedPlan: $isAssignedPlan');
          print('🔍   - Will include: ${isManualPlan && !isAssignedPlan}');
          print('🔍   - createdBy == userId: ${createdBy == userId}');
          print('🔍   - createdBy == null: ${createdBy == null}');
          print('🔍   - (createdBy == null || createdBy == userId): ${createdBy == null || createdBy == userId}');
          
          if (!isManualPlan) {
            print('❌ REJECTED: Not identified as manual plan (plan_type: $planType, created_by: $createdBy)');
          }
          if (isAssignedPlan) {
            print('❌ REJECTED: Identified as assigned plan');
          }
          
          if (planId != null && !seenIds.contains(planId) && isManualPlan && !isAssignedPlan) {
            seenIds.add(planId);
            uniquePlans.add(planMap);
            print('📝 Plans - Added manual plan ID: $planId');
          } else if (planId != null && seenIds.contains(planId)) {
            print('⚠️ Plans - Skipped duplicate plan ID: $planId');
          } else if (isAssignedPlan) {
            print('⚠️ Plans - Skipped assigned plan ID: $planId (belongs in Schedules tab)');
          } else {
            print('⚠️ Plans - Skipped plan with invalid ID: ${planMap['id']}');
          }
        }
        
        if (!isClosed) manualPlans.assignAll(uniquePlans);
        print('✅ Plans - Manual plans list updated: ${manualPlans.length} unique manual items (removed ${manualRes.length - uniquePlans.length} assigned/duplicate plans)');
        
        // TEMPORARY DEBUG: If no plans found, show ALL plans for debugging
        if (uniquePlans.isEmpty && manualRes.isNotEmpty) {
          print('🔍 DEBUG: No plans passed filtering, showing ALL plans for debugging:');
          final allPlans = manualRes.map((e) => Map<String, dynamic>.from(e)).toList();
          if (!isClosed) manualPlans.assignAll(allPlans);
          print('🔍 DEBUG: Temporarily showing ${allPlans.length} plans without filtering');
        }
      } catch (e) {
        print('⚠️ Plans - Failed to load manual plans: $e');
        if (!isClosed) manualPlans.clear();
      }

      // Fetch AI generated plans (Plans-specific)
      try {
        print('🤖 Plans - Fetching AI generated plans...');
        final aiRes = await _aiService.listGenerated(userId: userId);
        print('🤖 Plans - AI plans result: ${aiRes.length} items');
        
        if (!isClosed) aiGeneratedPlans.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
        print('✅ Plans - AI plans list updated: ${aiGeneratedPlans.length} items');
      } catch (e) {
        print('⚠️ Plans - Failed to load AI plans: $e');
        if (!isClosed) aiGeneratedPlans.clear();
      }
      
      // Refresh approval status from backend for all plans
      await refreshApprovalStatusFromBackend();
      
    } catch (e) {
      print('❌ Plans - Error loading data: $e');
    } finally {
      isLoading.value = false;
      hasLoadedOnce.value = true;
      print('🏁 Plans - Load completed');
    }
  }

  // Plans-specific methods
  Future<Map<String, dynamic>> getManualPlan(int id) async {
    return await _manualService.getPlan(id);
  }

  Future<Map<String, dynamic>> getAiGeneratedPlan(int id) async {
    return await _aiService.getGenerated(id);
  }

  Future<Map<String, dynamic>> getApproval(int approvalId) async {
    final data = await _approvalService.getApproval(approvalId);
    return Map<String, dynamic>.from(data);
  }

  /// Send AI generated plan for approval
  Future<Map<String, dynamic>> sendAiPlanForApproval(Map<String, dynamic> plan) async {
    try {
      print('🔍 PlansController - Sending AI plan for approval: ${plan['id']}');
      print('🔍 PlansController - Plan data keys: ${plan.keys.toList()}');
      print('🔍 PlansController - Plan data: $plan');
      
      // TEMPORARY DEBUG: Check if this is actually an AI plan
      final planType = plan['plan_type']?.toString().toLowerCase();
      final hasAiIndicators = plan.containsKey('exercise_plan_category') || 
                              plan.containsKey('user_level');
      
      print('🔍 PlansController - Plan type: $planType');
      print('🔍 PlansController - Has AI indicators: $hasAiIndicators');
      print('🔍 PlansController - exercise_plan_category: ${plan['exercise_plan_category']}');
      print('🔍 PlansController - user_level: ${plan['user_level']}');
      
      // TEMPORARY DEBUG: If this doesn't look like an AI plan, throw an error
      if (planType != 'ai_generated' && !hasAiIndicators) {
        throw Exception('This plan does not appear to be an AI-generated plan. Plan type: $planType, AI indicators: $hasAiIndicators');
      }
      
      // First, fetch the complete plan details with items
      final planId = int.tryParse(plan['id']?.toString() ?? '');
      if (planId == null) {
        throw Exception('Invalid plan ID');
      }
      
      print('🔍 PlansController - Fetching complete plan details for ID: $planId');
      final completePlan = await _aiService.getGenerated(planId);
      print('🔍 PlansController - Complete plan data: ${completePlan.keys.toList()}');
      
      // Check if plan has items
      // Normalize items: ensure weight_min_kg/weight_max_kg present
      final items = (completePlan['items'] as List? ?? []).map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        // map possible alternative keys
        m['weight_min_kg'] = m['weight_min_kg'] ?? m['weight_min'] ?? m['min_weight'] ?? m['min_weight_kg'];
        m['weight_max_kg'] = m['weight_max_kg'] ?? m['weight_max'] ?? m['max_weight'] ?? m['max_weight_kg'];
        return m;
      }).toList();
      // write back normalized items into plan data copy we'll send
      final normalizedPlan = Map<String, dynamic>.from(completePlan);
      normalizedPlan['items'] = items;
      print('🔍 PlansController - Plan has ${items.length} items');
      
      if (items.isEmpty) {
        throw Exception('Cannot send plan for approval: Plan has no workout items. Please regenerate the plan with workout items.');
      }
      
      // Derive category/workout_name
      final String category = (normalizedPlan['exercise_plan_category']?.toString() ??
          normalizedPlan['category']?.toString() ??
          plan['exercise_plan_category']?.toString() ??
          plan['workout_name']?.toString() ??
          'AI Generated');

      // Aggregate metrics expected by backend
      final int totalMinutes = items.fold<int>(0, (sum, it) => sum + (int.tryParse(it['minutes']?.toString() ?? it['training_minutes']?.toString() ?? '0') ?? 0));
      final int totalExercises = items.length;
      int totalDays = 0;
      try {
        if (normalizedPlan['start_date'] != null && normalizedPlan['end_date'] != null) {
          final s = DateTime.tryParse(normalizedPlan['start_date'].toString());
          final e = DateTime.tryParse(normalizedPlan['end_date'].toString());
          if (s != null && e != null) totalDays = e.difference(s).inDays + 1;
        }
      } catch (_) {}
      if (totalDays <= 0) {
        totalDays = int.tryParse(normalizedPlan['total_days']?.toString() ?? '0') ?? 0;
      }

      // Generate daily_plans based on pair rule and rotation
      final DateTime? startDate = normalizedPlan['start_date'] != null
          ? DateTime.tryParse(normalizedPlan['start_date'].toString())
          : null;
      if (totalDays <= 0) totalDays = 30; // fallback
      final List<Map<String, dynamic>> dailyPlans = _generateDailyPlans(items, startDate: startDate, totalDays: totalDays);
      normalizedPlan['daily_plans'] = dailyPlans;

      final payload = {
        'plan_id': plan['id'],
        'plan_type': 'ai_generated',
        'user_id': userId,
        'user_name': Get.find<ProfileController>().user?.name ?? 'Unknown User',
        'user_phone': Get.find<ProfileController>().user?.phone ?? '',
        'workout_name': category, // primary display name
        'category': category, // explicit category field required by backend
        'start_date': normalizedPlan['start_date'],
        'end_date': normalizedPlan['end_date'],
        // Common aggregates/fields for backend denormalization
        'minutes': totalMinutes,
        'total_exercises': totalExercises,
        'total_days': totalDays,
        'user_level': normalizedPlan['user_level'] ?? plan['user_level'],
        // Mirror arrays at root level for convenience
        'items': items,
        if (normalizedPlan['exercises_details'] != null) 'exercises_details': normalizedPlan['exercises_details'],
        'daily_plans': dailyPlans,
        'plan_data': normalizedPlan, // Use normalized plan data with items
        'requested_at': DateTime.now().toIso8601String(),
      };
      
      print('🔍 PlansController - AI plan approval payload:');
      print('🔍   - plan_id: ${payload['plan_id']}');
      print('🔍   - plan_type: ${payload['plan_type']}');
      print('🔍   - user_id: ${payload['user_id']}');
      print('🔍   - user_name: ${payload['user_name']}');
      print('🔍   - user_phone: ${payload['user_phone']}');
      print('🔍   - workout_name: ${payload['workout_name']}');
      print('🔍   - category: ${payload['category']}');
      print('🔍   - start_date: ${payload['start_date']}');
      print('🔍   - end_date: ${payload['end_date']}');
      print('🔍   - minutes: ${payload['minutes']}');
      print('🔍   - total_exercises: ${payload['total_exercises']}');
      print('🔍   - total_days: ${payload['total_days']}');
      print('🔍   - requested_at: ${payload['requested_at']}');
      print('🔍   - plan_data keys: ${normalizedPlan.keys.toList()}');
      print('🔍   - daily_plans days: ${dailyPlans.length}');
      
      final result = await _approvalService.sendForApproval(
        source: 'ai',
        payload: payload,
      );
      
      print('✅ PlansController - AI plan sent for approval successfully');
      print('🔍 PlansController - Approval result: $result');
      print('🔍 PlansController - Result keys: ${result.keys.toList()}');
      print('🔍 PlansController - Result ID: ${result['id']}');
      print('🔍 PlansController - Result ID type: ${result['id'].runtimeType}');
      
      // Update the plan's approval status locally
      if (planId != null && result['id'] != null) {
        final approvalId = result['id'];
        print('🔍 PlansController - Storing approval ID $approvalId for plan $planId');
        planToApprovalId[planId] = approvalId;
        planApprovalStatus[planId] = 'pending'; // Set initial status to pending
        await _persistApprovalIdCache();
        print('✅ PlansController - Approval ID stored successfully');
        
        // Force UI refresh to show "Pending" status
        if (!isClosed) update();
      } else {
        print('⚠️ PlansController - Failed to store approval ID - planId: $planId, resultId: ${result['id']}');
      }
      
      return result;
    } catch (e) {
      print('❌ PlansController - Failed to send AI plan for approval: $e');
      rethrow;
    }
  }

  /// Send manual plan for approval
  Future<Map<String, dynamic>> sendManualPlanForApproval(Map<String, dynamic> plan) async {
    try {
      print('🔍 PlansController - Sending manual plan for approval (or resending)...');
      print('🔍 PlansController - Plan data keys: ${plan.keys.toList()}');
      print('🔍 PlansController - Plan data: $plan');
      
      // First, fetch the complete plan details with items
      final planId = int.tryParse(plan['id']?.toString() ?? '');
      if (planId == null) {
        throw Exception('Invalid plan ID');
      }
      
      // DEBUG: Check plan type indicators before fetching
      print('🔍 PlansController - Plan type indicators:');
      print('🔍   - plan_type: ${plan['plan_type']}');
      print('🔍   - has request_id: ${plan.containsKey('request_id')}');
      print('🔍   - has ai_generated: ${plan.containsKey('ai_generated')}');
      print('🔍   - has created_by: ${plan.containsKey('created_by')}');
      print('🔍   - has assigned_by: ${plan['assigned_by']}');
      print('🔍   - has assignment_id: ${plan['assignment_id']}');
      print('🔍   - has web_plan_id: ${plan['web_plan_id']}');
      
      print('🔍 PlansController - Fetching complete manual plan details for ID: $planId');
      print('🔍 PlansController - Using ManualTrainingService.getPlan() - NOT AI service');
      final completePlan = await _manualService.getPlan(planId);
      print('🔍 PlansController - Complete manual plan: $completePlan');
      
      // Normalize items and exercises_details
      final List<Map<String, dynamic>> items = (completePlan['items'] as List? ?? [])
          .map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['weight_min_kg'] = m['weight_min_kg'] ?? m['weight_min'] ?? m['min_weight'] ?? m['min_weight_kg'];
        m['weight_max_kg'] = m['weight_max_kg'] ?? m['weight_max'] ?? m['max_weight'] ?? m['max_weight_kg'];
        return m;
      }).toList();
      List<Map<String, dynamic>> exercisesDetails = [];
      if (completePlan['exercises_details'] is List) {
        exercisesDetails = List<Map<String, dynamic>>.from(
            (completePlan['exercises_details'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (completePlan['exercises_details'] is String) {
        try {
          final parsed = jsonDecode(completePlan['exercises_details'] as String) as List<dynamic>;
          exercisesDetails = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }
      
      print('🔍 PlansController - Manual plan has ${items.length} items, ${exercisesDetails.length} exercises_details');
      
      if (items.isEmpty) {
        throw Exception('Cannot send plan for approval: Plan has no workout items. Please add workout items to the plan.');
      }
      
      // Aggregates and metadata
      final String category = (completePlan['exercise_plan_category']?.toString() ??
          plan['exercise_plan_category']?.toString() ?? plan['name']?.toString() ?? 'Manual Plan');
      final int minutes = items.fold<int>(0, (sum, it) => sum + (int.tryParse(it['minutes']?.toString() ?? it['training_minutes']?.toString() ?? '0') ?? 0));
      final int totalExercises = items.length;
      int totalDays = 0;
      try {
        if (completePlan['start_date'] != null && completePlan['end_date'] != null) {
          final s = DateTime.tryParse(completePlan['start_date'].toString());
          final e = DateTime.tryParse(completePlan['end_date'].toString());
          if (s != null && e != null) totalDays = e.difference(s).inDays + 1;
        }
      } catch (_) {}
      if (totalDays <= 0) totalDays = int.tryParse(completePlan['total_days']?.toString() ?? '0') ?? 0;

      final normalizedPlan = Map<String, dynamic>.from(completePlan);
      normalizedPlan['items'] = items;
      if (exercisesDetails.isNotEmpty) {
        normalizedPlan['exercises_details'] = exercisesDetails;
      }
      
      // Ensure normalizedPlan doesn't contain null values that could cause issues
      normalizedPlan.removeWhere((key, value) => value == null);

      // Generate daily_plans for manual too, using the same rule
      final DateTime? startDate = normalizedPlan['start_date'] != null
          ? DateTime.tryParse(normalizedPlan['start_date'].toString())
          : null;
      if (totalDays <= 0) totalDays = 30; // fallback
      final List<Map<String, dynamic>> dailyPlans = _generateDailyPlans(items, startDate: startDate, totalDays: totalDays);
      normalizedPlan['daily_plans'] = dailyPlans;

      // Ensure all required fields are not null
      final String safePlanId = plan['id']?.toString() ?? '';
      final int safeUserId = userId ?? 0;
      
      // Ensure profile is loaded before getting user data
      final profileController = Get.find<ProfileController>();
      if (profileController.user == null) {
        await profileController.loadUserProfileIfNeeded();
      }
      
      final String safeUserName = profileController.user?.name ?? 'Unknown User';
      final String safeUserPhone = profileController.user?.phone ?? '';
      
      print('🔍 PlansController - User data for approval:');
      print('🔍   - User ID: $safeUserId');
      print('🔍   - User Name: $safeUserName');
      print('🔍   - User Phone: $safeUserPhone');
      print('🔍   - Profile loaded: ${profileController.user != null}');
      final String safeCategory = category.isNotEmpty ? category : 'Manual Plan';
      final String safeStartDate = completePlan['start_date']?.toString() ?? DateTime.now().toIso8601String().split('T').first;
      final String safeEndDate = completePlan['end_date']?.toString() ?? DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first;
      final int safeMinutes = minutes;
      final int safeTotalExercises = totalExercises;
      final int safeTotalDays = totalDays;
      final String safeUserLevel = completePlan['user_level']?.toString() ?? plan['user_level']?.toString() ?? 'Beginner';
      final List<Map<String, dynamic>> safeItems = items.isNotEmpty ? items : <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> safeDailyPlans = dailyPlans.isNotEmpty ? dailyPlans : <Map<String, dynamic>>[];
      
      final payload = {
        'plan_id': safePlanId,
        'plan_type': 'manual',
        'user_id': safeUserId,
        'user_name': safeUserName,
        'user_phone': safeUserPhone,
        'workout_name': safeCategory,
        'category': safeCategory,
        'start_date': safeStartDate,
        'end_date': safeEndDate,
        'minutes': safeMinutes,
        'total_exercises': safeTotalExercises,
        'total_days': safeTotalDays,
        'user_level': safeUserLevel,
        'items': safeItems,
        if (normalizedPlan['exercises_details'] != null && normalizedPlan['exercises_details'] is List) 
          'exercises_details': normalizedPlan['exercises_details'],
        'daily_plans': safeDailyPlans,
        'plan_data': normalizedPlan,
        'requested_at': DateTime.now().toIso8601String(),
      };
      
      print('🔍 PlansController - Manual plan approval payload:');
      print('🔍   - plan_id: ${payload['plan_id']} (type: ${payload['plan_id'].runtimeType})');
      print('🔍   - plan_type: ${payload['plan_type']} (type: ${payload['plan_type'].runtimeType})');
      print('🔍   - user_id: ${payload['user_id']} (type: ${payload['user_id'].runtimeType})');
      print('🔍   - user_name: ${payload['user_name']} (type: ${payload['user_name'].runtimeType})');
      print('🔍   - user_phone: ${payload['user_phone']} (type: ${payload['user_phone'].runtimeType})');
      print('🔍   - start_date: ${payload['start_date']} (type: ${payload['start_date'].runtimeType})');
      print('🔍   - end_date: ${payload['end_date']} (type: ${payload['end_date'].runtimeType})');
      print('🔍   - minutes: ${payload['minutes']} (type: ${payload['minutes'].runtimeType})');
      print('🔍   - total_exercises: ${payload['total_exercises']} (type: ${payload['total_exercises'].runtimeType})');
      print('🔍   - total_days: ${payload['total_days']} (type: ${payload['total_days'].runtimeType})');
      print('🔍   - user_level: ${payload['user_level']} (type: ${payload['user_level'].runtimeType})');
      print('🔍   - items count: ${(payload['items'] as List).length}');
      print('🔍   - daily_plans count: ${(payload['daily_plans'] as List).length}');
      print('🔍   - requested_at: ${payload['requested_at']} (type: ${payload['requested_at'].runtimeType})');
      print('🔍   - plan_data keys: ${normalizedPlan.keys.toList()}');
      
      final result = await _approvalService.sendForApproval(
        source: 'manual',
        payload: payload,
      );
      
      print('✅ PlansController - Manual plan sent for approval successfully');
      print('🔍 PlansController - Approval result: $result');
      print('🔍 PlansController - Result keys: ${result.keys.toList()}');
      print('🔍 PlansController - Result ID: ${result['id']}');
      print('🔍 PlansController - Result ID type: ${result['id'].runtimeType}');
      
      // Update the plan's approval status locally
      if (planId != null && result['id'] != null) {
        planToApprovalId[planId] = result['id'];
        planApprovalStatus[planId] = 'pending'; // Set initial status to pending
        await _persistApprovalIdCache();
        print('✅ PlansController - Approval ID stored and status set to pending');
        
        // Force UI refresh to show "Pending" status
        if (!isClosed) update();
      }
      
      return result;
    } catch (e) {
      print('❌ PlansController - Failed to send manual plan for approval: $e');
      rethrow;
    }
  }

  void startPlan(Map<String, dynamic> plan) async {
    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
    if (planId == null) {
      print('❌ PlansController - Invalid plan ID: ${plan['id']}');
      return;
    }
    
    print('🚀 PlansController - Starting plan $planId');
    print('🚀 PlansController - Original plan keys: ${plan.keys.toList()}');
    print('🚀 PlansController - Original plan items: ${plan['items']}');
    print('🚀 PlansController - Original plan exercises_details: ${plan['exercises_details']}');
    
    // Check if there's already an active plan (from any tab)
    final existingActivePlan = await _getAnyActivePlan();
    if (existingActivePlan != null) {
      final currentPlanId = int.tryParse(existingActivePlan['id']?.toString() ?? '');
      
      // If trying to start the same plan, just return
      if (currentPlanId == planId) {
        print('ℹ️ PlansController - Plan $planId is already active');
        return;
      }
      
      // Show confirmation dialog to stop current plan
      final shouldStopCurrent = await _showStopCurrentPlanDialog(existingActivePlan);
      if (!shouldStopCurrent) {
        print('❌ PlansController - User cancelled starting new plan');
        return;
      }
      
      // Stop the current active plan from any tab
      print('🛑 PlansController - Stopping current active plan $currentPlanId');
      await _stopAnyActivePlan();
    }
    
    // Check if this is an AI plan or manual plan
    final planType = plan['plan_type']?.toString().toLowerCase();
    bool isAiPlan = false;
    
    // Check for explicit AI plan indicators first
    final hasExplicitAiIndicators = plan.containsKey('ai_generated') || 
                                   plan.containsKey('gemini_generated') ||
                                   plan.containsKey('ai_plan_id') ||
                                   plan.containsKey('request_id') || // AI plans have request_id
                                   (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
    
    // Check for explicit manual plan indicators
    final hasExplicitManualIndicators = plan.containsKey('created_by') && 
                                       plan['assigned_by'] == null && 
                                       plan['assignment_id'] == null && 
                                       plan['web_plan_id'] == null &&
                                       !plan.containsKey('request_id') && // Manual plans don't have request_id
                                       !plan.containsKey('ai_generated') &&
                                       !plan.containsKey('gemini_generated') &&
                                       !plan.containsKey('ai_plan_id');
    
    // Determine plan type based on indicators
    if (planType == 'ai_generated' || hasExplicitAiIndicators) {
      isAiPlan = true;
    } else if (planType == 'manual' || hasExplicitManualIndicators) {
      isAiPlan = false;
    } else {
      // Default to manual plan if unclear
      isAiPlan = false;
    }
    
    print('🚀 PlansController - Plan type detection: isAiPlan=$isAiPlan, planType=$planType');
    print('🚀 PlansController - AI indicators: ai_generated=${plan.containsKey('ai_generated')}, gemini_generated=${plan.containsKey('gemini_generated')}, ai_plan_id=${plan.containsKey('ai_plan_id')}, request_id=${plan.containsKey('request_id')}');
    print('🚀 PlansController - Manual indicators: created_by=${plan.containsKey('created_by')}, assigned_by=${plan['assigned_by']}, assignment_id=${plan['assignment_id']}, web_plan_id=${plan['web_plan_id']}');
    print('🚀 PlansController - hasExplicitAiIndicators=$hasExplicitAiIndicators, hasExplicitManualIndicators=$hasExplicitManualIndicators');
    
    // First, check if the original plan already has workout data
    bool hasWorkoutData = false;
    if ((plan['items'] != null && (plan['items'] as List).isNotEmpty) || 
        (plan['exercises_details'] != null && (plan['exercises_details'] as List).isNotEmpty)) {
      hasWorkoutData = true;
      print('✅ PlansController - Original plan already has workout data');
    }
    
    if (hasWorkoutData) {
      // Use the original plan data directly
      print('🚀 PlansController - Using original plan data with workout items');
    _startedPlans[planId] = true;
    _activePlan.value = plan;
    _currentDay[planId.toString()] = 0;
    
    _persistStartedPlansToCache();
    _persistActivePlanSnapshot();
      if (!isClosed) {
        update(); // Force UI refresh
        print('🚀 PlansController - Plan $planId started with original data, UI updated');
        print('🚀 PlansController - Active plan items: ${_activePlan.value?['items']?.length ?? 0}');
        print('🚀 PlansController - Active plan exercises_details: ${_activePlan.value?['exercises_details']?.length ?? 0}');
      }
      return;
    }
    
    // If no workout data in original plan, try to fetch full details
    try {
      Map<String, dynamic> fullPlanData;
      
      if (isAiPlan) {
        // Fetch full AI plan details
        print('🚀 PlansController - Fetching full AI plan details for $planId');
        try {
          fullPlanData = await _aiService.getGenerated(planId);
          print('✅ PlansController - AI plan fetched successfully');
        } catch (e) {
          print('❌ PlansController - Failed to fetch AI plan: $e');
          print('🔄 PlansController - Falling back to original plan data');
          fullPlanData = Map<String, dynamic>.from(plan);
        }
      } else {
        // Fetch full manual plan details
        print('🚀 PlansController - Fetching full manual plan details for $planId');
        try {
          fullPlanData = await _manualService.getPlan(planId);
          print('✅ PlansController - Manual plan fetched successfully');
        } catch (e) {
          print('❌ PlansController - Failed to fetch manual plan: $e');
          print('🔄 PlansController - Falling back to original plan data');
          fullPlanData = Map<String, dynamic>.from(plan);
        }
      }
      
      print('🚀 PlansController - Full plan data fetched: ${fullPlanData.keys.toList()}');
      print('🚀 PlansController - Items count: ${fullPlanData['items']?.length ?? 0}');
      print('🚀 PlansController - Exercises details count: ${fullPlanData['exercises_details']?.length ?? 0}');
      print('🚀 PlansController - Full plan items: ${fullPlanData['items']}');
      print('🚀 PlansController - Full plan exercises_details: ${fullPlanData['exercises_details']}');
      
      // Check if the fetched plan has workout data
      final hasItems = (fullPlanData['items'] as List?)?.isNotEmpty ?? false;
      final hasExercisesDetails = (fullPlanData['exercises_details'] as List?)?.isNotEmpty ?? false;
      
      if (!hasItems && !hasExercisesDetails) {
        print('⚠️ PlansController - Fetched plan has no workout data, using original plan data');
        // Use the original plan data if the fetched data is empty
        if ((plan['items'] as List?)?.isNotEmpty ?? false) {
          fullPlanData['items'] = plan['items'];
          print('✅ PlansController - Using original plan items: ${(plan['items'] as List).length}');
        }
        if ((plan['exercises_details'] as List?)?.isNotEmpty ?? false) {
          fullPlanData['exercises_details'] = plan['exercises_details'];
          print('✅ PlansController - Using original plan exercises_details: ${(plan['exercises_details'] as List).length}');
        }
      }
      
      _startedPlans[planId] = true;
      _activePlan.value = fullPlanData;
      _currentDay[planId.toString()] = 0;
      
      // Store daily training plan data in the database (only if we have workout data)
      final workoutItems = (fullPlanData['items'] as List? ?? []).cast<Map<String, dynamic>>();
      if (workoutItems.isNotEmpty) {
        try {
          final dailyPlans = _generateDailyPlans(
            workoutItems,
            startDate: fullPlanData['start_date'] != null 
                ? DateTime.tryParse(fullPlanData['start_date'].toString())
                : null,
            totalDays: _getTotalDays(fullPlanData),
          );
          
          if (dailyPlans.isNotEmpty) {
            await _dailyTrainingService.storeDailyTrainingPlan(
              planId: planId,
              planType: isAiPlan ? 'ai_generated' : 'manual',
              dailyPlans: dailyPlans,
              userId: userId ?? 0,
            );
            
            print('✅ PlansController - Daily training plan data stored successfully');
          } else {
            print('⚠️ PlansController - No daily plans generated, skipping storage');
          }
        } catch (e) {
          print('⚠️ PlansController - Failed to store daily training plan data: $e');
          // Don't fail the plan start if storage fails
        }
      } else {
        print('⚠️ PlansController - No workout items found, skipping daily plan storage');
      }
      
      _persistStartedPlansToCache();
      _persistActivePlanSnapshot();
      if (!isClosed) {
        update(); // Force UI refresh
        print('🚀 PlansController - Plan $planId started with full data, UI updated');
        print('🚀 PlansController - Final active plan items: ${_activePlan.value?['items']?.length ?? 0}');
        print('🚀 PlansController - Final active plan exercises_details: ${_activePlan.value?['exercises_details']?.length ?? 0}');
      } else {
        print('❌ PlansController - Controller is closed, cannot update UI');
      }
    } catch (e) {
      print('❌ PlansController - Error fetching full plan data: $e');
      print('❌ PlansController - Using original plan data as fallback');
      print('❌ PlansController - Original plan items: ${plan['items']?.length ?? 0}');
      print('❌ PlansController - Original plan exercises_details: ${plan['exercises_details']?.length ?? 0}');
      
      // Fallback to original plan data
      _startedPlans[planId] = true;
      _activePlan.value = plan;
      _currentDay[planId.toString()] = 0;
      
      _persistStartedPlansToCache();
      _persistActivePlanSnapshot();
      if (!isClosed) {
        update();
      }
    }
  }

  void stopPlan(Map<String, dynamic> plan) {
    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
    if (planId == null) return;
    
    print('🛑 PlansController - Stopping plan $planId');
    _startedPlans[planId] = false;
    if (_activePlan.value != null && (_activePlan.value!['id']?.toString() ?? '') == planId.toString()) {
      _activePlan.value = null;
    }
    
    _persistStartedPlansToCache();
    _clearActivePlanSnapshotIfStopped();
    if (!isClosed) update(); // Force UI refresh
    print('🛑 PlansController - Plan $planId stopped, UI updated');
  }

  /// Stop the current active plan without requiring a plan parameter
  void _stopCurrentActivePlan() {
    if (_activePlan.value == null) return;
    
    final currentPlan = _activePlan.value!;
    final planId = int.tryParse(currentPlan['id']?.toString() ?? '');
    if (planId == null) return;
    
    print('🛑 PlansController - Stopping current active plan $planId');
    _startedPlans[planId] = false;
    _activePlan.value = null;
    
    _persistStartedPlansToCache();
    _clearActivePlanSnapshotIfStopped();
    if (!isClosed) update(); // Force UI refresh
    print('🛑 PlansController - Current active plan $planId stopped, UI updated');
  }

  /// Check for active plans from any tab (Plans, Schedules, etc.)
  Future<Map<String, dynamic>?> _getAnyActivePlan() async {
    // Check Plans tab active plan
    if (_activePlan.value != null) {
      print('🔍 PlansController - Found active plan in Plans tab: ${_activePlan.value!['id']}');
      return _activePlan.value;
    }
    
    // Check Schedules tab active plan
    try {
      if (Get.isRegistered<SchedulesController>()) {
        final schedulesController = Get.find<SchedulesController>();
        if (schedulesController.activeSchedule != null) {
          print('🔍 PlansController - Found active plan in Schedules tab: ${schedulesController.activeSchedule!['id']}');
          return schedulesController.activeSchedule;
        }
      }
    } catch (e) {
      print('⚠️ PlansController - Could not check SchedulesController: $e');
    }
    
    print('🔍 PlansController - No active plans found in any tab');
    return null;
  }

  /// Stop active plan from any tab
  Future<void> _stopAnyActivePlan() async {
    // Stop Plans tab active plan
    if (_activePlan.value != null) {
      print('🛑 PlansController - Stopping active plan from Plans tab');
      _stopCurrentActivePlan();
    }
    
    // Stop Schedules tab active plan
    try {
      if (Get.isRegistered<SchedulesController>()) {
        final schedulesController = Get.find<SchedulesController>();
        if (schedulesController.activeSchedule != null) {
          print('🛑 PlansController - Stopping active plan from Schedules tab');
          schedulesController.stopSchedule(schedulesController.activeSchedule!);
        }
      }
    } catch (e) {
      print('⚠️ PlansController - Could not stop SchedulesController plan: $e');
    }
  }

  /// Show confirmation dialog to stop current plan
  Future<bool> _showStopCurrentPlanDialog(Map<String, dynamic> currentPlan) async {
    final planName = currentPlan['exercise_plan_category'] ?? 
                    currentPlan['name'] ?? 
                    'Current Plan';
    
    return await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Stop Current Plan?'),
        content: Text(
          'You already have an active plan: "$planName"\n\n'
          'Only one plan can be active at a time. Do you want to stop the current plan and start the new one?'
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Stop & Start New'),
          ),
        ],
      ),
      barrierDismissible: false,
    ) ?? false;
  }

  bool isPlanStarted(int planId) {
    return _startedPlans[planId] ?? false;
  }

  Map<String, dynamic>? get activePlan => _activePlan.value;

  int getCurrentDay(int planId) {
    return _currentDay[planId.toString()] ?? 0;
  }

  void setCurrentDay(int planId, int day) {
    _currentDay[planId.toString()] = day;
    _persistCurrentDayToCache(planId, day);
  }

  // Workout tracking methods (similar to SchedulesController)
  final RxMap<String, bool> _workoutStarted = <String, bool>{}.obs;
  final RxMap<String, bool> _workoutCompleted = <String, bool>{}.obs;
  final RxMap<String, int> _workoutRemainingMinutes = <String, int>{}.obs;
  final RxMap<String, Timer> _workoutTimers = <String, Timer>{}.obs;

  void startWorkout(String workoutKey, int totalMinutes) {
    _workoutStarted[workoutKey] = true;
    _workoutRemainingMinutes[workoutKey] = totalMinutes;
    _workoutCompleted[workoutKey] = false;
    
    // Start timer
    _startWorkoutTimer(workoutKey);
    if (!isClosed) update();
  }

  void _startWorkoutTimer(String workoutKey) {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!(_workoutStarted[workoutKey] ?? false)) {
        timer.cancel();
        return;
      }
      
      final remaining = _workoutRemainingMinutes[workoutKey] ?? 0;
      if (remaining <= 1) {
        // Workout completed
        _workoutCompleted[workoutKey] = true;
        _workoutStarted[workoutKey] = false;
        _workoutRemainingMinutes[workoutKey] = 0;
        timer.cancel();
        _workoutTimers.remove(workoutKey);
        
        // Store completion data
        _storeWorkoutCompletion(workoutKey);
        
        if (!isClosed) update();
      } else {
        _workoutRemainingMinutes[workoutKey] = remaining - 1;
        if (!isClosed) update();
      }
    });
  }

  void _storeWorkoutCompletion(String workoutKey) {
    // Parse workout key to get plan info
    final parts = workoutKey.split('_');
    if (parts.length >= 3) {
      final planId = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final workoutName = parts.sublist(2).join('_');
      
      if (planId != null && day != null) {
        // Store in daily_training_plans and daily_training_plan_items tables
        _storeDailyTrainingData(planId, day, workoutName);
      }
    }
  }

  Future<void> _storeDailyTrainingData(int planId, int day, String workoutName) async {
    try {
      print('✅ Workout completed: Plan $planId, Day $day, Workout $workoutName');
      
      // Store completion data using the correct API
      final completionData = [
        {
          'plan_id': planId,
          'day': day,
          'workout_name': workoutName,
          'completed_at': DateTime.now().toIso8601String(),
          'status': 'completed',
        }
      ];
      
      await _dailyTrainingService.submitDailyTrainingCompletion(
        planId: planId,
        completionData: completionData,
      );
      
      print('✅ Workout completion stored successfully');
    } catch (e) {
      print('❌ Error storing workout completion: $e');
    }
  }

  bool isWorkoutStarted(String workoutKey) {
    return _workoutStarted[workoutKey] ?? false;
  }

  bool isWorkoutCompleted(String workoutKey) {
    return _workoutCompleted[workoutKey] ?? false;
  }

  int getWorkoutRemainingMinutes(String workoutKey) {
    return _workoutRemainingMinutes[workoutKey] ?? 0;
  }

  // Approval methods for plans
  /// Mark a plan as modified since its last approval
  void markPlanAsModified(int planId) {
    planModifiedSinceApproval[planId] = true;
    print('🔍 PlansController - Marked plan $planId as modified since approval');
    print('🔍 PlansController - Current modification map: $planModifiedSinceApproval');
    print('🔍 PlansController - Plan $planId modification status: ${planModifiedSinceApproval[planId]}');
    
    // Persist modification flag to cache
    _persistModificationFlags();
    
    if (!isClosed) {
      update(); // Force UI refresh
      print('🔍 PlansController - UI update triggered for plan modification');
    } else {
      print('⚠️ PlansController - Controller is closed, cannot update UI');
    }
  }

  /// Check if a plan has been modified since its last approval
  bool hasPlanBeenModifiedSinceApproval(int planId) {
    final result = planModifiedSinceApproval[planId] ?? false;
    print('🔍 PlansController - Checking if plan $planId has been modified: $result');
    print('🔍 PlansController - Current modification map: $planModifiedSinceApproval');
    return result;
  }

  /// Reset modification flag when plan is approved
  void resetModificationFlag(int planId) {
    planModifiedSinceApproval[planId] = false;
    print('🔍 PlansController - Reset modification flag for plan $planId');
    
    // Persist modification flag to cache
    _persistModificationFlags();
    
    if (!isClosed) update(); // Force UI refresh
  }

  // Calculate total days for a plan
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

  // Build daily_plans using pair rule and rotation with 80-minute limit
  List<Map<String, dynamic>> _generateDailyPlans(List<Map<String, dynamic>> items, {DateTime? startDate, required int totalDays}) {
    final List<Map<String, dynamic>> days = [];
    if (items.isEmpty || totalDays <= 0) return days;
    
    int index = 0;
    for (int day = 0; day < totalDays; day++) {
      final List<Map<String, dynamic>> workoutsForDay = [];
      
      // Ensure we have valid items
      if (items.isNotEmpty) {
        // Add first workout
        final Map<String, dynamic> first = Map<String, dynamic>.from(items[index % items.length]);
        final int m1 = _extractWorkoutMinutesFromMap(first);
        workoutsForDay.add(first);
        index++;
        
        // Check if we can add a second workout (80-minute rule)
        if (items.length > 1) {
          final Map<String, dynamic> second = Map<String, dynamic>.from(items[index % items.length]);
          final int m2 = _extractWorkoutMinutesFromMap(second);
          final int totalMinutes = m1 + m2;
          
          print('🔍 Daily Plan Generation - Day ${day + 1}:');
          print('🔍   - First workout: ${first['workout_name'] ?? 'Unknown'} (${m1} min)');
          print('🔍   - Second workout: ${second['workout_name'] ?? 'Unknown'} (${m2} min)');
          print('🔍   - Total minutes: $totalMinutes');
          print('🔍   - 80-minute rule: ${totalMinutes <= 80 ? 'PASS' : 'FAIL'}');
          
          if (totalMinutes <= 80) {
            workoutsForDay.add(second);
            index++;
            print('✅ Added 2 workouts for Day ${day + 1} (${totalMinutes} min total)');
          } else {
            print('⚠️ Skipped second workout for Day ${day + 1} (would exceed 80 min: ${totalMinutes} min)');
          }
        }
      }
      
      final DateTime? date = startDate != null ? startDate.add(Duration(days: day)) : null;
      days.add({
        'day': day + 1,
        if (date != null) 'date': date.toIso8601String().split('T').first,
        'workouts': workoutsForDay,
      });
    }
    return days;
  }

  // Unified minutes extraction used by payload totals and daily_plans
  int _extractWorkoutMinutesFromMap(Map<String, dynamic> item) {
    final dynamic raw = item['minutes'] ?? item['training_minutes'] ?? item['trainingMinutes'] ?? item['duration'];
    if (raw == null) return 0;
    final String s = raw.toString();
    final int? i = int.tryParse(s);
    if (i != null) return i;
    final double? d = double.tryParse(s);
    return d?.round() ?? 0;
  }

  /// Get the approval status for a specific plan
  String getPlanApprovalStatus(int planId) {
    final status = planApprovalStatus[planId] ?? 'none';
    print('🔍 PlansController - getPlanApprovalStatus($planId) = $status');
    print('🔍 PlansController - Current planApprovalStatus map: $planApprovalStatus');
    return status;
  }

  /// Check approval status from backend for all plans that have been sent for approval
  Future<void> refreshApprovalStatusFromBackend() async {
    try {
      print('🔍 PlansController - Refreshing approval status from backend...');
      print('🔍 PlansController - Current planToApprovalId mappings: $planToApprovalId');
      print('🔍 PlansController - Current planApprovalStatus: $planApprovalStatus');
      
      // Method 1: Check via approval IDs (for plans we sent for approval)
      if (planToApprovalId.isNotEmpty) {
        print('🔍 PlansController - Checking status via approval IDs...');
        for (final entry in planToApprovalId.entries) {
          final planId = entry.key;
          final approvalId = entry.value;
          
          try {
            print('🔍 PlansController - Checking approval status for plan $planId (approval ID: $approvalId)');
            final approvalData = await _approvalService.getApproval(approvalId);
            print('🔍 PlansController - Raw approval data for plan $planId: $approvalData');
            
            // Extract status from approval data
            String status = 'none';
            if (approvalData['approval_status'] != null) {
              status = approvalData['approval_status'].toString().toLowerCase();
            } else if (approvalData['status'] != null) {
              status = approvalData['status'].toString().toLowerCase();
            } else if (approvalData['state'] != null) {
              status = approvalData['state'].toString().toLowerCase();
            }
            
            // Debug: Log all possible status fields for plan 41
            if (planId == 41) {
              print('🔍 DEBUG Plan 41 - Full approval data: $approvalData');
              print('🔍 DEBUG Plan 41 - approval_status: ${approvalData['approval_status']}');
              print('🔍 DEBUG Plan 41 - status: ${approvalData['status']}');
              print('🔍 DEBUG Plan 41 - state: ${approvalData['state']}');
              print('🔍 DEBUG Plan 41 - Extracted status: $status');
            }
            
            print('🔍 PlansController - Plan $planId approval status: $status');
            print('🔍 PlansController - Current local status: ${planApprovalStatus[planId]}');
            
            // Update local status if it's different
            if (planApprovalStatus[planId] != status) {
              final oldStatus = planApprovalStatus[planId];
    planApprovalStatus[planId] = status;
              print('✅ PlansController - Updated plan $planId status from $oldStatus to $status');
              
              // Reset modification flag when plan is approved
              if (status == 'approved') {
                resetModificationFlag(planId);
              }
            } else {
              print('ℹ️ PlansController - Plan $planId status unchanged: $status');
            }

            // Even if unchanged, ensure modified flag is cleared when approved
            if (status == 'approved' && (planModifiedSinceApproval[planId] ?? false)) {
              print('🔄 PlansController - Status unchanged but approved; clearing modified flag for plan $planId');
              resetModificationFlag(planId);
            }
            
          } catch (e) {
            print('⚠️ PlansController - Failed to check approval status for plan $planId: $e');
            // Don't throw here, continue checking other plans
          }
        }
      }
      
      // Method 2: Check approval status directly from plan data (for all plans)
      print('🔍 PlansController - Checking status directly from plan data...');
      
      // Check manual plans
      for (final plan in manualPlans) {
        final planId = int.tryParse(plan['id']?.toString() ?? '');
        if (planId != null) {
          try {
            print('🔍 PlansController - Checking manual plan $planId approval status from plan data...');
            final planData = await _manualService.getPlan(planId);
            print('🔍 PlansController - Manual plan $planId data: ${planData.keys.toList()}');
            print('🔍 PlansController - Manual plan $planId full data: $planData');
            
            // Check for approval_status in plan data
            String status = 'none';
            if (planData['approval_status'] != null) {
              status = planData['approval_status'].toString().toLowerCase();
              print('🔍 PlansController - Found approval_status in plan data: $status');
            } else {
              print('🔍 PlansController - No approval_status field found in plan data');
            }
            
            // Update local status if found
            if (status != 'none' && planApprovalStatus[planId] != status) {
              final oldStatus = planApprovalStatus[planId];
              planApprovalStatus[planId] = status;
              print('✅ PlansController - Updated manual plan $planId status from $oldStatus to $status');
              
              // Reset modification flag when plan is approved
              if (status == 'approved') {
                resetModificationFlag(planId);
              }
            } else if (status != 'none') {
              print('ℹ️ PlansController - Manual plan $planId status unchanged: $status');
            } else {
              print('⚠️ PlansController - Manual plan $planId has no approval status');
            }

            // Even if unchanged, ensure modified flag is cleared when approved
            if (status == 'approved' && (planModifiedSinceApproval[planId] ?? false)) {
              print('🔄 PlansController - Manual plan approved but flag set; clearing modified flag for plan $planId');
              resetModificationFlag(planId);
            }
            
          } catch (e) {
            print('⚠️ PlansController - Failed to check manual plan $planId: $e');
          }
        }
      }
      
      // Check AI plans
      for (final plan in aiGeneratedPlans) {
        final planId = int.tryParse(plan['id']?.toString() ?? '');
        if (planId != null) {
          try {
            print('🔍 PlansController - Checking AI plan $planId approval status from plan data...');
            
            // Check if this is actually an AI plan before calling AI service
            final planType = plan['plan_type']?.toString().toLowerCase();
            final hasAiIndicators = plan.containsKey('request_id') || 
                                  plan.containsKey('ai_generated') ||
                                  plan.containsKey('gemini_generated') ||
                                  (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level'));
            
            if (planType != 'ai_generated' && !hasAiIndicators) {
              print('⚠️ PlansController - Plan $planId appears to be a manual plan in AI list, skipping AI service call');
              continue;
            }
            
            Map<String, dynamic> planData;
            try {
              planData = await _aiService.getGenerated(planId);
              print('🔍 PlansController - AI plan $planId data: ${planData.keys.toList()}');
            } catch (e) {
              print('⚠️ PlansController - Failed to fetch AI plan $planId: $e');
              print('⚠️ PlansController - This might be a manual plan incorrectly listed as AI plan');
              continue; // Skip this plan and continue with the next one
            }
            
            // Check for approval_status in plan data
            String status = 'none';
            if (planData['approval_status'] != null) {
              status = planData['approval_status'].toString().toLowerCase();
              print('🔍 PlansController - Found approval_status in plan data: $status');
            }
            
            // Debug: Log all possible status fields for plan 41
            if (planId == 41) {
              print('🔍 DEBUG Plan 41 AI - Full plan data: $planData');
              print('🔍 DEBUG Plan 41 AI - approval_status: ${planData['approval_status']}');
              print('🔍 DEBUG Plan 41 AI - status: ${planData['status']}');
              print('🔍 DEBUG Plan 41 AI - state: ${planData['state']}');
              print('🔍 DEBUG Plan 41 AI - Extracted status: $status');
            }
            
            // Update local status if found
            if (status != 'none' && planApprovalStatus[planId] != status) {
              final oldStatus = planApprovalStatus[planId];
              planApprovalStatus[planId] = status;
              print('✅ PlansController - Updated AI plan $planId status from $oldStatus to $status');
              
              // Reset modification flag when plan is approved
              if (status == 'approved') {
                resetModificationFlag(planId);
              }
            }

            // Even if unchanged, ensure modified flag is cleared when approved
            if (status == 'approved' && (planModifiedSinceApproval[planId] ?? false)) {
              print('🔄 PlansController - AI plan approved but flag set; clearing modified flag for plan $planId');
              resetModificationFlag(planId);
            }
            
          } catch (e) {
            print('⚠️ PlansController - Failed to check AI plan $planId: $e');
          }
        }
      }
      
      print('✅ PlansController - Finished refreshing approval status from backend');
      print('🔍 PlansController - Final planApprovalStatus: $planApprovalStatus');
      
      // Force UI refresh to show updated statuses
      if (!isClosed) update();
      
    } catch (e) {
      print('❌ PlansController - Error refreshing approval status from backend: $e');
    }
  }

  /// Force refresh all data - useful when app comes back to focus
  Future<void> forceRefreshAllData() async {
    print('🔄 PlansController - Force refreshing all data...');
    await loadPlansData();
    await refreshApprovalStatusFromBackend();
    if (!isClosed) update();
    print('✅ PlansController - Force refresh completed');
  }

  /// Manually refresh approval status - can be called from UI
  Future<void> manualRefreshApprovalStatus() async {
    print('🔄 PlansController - Manual refresh of approval status requested');
    print('🔄 PlansController - Current manual plans: ${manualPlans.length}');
    print('🔄 PlansController - Current AI plans: ${aiGeneratedPlans.length}');
    print('🔄 PlansController - Current planToApprovalId: $planToApprovalId');
    print('🔄 PlansController - Current planApprovalStatus: $planApprovalStatus');
    
    await refreshApprovalStatusFromBackend();
    
    print('🔄 PlansController - After refresh - planApprovalStatus: $planApprovalStatus');
    
    // Force UI update
    if (!isClosed) update();
  }

  /// Debug method to check approval status for a specific plan
  Future<void> debugCheckPlanStatus(int planId) async {
    print('🔍 DEBUG - Checking status for plan $planId...');
    
    try {
      // Check if we have approval ID for this plan
      final approvalId = planToApprovalId[planId];
      print('🔍 DEBUG - Plan $planId approval ID: $approvalId');
      
      if (approvalId != null) {
        try {
          final approvalData = await _approvalService.getApproval(approvalId);
          print('🔍 DEBUG - Approval data for plan $planId: $approvalData');
        } catch (e) {
          print('⚠️ DEBUG - Failed to get approval data for plan $planId: $e');
        }
      }
      
      // Check plan data directly
      try {
        final planData = await _manualService.getPlan(planId);
        print('🔍 DEBUG - Plan $planId data keys: ${planData.keys.toList()}');
        print('🔍 DEBUG - Plan $planId full data: $planData');
        
        // Check for approval_status
        if (planData['approval_status'] != null) {
          print('🔍 DEBUG - Plan $planId approval_status: ${planData['approval_status']}');
        } else {
          print('⚠️ DEBUG - Plan $planId has no approval_status field');
        }
        
        // Check for other possible status fields
        final possibleStatusFields = ['status', 'state', 'approval_state', 'approvalState'];
        for (final field in possibleStatusFields) {
          if (planData[field] != null) {
            print('🔍 DEBUG - Plan $planId $field: ${planData[field]}');
          }
        }
        
      } catch (e) {
        print('⚠️ DEBUG - Failed to get plan data for plan $planId: $e');
      }
      
      // Check current local status
      print('🔍 DEBUG - Current local status for plan $planId: ${planApprovalStatus[planId]}');
      
    } catch (e) {
      print('❌ DEBUG - Error checking status for plan $planId: $e');
    }
  }

  bool isPlanPending(int planId) {
    return getPlanApprovalStatus(planId) == 'pending';
  }

  bool isPlanApproved(int planId) {
    return getPlanApprovalStatus(planId) == 'approved';
  }

  int? getApprovalIdForPlan(int planId) => planToApprovalId[planId];

  // Persistence methods for plans
  Future<void> _loadStartedPlansFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'startedPlans_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> cache = jsonDecode(data);
        _startedPlans.clear();
        cache.forEach((key, value) {
          final int? id = int.tryParse(key);
          if (id != null && value is bool) {
            _startedPlans[id] = value;
          }
        });
        print('📱 Plans - Loaded started plans from cache: $_startedPlans');
      }
    } catch (e) {
      print('❌ Plans - Error loading started plans from cache: $e');
    }
  }

  Future<void> _loadActivePlanSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activePlan_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> snapshot = jsonDecode(data);
        _activePlan.value = snapshot;
        print('📱 Plans - Loaded active plan snapshot from cache: ${snapshot['id']}');
      }
    } catch (e) {
      print('❌ Plans - Error loading active plan snapshot from cache: $e');
    }
  }

  Future<void> _persistStartedPlansToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'startedPlans_user_$userId';
      // Convert IdentityMap to regular Map for JSON serialization
      final Map<String, dynamic> serializableMap = {};
      _startedPlans.forEach((key, value) {
        serializableMap[key.toString()] = value;
      });
      await prefs.setString(key, jsonEncode(serializableMap));
      print('💾 Plans - Persisted started plans to cache');
    } catch (e) {
      print('❌ Plans - Error persisting started plans: $e');
    }
  }

  Future<void> _persistActivePlanSnapshot() async {
    if (_activePlan.value == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activePlan_user_$userId';
      await prefs.setString(key, jsonEncode(_activePlan.value));
      print('💾 Plans - Persisted active plan snapshot');
    } catch (e) {
      print('❌ Plans - Error persisting active plan snapshot: $e');
    }
  }

  Future<void> _clearActivePlanSnapshotIfStopped() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'activePlan_user_$userId';
      await prefs.remove(key);
      print('🗑️ Plans - Cleared active plan snapshot');
    } catch (e) {
      print('❌ Plans - Error clearing active plan snapshot: $e');
    }
  }

  Future<void> _persistCurrentDayToCache(int planId, int day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'plan_day_${planId}_user_$userId';
      await prefs.setInt(key, day);
    } catch (e) {
      print('❌ Plans - Error persisting current day: $e');
    }
  }

  Future<void> _loadCurrentDayFromCache(int planId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'plan_day_${planId}_user_$userId';
      final int? day = prefs.getInt(key);
      if (day != null) {
        _currentDay[planId.toString()] = day;
      }
    } catch (e) {
      print('❌ Plans - Error loading current day: $e');
    }
  }

  // Approval cache methods
  Future<void> _loadApprovalIdCacheIfNeeded() async {
    if (_approvalCacheLoaded) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'planApprovalIds_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> cache = jsonDecode(data);
        planToApprovalId.clear();
        cache.forEach((key, value) {
          final int? planId = int.tryParse(key);
          final int? approvalId = int.tryParse(value.toString());
          if (planId != null && approvalId != null) {
            planToApprovalId[planId] = approvalId;
          }
        });
        print('📱 Plans - Loaded approval IDs from cache: $planToApprovalId');
      }
      _approvalCacheLoaded = true;
    } catch (e) {
      print('❌ Plans - Error loading approval IDs from cache: $e');
    }
  }

  Future<void> _cleanupInvalidApprovalMappings() async {
    // Clean up any invalid approval mappings
    final invalidMappings = <int>[];
    
    for (final entry in planToApprovalId.entries) {
      try {
        await _approvalService.getApproval(entry.value);
      } catch (e) {
        print('🗑️ Plans - Removing invalid approval mapping: ${entry.key} -> ${entry.value}');
        invalidMappings.add(entry.key);
      }
    }
    
    for (final planId in invalidMappings) {
      planToApprovalId.remove(planId);
    }
    
    if (invalidMappings.isNotEmpty) {
      await _persistApprovalIdCache();
    }
  }

  Future<void> _persistApprovalIdCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'planApprovalIds_user_$userId';
      await prefs.setString(key, jsonEncode(planToApprovalId));
      print('💾 Plans - Persisted approval IDs to cache');
    } catch (e) {
      print('❌ Plans - Error persisting approval IDs: $e');
    }
  }

  // User and data access methods
  int? get userId => _profileController.user?.id;
  Map<String, dynamic>? get user => _profileController.user?.toJson();

  // Plan creation methods
  Future<Map<String, dynamic>> createManualPlan(Map<String, dynamic> payload) async {
    return await _manualService.createPlan(payload);
  }

  Future<Map<String, dynamic>> createAiRequest(Map<String, dynamic> payload) async {
    return await _aiService.createRequest(payload);
  }

  Future<Map<String, dynamic>> createAiGeneratedPlan(Map<String, dynamic> payload) async {
    return await _aiService.createGenerated(payload);
  }

  Future<Map<String, dynamic>> createAiGeneratedPlanViaBackend(Map<String, dynamic> payload) async {
    return await _aiService.createGeneratedViaBackend(payload);
  }

  /// Generate via backend and wait briefly for the plan to appear in /generated
  Future<void> generateViaBackendAndAwait(Map<String, dynamic> payload, {Duration timeout = const Duration(seconds: 20)}) async {
    final start = DateTime.now();
    final int? uid = _profileController.user?.id;
    final before = await _aiService.listGenerated(userId: uid);
    await createAiGeneratedPlanViaBackend(payload);
    while (DateTime.now().difference(start) < timeout) {
      await Future.delayed(const Duration(seconds: 2));
      // Check if controller is still active
      if (!isClosed) {
      final after = await _aiService.listGenerated(userId: uid);
      if (after.length > before.length) {
        if (!isClosed) aiGeneratedPlans.assignAll(after.map((e) => Map<String, dynamic>.from(e)));
          return;
        }
      } else {
        print('⚠️ Plans Controller - Controller disposed, stopping generation wait');
        return;
      }
    }
    // timeout: still refresh to reflect any late results
    if (!isClosed) {
    aiGeneratedPlans.assignAll((await _aiService.listGenerated(userId: uid)).map((e) => Map<String, dynamic>.from(e)));
    }
  }

  // Plan update methods
  Future<Map<String, dynamic>> updateManualPlan(int id, Map<String, dynamic> payload) async {
    print('🔍 PlansController - Updating manual plan $id with payload: $payload');
    
    // Store the current plan before update to preserve it if needed
    final currentPlan = manualPlans.firstWhereOrNull((plan) => plan['id'] == id);
    print('🔍 PlansController - Current plan before update: $currentPlan');
    
    final result = await _manualService.updatePlan(id, payload);
    print('🔍 PlansController - Manual plan update result: $result');
    
    // Mark plan as modified since approval when updated
    markPlanAsModified(id);
    print('🔍 PlansController - Marked plan $id as modified after update');
    
    // Refresh plans to show updated data
    await refreshManualPlans();
    print('🔍 PlansController - Refreshed manual plans after update');
    
    // Check if the plan is still in the list after refresh
    final planStillExists = manualPlans.any((plan) => plan['id'] == id);
    print('🔍 PlansController - Plan $id still exists after refresh: $planStillExists');
    
    // If plan was filtered out, try to add it back with updated data
    if (!planStillExists && currentPlan != null) {
      print('⚠️ PlansController - Plan $id was filtered out, attempting to restore...');
      
      // Merge the updated data with the current plan
      final updatedPlan = Map<String, dynamic>.from(currentPlan);
      updatedPlan.addAll(result);
      updatedPlan['id'] = id; // Ensure ID is preserved
      
      // Add it back to the list
      manualPlans.add(updatedPlan);
      print('✅ PlansController - Restored plan $id to manual plans list');
    }
    
    // Force UI update
    if (!isClosed) update();
    print('🔍 PlansController - Forced UI update after manual plan update');
    
    return result;
  }

  Future<Map<String, dynamic>> updateAiGeneratedPlan(int id, Map<String, dynamic> payload) async {
    print('🔍 PlansController - Updating AI plan $id with payload: $payload');
    
    final result = await _aiService.updateGenerated(id, payload);
    print('🔍 PlansController - AI plan update result: $result');
    
    // Mark plan as modified since approval when updated
    markPlanAsModified(id);
    
    // Refresh plans to show updated data
    await refreshAiPlans();
    
    return result;
  }

  // Assignment methods (for compatibility)
  Future<Map<String, dynamic>> getAssignmentDetails(int assignmentId) async {
    // For now, return a placeholder since getAssignmentDetails doesn't exist
    // This should be implemented in the ManualTrainingService if needed
    return {
      'id': assignmentId,
      'assignment_id': assignmentId,
      'exercises_details': [],
      'items': [],
    };
  }

  // Data loading method (for compatibility)
  Future<void> loadData() async {
    await loadPlansData();
  }

  // Refresh methods
  Future<void> refreshPlans() async {
    await loadPlansData();
    await refreshApprovalStatusFromBackend();
  }

  Future<void> refreshManualPlans() async {
    try {
      print('🔍 Plans - Starting refreshManualPlans...');
      final manualRes = await _manualService.listPlans();
      print('🔍 Plans - Raw manual plans from API: ${manualRes.length} items');
      
      // Store current plans before filtering to preserve any that might get filtered out
      final currentPlanIds = manualPlans.map((p) => p['id']).toSet();
      print('🔍 Plans - Current plan IDs before refresh: $currentPlanIds');
      
      // Filter to show ONLY manual plans created by the user (not assigned plans)
      final uniquePlans = <Map<String, dynamic>>[];
      final seenIds = <int>{};
      
      for (final plan in manualRes) {
        final planMap = Map<String, dynamic>.from(plan);
        final planId = int.tryParse(planMap['id']?.toString() ?? '');
        final planType = planMap['plan_type']?.toString().toLowerCase();
        final createdBy = planMap['created_by'];
        final assignedBy = planMap['assigned_by'];
        final assignmentId = planMap['assignment_id'];
        final webPlanId = planMap['web_plan_id'];
        
        // Check if this is an assigned plan (exclude these)
        final isAssignedPlan = planType == 'assigned' || 
                              assignedBy != null || 
                              assignmentId != null ||
                              webPlanId != null ||
                              planType == 'ai_generated' ||
                              planType == 'daily' ||
                              planType == 'schedule';
        
        // Include manual plans created by the user, including approved ones
        // Also include plans that don't have explicit plan_type but are created by user
        // Be more permissive to avoid filtering out valid plans
        // Handle cases where createdBy might be null but plan is still valid
        final isManualPlan = (planType == 'manual' || planType == null || planType == '') && 
                            (createdBy == null || createdBy == userId); // Allow null createdBy or match userId
                            // Removed strict checks for assignedBy, assignmentId, webPlanId
                            // as these might be set by the backend during updates
        
        print('🔍 Manual Plan Filter - Plan ID: $planId');
        print('🔍   - planType: $planType');
        print('🔍   - createdBy: $createdBy (type: ${createdBy.runtimeType})');
        print('🔍   - userId: $userId (type: ${userId.runtimeType})');
        print('🔍   - assignedBy: $assignedBy');
        print('🔍   - assignmentId: $assignmentId');
        print('🔍   - webPlanId: $webPlanId');
        print('🔍   - isAssignedPlan: $isAssignedPlan');
        print('🔍   - isManualPlan: $isManualPlan');
        print('🔍   - createdBy == userId: ${createdBy == userId}');
        print('🔍   - createdBy == null: ${createdBy == null}');
        print('🔍   - (createdBy == null || createdBy == userId): ${createdBy == null || createdBy == userId}');
        
        if (planId != null && !seenIds.contains(planId) && isManualPlan && !isAssignedPlan) {
          seenIds.add(planId);
          uniquePlans.add(planMap);
          print('✅ Plans - Added manual plan $planId to list');
        } else {
          print('❌ Plans - Excluded plan $planId: isManualPlan=$isManualPlan, isAssignedPlan=$isAssignedPlan');
        }
      }
      
      print('🔍 Plans - Filtered unique plans: ${uniquePlans.length} items');
      
      // Check if any previously visible plans were filtered out and restore them
      final filteredPlanIds = uniquePlans.map((p) => p['id']).toSet();
      final missingPlanIds = currentPlanIds.difference(filteredPlanIds);
      
      if (missingPlanIds.isNotEmpty) {
        print('⚠️ Plans - Some plans were filtered out: $missingPlanIds');
        
        // Try to restore missing plans from the original API response
        for (final missingId in missingPlanIds) {
          final originalPlan = manualRes.firstWhereOrNull((p) => p['id'] == missingId);
          if (originalPlan != null) {
            final planMap = Map<String, dynamic>.from(originalPlan);
            final planId = int.tryParse(planMap['id']?.toString() ?? '');
            
            if (planId != null && !seenIds.contains(planId)) {
              // Check if it's created by the current user or has null createdBy (basic check)
              final createdBy = planMap['created_by'];
              if (createdBy == null || createdBy == userId) {
                seenIds.add(planId);
                uniquePlans.add(planMap);
                print('✅ Plans - Restored filtered plan $planId');
              }
            }
          }
        }
      }
      
      if (!isClosed) {
        manualPlans.assignAll(uniquePlans);
        update(); // Force UI refresh
      }
      print('✅ Plans - Refreshed manual plans: ${manualPlans.length} unique manual items');
    } catch (e) {
      print('❌ Plans - Error refreshing manual plans: $e');
    }
  }

  Future<void> refreshAiPlans() async {
    try {
      final aiRes = await _aiService.listGenerated(userId: _profileController.user?.id);
      if (!isClosed) {
      aiGeneratedPlans.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
        update(); // Force UI refresh
      }
    } catch (e) {
      print('❌ Plans - Error refreshing AI plans: $e');
    }
  }

  void clearAiGeneratedPlans() {
    if (!isClosed) aiGeneratedPlans.clear();
  }

  void refreshAiGeneratedPlans() {
    refreshAiPlans();
  }

  // Delete methods
  Future<void> deleteManualPlan(int planId) async {
    try {
      print('🗑️ Plans - Deleting manual plan ID: $planId');
      await _manualService.deletePlan(planId);
      
      // Remove from local list
      manualPlans.removeWhere((plan) => plan['id'] == planId);
      
      // Remove from started plans if it was started
      if (_startedPlans.containsKey(planId)) {
        _startedPlans.remove(planId);
        await _persistStartedPlansToCache();
      }
      
      // Clear active plan if it was the deleted plan
      if (_activePlan.value?['id'] == planId) {
        _activePlan.value = null;
        await _clearActivePlanSnapshotIfStopped();
      }
      
      print('✅ Plans - Manual plan deleted successfully');
    } catch (e) {
      print('❌ Plans - Error deleting manual plan: $e');
      rethrow;
    }
  }

  Future<void> deleteAiGeneratedPlan(int planId) async {
    try {
      print('🗑️ Plans - Deleting AI generated plan ID: $planId');
      await _aiService.deleteGenerated(planId);
      
      // Remove from local list
      aiGeneratedPlans.removeWhere((plan) => plan['id'] == planId);
      
      // Remove from started plans if it was started
      if (_startedPlans.containsKey(planId)) {
        _startedPlans.remove(planId);
        await _persistStartedPlansToCache();
      }
      
      // Clear active plan if it was the deleted plan
      if (_activePlan.value?['id'] == planId) {
        _activePlan.value = null;
        await _clearActivePlanSnapshotIfStopped();
      }
      
      print('✅ Plans - AI generated plan deleted successfully');
    } catch (e) {
      print('❌ Plans - Error deleting AI generated plan: $e');
      rethrow;
    }
  }

  // Submit daily training completion for Plans
  Future<void> submitDailyTrainingCompletion({
    required int planId,
    required List<Map<String, dynamic>> completionData,
  }) async {
    try {
      print('📊 Submitting daily training completion for plan $planId');
      
      // Submit to daily training API using the correct method
      await _dailyTrainingService.submitDailyTrainingCompletion(
        planId: planId,
        completionData: completionData,
      );
      
      print('✅ Daily training completion submitted successfully');
      
      // Notify stats controller to refresh
      try {
        final statsController = Get.find<StatsController>();
        statsController.refreshStats();
      } catch (e) {
        print('⚠️ Stats controller not found, skipping stats refresh: $e');
      }
    } catch (e) {
      print('❌ Failed to submit daily training completion: $e');
      rethrow; // Re-throw to let the caller handle the error
    }
  }

  // Persistence methods for modification flags
  Future<void> _persistModificationFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'planModifications_user_$userId';
      
      // Convert map to JSON-serializable format
      final Map<String, bool> serializableMap = {};
      planModifiedSinceApproval.forEach((key, value) {
        serializableMap[key.toString()] = value;
      });
      
      final String data = jsonEncode(serializableMap);
      await prefs.setString(key, data);
      print('📱 Plans - Persisted modification flags to cache: $serializableMap');
    } catch (e) {
      print('❌ Plans - Error persisting modification flags: $e');
    }
  }

  Future<void> _loadModificationFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'planModifications_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> cache = jsonDecode(data);
        planModifiedSinceApproval.clear();
        cache.forEach((key, value) {
          final int? id = int.tryParse(key);
          if (id != null && value is bool) {
            planModifiedSinceApproval[id] = value;
          }
        });
        print('📱 Plans - Loaded modification flags from cache: $planModifiedSinceApproval');
      }
    } catch (e) {
      print('❌ Plans - Error loading modification flags from cache: $e');
    }
  }
}
