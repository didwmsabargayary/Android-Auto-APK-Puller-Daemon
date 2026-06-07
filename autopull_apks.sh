#!/usr/bin/env bash

# ==============================================================================
# Auto APK Puller Daemon
# Automatically detects Android devices via USB and pulls installed APKs.
# ==============================================================================

# ANSI Color Codes for Premium UI Aesthetics
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
OUTPUT_DIR="extracted_apks"
PULL_SYSTEM_APPS=false
POLL_INTERVAL=2

# Usage Guide
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

An automated daemon that monitors USB connections for Android devices and 
automatically pulls installed APKs when a device is connected.

Options:
  -a, --all          Pull all installed APKs (including system apps). 
                     By default, only user-installed (3rd-party) apps are pulled.
  -o, --output DIR   Specify output directory (default: './extracted_apks').
  -i, --interval SEC Specify connection polling interval in seconds (default: 2).
  -h, --help         Show this help message and exit.
EOF
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -a|--all) PULL_SYSTEM_APPS=true; shift ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -i|--interval) POLL_INTERVAL="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
done

# Function to check and install dependencies
check_dependencies() {
    if ! command -v adb &> /dev/null; then
        echo -e "${RED}[!] Error: 'adb' command not found.${NC}"
        echo -e "${YELLOW}[*] To run this script, please install Android Debug Bridge (ADB).${NC}"
        echo -e "On Debian/Ubuntu/Kali Linux: ${CYAN}sudo apt update && sudo apt install -y adb${NC}"
        echo -e "On Fedora/RHEL: ${CYAN}sudo dnf install android-tools${NC}"
        echo -e "On macOS: ${CYAN}brew install android-platform-tools${NC}"
        exit 1
    fi
}

check_dependencies

# Start ADB server if not already running
echo -e "${BLUE}[*] Initializing ADB Server...${NC}"
adb start-server > /dev/null

# Track processed devices: key is Serial, value is State (e.g. "done", "unauthorized")
declare -A PROCESSED_DEVICES

# Handle script termination gracefully
cleanup() {
    echo -e "\n${BLUE}[*] Shutting down APK Auto-Pull Daemon...${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}         Android Auto APK Puller Daemon is Active                ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "${CYAN}Output Directory:${NC}  $OUTPUT_DIR"
echo -e "${CYAN}App Selection Mode:${NC} $([ "$PULL_SYSTEM_APPS" = true ] && echo "All Apps (System & User)" || echo "User Installed (3rd-party) only")"
echo -e "${CYAN}Polling Interval:${NC}  ${POLL_INTERVAL}s"
echo -e "----------------------------------------------------------------"
echo -e "${YELLOW}[*] Waiting for Android device connection via USB...${NC}"
echo -e "${YELLOW}[*] Make sure 'USB Debugging' is enabled in Developer Options.${NC}"
echo -e "----------------------------------------------------------------"

# Main daemon loop
while true; do
    # 1. Fetch current devices and their states
    # adb devices output:
    # List of devices attached
    # [serial]       [state]
    devices_raw=$(adb devices | tail -n +2)
    
    current_authorized=""
    current_unauthorized=""
    
    while read -r line; do
        [ -z "$line" ] && continue
        serial=$(echo "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        
        if [[ "$state" == "device" ]]; then
            current_authorized="$current_authorized $serial"
        elif [[ "$state" == "unauthorized" ]]; then
            current_unauthorized="$current_unauthorized $serial"
        fi
    done <<< "$devices_raw"
    
    # Trim leading/trailing whitespace
    current_authorized=$(echo "$current_authorized" | xargs)
    current_unauthorized=$(echo "$current_unauthorized" | xargs)

    # 2. Report unauthorized devices (only once)
    for dev in $current_unauthorized; do
        if [[ "${PROCESSED_DEVICES[$dev]}" != "unauthorized" ]]; then
            echo -e "${RED}[!] Device detected ($dev) but it is UNAUTHORIZED.${NC}"
            echo -e "${YELLOW}[?] Please check your phone screen and tap 'Allow USB debugging'.${NC}"
            PROCESSED_DEVICES[$dev]="unauthorized"
        fi
    done

    # 3. Clean up disconnected devices from our state tracker
    for dev in "${!PROCESSED_DEVICES[@]}"; do
        if ! echo "$current_authorized $current_unauthorized" | grep -q "\b$dev\b"; then
            echo -e "${YELLOW}[-] Device disconnected: $dev${NC}"
            unset PROCESSED_DEVICES[$dev]
        fi
    done

    # 4. Process newly connected authorized devices
    for dev in $current_authorized; do
        # Process if device is completely new, or was previously unauthorized but is now authorized
        if [[ -z "${PROCESSED_DEVICES[$dev]}" ]] || [[ "${PROCESSED_DEVICES[$dev]}" == "unauthorized" ]]; then
            echo -e "${GREEN}[+] Authorized device connected: $dev${NC}"
            PROCESSED_DEVICES[$dev]="processing"
            
            # Fetch device metadata
            device_model=$(adb -s "$dev" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | sed 's/[^a-zA-Z0-9_-]/_/g')
            device_brand=$(adb -s "$dev" shell getprop ro.product.brand 2>/dev/null | tr -d '\r' | sed 's/[^a-zA-Z0-9_-]/_/g')
            
            [ -z "$device_model" ] && device_model="Unknown"
            [ -z "$device_brand" ] && device_brand="Android"
            
            timestamp=$(date +"%Y%m%d_%H%M%S")
            device_dir="$OUTPUT_DIR/${device_brand}_${device_model}_${dev}_${timestamp}"
            mkdir -p "$device_dir"
            
            echo -e "${BLUE}[*] Device identified:${NC} $device_brand $device_model"
            echo -e "${BLUE}[*] Pulling APKs to:${NC} $device_dir"
            
            # Get list of packages
            if [ "$PULL_SYSTEM_APPS" = true ]; then
                packages=$(adb -s "$dev" shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
            else
                # Filter for user-installed apps (-3)
                packages=$(adb -s "$dev" shell pm list packages -3 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort)
            fi
            
            if [ -z "$packages" ]; then
                echo -e "${YELLOW}[-] No suitable packages found or unable to list packages on $dev.${NC}"
                PROCESSED_DEVICES[$dev]="done"
                continue
            fi
            
            total_packages=$(echo "$packages" | wc -l)
            echo -e "${CYAN}[*] Found $total_packages packages to pull.${NC}"
            
            count=0
            interrupted=false
            
            for package in $packages; do
                [ -z "$package" ] && continue
                count=$((count + 1))
                
                # Check connection status before each pull to handle abrupt disconnection
                if ! adb -s "$dev" get-state &>/dev/null; then
                    echo -e "\n${RED}[!] Device disconnected during transfer: $dev${NC}"
                    interrupted=true
                    break
                fi
                
                # Find APK path(s)
                paths=$(adb -s "$dev" shell pm path "$package" 2>/dev/null | tr -d '\r' | sed 's/^package://')
                
                if [ -z "$paths" ]; then
                    echo -e "${RED}[-] Skipping $package: unable to find APK path.${NC}"
                    continue
                fi
                
                path_count=$(echo "$paths" | wc -l)
                
                if [ "$path_count" -gt 1 ]; then
                    # Split APK / App Bundle detected
                    package_dir="$device_dir/$package"
                    mkdir -p "$package_dir"
                    echo -e " [${count}/${total_packages}] ${CYAN}Pulling split APK bundle for ${YELLOW}${package}${NC} (${path_count} files)..."
                    
                    split_idx=1
                    for apk_path in $paths; do
                        [ -z "$apk_path" ] && continue
                        apk_name=$(basename "$apk_path")
                        adb -s "$dev" pull "$apk_path" "$package_dir/$apk_name" >/dev/null 2>&1
                        split_idx=$((split_idx + 1))
                    done
                else
                    # Standard Single APK
                    echo -e " [${count}/${total_packages}] ${CYAN}Pulling ${YELLOW}${package}${NC}..."
                    adb -s "$dev" pull "$paths" "$device_dir/${package}.apk" >/dev/null 2>&1
                fi
            done
            
            if [ "$interrupted" = true ]; then
                echo -e "${RED}[!] Extraction was interrupted. Extracted files remain in $device_dir.${NC}"
                # Clean up if directory is completely empty
                if [ -z "$(ls -A "$device_dir" 2>/dev/null)" ]; then
                    rmdir "$device_dir"
                fi
                # Reset state so it retries connection/pull when plugged back in
                unset PROCESSED_DEVICES[$dev]
            else
                echo -e "${GREEN}[+] Successfully pulled all APKs for $device_brand $device_model ($dev).${NC}"
                PROCESSED_DEVICES[$dev]="done"
            fi
            
            echo -e "----------------------------------------------------------------"
            echo -e "${YELLOW}[*] Waiting for Android device connection via USB...${NC}"
            echo -e "----------------------------------------------------------------"
        fi
    done
    
    sleep "$POLL_INTERVAL"
done
