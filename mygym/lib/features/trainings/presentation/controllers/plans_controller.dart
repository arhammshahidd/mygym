import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../stats/presentation/controllers/stats_controller.dart';
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
  final Map<String, bool> _workoutTimers = {};
  final Map<String, int> _currentDay = {};
  
  // Plans-specific approval tracking
  final RxMap<int, String> planApprovalStatus = <int, String>{}.obs;
  final RxMap<int, int> planToApprovalId = <int, int>{}.obs;
  bool _approvalCacheLoaded = false;

  @override
  void onInit() {
    super.onInit();
    _loadStartedPlansFromCache();
    _loadActivePlanSnapshot();
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
      
      // Test API connectivity
      await _manualService.testApiConnectivity();
      
      // Fetch manual training plans (Plans-specific)
      try {
        print('📝 Plans - Fetching manual training plans...');
        final manualRes = await _manualService.listPlans();
        print('📝 Plans - Manual plans result: ${manualRes.length} items');
        
        manualPlans.assignAll(manualRes.map((e) => Map<String, dynamic>.from(e)));
        print('✅ Plans - Manual plans list updated: ${manualPlans.length} items');
      } catch (e) {
        print('⚠️ Plans - Failed to load manual plans: $e');
        manualPlans.clear();
      }

      // Fetch AI generated plans (Plans-specific)
      try {
        print('🤖 Plans - Fetching AI generated plans...');
        final aiRes = await _aiService.listGenerated(userId: userId);
        print('🤖 Plans - AI plans result: ${aiRes.length} items');
        
        aiGeneratedPlans.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
        print('✅ Plans - AI plans list updated: ${aiGeneratedPlans.length} items');
      } catch (e) {
        print('⚠️ Plans - Failed to load AI plans: $e');
        aiGeneratedPlans.clear();
      }
      
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

  void startPlan(Map<String, dynamic> plan) {
    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
    if (planId == null) return;
    
    _startedPlans[planId] = true;
    _activePlan.value = plan;
    _currentDay[planId.toString()] = 0;
    
    _persistStartedPlansToCache();
    _persistActivePlanSnapshot();
  }

  void stopPlan(Map<String, dynamic> plan) {
    final int? planId = int.tryParse(plan['id']?.toString() ?? '');
    if (planId == null) return;
    
    _startedPlans[planId] = false;
    if (_activePlan.value != null && (_activePlan.value!['id']?.toString() ?? '') == planId.toString()) {
      _activePlan.value = null;
    }
    
    _persistStartedPlansToCache();
    _clearActivePlanSnapshotIfStopped();
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

  // Approval methods for plans
  String getPlanApprovalStatus(int planId) {
    return planApprovalStatus[planId] ?? 'none';
  }

  void setPlanApprovalStatus(int planId, String status) {
    planApprovalStatus[planId] = status;
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
          aiGeneratedPlans.assignAll(after.map((e) => Map<String, dynamic>.from(e)));
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
    return await _manualService.updatePlan(id, payload);
  }

  Future<Map<String, dynamic>> updateAiGeneratedPlan(int id, Map<String, dynamic> payload) async {
    return await _aiService.updateGenerated(id, payload);
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
  }

  Future<void> refreshManualPlans() async {
    try {
      final manualRes = await _manualService.listPlans();
      manualPlans.assignAll(manualRes.map((e) => Map<String, dynamic>.from(e)));
    } catch (e) {
      print('❌ Plans - Error refreshing manual plans: $e');
    }
  }

  Future<void> refreshAiPlans() async {
    try {
      final aiRes = await _aiService.listGenerated(userId: _profileController.user?.id);
      aiGeneratedPlans.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
    } catch (e) {
      print('❌ Plans - Error refreshing AI plans: $e');
    }
  }

  void clearAiGeneratedPlans() {
    aiGeneratedPlans.clear();
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
      
      // Submit to daily training API
      await _dailyTrainingService.submitCompletion(
        dailyPlanId: planId,
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
}
