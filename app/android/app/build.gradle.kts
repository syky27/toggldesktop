import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is loaded from key.properties (kept out of git). When it's
// absent — local `flutter run --release`, forks, secret-less CI — we fall back to
// the debug key so the build still works. This mirrors the iOS lane's
// "gated on signing secrets" approach. See docs/ANDROID_RELEASE.md.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
// Sign with the upload key only when key.properties is present AND complete; an
// empty or partial file falls back to the debug key instead of failing the build
// with "null cannot be cast to non-null type kotlin.String".
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { (keystoreProperties.getProperty(it) ?: "").isNotBlank() }

android {
    namespace = "cz.syky.redtick.redtick"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (used by reminders + the running-timer
        // ongoing notification) requires core library desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "cz.syky.redtick.redtick"
        // flutter_secure_storage (encryptedSharedPreferences) needs API 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        // Resolves to 36 with Flutter 3.44.3 — already ≥ Google Play's 2026
        // minimum (targetSdk 35). Pin explicitly only if reproducibility across
        // SDK upgrades is required.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String).let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when key.properties is present; otherwise fall back
            // to the debug key (forks / secret-less CI / local --release).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep R8/shrinking OFF. AGP 9 minifies the release build by default,
            // and R8 full mode strips WorkManager's reflectively-instantiated Room
            // class (androidx.work.impl.WorkDatabase_Impl.<init>), which crashes at
            // startup via the androidx.startup InitializationProvider. Disable until
            // a hardening pass adds the necessary keep rules (proguard-rules.pro).
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    // Required by flutter_local_notifications (core library desugaring).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
