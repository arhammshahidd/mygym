import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';

class AuthController extends GetxController {
  final AuthService _authService = AuthService();
  
  // Observable variables
  final _isLoggedIn = false.obs;
  final _isLoading = false.obs;
  final _errorMessage = ''.obs;

  // Getters
  bool get isLoggedIn => _isLoggedIn.value;
  bool get isLoading => _isLoading.value;
  String get errorMessage => _errorMessage.value;

  @override
  void onInit() {
    super.onInit();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      _isLoading.value = true;
      final loggedIn = await _authService.isLoggedIn();
      _isLoggedIn.value = loggedIn;
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> login(String phone, String password) async {
    try {
      _isLoading.value = true;
      _errorMessage.value = '';
      
      await _authService.login(phone: phone, password: password);
      _isLoggedIn.value = true;
      
      // Navigate to dashboard after successful login
      Get.offAllNamed('/dashboard');
      
      Get.snackbar(
        'Success',
        'Logged in successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Colors.white,
      );
    } catch (e) {
      _errorMessage.value = e.toString();
      Get.snackbar(
        'Login Failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> logout() async {
    try {
      _isLoading.value = true;
      await _authService.logout();
      _isLoggedIn.value = false;
      
      // Navigate to login page
      Get.offAllNamed('/login');
      
      Get.snackbar(
        'Logged Out',
        'You have been logged out successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Colors.white,
      );
    } catch (e) {
      _errorMessage.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  void clearError() {
    _errorMessage.value = '';
  }
}
