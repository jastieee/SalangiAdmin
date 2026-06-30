import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Upgrader.clearSavedSettings(); // uncomment during testing only
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const _appcastURL =
      'https://raw.githubusercontent.com/jastieee/SalangiAdmin/main/appcast.xml';

  static final _upgrader = Upgrader(
    storeController: UpgraderStoreController(
      onAndroid: () => UpgraderAppcastStore(
        appcastURL: _appcastURL,
        osVersion: '0.0.0',        // ← String not Version
      ),
      onWindows: () => UpgraderAppcastStore(
        appcastURL: _appcastURL,
        osVersion: '0.0.0',        // ← String not Version
      ),
    ),
    debugLogging: true,            // remove after testing
    durationUntilAlertAgain: const Duration(days: 1),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Salangi Ko Pu",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: UpgradeAlert(
        upgrader: _upgrader,
        child: const LoginScreen(),
      ),
    );
  }
}