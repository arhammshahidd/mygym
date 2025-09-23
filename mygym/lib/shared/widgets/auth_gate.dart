import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import 'main_tab_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController authController = Get.find();
    
    return Obx(() {
      if (authController.isLoading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      
      if (authController.isLoggedIn) {
        return const MainTabScreen();
      } else {
        return const LoginPage();
      }
    });
  }
}
