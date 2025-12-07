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
  final RxMap<String, int> _currentDay = <String, int>{}.obs; // Make reactive like schedules
  
  // Plans-specific approval tracking
  final RxMap<int, String> planApprovalStatus = <int, String>{}.obs;
  final RxMap<int, int> planToApprovalId = <int, int>{}.obs;
  final RxMap<int, bool> planModifiedSinceApproval = <int, bool>{}.obs;
  bool _approvalCacheLoaded = false;

  final RxInt uiTick = 0.obs;
  final RxMap<String, int> _workoutRemainingMinutes = <String, int>{}.obs;
  final RxMap<String, Timer> _workoutTimers = <String, Timer>{}.obs;

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
        // Real-time update received
        // Handle real-time updates for plans
        _handleRealtimeUpdate(data);
      });
      _socketSubscribed = true;
      // Connected to real-time updates
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
      // Loading plans data
      isLoading.value = true;
      
      await _loadApprovalIdCacheIfNeeded();
      await _cleanupInvalidApprovalMappings();
      
      // Ensure profile is loaded
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      if (userId == null) {
        print('❌ Plans - User ID is null! Cannot fetch plans.');
        return;
      }
      
      // Test API connectivity
      await _manualService.testApiConnectivity();
      
      // Fetch manual training plans (Plans-specific)
      // NOTE: Backend now filters out plans with web_plan_id (mirrored assigned plans)
      // Frontend filtering below is a defense-in-depth measure
      try {
        final manualRes = await _manualService.listPlans();
        
        if (manualRes.isEmpty) {
          print('⚠️ Plans - No manual plans returned from API!');
          print('⚠️ Plans - This could mean:');
          print('⚠️ Plans - 1. No manual plans exist in the database');
          print('⚠️ Plans - 2. API endpoint is incorrect');
          print('⚠️ Plans - 3. User has no manual plans');
          print('⚠️ Plans - 4. Backend is returning empty list');
          
          // Try alternative endpoint as fallback
          // NOTE: This endpoint may return assigned plans, but they will be filtered out below
          print('🔄 Plans - Trying alternative endpoint: /api/trainingPlans/');
          try {
            final dio = await _manualService.getAuthedDio();
            final altRes = await dio.get('/api/trainingPlans/');
            
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
                // CRITICAL: Add plans from alternative endpoint - they will be filtered below
                // to exclude assigned plans (web_assigned, assigned, etc.)
                manualRes.addAll(altPlans);
                print('🔄 Plans - Added ${altPlans.length} plans from alternative endpoint (will be filtered)');
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
        // NOTE: Backend (/api/appManualTraining/) now filters out plans with web_plan_id
        // AND plans matching assignments by date range (two-layer filter)
        // This frontend filtering is a defense-in-depth measure to catch any edge cases
        // or plans from the alternative endpoint fallback
        // 
        // BACKEND FIX: The backend now uses a two-layer filter:
        // 1. Primary: whereNull('web_plan_id') - excludes plans with web_plan_id set
        // 2. Secondary: Date range matching - excludes plans whose start_date and end_date
        //    exactly match any assignment (catches edge cases where web_plan_id might be NULL)
        final uniquePlans = <Map<String, dynamic>>[];
        final seenIds = <int>{};
        
        // Try to get assignments to cross-reference for date range matching
        // This helps catch assigned plans that might have web_plan_id = NULL
        // BACKEND FIX: Some assigned plans may have web_plan_id = NULL but match assignments by date range
        // This cross-reference ensures we catch those edge cases
        List<Map<String, dynamic>> assignments = [];
        try {
          if (Get.isRegistered<SchedulesController>()) {
            final schedulesController = Get.find<SchedulesController>();
            // Ensure assignments are loaded if not already
            if (schedulesController.assignments.isEmpty) {
              print('🔍 Plans - Assignments not loaded, loading now for cross-reference...');
              await schedulesController.loadSchedulesData();
            }
            assignments = List<Map<String, dynamic>>.from(schedulesController.assignments);
            print('🔍 Plans - Found ${assignments.length} assignments for cross-reference');
            
            // Log all assignment IDs for debugging
            if (assignments.isNotEmpty) {
              final assignmentIds = assignments.map((a) => a['id']?.toString() ?? 'N/A').toList();
              final webPlanIds = assignments.map((a) => a['web_plan_id']?.toString() ?? 'N/A').toList();
              print('🔍 Plans - Assignment IDs: $assignmentIds');
              print('🔍 Plans - Assignment web_plan_ids: $webPlanIds');
            }
          }
        } catch (e) {
          print('⚠️ Plans - Could not access SchedulesController for assignments: $e');
          print('⚠️ Plans - Will rely on other assignment indicators (web_plan_id, assigned_by, etc.)');
        }
        
        // CRITICAL: Create a set of all assignment-related IDs for quick lookup
        // This includes assignment IDs, web_plan_ids, and plan_ids from assignments
        final Set<int> assignmentRelatedIds = {};
        for (final assignment in assignments) {
          final assignId = int.tryParse(assignment['id']?.toString() ?? '');
          final assignWebPlanId = int.tryParse(assignment['web_plan_id']?.toString() ?? '');
          final assignPlanId = int.tryParse(assignment['plan_id']?.toString() ?? '');
          
          if (assignId != null) assignmentRelatedIds.add(assignId);
          if (assignWebPlanId != null) assignmentRelatedIds.add(assignWebPlanId);
          if (assignPlanId != null) assignmentRelatedIds.add(assignPlanId);
        }
        print('🔍 Plans - Assignment-related IDs set: $assignmentRelatedIds');
        
        for (final plan in manualRes) {
          final planMap = Map<String, dynamic>.from(plan);
          final planId = int.tryParse(planMap['id']?.toString() ?? '');
          final planType = planMap['plan_type']?.toString().toLowerCase();
          final createdBy = planMap['created_by'];
          final assignedBy = planMap['assigned_by'];
          final assignmentId = planMap['assignment_id'];
          final webPlanId = planMap['web_plan_id'];
          final startDate = planMap['start_date'];
          final endDate = planMap['end_date'];
          
          // Check if this is an assigned plan (exclude these)
          // CRITICAL: web_assigned plans belong in Schedules tab, not Plans tab
          // ANY indicator of assignment means this plan belongs in Schedules tab
          // Backend should have filtered these out, but we check again as a safety measure
          final trainerId = planMap['trainer_id'];
          final assignedAt = planMap['assigned_at'];
          final status = planMap['status']?.toString().toUpperCase();
          
          bool isAssignedPlan = planType == 'assigned' || 
                                planType == 'web_assigned' ||
                                assignedBy != null || 
                                assignmentId != null ||
                                webPlanId != null ||
                                trainerId != null || // Has trainer_id (assigned by trainer)
                                assignedAt != null || // Has assigned_at timestamp
                                status == 'PLANNED' || // Status indicates assigned plan
                                status == 'ACTIVE' ||
                                planType == 'ai_generated' ||
                                planType == 'daily' ||
                                planType == 'schedule';
          
        // CRITICAL: Check if this plan ID is in the assignment-related IDs set
        // This is the fastest way to check if a plan is linked to any assignment
        if (!isAssignedPlan && planId != null && assignmentRelatedIds.contains(planId)) {
          isAssignedPlan = true;
          print('⚠️ Plans - Plan $planId is in assignment-related IDs set - excluding from manual plans');
        }
        
        // CRITICAL: Also check if this plan ID matches any assignment's web_plan_id or plan ID
        // This catches cases where the plan is linked to an assignment (redundant but thorough)
        if (!isAssignedPlan && assignments.isNotEmpty) {
          for (final assignment in assignments) {
            final assignWebPlanId = assignment['web_plan_id'];
            final assignPlanId = assignment['plan_id'];
            final assignId = assignment['id'];
            
            // If plan ID matches assignment's web_plan_id, plan_id, or assignment id, it's assigned
            if (planId != null && (
                (assignWebPlanId != null && planId == int.tryParse(assignWebPlanId.toString())) ||
                (assignPlanId != null && planId == int.tryParse(assignPlanId.toString())) ||
                (assignId != null && planId == int.tryParse(assignId.toString()))
              )) {
              isAssignedPlan = true;
              print('⚠️ Plans - Plan $planId matches assignment ${assignment['id']} by ID - excluding from manual plans');
              break;
            }
          }
        }
          
          // CRITICAL: Additional check for edge cases where web_plan_id might be NULL
          // but the plan matches an assignment by date range (backend fix scenario)
          // Check if plan's date range matches any assignment's date range
          if (!isAssignedPlan && startDate != null && endDate != null && assignments.isNotEmpty) {
            try {
              final planStartDate = DateTime.tryParse(startDate.toString());
              final planEndDate = DateTime.tryParse(endDate.toString());
              
              if (planStartDate != null && planEndDate != null) {
                // Normalize dates to compare only date part (ignore time)
                final planStartNormalized = DateTime(planStartDate.year, planStartDate.month, planStartDate.day);
                final planEndNormalized = DateTime(planEndDate.year, planEndDate.month, planEndDate.day);
                
                for (final assignment in assignments) {
                  final assignmentStartDate = assignment['start_date'];
                  final assignmentEndDate = assignment['end_date'];
                  
                  if (assignmentStartDate != null && assignmentEndDate != null) {
                    final assignStart = DateTime.tryParse(assignmentStartDate.toString());
                    final assignEnd = DateTime.tryParse(assignmentEndDate.toString());
                    
                    if (assignStart != null && assignEnd != null) {
                      final assignStartNormalized = DateTime(assignStart.year, assignStart.month, assignStart.day);
                      final assignEndNormalized = DateTime(assignEnd.year, assignEnd.month, assignEnd.day);
                      
                      // If dates exactly match, this is likely an assigned plan
                      if (planStartNormalized == assignStartNormalized && 
                          planEndNormalized == assignEndNormalized) {
                        isAssignedPlan = true;
                        print('⚠️ Plans - Plan $planId matches assignment ${assignment['id']} by date range - excluding from manual plans');
                        break;
                      }
                    }
                  }
                }
              }
            } catch (e) {
              print('⚠️ Plans - Error checking date range match: $e');
            }
          }
          
          // Include ONLY manual plans created by the user
          // CRITICAL: If plan has ANY assignment indicators, it's NOT a manual plan
          // Even if plan_type is null/empty, if it has assignedBy/assignmentId/webPlanId, exclude it
          final isManualPlan = !isAssignedPlan && // Must NOT be an assigned plan
                              (planType == 'manual' || planType == null || planType == '') && 
                              (createdBy == null || createdBy == userId); // Allow null createdBy or match userId
          
          print('🔍 Plans - Checking plan $planId:');
          print('🔍   - plan_type: $planType');
          print('🔍   - created_by: $createdBy (type: ${createdBy.runtimeType})');
          print('🔍   - userId: $userId (type: ${userId.runtimeType})');
          print('🔍   - assigned_by: $assignedBy');
          print('🔍   - assignment_id: $assignmentId');
          print('🔍   - web_plan_id: $webPlanId');
          print('🔍   - trainer_id: $trainerId');
          print('🔍   - assigned_at: $assignedAt');
          print('🔍   - status: $status');
          print('🔍   - start_date: $startDate');
          print('🔍   - end_date: $endDate');
          print('🔍   - isAssignedPlan: $isAssignedPlan');
          print('🔍   - isManualPlan: $isManualPlan');
          print('🔍   - Will include: ${isManualPlan && !isAssignedPlan}');
          print('🔍   - createdBy == userId: ${createdBy == userId}');
          print('🔍   - createdBy == null: ${createdBy == null}');
          print('🔍   - (createdBy == null || createdBy == userId): ${createdBy == null || createdBy == userId}');
          
          if (!isManualPlan) {
            print('❌ Plans - REJECTED: Not identified as manual plan (plan_type: $planType, created_by: $createdBy)');
          }
          if (isAssignedPlan) {
            print('❌ Plans - REJECTED: Identified as assigned plan (has assignment indicators)');
          }
          
          if (planId != null && !seenIds.contains(planId) && isManualPlan && !isAssignedPlan) {
            seenIds.add(planId);
            
            // Extract approval_status from plan data and store it in both places
            if (planMap['approval_status'] != null) {
              final approvalStatus = planMap['approval_status'].toString().toLowerCase();
              if (approvalStatus.isNotEmpty && approvalStatus != 'null') {
                planApprovalStatus[planId] = approvalStatus;
                // Also ensure it's stored in the plan map itself (normalize to lowercase)
                planMap['approval_status'] = approvalStatus;
                
                // IMPORTANT: If plan is approved, also extract and store approval_id
                if (approvalStatus == 'approved' && planToApprovalId[planId] == null) {
                  final approvalId = planMap['approval_id'];
                  if (approvalId != null) {
                    final approvalIdInt = int.tryParse(approvalId.toString());
                    if (approvalIdInt != null) {
                      planToApprovalId[planId] = approvalIdInt;
                      await _persistApprovalIdCache();
                      print('✅ Plans - Stored approval_id $approvalIdInt for approved plan $planId from plan data');
                    }
                  } else {
                    print('⚠️ Plans - Plan $planId is approved but approval_id not in plan data');
                    print('⚠️ Plans - Will need to find approval_id from training_approvals table');
                  }
                }
              }
            } else {
              // If not in plan data, check cache and add it to plan map
              final cachedStatus = planApprovalStatus[planId];
              if (cachedStatus != null && cachedStatus.isNotEmpty && cachedStatus != 'none') {
                planMap['approval_status'] = cachedStatus;
              }
            }
            
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
        
        // Normalize items to ensure minutes field is properly set BEFORE assigning
        for (final plan in uniquePlans) {
          _normalizePlanItemsForMinutes(plan);
        }
        
        // FINAL SAFETY CHECK: Remove any plans that might have slipped through
        // Double-check all plans against assignment-related IDs
        final finalFilteredPlans = uniquePlans.where((plan) {
          final planId = int.tryParse(plan['id']?.toString() ?? '');
          if (planId == null) return false;
          
          // If plan ID is in assignment-related IDs, exclude it
          if (assignmentRelatedIds.contains(planId)) {
            print('⚠️ Plans - FINAL CHECK: Removing plan $planId (found in assignment-related IDs)');
            return false;
          }
          
          // Double-check assignment indicators
          final hasWebPlanId = plan['web_plan_id'] != null;
          final hasAssignedBy = plan['assigned_by'] != null;
          final hasAssignmentId = plan['assignment_id'] != null;
          final hasTrainerId = plan['trainer_id'] != null;
          
          if (hasWebPlanId || hasAssignedBy || hasAssignmentId || hasTrainerId) {
            print('⚠️ Plans - FINAL CHECK: Removing plan $planId (has assignment indicators)');
            return false;
          }
          
          return true;
        }).toList();
        
        print('🔍 Plans - Final filtered plans: ${finalFilteredPlans.length} (removed ${uniquePlans.length - finalFilteredPlans.length} in final check)');
        
        if (!isClosed) manualPlans.assignAll(finalFilteredPlans);
        
        // CRITICAL: Do NOT show all plans if filtering results in empty list
        // This ensures assigned plans never appear in Plans tab
        if (finalFilteredPlans.isEmpty && manualRes.isNotEmpty) {
          print('⚠️ Plans - No manual plans passed filtering after checking ${manualRes.length} plans');
          print('⚠️ Plans - This is expected if all plans are assigned plans (belong in Schedules tab)');
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
      // Sending AI plan for approval
      
      // TEMPORARY DEBUG: Check if this is actually an AI plan
      final planType = plan['plan_type']?.toString().toLowerCase();
      final hasAiIndicators = plan.containsKey('exercise_plan_category') || 
                              plan.containsKey('user_level');
      
      
      // TEMPORARY DEBUG: If this doesn't look like an AI plan, throw an error
      if (planType != 'ai_generated' && !hasAiIndicators) {
        throw Exception('This plan does not appear to be an AI-generated plan. Plan type: $planType, AI indicators: $hasAiIndicators');
      }
      
      // First, fetch the complete plan details with items
      final planId = int.tryParse(plan['id']?.toString() ?? '');
      if (planId == null) {
        throw Exception('Invalid plan ID');
      }
      
      // Fetching complete plan details
      final completePlan = await _aiService.getGenerated(planId);
      
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
      
      // AI plan sent for approval successfully
      
      // Update the plan's approval status locally
      if (planId != null && result['id'] != null) {
        final approvalId = result['id'];
        planToApprovalId[planId] = approvalId;
        planApprovalStatus[planId] = 'pending'; // Set initial status to pending
        await _persistApprovalIdCache();
        
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
      // Sending manual plan for approval
      
      // First, fetch the complete plan details with items
      final planId = int.tryParse(plan['id']?.toString() ?? '');
      if (planId == null) {
        throw Exception('Invalid plan ID');
      }
      
      // DEBUG: Check plan type indicators before fetching
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
        // Normalize weight fields
        m['weight_min_kg'] = m['weight_min_kg'] ?? m['weight_min'] ?? m['min_weight'] ?? m['min_weight_kg'];
        m['weight_max_kg'] = m['weight_max_kg'] ?? m['weight_max'] ?? m['max_weight'] ?? m['max_weight_kg'];
        // Normalize minutes: ensure both minutes and training_minutes are set
        final int minutes = int.tryParse(m['minutes']?.toString() ?? '') ?? 
                           int.tryParse(m['training_minutes']?.toString() ?? '') ?? 0;
        m['minutes'] = minutes;
        m['training_minutes'] = minutes;
        return m;
      }).toList();
      List<Map<String, dynamic>> exercisesDetails = [];
      if (completePlan['exercises_details'] is List) {
        exercisesDetails = (completePlan['exercises_details'] as List).map((e) {
          final itemMap = Map<String, dynamic>.from(e as Map);
          // Normalize minutes in exercises_details too
          final int minutes = int.tryParse(itemMap['minutes']?.toString() ?? '') ?? 
                             int.tryParse(itemMap['training_minutes']?.toString() ?? '') ?? 0;
          itemMap['minutes'] = minutes;
          itemMap['training_minutes'] = minutes;
          return itemMap;
        }).toList();
      } else if (completePlan['exercises_details'] is String) {
        try {
          final parsed = jsonDecode(completePlan['exercises_details'] as String) as List<dynamic>;
          exercisesDetails = parsed.map((e) {
            final itemMap = Map<String, dynamic>.from(e as Map);
            // Normalize minutes in exercises_details too
            final int minutes = int.tryParse(itemMap['minutes']?.toString() ?? '') ?? 
                               int.tryParse(itemMap['training_minutes']?.toString() ?? '') ?? 0;
            itemMap['minutes'] = minutes;
            itemMap['training_minutes'] = minutes;
            return itemMap;
          }).toList();
        } catch (_) {}
      }
      
      
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
      // Always use normalized exercisesDetails if available
      if (exercisesDetails.isNotEmpty) {
        normalizedPlan['exercises_details'] = exercisesDetails;
      } else if (items.isNotEmpty) {
        // If exercisesDetails is empty, create it from items (mirror items structure)
        normalizedPlan['exercises_details'] = items.map((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
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
        if (exercisesDetails.isNotEmpty) 
          'exercises_details': exercisesDetails,
        'daily_plans': safeDailyPlans,
        'plan_data': normalizedPlan,
        'requested_at': DateTime.now().toIso8601String(),
      };
      
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
      // Debug: Log minutes for each item
      for (int i = 0; i < (payload['items'] as List).length; i++) {
        final item = (payload['items'] as List)[i];
        print('🔍   - item[$i] (${item['workout_name'] ?? 'Unknown'}): minutes=${item['minutes']}, training_minutes=${item['training_minutes']}');
      }
      print('🔍   - exercises_details count: ${exercisesDetails.length}');
      if (exercisesDetails.isNotEmpty) {
        for (int i = 0; i < exercisesDetails.length; i++) {
          final item = exercisesDetails[i];
          print('🔍   - exercises_details[$i] (${item['workout_name'] ?? 'Unknown'}): minutes=${item['minutes']}, training_minutes=${item['training_minutes']}');
        }
      }
      print('🔍   - daily_plans count: ${(payload['daily_plans'] as List).length}');
      print('🔍   - requested_at: ${payload['requested_at']} (type: ${payload['requested_at'].runtimeType})');
      print('🔍   - plan_data keys: ${normalizedPlan.keys.toList()}');
      
      final result = await _approvalService.sendForApproval(
        source: 'manual',
        payload: payload,
      );
      
      // Manual plan sent for approval successfully
      
      // Update the plan's approval status locally
      if (planId != null && result['id'] != null) {
        final approvalId = int.tryParse(result['id'].toString()) ?? result['id'] as int?;
        if (approvalId != null) {
          planToApprovalId[planId] = approvalId;
        planApprovalStatus[planId] = 'pending'; // Set initial status to pending
        await _persistApprovalIdCache();
          
          // Immediately refresh approval status from backend to get accurate status
          try {
            await refreshApprovalStatusFromBackend();
            print('✅ PlansController - Approval status refreshed from backend');
          } catch (e) {
            print('⚠️ PlansController - Error refreshing approval status: $e');
          }
        
        // Force UI refresh to show "Pending" status
        if (!isClosed) update();
        }
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
    
    // Starting plan $planId
    
    // Normalize items/exercises_details to Lists to avoid type errors from String JSON
    try {
      List<Map<String, dynamic>> normItems = [];
      if (plan['items'] is List) {
        normItems = List<Map<String, dynamic>>.from((plan['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (plan['items'] is String && (plan['items'] as String).trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(plan['items'] as String) as List<dynamic>;
          normItems = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }
      List<Map<String, dynamic>> normExercises = [];
      if (plan['exercises_details'] is List) {
        normExercises = List<Map<String, dynamic>>.from((plan['exercises_details'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (plan['exercises_details'] is String && (plan['exercises_details'] as String).trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(plan['exercises_details'] as String) as List<dynamic>;
          normExercises = parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }
      if (normItems.isNotEmpty) plan['items'] = normItems;
      if (normExercises.isNotEmpty) plan['exercises_details'] = normExercises;
    } catch (_) {}
    
    // Check if there's already an active plan (from any tab)
    final existingActivePlan = await _getAnyActivePlan();
    if (existingActivePlan != null) {
      final currentPlanId = int.tryParse(existingActivePlan['id']?.toString() ?? '');
      
      // If trying to start the same plan, just return
      if (currentPlanId == planId) {
        return;
      }
      
      // Show confirmation dialog to stop current plan
      final shouldStopCurrent = await _showStopCurrentPlanDialog(existingActivePlan);
      if (!shouldStopCurrent) {
        return;
      }
      
      // Stop the current active plan from any tab
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
    
    // Plan type: ${isAiPlan ? 'AI' : 'Manual'}
    
    // First, check if the original plan already has workout data
    bool hasWorkoutData = false;
    final List? itemsList = plan['items'] is List ? plan['items'] as List : null;
    final List? exList = plan['exercises_details'] is List ? plan['exercises_details'] as List : null;
    if ((itemsList != null && itemsList.isNotEmpty) || (exList != null && exList.isNotEmpty)) {
      hasWorkoutData = true;
    }
    
    if (hasWorkoutData) {
      // Use the original plan data directly
    _startedPlans[planId] = true;
    // Ensure daily_plans present on active plan using client rotation if backend didn't provide
    try {
      final List<Map<String, dynamic>> workoutItems = (plan['items'] as List? ?? []).cast<Map<String, dynamic>>();
      if ((plan['daily_plans'] as List?) == null || (plan['daily_plans'] as List?)!.isEmpty) {
        final generatedDays = _generateDailyPlans(
          workoutItems,
          startDate: plan['start_date'] != null ? DateTime.tryParse(plan['start_date'].toString()) : null,
          totalDays: _getTotalDays(plan),
        );
        plan['daily_plans'] = generatedDays;
      }
    } catch (_) {}
    // Ensure approval_id is included in active plan data for stats filtering
    if (plan['approval_id'] == null) {
      final approvalId = getApprovalIdForPlan(planId);
      if (approvalId != null) {
        plan['approval_id'] = approvalId;
      } else {
        // If plan is approved but approval_id is missing, this is a problem
        final approvalStatus = plan['approval_status']?.toString().toLowerCase();
        if (approvalStatus == 'approved') {
          print('⚠️ PlansController - WARNING: Plan $planId is approved but approval_id is missing!');
          print('⚠️ PlansController - This will prevent daily_training_plans from being created and stats from being tracked');
          print('⚠️ PlansController - Backend should include approval_id in plan data when approved');
        }
      }
    }
    
    _activePlan.value = plan;
    
    // ALWAYS check database first (database is source of truth), then fall back to cache
    // This ensures we resume correctly even if cache is cleared on app restart
    int? cachedDay;
    try {
      final completedDay = await _getLastCompletedDayFromDatabase(planId, isAiPlan ? 'ai_generated' : 'manual');
      if (completedDay != null) {
        // completedDay is 1-based (from daily_plans), _currentDay is 0-based
        // If completedDay = 2 (Day 2 completed), we should resume at Day 3 (index 2 in 0-based)
        final nextDay = completedDay; // completedDay is 1-based, use directly as 0-based index for next day
        _currentDay[planId.toString()] = nextDay;
        _persistCurrentDayToCache(planId, nextDay);
        cachedDay = nextDay;
      } else {
        // If no completed days in database, check cache as fallback
        await _loadCurrentDayFromCache(planId);
        cachedDay = _currentDay[planId.toString()];
      }
    } catch (e) {
      // If database check fails, fall back to cache
      await _loadCurrentDayFromCache(planId);
      cachedDay = _currentDay[planId.toString()];
    }
    
    if (cachedDay == null) {
      // First time starting this plan, start at day 0
    _currentDay[planId.toString()] = 0;
      _persistCurrentDayToCache(planId, 0);
    }
    
    _persistStartedPlansToCache();
    _persistActivePlanSnapshot();
      if (!isClosed) {
        update(); // Force UI refresh
      }
      
      // Refresh stats when plan is started to show current values
      try {
        final statsController = Get.find<StatsController>();
        await statsController.refreshStats(forceSync: true);
      } catch (e) {
        print('⚠️ PlansController - Error refreshing stats for started plan: $e');
      }
      
      return;
    }
    
    // If no workout data in original plan, try to fetch full details
    try {
      Map<String, dynamic> fullPlanData;
      
      if (isAiPlan) {
        // Fetch full AI plan details
        // Fetching full AI plan details
        try {
          fullPlanData = await _aiService.getGenerated(planId);
        } catch (e) {
          print('❌ PlansController - Failed to fetch AI plan: $e');
          fullPlanData = Map<String, dynamic>.from(plan);
        }
      } else {
        // Fetch full manual plan details
        // Fetching full manual plan details
        try {
          fullPlanData = await _manualService.getPlan(planId);
        } catch (e) {
          print('❌ PlansController - Failed to fetch manual plan: $e');
          fullPlanData = Map<String, dynamic>.from(plan);
        }
      }
      
      
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
      
      // Ensure approval_id is included in active plan data for stats filtering
      if (fullPlanData['approval_id'] == null) {
        final approvalId = getApprovalIdForPlan(planId);
        if (approvalId != null) {
          fullPlanData['approval_id'] = approvalId;
          print('🔍 PlansController - Added approval_id $approvalId to active plan data (fetched path)');
        }
      }
      
      _activePlan.value = fullPlanData;
      
      // ALWAYS check database first (database is source of truth), then fall back to cache
      // This ensures we resume correctly even if cache is cleared on app restart
      int? cachedDay;
      try {
        print('📅 PlansController - Checking database for completed days (database is source of truth)...');
        final completedDay = await _getLastCompletedDayFromDatabase(planId, isAiPlan ? 'ai_generated' : 'manual');
        if (completedDay != null) {
          // completedDay is 1-based (from daily_plans), _currentDay is 0-based
          // If completedDay = 2 (Day 2 completed), we should resume at Day 3 (index 2 in 0-based)
          final nextDay = completedDay; // completedDay is 1-based, use directly as 0-based index for next day
          _currentDay[planId.toString()] = nextDay;
          _persistCurrentDayToCache(planId, nextDay);
          print('📅 PlansController - ✅ Found completed day $completedDay (1-based) in database, resuming at day $nextDay (0-based index, Day ${completedDay + 1})');
          cachedDay = nextDay;
        } else {
          // If no completed days in database, check cache as fallback
          await _loadCurrentDayFromCache(planId);
          cachedDay = _currentDay[planId.toString()];
          if (cachedDay != null) {
            print('📅 PlansController - Using cached day $cachedDay as fallback');
          }
        }
      } catch (e) {
        print('⚠️ PlansController - Error checking database for completed days: $e');
        // If database check fails, fall back to cache
        await _loadCurrentDayFromCache(planId);
        cachedDay = _currentDay[planId.toString()];
        if (cachedDay != null) {
          print('📅 PlansController - Using cached day $cachedDay after database error');
        }
      }
      
      if (cachedDay == null) {
        // First time starting this plan, start at day 0
      _currentDay[planId.toString()] = 0;
        _persistCurrentDayToCache(planId, 0);
        print('📅 PlansController - Starting new plan $planId at day 0');
      } else {
        // Resume from previous progress
        print('📅 PlansController - Resuming plan $planId at day $cachedDay');
      }
      
      // Store daily training plan data in the database (only if we have workout data)
      final workoutItems = (fullPlanData['items'] as List? ?? []).cast<Map<String, dynamic>>();
      if (workoutItems.isNotEmpty) {
        try {
          // Prefer backend-approved daily plan structure when available
          List<Map<String, dynamic>> dailyPlans = [];
          final int? approvalId = planToApprovalId[planId];
          // Get plan_category from the plan (will get from approval if available)
          String planCategory = fullPlanData['exercise_plan_category']?.toString() ?? 
                               fullPlanData['plan_category']?.toString() ??
                               plan['exercise_plan_category']?.toString() ?? 
                               plan['plan_category']?.toString() ??
                               plan['name']?.toString() ?? 
                               (isAiPlan ? 'AI Generated Plan' : 'Manual Plan');
          String userLevel = fullPlanData['user_level']?.toString() ?? 
                           plan['user_level']?.toString() ?? 
                           'Beginner';
          
          if (approvalId != null) {
            try {
              final approval = await _approvalService.getApproval(approvalId);
              // Use approval's plan_category and user_level if available
              planCategory = approval['exercise_plan_category']?.toString() ?? 
                           approval['plan_category']?.toString() ?? 
                           planCategory;
              userLevel = approval['user_level']?.toString() ?? userLevel;
              dailyPlans = _buildDailyPlansFromApproval(
                approval, 
                workoutItems,
                planCategory: planCategory,
                userLevel: userLevel,
              );
              print('🔍 PlansController - Built ${dailyPlans.length} daily plans from approval');
            } catch (e) {
              print('⚠️ PlansController - Could not build daily plans from approval: $e');
            }
          }

          // Fallback to client-generated rotation if approval has no per-day plan
          if (dailyPlans.isEmpty) {
            dailyPlans = _generateDailyPlans(
              workoutItems,
              startDate: fullPlanData['start_date'] != null 
                  ? DateTime.tryParse(fullPlanData['start_date'].toString())
                  : null,
              totalDays: _getTotalDays(fullPlanData),
            );
          }
          
          if (dailyPlans.isNotEmpty) {
            // Attach to in-memory plan so UI uses backend distribution immediately
            fullPlanData['daily_plans'] = dailyPlans;
            // Get plan_category from the plan (API expects plan_category not exercise_plan_category)
            final String planCategory = fullPlanData['exercise_plan_category']?.toString() ?? 
                                       fullPlanData['plan_category']?.toString() ??
                                       plan['exercise_plan_category']?.toString() ?? 
                                       plan['plan_category']?.toString() ??
                                       plan['name']?.toString() ?? 
                                       (isAiPlan ? 'AI Generated Plan' : 'Manual Plan');
            
            // Get user_level from the plan
            final String userLevel = fullPlanData['user_level']?.toString() ?? 
                                   plan['user_level']?.toString() ?? 
                                   'Beginner';
            
            // Ensure plan_category and user_level are included in each daily plan
            for (final dailyPlan in dailyPlans) {
              dailyPlan['plan_category'] = dailyPlan['plan_category'] ?? 
                                          dailyPlan['exercise_plan_category'] ?? 
                                          planCategory;
              dailyPlan['user_level'] = dailyPlan['user_level'] ?? userLevel;
            }
            
            print('📤 PlansController - Storing ${dailyPlans.length} daily plans for plan $planId');
            print('📤 PlansController - First day workouts: ${dailyPlans.isNotEmpty ? dailyPlans[0]['workouts']?.length ?? 0 : 0}');
            print('📤 PlansController - Plan category: $planCategory');
            print('📤 PlansController - User level: $userLevel');
            
            // BACKEND BEHAVIOR (syncDailyPlansFromManualPlanHelper / syncDailyPlansFromAIPlanHelper):
            // - Finds the last completed daily plan by plan_date (not completed_at)
            // - Skips days with plan_date <= lastCompletedDate
            // - Creates/updates only days after the last completed date
            // - This preserves completed days and continues from the next day
            // - Handles duplicate key errors using the new unique constraint:
            //   (user_id, plan_date, plan_type, source_plan_id)
            // 
            // CRITICAL: Multiple Plans Support (Backend Schema Change)
            // The backend now supports multiple plans of the same type on the same date by including
            // source_plan_id in the unique constraint: (user_id, plan_date, plan_type, source_plan_id)
            // This means multiple manual plans (e.g., "Home Workout" + "Gym Workout") or multiple
            // AI plans (e.g., "Beginner Plan" + "Advanced Plan") can have daily plans on the same
            // date, distinguished by their source_plan_id (approval_id or plan_id).
            // Each plan tracks completion independently.
            // 
            // FRONTEND BEHAVIOR:
            // - Stores all daily plans when plan is started
            // - Backend sync handles skipping completed days automatically
            // - Backend handles duplicate key conflicts for multiple plans on same date
            try {
              final result = await _dailyTrainingService.storeDailyTrainingPlan(
                planId: planId,
                planType: isAiPlan ? 'ai_generated' : 'manual',
                dailyPlans: dailyPlans,
                userId: userId ?? 0,
                planCategory: planCategory,
                userLevel: userLevel,
              );
              
              print('✅ PlansController - Daily training plan data stored successfully');
              print('✅ PlansController - Storage result: $result');
            } catch (e, stackTrace) {
              print('❌ PlansController - Failed to store daily training plan data: $e');
              print('❌ PlansController - Stack trace: $stackTrace');
              // Continue anyway - plan can still be started without stored daily plans
            }
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
      // Debug: print all days distribution to console
      _debugPrintAllDaysForActivePlan();
      
      // Refresh stats when plan is started to show current values
      try {
        final statsController = Get.find<StatsController>();
        print('🔄 PlansController - Refreshing stats after starting plan $planId...');
        await statsController.refreshStats(forceSync: true);
        print('✅ PlansController - Stats refreshed for started plan $planId');
      } catch (e) {
        print('⚠️ PlansController - Error refreshing stats for started plan: $e');
      }
    } catch (e) {
      print('❌ PlansController - Error fetching full plan data: $e');
      print('❌ PlansController - Using original plan data as fallback');
      print('❌ PlansController - Original plan items: ${plan['items']?.length ?? 0}');
      print('❌ PlansController - Original plan exercises_details: ${plan['exercises_details']?.length ?? 0}');
      
      // Fallback to original plan data
      _startedPlans[planId] = true;
      _activePlan.value = plan;
      
      // ALWAYS check database first (database is source of truth), then fall back to cache
      // This ensures we resume correctly even if cache is cleared on app restart
      int? cachedDay;
      try {
        print('📅 PlansController - Checking database for completed days (database is source of truth)...');
        final completedDay = await _getLastCompletedDayFromDatabase(planId, isAiPlan ? 'ai_generated' : 'manual');
        if (completedDay != null) {
          // completedDay is 1-based (from daily_plans), _currentDay is 0-based
          // If completedDay = 2 (Day 2 completed), we should resume at Day 3 (index 2 in 0-based)
          final nextDay = completedDay; // completedDay is 1-based, use directly as 0-based index for next day
          _currentDay[planId.toString()] = nextDay;
          _persistCurrentDayToCache(planId, nextDay);
          print('📅 PlansController - ✅ Found completed day $completedDay (1-based) in database, resuming at day $nextDay (0-based index, Day ${completedDay + 1})');
          cachedDay = nextDay;
        } else {
          // If no completed days in database, check cache as fallback
          await _loadCurrentDayFromCache(planId);
          cachedDay = _currentDay[planId.toString()];
          if (cachedDay != null) {
            print('📅 PlansController - Using cached day $cachedDay as fallback');
          }
        }
      } catch (e) {
        print('⚠️ PlansController - Error checking database for completed days: $e');
        // If database check fails, fall back to cache
        await _loadCurrentDayFromCache(planId);
        cachedDay = _currentDay[planId.toString()];
        if (cachedDay != null) {
          print('📅 PlansController - Using cached day $cachedDay after database error');
        }
      }
      
      if (cachedDay == null) {
        // First time starting this plan, start at day 0
      _currentDay[planId.toString()] = 0;
        _persistCurrentDayToCache(planId, 0);
        print('📅 PlansController - Starting new plan $planId at day 0');
      } else {
        // Resume from previous progress
        print('📅 PlansController - Resuming plan $planId at day $cachedDay');
      }
      
      _persistStartedPlansToCache();
      _persistActivePlanSnapshot();
      if (!isClosed) {
        update();
      }
      // Debug: print all days distribution to console
      _debugPrintAllDaysForActivePlan();
      
      // Refresh stats when plan is started to show current values
      try {
        final statsController = Get.find<StatsController>();
        print('🔄 PlansController - Refreshing stats after starting plan $planId...');
        await statsController.refreshStats(forceSync: true);
        print('✅ PlansController - Stats refreshed for started plan $planId');
      } catch (e) {
        print('⚠️ PlansController - Error refreshing stats for started plan: $e');
      }
    }
  }

  // Debug helper: print all days' workouts for the active plan
  void _debugPrintAllDaysForActivePlan() {
    try {
      final active = _activePlan.value;
      if (active == null) {
        print('⚠️ PlansController - _debugPrintAllDaysForActivePlan: No active plan');
        return;
      }
      final int planId = int.tryParse(active['id']?.toString() ?? '') ?? 0;
      final int totalDays = _getTotalDays(active);
      print('🗓️ PlansController - Printing all days for plan $planId (totalDays=$totalDays)');
      for (int d = 0; d < totalDays; d++) {
        final dayWorkouts = _getDayWorkouts(active, d);
        final names = dayWorkouts.map((w) => (w['name'] ?? w['workout_name'] ?? w['exercise_name'] ?? 'Unknown').toString()).toList();
        print('📅 Day ${d + 1}: ${names.join(', ')}');
      }
      print('🗓️ PlansController - End of plan days print');
    } catch (e) {
      print('❌ PlansController - Error printing all days: $e');
    }
  }

  Future<void> stopPlan(Map<String, dynamic> plan) async {
    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
    if (planId == null) return;
    
    print('🛑 PlansController - Stopping plan $planId');
    _startedPlans[planId] = false;
    if (_activePlan.value != null && (_activePlan.value!['id']?.toString() ?? '') == planId.toString()) {
      _activePlan.value = null;
    }
    
    _persistStartedPlansToCache();
    _clearActivePlanSnapshotIfStopped();
    
    // Clear stats data for this plan when stopped
    try {
      final statsController = Get.find<StatsController>();
      final approvalId = planToApprovalId[planId];
      
      // Determine if this is an AI plan or manual plan
      final isAiPlan = plan.containsKey('ai_generated') || 
                      plan.containsKey('gemini_generated') ||
                      plan.containsKey('ai_plan_id') ||
                      plan.containsKey('request_id') ||
                      (plan.containsKey('exercise_plan_category') && plan.containsKey('user_level') && plan.containsKey('total_days'));
      
      print('🧹 PlansController - Clearing stats for stopped plan ID: $planId (type: ${isAiPlan ? 'AI' : 'Manual'}, approval_id: $approvalId)');
      await statsController.cleanupStatsForPlan(
        planId,
        assignmentId: null, // Manual/AI plans don't have assignment_id
        webPlanId: null, // Manual/AI plans don't have web_plan_id
      );
      print('✅ PlansController - Stats cleared for stopped plan $planId');
    } catch (e) {
      print('⚠️ PlansController - Error clearing stats for stopped plan: $e');
    }
    
    if (!isClosed) update(); // Force UI refresh
    print('🛑 PlansController - Plan $planId stopped, UI updated');
  }

  /// Stop the current active plan without requiring a plan parameter
  Future<void> _stopCurrentActivePlan() async {
    if (_activePlan.value == null) return;
    
    final currentPlan = _activePlan.value!;
    final planId = int.tryParse(currentPlan['id']?.toString() ?? '');
    if (planId == null) return;
    
    print('🛑 PlansController - Stopping current active plan $planId');
    _startedPlans[planId] = false;
    _activePlan.value = null;
    
    _persistStartedPlansToCache();
    _clearActivePlanSnapshotIfStopped();
    
    // Clear stats data for this plan when stopped
    try {
      final statsController = Get.find<StatsController>();
      final approvalId = planToApprovalId[planId];
      
      // Determine if this is an AI plan or manual plan
      final isAiPlan = currentPlan.containsKey('ai_generated') || 
                      currentPlan.containsKey('gemini_generated') ||
                      currentPlan.containsKey('ai_plan_id') ||
                      currentPlan.containsKey('request_id') ||
                      (currentPlan.containsKey('exercise_plan_category') && currentPlan.containsKey('user_level') && currentPlan.containsKey('total_days'));
      
      print('🧹 PlansController - Clearing stats for stopped current plan ID: $planId (type: ${isAiPlan ? 'AI' : 'Manual'}, approval_id: $approvalId)');
      await statsController.cleanupStatsForPlan(
        planId,
        assignmentId: null, // Manual/AI plans don't have assignment_id
        webPlanId: null, // Manual/AI plans don't have web_plan_id
      );
      print('✅ PlansController - Stats cleared for stopped current plan $planId');
    } catch (e) {
      print('⚠️ PlansController - Error clearing stats for stopped current plan: $e');
    }
    
    if (!isClosed) update(); // Force UI refresh
    print('🛑 PlansController - Current active plan $planId stopped, UI updated');
  }

  /// Check for active plans from any tab (Plans, Schedules, etc.)
  /// CRITICAL: Only returns active plans that belong to the current user
  Future<Map<String, dynamic>?> _getAnyActivePlan() async {
    final currentUserId = _profileController.user?.id;
    if (currentUserId == null) {
      print('⚠️ PlansController - No current user ID, cannot check for active plans');
      return null;
    }
    
    // Check Plans tab active plan
    if (_activePlan.value != null) {
      final plan = _activePlan.value!;
      final planUserId = plan['user_id'] as int?;
      
      // CRITICAL: Validate that the active plan belongs to the current user
      if (planUserId != null && planUserId == currentUserId) {
        print('🔍 PlansController - Found active plan in Plans tab: ${plan['id']} (user_id: $planUserId matches current user: $currentUserId)');
        return plan;
      } else {
        print('❌ PlansController - Active plan ${plan['id']} belongs to user $planUserId, but current user is $currentUserId - clearing invalid active plan');
        // Clear invalid active plan (belongs to different user)
        _activePlan.value = null;
        await _clearActivePlanFromCache();
      }
    }
    
    // Check Schedules tab active plan
    try {
      if (Get.isRegistered<SchedulesController>()) {
        final schedulesController = Get.find<SchedulesController>();
        if (schedulesController.activeSchedule != null) {
          final schedule = schedulesController.activeSchedule!;
          final scheduleUserId = schedule['user_id'] as int?;
          
          // CRITICAL: Validate that the active schedule belongs to the current user
          if (scheduleUserId != null && scheduleUserId == currentUserId) {
            print('🔍 PlansController - Found active plan in Schedules tab: ${schedule['id']} (user_id: $scheduleUserId matches current user: $currentUserId)');
            return schedule;
          } else {
            print('❌ PlansController - Active schedule ${schedule['id']} belongs to user $scheduleUserId, but current user is $currentUserId - this should be cleared by SchedulesController');
            // Don't clear here - SchedulesController should handle it, but log the issue
          }
        }
      }
    } catch (e) {
      print('⚠️ PlansController - Could not check SchedulesController: $e');
    }
    
    print('🔍 PlansController - No active plans found in any tab for current user: $currentUserId');
    return null;
  }

  /// Stop active plan from any tab
  Future<void> _stopAnyActivePlan() async {
    // Stop Plans tab active plan
    if (_activePlan.value != null) {
      print('🛑 PlansController - Stopping active plan from Plans tab');
      await _stopCurrentActivePlan();
    }
    
    // Stop Schedules tab active plan
    try {
      if (Get.isRegistered<SchedulesController>()) {
        final schedulesController = Get.find<SchedulesController>();
        if (schedulesController.activeSchedule != null) {
          print('🛑 PlansController - Stopping active plan from Schedules tab');
          await schedulesController.stopSchedule(schedulesController.activeSchedule!);
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
    // Return 0-based day index (Day 1 = 0, Day 2 = 1, Day 3 = 2, etc.)
    // This matches the internal storage format
    final day = _currentDay[planId.toString()] ?? 0;
    print('🔍 PlansController - getCurrentDay($planId) = $day (0-based, Day ${day + 1})');
    return day;
  }

  Future<void> setCurrentDay(int planId, int day) async {
    _currentDay[planId.toString()] = day;
    _persistCurrentDayToCache(planId, day);
    
    // Check if this day is completed and mark workouts accordingly
    await _checkAndMarkDayCompleted(planId, day);
    
    // Refresh reactive map (same as schedules)
    _currentDay.refresh();
    uiTick.value++;
    if (!isClosed) update();
  }
  
  /// Check if a specific day is completed and mark all workouts for that day as completed
  Future<void> _checkAndMarkDayCompleted(int planId, int day) async {
    try {
      final activePlan = _activePlan.value;
      if (activePlan == null) return;
      
      // Determine plan type
      final isAiPlan = activePlan.containsKey('ai_generated') || 
                      activePlan.containsKey('gemini_generated') ||
                      activePlan.containsKey('ai_plan_id') ||
                      activePlan.containsKey('request_id') ||
                      (activePlan.containsKey('exercise_plan_category') && activePlan.containsKey('user_level') && activePlan.containsKey('total_days'));
      final planType = isAiPlan ? 'ai_generated' : 'manual';
      
      // Get plan's start_date to calculate plan_date
      DateTime? planStartDate;
      if (activePlan['start_date'] != null) {
        planStartDate = DateTime.tryParse(activePlan['start_date'].toString());
      }
      planStartDate ??= DateTime.now();
      
      // Calculate plan_date for this day (day is 0-based in Plans controller)
      final utcDate = DateTime.utc(planStartDate.year, planStartDate.month, planStartDate.day);
      final dayOffset = day; // day is 0-based, so Day 1 = 0, Day 2 = 1, etc.
      final planDate = utcDate.add(Duration(days: dayOffset)).toIso8601String().split('T').first;
      
      print('🔍 PlansController - Checking if day ${day + 1} (plan_date: $planDate) is completed...');
      
      // Get approval_id for manual/AI plans
      int? approvalId = planToApprovalId[planId];
      if (approvalId == null) {
        approvalId = getApprovalIdForPlan(planId);
      }
      
      // Get all daily plans for this plan type
      final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: planType);
      
      final matchingDay = dailyPlans.firstWhereOrNull((dp) {
        final dpDate = dp['plan_date']?.toString().split('T').first;
        final dpPlanType = dp['plan_type']?.toString() ?? '';
        
        // For manual/AI plans, source_plan_id can be either approval_id OR plan_id (if approval_id is null)
        if (dpPlanType == 'manual' || dpPlanType == 'ai_generated') {
          final dpSourcePlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
          // Match by approval_id if available, otherwise match by plan_id (source_plan_id)
          return (approvalId != null && dpSourcePlanId == approvalId && dpDate == planDate) ||
                 (approvalId == null && dpSourcePlanId == planId && dpDate == planDate);
        }
        return false;
      });
      
      if (matchingDay != null) {
        final isCompleted = matchingDay['is_completed'] as bool? ?? false;
        final completedAt = matchingDay['completed_at'] as String?;
        print('🔍 PlansController - Day ${day + 1} completion status: is_completed=$isCompleted, completed_at=$completedAt');
        
        if (isCompleted) {
          // Day is completed, mark all workouts for this day as completed
          final dayWorkouts = _getDayWorkouts(activePlan, day);
          print('✅ PlansController - Day ${day + 1} is completed, marking ${dayWorkouts.length} workouts as completed');
          
          for (final workout in dayWorkouts) {
            final workoutName = workout['name']?.toString() ?? workout['workout_name']?.toString() ?? '';
            final safeName = workoutName.replaceAll(' ', '_');
            final minutesVal = _extractWorkoutMinutesFromMap(workout);
            final workoutKey = '${planId}_${day}_${safeName}_${minutesVal}';
            _workoutCompleted[workoutKey] = true;
            _workoutStarted[workoutKey] = false;
            _workoutRemainingMinutes[workoutKey] = 0;
            print('✅ PlansController - Marked workout "$workoutName" as completed (key: $workoutKey)');
          }
          
          // Force UI refresh to show completed workouts
          refreshUI();
        }
      } else {
        print('⚠️ PlansController - Could not find daily plan for day ${day + 1} (plan_date: $planDate, planId: $planId, approvalId: $approvalId)');
        print('⚠️ PlansController - Searched in ${dailyPlans.length} daily plans for planType: $planType');
      }
    } catch (e) {
      print('⚠️ PlansController - Error checking day completion: $e');
    }
  }

  // Public: return today's workouts for the active plan (same as schedules controller)
  List<Map<String, dynamic>> getActiveDayWorkouts() {
    final active = _activePlan.value;
    if (active == null) return [];
    final planId = int.tryParse(active['id']?.toString() ?? '') ?? 0;
    // Access reactive _currentDay to trigger rebuilds
    final currentDay = _currentDay[planId.toString()] ?? 0;
    print('🔍 PlansController - getActiveDayWorkouts: planId=$planId, currentDay=$currentDay');
    final workouts = _getDayWorkouts(active, currentDay);
    print('🔍 PlansController - getActiveDayWorkouts: returning ${workouts.length} workouts for day ${currentDay + 1}');
    return workouts;
  }

  // Public: get workouts for a specific day of a plan (for PlanDetailPage)
  List<Map<String, dynamic>> getDayWorkoutsForDay(Map<String, dynamic> plan, int dayIndex) {
    // dayIndex is 0-based (Day 1 = 0, Day 2 = 1, Day 3 = 2, etc.)
    print('🔍 PlansController - getDayWorkoutsForDay: dayIndex=$dayIndex (Day ${dayIndex + 1})');
    return _getDayWorkouts(plan, dayIndex);
  }

  // Workout tracking methods (similar to SchedulesController)
  final RxMap<String, bool> _workoutStarted = <String, bool>{}.obs;
  final RxMap<String, bool> _workoutCompleted = <String, bool>{}.obs;

  void startWorkout(String workoutKey, int totalMinutes) {
    _workoutStarted[workoutKey] = true;
    _workoutRemainingMinutes[workoutKey] = totalMinutes;
    _workoutCompleted[workoutKey] = false;
    
    // Start timer
    _startWorkoutTimer(workoutKey);
    if (!isClosed) update();
  }

  void forceCompleteWorkout(String workoutKey) {
    // Manually mark a workout as completed immediately (useful when API errors or for quick progression)
    _workoutStarted[workoutKey] = true;
    _workoutRemainingMinutes[workoutKey] = 0;
    _workoutCompleted[workoutKey] = true;
    if (!isClosed) update();
    // Store completion and advance day
    _storeWorkoutCompletion(workoutKey);
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

  void _checkDayCompletionAndAdvance(int planId, int day) {
    // Get the active plan first (same approach as schedules controller)
    final activePlan = _activePlan.value;
    if (activePlan == null) {
      print('⚠️ PlansController - No active plan found for plan $planId');
      return;
    }
    
    // Verify the plan ID matches
    final activePlanId = int.tryParse(activePlan['id']?.toString() ?? '') ?? 0;
    if (activePlanId != planId) {
      print('⚠️ PlansController - Active plan ID ($activePlanId) does not match plan ID ($planId)');
      return;
    }
    
    // Get all workouts for current day using the same approach as schedules controller
    final dayWorkouts = _getDayWorkouts(activePlan, day);
    if (dayWorkouts.isEmpty) {
      print('⚠️ PlansController - No workouts found for plan $planId day ${day + 1}');
      return;
    }
    
    // Build workout key prefix and match actual started/completed keys.
    // UI keys include minutes and normalized names, so use prefix match: planId_day_
    final String keyPrefix = '${planId}_${day}_';
    final List<String> keysForDay = _workoutCompleted.keys
        .where((k) => k.startsWith(keyPrefix))
        .toList();
    final int expectedCount = dayWorkouts.length; // honors 80-min rule already applied
    final int completedCount = keysForDay.where((k) => _workoutCompleted[k] == true).length;
    
    print('🔍 PlansController - Checking day completion for plan $planId, day ${day + 1}');
    print('🔍 PlansController - Day workouts: ${dayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
    print('🔍 PlansController - Keys for day (prefix $keyPrefix): $keysForDay');
    print('🔍 PlansController - Completed count: $completedCount / expected: $expectedCount');
    
    // Check if all workouts (for this day) are completed
    final bool allCompleted = completedCount >= expectedCount && expectedCount > 0;
    print('🔍 PlansController - All workouts completed: $allCompleted');
    
    if (!allCompleted) return;
    
    final int newDay = day + 1;
    _currentDay[planId.toString()] = newDay;
    _persistCurrentDayToCache(planId, newDay);
    
    // Clear state for completed day (remove all keys with the day prefix)
    for (final key in List<String>.from(_workoutCompleted.keys)) {
      if (key.startsWith(keyPrefix)) {
        _workoutCompleted.remove(key);
        _workoutStarted.remove(key);
        _workoutRemainingMinutes.remove(key);
        final timer = _workoutTimers.remove(key);
        timer?.cancel();
      }
    }
    
    print('🎉 PlansController - Advanced from day ${day + 1} to ${newDay + 1} for plan $planId');
    print('🔍 PlansController - Day progression: $day → $newDay for plan $planId');
    print('🔍 PlansController - Current day state: ${_currentDay}');
    
    // Debug: Check what workouts will be shown for the new day (same as schedules controller)
    final newDayWorkouts = _getDayWorkouts(activePlan, newDay);
    print('🔍 PlansController - New day $newDay workouts: ${newDayWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
    
    // Force UI refresh (same approach as schedules controller)
    refreshUI();
    
    // Also refresh stats after day advancement
    Future.microtask(() => _refreshStatsSafe());
    
    print('✅ PlansController - Day advancement complete, UI should refresh');
  }
  
  // Get workouts for a specific day (EXACT same approach as schedules controller)
  List<Map<String, dynamic>> _getDayWorkouts(Map<String, dynamic> plan, int dayIndex) {
    // This should match the logic in _getDayItems (same as schedules)
    try {
      Map<String, dynamic> actualPlan = plan;
      if (plan.containsKey('success') && plan.containsKey('data')) {
        actualPlan = plan['data'] ?? {};
      }
      
      // 1) If backend provided daily_plans, use that as source of truth per day
      final dailyPlansRaw = actualPlan['daily_plans'];
      print('🔍 PlansController - Checking daily_plans for day ${dayIndex + 1}: type=${dailyPlansRaw.runtimeType}');

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
          print('⚠️ PlansController - Failed to parse daily_plans JSON string: $e');
        }
      }

      if (dailyPlansList != null && dailyPlansList.isNotEmpty) {
        try {
          final List<Map<String, dynamic>> dailyPlans = dailyPlansList;
          print('🔍 PlansController - Found ${dailyPlans.length} daily plans in backend data');
          
          // try find by day field first (1-based), fallback to index
          Map<String, dynamic>? dayEntry = dailyPlans.firstWhereOrNull((dp) {
            final d = int.tryParse(dp['day']?.toString() ?? '');
            return d != null && d == dayIndex + 1;
          });
          dayEntry ??= (dayIndex < dailyPlans.length ? dailyPlans[dayIndex] : null);
          
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
              print('⚠️ PlansController - Failed to parse workouts JSON for day ${dayIndex + 1}: $e');
            }
          }

          if (resultList != null) {
            final result = resultList;
            print('✅ PlansController - Using backend daily_plans for day ${dayIndex + 1}: ${result.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()}');
            return result;
          } else {
            print('⚠️ PlansController - daily_plans[${dayIndex}] found but no workouts, falling back to rotation');
          }
        } catch (e) {
          print('⚠️ PlansController - Error parsing daily_plans: $e, falling back to rotation');
        }
      } else {
        print('⚠️ PlansController - No daily_plans in backend data, using client-side rotation for day ${dayIndex + 1}');
      }

      List<Map<String, dynamic>> workouts = [];
      
      final exercisesDetails = actualPlan['exercises_details'];
      if (exercisesDetails is List && exercisesDetails.isNotEmpty) {
        workouts = exercisesDetails.cast<Map<String, dynamic>>();
      } else if (exercisesDetails is String) {
        try {
          final List<dynamic> parsed = jsonDecode(exercisesDetails);
          workouts = parsed.cast<Map<String, dynamic>>();
        } catch (e) {
          return [];
        }
      }
      
      // Also check items if exercises_details is empty
      if (workouts.isEmpty && actualPlan['items'] is List) {
        workouts = (actualPlan['items'] as List).cast<Map<String, dynamic>>();
      }
      
      // Calculate total days from start/end date or use provided total_days (same as schedules)
      int totalDays = 1;
      if (actualPlan['start_date'] != null && actualPlan['end_date'] != null) {
        final start = DateTime.tryParse(actualPlan['start_date']);
        final end = DateTime.tryParse(actualPlan['end_date']);
        if (start != null && end != null) {
          totalDays = max(1, end.difference(start).inDays + 1);
        }
      } else {
        totalDays = max(1, (actualPlan['total_days'] ?? 1) as int);
      }
      
      print('🔍 PlansController - _getDayWorkouts: Day $dayIndex of $totalDays total days');
      print('🔍 PlansController - Total workouts available: ${workouts.length}');
      
      if (workouts.isEmpty) {
        return [];
      }
      
      // 2) Fallback: Distribute workouts across days properly (same as schedules)
      return _distributeWorkoutsAcrossDays(workouts, totalDays, dayIndex);
      
    } catch (e) {
      print('❌ PlansController - Error in _getDayWorkouts: $e');
      return [];
    }
  }
  
  // Distribute workouts across days (EXACT same logic as schedules controller)
  List<Map<String, dynamic>> _distributeWorkoutsAcrossDays(List<Map<String, dynamic>> workouts, int totalDays, int dayIndex) {
    if (workouts.isEmpty) return [];
    
    print('🔍 PlansController - _distributeWorkoutsAcrossDays: ${workouts.length} workouts across $totalDays days, requesting day $dayIndex');
    
    // If only one workout, return it for all days (same as schedules)
    if (workouts.length == 1) {
      final single = Map<String, dynamic>.from(workouts.first);
      print('🔍 PlansController - Only one workout available: ${single['name'] ?? single['workout_name'] ?? 'Unknown'}');
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
    final int m1 = _extractWorkoutMinutesFromMap(first);
    final int m2 = _extractWorkoutMinutesFromMap(second);
    int combined = m1 + m2;
    
    print('🔍 PlansController - dayRotationOffset: $dayRotationOffset (dayIndex: $dayIndex, workoutsPerDay: $workoutsPerDay, totalWorkouts: ${workouts.length})');
    print('🔍 PlansController - Pair indices: $firstIdx & $secondIdx → ${first['name'] ?? first['workout_name'] ?? 'Unknown'}($m1) + ${second['name'] ?? second['workout_name'] ?? 'Unknown'}($m2) = $combined');
    
    List<Map<String, dynamic>> selectedWorkouts = [];
    
    // Updated distribution logic:
    // - If total minutes > 80: show only 1 workout
    // - If total minutes <= 80: show 2 workouts
    // - If total minutes < 50: try to add a third workout if available
    if (combined > 80) {
      // More than 80 minutes: show only first workout
      selectedWorkouts = [first];
      print('🔍 PlansController - Total minutes ($combined) > 80, showing only 1 workout');
    } else if (combined < 50) {
      // Less than 50 minutes: try to add a third workout
      selectedWorkouts = [first, second];
      
      if (workouts.length > 2) {
        final int thirdIdx = (dayRotationOffset + 2) % workouts.length;
        final Map<String, dynamic> third = Map<String, dynamic>.from(workouts[thirdIdx]);
        final int m3 = _extractWorkoutMinutesFromMap(third);
        final int totalWithThird = combined + m3;
        
        // Only add third workout if it doesn't exceed 80 minutes
        if (totalWithThird <= 80) {
          selectedWorkouts.add(third);
          combined = totalWithThird;
          print('🔍 PlansController - Total minutes ($combined) < 50, added third workout: ${third['name'] ?? third['workout_name'] ?? 'Unknown'}($m3)');
        } else {
          print('🔍 PlansController - Total minutes would be $totalWithThird with third workout, keeping 2 workouts');
        }
      } else {
        print('🔍 PlansController - Total minutes ($combined) < 50, but only ${workouts.length} workouts available');
      }
    } else {
      // Between 50 and 80 minutes: show 2 workouts
      selectedWorkouts = [first, second];
      print('🔍 PlansController - Total minutes ($combined) between 50-80, showing 2 workouts');
    }

    print('🔍 PlansController - Day $dayIndex selected workouts: ${selectedWorkouts.map((w) => w['name'] ?? w['workout_name'] ?? 'Unknown').toList()} (total: ${selectedWorkouts.fold<int>(0, (sum, w) => sum + _extractWorkoutMinutesFromMap(w))} minutes)');
    return selectedWorkouts;
  }
  
  // Force UI refresh (same approach as schedules controller)
  void refreshUI() {
    print('🔄 PlansController - Refreshing UI...');
    _currentDay.refresh(); // Refresh current day to trigger UI updates (same as schedules)
    _workoutStarted.refresh();
    _workoutCompleted.refresh();
    _workoutRemainingMinutes.refresh();
    _activePlan.refresh(); // Also refresh active plan to trigger UI updates
    uiTick.value++;
    if (!isClosed) update();
    print('🔄 PlansController - UI refresh completed');
  }

  Future<void> _storeDailyTrainingData(int planId, int day, String workoutName) async {
    try {
      print('✅ Workout completed: Plan $planId, Day ${day + 1}, Workout $workoutName');
      
      // Get plan's start_date to calculate correct plan_date (not DateTime.now())
      final activePlan = _activePlan.value;
      
      // Get approval_id for manual/AI plans (needed for lookup and creation)
      // Try multiple sources: planToApprovalId map, active plan data, or plan data
      int? approvalId = planToApprovalId[planId];
      if (approvalId == null && activePlan != null) {
        final approvalIdFromPlan = activePlan['approval_id'];
        if (approvalIdFromPlan != null) {
          approvalId = int.tryParse(approvalIdFromPlan.toString());
          if (approvalId != null) {
            planToApprovalId[planId] = approvalId;
            await _persistApprovalIdCache();
            print('✅ PlansController - Retrieved approval_id $approvalId from active plan data');
          }
        }
      }
      // If still null, try to get from controller's getApprovalIdForPlan
      if (approvalId == null) {
        approvalId = getApprovalIdForPlan(planId);
        if (approvalId != null) {
          print('✅ PlansController - Retrieved approval_id $approvalId from controller cache');
        }
      }
      print('🔍 PlansController - Looking up daily_plan_id for plan $planId, approval_id: $approvalId, day ${day + 1}');
      DateTime? planStartDate;
      if (activePlan != null && activePlan['id']?.toString() == planId.toString()) {
        if (activePlan['start_date'] != null) {
          planStartDate = DateTime.tryParse(activePlan['start_date'].toString());
          print('🔍 PlansController - Found plan start_date: $planStartDate');
        }
      }
      // Fallback to current date if start_date not found
      planStartDate ??= DateTime.now();
      
      // First, try to get the daily_plan_id from stored daily plans
      int? dailyPlanId;
      try {
        // CRITICAL: Pass planType to ensure we only get plans of the correct type (manual or ai_generated)
        // This prevents interference from assigned plans or stats records
        // Determine plan type from active plan
        final isAiPlanForLookup = activePlan != null && (
          activePlan.containsKey('ai_generated') || 
          activePlan.containsKey('gemini_generated') ||
          activePlan.containsKey('ai_plan_id') ||
          activePlan.containsKey('request_id') ||
          (activePlan.containsKey('exercise_plan_category') && activePlan.containsKey('user_level') && activePlan.containsKey('total_days'))
        );
        final planTypeForLookup = isAiPlanForLookup ? 'ai_generated' : 'manual';
        final dailyPlans = await _dailyTrainingService.getDailyTrainingPlans(planType: planTypeForLookup);
        // Calculate plan_date using plan's start_date + day offset (not DateTime.now())
        final planDate = planStartDate.add(Duration(days: day)).toIso8601String().split('T').first;
        print('🔍 PlansController - Searching for daily plan with date: $planDate (calculated from start_date: $planStartDate + $day days)');
        print('🔍 PlansController - Total daily plans fetched: ${dailyPlans.length}');
        
        final matchingDay = dailyPlans.firstWhereOrNull((dp) {
          final dpDate = dp['plan_date']?.toString().split('T').first;
          final dpPlanType = dp['plan_type']?.toString() ?? '';
          
          // For manual/AI plans, source_plan_id can be either approval_id OR plan_id (if approval_id is null)
          if (dpPlanType == 'manual' || dpPlanType == 'ai_generated') {
            final dpSourcePlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            // Match by approval_id if available, otherwise match by plan_id (source_plan_id)
            final matches = (approvalId != null && dpSourcePlanId == approvalId && dpDate == planDate) ||
                          (approvalId == null && dpSourcePlanId == planId && dpDate == planDate);
            if (matches) {
              print('🔍 PlansController - Found match: source_plan_id=$dpSourcePlanId (${approvalId != null ? "approval_id" : "plan_id"}), date=$dpDate');
            }
            return matches;
          } else {
            // For assigned plans, source_plan_id is the assignment_id
            final dpSourcePlanId = int.tryParse(dp['source_plan_id']?.toString() ?? '');
            return dpSourcePlanId == planId && dpDate == planDate;
          }
        });
        
        if (matchingDay != null) {
          dailyPlanId = int.tryParse(matchingDay['id']?.toString() ?? matchingDay['daily_plan_id']?.toString() ?? '');
          print('🔍 PlansController - Found daily_plan_id: $dailyPlanId for day ${day + 1}');
          // Store the matching daily plan for later use in item_id calculation
          activePlan?['_found_daily_plan'] = matchingDay;
        } else {
          print('⚠️ PlansController - No matching daily plan found for plan $planId, approval_id: $approvalId, date: $planDate');
        }
      } catch (e) {
        print('⚠️ PlansController - Could not fetch daily plan ID: $e');
      }
      
      // If we couldn't find daily_plan_id, try to find/create one using findDailyPlanBySource
      // Backend now supports source_plan_id (plan_id) even when approval_id is null
      if (dailyPlanId == null) {
        try {
          print('📤 PlansController - No daily_plan_id found, trying to find/create using findDailyPlanBySource for day ${day + 1}');
          
          // Calculate plan_date using plan's start_date + day offset (not DateTime.now())
          final planDate = planStartDate.add(Duration(days: day)).toIso8601String().split('T').first;
          
          // Try to find daily plan using findDailyPlanBySource (backend will auto-sync if needed)
          Map<String, dynamic>? foundPlan;
          if (approvalId != null) {
            print('📤 PlansController - Finding daily plan with approval_id: $approvalId, plan_date: $planDate');
            foundPlan = await _dailyTrainingService.findDailyPlanBySource(
              approvalId: approvalId,
              planDate: planDate,
            );
          } else {
            // Use source_plan_id (plan_id) when approval_id is null (backend supports this now)
            print('📤 PlansController - Finding daily plan with source_plan_id (plan_id): $planId, plan_date: $planDate');
            foundPlan = await _dailyTrainingService.findDailyPlanBySource(
              sourcePlanId: planId,
              planDate: planDate,
            );
          }
          
          if (foundPlan != null && foundPlan.isNotEmpty) {
            dailyPlanId = int.tryParse(foundPlan['id']?.toString() ?? foundPlan['daily_plan_id']?.toString() ?? '');
            if (dailyPlanId != null) {
              print('✅ PlansController - Found/created daily_plan_id: $dailyPlanId using findDailyPlanBySource');
              // Store the found/created daily plan for later use in item_id calculation
              activePlan?['_found_daily_plan'] = foundPlan;
            } else {
              print('⚠️ PlansController - Found daily plan but could not extract daily_plan_id');
            }
          } else {
            // Fallback: try createDailyPlanFromApproval if findDailyPlanBySource didn't work
            print('⚠️ PlansController - findDailyPlanBySource returned empty, trying createDailyPlanFromApproval as fallback');
            if (approvalId != null) {
              final createdPlan = await _dailyTrainingService.createDailyPlanFromApproval(
                approvalId: approvalId,
                planDate: planDate,
              );
              
              if (createdPlan.isNotEmpty) {
                dailyPlanId = int.tryParse(createdPlan['id']?.toString() ?? createdPlan['daily_plan_id']?.toString() ?? '');
                if (dailyPlanId != null) {
                  print('✅ PlansController - Created daily_plan_id on-demand: $dailyPlanId');
                  activePlan?['_found_daily_plan'] = createdPlan;
                }
              }
            } else {
              print('⚠️ PlansController - No approval_id and findDailyPlanBySource failed, cannot create daily plan');
            }
          }
        } catch (e) {
          print('⚠️ PlansController - Failed to find/create daily plan on-demand: $e');
        }
      }
      
      // If we still don't have daily_plan_id, use planId as fallback (backend might handle it)
      final int targetPlanId = dailyPlanId ?? planId;
      
      // Get workout details from daily plan's exercises_details (preferred) or active plan
      // Use exercises_details from the daily plan structure (not items)
      List<Map<String, dynamic>> workouts = [];
      Map<String, dynamic>? dailyPlanData = activePlan?['_found_daily_plan'] as Map<String, dynamic>?;
      
      // Prefer exercises_details from the found/created daily plan
      if (dailyPlanData != null) {
        if (dailyPlanData['exercises_details'] is List) {
          workouts = (dailyPlanData['exercises_details'] as List).cast<Map<String, dynamic>>();
          print('🔍 PlansController - Using exercises_details from daily plan (${workouts.length} workouts)');
        } else if (dailyPlanData['items'] is List) {
          workouts = (dailyPlanData['items'] as List).cast<Map<String, dynamic>>();
          print('🔍 PlansController - Using items from daily plan (${workouts.length} workouts)');
        }
      }
      
      // Fallback to active plan's exercises_details if daily plan not available
      if (workouts.isEmpty && activePlan != null && activePlan['id']?.toString() == planId.toString()) {
        // For manual/AI plans, use exercises_details (array format)
        if (activePlan['exercises_details'] is List) {
          workouts = (activePlan['exercises_details'] as List).cast<Map<String, dynamic>>();
          print('🔍 PlansController - Using exercises_details from active plan (${workouts.length} workouts)');
        } else if (activePlan['items'] is List) {
          workouts = (activePlan['items'] as List).cast<Map<String, dynamic>>();
          print('🔍 PlansController - Using items from active plan (${workouts.length} workouts)');
        }
      }
      
      // Find the matching workout and get its 1-based index in exercises_details
      // Handle workout names with suffixes like "_1", "_2" by stripping them for matching
      int itemId = 0;
      Map<String, dynamic>? workout;
      // Strip suffix from workoutName (e.g., "Squats_1" -> "Squats")
      final baseWorkoutName = workoutName.replaceAll(RegExp(r'_\d+$'), '').trim();
      
      for (int i = 0; i < workouts.length; i++) {
        final w = workouts[i];
        final wName = (w['workout_name'] ?? w['name'] ?? '').toString().trim();
        final wNameBase = wName.replaceAll(RegExp(r'_\d+$'), '').trim();
        
        // Try exact match first, then base name match (without suffix)
        if (wName.toLowerCase() == workoutName.toLowerCase() || 
            wNameBase.toLowerCase() == baseWorkoutName.toLowerCase() ||
            wName.toLowerCase() == baseWorkoutName.toLowerCase()) {
          workout = w;
          // item_id is 1-based index in exercises_details array
          itemId = i + 1;
          print('🔍 PlansController - Found workout "$workoutName" (base: "$baseWorkoutName") matching "$wName" (base: "$wNameBase") at index $i, item_id: $itemId (1-based)');
          break;
        }
      }
      
      if (itemId == 0) {
        print('⚠️ PlansController - Could not find workout "$workoutName" (base: "$baseWorkoutName") in exercises_details');
        print('⚠️ PlansController - Available workouts: ${workouts.map((w) => (w['workout_name'] ?? w['name'] ?? '').toString()).toList()}');
        print('⚠️ PlansController - Using item_id: 0 (this may cause issues)');
      }
      
      // Build completion data with item-based format
      final completionData = [
        {
          'item_id': itemId,
          'sets_completed': workout != null ? (int.tryParse(workout['sets']?.toString() ?? '0') ?? 0) : 0,
          'reps_completed': workout != null ? (int.tryParse(workout['reps']?.toString() ?? '0') ?? 0) : 0,
          'weight_used': workout != null ? (double.tryParse(workout['weight_kg']?.toString() ?? workout['weight']?.toString() ?? '0') ?? 0.0) : 0.0,
          'minutes_spent': workout != null ? _extractWorkoutMinutesFromMap(workout) : 0,
          'notes': 'Completed via Plans tab - Day ${day + 1}',
          'day': day,
          'workout_name': workoutName,
        }
      ];
      
      final completionResponse = await _dailyTrainingService.submitDailyTrainingCompletion(
        planId: targetPlanId,
        completionData: completionData,
      );
      
      print('✅ Workout completion submitted successfully');
      print('📊 PlansController - Completion response: $completionResponse');
      
      // Extract daily_plan_id from response if available (backend may return it)
      // Reuse existing dailyPlanId variable (already declared earlier in the method)
      if (completionResponse is Map<String, dynamic>) {
        final responseDailyPlanId = int.tryParse(completionResponse['daily_plan_id']?.toString() ?? '') ??
                                     int.tryParse(completionResponse['id']?.toString() ?? '');
        if (responseDailyPlanId != null) {
          dailyPlanId = responseDailyPlanId; // Update existing variable
          print('📊 PlansController - Found daily_plan_id in response: $dailyPlanId');
        }
      }
      
      // CRITICAL: Verify completion was persisted (backend now uses transactions)
      // Check both is_completed AND completed_at (backend requires both)
      if (dailyPlanId != null) {
        bool verified = false;
        int retryCount = 0;
        const maxRetries = 3;
        
        while (!verified && retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1))); // Increasing delay
          retryCount++;
          
          try {
            print('📊 PlansController - Verifying completion (attempt $retryCount/$maxRetries) for daily_plan_id: $dailyPlanId');
            final updatedDailyPlan = await _dailyTrainingService.getDailyTrainingPlan(dailyPlanId);
            
            final isCompleted = updatedDailyPlan['is_completed'] as bool? ?? false;
            final completedAt = updatedDailyPlan['completed_at'] as String?;
            final planDate = updatedDailyPlan['plan_date'] as String?;
            final planType = updatedDailyPlan['plan_type'] as String?;
            
            print('📊 PlansController - Verification result:');
            print('  - is_completed: $isCompleted');
            print('  - completed_at: $completedAt');
            print('  - plan_date: $planDate');
            print('  - plan_type: $planType');
            
            // Backend requires BOTH is_completed=true AND completed_at timestamp
            if (isCompleted && completedAt != null && completedAt.isNotEmpty) {
              verified = true;
              print('✅ PlansController - Completion verified successfully (transaction committed)');
            } else {
              print('⚠️ PlansController - Completion not yet verified: is_completed=$isCompleted, completed_at=${completedAt != null ? "set" : "null"}');
              if (retryCount < maxRetries) {
                print('📊 PlansController - Retrying verification...');
              }
            }
          } catch (verifyError) {
            print('⚠️ PlansController - Verification attempt $retryCount failed: $verifyError');
            if (retryCount >= maxRetries) {
              print('❌ PlansController - Could not verify completion after $maxRetries attempts');
            }
          }
        }
        
        if (!verified) {
          print('⚠️ PlansController - WARNING: Completion may not have been persisted (transaction may have failed)');
          print('⚠️ PlansController - Backend logs should show transaction commit/rollback status');
        }
      } else {
        print('⚠️ PlansController - Could not extract daily_plan_id from response, skipping verification');
      }
      
      // CRITICAL: Force stats sync after completion to ensure backend calculates stats correctly
      // Wait a moment for backend transaction to fully commit before syncing stats
      await Future.delayed(const Duration(milliseconds: 500));
      
      try {
        final statsController = Get.find<StatsController>();
        print('📊 PlansController - Syncing stats after workout completion...');
        await statsController.refreshStats(forceSync: true);
        print('✅ PlansController - Stats synced after workout completion');
      } catch (e) {
        print('⚠️ PlansController - Failed to sync stats after completion: $e');
      }
    } catch (e) {
      print('❌ Error storing workout completion: $e');
      // Even if remote store fails (e.g., 404 on some servers), still advance the day locally
      await _recordLocalCompletion(planId: planId, day: day, workoutName: workoutName);
      _checkDayCompletionAndAdvance(planId, day);
      _refreshStatsSafe();
      return;
    }
    // Record completion locally first, then check and advance day
    await _recordLocalCompletion(planId: planId, day: day, workoutName: workoutName);
    _checkDayCompletionAndAdvance(planId, day);
    _refreshStatsSafe();
    
    // Force UI update after completion and advancement
    Future.microtask(() {
      if (!isClosed) {
        uiTick.value++;
        update();
        print('✅ PlansController - Forced UI refresh after workout completion');
      }
    });
  }

  Future<void> _recordLocalCompletion({
    required int planId,
    required int day,
    required String workoutName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      final key = 'local_workout_completions_user_$userId';
      final String today = DateTime.now().toIso8601String().split('T').first;
      final String existing = prefs.getString(key) ?? '[]';
      final List<dynamic> list = jsonDecode(existing);
      list.add({
        'date': today,
        'plan_id': planId,
        'day': day,
        'workout_name': workoutName,
        'source': 'plans',
      });
      await prefs.setString(key, jsonEncode(list));
      print('📊 PlansController - Recorded local completion for stats');
    } catch (e) {
      print('⚠️ PlansController - Failed to record local completion: $e');
    }
  }

  void _refreshStatsSafe() {
    try {
      final statsController = Get.find<StatsController>();
      // Force sync after workout completion to ensure stats are recalculated
      statsController.refreshStats(forceSync: true);
    } catch (e) {
      print('⚠️ PlansController - StatsController not available to refresh: $e');
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
    
    // Rotation logic for manual plans: dayRotationOffset = (dayIndex * workoutsPerDay) % items.length
    // Distribution rule:
    // - If combined minutes > 80: show 1 workout per day
    // - If combined minutes <= 80: show 2 workouts per day
    const int workoutsPerDay = 2; // Base rotation for selecting workouts
    for (int day = 0; day < totalDays; day++) {
      final int dayRotationOffset = (day * workoutsPerDay) % items.length;
      final int firstIdx = dayRotationOffset;
      final int secondIdx = (dayRotationOffset + 1) % items.length;
      
      final Map<String, dynamic> first = Map<String, dynamic>.from(items[firstIdx]);
        final int m1 = _extractWorkoutMinutesFromMap(first);
      
      final List<Map<String, dynamic>> workoutsForDay = [first];
        
      // Manual Plan Distribution Rule:
      // - If combined minutes > 80: show 1 workout per day (only first)
      // - If combined minutes <= 80: show 2 workouts per day (both first and second)
        if (items.length > 1) {
        final Map<String, dynamic> second = Map<String, dynamic>.from(items[secondIdx]);
          final int m2 = _extractWorkoutMinutesFromMap(second);
        final int combinedMinutes = m1 + m2;
          
          print('🔍 Daily Plan Generation - Day ${day + 1}:');
          print('🔍   - First workout: ${first['workout_name'] ?? 'Unknown'} (${m1} min)');
          print('🔍   - Second workout: ${second['workout_name'] ?? 'Unknown'} (${m2} min)');
        print('🔍   - Combined minutes: $combinedMinutes');
        print('🔍   - Distribution rule: ${combinedMinutes > 80 ? '1 workout (exceeds 80 min)' : '2 workouts (<= 80 min)'}');
          
        if (combinedMinutes <= 80) {
            workoutsForDay.add(second);
          print('✅ Added 2 workouts for Day ${day + 1} (${combinedMinutes} min total)');
          } else {
          print('⚠️ Showing 1 workout for Day ${day + 1} (combined ${combinedMinutes} min exceeds 80 min limit)');
        }
      }
      
      final DateTime? date = startDate != null ? startDate.add(Duration(days: day)) : null;
      final int totalMinutes = workoutsForDay.fold(0, (sum, w) => sum + _extractWorkoutMinutesFromMap(w));
      
      days.add({
        'day': day + 1,
        if (date != null) 'date': date.toIso8601String().split('T').first,
        'workouts': workoutsForDay,
        'total_workouts': workoutsForDay.length,
        'total_minutes': totalMinutes,
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

  // Build daily plans using the structure stored in training approvals
  List<Map<String, dynamic>> _buildDailyPlansFromApproval(
    Map<String, dynamic> approval,
    List<Map<String, dynamic>> fallbackItems, {
    String? planCategory,
    String? userLevel,
  }) {
    try {
      final List<Map<String, dynamic>> result = [];
      // Parse daily_plans
      List<dynamic> daily = [];
      if (approval['daily_plans'] is List) {
        daily = approval['daily_plans'] as List;
      } else if (approval['daily_plans'] is String) {
        try { daily = jsonDecode(approval['daily_plans'] as String) as List<dynamic>; } catch (_) {}
      }
      // Parse exercises_details as global catalog
      List<dynamic> catalog = [];
      if (approval['exercises_details'] is List) {
        catalog = approval['exercises_details'] as List;
      } else if (approval['exercises_details'] is String) {
        try { catalog = jsonDecode(approval['exercises_details'] as String) as List<dynamic>; } catch (_) {}
      }
      Map<String, Map<String, dynamic>> byIdOrName = {};
      for (final e in catalog) {
        final m = Map<String, dynamic>.from(e as Map);
        final String id = (m['id']?.toString() ?? '').trim();
        final String name = (m['workout_name'] ?? m['name'] ?? '').toString().trim();
        if (id.isNotEmpty) byIdOrName[id] = m;
        if (name.isNotEmpty) byIdOrName[name.toLowerCase()] = m;
      }

      for (int i = 0; i < daily.length; i++) {
        final Map<String, dynamic> day = Map<String, dynamic>.from(daily[i] as Map);
        final List<dynamic> dayWorkouts = (day['workouts'] ?? []) as List<dynamic>;
        final List<Map<String, dynamic>> workouts = [];
        int totalMinutes = 0, totalSets = 0, totalReps = 0; double totalWeight = 0.0;

        // Cap to 2 workouts per day (matching UI view distribution)
        final int maxWorkoutsPerDay = 2;
        int workoutsAdded = 0;
        
        for (final w in dayWorkouts) {
          // Stop if we've already added 2 workouts for this day
          if (workoutsAdded >= maxWorkoutsPerDay) {
            print('🔍 PlansController - Capped day ${i + 1} to $maxWorkoutsPerDay workouts (view distribution)');
            break;
          }
          
          final wm = Map<String, dynamic>.from(w as Map);
          final String keyId = (wm['id']?.toString() ?? '').trim();
          final String keyName = (wm['workout_name'] ?? wm['name'] ?? '').toString().trim();
          Map<String, dynamic>? src = byIdOrName[keyId];
          src ??= byIdOrName[keyName.toLowerCase()];
          src ??= fallbackItems.firstWhereOrNull((it) => (it['name'] ?? it['workout_name'] ?? '').toString().trim().toLowerCase() == keyName.toLowerCase());
          final String exerciseName = keyName.isNotEmpty ? keyName : (src?['workout_name'] ?? src?['name'] ?? 'Workout').toString();
          final int sets = int.tryParse(src?['sets']?.toString() ?? '0') ?? 0;
          final int reps = int.tryParse(src?['reps']?.toString() ?? '0') ?? 0;
          final double weight = double.tryParse(src?['weight_kg']?.toString() ?? '0') ?? 0.0;
          final int minutes = _extractWorkoutMinutesFromMap(src ?? {});
          final int exerciseType = int.tryParse(src?['exercise_types']?.toString() ?? '0') ?? 0;
          
          // For second workout, check 80-minute rule
          if (workoutsAdded == 1 && totalMinutes + minutes > 80) {
            print('🔍 PlansController - Skipped second workout for day ${i + 1} (would exceed 80 min: ${totalMinutes + minutes} min)');
            break;
          }
          
          workouts.add({
            'exercise_name': exerciseName,
            'sets': sets,
            'reps': reps,
            'weight_kg': weight,
            'minutes': minutes,
            'exercise_type': exerciseType,
            // Note: plan_category and user_level are at the day level, not individual workout level
          });
          totalMinutes += minutes; totalSets += sets; totalReps += reps; totalWeight += weight;
          workoutsAdded++;
        }

        final String date = (day['date'] ?? day['plan_date'])?.toString() ?? '';
        final String workoutName = (day['workout_name'] ?? 'Daily Workout').toString();
        result.add({
          if (date.isNotEmpty) 'date': date,
          'workouts': workouts,
          'workout_name': workoutName,
          'plan_category': planCategory ?? 'Training Plan',
          'user_level': userLevel ?? 'Beginner',
          'training_minutes': totalMinutes,
          'total_sets': totalSets,
          'total_reps': totalReps,
          'total_weight_kg': totalWeight,
        });
      }
      return result;
    } catch (e) {
      print('⚠️ PlansController - _buildDailyPlansFromApproval failed: $e');
      return [];
    }
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
              
              // Force UI update when status changes
              if (!isClosed) update();
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
            
            // IMPORTANT: If plan is approved but we don't have approval_id, extract it from plan data
            // Backend now includes approval_id in plan data for approved plans (prioritizes plan_type='manual')
            if (status == 'approved' && planToApprovalId[planId] == null) {
              print('🔍 PlansController - Plan $planId is approved but approval_id not in cache, extracting from plan data...');
              
              // Extract approval_id from plan data (backend now includes it)
              int? approvalId;
              if (planData['approval_id'] != null) {
                approvalId = int.tryParse(planData['approval_id'].toString());
                print('🔍 PlansController - Found approval_id in plan data: $approvalId');
              }
              
              if (approvalId != null) {
                // Store the approval_id for future use
                planToApprovalId[planId] = approvalId;
                await _persistApprovalIdCache();
                print('✅ PlansController - Stored approval_id $approvalId for approved plan $planId');
              } else {
                print('⚠️ PlansController - approval_id not found in plan data for approved plan $planId');
                print('⚠️ PlansController - Backend should include approval_id for approved plans (check backend approval lookup)');
              }
            }
            
            // Update local status if found - always update if status is found in plan data
            if (status != 'none') {
              final oldStatus = planApprovalStatus[planId] ?? 'none';
              if (oldStatus != status) {
              planApprovalStatus[planId] = status;
              print('✅ PlansController - Updated manual plan $planId status from $oldStatus to $status');
              
              // Reset modification flag when plan is approved
              if (status == 'approved') {
                resetModificationFlag(planId);
              }
                
                // Force UI update when status changes
                if (!isClosed) update();
              } else {
              print('ℹ️ PlansController - Manual plan $planId status unchanged: $status');
              }
            } else {
              print('⚠️ PlansController - Manual plan $planId has no approval status in plan data');
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
              
              // Force UI update when status changes
              if (!isClosed) update();
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
      if (userId == 0) {
        print('⚠️ Plans - No user ID, skipping active plan load');
        return;
      }
      
      final key = 'activePlan_user_$userId';
      final String? data = prefs.getString(key);
      
      if (data != null && data.isNotEmpty) {
        final Map<String, dynamic> snapshot = jsonDecode(data);
        
        // CRITICAL: Validate that the cached plan belongs to the current user
        final planUserId = snapshot['user_id'] as int?;
        if (planUserId != null && planUserId != userId) {
          print('❌ Plans - Cached active plan ${snapshot['id']} belongs to user $planUserId, but current user is $userId - clearing invalid cache');
          await prefs.remove(key);
          _activePlan.value = null;
          return;
        }
        
        _activePlan.value = snapshot;
        final planId = int.tryParse(snapshot['id']?.toString() ?? '');
        print('📱 Plans - Loaded active plan snapshot from cache: $planId (user_id: $planUserId, validated for current user: $userId)');
        
        // When restoring active plan, check database for completed days
        if (planId != null) {
          try {
            print('📱 Plans - Checking database for completed days when restoring active plan...');
            
            // Determine plan type
            final planType = snapshot['plan_type']?.toString().toLowerCase();
            bool isAiPlan = false;
            if (planType == 'ai_generated' || 
                snapshot.containsKey('ai_generated') || 
                snapshot.containsKey('gemini_generated') ||
                snapshot.containsKey('ai_plan_id') ||
                snapshot.containsKey('request_id')) {
              isAiPlan = true;
            }
            
            final completedDay = await _getLastCompletedDayFromDatabase(planId, isAiPlan ? 'ai_generated' : 'manual');
            if (completedDay != null) {
              // completedDay is 1-based (from daily_plans), _currentDay is 0-based
              // If completedDay = 2 (Day 2 completed), we should resume at Day 3 (index 2 in 0-based)
              final nextDay = completedDay; // completedDay is 1-based, use directly as 0-based index for next day
              _currentDay[planId.toString()] = nextDay;
              _persistCurrentDayToCache(planId, nextDay);
              print('📱 Plans - ✅ Restored active plan: found completed day $completedDay (1-based) in database, resuming at day $nextDay (0-based index, Day ${completedDay + 1})');
            } else {
              // No completed days in database, fall back to cache
              await _loadCurrentDayFromCache(planId);
              final cachedDay = _currentDay[planId.toString()];
              if (cachedDay != null) {
                print('📱 Plans - Loaded current day $cachedDay for plan $planId from cache (no completed days in database)');
              }
            }
          } catch (e) {
            print('⚠️ Plans - Error checking database when restoring active plan: $e');
            // If database check fails, fall back to cache
            await _loadCurrentDayFromCache(planId!);
            final cachedDay = _currentDay[planId.toString()];
            if (cachedDay != null) {
              print('📱 Plans - Loaded current day $cachedDay for plan $planId from cache (after database error)');
            }
          }
        }
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

  Future<void> _clearActivePlanFromCache() async {
    await _clearActivePlanSnapshotIfStopped();
  }

  /// Clear all user data when user logs out or switches users
  /// CRITICAL: This ensures no data from previous user is shown to new user
  Future<void> clearAllUserData() async {
    try {
      print('🧹 PlansController - Clearing all user data (user switch/logout)...');
      
      // Clear in-memory state
      _activePlan.value = null;
      _startedPlans.clear();
      _currentDay.clear();
      _workoutStarted.clear();
      _workoutRemainingMinutes.clear();
      _workoutCompleted.clear();
      manualPlans.clear();
      aiGeneratedPlans.clear();
      planToApprovalId.clear();
      planApprovalStatus.clear();
      
      // Clear cache for current user (if available)
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      if (userId > 0) {
        await prefs.remove('activePlan_user_$userId');
        await prefs.remove('startedPlans_user_$userId');
        await prefs.remove('planApprovalIds_user_$userId');
        // Clear all day caches for this user
        final allKeys = prefs.getKeys();
        for (final key in allKeys) {
          if ((key.startsWith('plan_day_') || key.startsWith('planDay_')) && key.endsWith('_user_$userId')) {
            await prefs.remove(key);
          }
        }
      }
      
      print('✅ PlansController - All user data cleared');
    } catch (e) {
      print('❌ PlansController - Error clearing user data: $e');
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

  // Get the last completed day from database by checking completed daily plans
  Future<int?> _getLastCompletedDayFromDatabase(int planId, String planType) async {
    try {
      print('🔍 PlansController - Checking database for completed days for plan $planId (type: $planType)');
      
      // Get all daily plans from database
      final allPlans = await _dailyTrainingService.getDailyTrainingPlans();
      print('📅 PlansController - Retrieved ${allPlans.length} total daily plans from database');
      
      // Get approval_id for this plan (needed to match source_plan_id)
      int? approvalId = planToApprovalId[planId];
      if (approvalId == null) {
        approvalId = getApprovalIdForPlan(planId);
      }
      
      // Filter plans for this plan (check source_plan_id)
      // For manual/AI plans, source_plan_id can be either approval_id OR plan_id (if approval_id is null)
      // CRITICAL: STRICTLY filter by plan_type to avoid picking up assigned plan data
      // Manual plans and assigned plans are completely independent and should never interfere
      // 
      // CRITICAL: Multiple Plans Support
      // With the new schema, multiple plans of the same type can exist on the same date if they
      // have different source_plan_id values. We must filter by BOTH plan_type AND source_plan_id
      // to ensure we only get plans for this specific plan, not other plans of the same type.
      final planPlans = allPlans.where((plan) {
        final sourcePlanId = plan['source_plan_id'] as int?;
        final planTypeRaw = plan['plan_type'] as String?;
        
        // CRITICAL: First check plan type - MUST match exactly (not 'web_assigned')
        // This ensures manual/AI plans and assigned plans are completely isolated
        if (planTypeRaw != planType) {
          return false; // Reject any plans with different plan type immediately
        }
        
        // Match by approval_id if available, otherwise match by plan_id
        if (approvalId != null) {
          return sourcePlanId == approvalId;
        } else {
          return sourcePlanId == planId;
        }
      }).toList();
      
      print('📅 PlansController - Found ${planPlans.length} plans for plan $planId (approval_id: $approvalId)');
      
      if (planPlans.isEmpty) {
        print('📅 PlansController - No daily plans found in database for plan $planId');
        return null;
      }
      
      // Get plan's start_date to calculate day numbers
      final activePlan = _activePlan.value;
      DateTime? startDate;
      if (activePlan != null && activePlan['id']?.toString() == planId.toString()) {
        if (activePlan['start_date'] != null) {
          startDate = DateTime.tryParse(activePlan['start_date'].toString());
        }
      }
      
      // If start_date not found in active plan, try to get from plan data
      if (startDate == null) {
        try {
          if (planType == 'manual') {
            final planData = await _manualService.getPlan(planId);
            if (planData['start_date'] != null) {
              startDate = DateTime.tryParse(planData['start_date'].toString());
            }
          } else if (planType == 'ai_generated') {
            final planData = await _aiService.getGenerated(planId);
            if (planData['start_date'] != null) {
              startDate = DateTime.tryParse(planData['start_date'].toString());
            }
          }
        } catch (e) {
          print('⚠️ PlansController - Could not fetch plan data for start_date: $e');
        }
      }
      
      // Fallback to current date if start_date not found
      startDate ??= DateTime.now();
      final startDateNormalized = DateTime(startDate.year, startDate.month, startDate.day);
      
      print('📅 PlansController - Using start_date: $startDateNormalized');
      
      // Find completed plans and calculate day numbers
      int? lastCompletedDay;
      final completedPlans = <Map<String, dynamic>>[];
      
      for (final plan in planPlans) {
        final isCompleted = plan['is_completed'] as bool? ?? false;
        final completedAt = plan['completed_at'] as String?;
        
        // Must have both is_completed: true AND completed_at timestamp
        if (!isCompleted || completedAt == null || completedAt.isEmpty) {
          continue;
        }
        
        // Calculate day number from plan_date
        final planDate = plan['plan_date'] as String?;
        if (planDate == null) continue;
        
        final planDateObj = DateTime.tryParse(planDate);
        if (planDateObj == null) continue;
        
        final planDateNormalized = DateTime(planDateObj.year, planDateObj.month, planDateObj.day);
        final daysDiff = planDateNormalized.difference(startDateNormalized).inDays;
        
        // Day number is 1-based (Day 1 = daysDiff 0)
        final dayNumber = daysDiff + 1;
        
        if (dayNumber > 0) {
          completedPlans.add(plan);
          if (lastCompletedDay == null || dayNumber > lastCompletedDay) {
            lastCompletedDay = dayNumber;
            print('📅 PlansController - Updated lastCompletedDay to $lastCompletedDay (plan_date: $planDateNormalized)');
          }
        }
      }
      
      print('📅 PlansController - Found ${completedPlans.length} completed plans for plan $planId');
      print('📅 PlansController - Last completed day from database: $lastCompletedDay');
      
      if (lastCompletedDay != null) {
        // lastCompletedDay is 1-based (from daily_plans), _currentDay is 0-based
        // If lastCompletedDay = 2 (Day 2 completed), we should resume at Day 3 (index 2 in 0-based)
        final nextDay = lastCompletedDay; // lastCompletedDay is 1-based, use directly as 0-based index for next day
        print('📅 PlansController - Last completed day: $lastCompletedDay (1-based, Day $lastCompletedDay completed)');
        print('📅 PlansController - Should resume at Day ${lastCompletedDay + 1} (0-based index: $nextDay)');
        return nextDay;
      } else {
        print('📅 PlansController - No completed days found in database for plan $planId');
        return null;
      }
    } catch (e) {
      print('⚠️ PlansController - Error getting last completed day from database: $e');
      return null;
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
      
      // Normalize items to ensure minutes field is properly set
      _normalizePlanItemsForMinutes(updatedPlan);
      
      // Add it back to the list
      manualPlans.add(updatedPlan);
      print('✅ PlansController - Restored plan $id to manual plans list');
    }
    
    // Also normalize the updated plan if it exists in the list
    final updatedPlanInList = manualPlans.firstWhereOrNull((plan) => plan['id'] == id);
    if (updatedPlanInList != null) {
      _normalizePlanItemsForMinutes(updatedPlanInList);
      print('✅ PlansController - Normalized items for updated plan $id');
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
      // NOTE: Backend (/api/appManualTraining/) now filters out plans with web_plan_id
      // AND plans matching assignments by date range (two-layer filter)
      // This frontend filtering is a defense-in-depth measure
      // 
      // BACKEND FIX: The backend now uses a two-layer filter:
      // 1. Primary: whereNull('web_plan_id') - excludes plans with web_plan_id set
      // 2. Secondary: Date range matching - excludes plans whose start_date and end_date
      //    exactly match any assignment (catches edge cases where web_plan_id might be NULL)
      final uniquePlans = <Map<String, dynamic>>[];
      final seenIds = <int>{};
      
      // Try to get assignments to cross-reference for date range matching
      // This helps catch assigned plans that might have web_plan_id = NULL
      // BACKEND FIX: Some assigned plans may have web_plan_id = NULL but match assignments by date range
      // This cross-reference ensures we catch those edge cases
      List<Map<String, dynamic>> assignments = [];
      try {
        if (Get.isRegistered<SchedulesController>()) {
          final schedulesController = Get.find<SchedulesController>();
          // Ensure assignments are loaded if not already
          if (schedulesController.assignments.isEmpty) {
            print('🔍 Plans - Assignments not loaded, loading now for cross-reference in refreshManualPlans...');
            await schedulesController.loadSchedulesData();
          }
          assignments = List<Map<String, dynamic>>.from(schedulesController.assignments);
          print('🔍 Plans - Found ${assignments.length} assignments for cross-reference in refreshManualPlans');
          
          // Log all assignment IDs for debugging
          if (assignments.isNotEmpty) {
            final assignmentIds = assignments.map((a) => a['id']?.toString() ?? 'N/A').toList();
            final webPlanIds = assignments.map((a) => a['web_plan_id']?.toString() ?? 'N/A').toList();
            print('🔍 Plans - Assignment IDs (refresh): $assignmentIds');
            print('🔍 Plans - Assignment web_plan_ids (refresh): $webPlanIds');
          }
        }
      } catch (e) {
        print('⚠️ Plans - Could not access SchedulesController for assignments: $e');
        print('⚠️ Plans - Will rely on other assignment indicators (web_plan_id, assigned_by, etc.)');
      }
      
      // CRITICAL: Create a set of all assignment-related IDs for quick lookup
      // This includes assignment IDs, web_plan_ids, and plan_ids from assignments
      final Set<int> assignmentRelatedIds = {};
      for (final assignment in assignments) {
        final assignId = int.tryParse(assignment['id']?.toString() ?? '');
        final assignWebPlanId = int.tryParse(assignment['web_plan_id']?.toString() ?? '');
        final assignPlanId = int.tryParse(assignment['plan_id']?.toString() ?? '');
        
        if (assignId != null) assignmentRelatedIds.add(assignId);
        if (assignWebPlanId != null) assignmentRelatedIds.add(assignWebPlanId);
        if (assignPlanId != null) assignmentRelatedIds.add(assignPlanId);
      }
      print('🔍 Plans - Assignment-related IDs set (refresh): $assignmentRelatedIds');
      
      for (final plan in manualRes) {
        final planMap = Map<String, dynamic>.from(plan);
        final planId = int.tryParse(planMap['id']?.toString() ?? '');
        final planType = planMap['plan_type']?.toString().toLowerCase();
        final createdBy = planMap['created_by'];
        final assignedBy = planMap['assigned_by'];
        final assignmentId = planMap['assignment_id'];
        final webPlanId = planMap['web_plan_id'];
        final startDate = planMap['start_date'];
        final endDate = planMap['end_date'];
        
        // Check if this is an assigned plan (exclude these)
        // CRITICAL: web_assigned plans belong in Schedules tab, not Plans tab
        // ANY indicator of assignment means this plan belongs in Schedules tab
        // Backend should have filtered these out, but we check again as a safety measure
        final trainerId = planMap['trainer_id'];
        final assignedAt = planMap['assigned_at'];
        final status = planMap['status']?.toString().toUpperCase();
        
        bool isAssignedPlan = planType == 'assigned' || 
                              planType == 'web_assigned' ||
                              assignedBy != null || 
                              assignmentId != null ||
                              webPlanId != null ||
                              trainerId != null || // Has trainer_id (assigned by trainer)
                              assignedAt != null || // Has assigned_at timestamp
                              status == 'PLANNED' || // Status indicates assigned plan
                              status == 'ACTIVE' ||
                              planType == 'ai_generated' ||
                              planType == 'daily' ||
                              planType == 'schedule';
        
        // CRITICAL: Check if this plan ID is in the assignment-related IDs set
        // This is the fastest way to check if a plan is linked to any assignment
        if (!isAssignedPlan && planId != null && assignmentRelatedIds.contains(planId)) {
          isAssignedPlan = true;
          print('⚠️ Plans - Plan $planId is in assignment-related IDs set - excluding from manual plans (refreshManualPlans)');
        }
        
        // CRITICAL: Also check if this plan ID matches any assignment's web_plan_id or plan ID
        // This catches cases where the plan is linked to an assignment (redundant but thorough)
        if (!isAssignedPlan && assignments.isNotEmpty) {
          for (final assignment in assignments) {
            final assignWebPlanId = assignment['web_plan_id'];
            final assignPlanId = assignment['plan_id'];
            final assignId = assignment['id'];
            
            // If plan ID matches assignment's web_plan_id, plan_id, or assignment id, it's assigned
            if (planId != null && (
                (assignWebPlanId != null && planId == int.tryParse(assignWebPlanId.toString())) ||
                (assignPlanId != null && planId == int.tryParse(assignPlanId.toString())) ||
                (assignId != null && planId == int.tryParse(assignId.toString()))
              )) {
              isAssignedPlan = true;
              print('⚠️ Plans - Plan $planId matches assignment ${assignment['id']} by ID - excluding from manual plans (refreshManualPlans)');
              break;
            }
          }
        }
        
        // CRITICAL: Additional check for edge cases where web_plan_id might be NULL
        // but the plan matches an assignment by date range (backend fix scenario)
        // Check if plan's date range matches any assignment's date range
        if (!isAssignedPlan && startDate != null && endDate != null && assignments.isNotEmpty) {
          try {
            final planStartDate = DateTime.tryParse(startDate.toString());
            final planEndDate = DateTime.tryParse(endDate.toString());
            
            if (planStartDate != null && planEndDate != null) {
              // Normalize dates to compare only date part (ignore time)
              final planStartNormalized = DateTime(planStartDate.year, planStartDate.month, planStartDate.day);
              final planEndNormalized = DateTime(planEndDate.year, planEndDate.month, planEndDate.day);
              
              for (final assignment in assignments) {
                final assignmentStartDate = assignment['start_date'];
                final assignmentEndDate = assignment['end_date'];
                
                if (assignmentStartDate != null && assignmentEndDate != null) {
                  final assignStart = DateTime.tryParse(assignmentStartDate.toString());
                  final assignEnd = DateTime.tryParse(assignmentEndDate.toString());
                  
                  if (assignStart != null && assignEnd != null) {
                    final assignStartNormalized = DateTime(assignStart.year, assignStart.month, assignStart.day);
                    final assignEndNormalized = DateTime(assignEnd.year, assignEnd.month, assignEnd.day);
                    
                    // If dates exactly match, this is likely an assigned plan
                    if (planStartNormalized == assignStartNormalized && 
                        planEndNormalized == assignEndNormalized) {
                      isAssignedPlan = true;
                      print('⚠️ Plans - Plan $planId matches assignment ${assignment['id']} by date range - excluding from manual plans (refreshManualPlans)');
                      break;
                    }
                  }
                }
              }
            }
          } catch (e) {
            print('⚠️ Plans - Error checking date range match in refreshManualPlans: $e');
          }
        }
        
        // Include ONLY manual plans created by the user
        // CRITICAL: If plan has ANY assignment indicators, it's NOT a manual plan
        // Even if plan_type is null/empty, if it has assignedBy/assignmentId/webPlanId, exclude it
        final isManualPlan = !isAssignedPlan && // Must NOT be an assigned plan
                            (planType == 'manual' || planType == null || planType == '') && 
                            (createdBy == null || createdBy == userId); // Allow null createdBy or match userId
        
        if (planId != null && !seenIds.contains(planId) && isManualPlan && !isAssignedPlan) {
          seenIds.add(planId);
          
          // Extract approval_status and approval_id from plan data
          if (planMap['approval_status'] != null) {
            final approvalStatus = planMap['approval_status'].toString().toLowerCase();
            if (approvalStatus.isNotEmpty && approvalStatus != 'null') {
              planApprovalStatus[planId] = approvalStatus;
              planMap['approval_status'] = approvalStatus;
              print('📝 Plans - Extracted approval_status for plan $planId: $approvalStatus');
              
              // IMPORTANT: If plan is approved, extract and store approval_id (backend now includes it)
              if (approvalStatus == 'approved' && planToApprovalId[planId] == null) {
                final approvalId = planMap['approval_id'];
                if (approvalId != null) {
                  final approvalIdInt = int.tryParse(approvalId.toString());
                  if (approvalIdInt != null) {
                    planToApprovalId[planId] = approvalIdInt;
                    await _persistApprovalIdCache();
                    print('✅ Plans - Stored approval_id $approvalIdInt for approved plan $planId from refreshManualPlans');
                  }
        } else {
                  print('⚠️ Plans - Plan $planId is approved but approval_id not in plan data (backend should include it)');
                }
              }
            }
          }
          
          uniquePlans.add(planMap);
          print('📝 Plans - Added manual plan ID: $planId');
        } else if (planId != null && seenIds.contains(planId)) {
          print('⚠️ Plans - Skipped duplicate plan ID: $planId');
        } else if (planId == null) {
          print('⚠️ Plans - Skipped plan with invalid ID');
        } else if (!isManualPlan) {
          print('⚠️ Plans - Skipped non-manual plan ID: $planId (type: $planType)');
        } else if (isAssignedPlan) {
          print('⚠️ Plans - Skipped assigned plan ID: $planId');
        }
      }
      
      print('🔍 Plans - Filtered unique plans: ${uniquePlans.length} items');
      
      // FINAL SAFETY CHECK: Remove any plans that might have slipped through
      // Double-check all plans against assignment-related IDs
      final finalFilteredPlans = uniquePlans.where((plan) {
        final planId = int.tryParse(plan['id']?.toString() ?? '');
        if (planId == null) return false;
        
        // If plan ID is in assignment-related IDs, exclude it
        if (assignmentRelatedIds.contains(planId)) {
          print('⚠️ Plans - FINAL CHECK (refresh): Removing plan $planId (found in assignment-related IDs)');
          return false;
        }
        
        // Double-check assignment indicators
        final hasWebPlanId = plan['web_plan_id'] != null;
        final hasAssignedBy = plan['assigned_by'] != null;
        final hasAssignmentId = plan['assignment_id'] != null;
        final hasTrainerId = plan['trainer_id'] != null;
        
        if (hasWebPlanId || hasAssignedBy || hasAssignmentId || hasTrainerId) {
          print('⚠️ Plans - FINAL CHECK (refresh): Removing plan $planId (has assignment indicators)');
          return false;
        }
        
        return true;
      }).toList();
      
      print('🔍 Plans - Final filtered plans (refresh): ${finalFilteredPlans.length} (removed ${uniquePlans.length - finalFilteredPlans.length} in final check)');
      
      // Check if any previously visible plans were filtered out
      // CRITICAL: Do NOT restore plans that are assigned - they belong in Schedules tab
      final filteredPlanIds = finalFilteredPlans.map((p) => p['id']).toSet();
      final missingPlanIds = currentPlanIds.difference(filteredPlanIds);
      
      if (missingPlanIds.isNotEmpty) {
        print('⚠️ Plans - Some plans were filtered out: $missingPlanIds');
        print('⚠️ Plans - Checking if filtered plans are assigned plans (should NOT restore assigned plans)');
        
        // Try to restore missing plans from the original API response
        // BUT ONLY if they are NOT assigned plans
        for (final missingId in missingPlanIds) {
          final originalPlan = manualRes.firstWhereOrNull((p) => p['id'] == missingId);
          if (originalPlan != null) {
            final planMap = Map<String, dynamic>.from(originalPlan);
            final planId = int.tryParse(planMap['id']?.toString() ?? '');
            
            // CRITICAL: Check if this plan is an assigned plan before restoring
            final hasWebPlanId = planMap['web_plan_id'] != null;
            final hasAssignedBy = planMap['assigned_by'] != null;
            final hasAssignmentId = planMap['assignment_id'] != null;
            final hasTrainerId = planMap['trainer_id'] != null;
            final isInAssignmentIds = planId != null && assignmentRelatedIds.contains(planId);
            
            if (hasWebPlanId || hasAssignedBy || hasAssignmentId || hasTrainerId || isInAssignmentIds) {
              print('⚠️ Plans - NOT restoring plan $planId - it is an assigned plan (belongs in Schedules tab)');
              continue; // Skip restoring assigned plans
            }
            
            if (planId != null && !seenIds.contains(planId)) {
              // Check if it's created by the current user or has null createdBy (basic check)
              final createdBy = planMap['created_by'];
              if (createdBy == null || createdBy == userId) {
                // Double-check it's not an assigned plan before restoring
                final hasWebPlanId = planMap['web_plan_id'] != null;
                final hasAssignedBy = planMap['assigned_by'] != null;
                final hasAssignmentId = planMap['assignment_id'] != null;
                final hasTrainerId = planMap['trainer_id'] != null;
                final isInAssignmentIds = assignmentRelatedIds.contains(planId);
                
                if (!hasWebPlanId && !hasAssignedBy && !hasAssignmentId && !hasTrainerId && !isInAssignmentIds) {
                seenIds.add(planId);
                  finalFilteredPlans.add(planMap);
                  print('✅ Plans - Restored filtered plan $planId (verified not assigned)');
                } else {
                  print('⚠️ Plans - NOT restoring plan $planId - it is an assigned plan');
                }
              }
            }
          }
        }
      }
      
      // Normalize items to ensure minutes field is properly set
      for (final plan in finalFilteredPlans) {
        _normalizePlanItemsForMinutes(plan);
      }
      
      if (!isClosed) {
        manualPlans.assignAll(finalFilteredPlans);
        update(); // Force UI refresh
      }
      print('✅ Plans - Refreshed manual plans: ${manualPlans.length} unique manual items (after final filtering)');
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
      
      // Get the plan details before deletion to extract approval_id
      final plan = manualPlans.firstWhereOrNull((p) {
        final int id = int.tryParse(p['id']?.toString() ?? '') ?? -1;
        final int pid = int.tryParse(p['plan_id']?.toString() ?? '') ?? -1;
        return id == planId || pid == planId;
      });
      
      // Get approval_id from plan or from planToApprovalId map
      int? approvalId;
      if (plan != null) {
        approvalId = int.tryParse(plan['approval_id']?.toString() ?? '');
        if (approvalId == null) {
          approvalId = planToApprovalId[planId];
        }
      } else {
        approvalId = planToApprovalId[planId];
      }
      
      print('🗑️ Plans - Found approval_id: $approvalId for plan $planId');
      
      // Step 1: Delete daily training plans associated with this manual plan
      // Use approval_id as source_plan_id for manual plans
      if (approvalId != null) {
        try {
          print('🗑️ Plans - Deleting daily training plans for approval_id: $approvalId');
          await _dailyTrainingService.deleteDailyPlansBySource(
            approvalId: approvalId,
            sourcePlanId: approvalId, // For manual plans, approval_id is the source_plan_id
          );
          print('✅ Plans - Daily training plans deleted for approval_id: $approvalId');
        } catch (e) {
          print('⚠️ Plans - Error deleting daily training plans (backend may handle cascading deletes): $e');
          // Don't fail the entire deletion if this fails - backend should handle cascading deletes
        }
      }
      
      // Step 2: Delete the manual plan from backend
      bool planDeletedFromBackend = false;
      try {
      await _manualService.deletePlan(planId);
        planDeletedFromBackend = true;
        print('✅ Plans - Plan $planId deleted successfully from backend');
      } on Exception catch (e) {
        final msg = e.toString();
        if (msg.contains('not found') || msg.contains('404')) {
          print('⚠️ Plans - Plan $planId not found in backend (404). Trying fallback...');
          
          // Try fallback using plan_id if available in list
          final alt = manualPlans.firstWhereOrNull((p) => int.tryParse(p['plan_id']?.toString() ?? '') == planId);
          final int? altId = alt != null ? int.tryParse(alt['id']?.toString() ?? '') : null;
          if (altId != null && altId != planId) {
            print('🗑️ Plans - Retrying delete using alt id $altId for plan_id $planId');
            try {
            await _manualService.deletePlan(altId);
              planDeletedFromBackend = true;
              print('✅ Plans - Plan deleted successfully using alt id $altId');
            } catch (altError) {
              final altMsg = altError.toString();
              if (altMsg.contains('not found') || altMsg.contains('404')) {
                print('⚠️ Plans - Plan not found in backend (already deleted or doesn\'t exist). Cleaning up local state only.');
                // Plan doesn't exist in backend - treat as successful deletion (clean up local state)
                planDeletedFromBackend = false; // Will clean up local state below
          } else {
            rethrow;
              }
          }
        } else {
            // Plan not found in backend - treat as successful deletion (clean up local state)
            print('⚠️ Plans - Plan $planId not found in backend (already deleted or doesn\'t exist). Cleaning up local state only.');
            planDeletedFromBackend = false; // Will clean up local state below
          }
        } else {
          // Other errors should be rethrown
          print('❌ Plans - Error deleting plan from backend: $e');
          rethrow;
        }
      }
      
      // Step 3: Remove from local list (always do this, even if backend deletion failed)
      final removedCount = manualPlans.length;
      manualPlans.removeWhere((plan) {
        final int id = int.tryParse(plan['id']?.toString() ?? '') ?? -1;
        final int pid = int.tryParse(plan['plan_id']?.toString() ?? '') ?? -1;
        return id == planId || pid == planId;
      });
      final remainingCount = manualPlans.length;
      print('🗑️ Plans - Removed plan from local list (${removedCount - remainingCount} plan(s) removed)');
      
      // Step 4: Remove from started plans if it was started
      if (_startedPlans.containsKey(planId)) {
        _startedPlans.remove(planId);
        await _persistStartedPlansToCache();
        print('🗑️ Plans - Removed plan $planId from started plans');
      }
      
      // Step 5: Clear active plan if it was the deleted plan
      final activePlanId = int.tryParse(_activePlan.value?['id']?.toString() ?? '') ?? -1;
      if (activePlanId == planId) {
        _activePlan.value = null;
        await _clearActivePlanSnapshotIfStopped();
        print('🗑️ Plans - Cleared active plan (was plan $planId)');
      }
      
      // Step 6: Remove from planToApprovalId map
      planToApprovalId.remove(planId);
      print('🗑️ Plans - Removed plan $planId from planToApprovalId map');
      
      // Step 7: Clean up stats data for this plan (always do this, even if backend deletion failed)
      try {
        final statsController = Get.find<StatsController>();
        await statsController.cleanupStatsForPlan(planId);
        print('✅ Plans - Stats data cleaned up for plan $planId');
        
        // Refresh stats to sync with backend after deletion
        if (planDeletedFromBackend) {
          await statsController.refreshStats(forceSync: true);
          print('✅ Plans - Stats refreshed after plan deletion');
        } else {
          print('⚠️ Plans - Skipping stats refresh (plan not found in backend)');
        }
      } catch (e) {
        print('⚠️ Plans - Error cleaning up stats for plan $planId: $e');
      }
      
      // Step 8: Refresh plans list to ensure UI is updated
      await refreshPlans();
      
      if (planDeletedFromBackend) {
        print('✅ Plans - Manual plan deleted successfully (plan ID: $planId, approval_id: $approvalId)');
      } else {
        print('✅ Plans - Manual plan removed from local state (plan ID: $planId was not found in backend, may have been already deleted)');
      }
    } catch (e) {
      print('❌ Plans - Error deleting manual plan: $e');
      rethrow;
    }
  }

  Future<void> deleteAiGeneratedPlan(int planId) async {
    try {
      print('🗑️ Plans - Deleting AI generated plan ID: $planId');
      await _aiService.deleteGenerated(planId);
      
      // Remove from local list - check both id and plan_id fields
      aiGeneratedPlans.removeWhere((plan) {
        final int id = int.tryParse(plan['id']?.toString() ?? '') ?? -1;
        final int pid = int.tryParse(plan['plan_id']?.toString() ?? '') ?? -1;
        return id == planId || pid == planId;
      });
      
      // Remove from started plans if it was started
      if (_startedPlans.containsKey(planId)) {
        _startedPlans.remove(planId);
        await _persistStartedPlansToCache();
      }
      
      // Clear active plan if it was the deleted plan
      final activePlanId = int.tryParse(_activePlan.value?['id']?.toString() ?? '') ?? -1;
      if (activePlanId == planId) {
        _activePlan.value = null;
        await _clearActivePlanSnapshotIfStopped();
      }
      
      // Clean up stats data for this plan
      try {
        final statsController = Get.find<StatsController>();
        await statsController.cleanupStatsForPlan(planId);
        print('✅ Plans - Stats data cleaned up for plan $planId');
      } catch (e) {
        print('⚠️ Plans - Error cleaning up stats for plan $planId: $e');
      }
      
      // Refresh plans to ensure UI is updated
      await refreshPlans();
      
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

  Future<void> resetManualPlanCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _profileController.user?.id ?? 0;
      // Keys
      final startedKey = 'startedPlans_user_$userId';
      final activeKey = 'activePlan_user_$userId';
      final approvalKey = 'planApprovalIds_user_$userId';
      await prefs.remove(startedKey);
      await prefs.remove(activeKey);
      await prefs.remove(approvalKey);
      // Remove per-plan day indexes
      for (final plan in manualPlans) {
        final int id = int.tryParse(plan['id']?.toString() ?? '') ?? -1;
        if (id > 0) {
          await prefs.remove('plan_day_${id}_user_$userId');
        }
        final int pid = int.tryParse(plan['plan_id']?.toString() ?? '') ?? -1;
        if (pid > 0) {
          await prefs.remove('plan_day_${pid}_user_$userId');
        }
      }
      // Clear in-memory state
      _startedPlans.clear();
      _activePlan.value = null;
      _currentDay.clear();
      planToApprovalId.clear();
      planApprovalStatus.clear();
      if (!isClosed) update();
      print('🧹 Plans - Manual plan cache reset for user $userId');
    } catch (e) {
      print('❌ Plans - Error resetting manual plan cache: $e');
      rethrow;
    }
  }

  /// Normalize plan items to ensure minutes field is properly synced
  void _normalizePlanItemsForMinutes(Map<String, dynamic> plan) {
    try {
      if (plan['items'] is List) {
        final items = (plan['items'] as List).map((item) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          // Sync minutes and training_minutes: prefer minutes, fallback to training_minutes
          final int minutes = int.tryParse(itemMap['minutes']?.toString() ?? '') ?? 
                             int.tryParse(itemMap['training_minutes']?.toString() ?? '') ?? 0;
          // Ensure both fields are set
          itemMap['minutes'] = minutes;
          itemMap['training_minutes'] = minutes;
          return itemMap;
        }).toList();
        plan['items'] = items;
      }
      
      // Also normalize exercises_details if present
      if (plan['exercises_details'] is List) {
        final exercisesDetails = (plan['exercises_details'] as List).map((item) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          final int minutes = int.tryParse(itemMap['minutes']?.toString() ?? '') ?? 
                             int.tryParse(itemMap['training_minutes']?.toString() ?? '') ?? 0;
          itemMap['minutes'] = minutes;
          itemMap['training_minutes'] = minutes;
          return itemMap;
        }).toList();
        plan['exercises_details'] = exercisesDetails;
      } else if (plan['exercises_details'] is String) {
        try {
          final parsed = jsonDecode(plan['exercises_details'] as String) as List<dynamic>;
          final normalized = parsed.map((item) {
            final itemMap = Map<String, dynamic>.from(item as Map);
            final int minutes = int.tryParse(itemMap['minutes']?.toString() ?? '') ?? 
                               int.tryParse(itemMap['training_minutes']?.toString() ?? '') ?? 0;
            itemMap['minutes'] = minutes;
            itemMap['training_minutes'] = minutes;
            return itemMap;
          }).toList();
          plan['exercises_details'] = normalized;
        } catch (e) {
          print('⚠️ Plans - Could not parse exercises_details JSON: $e');
        }
      }
    } catch (e) {
      print('⚠️ Plans - Error normalizing plan items for minutes: $e');
    }
  }
}
