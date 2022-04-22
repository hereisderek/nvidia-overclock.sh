#!/usr/bin/env bash
################################################################################
# Copyright (c) 2020 Plyint, LLC <contact@plyint.com>. All Rights Reserved.
# This file is licensed under the MIT License (MIT).
# Please see LICENSE.txt for more information.
#
# DESCRIPTION:
# A simple script to manage overclocking of NVIDIA Graphics cards on Linux.
#
# To use it, please perform the following steps:
# (1) Update the values in the overclock() function with values for your GPUs.
# (2) Install the script by changing to its directory and running:
#
#     ./nvidia-overclock.sh install-svc -x
#
#     This will install the service and use "startx" to automatically start
#     XWindows.  If you already have XWindows installed and configured to run
#			automatically on boot, then omit the -x option:
#
#      ./nvidia-overclock.sh install-svc
#
# (3) Reboot the system and XWindows should start automatically with your GPUs
#     set to the specified overclocked values.
#
# For the full documentation and detailed requirements, please read the
# accompanying README.md file.
################################################################################

LOG_FILE="/var/log/nvidia-overclock.log"
LOG=0

SMI='/usr/bin/nvidia-smi'
SET='/usr/bin/nvidia-settings'
VER=$(awk '/NVIDIA/ {print $8}' /proc/driver/nvidia/version | cut -d . -f 1)

NUM_GPU="$(nvidia-smi -L | wc -l)"
NUM_FAN="$(DISPLAY=:0 /usr/bin/nvidia-settings -q fans | grep "FAN-" | wc -l)"

# Drivers from 285.x.y on allow persistence mode setting
if [ ${VER} -lt 285 ]; then
  echo "Error: Current driver version is ${VER}. Driver version must be greater than 285."
  exit 1
fi


echo "NUM_GPU:$NUM_GPU NUM_FAN:$NUM_FAN VER:$VER"

# power limit
set_gpu_pl() {
  echo "set_gpu_pl $@ .."
  if [ "$1" = "stop" ]; then 
    # reset power limit to default
    for ((i = 0 ; i < $NUM_GPU; i++)); do
      local pl_query=$(nvidia-smi -q -d POWER -i ${i})
      local pl_query=$(nvidia-smi -q -d POWER -i 0)
      local current_power_draw=$(echo "${pl_query}" | grep 'Power Draw' | tr -s ' ' | cut -d ' ' -f 5)
      local current_pl=$(echo "${pl_query}" | grep '   Power Limit' | tr -s ' ' | head -n 1 | cut -d ' ' -f 5) # there might be a better way
      local default_pl=$(echo "${pl_query}" | grep 'Default Power Limit' | tr -s ' ' | cut -d ' ' -f 6)
      local mini_pl=$(echo "${pl_query}" | grep 'Min Power Limit' | tr -s ' ' | cut -d ' ' -f 6)
      local max_pl=$(echo "${pl_query}" | grep 'Max Power Limit' | tr -s ' ' | cut -d ' ' -f 6)

      printf "set_gpu_pl to Default Power Limit($default_pl) on GPU[${i}] Power Draw:$current_power_draw Power Limit:$current_pl Default Power Limit:$default_pl Max Power Limit:$max_pl.."
      $SMI -i $i -pm 1 &> /dev/null
      $SMI -i $i -pl $default_pl &> /dev/null

      sleep 2
      local pl_query=$(nvidia-smi -q -d POWER -i ${i})
      local new_power_draw=$(echo "${pl_query}" | grep 'Power Draw' | tr -s ' ' | cut -d ' ' -f 5)
      local new_pl=$(echo "${pl_query}" | grep '   Power Limit' | tr -s ' ' | head -n 1 | cut -d ' ' -f 5) # there might be a better way
      
      printf "\t Completed with [Power Limit:${new_pl} Power Draw:${new_power_draw}]\n\n"
    done

  elif [ "$1" -eq "$1" ] 2>/dev/null; then
    for ((i = 0 ; i < $NUM_GPU; i++)); do
      local target_pl=$1
      local pl_query=$(nvidia-smi -q -d POWER -i ${i})
      local current_power_draw=$(echo "${pl_query}" | grep 'Power Draw' | tr -s ' ' | cut -d ' ' -f 5)
      local current_pl=$(echo "${pl_query}" | grep '   Power Limit' | tr -s ' ' | head -n 1 | cut -d ' ' -f 5) # there might be a better way
      local default_pl=$(echo "${pl_query}" | grep 'Default Power Limit' | tr -s ' ' | cut -d ' ' -f 6)
      local mini_pl=$(echo "${pl_query}" | grep 'Min Power Limit' | tr -s ' ' | cut -d ' ' -f 6)
      local max_pl=$(echo "${pl_query}" | grep 'Max Power Limit' | tr -s ' ' | cut -d ' ' -f 6)

      if [[ ${POWER_LIMIT%.*}+0 -gt ${MAX_POWER_LIMIT%.*}+0 ]]; then
        echo "Error, target Power Limit($target_pl) > MAX_POWER_LIMIT($max_pl)"
        continue;
      fi
      
      printf "set_gpu_pl to Default Power Limit($default_pl) on GPU[${i}] Power Draw:$current_power_draw Power Limit:$current_pl Default Power Limit:$default_pl Max Power Limit:$max_pl.."
      $SMI -i $i -pm 1 &> /dev/null
      $SMI -i $i -pl $target_pl &> /dev/null

      sleep 2
      local pl_query=$(nvidia-smi -q -d POWER -i ${i})
      local new_power_draw=$(echo "${pl_query}" | grep 'Power Draw' | tr -s ' ' | cut -d ' ' -f 5)
      local new_pl=$(echo "${pl_query}" | grep '   Power Limit' | tr -s ' ' | head -n 1 | cut -d ' ' -f 5) # there might be a better way
      
      printf "\t Completed with [Power Limit:${new_pl} Power Draw:${new_power_draw}]\n\n"
    done
    
  else 
    echo "set_gpu_pl Invalid input: $1"
    exit 1;
  fi
}

set_fan_speed() {
  # fan speed in percentage or "stop" for default audo adjustment

  if [ "$1" = "stop" ] || [ "$1" -lt "0" ]; then 
    # Stop
    $SMI -pm 0 # disable persistance mode

    echo "Enabling default auto fan control.. NUM_GPU:$NUM_GPU"
    
    for ((i = 0 ; i < $NUM_GPU; i++)); do
        DISPLAY=:0 ${SET} -a [gpu:${i}]/GPUFanControlState=0 -- :0 -once &> /dev/null
    done

    echo "Complete"
  elif [ "$1" -eq "$1" ] 2>/dev/null; then
    $SMI -pm 1 # enable persistance mode
    speed=$1

    echo "Setting fan to $speed%.."
    for ((i = 0 ; i < $NUM_GPU; i++)); do
        DISPLAY=:0 ${SET} -a [gpu:${i}]/GPUFanControlState=1 -- :0 -once &> /dev/null
    done

    for ((i = 0 ; i < $NUM_FAN; i++)); do
        DISPLAY=:0 ${SET} -a [fan:${i}]/GPUTargetFanSpeed=$speed -- :0 -once
        local set_speed=`DISPLAY=:0 ${SET} -q [fan:${i}]/GPUTargetFanSpeed -t`
        echo "fan speed set for fan[${i}]:${set_speed}"
    done
    echo "Complete"
  else
    echo "invalid input for set_fan_speed:${1}"; exit 1;
  fi
}

overclock_cclock_mem() {
  if [ "$1" = "stop" ]; then 
    local clock=0
    local mem=0
  else 
    local clock=$1 #GPUGraphicsClockOffset
    local mem=$2 #GPUMemoryTransferRateOffset 
  fi


  [ ${clock} -ne ${clock} ] || [ ${mem} -ne ${mem} ] && {
    echo "invalid input for overclock_cclock_mem clock:$clock mem:$mem"
    exit 1
  }

  echo "updating overclock GPUGraphicsClockOffset:$clock GPUMemoryTransferRateOffset:$mem..."
  for ((i = 0; i < $NUM_GPU; i++)); do
    # DISPLAY=:0 ${SET} -a [gpu:${i}]/GPUGraphicsClockOffset[3]=${clock} -a [gpu:${i}]/GPUMemoryTransferRateOffset[3]=${mem}  -- :0 -once
    DISPLAY=:0 ${SET} -c :0 -a [gpu:${i}]/GPUGraphicsClockOffset[3]=${clock} -a [gpu:${i}]/GPUMemoryTransferRateOffset[3]=${mem} -a [gpu:${i}]/GPUPowerMizerMode=1
    local set_clock=`DISPLAY=:0 ${SET} -q [gpu:${i}]/GPUGraphicsClockOffset[3] -t`
    local set_mem=`DISPLAY=:0 ${SET} -q [gpu:${i}]/GPUMemoryTransferRateOffset[3] -t`
    echo "GPU:$i overclock settings updated, GPUGraphicsClockOffset:$set_clock GPUMemoryTransferRateOffset:$set_mem"
  done
}

stop_oc() {
  set_gpu_pl "stop"
  set_fan_speed "stop"
  overclock_cclock_mem "stop"
}

overclock() {
  # The following default overclock values for the NVIDIA GTX 1070
  # were found on average to be stable:
  # - Graphics Clock       = 100
  # - Memory Transfer Rate = 1300
  #
  # Adjust these values for each card as needed.  Some cards are more
  # unstable than others and will only tolerate less overclocking.  Other
  # cards might tolerate above normal overclocking. If you are unsure of the
  # starting values to use for your graphics cards, try searching online
  # for what other people with your same graphics cards have found to be stable.
  #
  # Note: The lines below were used to configure a system with 6 graphics cards.
  # You will neeed to add/remove lines based on the number of graphics cards in
  # your particular system.
  #log "Calling nvidia-settings to overclock GPU(s).."
  #log "$(nvidia-settings -c :0 -a '[gpu:0]/GPUGraphicsClockOffset[3]=100' -a '[gpu:0]/GPUMemoryTransferRateOffset[3]=1300')"
  #log "$(nvidia-settings -c :0 -a '[gpu:1]/GPUGraphicsClockOffset[3]=100' -a '[gpu:1]/GPUMemoryTransferRateOffset[3]=1300')"
  #log "$(nvidia-settings -c :0 -a '[gpu:2]/GPUGraphicsClockOffset[3]=100' -a '[gpu:2]/GPUMemoryTransferRateOffset[3]=1300')"
  #log "$(nvidia-settings -c :0 -a '[gpu:3]/GPUGraphicsClockOffset[3]=100' -a '[gpu:3]/GPUMemoryTransferRateOffset[3]=1300')"
  #log "$(nvidia-settings -c :0 -a '[gpu:4]/GPUGraphicsClockOffset[3]=100' -a '[gpu:4]/GPUMemoryTransferRateOffset[3]=1300')"
  #log "$(nvidia-settings -c :0 -a '[gpu:5]/GPUGraphicsClockOffset[3]=100' -a '[gpu:5]/GPUMemoryTransferRateOffset[3]=1300')"

  set_gpu_pl 130
  set_fan_speed 90
  overclock_cclock_mem -200 1300
}

abs_filename() {
  # $1 : relative filename
  filename="$1"
  parentdir="$(dirname "${filename}")"

  if [ -d "${filename}" ]; then
    cd "${filename}" && pwd
  elif [ -d "${parentdir}" ]; then
    echo "$(cd "${parentdir}" && pwd)/$(basename "${filename}")"
  fi
}

SCRIPT="$(abs_filename "$0")"

log() {
  if [ "$LOG" -eq 1 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S - ')$1" >>$LOG_FILE
  fi
  echo "$1"
}

xserver_up() {
  # Give Xserver 10 seconds to come up
  sleep 5

  # shellcheck disable=SC2009,SC2126
  if [ "$(ps ax | grep '[x]init' | wc -l)" = "1" ]; then
    log "An Xserver is running."
  else
    log "Error: No xinit process found. Exiting."
    exit
  fi
}

install_svc() {
  log "Creating systemd services.."

  # If STARTX is set then we will add a service file
  # to systemd to launch the Xserver
  if [ -n "$STARTX" ]; then
    cat <<EOF >/etc/systemd/system/nvidia-overclock-startx.service
[Unit]
Description=StartX to overclock NVIDIA GPUs
After=runlevel4.target

[Service]
Type=oneshot
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/etc/X11/.Xauthority"
ExecStart=/usr/bin/startx

[Install]
WantedBy=nvidia-overclock.service
EOF
  fi

  cat <<EOF >/etc/systemd/system/nvidia-overclock.service
[Unit]
Description=Overclock NVIDIA GPUs at system start
After=runlevel4.target

[Service]
Type=oneshot
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/etc/X11/.Xauthority"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$SCRIPT auto -l -x

[Install]
WantedBy=multi-user.target
EOF

  chmod 664 /etc/systemd/system/nvidia-overclock-startx.service
  chmod 664 /etc/systemd/system/nvidia-overclock.service
  log "Reloading systemd daemon.."
  systemctl daemon-reload
  systemctl enable nvidia-overclock-startx.service
  systemctl enable nvidia-overclock.service
  log "Services installation complete."
}

uninstall_svc() {
  # Remove services
  if [ -f "/etc/systemd/system/nvidia-overclock-startx.service" ]; then
    log "Uninstalling nvidia-overclock-startx.service.."
    systemctl disable nvidia-overclock-startx.service
    rm /etc/systemd/system/nvidia-overclock-startx.service
    RELOAD_SYSTEMD=1
  else
    log "No nvidia-overclock-startx.service file exists to uninstall."
  fi

  if [ -f "/etc/systemd/system/nvidia-overclock.service" ]; then
    log "Uninstalling nvidia-overclock.service.."
    systemctl disable nvidia-overclock.service
    rm /etc/systemd/system/nvidia-overclock.service
    RELOAD_SYSTEMD=1
  else
    log "No nvidia-overclock.service file exists to uninstall."
  fi

  # Reload systemd
  if [ -n "$RELOAD_SYSTEMD" ]; then
    log "Reloading systemd daemon.."
    systemctl daemon-reload
    systemctl reset-failed
    log "Service uninstall complete."
  fi
}

create_Xwrapper_config() {
  # Preserve the existing Xwrapper.config file if it exists
  if [ ! -f "/etc/X11/Xwrapper.config.orig" ]; then
    if [ -f "/etc/X11/Xwrapper.config" ]; then
      mv /etc/X11/Xwrapper.config /etc/X11/Xwrapper.config.orig
    fi
  else
    # If an existing Xwrapper.config.orig file exists (even if it was
    # created by us), do NOT overwrite as this could be an accidental run
    # to install the service again. Better to have the user manually verify
    # and move it themselves.
    log "Error: Unable to move /etc/X11/Xwrapper.config."
    log "The file /etc/X11/Xwrapper.config.orig already exists. Please move or rename it."
    log "Exiting to avoid overwriting the existing file."
    exit
  fi

  # Create a custom /etc/X11/Xwrapper.config if it does not already exist
  if [ ! -f "/etc/X11/Xwrapper.config" ]; then
    cat <<EOF >/etc/X11/Xwrapper.config
# Xwrapper.config (Debian X Window System server wrapper configuration file)
#
# This file was generated by nvidia-overclock.sh script to enable startx
# to be invoked from a non-console session at startup.
#
# The original file has been moved to /etc/X11/Xwrapper.config.orig
allowed_users=anybody
needs_root_rights=yes
EOF
  fi
}

restore_Xwrapper_config() {
  if [ -f "/etc/X11/Xwrapper.config" ]; then
    # As a safety measure only overwrite config files that were created by nvidia-overclock.sh
    # shellcheck disable=SC2009,SC2126
    if [ "$(grep nvidia-overclock /etc/X11/Xwrapper.config | wc -l)" = "1" ]; then
      RESTORE_XWRAPPER=1
    else
      log "Existing /etc/X11/Xwrapper.config was not created by nvidia-overclock.sh."
      log "No restoration of the original file will be performed."
      return
    fi
  else
    RESTORE_XWRAPPER=1
  fi

  if [ -n "$RESTORE_XWRAPPER" ]; then
    if [ -f "/etc/X11/Xwrapper.config.orig" ]; then
      log "Found original Xwrapper.config file.  Restoring.."
      mv /etc/X11/Xwrapper.config.orig /etc/X11/Xwrapper.config
      log "Xwrapper.config file restored."
    else
      log "No original Xwrapper.config file found."
    fi
  fi
}

usage() {
  cat <<EOF
Usage:
  nvidia-overclock.sh [COMMAND]

Description:
  This script manages simple overclocking of NVIDIA Graphics cards on Linux.

  To use it, please perform the following steps:
  (1) Update the values in the overclock() function with values for your GPUs.
  (2) Install the script by changing to its directory and running:
 
      ./nvidia-overclock.sh install-svc -x

      This will install the service and use "startx" to automatically start
      XWindows.  If you already have XWindows installed and configured to run
      automatically on boot, then omit the -x option.
 
      ./nvidia-overclock.sh install-svc
 
  (3) Reboot the system and XWindows should start automatically with your GPUs
      set to the specified overclocked values.
 
  For the full documentation and detailed requirements, please read the 
  accompanying README.md file.

Commands:
  stop
    Stop overclocking.

  overclock
    Set the overclock values for the graphics card(s) defined in the overclock
    function.  No check is performed to verify if XWindows is running or if 
    logging is enabled.

  auto [-l] [-x]
    Check that XWindows is started if the -x is passed.  If XWindows is 
    started, then set the overclock values for the graphics cards(s) defined in
    the overclock function.  If -l is passed, then output will be logged to the
    file specified by LOG_FILE.

  install-svc [-x]
    Creates a systemd service to overclock the cards, installs, and enables it.
    If the -x option is passed, then it will create a custom Xwrapper.config
    file, so that "startx" can be used to automatically start XWindows on boot.

  uninstall-svc
    Removes the systemd service and restores the original Xwrapper.config file
    if it previously existed.

  help|--help|usage|--usage|?
    Display this help message.
EOF
}

case $1 in
stop)
  # reset to default
  stop_oc
  ;;
overclock)
  # Set the overclock values for the graphics card(s).
  # No check is performed for XWindows or logging.

  overclock
  ;;
auto)
  # If -l parameter is passed then enable logging
  # If -x parameter is passed then check that Xwindows is running
  shift
  while getopts ":lx" OPTS; do
    case $OPTS in
    l)
      LOG=1
      shift
      ;;
    x)
      xserver_up
      shift
      ;;
    esac
  done

  overclock
  ;;
install-svc)
  # Automatically creates a systemd service script
  # and installs the service so it will be run
  # everytime the system starts up.

  # If -x parameter is passed then replace
  # the /etc/X11/Xwrapper.config file
  shift
  while getopts ":x" OPTS; do
    case $OPTS in
    x) STARTX="/usr/bin/startx" && create_Xwrapper_config ;;
    esac
  done

  install_svc
  ;;
uninstall-svc)
  # Removes the systemd service
  restore_Xwrapper_config
  uninstall_svc
  ;;
help | --help | usage | --usage | \?)
  usage
  ;;
*)
  usage
  ;;
esac
