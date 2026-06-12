allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        val androidExtension =
            extensions.findByName("android") ?: return@afterEvaluate

        try {
            val nsMethod = androidExtension.javaClass.getMethod("getNamespace")
            val currentNs = nsMethod.invoke(androidExtension) as? String
            if (currentNs.isNullOrBlank()) {
                val setNs = androidExtension.javaClass
                    .getMethod("setNamespace", String::class.java)
                setNs.invoke(androidExtension, group.toString())
            }
        } catch (_: Exception) {
            // Extension doesn't support namespace — skip silently
        }
    }
}

tasks.register<Delete>("clean") {
    delete(layout.buildDirectory)
}