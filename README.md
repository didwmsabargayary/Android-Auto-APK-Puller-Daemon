# Android-Auto-APK-Puller-Daemon
A lightweight, automated Bash daemon that monitors USB connections for Android devices and automatically extracts installed APK files (supporting both standard and split/app bundles) to organized local directories. 
Perfect for security researchers, reverse engineers, and developers looking to archive or audit apps directly from physical devices upon plug-in.

---

## Features

- 🔌 **Plug-and-Play Detection**: Automatically detects Android devices as soon as they are connected via USB with USB debugging enabled.
- 🔄 **Stateful Loop (No Infinite Pulls)**: Tracks connected devices using internal state tracking so that connected devices are processed exactly once per USB session (no infinite loops while plugged in).
- 🧩 **Split APK (App Bundle) Support**: Detects and pulls all split parts (e.g., config, language, architecture APKs) into a dedicated folder for each package, avoiding filename collisions.
- 📦 **Targeted Extraction**: Allows you to pull either user-installed (third-party) apps only to save storage/time (default), or all apps including system packages (`-a` / `--all`).
- 📁 **Organized Directory Structure**: Creates clean, timestamped output directories organized by device brand, model, serial, and connection time:
  `extracted_apks/Brand_Model_Serial_YYYYMMDD_HHMMSS/`
- 🛡️ **Robust Error Handling**: Checks for device authorization states and alerts you if a connected phone is unauthorized. Also detects abrupt disconnections during file transfer to prevent corrupt downloads.
- 🚀 **Zero Dependencies (Except ADB)**: Pure Bash script that uses basic utilities (`sed`, `awk`, `grep`) and standard ADB commands.

---

## Prerequisites

Before using this script, ensure you have the following requirements satisfied:

### 1. Host Machine Requirements
You must have the Android Debug Bridge (`adb`) installed on your system.

- **Debian / Ubuntu / Kali Linux**:
  ```bash
  sudo apt update && sudo apt install -y adb
  ```
- **Fedora / RHEL**:
  ```bash
  sudo dnf install android-tools
  ```
- **macOS**:
  ```bash
  brew install android-platform-tools
  ```

### 2. Android Device Requirements
- **Developer Options** must be enabled:
  - Go to **Settings** -> **About phone** -> Tap **Build number** 7 times.
- **USB Debugging** must be toggled on:
  - Go to **Settings** -> **System** -> **Developer options** -> Enable **USB debugging**.

---

## Installation & Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/android-auto-apk-puller.git
   cd android-auto-apk-puller
   ```

2. **Make the script executable**:
   ```bash
   chmod +x autopull_apks.sh
   ```

---

## Usage Syntax

```bash
./autopull_apks.sh [OPTIONS]
```

### Options

| Flag | Long Option | Description |
|------|-------------|-------------|
| `-a` | `--all` | Pull all installed apps, including system and bloatware apps (default is only user-installed apps). |
| `-o` | `--output` | Specify a custom output directory (default: `./extracted_apks`). |
| `-i` | `--interval`| Time interval in seconds to poll for new USB devices (default: `2`). |
| `-h` | `--help` | Show the help message and exit. |

---

## Step-by-Step Guide

1. **Start the daemon in your terminal**:
   ```bash
   ./autopull_apks.sh
   ```
   The terminal will print initialization details and start waiting for connection:
   ```
   ================================================================
            Android Auto APK Puller Daemon is Active                
   ================================================================
   Output Directory:  extracted_apks
   App Selection Mode: User Installed (3rd-party) only
   Polling Interval:  2s
   ----------------------------------------------------------------
   [*] Waiting for Android device connection via USB...
   [*] Make sure 'USB Debugging' is enabled in Developer Options.
   ----------------------------------------------------------------
   ```

2. **Plug in your phone** via a USB cable.

3. **Authorize the computer on your phone screen**:
   Look at your phone for a prompt asking: *Allow USB debugging?*
   Check **"Always allow from this computer"** and tap **Allow**.

4. **Observe the download**:
   The script will detect the authorization state, fetch the device brand (e.g. *Samsung*, *Google*) and model, and start pulling all the APKs package-by-package.

5. **Stop the daemon**:
   Press `Ctrl + C` at any time to safely shut down the daemon.

---

## Under the Hood

Unlike simple loops that use `while read` along with interactive commands, this script is built to be robust against **stdin consumption** issues. It uses standard Bash `for` loops to iterate over package collections, preventing `adb` commands from swallowing the package queue. It also tracks the active state of each connected serial key to allow multi-device management without collision or repetitive downloads.

---

## License

This project is licensed under the MIT License. Feel free to use, modify, and distribute it.
