# Правила R8/ProGuard для release-сборки.
#
# Flutter и плагины поставляются с собственными правилами, поэтому здесь —
# только то, что нужно нашему приложению.

# url_launcher: вызывает системный браузер через Intent
-keep class io.flutter.plugins.urllauncher.** { *; }

# Supabase/OkHttp: сетевой слой
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# Kotlin-метаданные не нужны в рантайме, но их отсутствие ломает часть плагинов
-keepattributes *Annotation*, InnerClasses, Signature