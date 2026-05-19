param (
    [Parameter(Mandatory = $false)]
    [string]$DistroName,

    [Parameter(Mandatory = $false)]
    [int]$LocalPort,

    [Parameter(Mandatory = $false)]
    [int]$WslPort,

    [Parameter(Mandatory = $false)]
    [string]$WslIp,

    [Parameter(Mandatory = $false)]
    [switch]$Purge,

    [Parameter(Mandatory = $false)]
    [switch]$ShowRules
)

function Set-ErrorHandling {
    param (
        [string]$ErrorMessage
    )
    Write-Host $ErrorMessage -ForegroundColor Red
    exit 1
}

function Read-UserInput {
    param (
        [string]$Prompt
    )

    if ([Console]::IsInputRedirected) {
        Write-Host -NoNewline "${Prompt}: "
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) {
            return $null
        }

        return $line.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    param (
        [string]$Action
    )

    if (-not (Test-IsAdministrator)) {
        Set-ErrorHandling "$Action requires elevation. Re-run PowerShell as Administrator."
    }
}

function Get-WslDistros {
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new("wsl.exe", "--list --quiet")
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.UseShellExecute = $false

        $process = [System.Diagnostics.Process]::Start($startInfo)
        $memoryStream = [System.IO.MemoryStream]::new()
        $process.StandardOutput.BaseStream.CopyTo($memoryStream)
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            $errorText = $process.StandardError.ReadToEnd().Trim()
            Set-ErrorHandling "Failed to list WSL distros. $errorText"
        }

        $bytes = $memoryStream.ToArray()
        if ($bytes.Length -ge 2 -and $bytes[1] -eq 0) {
            $raw = [System.Text.Encoding]::Unicode.GetString($bytes)
        }
        else {
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
        }

        $distros = (($raw -replace [string][char]0, "") -split "\r?\n") | ForEach-Object {
            $_.Trim([char]0xFEFF).Trim()
        } | Where-Object { $_ }

        return @($distros)
    }
    catch {
        Set-ErrorHandling "An error occurred while listing WSL distros: $_"
    }
}

function Show-WslDistros {
    $distros = @(Get-WslDistros)

    if ($distros.Count -eq 0) {
        Write-Host "No WSL distros found." -ForegroundColor Yellow
        return
    }

    Write-Host "`nInstalled WSL distros:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $distros.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $distros[$i])
    }
}

function Select-WslDistro {
    $distros = @(Get-WslDistros)

    if ($distros.Count -eq 0) {
        Set-ErrorHandling "No WSL distros found. Install or register a distro first."
    }

    Show-WslDistros

    while ($true) {
        $selection = Read-UserInput "`nSelect a distro number"
        if ($null -eq $selection) {
            Set-ErrorHandling "No distro selection received."
        }

        $index = 0

        if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $distros.Count) {
            return $distros[$index - 1]
        }

        Write-Host "Enter a number between 1 and $($distros.Count)." -ForegroundColor Yellow
    }
}

function Read-Port {
    param (
        [string]$Prompt
    )

    while ($true) {
        $value = Read-UserInput $Prompt
        if ($null -eq $value) {
            Set-ErrorHandling "No port value received."
        }

        $port = 0

        if ([int]::TryParse($value, [ref]$port) -and $port -ge 1 -and $port -le 65535) {
            return $port
        }

        Write-Host "Enter a valid TCP port between 1 and 65535." -ForegroundColor Yellow
    }
}

function Get-WslIpAddresses {
    param (
        [string]$DistroName
    )

    try {
        $addressLines = wsl -d $DistroName -e sh -c "ip -o -4 addr show scope global 2>/dev/null || hostname -I"
        $addresses = @()

        foreach ($line in $addressLines) {
            $text = $line.Trim()
            if (-not $text) {
                continue
            }

            if ($text -match "^\d+:\s+(\S+)\s+inet\s+(\d+(\.\d+){3})/") {
                $addresses += [PSCustomObject]@{
                    Interface = $Matches[1]
                    Address = $Matches[2]
                }
                continue
            }

            foreach ($address in ($text -split "\s+")) {
                if ($address -match "^\d+(\.\d+){3}$") {
                    $addresses += [PSCustomObject]@{
                        Interface = "unknown"
                        Address = $address
                    }
                }
            }
        }

        $addresses = @($addresses | Sort-Object -Property @{ Expression = {
            if ($_.Interface -eq "lo") {
                2
            }
            elseif ($_.Interface -like "docker*" -or $_.Interface -like "br-*") {
                1
            }
            else {
                0
            }
        } }, Address -Unique)
        if ($addresses.Count -eq 0) {
            Set-ErrorHandling "Failed to retrieve WSL IPv4 addresses. Ensure '$DistroName' is running and has an IPv4 address."
        }

        return $addresses
    }
    catch {
        Set-ErrorHandling "An error occurred while trying to get WSL IPv4 addresses: $_"
    }
}

function Select-WslIpAddress {
    param (
        [string]$DistroName
    )

    $addresses = @(Get-WslIpAddresses -DistroName $DistroName)

    if ($addresses.Count -eq 1) {
        Write-Host "`nUsing WSL IPv4 address $($addresses[0].Address) ($($addresses[0].Interface))." -ForegroundColor Cyan
        return $addresses[0].Address
    }

    Write-Host "`nAvailable IPv4 addresses for '$DistroName':" -ForegroundColor Cyan
    for ($i = 0; $i -lt $addresses.Count; $i++) {
        $hint = if ($i -eq 0) { " recommended" } else { "" }
        Write-Host ("  {0}. {1} ({2}){3}" -f ($i + 1), $addresses[$i].Address, $addresses[$i].Interface, $hint)
    }

    while ($true) {
        $selection = Read-UserInput "`nSelect an address number"
        if ($null -eq $selection) {
            Set-ErrorHandling "No address selection received."
        }

        $index = 0

        if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $addresses.Count) {
            return $addresses[$index - 1].Address
        }

        Write-Host "Enter a number between 1 and $($addresses.Count)." -ForegroundColor Yellow
    }
}

function Add-PortForwardingRule {
    param (
        [string]$WslIp,
        [int]$LocalPort,
        [int]$WslPort
    )

    try {
        $ruleExists = netsh interface portproxy show v4tov4 | Select-String -Pattern "^\s*0\.0\.0\.0\s+$LocalPort\s+"
        if ($ruleExists) {
            Write-Host "Port forwarding rule for port $LocalPort already exists. Skipping creation." -ForegroundColor Yellow
        }
        else {
            $output = netsh interface portproxy add v4tov4 listenport=$LocalPort listenaddress=0.0.0.0 connectport=$WslPort connectaddress=$WslIp 2>&1
            if ($LASTEXITCODE -ne 0) {
                Set-ErrorHandling "Failed to add port forwarding rule for port $LocalPort. $($output -join ' ')"
            }

            Write-Host "Port forwarding rule added: $LocalPort -> ${WslIp}:${WslPort}" -ForegroundColor Green
        }
    }
    catch {
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
        }
        else {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $LocalPort -Protocol TCP -Action Allow -ErrorAction Stop | Out-Null
            Write-Host "Firewall rule added for port $LocalPort." -ForegroundColor Green
        }
    }
    catch {
        Set-ErrorHandling "An error occurred while adding the firewall rule: $_"
    }
}

function Remove-PortForwardingRule {
    param (
        [int]$LocalPort
    )

    try {
        $ruleExists = netsh interface portproxy show v4tov4 | Select-String -Pattern "^\s*0\.0\.0\.0\s+$LocalPort\s+"
        if ($ruleExists) {
            $output = netsh interface portproxy delete v4tov4 listenport=$LocalPort listenaddress=0.0.0.0 2>&1
            if ($LASTEXITCODE -ne 0) {
                Set-ErrorHandling "Failed to remove port forwarding rule for port $LocalPort. $($output -join ' ')"
            }

            Write-Host "Port forwarding rule for port $LocalPort removed." -ForegroundColor Green
        }
        else {
            Write-Host "No port forwarding rule found for port $LocalPort." -ForegroundColor Yellow
        }
    }
    catch {
        Set-ErrorHandling "An error occurred while removing the port forwarding rule: $_"
    }
}

function Remove-FirewallRule {
    param (
        [int]$LocalPort
    )

    try {
        $ruleName = "WSL Port Forwarding $LocalPort"
        $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

        if ($ruleExists) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
            Write-Host "Firewall rule for port $LocalPort removed." -ForegroundColor Green
        }
        else {
            Write-Host "No firewall rule found for port $LocalPort." -ForegroundColor Yellow
        }
    }
    catch {
        Set-ErrorHandling "An error occurred while removing the firewall rule: $_"
    }
}

function Show-ExistingRules {
    Write-Host "`nPortproxy rules:" -ForegroundColor Cyan
    $portProxyRules = netsh interface portproxy show all
    if ($portProxyRules) {
        $portProxyRules | Out-Host
    }
    else {
        Write-Host "No portproxy rules found." -ForegroundColor Yellow
    }

    Write-Host "`nFirewall rules created by this script:" -ForegroundColor Cyan
    $firewallRules = Get-NetFirewallRule -DisplayName "WSL Port Forwarding *" -ErrorAction SilentlyContinue | ForEach-Object {
        $rule = $_
        $rule | Get-NetFirewallPortFilter | Select-Object @{Name = "Name"; Expression = { $rule.DisplayName } }, Protocol, LocalPort
    }

    if ($firewallRules) {
        $firewallRules | Format-Table -AutoSize | Out-Host
    }
    else {
        Write-Host "No matching firewall rules found." -ForegroundColor Yellow
    }
}

function Invoke-AddRule {
    param (
        [string]$DistroName,
        [int]$LocalPort,
        [int]$WslPort,
        [string]$WslIp
    )

    Assert-Administrator "Adding port forwarding and firewall rules"

    if (-not $DistroName) {
        $DistroName = Select-WslDistro
    }

    if (-not $WslIp) {
        $WslIp = Select-WslIpAddress -DistroName $DistroName
    }

    if (-not $LocalPort) {
        $LocalPort = Read-Port "Local Windows port"
    }

    if (-not $WslPort) {
        $WslPort = Read-Port "WSL port"
    }

    Add-PortForwardingRule -WslIp $WslIp -LocalPort $LocalPort -WslPort $WslPort
    Add-FirewallRule -LocalPort $LocalPort
}

function Invoke-RemoveRule {
    param (
        [int]$LocalPort
    )

    Assert-Administrator "Removing port forwarding and firewall rules"

    if (-not $LocalPort) {
        $LocalPort = Read-Port "Local Windows port to remove"
    }

    Remove-PortForwardingRule -LocalPort $LocalPort
    Remove-FirewallRule -LocalPort $LocalPort
}

function Start-InteractiveMenu {
    while ($true) {
        Write-Host "`nWSL Port Forwarding" -ForegroundColor Cyan
        Write-Host "  1. Add port forwarding rule"
        Write-Host "  2. Remove port forwarding rule"
        Write-Host "  3. Show installed WSL distros"
        Write-Host "  4. Show distro IPv4 addresses"
        Write-Host "  5. Show existing portproxy and firewall rules"
        Write-Host "  6. Exit"

        $choice = Read-UserInput "`nChoose an option"
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "1" { Invoke-AddRule }
            "2" { Invoke-RemoveRule }
            "3" { Show-WslDistros }
            "4" {
                $selectedDistro = Select-WslDistro
                $addresses = @(Get-WslIpAddresses -DistroName $selectedDistro)
                Write-Host "`nAvailable IPv4 addresses for '$selectedDistro':" -ForegroundColor Cyan
                for ($i = 0; $i -lt $addresses.Count; $i++) {
                    $hint = if ($i -eq 0) { " recommended" } else { "" }
                    Write-Host ("  {0}. {1} ({2}){3}" -f ($i + 1), $addresses[$i].Address, $addresses[$i].Interface, $hint)
                }
            }
            "5" { Show-ExistingRules }
            "6" { return }
            default { Write-Host "Choose a number from 1 to 6." -ForegroundColor Yellow }
        }
    }
}

if ($ShowRules) {
    Show-ExistingRules
    exit 0
}

if ($Purge) {
    Invoke-RemoveRule -LocalPort $LocalPort
}
elseif ($DistroName -or $LocalPort -or $WslPort -or $WslIp) {
    Invoke-AddRule -DistroName $DistroName -LocalPort $LocalPort -WslPort $WslPort -WslIp $WslIp
}
else {
    Start-InteractiveMenu
}
