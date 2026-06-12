plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.near_miss_detector"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        applicationId = "com.example.near_miss_detector"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

tasks.whenTaskAdded {
    if (name == "assembleDebug" || name == "assembleRelease") {
        doLast {
            val apkDir = file("${layout.buildDirectory.get()}/outputs/flutter-apk")
            val targetDir = file("${rootDir.parentFile}/build/app/outputs/flutter-apk")
            targetDir.mkdirs()
            apkDir.listFiles()?.forEach { apk ->
                apk.copyTo(file("${targetDir}/${apk.name}"), overwrite = true)
            }
        }
    }
}