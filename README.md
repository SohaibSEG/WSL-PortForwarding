# WSL-PortForwarding
a powershell script to set port forwarding to wsl2 and automatically add firewall rules

# Usage:
In an elevated powershell window
## Enable script execution
```powershell
set-executionpolicy remotesigned
```
## Add port forwarrding rule
```powershell
.\WSL-PortForwarding.ps1 -DistroName "YourWslDistro" -LocalPort 8080 -WslPort 80
```
## Remove port forwarrding rule
```powershell
.\WSL-PortForwarding.ps1 -DistroName "YourWslDistro" -LocalPort 8080 -WslPort 80 -Purge
```
