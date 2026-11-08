# Breeze 🌬️ — Apple Silicon Fan Control

<p align="center">
  <img src="assets/AppIcon-Light.png" width="130" alt="Breeze Light Mode Icon" />
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/AppIcon-Dark.png" width="130" alt="Breeze Dark Mode Icon" />
</p>
<p align="center">
  <i>Light Mode &nbsp; • &nbsp; Dark Mode</i>
</p>

<p align="center">
  <b>A minimalist, native Apple-style macOS menu bar application for fan control on Apple Silicon (M1/M2/M3/M4/M5 Pro).</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS"/>
  <img src="https://img.shields.io/badge/Apple_Silicon-M1_.._M5-00D2FF?logo=apple" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift" alt="Swift"/>
  <img src="https://img.shields.io/badge/License-MIT-brightgreen" alt="License"/>
</p>

---

## 🇵🇱 Opis / Overview

**Breeze** to lekka, minimalistyczna aplikacja stworzona z myślą o użytkownikach komputerów Apple Silicon (przetestowana m.in. na **Mac mini M5 Pro**, MacBook Pro, Mac Studio). Program dyskretnie działa w górnym pasku menu (Menu Bar) i oferuje precyzyjną kontrolę nad chłodzeniem komputera przy zachowaniu pełnego bezpieczeństwa sprzętowego.

### 🌟 Kluczowe funkcje / Key Features
- **Trójjęzyczny interfejs (EN 🇬🇧 / PL 🇵🇱 / ES 🇪🇸)**: Pełna lokalizacja wszystkich menu, profili, opisów i ustawień.
- **Optymalizacja energetyczna (Energy Optimization)**: Reakcja na zdarzenia systemowe `NSWorkspace` — automatyczne przejście w tryb fabryczny Apple przed uśpieniem (`willSleepNotification`), wstrzymanie timerów, obniżenie częstotliwości odpytywania SMC przy wygaszonym ekranie (`screensDidSleepNotification`) oraz adaptacyjny polling (4.0s w trybie systemowym, 1.5s pod obciążeniem).
- **Apple Control Center UX**: Płynny suwak w stylu macOS Control Center bezpośrednio w menu paska zadań, pozwalający na natychmiastowe precyzyjne ustawienie obrotów bez otwierania osobnych okien.
- **Wielowentylatorowa architektura (Multi-Fan Support)**: Automatyczna detekcja liczby wentylatorów (`FNum`) i zsynchronizowane sterowanie dla Mac mini (1 wentylator), MacBook Pro 14"/16" (2 wentylatory: lewy i prawy) oraz Mac Studio / Mac Pro.
- **Selektor motywu ikony (Icon Theme Selector)**: Wybór między trybem automatycznym (dopasowanym do Dark/Light Mode systemu), Dark Glass oraz Frosted White.
- **Konfigurowalny widok Menu Bar**: Możliwość wyświetlania samej ikony, ikony z temperaturą (°C) lub ikony z obrotami (RPM).
- **Bezpieczny Privileged Helper Daemon (`breeze-helper`)**: Działa w tle z 30-sekundowym heartbeat watchdogiem — w przypadku zamknięcia lub awarii aplikacji głównej, sprzęt natychmiast wraca pod pełną fabryczną kontrolę Apple SMC.

---

## 🎯 Profile chłodzenia / Cooling Profiles

| Profil | Zastosowanie (*Best for*) | Opis działania |
| :--- | :--- | :--- |
| **System** | *Lets macOS manage the fans.* | Domyślna regulacja Apple Silicon SMC i CLPC. macOS sam kontroluje obroty. |
| **System+** | *Gentle, earlier airflow for everyday use.* | Spokojny, wczesny przepływ powietrza (~1700 RPM). Zapobiega nagrzewaniu obudowy podczas codziennej pracy biurowej. |
| **Cool Chassis** | *Keeps the typing area cool and comfortable.* | Utrzymuje chłodną obudowę (~2400 RPM bazowo), proaktywnie chłodząc radiator. |
| **Gaming** | *Very early and stronger cooling during sustained loads.* | Wczesne i mocniejsze chłodzenie (~3400 RPM bazowo) eliminujące thermal throttling w grach i kompilacji. |
| **Silent** | *Keeps the fans slower for quiet environments.* | Priorytet absolutnej ciszy (1000–1200 RPM) z automatyczną ochroną awaryjną powyżej 86°C. |
| **Max** | *Runs each fan at its maximum.* | 100% maksymalnej wydajności wentylatora (~4900 RPM na Mac mini M5 Pro). |
| **Custom Profiles** | *Create your own cooling curves.* | Edytor własnych krzywych termicznych: temperatura startu, temperatura maks., obroty bazowe i docelowe. |

---

## 🛡️ Bezpieczeństwo Sprzętowe / Hardware Safety Architecture

Aplikacja została zaprojektowana z zachowaniem rygorystycznych standardów bezpieczeństwa:

1. **Acoustic Stabilization (Brak "falowania" obrotów)**:
   * **EMA Low-pass Filter**: Zamiast reagować na chwilowe 100ms skoki rdzenia krzemowego (`TCMb`), aplikacja łączy odczyty procesora z temperaturą radiatora (`TH0a`) i wygładza je filtrem EMA.
   * **Slew-Rate Limiting**: Ograniczenie tempa zmian obrotów (maks. 50–70 RPM na sekundę przy schładzaniu).
   * **Hysteresis Hold Time**: Po wzroście obrotów wentylator utrzymuje wyższy bieg przez min. 7 sekund przed powolnym zejściem, co całkowicie eliminuje irytujące "falowanie" głośności.
2. **Watchdog Heartbeat w Daemonie**:
   * Daemon pomocniczy (`breeze-helper`) monitoruje stan połączenia. Jeśli aplikacja ulegnie awarii lub zostanie wymuszona jej likwidacja (`kill -9`), daemon po **30 sekundach braku sygnału automatycznie przywraca fabryczny tryb Apple System dla wszystkich wentylatorów (`F0md = 0`, `F1md = 0`)**.
3. **Signal Trapping**:
   * Zarejestrowane procedury obsługi sygnałów `SIGINT`, `SIGTERM` i `SIGHUP` w aplikacji natychmiast przywracają tryb systemowy przed zamknięciem.
4. **Thermal Panic Emergency Override**:
   * Jeśli jakikolwiek sensor przekroczy temperaturę krytyczną **86.0°C**, aplikacja automatycznie ignoruje aktywny profil (nawet *Silent*) i wymusza natychmiast 100% chłodzenia do czasu ustabilizowania temperatur.
5. **Hardware Boundary Clamping**:
   * Obroty są ściśle ryglowane w sprzętowym zakresie Apple Silicon (dla Mac mini M5 Pro: `[1000 RPM, 4900 RPM]`).

---

## 📦 Instalacja / Installation

### 1. Pobranie i instalacja z pliku DMG
Gotowy instalator znajduje się w pliku:
`Breeze-1.0.0.dmg`

1. Otwórz `Breeze-1.0.0.dmg`.
2. Przeciągnij **Breeze.app** do folderu **Applications**.
3. Kliknij dwukrotnie w dołączony skrypt **Install Privileged Helper.command** (lub zainstaluj helper z okna `Settings` w aplikacji).

---

## 🐙 Repozytorium GitHub / GitHub Repository

Projekt jest dostępny na GitHubie:
👉 **[https://github.com/rudkowski-dominik/Breeze](https://github.com/rudkowski-dominik/Breeze)**

```bash
git clone https://github.com/rudkowski-dominik/Breeze.git
cd Breeze
./scripts/build.sh
```

---

## 📁 Struktura Projektu / Project Structure

```text
Breeze/
├── Breeze-1.0.0.dmg                # Gotowy instalator macOS DMG
├── Breeze.app/                     # Gotowa paczka aplikacji Menu Bar
├── AppIcon_preview.png             # Podgląd ikony Liquid Glass (512x512)
├── AppIcon.icns                    # Natywna ikona macOS
├── assets/
│   ├── AppIcon-Dark.png            # Ikona Liquid Glass Dark Mode (2048x2048)
│   ├── AppIcon-Dark.icns           # Plik icns Dark Mode
│   ├── AppIcon-Light.png           # Ikona Liquid Glass Light Mode (2048x2048)
│   └── AppIcon-Light.icns          # Plik icns Light Mode
├── Sources/
│   ├── Breeze/
│   │   ├── AppDelegate.swift       # Cykl życia, rejestracja sygnałów SIGINT/SIGTERM
│   │   ├── main.swift              # Punkt startowy NSApplication
│   │   ├── SMC/
│   │   │   └── SMCEngine.swift     # IOKit AppleSMC, filtr EMA i multi-fan support
│   │   ├── Models/
│   │   │   └── FanProfile.swift    # Skalibrowane profile termiczne, lokalizacja
│   │   ├── Services/
│   │   │   ├── FanManager.swift    # Zarządzanie wentylatorami, optymalizacja energetyczna
│   │   │   ├── LocalizationManager.swift # Obsługa języków: EN, PL, ES
│   │   │   └── HelperClient.swift  # Komunikacja IPC przez /var/run/breeze.sock
│   │   └── UI/
│   │       ├── MenuBarController.swift # Ikona Apple-style, menu status bar
│   │       ├── GaugeMenuItemView.swift # Suwak Control Center i wskaźnik obrotów
│   │       ├── SettingsWindowController.swift # Kontroler okna ustawień
│   │       └── Views/
│   │           ├── ProfileEditorView.swift    # Edytor krzywych i wykres
│   │           └── SettingsView.swift         # Ustawienia, sensory, motywy, instalacja daemona
│   └── Helper/
│       └── main.swift              # Daemon launchd z 30s watchdogiem i obsługą wielu wentylatorów
└── scripts/
    ├── build.sh                    # Kompilacja aplikacji i daemona
    ├── create-dmg.sh               # Tworzenie obrazu instalacyjnego DMG
    ├── export_sources.sh           # Eksport pełnego kodu źródłowego
    ├── process_user_icons.swift    # Generator natywnych ikon Apple HIG Liquid Glass
    └── install-helper.sh           # Instalator daemona launchd
```
