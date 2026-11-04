import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';

/// Экран «Лицензии»: список компонентов и их лицензий.
///
/// Юридическое требование: открытые пакеты требуют атрибуции. Страница
/// однотонная, текст на английском — лицензионные формулировки не
/// переводятся (юридический текст меняет смысл при переводе).
///
/// Список ведётся вручную и синхронизируется с pubspec.lock: компонент
/// добавляется сюда при добавлении в зависимости. Версии не пишем:
/// у некоторых пакетов лицензия одна на все версии, и перечисление
/// версий здесь бы дублило lock-файл.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  /// Компоненты приложения и его зависимостей.
  static const _entries = <(String, String, String)>[
    // (пакет, автор/правообладатель, лицензия)
    ('flutter', 'Google LLC', 'BSD 3-Clause "New" or "Revised" License'),
    ('flutter_riverpod', 'Remi Rousselet, Thomas Burkhart', 'MIT License'),
    ('shared_preferences', 'Google LLC', 'BSD 3-Clause License'),
    ('url_launcher', 'Google LLC', 'BSD 3-Clause License'),
    ('path_provider', 'Google LLC', 'BSD 3-Clause License'),
    ('sentry_flutter', 'Sentry (Functional Software, Inc.)', 'MIT License'),
    ('cupertino_icons', 'Google LLC', 'MIT License'),
    ('Dart SDK', 'Google LLC', 'BSD 3-Clause License'),
    // Криптография и сертификаты, используемые стеком:
    ('BoringSSL / OpenSSL', 'The OpenSSL Project Authors', 'Apache License 2.0 / OpenSSL License'),
    ('Mozilla CA Certificate Store', 'Mozilla Foundation', 'Mozilla Public License 2.0'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лицензии'),
        titleTextStyle: AppText.headline,
        leading: const GlassBackButton(),
      ),
      body: ListView.separated(
        physics: AppScroll.plain,
        padding: EdgeInsets.fromLTRB(
          AppInsets.horizontal(MediaQuery.sizeOf(context).width),
          16,
          AppInsets.horizontal(MediaQuery.sizeOf(context).width),
          AppInsets.screenBottom(context),
        ),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final (name, holder, license) = _entries[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppText.headline),
              const SizedBox(height: 2),
              Text(
                'Copyright (c) $holder',
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
              const SizedBox(height: 2),
              Text(license, style: AppText.body),
            ],
          );
        },
      ),
    );
  }
}
