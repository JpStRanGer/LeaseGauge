import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep upload credentials outside version control. Debug builds do not need them.
val uploadPropertiesFile = rootProject.file("key.properties")
val uploadProperties = Properties()
val uploadPropertiesLoaded = runCatching {
    if (uploadPropertiesFile.isFile) {
        uploadPropertiesFile.inputStream().use { uploadProperties.load(it) }
    }
}.isSuccess
val uploadEnvironmentNames = mapOf(
    "storeFile" to "LEASEGAUGE_KEYSTORE_PATH",
    "storePassword" to "LEASEGAUGE_STORE_PASSWORD",
    "keyAlias" to "LEASEGAUGE_KEY_ALIAS",
    "keyPassword" to "LEASEGAUGE_KEY_PASSWORD",
)
val uploadSigningValues = uploadEnvironmentNames.mapValues { (propertyName, environmentName) ->
    System.getenv(environmentName)
        ?: if (uploadPropertiesLoaded) uploadProperties.getProperty(propertyName) else null
}
val uploadSigningComplete = uploadSigningValues.values.all { !it.isNullOrBlank() }

val validateUploadSigning = tasks.register("validateUploadSigning") {
    group = "verification"
    description = "Checks local upload-key configuration before building a release."
    doLast {
        if (!uploadSigningComplete) {
            throw GradleException(
                "Release signing is not configured. Run tools/build-android-release.ps1 " +
                    "from the project root, or copy android/key.properties.example " +
                    "to android/key.properties and fill in all four values locally. " +
                    "Never commit that file or your keystore. Debug builds need no upload key."
            )
        }
        if (!rootProject.file(uploadSigningValues.getValue("storeFile")!!).isFile) {
            throw GradleException(
                "Release signing keystore was not found. Check LEASEGAUGE_KEYSTORE_PATH " +
                    "or storeFile in android/key.properties locally. " +
                    "Use forward slashes in Windows properties-file paths."
            )
        }
    }
}

// Gate both compilation and signing; an incomplete setup must never produce an
// unsigned or debug-signed release artifact.
tasks.matching { it.name == "preReleaseBuild" || it.name == "validateSigningRelease" }
    .configureEach { dependsOn(validateUploadSigning) }

android {
    namespace = "com.strangestudio.leasegauge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.strangestudio.leasegauge"
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
    }

    signingConfigs {
        create("upload") {
            if (uploadSigningComplete) {
                storeFile = rootProject.file(uploadSigningValues.getValue("storeFile")!!)
                storePassword = uploadSigningValues.getValue("storePassword")
                keyAlias = uploadSigningValues.getValue("keyAlias")
                keyPassword = uploadSigningValues.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("upload")
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
