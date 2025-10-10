import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/profile_controller.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _profileController;
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _profileController = Get.find<ProfileController>();
    _authController = Get.find<AuthController>();
    
    // Ensure profile data is loaded
    _profileController.loadUserProfileIfNeeded();
  }

  void _logout() {
    _authController.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.appBackgroundColor,
        elevation: 0,
        foregroundColor: AppTheme.textColor,
        actions: [
          IconButton(
            onPressed: () {
              Get.to(() => const EditProfilePage());
            },
            icon: const Icon(Icons.edit, color: AppTheme.textColor),
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: Obx(() {
        if (_profileController.isLoading) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
        }
        
        if (_profileController.errorMessage.isNotEmpty) {
          return _buildErrorState();
        }
        
        if (_profileController.hasUser) {
          return _buildProfileContent();
        }
        
        return const Center(child: Text('No user data', style: TextStyle(color: AppTheme.textColor)));
      }),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            'Error loading profile',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            _profileController.errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textColor),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _profileController.refresh,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: AppTheme.textColor),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return RefreshIndicator(
      onRefresh: _profileController.loadUserProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
        children: [
          // User Profile Header
          _buildProfileHeader(),
          const SizedBox(height: 24),
          
          // Personal Information Section
          _buildPersonalInfoSection(),
          const SizedBox(height: 24),
          
          // Notifications Section
          _buildNotificationsSection(),
          const SizedBox(height: 24),
          
          // Support Section
          _buildSupportSection(),
          const SizedBox(height: 32),
          
          // Sign Out Button
          _buildSignOutButton(),
        ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _profileController.user!.initials,
                style: const TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Name and Premium Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _profileController.user!.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: AppTheme.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'PREMIUM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Email
          Text(
            _profileController.user!.email,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 16),
          
          // Member Since
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primaryColor),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Since March 2025',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Information',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          icon: Icons.person,
          title: 'Basic Info',
          subtitle: 'Age: ${_profileController.user!.age ?? 'Not set'}, Weight: ${_profileController.user!.formattedWeight}, Height: ${_profileController.user!.formattedHeight}',
          onTap: () {
            Get.to(() => const EditProfilePage());
          },
        ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notifications',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 12),
        _buildNotificationCard(
          icon: Icons.notifications,
          title: 'Notifications',
          subtitle: 'Workout reminders, meal alerts',
          isEnabled: _profileController.user!.prefWorkoutAlerts,
          onToggle: (value) {
            _profileController.updateNotificationPreferences(
              workoutAlerts: value,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSupportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Support',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          icon: Icons.support_agent,
          title: 'Contact Support',
          subtitle: 'Get help from our team',
          onTap: () {
            // TODO: Navigate to support
          },
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textColor),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textColor),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textColor)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textColor),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNotificationCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.textColor),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textColor),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textColor)),
        trailing: Switch(
          value: isEnabled,
          onChanged: onToggle,
          activeColor: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primaryColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ElevatedButton.icon(
        onPressed: _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(
          Icons.logout,
          color: AppTheme.primaryColor,
        ),
        label: const Text(
          'Sign out',
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
