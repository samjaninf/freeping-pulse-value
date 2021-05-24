#!/bin/sh -
#======================================================================================================================
# vim: softtabstop=4 shiftwidth=4 expandtab fenc=utf-8 spell spelllang=en cc=120
#======================================================================================================================
#
#          FILE: pulse.sh
#
#   DESCRIPTION: Installation and runtime for sending pulses aka heartbeatto a monitoring api
#                suitable for various Linux systems/distributions
#
#          BUGS: https://github.com/cloudradar-monitoring/omc/issues
#
#     COPYRIGHT: (c) 2020 by the CloudRadar Team,
#
#       LICENSE: MIT
#  ORGANIZATION: cloudradar GmbH, Potsdam, Germany (cloudradar.io)
#       CREATED: 02/05/2021
#======================================================================================================================

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  abort
#   DESCRIPTION:  Exit the script with an error message.
#----------------------------------------------------------------------------------------------------------------------
abort() {
    >&1 echo "$1 Exit!"
    exit 1
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  confirm
#   DESCRIPTION:  Print a success message.
#----------------------------------------------------------------------------------------------------------------------
confirm() {
    echo "Success: $1"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  warn
#   DESCRIPTION:  Print a warning message.
#----------------------------------------------------------------------------------------------------------------------
warn() {
    echo "Warning: $1"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  is_available
#   DESCRIPTION:  Check if a command is available on the system.
#    PARAMETERS:  command name
#       RETURNS:  0 if available, 1 otherwise
#----------------------------------------------------------------------------------------------------------------------
is_available() {
    if which $1 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  set_location
#   DESCRIPTION:  Retrieve the Country and the city of the currently used public IP address
#----------------------------------------------------------------------------------------------------------------------
set_location() {
    LOCATION=$(curl -f -m2 -Ss "http://ip-api.com/line/?fields=country,city" | tr '\n' '/' | sed 's/.$//')
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  require_root
#   DESCRIPTION:  Abort the script execution if no root rights given
#----------------------------------------------------------------------------------------------------------------------
require_root() {
    if [ $(id -u) -ne 0 ]; then
        abort "Execute as root or use sudo."
    fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  install
#   DESCRIPTION:  Perform all needed steps to install this script as a systemd service
#----------------------------------------------------------------------------------------------------------------------
install() {
    if is_available systemd-run; then
        true
    else
        echo "Look at https:// for manual installation on almost any operating system."
        abort "Sorry. This installer supports only distributions based on systemd."
    fi
    require_root
    echo "Installing Pulse as a daemon"
    require_var OMC_TOKEN
    require_var PULSE_URL
    require_var HOSTNAME
    validate_token
    validate_url
    set_location
    set_linux_version
    set_description
    if cp -f $0 $DESTINATION 2>/dev/null; then
        confirm "Installed to ${DESTINATION}"
    else
        abort "Failed to install to ${DESTINATION}"
    fi
    create_env_file
    create_service_file
    systemctl start pulse
    systemctl enable pulse
    finish
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_env_file
#   DESCRIPTION:  Create an env file with all settings that will be sourced by systemd
#----------------------------------------------------------------------------------------------------------------------
create_env_file() {
    if [ -e ${ENV_FILE} ] && [ $FORCE -eq 0 ]; then
        warn "File ${ENV_FILE} exists. Skipping. Use -f to force overwriting."
        return 0
    fi
    echo "# ${ENV_FILE}
# This file contains a bunch of variables for ${DESTINATION}
# and ${SERVICE_FILE}
# Feel free to edit to your needs.
# The pulse.sh script runs as service. Restart the 'pulse' service to activate changes.
#
# Thanks for using freeping.io
PULSE_URL=${PULSE_URL}
OMC_TOKEN=${OMC_TOKEN}
HOSTNAME=${HOSTNAME}
DESCRIPTION=\"${DESCRIPTION}\"
LOCATION=\"${LOCATION}\"" >${ENV_FILE}
    confirm "File ${ENV_FILE} created."
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  create_service_file
#   DESCRIPTION:  Create an systemd service file that runs this script as a daemon
#----------------------------------------------------------------------------------------------------------------------
create_service_file() {
    echo "[Unit]
Description=Runs and keeps alive the Freeping.io Pulse

[Service]
User=daemon
Group=daemon
Restart=always
WorkingDirectory=/tmp
EnvironmentFile=${ENV_FILE}
ExecStart=${DESTINATION} -d

[Install]
WantedBy=multi-user.target" >${SERVICE_FILE}
    systemctl daemon-reload
    confirm "Systemd service created in ${SERVICE_FILE}"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  require_var
#   DESCRIPTION:  Check if variable is set
#    PARAMETERS:  variable name
#       RETURNS:  NULL|abort(), aborts the entire script execution if the variable is not set
#----------------------------------------------------------------------------------------------------------------------
require_var() {
    (eval test -z \$$1) && abort "Variable $1 is required."
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  validate_token
#   DESCRIPTION:  Check if the token has the expected length of 21 bytes
#----------------------------------------------------------------------------------------------------------------------
validate_token() {
    if [ $(echo -n $OMC_TOKEN | wc -c) -ne 21 ]; then
        abort "Invalid token. OMC_TOKEN must have exactly 21 characters."
    fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  set_linux_version
#   DESCRIPTION:  Set the LINUX_VERSION variable trying to add some basic information about the running OS
#----------------------------------------------------------------------------------------------------------------------
set_linux_version() {
    if is_available lsb_release; then
        LINUX_VERSION=$(lsb_release -d -s)
    elif [ -e /etc/redhat-release ]; then
        LINUX_VERSION=$(cat /etc/redhat-release|sed s/"Linux release "/""/g)
    else
        LINUX_VERSION="Linux "$(uname -r)
    fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  set_description
#   DESCRIPTION:  Set the DESCRIPTION variable trying to add some basic information about the hardware/VM
#----------------------------------------------------------------------------------------------------------------------
set_description() {
    CPU_MODEL=$(cat /proc/cpuinfo | grep "model name" | sort -u | cut -d':' -f2)
    CPU_NUM=$(cat /proc/cpuinfo | grep -c processor)
    if is_available dmidecode; then
        DESCRIPTION=${LINUX_VERSION}" on "$(sudo dmidecode -t 1 | egrep "(Manufacturer|Product Name)" | cut -d':' -f2 | tr -d '\n')
    else
        DESCRIPTION=${LINUX_VERSION}
    fi
    DESCRIPTION=${DESCRIPTION}" ${CPU_NUM} CPU(s) of ${CPU_MODEL}"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  validate_url
#   DESCRIPTION:  Check if the PULSE URL is valid
#----------------------------------------------------------------------------------------------------------------------
validate_url() {
    if echo ${PULSE_URL} | grep -q -e "^http[s,]*:\/\/"; then
        true
    else
        abort "Invalid PULSE_URL ${PULSE_URL}. Use scheme http(s)://my.example.com"
    fi
    if curl -fsSI -m3 ${PULSE_URL} >/dev/null 2>&1; then
        confirm "PULSE_URL is valid"
    else
        abort "Invalid PULSE_URL"
    fi
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  help
#   DESCRIPTION:  Print a help message
#----------------------------------------------------------------------------------------------------------------------
help() {
    cat <<EOL
This script installs and runs the freeping.io Pulse.

Supported arguments:
    -h  Show this help message
    -i  Install the Pulse.sh script to /usr/local/bin/pulse.sh
        and create a Systemd service so it runs continuously in the background.
        -u <PULSE_URL> and -t <OMC_TOKEN> are mandatory to install the service.
    -s  Send a single pulse and exit.
        -u <PULSE_URL> and -t <OMC_TOKEN> are optional. An existing environment is used otherwise.
    -r  Uninstall the systemd service file, the configuration and the script itself.
    -d  Daemonize. Executes -s in an endless loop. Command remains in the foreground.
    -u  <PULSE_URL> of the monitoring API the pulse is send to.
    -t  <OMC_TOKEN> to authenticate the request.

Example:
    ./pulse.sh -i -u https://pulse.freeping.io -t Tp_UDKR6nLhEfAR_k01QI
EOL
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  finish
#   DESCRIPTION:  print some information
#----------------------------------------------------------------------------------------------------------------------
finish() {
    echo "
#
#  Installation of Freeping Pulse finished.
#
#  You are now sending pulses to ${PULSE_URL}
#
#  Look at ${ENV_FILE}. Maybe you want to optimize it.
#
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#  Give us a star on https://github.com/cloudradar-monitoring/omc
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#
#

Thanks for using

8888888b.           888
888   Y88b          888
888    888          888
888   d88P 888  888 888 .d8888b   .d88b.
8888888P\"  888  888 888 88K      d8P  Y8b
888        888  888 888 \"Y8888b. 88888888
888        Y88b 888 888      X88 Y8b.
888         \"Y88888 888  88888P'  \"Y8888

"
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  send_pulse
#   DESCRIPTION:  Send a pulse
#----------------------------------------------------------------------------------------------------------------------
send_pulse() {
    for i in $(seq 1 3); do
        response=$(curl -sSf -X POST ${PULSE_URL} \
            --header "omc_token: ${OMC_TOKEN}" \
            -m 2 \
            -A "${USERAGENT}" \
            -F "hostname=${HOSTNAME}" \
            -F "location=${LOCATION}" \
            -F "description=${DESCRIPTION}" 2>&1) && break
        >&1 echo "Error ${response} on sending pulse to ${PULSE_URL}"
        sleep 2
    done
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  send
#   DESCRIPTION:  Send a pulse and exit
#----------------------------------------------------------------------------------------------------------------------
send() {
    . ${ENV_FILE}
    set_linux_version
    USERAGENT="pulse.sh/"${LINUX_VERSION}
    require_var OMC_TOKEN
    require_var PULSE_URL
    send_pulse
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  daemonize
#   DESCRIPTION:  Send pulse continuously
#----------------------------------------------------------------------------------------------------------------------
daemonize() {
    . ${ENV_FILE}
    require_var OMC_TOKEN
    require_var PULSE_URL
    set_linux_version
    USERAGENT="pulse.sh/"${LINUX_VERSION}
    while true; do
        send_pulse
        # Do not set the sleep below 30 seconds.
        # The API uses strict rate limiting. You run the risk to get blocked when sending to fast.
        sleep 30
    done
}

#---  FUNCTION  -------------------------------------------------------------------------------------------------------
#          NAME:  uninstall
#   DESCRIPTION:  Remove everything without a trace
#----------------------------------------------------------------------------------------------------------------------
uninstall() {
    echo "** Uninstalling Freeping Pulse **"
    systemctl stop pulse
    rm -f ${ENV_FILE}&&confirm "${ENV_FILE} removed"
    rm -f ${SERVICE_FILE}&&confirm "${SERVICE_FILE} removed"
    rm -f ${DESTINATION}&&confirm "${DESTINATION} removed"
}

#----------------------------------------------------------------------------------------------------------------------
#                                               END OF FUNCTION DECLARATION
#----------------------------------------------------------------------------------------------------------------------

#
# Check for prerequisites
#
if which sed 2>&1 >/dev/null; then
    true
else
    abort "sed missing. Make sure sed is in your path."
fi

#
# Set some basic variables
#
ENV_FILE=/etc/default/pulse
DESTINATION=/usr/local/bin/pulse.sh
SERVICE_FILE=/etc/systemd/system/pulse.service
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
ACTION=send
FORCE=0

#
# Read the command line options and map to a function call
#
while getopts 'hfirdt:u:x' opt; do
    case "${opt}" in

    h) ACTION=help ;;
    f) FORCE=1 ;;
    i) ACTION=install ;;
    r) ACTION=uninstall ;;
    d) ACTION=daemonize ;;
    t) OMC_TOKEN=${OPTARG} ;;
    u) PULSE_URL=${OPTARG} ;;
    # Execute a single function. For dev and debug only  #
    x) ACTION=$2 ;;

    \?)
        help
        exit 1
        ;;
    esac # --- end of case ---
done
shift $((OPTIND - 1))
$ACTION # Execute the function according to the users decision
