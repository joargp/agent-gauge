import Foundation

enum RingGeometry {
    /// Adjusts a trimmed circle so its visible colored circumference matches
    /// the requested progress when round caps are used.
    static func trimProgress(
        for progress: Double,
        centerRadius: Double,
        lineWidth: Double
    ) -> Double {
        let boundedProgress = bounded(progress)
        guard usesRoundedCaps(
            for: boundedProgress,
            centerRadius: centerRadius,
            lineWidth: lineWidth
        ) else {
            return boundedProgress
        }
        return boundedProgress - capFraction(
            centerRadius: centerRadius,
            lineWidth: lineWidth
        )
    }

    /// Very small arcs use butt caps because a single round cap would already
    /// represent more circumference than the requested progress.
    static func usesRoundedCaps(
        for progress: Double,
        centerRadius: Double,
        lineWidth: Double
    ) -> Bool {
        let boundedProgress = bounded(progress)
        guard boundedProgress > 0,
              boundedProgress < 1,
              centerRadius.isFinite,
              lineWidth.isFinite,
              centerRadius > 0,
              lineWidth > 0
        else {
            return false
        }
        return boundedProgress > capFraction(
            centerRadius: centerRadius,
            lineWidth: lineWidth
        )
    }

    private static func bounded(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    private static func capFraction(centerRadius: Double, lineWidth: Double) -> Double {
        lineWidth / (2 * .pi * centerRadius)
    }
}
