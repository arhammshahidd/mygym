import 'package:get/get.dart';
import 'package:flutter/material.dart';
import '../../../../shared/models/user_model.dart';
import '../../data/services/profile_service.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

class ProfileController extends GetxController {
  final ProfileService _profileService = ProfileService();
  
  // Observable variables
  final _user = Rxn<User>();
  final _isLoading = false.obs;
  final _errorMessage = ''.obs;

  // Getters
  User? get user => _user.value;
  bool get isLoading => _isLoading.value;
  String get errorMessage => _errorMessage.value;
  bool get hasUser => _user.value != null;

  @override
  void onInit() {
    super.onInit();
    // Check if user is authenticated and load profile
    _checkAndLoadProfile();
  }

  Future<void> _checkAndLoadProfile() async {
    try {
      final authController = Get.find<AuthController>();
      if (authController.isLoggedIn && !hasUser) {
        await loadUserProfile();
      }
    } catch (e) {
      print('Profile controller: Could not check auth status: $e');
    }
  }

  Future<void> loadUserProfile() async {
    try {
      _isLoading.value = true;
      _errorMessage.value = '';
      
      print('🔐 Loading user profile...');
      final user = await _profileService.getCurrentUserProfile();
      _user.value = user;
      
      if (user.id == 1 && user.name == 'User') {
        print('🔐 Using fallback user profile - backend profile endpoint may be unavailable');
      } else {
        print('🔐 Successfully loaded real user profile: ${user.name} (ID: ${user.id})');
      }
    } catch (e) {
      _errorMessage.value = e.toString();
      print('🔐 Profile loading failed: $e');
      Get.snackbar(
        'Error',
        'Failed to load profile: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> loadUserProfileIfNeeded() async {
    if (!hasUser && !isLoading) {
      await loadUserProfile();
    }
  }

  Future<void> updateUserProfile(User updatedUser) async {
    try {
      _isLoading.value = true;
      _errorMessage.value = '';
      
      final user = await _profileService.updateUserProfile(updatedUser);
      _user.value = user;
      
      Get.snackbar(
        'Success',
        'Profile updated successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Get.theme.colorScheme.primary,
        colorText: Colors.white,
      );
    } catch (e) {
      _errorMessage.value = e.toString();
      Get.snackbar(
        'Error',
        'Failed to update profile: ${e.toString()}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> updateNotificationPreferences({
    bool? workoutAlerts,
    bool? mealReminders,
  }) async {
    if (_user.value == null) return;
    
    final updatedUser = _user.value!.copyWith(
      prefWorkoutAlerts: workoutAlerts,
      prefMealReminders: mealReminders,
    );
    
    await updateUserProfile(updatedUser);
  }

  void clearError() {
    _errorMessage.value = '';
  }

  void clearUser() {
    _user.value = null;
  }

  @override
  void refresh() {
    loadUserProfile();
  }
}
