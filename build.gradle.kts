
allprojects {
    repositories {
        mavenCentral()
    }
}

buildscript {
    dependencies {
        classpath("org.jetbrains.kotlinx:atomicfu-gradle-plugin:0.27.0")
    }
}

plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.goncalossilva.resources)
    id("com.dorongold.task-tree") version "2.1.1"
}

subprojects {
    group = "io.github.davidepianca98"
    version = "1.0.0"
}
