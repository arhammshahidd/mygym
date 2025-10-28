import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/profile/presentation/controllers/profile_controller.dart';
import 'features/trainings/presentation/controllers/schedules_controller.dart';
import 'features/trainings/presentation/controllers/plans_controller.dart';
import 'features/food/presentation/controllers/nutrition_controller.dart';
import 'features/stats/presentation/controllers/stats_controller.dart';
import 'shared/widgets/main_tab_screen.dart';

void main() {
  // Add error handling for Flutter web disposed view issues
  FlutterError.onError = (FlutterErrorDetails details) {
    // Suppress disposed view errors in web
    if (details.exception.toString().contains('disposed EngineFlutterView')) {
      print('Suppressed disposed view error: ${details.exception}');
      return;
    }
    // Log other errors normally
    FlutterError.presentError(details);
  };

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Gym App',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      initialBinding: AppBinding(),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const AuthWrapper()),
        GetPage(name: '/MainTabScreen', page: () => const MainTabScreen()),
        GetPage(name: '/login', page: () => const LoginPage()),
      ],
      unknownRoute: GetPage(name: '/', page: () => const AuthWrapper()),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AuthController>(
      builder: (authController) {
        // Check authentication status
        if (authController.isLoggedIn) {
          return const MainTabScreen();
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<AuthController>(AuthController(), permanent: true);
    Get.put<ProfileController>(ProfileController(), permanent: true);
    Get.put<SchedulesController>(SchedulesController(), permanent: true);
    Get.put<PlansController>(PlansController(), permanent: true);
    Get.put<NutritionController>(NutritionController(), permanent: true);
    Get.put<StatsController>(StatsController(), permanent: true);
  }
}