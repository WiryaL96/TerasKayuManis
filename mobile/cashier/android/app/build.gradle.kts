import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyFile.inputStream().use { releaseKeys.load(it) }
val releaseKeyNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val configuredSigning = releaseKeyNames.all { !releaseKeys.getProperty(it).isNullOrBlank() }
if (keyFile.exists() && !configuredSigning) throw GradleException("Release signing configuration is incomplete")

android {
    namespace = "id.alrizky.teraskayumanis.cashier"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Development identifier: agree ownership before store publishing.
        applicationId = "id.alrizky.teraskayumanis.cashier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (configuredSigning) create("production") {
            storeFile = file(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
        }
    }
    buildTypes {
        getByName("release") {
            if (configuredSigning) signingConfig = signingConfigs.getByName("production")
            // Without a private key this produces an unsigned review artifact.
            // Distribution tooling below rejects unsigned/debug-signed artifacts.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

flutter {
    source = "../.."
}
