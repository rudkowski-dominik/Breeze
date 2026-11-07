import Foundation

public enum ProfileType: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case max = "Max"
    case systemPlus = "System+"
    case coolChassis = "Cool Chassis"
    case gaming = "Gaming"
    case silent = "Silent"
    case custom = "Custom"

    public var bestForDescription: String {
        switch self {
        case .system:
            return "Lets macOS manage the fans."
        case .max:
            return "Runs each fan at its maximum."
        case .systemPlus:
            return "Gentle, earlier airflow for everyday use."
        case .coolChassis:
            return "Keeps the typing area cool and comfortable."
        case .gaming:
            return "Very early and stronger cooling during sustained loads."
        case .silent:
            return "Keeps the fans slower for quiet environments."
        case .custom:
            return "Create your own cooling curves and temperature targets."
        }
    }
}

public struct CoolingCurve: Codable, Equatable, Sendable {
    public var startTemp: Float      // Temperature where fan begins ramping above floor (°C)
    public var maxTemp: Float        // Temperature where fan hits curve max RPM (°C)
    public var baseRPM: Float        // Baseline idle RPM floor
    public var maxRPM: Float         // Target peak RPM

    public init(startTemp: Float, maxTemp: Float, baseRPM: Float, maxRPM: Float) {
        self.startTemp = startTemp
        self.maxTemp = maxTemp
        self.baseRPM = baseRPM
        self.maxRPM = maxRPM
    }

    public func calculateTargetRPM(currentTemp: Float, hardwareMin: Float, hardwareMax: Float) -> Float {
        let effBase = max(hardwareMin, min(baseRPM, hardwareMax))
        let effMax = max(effBase, min(hardwareMax, maxRPM))

        if currentTemp <= startTemp {
            return effBase
        } else if currentTemp >= maxTemp {
            return effMax
        } else {
            let progress = (currentTemp - startTemp) / max(1.0, (maxTemp - startTemp))
            // Smooth S-curve (cubic hermite interpolation) to avoid sharp acoustic inflection points
            let smoothed = progress * progress * (3.0 - 2.0 * progress)
            return effBase + smoothed * (effMax - effBase)
        }
    }
}

public struct FanProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var type: ProfileType
    public var subtitle: String
    public var isManual: Bool
    public var fixedRPM: Float?
    public var curve: CoolingCurve?

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: ProfileType,
        subtitle: String,
        isManual: Bool = true,
        fixedRPM: Float? = nil,
        curve: CoolingCurve? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.subtitle = subtitle
        self.isManual = isManual
        self.fixedRPM = fixedRPM
        self.curve = curve
    }

    public static func defaultProfiles(hardwareMin: Float = 1000.0, hardwareMax: Float = 4900.0) -> [FanProfile] {
        return [
            FanProfile(
                id: "system",
                name: "System",
                type: .system,
                subtitle: "Lets macOS manage the fans.",
                isManual: false
            ),
            FanProfile(
                id: "max",
                name: "Max",
                type: .max,
                subtitle: "Runs each fan at its maximum.",
                isManual: true,
                fixedRPM: hardwareMax
            ),
            FanProfile(
                id: "system_plus",
                name: "System+",
                type: .systemPlus,
                subtitle: "Gentle, earlier airflow for everyday use.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 58.0,
                    maxTemp: 84.0,
                    baseRPM: 1700.0, // Quiet gentle airflow, inaudible on Mac mini
                    maxRPM: 3400.0
                )
            ),
            FanProfile(
                id: "cool_chassis",
                name: "Cool Chassis",
                type: .coolChassis,
                subtitle: "Keeps the typing area cool and comfortable.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 50.0,
                    maxTemp: 78.0,
                    baseRPM: 2400.0,
                    maxRPM: 4000.0
                )
            ),
            FanProfile(
                id: "gaming",
                name: "Gaming",
                type: .gaming,
                subtitle: "Very early and stronger cooling during sustained loads.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 45.0,
                    maxTemp: 74.0,
                    baseRPM: 3400.0,
                    maxRPM: hardwareMax
                )
            ),
            FanProfile(
                id: "silent",
                name: "Silent",
                type: .silent,
                subtitle: "Keeps the fans slower for quiet environments.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 76.0,
                    maxTemp: 90.0,
                    baseRPM: hardwareMin,
                    maxRPM: 2800.0
                )
            )
        ]
    }
}
