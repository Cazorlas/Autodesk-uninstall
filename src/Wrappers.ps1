function Get-AdskRegistryRows {
    $roots = @(
        @{ Hive = 'HKLM'; View = '64'; RegistryHive = 'LocalMachine'; RegistryView = 'Registry64' }
        @{ Hive = 'HKLM'; View = '32'; RegistryHive = 'LocalMachine'; RegistryView = 'Registry32' }
        @{ Hive = 'HKCU'; View = '64'; RegistryHive = 'CurrentUser'; RegistryView = 'Registry64' }
    )
    $fields = @('DisplayName', 'DisplayVersion', 'Publisher', 'UninstallString',
        'QuietUninstallString', 'SystemComponent', 'WindowsInstaller', 'InstallLocation', 'ParentKeyName')
    foreach ($root in $roots) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($root.RegistryHive, $root.RegistryView)
        try {
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', $false)
            if ($null -eq $uninstall) { continue }
            try {
                foreach ($name in $uninstall.GetSubKeyNames()) {
                    $key = $uninstall.OpenSubKey($name, $false)
                    if ($null -eq $key) { continue }
                    try {
                        $row = [ordered]@{ Hive = $root.Hive; View = $root.View; KeyName = $name }
                        foreach ($field in $fields) { $row[$field] = $key.GetValue($field) }
                        if ($row.Publisher -match 'Autodesk' -or
                            $row.DisplayName -match 'Autodesk|Revit|AutoCAD|Navisworks|Desktop Connector|Civil 3D|Inventor|3ds Max|Maya') {
                            [pscustomobject]$row
                        }
                    } finally { $key.Dispose() }
                }
            } finally { $uninstall.Dispose() }
        } finally { $base.Dispose() }
    }
}

function Invoke-AdskProcess {
    # Runs one uninstaller and waits. Returns @{ ExitCode = <int or $null>; TimedOut = <bool> }.
    # On timeout the process is left running (killing an installer mid-transaction breaks MSI state).
    param([Parameter(Mandatory = $true)][string]$FilePath, [string]$Arguments, [int]$TimeoutSeconds = 3600)
    $options = @{ FilePath = $FilePath; PassThru = $true; ErrorAction = 'Stop'; WindowStyle = 'Hidden' }
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $options.ArgumentList = $Arguments }
    $process = Start-Process @options
    $null = $process.Handle   # keeps the handle so ExitCode is readable after exit
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        return [pscustomobject]@{ ExitCode = $null; TimedOut = $true }
    }
    $process.WaitForExit()
    [pscustomobject]@{ ExitCode = $process.ExitCode; TimedOut = $false }
}

function Test-AdskPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    Test-Path -LiteralPath $Path
}

function Move-AdskItem {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Destination)
    Move-Item -LiteralPath $Path -Destination $Destination -ErrorAction Stop
}

function Export-AdskRegistryKey {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Destination)
    & reg.exe export $Path $Destination /y
    if ($LASTEXITCODE -ne 0) { throw "Registry export failed (exit $LASTEXITCODE): $Path" }
}

function Remove-AdskRegistryKey {
    param([Parameter(Mandatory = $true)][string]$Path)
    Remove-Item -LiteralPath $Path -Recurse -ErrorAction Stop
}

function Get-AdskService {
    Get-CimInstance -ClassName Win32_Service
}

function Get-AdskProcessByPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $prefix = $Path.TrimEnd('\') + '\'
    Get-Process | Where-Object {
        $_.Path -and $_.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Stop-AdskProcess {
    param([Parameter(Mandatory = $true)][int]$Id)
    Stop-Process -Id $Id -ErrorAction Stop
}

function Test-AdskMsiBusy {
    # Windows Installer holds Global\_MSIExecute only while an install/uninstall transaction runs.
    # Existence alone means busy; never acquire it (that would block msiexec).
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::OpenExisting('Global\_MSIExecute')
        return $true
    } catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $false
    } catch [System.UnauthorizedAccessException] {
        return $true
    } finally {
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}
