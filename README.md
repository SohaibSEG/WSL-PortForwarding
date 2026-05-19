# WSL-PortForwarding
a powershell script to set port forwarding to wsl2 and automatically add firewall rules

# Usage:
In an elevated powershell window
## Enable script execution
```powershell
set-executionpolicy remotesigned
```
Adding or removing port forwarding and firewall rules requires an elevated PowerShell window. Listing distros, distro addresses, and existing rules can be used without elevation.

## Interactive menu
Run the script without parameters to open the interactive menu. The menu can list installed WSL distros, show distro IPv4 addresses, add or remove forwarding rules, and show existing portproxy/firewall rules.
```powershell
.\WSL-PortForwarding.ps1
```
## Add port forwarding rule
The script discovers IPv4 addresses dynamically from the selected WSL distro. It does not require a specific interface name such as `eth0`.
```powershell
.\WSL-PortForwarding.ps1 -DistroName "YourWslDistro" -LocalPort 8080 -WslPort 80
```
You can also provide the target WSL IP address explicitly.
```powershell
.\WSL-PortForwarding.ps1 -DistroName "YourWslDistro" -WslIp 172.24.32.10 -LocalPort 8080 -WslPort 80
```
## Remove port forwarding rule
```powershell
.\WSL-PortForwarding.ps1 -DistroName "YourWslDistro" -LocalPort 8080 -WslPort 80 -Purge
```
## Show existing rules
```powershell
.\WSL-PortForwarding.ps1 -ShowRules
```
