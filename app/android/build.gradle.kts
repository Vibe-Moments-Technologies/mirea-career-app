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

// Здесь раньше стоял шаблонный `subprojects { project.evaluationDependsOn(":app") }`.
// С AGP 9 он падает с NoClassDefFoundError: Build_gradle — плагин форсирует
// оценку :app до компиляции этого скрипта, и Kotlin DSL не находит свой класс.
// Зависимость не нужна: плагины Flutter подключаются через settings.gradle.kts
// (includeBuild), а build-каталог уже перенаправлен выше.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
