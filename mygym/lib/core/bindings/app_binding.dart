import 'package:get/get.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/profile_controller.dart';
import '../../features/trainings/presentation/controllers/schedules_controller.dart';
import '../../features/trainings/presentation/controllers/plans_controller.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(AuthController());
    Get.put(ProfileController());
    // Keep trainings state alive across hot reloads/navigation
    Get.put(SchedulesController(), permanent: true);
    Get.put(PlansController(), permanent: true);
  }
}
