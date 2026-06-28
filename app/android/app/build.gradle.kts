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
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "cz.syky.redtick.redtick"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
            // R8/shrinking intentionally left off this round (no keep rules
            // authored yet; Flutter + plugins can break under R8 without them).
            // Enable in a later hardening pass with isMinifyEnabled +
            // proguardFiles(getDefaultProguardFile(...), "proguard-rules.pro").
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
