import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'providers/app_state.dart';
import 'screens/main_screen.dart';

import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'TagFix',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.createTheme(lightDynamic, Brightness.light),
          darkTheme: AppTheme.createTheme(darkDynamic, Brightness.dark),
          themeMode: ThemeMode.system,
          home: const MainScreen(),
        );
      },
    );
  }
}
