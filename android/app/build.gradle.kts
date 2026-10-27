import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing configuration.
//
// Release credentials come from android/key.properties.
// Debug builds continue to work without the release keystore.
// ---------------------------------------------------------------------------

fun requiredKey(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val releaseStorePath = requiredKey("storeFile")
val releaseStorePassword = requiredKey("storePassword")
val releaseKeyAlias = requiredKey("keyAlias")
val releaseKeyPassword = requiredKey("keyPassword")

val hasReleaseSigning = !listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).any { it == null }

val buildingReleaseArtifact = gradle.startParameter.taskNames.any { task ->
    task.contains("release", ignoreCase = true)
}

fun releaseSigningHelp(): String =
    """
    |
    |ParkShare: refusing to build a release artifact that is not properly signed.
    |
    |Create android/key.properties with:
    |
    |    storeFile=<path to your upload keystore (.jks)>
    |    storePassword=<keystore password>
    |    keyAlias=<key alias>
    |    keyPassword=<key password>
    |
    |Example:
    |
    |    storeFile=C:/Users/Admin/parkshare-keys/parkshare-upload.jks
    |    keyAlias=upload
    |
    |Debug builds are unaffected.
    |
    """.trimMargin()

android {
    namespace = "com.parkshare.nexzware"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.parkshare.nexzware"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (buildingReleaseArtifact && !hasReleaseSigning) {
                throw GradleException(releaseSigningHelp())
            }

            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }

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