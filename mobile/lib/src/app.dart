import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/dashboard_controller.dart';
import 'services/instance_store.dart';
import 'theme/app_theme.dart';
import 'ui/home_screen.dart';

class DokployRadarMobileApp extends StatelessWidget {
  const DokployRadarMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<InstanceStore>(create: (_) => InstanceStore()),
        ChangeNotifierProvider<DashboardController>(
          create: (context) {
            final controller = DashboardController(
              store: context.read<InstanceStore>(),
            );
            unawaited(controller.initialize());
            return controller;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Dokploy Radar',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
