plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {

    namespace = "com.example.dsc_demo"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    compileOptions {

        sourceCompatibility = JavaVersion.VERSION_17

        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {

        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {

        applicationId = "com.example.dsc_demo"

        minSdk = 24

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode

        versionName = flutter.versionName

        ndk {

            abiFilters += listOf(
                "armeabi-v7a",
                "arm64-v8a"
            )
        }
    }

    buildTypes {

        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {

    source = "../.."
}

repositories {

    flatDir {

        dirs("libs")
    }
}

dependencies {

    implementation(
        files("libs/InnaITPKCS11.jar")
    )
}