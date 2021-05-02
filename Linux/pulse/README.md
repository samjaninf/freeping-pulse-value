# Pulse for Linux
The script `pulse.sh` sends a pulse aka heartbeat to an HTTP API – usually https://pulse.freeping.io – providing a reverse ping monitoring for systems behind firewalls.

Pulse runs in the background controlled by Systemd sending the pulse every 30 seconds.

Pulse is configured by a simple environment file located at `/etc/default/pulse`. 

Advantages of pulse.sh:
* Faster sending than using cron.
* Fast and clean installation.
* Errors are logged to the systemd journal.
* `/etc/default/pulse` is preseeded with your location and your OS environment.
* The user-agent header is set to a meaningful value.
* Controllable via the usual `systemctl` or `service` commands.
* It's not running as root.

## Installation
Download to some location and execute
```
sudo ./pulse.sh -i -u https://pulse.freeping.io -t <TRANSMITTER_TOKEN> && rm ./pulse.sh
```

The script copies itself to `/usr/local/bin`.

> Only the installation requires root privileges to create the systemd service file. Pulse runs with the unprivileged user "daemon".

You might want to change the pre-generated values in `/etc/default/pulse`. 
```
# /etc/default/pulse
# This file contains a bunch of variables for /usr/local/bin/pulse.sh
# and /etc/systemd/system/pulse.service
# Feel free to edit to your needs.
# The pulse.sh script runs as service. Restart the 'pulse' service to activate changes.
#
# Thanks for using freeping.io
PULSE_URL=https://pulse.freeping.io
TRANSMITTER_TOKEN=*********************
HOSTNAME=centos7.testlab.local
DESCRIPTION="Linux host on  VMware, Inc. VMware Virtual Platform 1 CPU(s) of  Intel(R) Core(TM) i9-8950HK CPU @ 2.90GHz"
LOCATION="Germany/Cologne"
```

Use `pulse.sh -h` to see all options.

## Removal
To stop using pulse and cleanly uninstall it execute `/usr/local/bin/pulse -r`. 