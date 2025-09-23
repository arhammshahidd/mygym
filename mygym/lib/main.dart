import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'core/bindings/app_binding.dart';
import 'shared/widgets/auth_gate.dart';
import 'shared/widgets/main_tab_screen.dart';
import 'features/auth/presentation/pages/login_page.dart';

void main() {
  runApp(const MyGymApp());
}

class MyGymApp extends StatelessWidget {
  const MyGymApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MyGym',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // Green theme for gym app
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      initialBinding: AppBinding(),
      getPages: [
        GetPage(name: '/', page: () => const AuthGate()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/dashboard', page: () => const MainTabScreen()),
      ],
      initialRoute: '/',
    );
  }
}


