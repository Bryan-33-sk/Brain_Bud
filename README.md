# 🧠 Brain Bud

**A Flutter-based Android app that tracks your screen time and provides emotional feedback through an animated character based on your social media usage.**

---

## 📱 Overview

Brain Bud is a digital wellbeing application that helps users become more aware of their smartphone usage patterns, particularly focusing on social media consumption. The app features a unique animated "Brain Bud" character that changes its mood based on how much time you spend on social media apps, providing an emotional and visual representation of your digital habits.

### Key Concept

Instead of overwhelming users with raw data and lists of apps, Brain Bud uses a friendly animated character that reacts to your social media usage:
- **😊 Happy** - When you spend less than 30 minutes on social media
- **😐 Neutral** - When you spend 30 minutes to 2 hours on social media  
- **😢 Sad** - When you spend more than 2 hours on social media

---

## ✨ Features

### 🎨 Main Screen

1. **Animated Brain Bud Character**
   - Custom-painted animated character with 3 distinct mood expressions
   - Gentle floating animation
   - Mood-based color glow effect (green/yellow/red)
   - Real-time mood updates based on social media usage

2. **Mood-Based Messages**
   - Personalized messages that change based on your social media time
   - Examples:
     - "No social media today! I'm so proud of you! 🌟"
     - "Only 15m on social media. Great balance! 🎉"
     - "1h 30m on social media. Maybe take a break? 🤔"
     - "3h 45m scrolling... I miss the real you 😢"

3. **Summary Card**
   - Total screen time for today (midnight to now)
   - Quick stats: Total apps, Social apps, Productivity apps, Games
   - Tap to navigate to detailed category breakdown

4. **Social Media Progress Bar**
   - Visual indicator showing social media usage
   - Threshold markers at 0m, 30m, and 2h
   - Color-coded based on current mood

### 📊 Category Breakdown Screen

- **Grouped App Display**: Apps organized by category (Social, Productivity, Games, Other)
- **Category Totals**: Total time spent per category with percentage breakdown
- **Expandable Sections**: Tap categories to see individual apps within each group
- **Visual Progress Bars**: Category-wise progress indicators
- **Sorted by Usage**: Apps within each category sorted by usage time

### 🐛 Debug Features

**Debug Mode** (accessible via science icon in AppBar):
- **Time Adjustment Controls**: 
  - `-30m` / `-5m` buttons to decrease social media time
  - `+5m` / `+30m` buttons to increase social media time
  - `Reset` button to return to real data
- **Quick Presets**:
  - "Happy (<30m)" - Sets social time to 15 minutes
  - "Neutral (1h)" - Sets social time to 1 hour
  - "Sad (3h)" - Sets social time to 3 hours
- **Real-time Testing**: Character updates instantly as you adjust values
- **Visual Indicator**: Shows real time vs. debug offset

### 🔍 Debug Log Screen

- Comprehensive logging system for troubleshooting
- Log types: Info, Success, Warning, Error, Data, API
- Timestamped entries with formatted time display
- Export functionality for log analysis
- Maximum 500 log entries (auto-trims oldest)

---

## 🏗️ Architecture

### Technology Stack

- **Framework**: Flutter 3.5.4+
- **Language**: Dart (Flutter), Kotlin (Android native)
- **Platform**: Android (primary), iOS/Web/Windows/Linux/macOS (Flutter support)

### Project Structure

```
lib/
├── main.dart                    # Main app entry, Brain Bud character, main screen
├── services/
│   ├── usage_stats_service.dart # Flutter service for Android usage stats API
│   └── debug_log_service.dart  # Debug logging system
└── screens/
    ├── category_breakdown_screen.dart  # Category-based app breakdown
    └── debug_log_screen.dart           # Debug log viewer

android/app/src/main/kotlin/com/example/brain_bud/
└── MainActivity.kt              # Native Android implementation
```

### Platform Channels

The app uses Flutter's platform channels to communicate between Dart and native Android code:

- **Channel**: `com.brainbud.usage_stats/channel`
- **Methods**:
  - `hasUsagePermission` - Check if usage access permission is granted
  - `openUsageSettings` - Open Android usage access settings
  - `getUsageStats` - Get usage stats with time window mode
  - `getUsageStatsForRange` - Get usage stats for custom time range

---

## 🔧 Technical Details

### Usage Statistics Tracking

**Method**: Event-based tracking using Android's `UsageEvents` API
- Tracks `ACTIVITY_RESUMED` → `ACTIVITY_PAUSED` pairs
- Same method used by Google's Digital Wellbeing
- Strictly clips durations to requested time windows
- Handles edge cases (apps opened before window start, still-active apps)

**Time Window Modes**:
- `today` - Midnight to now (calendar day, resets at 12:00 AM)
- `rolling24h` - Rolling 24-hour window (now - 24h → now)
- `week` - Last 7 days

**Supported Android Versions**:
- Android 5.0 (API 21) and above
- Uses `MOVE_TO_FOREGROUND`/`MOVE_TO_BACKGROUND` events for older Android versions

### App Categorization

Apps are automatically categorized using keyword matching:

**Social Media Apps**:
- Keywords: facebook, instagram, whatsapp, telegram, snapchat, tiktok, twitter, linkedin, messenger, reddit, discord, pinterest, youtube

**Productivity Apps**:
- Keywords: calendar, mail, email, office, docs, sheets, drive, notes, notion, slack, teams, zoom, meet

**Gaming Apps**:
- Keywords: game, games, play, candy, clash, pubg, minecraft, roblox, fortnite

### Mood Thresholds

- **Happy**: < 30 minutes of social media usage
- **Neutral**: 30 minutes - 2 hours of social media usage
- **Sad**: > 2 hours of social media usage

These thresholds are configurable in the code (`_happyThreshold` and `_neutralThreshold` constants).

---

## 🎨 UI/UX Features

### Design System

- **Material Design 3**: Modern Material Design implementation
- **Dark Mode Support**: Automatic theme switching based on system settings
- **Color Scheme**: Purple-based theme (`#7C3AED`) with mood-based accents
- **Smooth Animations**: Animated character with floating effect
- **Pull-to-Refresh**: Refresh usage data by pulling down

### Character Design

The Brain Bud character is custom-painted using Flutter's `CustomPainter`:
- **Brain-like Shape**: Wavy blob shape resembling a brain
- **Facial Expressions**: 
  - Happy: Raised eyebrows, big smile, blush cheeks
  - Neutral: Straight eyebrows, straight mouth
  - Sad: Worried eyebrows, frown, eyes looking down
- **Dynamic Colors**: Green (happy), Yellow/Amber (neutral), Red (sad)
- **Visual Effects**: Shadow, gradient fill, brain detail lines

---

## 📋 Permissions

### Required Permissions

**Android Usage Access Permission**:
- Required to track app usage statistics
- User must manually grant via Android Settings
- App guides users through the permission flow

**How to Grant**:
1. App displays permission request screen
2. User taps "Grant Permission"
3. Android Settings opens
4. User finds "Brain Bud" in the list
5. User enables the toggle
6. Returns to app

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.5.4 or higher
- Android Studio / VS Code with Flutter extensions
- Android device/emulator (API 21+)

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd Brain_Bud
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   flutter run
   ```

### Building for Release

**Android APK**:
```bash
flutter build apk --release
```

**Android App Bundle**:
```bash
flutter build appbundle --release
```

---

## 📱 Usage Guide

### First Launch

1. **Grant Permissions**: When you first open the app, you'll be prompted to grant usage access permission
2. **Navigate to Settings**: Tap "Grant Permission" and follow the on-screen instructions
3. **Enable Access**: Find "Brain Bud" in the list and enable the toggle
4. **Return to App**: Come back to the app and your usage data will load

### Daily Use

1. **View Your Character**: The Brain Bud character greets you with its current mood
2. **Check Your Stats**: View total screen time and category breakdowns
3. **See Detailed Breakdown**: Tap the summary card to see apps grouped by category
4. **Monitor Progress**: Watch the social media progress bar to track your usage

### Debug Mode

1. **Enable Debug Mode**: Tap the science icon (🧪) in the AppBar
2. **Adjust Values**: Use the +/- buttons to simulate different social media usage
3. **Test Moods**: Use preset buttons to quickly test all three mood states
4. **Reset**: Tap "Reset" to return to real data

---

## 🐛 Debugging

### Debug Logs

Access debug logs via the bug icon (🐛) in the AppBar:
- View all API calls, errors, warnings, and data logs
- Filter by log type
- Export logs for analysis
- Clear logs when needed

### Common Issues

**Permission Not Granted**:
- Ensure you've enabled "Usage Access" for Brain Bud in Android Settings
- Some devices may require additional permissions

**No Data Showing**:
- Make sure you've used apps today (data resets at midnight)
- Check that usage access permission is granted
- Try refreshing the data

**Character Not Updating**:
- Refresh the app data
- Check debug logs for errors
- Verify social media apps are being detected correctly

---

## 🔮 Future Enhancements

Potential features for future versions:

- [ ] Historical trends and charts
- [ ] Daily/weekly/monthly reports
- [ ] Customizable mood thresholds
- [ ] App usage limits and alerts
- [ ] Focus mode integration
- [ ] Export usage data
- [ ] Multiple character themes
- [ ] Achievement system
- [ ] Social sharing of milestones

---

## 📄 License

[Add your license information here]

---

## 👥 Contributing

[Add contribution guidelines here]

---

## 📞 Support

[Add support/contact information here]

---

## 🙏 Acknowledgments

- Uses Android's UsageStatsManager API (same as Digital Wellbeing)
- Built with Flutter framework
- Material Design 3 components

---

**Version**: 1.0.0+1  
**Last Updated**: 2024  
**Platform**: Android (Primary), Flutter Multi-platform Support
