import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';
 

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = Get.find<AuthController>();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    
    _authController.login(
      _phoneController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.appBackgroundColor,
              AppTheme.cardBackgroundColor,
              AppTheme.primaryColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Icon Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackgroundColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryColor, width: 2),
                    ),
                    child: const Icon(
                      Icons.fitness_center,
                      size: 60,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Welcome Text
                  const Text(
                    'Welcome to MyGym',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue your fitness journey',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Login Form Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackgroundColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primaryColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Phone Field
                          TextFormField(
                            controller: _phoneController,
                            style: const TextStyle(color: AppTheme.textColor),
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              labelStyle: const TextStyle(color: AppTheme.textColor),
                              hintText: '+1234567890',
                              hintStyle: TextStyle(color: AppTheme.textColor.withOpacity(0.7)),
                              prefixIcon: const Icon(Icons.phone, color: AppTheme.textColor),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                              ),
                              filled: true,
                              fillColor: AppTheme.appBackgroundColor,
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Phone number is required';
                              final phoneDigits = value.replaceAll(RegExp(r'[^\d]'), '');
                              if (phoneDigits.length < 10) return 'Enter a valid phone number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          
                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            style: const TextStyle(color: AppTheme.textColor),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: AppTheme.textColor),
                              prefixIcon: const Icon(Icons.lock, color: AppTheme.textColor),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                              ),
                              filled: true,
                              fillColor: AppTheme.appBackgroundColor,
                            ),
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Password is required';
                              if (value.length < 6) return 'Min 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),
                          
                          // Login Button
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryColor, AppTheme.primaryColor],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primaryColor, width: 2),
                            ),
                            child: Obx(() => ElevatedButton(
                              onPressed: _authController.isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _authController.isLoading
                                  ? const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textColor),
                                    )
                                  : const Text(
                                      'LOGIN',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textColor,
                                      ),
                                    ),
                            )),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  
                  
                  // Footer Text
                  const Text(
                    'Start your fitness journey today!',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Account Status Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Note: Make sure your account is ACTIVE in the system',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

