import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'providers/app_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';
import 'screens/server_welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en'),
      child: const NanoLinkApp(),
    ),
  );
}

class NanoLinkApp extends StatelessWidget {
  const NanoLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => AppProvider()..init()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'NanoLink',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.materialThemeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Consumer<AppProvider>(
              builder: (context, appProvider, _) {
                // Show loading while initializing
                if (appProvider.isLoading) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                // Show welcome screen if no servers configured
                if (appProvider.servers.isEmpty) {
                  return const ServerWelcomeScreen();
                }
                // Otherwise show main app shell
                return const AppShell();
              },
            ),
          );
        },
      ),
    );
  }
}
