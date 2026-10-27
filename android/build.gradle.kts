allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    // geocoding_android 3.3.1 (via geocoding ^3.0.0) is compiled against
    // android-33, but its AndroidX dependencies (fragment/window/activity 1.7+)
    // require compileSdk >= 34, so the AAR-metadata check fails on a fresh
    // build. Bump every Android library subproject to Flutter's default
    // compileSdk so the plugin can resolve its dependencies.
    val bumpPluginCompileSdk = Action<Project> {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
    if (state.executed) {
        // Flutter's plugin loader evaluates subprojects early; afterEvaluate()
        // is not allowed then, so configure directly.
        bumpPluginCompileSdk.execute(this)
    } else {
        afterEvaluate(bumpPluginCompileSdk)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
