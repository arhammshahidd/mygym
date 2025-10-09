# OpenAI API Key Setup

To enable full AI meal plan generation, you need to configure your OpenAI API key.

## Option 1: Environment Variable (Recommended)

### For Development:
```bash
# Windows (PowerShell)
$env:OPENAI_API_KEY="your-api-key-here"
flutter run

# Windows (Command Prompt)
set OPENAI_API_KEY=your-api-key-here
flutter run

# macOS/Linux
export OPENAI_API_KEY="your-api-key-here"
flutter run
```

### For Production Build:
```bash
flutter build apk --dart-define=OPENAI_API_KEY=your-api-key-here
flutter build ios --dart-define=OPENAI_API_KEY=your-api-key-here
```

## Option 2: Direct Configuration

You can also modify `mygym/lib/core/constants/app_constants.dart`:

```dart
static const String openAIApiKey = 'your-api-key-here'; // Replace with your actual key
```

**Note**: This method is not recommended for production as it exposes your API key in the source code.

## Getting an OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/)
2. Sign up or log in to your account
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key and use it in the configuration above

## Current Behavior

- **With API Key**: Full AI-generated meal plans with personalized recommendations
- **Without API Key**: Fallback to gym-friendly meal plans (no Pakistani dishes, general fitness meals)

## Fallback Meals

When OpenAI is not configured, the app will generate gym-friendly meals like:
- **Breakfast**: Protein Oatmeal with Berries, Greek Yogurt Parfait, Scrambled Eggs with Toast
- **Lunch**: Grilled Chicken with Quinoa, Salmon with Sweet Potato, Turkey Wrap with Vegetables
- **Dinner**: Baked Chicken Breast with Vegetables, Grilled Fish with Rice, Lean Steak with Roasted Potatoes

These meals are designed for fitness enthusiasts and provide balanced nutrition for gym workouts.