import CoreGraphics

/// Chooses a contiguous canvas, preserving image aspect fitting rather than masking pixels.
public enum WorkspaceRegion {
    public static func largestRectangle(in bounds: CGRect, avoiding obstacles: [CGRect]) -> CGRect {
        let candidates = obstacles.reduce([bounds]) { candidates, obstacle in
            candidates.flatMap { available -> [CGRect] in
                let intersection = available.intersection(obstacle)
                guard !intersection.isNull, !intersection.isEmpty else { return [available] }
                return [
                    CGRect(x: available.minX, y: available.minY, width: intersection.minX - available.minX, height: available.height),
                    CGRect(x: intersection.maxX, y: available.minY, width: available.maxX - intersection.maxX, height: available.height),
                    CGRect(x: available.minX, y: available.minY, width: available.width, height: intersection.minY - available.minY),
                    CGRect(x: available.minX, y: intersection.maxY, width: available.width, height: available.maxY - intersection.maxY),
                ].filter { !$0.isEmpty }
            }
        }
        return candidates.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
    }
}
