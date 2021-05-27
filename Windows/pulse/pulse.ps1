#======================================================================================================================
#
#          FILE: pulse.ps1
#
#   DESCRIPTION: A script that sends pulses aka heartbeats to a monitoring API
#
#          BUGS: https://github.com/cloudradar-monitoring/omc/issues
#
#     COPYRIGHT: (c) 2021 by the CloudRadar Team,
#
#       LICENSE: MIT
#  ORGANIZATION: cloudradar GmbH, Potsdam, Germany (cloudradar.io)
#       CREATED: 01/05/2021
#======================================================================================================================
#Requires -RunAsAdministrator
# Catch the paramters passed on the command line to tis script
param (
    [switch]$Install = $false,
    [switch]$Force = $false,
    [switch]$Daemonize = $false,
    [string]$PulseUrl = "",
    [string]$Token = ""
)
$Location = Get-Location
$InstallDir = "$( $Env:Programfiles )\FreepingPulse"
function Send-Pulse {
    <#
    .SYNOPSIS
        Send a pulse request to the monitoring system to indicate this host is alive
     #>
    param(
        [string]$c = "./pulse.cfg"
    )
    $config = Read-Config -path $c
    $request = @{
        Uri = $config.pulse_url
        UserAgent = "pulse.ps1/$( [environment]::OSVersion.VersionString )"
        ContentType = "application/json; charset=utf-8"
        Method = "post"
        Body = @{
            "hostname" = $config.hostname
            "location" = $config.location
            "description" = $config.description
        }|ConvertTo-Json
        Headers = @{
            "omc-token" = $config.omc_token
        }
        TimeoutSec = 2
    }

    # Send the pulse, retry twice on failures
    for($i = 1; $i -le 3; $i++) {
        try {
            $response = Invoke-WebRequest @request
            if (($response.StatusCode -gt 199) -and ($response.StatusCode -lt 300)) {
                return $true
                break
            }
            else {
                Write-Host $response
            }
        }
        catch {
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
            Write-Host $_
            if (401 -eq $_.Exception.Response.StatusCode.value__) {
                Write-Host "Please check the omc token in your config."
                break
            }
            elseif(429 -eq $_.Exception.Response.StatusCode.value__) {
                Write-Host "You are sending too fast. Slow down your interval."
                break
            }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Register-As-Service {
    <#
    .SYNOPSIS
        Register this script as a service sending the pulse every 30 seconds.
    #>
    Write-Host "** Registering pulse.ps1 as a windows service"
    if ($false -eq ([environment]::OSVersion.VersionString).StartsWith("Microsoft Windows")) {
        Write-Error -Msg "Registering pulse.ps1 as a service is only supported on Microsoft Windows." -Exit
    }
    # Create the directory
    if (-not(Test-Path $InstallDir)) {
        mkdir $InstallDir| Out-Null
    }
    Copy-Item -Path ./pulse.ps1 -Destination $InstallDir -Force
    Move-Item -Path ./pulse.cfg -Destination $InstallDir -Force
    Set-Location $InstallDir
    $NssmDownloadUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $NssmSha1 = "BE7B3577C6E3A280E5106A9E9DB5B3775931CEFC"
    $file = "nssm-2.24.zip"
    Write-Host "** Downloading Service Manager $( $NssmDownloadUrl )"
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $NssmDownloadUrl -OutFile $file
    if ((Get-FileHash $file -Algorithm "SHA1").hash -ne $NssmSha1) {
        Write-Error -Msg "Integraty check of downloaded $( $file ) failed." -Exit
    }
    Expand-Archive -Path $file -DestinationPath .
    Copy-Item -Path ./nssm-2.24/win64/nssm.exe -Destination .
    Remove-Item nssm-2.24* -Recurse -Force
    Write-Host "** Service Manager downloaded successfully."
    $serviceName = 'Pulse'
    $arguments = '-ExecutionPolicy Bypass -NoProfile -File pulse.ps1 -Daemonize'
    & ./nssm install $serviceName powershell $arguments
    & ./nssm status $serviceName
    & ./nssm set $serviceName AppDirectory $InstallDir
    & ./nssm set $serviceName Description "Sends a pulse to https://freeping.io"
    & ./nssm set $serviceName DisplayName "Pulse by freeping.io"
    Write-Uninstaller
    Set-Location $Location
    & sc.exe failure Pulse reset=30 actions=restart/5000
    Start-Service $serviceName
    if("Running" -eq (Get-Service $serviceName).Status) {
        Finish
    }
    else {
        Write-Error -Msg "Installation failed" -Exit
    }
}

function Get-Host-Name {
    return [Environment]::MachineName
}

function Get-GeoLocation {
    <#
    .SYNOPSIS
        Retrieve the country and city of current external IP address.
    #>
    $geoUrl = "http://ip-api.com/json/?fields=country,city"
    try {
        $geoData = Invoke-RestMethod -Uri $geoUrl -TimeoutSec 2
        $GeoLocation = "{0}/{1}" -f $geoData.country, $geoData.city
    }
    catch {
        $GeoLocation = "Location not set"
    }
    return $GeoLocation
}

function Get-Description {
    <#
    .SYNOPSIS
        Generate a short discription of the host including some base information about the (virtual) hardware.
    #>
    $ComputerInfo = Get-Computerinfo -Property "Cs*"

    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4).IPAddress|Select-Object -first 1
    }
    catch {
        $ip = "Unknown IP Address"
    }
    return "{0}/{1},{2}/{3} CPU(s) of {4}/{5}" -f `
    (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue('ProductName'),`
    $ComputerInfo.CsManufacturer,`
    $ComputerInfo.CsModel,`
    $ComputerInfo.CsNumberOfProcessors,`
    $ComputerInfo.CsProcessors[0].name,`
    $ip
}

function Write-Error {
    <#
    .SYNOPSIS
        Write an error to the console. Optionally abort the script.
    #>
    param(
        [string]$msg = "",
        [switch]$Exit = $false
    )
    Write-Host "ERROR: $( $Msg )" -ForegroundColor red
    if ($exit) {
        Write-Host "Exit"
        exit 1
    }
}

function Write-Config {
    <#
    .SYNOPSIS
        Create a configuration file unless its missing
    #>
    if ($Token.length -eq 0) {
        Write-Error -msg "You must provide your tranmitter token using '-Token <TOKEN>' for the installation." -Exit
    }
    elseif($Token.length -ne 21) {
        Write-Error -Msg "The provided token is invalid." -Exit
    }
    if($PulseUrl.Length -eq 0) {
        Write-Error -Msg "You must provide the Pulse URL using '-PulseUrl <URL>'" -Exit
    }
    if($PulseUrl -notmatch '^http[s]{0,1}://') {
        Write-Error -Msg "Invalid Pulse URL. Use http(s)://sub.example.com" -Exit
    }
    $config = @(
    "# Pulse.ps1 configuration file",
    "# This is an auto-generated configuration.",
    "# Feel free to edit to your needs.",
    "# CAUTION: Do not put values into single or double quotes!",
    "# The pulse.ps1 script runs as service. Restart the 'Pulse' service to activate changes.",
    "# ",
    "# Thanks for using freeping.io",
    "pulse_url = $( $PulseUrl )",
    "omc_token = $( $Token )",
    "hostname =  $( Get-Host-Name )",
    "description = $( Get-Description )",
    "location = $( Get-GeoLocation )"
    )
    $config -join "`r`n"|Out-File -encoding utf8 ./pulse.cfg
}

function Read-Config {
    <#
    .SYNOPSIS
        Read the configuration from a file or exit with an error
     #>
    param(
        [Parameter(Mandatory)][string]$path
    )
    try {
        $config = ConvertFrom-StringData((Get-Content $path -ErrorAction Stop) -join "`n")
    }
    catch {
        Write-Host "An error occurred: Config missing"
        Write-Host $_
        exit 1
    }
    return $config
}

function Write-Uninstaller {
    <#
    .SYNOPSIS
       Store a simple script to remove the Pulse service and to cleanly uninstall the Pulse script.
     #>
    @(
    "echo off",
    "echo Removing Freeping Pulse now",
    "ping -n 5 127.0.0.1 > null",
    "sc stop Pulse",
    '"%PROGRAMFILES%"\FreepingPulse\nssm.exe remove Pulse confirm'
    "cd C:\",
    'rmdir /S /Q "%PROGRAMFILES%"\FreepingPulse\',
    "echo Freeping Pulse removed",
    "ping -n 2 127.0.0.1 > null"
    ) -join "`r`n"|Out-File uninstall.bat -Encoding utf8
}

function Finish {
    Write-Host "#
#
#  Installation of Freeping Pulse finished.
#
#  You are now sending pulses to $($PulseUrl)
#
#  Look at $($InstallDir)\.pulse.cfg and change to your needs.
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
8888888P`"  888  888 888 88K      d8P  Y8b
888        888  888 888 `"Y8888b. 88888888
888        Y88b 888 888      X88 Y8b.
888         `"Y88888 888  88888P'  `"Y8888

"
}

if ($Install) {
    Write-Config
    Register-As-Service
    exit 0
}
elseif($Daemonize) {
    while ($True) {
        Send-Pulse
        # Do not set the sleep time below 30 seconds.
        # The API implement strict rate limiting.
        # You run the risk of being blocked.
        Start-Sleep -Seconds 30
    }
}
Send-Pulse
