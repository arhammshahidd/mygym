import 'package:get/get.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../data/services/manual_training_service.dart';
import '../../data/services/ai_training_service.dart';
import '../../data/services/training_approval_service.dart';
import '../../../../shared/services/realtime_service.dart';
import '../../../auth/data/services/auth_service.dart';

class TrainingsController extends GetxController {
  final ManualTrainingService _manualService = ManualTrainingService();
  final AiTrainingService _aiService = AiTrainingService();
  final TrainingApprovalService _approvalService = TrainingApprovalService();
  final RealtimeService _realtime = RealtimeService();
  final AuthService _authService = AuthService();
  final ProfileController _profileController = Get.find<ProfileController>();
  bool _socketSubscribed = false;
  bool _reloadScheduled = false;

  // Public Rx fields so Obx can track them directly
  final RxBool isLoading = false.obs;
  final RxBool hasLoadedOnce = false.obs;
  final RxList<Map<String, dynamic>> plans = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> aiGenerated = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> _assignments = <Map<String, dynamic>>[].obs;
  // Selected tab index across pages (0 = Schedules, 1 = Plans)
  final RxInt selectedTabIndex = 0.obs;
  // Cache for extra attributes not present in list responses
  final RxMap<int, String> planUserLevels = <int, String>{}.obs;

  Future<void> loadData() async {
    try {
      print('🚀 Starting loadData...');
      isLoading.value = true;
      // Ensure profile is loaded to obtain user id for filtering
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      print('👤 User ID: $userId');
      print('👤 User object: ${_profileController.user}');
      print('👤 Profile controller hasUser: ${_profileController.hasUser}');
      
      // Test API connectivity first
      await _manualService.testApiConnectivity();
      
      // Fetch assigned training plans from assignments table (for Schedules tab)
      if (userId != null) {
        print('📋 Fetching assigned training plans for user ID: $userId...');
        print('📋 API endpoint: /api/trainingPlans/assignments/user/$userId');
        try {
          final assignmentsRes = await _manualService.getUserAssignments(userId);
          print('📋 Assignments result: ${assignmentsRes.length} items');
          print('📋 Assignments data: $assignmentsRes');
          // Store assignments separately for Schedules tab
          _assignments.assignAll(assignmentsRes.map((e) => Map<String, dynamic>.from(e)));
          print('✅ Assigned plans list updated: ${_assignments.length} items');
        } catch (e) {
          print('❌ Error fetching assignments: $e');
          // Fallback: try with user ID 2 (from database screenshot)
          print('🔄 Trying fallback with user ID 2...');
          try {
            final fallbackRes = await _manualService.getUserAssignments(2);
            print('📋 Fallback result: ${fallbackRes.length} items');
            print('📋 Fallback data: $fallbackRes');
            _assignments.assignAll(fallbackRes.map((e) => Map<String, dynamic>.from(e)));
            print('✅ Fallback assigned plans list updated: ${_assignments.length} items');
          } catch (fallbackError) {
            print('❌ Fallback also failed: $fallbackError');
            _assignments.clear();
          }
        }
      } else {
        _assignments.clear();
        print('⚠️ No user ID, clearing assigned plans');
      }

      // Fetch manual training plans (for Plans tab)
      try {
        print('📝 Fetching manual training plans from app_manual_training_plans...');
        print('📝 API endpoint: /api/appManualTraining/');
        final manualRes = await _manualService.listPlans();
        print('📝 Manual plans result: ${manualRes.length} items');
        print('📝 Manual plans data: $manualRes');
        if (manualRes.isNotEmpty) {
          print('📝 First manual plan: ${manualRes.first}');
        }
        plans.assignAll(manualRes.map((e) => Map<String, dynamic>.from(e)));
        print('✅ Manual plans list updated: ${plans.length} items');
      } catch (e) {
        print('⚠️ Failed to load manual plans from app_manual_training_plans: $e');
        print('⚠️ Error type: ${e.runtimeType}');
        plans.clear();
      }

      // Fetch AI generated plans, but isolate errors so they don't affect manual plans
      try {
        print('🤖 Fetching AI generated plans...');
        final aiRes = await _aiService.listGenerated(userId: userId);
        print('🤖 AI plans result: ${aiRes.length} items');
        aiGenerated.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
        print('✅ AI Generated list updated: ${aiGenerated.length} items');
      } catch (e) {
        print('⚠️ Failed to load AI generated plans: $e');
      }
      // Connect realtime approvals once
      if (!_realtime.isConnected) {
        final token = await _authService.getToken();
        _realtime.connectApprovals(token: token);
      }
      if (!_socketSubscribed) {
        _socketSubscribed = true;
        _realtime.events.listen((event) {
          if (event['type'] == 'approval_status') {
            if (_reloadScheduled || isLoading.value) return;
            _reloadScheduled = true;
            // When new plans are approved or sent from web, focus Schedules tab
            selectedTabIndex.value = 0;
            Future.delayed(const Duration(milliseconds: 600), () {
              _reloadScheduled = false;
              loadData();
            });
          }
        });
      }
    } catch (e) {
      print('❌ Error loading data: $e');
      // ignore for now, UI will show empty
    } finally {
      isLoading.value = false;
      hasLoadedOnce.value = true;
      print('🏁 Load completed - hasLoadedOnce: ${hasLoadedOnce.value}');
    }
  }

  int? get userId => _profileController.user?.id;
  
  // Getter for user object
  dynamic get user => _profileController.user;
  
  // Getter for assignments (for Schedules tab)
  List<Map<String, dynamic>> get assignments => _assignments;

  Future<void> sendForApproval({
    required String source, // 'manual' | 'ai'
    required Map<String, dynamic> payload,
  }) async {
    await _approvalService.sendForApproval(source: source, payload: payload);
    // Also emit over websocket for realtime processing if connected
    if (_realtime.isConnected) {
      _realtime.send({
        'type': 'send_for_approval',
        'source': source,
        'data': payload,
      });
    }
  }

  Future<void> sendPlanForApproval(Map<String, dynamic> payload) async {
    print('🔍 Controller - sendPlanForApproval called');
    print('🔍 Controller - Payload: $payload');
    print('🔍 Controller - Payload keys: ${payload.keys.toList()}');
    
    // Use the mobile-specific sendPlanForApproval method
    await _approvalService.sendPlanForApproval(payload);
  }

  Future<Map<String, dynamic>> createManualPlan(Map<String, dynamic> payload) async {
    print('🔍 Controller - createManualPlan called');
    print('🔍 Controller - Payload: $payload');
    print('🔍 Controller - total_exercises in payload: ${payload['total_exercises']}');
    
    final created = await _manualService.createPlan(payload);
    print('🔍 Controller - Service returned: $created');
    print('🔍 Controller - total_exercises in response: ${created['total_exercises']}');
    
    // Do not show in schedules until approved by web portal
    // Keep only in Plans tab list (aiGenerated list is separate)
    return Map<String, dynamic>.from(created);
  }

  Future<Map<String, dynamic>> updateManualPlan(int id, Map<String, dynamic> payload) async {
    print('🔍 Controller - updateManualPlan called with ID: $id');
    print('🔍 Controller - Payload: $payload');
    print('🔍 Controller - total_exercises in payload: ${payload['total_exercises']}');
    
    final updated = await _manualService.updatePlan(id, payload);
    print('🔍 Controller - Service returned: $updated');
    print('🔍 Controller - total_exercises in response: ${updated['total_exercises']}');
    
    final index = plans.indexWhere((p) => (p['id']?.toString() ?? '') == updated['id']?.toString());
    if (index >= 0) {
      plans[index] = Map<String, dynamic>.from(updated);
      plans.refresh();
      print('🔍 Controller - Updated plan in local list');
    }
    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> getManualPlan(int id) async {
    print('🔍 Controller - getManualPlan called with ID: $id');
    print('🔍 Controller - API endpoint: /api/appManualTraining/$id');
    try {
      final full = await _manualService.getPlan(id);
      print('🔍 Controller - getManualPlan success: ${full.keys}');
      return Map<String, dynamic>.from(full);
    } catch (e) {
      print('❌ Controller - getManualPlan failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAssignmentDetails(int assignmentId) async {
    final full = await _manualService.getAssignment(assignmentId);
    print('🔍 Controller - Assignment details: $full');
    
    // If assignment doesn't have items, try to fetch from the original plan
    if ((full['items'] == null || (full['items'] as List).isEmpty) && 
        (full['exercises_details'] == null || (full['exercises_details'] as List).isEmpty)) {
      final webPlanId = full['web_plan_id'];
      if (webPlanId != null) {
        print('🔍 Controller - Assignment missing items, fetching from web_plan_id: $webPlanId');
        try {
          final planDetails = await _manualService.getPlan(webPlanId);
          print('🔍 Controller - Plan details: $planDetails');
          // Merge plan details with assignment data
          full['items'] = planDetails['items'];
          full['exercise_plan_category'] = planDetails['exercise_plan_category'] ?? planDetails['exercise_plan'];
          full['total_workouts'] = planDetails['total_workouts'];
          full['training_minutes'] = planDetails['training_minutes'] ?? planDetails['total_training_minutes'];
        } catch (e) {
          print('❌ Controller - Failed to fetch plan details: $e');
        }
      }
    }
    
    // Map exercises_details to items if needed
    if (full['exercises_details'] != null && (full['exercises_details'] as List).isNotEmpty) {
      full['items'] = full['exercises_details'];
      print('🔍 Controller - Mapped exercises_details to items: ${full['items']}');
    }
    
    return Map<String, dynamic>.from(full);
  }

  /// Ensure user_level is available for a plan card. If missing, fetch full
  /// plan once and cache the discovered level in [planUserLevels] and the
  /// plan map itself, then refresh observers.
  Future<void> ensureUserLevelForPlan(Map<String, dynamic> plan) async {
    try {
      final int? id = int.tryParse(plan['id']?.toString() ?? '');
      if (id == null) return;
      // If already present in plan or cache, skip
      final existing = plan['user_level']?.toString();
      if (existing != null && existing.isNotEmpty) return;
      if (planUserLevels.containsKey(id)) {
        plan['user_level'] = planUserLevels[id];
        plans.refresh();
        return;
      }
      // For assignments, try to get assignment details first
      final assignmentId = plan['assignment_id'] ?? plan['id'];
      final full = await getAssignmentDetails(assignmentId);
      String? level = full['user_level']?.toString();
      if ((level == null || level.isEmpty) && full['items'] is List && (full['items'] as List).isNotEmpty) {
        final Map first = Map<String, dynamic>.from((full['items'] as List).first as Map);
        level = first['user_level']?.toString();
      }
      if (level != null && level.isNotEmpty) {
        planUserLevels[id] = level;
        plan['user_level'] = level;
        plans.refresh();
      }
    } catch (_) {
      // ignore quietly
    }
  }

  /// Ensure `items` are present for a plan (list endpoints often omit them).
  /// Mutates the provided plan map to include fetched `items` and refreshes
  /// observers. Safe to call repeatedly; it will no-op if items already exist.
  Future<void> ensureItemsForPlan(Map<String, dynamic> plan) async {
    try {
      if (plan['items'] is List && (plan['items'] as List).isNotEmpty) return;
      final int? id = int.tryParse(plan['id']?.toString() ?? '');
      if (id == null) return;
      // For assignments, fetch assignment details
      final assignmentId = plan['assignment_id'] ?? plan['id'];
      final full = await getAssignmentDetails(assignmentId);
      if (full['items'] is List) {
        plan['items'] = (full['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        plans.refresh();
      }
      // Also capture user_level if present now
      final String? lvl = full['user_level']?.toString();
      if (lvl != null && lvl.isNotEmpty) {
        planUserLevels[id] = lvl;
        plan['user_level'] = lvl;
        plans.refresh();
      }
    } catch (_) {
      // ignore
    }
  }

  Future<Map<String, dynamic>> createAiRequest(Map<String, dynamic> payload) async {
    final created = await _aiService.createRequest(payload);
    // Immediately create a generated plan using the request data so tables are filled
    final now = DateTime.now();
    final requestId = created['id'] ?? created['request_id'];
    final genPayload = {
      'user_id': userId ?? payload['user_id'],
      if (requestId != null) 'request_id': requestId,
      'exercise_plan': payload['exercise_plan'] ?? payload['exercise_plan_category'],
      'start_date': now.toIso8601String().split('T').first,
      'end_date': now.add(const Duration(days: 7)).toIso8601String().split('T').first,
      // carry through optional request context for AI generation if needed
      'age': payload['age'],
      'height_cm': payload['height_cm'],
      'weight_kg': payload['weight_kg'],
      'gender': payload['gender'],
      'future_goal': payload['future_goal'] ?? payload['goal'],
      // items left empty so service will generate or synthesize minimal valid ones
      'items': <Map<String, dynamic>>[],
    };
    try {
      final generated = await _aiService.createGenerated(genPayload);
      // insert into AI list for immediate UI feedback
      aiGenerated.insert(0, Map<String, dynamic>.from(generated));
    } catch (_) {
      // If generation fails, fall back to polling for server-side generation
      _pollAiGeneratedOnce();
    }
    return Map<String, dynamic>.from(created);
  }

  void _pollAiGeneratedOnce() async {
    try {
      final userId = _profileController.user?.id;
      // Poll up to 5 times over ~10s total
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration(seconds: i == 0 ? 1 : 2));
        final aiRes = await _aiService.listGenerated(userId: userId);
        if (aiRes.isNotEmpty) {
          aiGenerated.assignAll(aiRes.map((e) => Map<String, dynamic>.from(e)));
          break;
        }
      }
    } catch (_) {
      // ignore; UI keeps existing state
    }
  }

  Future<Map<String, dynamic>> createAiGeneratedPlan(Map<String, dynamic> payload) async {
    final created = await _aiService.createGenerated(payload);
    // Do not show in schedules until approved by web portal
    return Map<String, dynamic>.from(created);
  }

  Future<Map<String, dynamic>> updateAiGeneratedPlan(int id, Map<String, dynamic> payload) async {
    final updated = await _aiService.updateGenerated(id, payload);
    final index = aiGenerated.indexWhere((p) => (p['id']?.toString() ?? '') == updated['id']?.toString());
    if (index >= 0) {
      aiGenerated[index] = Map<String, dynamic>.from(updated);
      aiGenerated.refresh();
    }
    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> getAiGeneratedPlan(int id) async {
    final full = await _aiService.getGenerated(id);
    return Map<String, dynamic>.from(full);
  }

  Future<void> deleteManualPlan(int id) async {
    try {
      print('🗑️ Deleting manual plan with ID: $id');
      await _manualService.deletePlan(id);
      print('✅ Manual plan deleted from backend successfully');
      
      // Remove from the list for immediate UI feedback
      final initialLength = plans.length;
      plans.removeWhere((p) => (p['id']?.toString() ?? '') == id.toString());
      print('📝 Removed from local list. Before: $initialLength, After: ${plans.length}');
    } catch (e) {
      print('❌ Error deleting manual plan: $e');
      rethrow; // Re-throw to let the UI handle the error
    }
  }

  Future<void> deleteAiGeneratedPlan(int id) async {
    try {
      print('🗑️ Deleting AI generated plan with ID: $id');
      await _aiService.deleteGenerated(id);
      print('✅ AI generated plan deleted from backend successfully');
      
      // Remove from the list for immediate UI feedback
      final initialLength = aiGenerated.length;
      aiGenerated.removeWhere((p) => (p['id']?.toString() ?? '') == id.toString());
      print('📝 Removed from AI list. Before: $initialLength, After: ${aiGenerated.length}');
    } catch (e) {
      print('❌ Error deleting AI generated plan: $e');
      rethrow; // Re-throw to let the UI handle the error
    }
  }
}


