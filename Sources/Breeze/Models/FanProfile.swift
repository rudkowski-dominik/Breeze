import Foundation

public enum ProfileType: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case max = "Max"
    case systemPlus = "System+"
    case coolChassis = "Cool Chassis"
    case gaming = "Gaming"
    case silent = "Silent"
    case custom = "Custom"

    public var localizedName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .system: return loc.text(.profileSystem)
        case .max: return loc.text(.profileMax)
        case .systemPlus: return loc.text(.profileSystemPlus)
        case .coolChassis: return loc.text(.profileCoolChassis)
        case .gaming: return loc.text(.profileGaming)
        case .silent: return loc.text(.profileSilent)
        case .custom: return loc.text(.profileCustom)
        }
    }

    public var bestForDescription: String {
        let loc = LocalizationManager.shared
        switch self {
        case .system: return loc.text(.profileSystemDesc)
        case .max: return loc.text(.profileMaxDesc)
        case .systemPlus: return loc.text(.profileSystemPlusDesc)
        case .coolChassis: return loc.text(.profileCoolChassisDesc)
        case .gaming: return loc.text(.profileGamingDesc)
        case .silent: return loc.text(.profileSilentDesc)
        case .custom: return loc.text(.profileCustomDesc)
        }
    }
}

public struct CoolingCurve: Codable, Equatable, Sendable {
    public var startTemp: Float
    public var maxTemp: Float
    public var baseRPM: Float
    public var maxRPM: Float

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

    public var localizedName: String {
        return type == .custom ? name : type.localizedName
    }

    public var localizedSubtitle: String {
        return type == .custom ? subtitle : type.bestForDescription
    }

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
                    baseRPM: 1700.0,
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

extension TimerDuration {
    public var localizedTitle: String {
        let loc = LocalizationManager.shared
        switch self {
        case .indefinitely: return loc.text(.indefinitely)
        case .for15Mins: return loc.text(.for15Mins)
        case .for30Mins: return loc.text(.for30Mins)
        case .for1Hour: return loc.text(.for1Hour)
        case .for2Hours: return loc.text(.for2Hours)
        case .untilQuit: return loc.text(.untilQuit)
        }
    }
}
