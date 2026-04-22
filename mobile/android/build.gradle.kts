import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.JavaVersion
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

val globalJavaVersion = JavaVersion.VERSION_17
val globalJvmTarget = globalJavaVersion.toString()

subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension>("android") {
            compileOptions {
                sourceCompatibility = globalJavaVersion
                targetCompatibility = globalJavaVersion
            }
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            compileOptions {
                sourceCompatibility = globalJavaVersion
                targetCompatibility = globalJavaVersion
            }
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        if (!options.compilerArgs.contains("-Xlint:-options")) {
            options.compilerArgs.add("-Xlint:-options")
        }
    }

    tasks.withType<KotlinCompile>().configureEach {
        kotlinOptions.jvmTarget = globalJvmTarget
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
