import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case polish = "pl"
    case spanish = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English 🇬🇧"
        case .polish: return "Polski 🇵🇱"
        case .spanish: return "Español 🇪🇸"
        }
    }
}

public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()

    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "breeze_app_language")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "breeze_app_language"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Auto detect from system locale
            let locale = Locale.current.language.languageCode?.identifier ?? "en"
            if locale == "pl" {
                self.currentLanguage = .polish
            } else if locale == "es" {
                self.currentLanguage = .spanish
            } else {
                self.currentLanguage = .english
            }
        }
    }

    public func text(_ key: LocalizedKey) -> String {
        return key.translation(for: currentLanguage)
    }
}

public enum LocalizedKey {
    // Menu items
    case customFanSpeed
    case activateForUntil
    case indefinitely
    case for15Mins
    case for30Mins
    case for1Hour
    case for2Hours
    case untilQuit
    case editProfiles
    case settings
    case quit

    // Status messages
    case monitoringExternal
    case systemManaged
    case activeProfileText(String, String)
    case enterCustomRPM
    case enterRPMDetails

    // Profiles & Best for
    case profileSystem
    case profileSystemDesc
    case profileMax
    case profileMaxDesc
    case profileSystemPlus
    case profileSystemPlusDesc
    case profileCoolChassis
    case profileCoolChassisDesc
    case profileGaming
    case profileGamingDesc
    case profileSilent
    case profileSilentDesc
    case profileCustom
    case profileCustomDesc

    // Settings tabs & options
    case tabProfiles
    case tabSensors
    case tabHelper
    case tabGeneral
    case language
    case iconTheme
    case iconThemeAuto
    case iconThemeDark
    case iconThemeLight
    case menuBarStyle
    case menuBarIconOnly
    case menuBarIconTemp
    case menuBarIconRPM
    case energyOptimization
    case energyDesc
    case failsafeThreshold
    case failsafeDesc
    case helperActive
    case helperInactive
    case helperInstallBtn
    case helperReinstallBtn

    public func translation(for lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return englishText
        case .polish:
            return polishText
        case .spanish:
            return spanishText
        }
    }

    private var englishText: String {
        switch self {
        case .customFanSpeed: return "Custom Fan Speed"
        case .activateForUntil: return "Activate for/until"
        case .indefinitely: return "Indefinitely"
        case .for15Mins: return "For 15 minutes"
        case .for30Mins: return "For 30 minutes"
        case .for1Hour: return "For 1 hour"
        case .for2Hours: return "For 2 hours"
        case .untilQuit: return "Until app quits"
        case .editProfiles: return "Edit Profiles..."
        case .settings: return "Settings..."
        case .quit: return "Quit"

        case .monitoringExternal: return "Monitoring · external manual control observed"
        case .systemManaged: return "System Managed · macOS Thermal Governance"
        case .activeProfileText(let name, let temp): return "\(name) Active · SoC \(temp)°C"
        case .enterCustomRPM: return "Enter Custom RPM..."
        case .enterRPMDetails: return "Enter target RPM (Hardware range: 1000 - 4900 RPM):"

        case .profileSystem: return "System"
        case .profileSystemDesc: return "Lets macOS manage the fans."
        case .profileMax: return "Max"
        case .profileMaxDesc: return "Runs each fan at its maximum."
        case .profileSystemPlus: return "System+"
        case .profileSystemPlusDesc: return "Gentle, earlier airflow for everyday use."
        case .profileCoolChassis: return "Cool Chassis"
        case .profileCoolChassisDesc: return "Keeps the typing area cool and comfortable."
        case .profileGaming: return "Gaming"
        case .profileGamingDesc: return "Very early and stronger cooling during sustained loads."
        case .profileSilent: return "Silent"
        case .profileSilentDesc: return "Keeps the fans slower for quiet environments."
        case .profileCustom: return "Custom"
        case .profileCustomDesc: return "Create your own cooling curves and temperature targets."

        case .tabProfiles: return "Profiles"
        case .tabSensors: return "Hardware Sensors"
        case .tabHelper: return "Privileged Helper"
        case .tabGeneral: return "General"
        case .language: return "Language"
        case .iconTheme: return "App Icon Theme"
        case .iconThemeAuto: return "Automatic (System Appearance)"
        case .iconThemeDark: return "Dark Glass (Always Dark)"
        case .iconThemeLight: return "Frosted White (Always Light)"
        case .menuBarStyle: return "Menu Bar Display"
        case .menuBarIconOnly: return "Icon Only"
        case .menuBarIconTemp: return "Icon + Temperature"
        case .menuBarIconRPM: return "Icon + Fan RPM"
        case .energyOptimization: return "Energy Optimization & Sleep Safety"
        case .energyDesc: return "Automatically pauses telemetry and returns fans to macOS firmware during system sleep."
        case .failsafeThreshold: return "Emergency Failsafe Threshold:"
        case .failsafeDesc: return "If SoC temperature exceeds 86°C, Breeze immediately forces 100% cooling to protect hardware."
        case .helperActive: return "Privileged Helper Daemon is Active"
        case .helperInactive: return "Helper Daemon Not Installed / Inactive"
        case .helperInstallBtn: return "Install Privileged Helper..."
        case .helperReinstallBtn: return "Reinstall Helper Daemon"
        }
    }

    private var polishText: String {
        switch self {
        case .customFanSpeed: return "Własna prędkość wentylatora"
        case .activateForUntil: return "Włącz na czas"
        case .indefinitely: return "Na stałe"
        case .for15Mins: return "Na 15 minut"
        case .for30Mins: return "Na 30 minut"
        case .for1Hour: return "Na 1 godzinę"
        case .for2Hours: return "Na 2 godziny"
        case .untilQuit: return "Do zamknięcia programu"
        case .editProfiles: return "Edytuj profile..."
        case .settings: return "Ustawienia..."
        case .quit: return "Zakończ"

        case .monitoringExternal: return "Monitorowanie · wykryto zewnętrzne sterowanie"
        case .systemManaged: return "Zarządzane przez system macOS"
        case .activeProfileText(let name, let temp): return "\(name) aktywny · SoC \(temp)°C"
        case .enterCustomRPM: return "Wpisz własną prędkość RPM..."
        case .enterRPMDetails: return "Podaj docelowe obroty RPM (zakres sprzętowy: 1000 - 4900 RPM):"

        case .profileSystem: return "System"
        case .profileSystemDesc: return "macOS automatycznie zarządza chłodzeniem."
        case .profileMax: return "Maksimum"
        case .profileMaxDesc: return "Wymusza maksymalne obroty każdego wentylatora."
        case .profileSystemPlus: return "System+"
        case .profileSystemPlusDesc: return "Spokojny, wczesny przepływ powietrza do codziennej pracy."
        case .profileCoolChassis: return "Chłodna obudowa"
        case .profileCoolChassisDesc: return "Utrzymuje chłodną i komfortową obudowę komputera."
        case .profileGaming: return "Gaming"
        case .profileGamingDesc: return "Mocne i wczesne chłodzenie pod długim obciążeniem."
        case .profileSilent: return "Cichy"
        case .profileSilentDesc: return "Maksymalna cisza w spokojnym otoczeniu."
        case .profileCustom: return "Własny"
        case .profileCustomDesc: return "Twórz własne krzywe chłodzenia i docelowe temperatury."

        case .tabProfiles: return "Profile"
        case .tabSensors: return "Sensory sprzętowe"
        case .tabHelper: return "Daemon pomocniczy"
        case .tabGeneral: return "Ogólne"
        case .language: return "Język aplikacji"
        case .iconTheme: return "Motyw ikony programu"
        case .iconThemeAuto: return "Automatyczny (motyw systemu)"
        case .iconThemeDark: return "Ciemne szkło (zawsze ciemna)"
        case .iconThemeLight: return "Mrożona biel (zawsze jasna)"
        case .menuBarStyle: return "Wygląd w pasku zadań"
        case .menuBarIconOnly: return "Tylko ikona"
        case .menuBarIconTemp: return "Ikona + Temperatura"
        case .menuBarIconRPM: return "Ikona + Obroty RPM"
        case .energyOptimization: return "Optymalizacja energii i obsługa uśpienia"
        case .energyDesc: return "Automatycznie wstrzymuje odpytywanie i oddaje kontrolę macOS podczas uśpienia komputera."
        case .failsafeThreshold: return "Próg bezpieczeństwa awaryjnego:"
        case .failsafeDesc: return "W przypadku wzrostu temperatury SoC powyżej 86°C, Breeze natychmiast wymusza 100% chłodzenia."
        case .helperActive: return "Daemon pomocniczy jest aktywny"
        case .helperInactive: return "Daemon nie jest zainstalowany lub jest nieaktywny"
        case .helperInstallBtn: return "Zainstaluj daemona pomocniczego..."
        case .helperReinstallBtn: return "Zainstaluj ponownie daemona"
        }
    }

    private var spanishText: String {
        switch self {
        case .customFanSpeed: return "Velocidad personalizada"
        case .activateForUntil: return "Activar durante"
        case .indefinitely: return "Indefinidamente"
        case .for15Mins: return "Durante 15 minutos"
        case .for30Mins: return "Durante 30 minutos"
        case .for1Hour: return "Durante 1 hora"
        case .for2Hours: return "Durante 2 horas"
        case .untilQuit: return "Hasta cerrar la app"
        case .editProfiles: return "Editar perfiles..."
        case .settings: return "Ajustes..."
        case .quit: return "Salir"

        case .monitoringExternal: return "Monitorizando · control manual externo detectado"
        case .systemManaged: return "Controlado por macOS automáticamente"
        case .activeProfileText(let name, let temp): return "\(name) activo · SoC \(temp)°C"
        case .enterCustomRPM: return "Introducir RPM manual..."
        case .enterRPMDetails: return "Introduce RPM objetivo (rango de hardware: 1000 - 4900 RPM):"

        case .profileSystem: return "Sistema"
        case .profileSystemDesc: return "macOS gestiona los ventiladores automáticamente."
        case .profileMax: return "Máximo"
        case .profileMaxDesc: return "Ejecuta cada ventilador a su máxima velocidad."
        case .profileSystemPlus: return "Sistema+"
        case .profileSystemPlusDesc: return "Flujo de aire suave y anticipado para el uso diario."
        case .profileCoolChassis: return "Chasis frío"
        case .profileCoolChassisDesc: return "Mantiene la carcasa fría y cómoda al tacto."
        case .profileGaming: return "Juegos"
        case .profileGamingDesc: return "Refrigeración temprana y potente bajo cargas intensas."
        case .profileSilent: return "Silencioso"
        case .profileSilentDesc: return "Mantiene los ventiladores lentos para máxima discreción."
        case .profileCustom: return "Personalizado"
        case .profileCustomDesc: return "Crea curvas de refrigeración y temperaturas objetivo."

        case .tabProfiles: return "Perfiles"
        case .tabSensors: return "Sensores de hardware"
        case .tabHelper: return "Demonio auxiliar"
        case .tabGeneral: return "General"
        case .language: return "Idioma"
        case .iconTheme: return "Tema del icono"
        case .iconThemeAuto: return "Automático (según el sistema)"
        case .iconThemeDark: return "Cristal oscuro (siempre oscuro)"
        case .iconThemeLight: return "Blanco esmerilado (siempre claro)"
        case .menuBarStyle: return "Visualización en la barra"
        case .menuBarIconOnly: return "Solo icono"
        case .menuBarIconTemp: return "Icono + Temperatura"
        case .menuBarIconRPM: return "Icono + RPM"
        case .energyOptimization: return "Optimización de energía y reposo"
        case .energyDesc: return "Pausa la telemetría y devuelve el control a macOS durante el reposo del sistema."
        case .failsafeThreshold: return "Límite de seguridad térmica:"
        case .failsafeDesc: return "Si el procesador supera 86°C, Breeze activa inmediatamente el 100% de ventilación."
        case .helperActive: return "El demonio auxiliar está activo"
        case .helperInactive: return "Demonio auxiliar no instalado / inactivo"
        case .helperInstallBtn: return "Instalar demonio auxiliar..."
        case .helperReinstallBtn: return "Reinstalar demonio auxiliar"
        }
    }
}
