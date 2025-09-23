import 'package:get/get.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/profile_controller.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(AuthController());
    Get.put(ProfileController());
  }
}
