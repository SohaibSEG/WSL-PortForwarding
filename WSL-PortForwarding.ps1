param (
    [Parameter(Mandatory = $true)]
    [string]$DistroName,

    [Parameter(Mandatory = $true)]
    [int]$LocalPort,

    [Parameter(Mandatory = $true)]
    [int]$WslPort
)

function Set-ErrorHandling {
    param (
        [string]$ErrorMessage
    )
    Write-Host $ErrorMessage -ForegroundColor Red
    exit 1
}

function Get-WslIp {
    try {
        $WslIp = wsl -d $DistroName -e sh -c "ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'"
        if (-not $WslIp) {
            Set-ErrorHandling "Failed to retrieve WSL IP address. Ensure WSL is running."
        }
        return $WslIp.Trim()
    } catch {
        Set-ErrorHandling "An error occurred while trying to get the WSL IP address: $_"
    }
}

function Add-PortForwardingRule {
    param (
        [string]$WslIp,
        [int]$LocalPort,
        [int]$WslPort
    )

    try {
        $ruleExists = netsh interface portproxy show all | Select-String -Pattern "$LocalPort"
        if ($ruleExists) {
            Write-Host "Port forwarding rule for port $LocalPort already exists. Skipping creation." -ForegroundColor Yellow
        } else {
            netsh interface portproxy add v4tov4 listenport=$LocalPort listenaddress=0.0.0.0 connectport=$WslPort connectaddress=$WslIp
            Write-Host "Port forwarding rule added: $LocalPort -> $WslIp:$WslPort" -ForegroundColor Green
        }
    } catch {
        Set-ErrorHandling "An error occurred while setting up port forwarding: $_"
    }
}

function Add-FirewallRule {
    param (
        [int]$LocalPort
    )

    try {
        $ruleName = "WSL Port Forwarding $LocalPort"
        $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

        if ($ruleExists) {
            Write-Host "Firewall rule for port $LocalPort already exists. Skipping creation." -ForegroundColor Yellow
        } else {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $LocalPort -Protocol TCP -Action Allow
            Write-Host "Firewall rule added for port $LocalPort." -ForegroundColor Green
        }
    } catch {
        Set-ErrorHandling "An error occurred while adding the firewall rule: $_"
    }
}

$WslIp = Get-WslIp
Add-PortForwardingRule -WslIp $WslIp -LocalPort $LocalPort -WslPort $WslPort
Add-FirewallRule -LocalPort $LocalPort
