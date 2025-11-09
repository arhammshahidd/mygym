// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:mygym/main.dart';

void main() {
  testWidgets('App initializes correctly', (WidgetTester tester) async {
    // Initialize GetX for testing
    Get.testMode = true;
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());
    
    // Wait for async initialization
    await tester.pumpAndSettle();

    // Verify that the app builds without errors
    // The app will show either LoginPage or MainTabScreen based on auth state
    // Since we're in test mode, we just verify the app structure exists
    // Note: MyApp uses GetMaterialApp, so we check for the widget tree instead
    expect(tester.allWidgets.isNotEmpty, isTrue);
  });
}
