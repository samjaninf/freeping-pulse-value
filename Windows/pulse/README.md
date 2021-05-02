# Pulse for Windows
The script `pulse.ps1` sends a pulse aka heartbeat to an HTTP API – usually https://pulse.freeping.io – providing a reverse ping monitoring for systems behind firewalls.

Pulse runs in the background controlled by [nssm](https://nssm.cc/) sending the pulse every 30 seconds.

Pulse is configured by a simple configuration file located at `C:\Program Files\FreepingPulse\pulse.cfg`. 

Advantages of pulse.ps1:
* Faster sending than using a scheduled task.
* Fast and clean installation.
* `pulse.cfg` is preseeded with your location and your OS environment.
* The user-agent header is set to a meaningful value.
* Controllable via Windows service and the usual `sc` command.

## Installation
Download to some location, open an administrative Powershell console.
```
./pulse.ps1 -Install -PulseUrl https://pulse.freeping.io -Token <TRANSMITTER_TOKEN> && del ./pulse.ps1
```

The script copies itself to `C:\Program Files\FreepingPulse\pulse.ps1`.

*That's not the whole truth. The script resides in `"%PROGRAMFILES%"\FreepingPulse\`. None-default Program Files folders are supported. ;-)*


You might want to change the pre-generated values in `C:\Program Files\FreepingPulse\pulse.cfg`. 
```
# Pulse.ps1 configuration file
# This is an auto-generated configuration.
# Feel free to edit to your needs.
# CAUTION: Do not put values into single or double quotes!
# The pulse.ps1 script runs as service. Restart the 'Pulse' service to activate changes.
# 
# Thanks for using freeping.io
pulse_url = https://pulse.freeping.io
transmitter_token = *******************
hostname =  WIN-T678R1TUUQD
description = Microsoft Windows Server 2019 Standard
location = Germany/Cologne
```

## Removal
To stop using pulse and cleanly uninstall it execute `C:\Program Files\FreepingPulse\uninstall.bat`. 