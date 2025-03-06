#!/bin/bash

FIDO2_TOKEN_CMD="/usr/local/bin/fido2-token2"

list=false
info=false
device=""
pin=""
storage=false
residentKeys=false
domain=""
delete=false
credential=""
changePIN=false
setPIN=false
reset=false
uvs=false
uvd=false
fingerprint=false
help=false

show_message() {
    local message=$1
    local type=${2:-"Info"}
    echo "[$type] $message"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -list) list=true ;;
        -info) info=true ;;
        -device) device="$2"; shift ;;
        -pin) pin="$2"; shift ;;
        -storage) storage=true ;;
        -fingerprint) fingerprint=true ;;        
        -residentKeys) residentKeys=true ;;
        -domain) domain="$2"; shift ;;
        -delete) delete=true ;;
        -credential) credential="$2"; shift ;;
        -changePIN) changePIN=true ;;
        -setPIN) setPIN=true ;;
        -reset) reset=true ;;
        -uvs) uvs=true ;;
        -uvd) uvd=true ;;
        -help) help=true ;;
        *) show_message "Unknown parameter: $1" "Error"; exit 1 ;;
    esac
    shift
done

show_help() {
    cat << EOF
FIDO2 Token Management Tool
v 0.2.2
This is a wrapper for libfido2 library - modified for macOS

(c) Token2 Sarl

Usage: ./fido2-manage.sh [-list] [-info -device <number>] [-storage -device <number>] [-residentKeys -device <number> -domain <domain>] [-uvs] [-uvd] [-delete -device <number> -credential <credential>] [-help]

Examples:
  ./fido2-manage.sh -list
  ./fido2-manage.sh -info -device 1
  ./fido2-manage.sh -storage -device 2
  ./fido2-manage.sh -residentKeys -device 1 -domain login.microsoft.com
  ./fido2-manage.sh -uvs -device 1
  ./fido2-manage.sh -uvd -device 1
  ./fido2-manage.sh -setPIN -device 1
  ./fido2-manage.sh -fingerprint -device 1
  ./fido2-manage.sh -reset -device 1
  ./fido2-manage.sh -changePIN -device 1
  ./fido2-manage.sh -delete -device 2 -credential Y+Dh/tSy/Q2IdZt6PW/G1A==
  ./fido2-manage.sh -help
EOF
}

if $help; then
    show_help
    exit 0
fi

if ! $list && ! $info && [[ -z $device ]] && ! $fingerprint && ! $storage && ! $residentKeys && [[ -z $domain ]] && ! $delete && [[ -z $credential ]] && ! $changePIN && ! $setPIN && ! $reset && ! $uvs && ! $uvd && ! $help; then
    show_help
    exit 1
fi

if $list; then
    if ! command_output=$($FIDO2_TOKEN_CMD -L 2>&1); then
        show_message "Error executing $FIDO2_TOKEN_CMD -L: $command_output" "Error"
        exit 1
    fi

    device_count=1
    echo "$command_output" | while read -r line; do
        if [[ $line =~ ^([^:]+) ]]; then
            echo "Device [$device_count] : $(echo "${line}" | ggrep -oP '\(([^)]+)\)' | sed 's/(\(.*\))/\1/')"
            device_count=$((device_count + 1))
        fi
    done
    exit 0
fi

if [[ -n $device ]]; then
    device_index=$((device - 1))
    if ! command_output=$($FIDO2_TOKEN_CMD -L 2>&1); then
        show_message "Error executing $FIDO2_TOKEN_CMD -L: $command_output" "Error"
        exit 1
    fi

    if [[ $command_output =~ pcsc://slot0: ]]; then
        device_string="pcsc://slot0"
    else
        device_string=$(echo "$command_output" | sed -n "$((device_index + 1))p" | awk -F':' '{print $1":"$2}')
    fi

    if $reset; then
        show_message "WARNING: Factory reset will remove all data and settings. Are you sure? (Y/N)"
        read -r confirmation
        if [[ $confirmation =~ [Yy] ]]; then
            show_message "Touch or press the security key button when it starts blinking."
            if ! output=$($FIDO2_TOKEN_CMD -R "$device_string" 2>&1); then
                if [[ $output == *"FIDO_ERR_NOT_ALLOWED"* ]]; then
                    show_message "Error: Factory reset not allowed. Unplug and retry within 10 seconds."
                else
                    show_message "Factory reset completed."
                fi
            fi
        else
            show_message "Factory reset canceled."
        fi
        exit 0
    fi

    if $changePIN; then
        show_message "Enter the old and new PIN below."
        $FIDO2_TOKEN_CMD -C "$device_string"
        exit 0
    fi

    if $uvs; then
        show_message "Enforcing user verification."
        $FIDO2_TOKEN_CMD -Su "$device_string"
        exit 0
    fi

    if $uvd; then
        show_message "Disabling user verification."
        $FIDO2_TOKEN_CMD -Du "$device_string"
        exit 0
    fi

    if $setPIN; then
        show_message "Enter and confirm the PIN as prompted."
        $FIDO2_TOKEN_CMD -S "$device_string"
        exit 0
    fi

    if $delete && [[ -n $credential ]]; then
        show_message "WARNING: Deleting a credential is irreversible. Are you sure? (Y/N)"
        read -r confirmation
        if [[ $confirmation =~ [Yy] ]]; then
            $FIDO2_TOKEN_CMD -D -i "$credential" "$device_string"
            show_message "Credential deleted successfully."
        else
            show_message "Deletion canceled."
        fi
        exit 0
    fi

    pin_option=$([[ -n $pin ]] && echo "-w \"$pin\"")

    if $fingerprint; then
        echo "Enrolling fingerprints (for bio models only)"
        $FIDO2_TOKEN_CMD "$pin_option" -S -e "$device_string"
        exit 0
    fi    

    if $storage; then
        $FIDO2_TOKEN_CMD -I -c "$pin_option" "$device_string"
        exit 0
    elif $residentKeys; then
        if [[ -n $domain ]]; then
            domain_command="$FIDO2_TOKEN_CMD -L -k \"$domain\" $pin_option \"$device_string\""
            domain_output=$(eval "$domain_command")

            echo "$domain_output" | while read -r line; do
                credential_id=$(echo "$line" | awk '{print $2}')
                user_field=$(echo "$line" | awk '{print $3 , $4}')
                email_field=$(echo "$line" | awk '{print $5, $6}')

                if [[ "$user_field" == "(null)" ]]; then
                    user_field=""
                fi

                if [[ "$user_field" == *"@"* ]]; then
                    email=$user_field
                    user=""
                else
                    user=$user_field
                    email=$email_field
                fi

                show_message "Credential ID: $credential_id, User: $user $email"
            done
        else
            $FIDO2_TOKEN_CMD -L -r "$pin_option" "$device_string"
        fi
        exit 0
    fi

    if $info; then
        command_output=$($FIDO2_TOKEN_CMD -I "$device_string")
        show_message "Device $device Information:"
        echo "$command_output"
        exit 0
    fi
fi
