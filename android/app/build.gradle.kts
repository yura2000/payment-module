plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.test.payment"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // AppInfoHandler reads BuildConfig.FLAVOR / VERSION_NAME / VERSION_CODE (docs/architecture.md §9).
        buildConfig = true
        // The flavors below set app_name with resValue.
        resValues = true
    }

    defaultConfig {
        applicationId = "dev.test.payment"
        // docs/architecture.md §1: minSdk 26 — the notification channel and Process.waitFor(timeout)
        // are used without version gates on that basis.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Brand = Flavor, 1:1 (docs/architecture.md §6, ADR-0002). Adding a brand adds one block (§13).
    flavorDimensions += "brand"
    productFlavors {
        create("retail") {
            dimension = "brand"
            applicationIdSuffix = ".retail"
            resValue("string", "app_name", "Retail Shop")
        }
        create("utility") {
            dimension = "brand"
            applicationIdSuffix = ".utility"
            resValue("string", "app_name", "Utility Pay")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    // Parses contract/fixtures/*.json in JVM tests. Not org.json: android.jar's stubbed copy shadows it.
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
}

// JVM tests read the shared channel fixtures and the manifest from the repo, not from test resources,
// so Dart and Kotlin pin the same files (docs/architecture.md §9, §14).
val contractFixtures: File = rootProject.file("../contract/fixtures").canonicalFile
val mainManifest: File = file("src/main/AndroidManifest.xml")
tasks.withType<Test>().configureEach {
    systemProperty("contract.fixtures", contractFixtures.path)
    systemProperty("main.manifest", mainManifest.path)
    inputs.dir(contractFixtures)
    inputs.file(mainManifest)
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
