import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ru.mirea.career"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion намеренно не задаём: у нас нет нативного кода, а требование
    // NDK заставляет CI качать ~1 ГБ и падать, если он не установлен.
    // Понадобится (плагин с C/C++) — вернуть flutter.ndkVersion и добавить
    // установку NDK в workflow.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.mirea.career"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Ключ и пароли приходят из key.properties (локально) или из CI-секретов.
        // Файла нет — release собирается на debug-ключе, чтобы `flutter run --release`
        // работал без настройки подписи (docs/DEVELOPMENT.md).
        create("release") {
            val propsFile = rootProject.file("key.properties")
            if (propsFile.exists()) {
                val props = Properties().apply { propsFile.inputStream().use { load(it) } }
                storeFile = file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Подпись: release-ключ, если он настроен, иначе debug
            // (чтобы `flutter run --release` работал без настройки).
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Минификацию и shrinkResources здесь НЕ задаём: Flutter-плагин
            // настраивает их сам (FlutterPluginUtils.shouldShrinkResources)
            // и сам подключает свои proguard-правила. Повторная настройка
            // в AGP 9 конфликтует с плагином и ломает release-сборку.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
