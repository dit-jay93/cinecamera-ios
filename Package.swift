// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CineCamera",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CinePipeline", targets: ["CinePipeline"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CinePipeline",
            path: "CineCamera/Sources",
            resources: [
                .process("../Resources"),
                .copy("Metal/CineLogCurve.metal"),
                .copy("Metal/CDL.metal"),
                .copy("Metal/LUT3D.metal"),
                .copy("Metal/FilmGrain.metal"),
                .copy("Metal/CinemaFilter.metal")
            ]
        ),
        .testTarget(
            name: "CineCameraTests",
            dependencies: ["CinePipeline"],
            path: "CineCameraTests"
        )
    ]
)
