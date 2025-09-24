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

  Future<void> loadData() async {
    try {
      print('🚀 Starting loadData...');
      isLoading.value = true;
      // Ensure profile is loaded to obtain user id for filtering
      await _profileController.loadUserProfileIfNeeded();
      final userId = _profileController.user?.id;
      print('👤 User ID: $userId');
      
      print('📋 Fetching manual plans...');
      final plansRes = await _manualService.listPlans();
      print('📋 Manual plans result: ${plansRes.length} items');
      print('📋 Manual plans data: $plansRes');
      // Assign manual plans immediately so an error in AI fetch doesn't wipe UI
      plans.assignAll(plansRes.map((e) => Map<String, dynamic>.from(e)));
      print('✅ Plans list updated: ${plans.length} items');

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

  Future<Map<String, dynamic>> createManualPlan(Map<String, dynamic> payload) async {
    print('🔍 Controller - createManualPlan called');
    print('🔍 Controller - Payload: $payload');
    print('🔍 Controller - total_exercises in payload: ${payload['total_exercises']}');
    
    final created = await _manualService.createPlan(payload);
    print('🔍 Controller - Service returned: $created');
    print('🔍 Controller - total_exercises in response: ${created['total_exercises']}');
    
    // Optimistically insert into list for immediate UI feedback
    plans.insert(0, created);
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
    final full = await _manualService.getPlan(id);
    return Map<String, dynamic>.from(full);
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
    aiGenerated.insert(0, Map<String, dynamic>.from(created));
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


