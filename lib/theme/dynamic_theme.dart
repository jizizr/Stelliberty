import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:stelliberty/providers/theme_provider.dart';
import 'package:stelliberty/providers/window_effect_provider.dart';
import 'package:stelliberty/ui/widgets/modern_toast.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 动态主题应用根组件
class DynamicThemeApp extends StatelessWidget {
  final Widget home;

  const DynamicThemeApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, WindowEffectProvider>(
      builder: (context, themeProvider, windowEffectProvider, _) {
        return SystemThemeBuilder(
          builder: (context, accent) {
            return MaterialApp(
              navigatorKey: ModernToast.navigatorKey,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: _buildThemeData(
                themeProvider.lightColorScheme,
                windowEffectProvider.windowEffectBackgroundColor,
              ),
              darkTheme: _buildThemeData(
                themeProvider.darkColorScheme,
                windowEffectProvider.windowEffectBackgroundColor,
              ),
              themeMode: themeProvider.themeMode.toThemeMode(),
              home: Builder(
                builder: (context) {
                  _scheduleBrightnessUpdate(
                    context,
                    themeProvider,
                    windowEffectProvider,
                  );
                  return home;
                },
              ),
            );
          },
        );
      },
    );
  }

  ThemeData _buildThemeData(
    ColorScheme colorScheme,
    Color? scaffoldBackgroundColor,
  ) {
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      useMaterial3: true,
      textTheme: GoogleFonts.notoSansScTextTheme(
        colorScheme.brightness == Brightness.dark
            ? ThemeData.dark().textTheme
            : ThemeData.light().textTheme,
      ),
    );
  }

  void _scheduleBrightnessUpdate(
    BuildContext context,
    ThemeProvider themeProvider,
    WindowEffectProvider windowEffectProvider,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final brightness = Theme.of(context).brightness;
      themeProvider.updateBrightness(brightness);
      windowEffectProvider.updateBrightness(brightness);
    });
  }
}
