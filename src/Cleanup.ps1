# --- side-effect wrappers (T3) ---
function New-AdskDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
}

function Remove-AdskRegistryValue {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Name)
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
}
# --- end side-effect wrappers (T3) ---

function Get-AdskRemnantCatalog {
    param([string[]]$Group = @('Revit', 'AutoCAD', 'Navisworks', 'DesktopConnector'),
        [int[]]$Year = @(2010..2099), [switch]$InfrastructureRemoved, [object[]]$Packages = @())
    $templates = @(
        @('Revit', '%ProgramFiles%\Autodesk\Revit {Y}', $false),
        @('Revit', '%ProgramData%\Autodesk\RVT {Y}', $false),
        @('Revit', '%ProgramData%\Autodesk\Revit\Addins\{Y}', $true),
        @('Revit', '%ProgramFiles%\Autodesk\Revit Interoperability {Y}', $false),
        @('Revit', '%ProgramData%\Autodesk\Revit Interoperability {Y}', $false),
        @('Revit', '%ProgramData%\Autodesk\Revit Server {Y}', $false),
        @('Revit', '%ProgramData%\Autodesk\Revit Steel Connections {Y}', $false),
        @('Revit', '%APPDATA%\Autodesk\Revit\Autodesk Revit {Y}', $true),
        @('Revit', '%APPDATA%\Autodesk\Revit\Addins\{Y}', $true),
        @('Revit', '%LOCALAPPDATA%\Autodesk\Revit\Autodesk Revit {Y}', $true),
        @('Revit', 'HKCU:\Software\Autodesk\Revit\Autodesk Revit {Y}', $true),
        @('AutoCAD', '%ProgramFiles%\Autodesk\AutoCAD {Y}', $false),
        @('AutoCAD', '%APPDATA%\Autodesk\AutoCAD {Y}', $true),
        @('AutoCAD', '%LOCALAPPDATA%\Autodesk\AutoCAD {Y}', $true),
        @('AutoCAD', '%ProgramData%\Autodesk\AutoCAD {Y}', $false),
        @('Navisworks', '%ProgramFiles%\Autodesk\Navisworks Manage {Y}', $false),
        @('Navisworks', '%ProgramFiles%\Autodesk\Navisworks Simulate {Y}', $false),
        @('Navisworks', '%ProgramFiles%\Autodesk\Navisworks Freedom {Y}', $false),
        @('Navisworks', '%ProgramFiles%\Autodesk\Navisworks Exporters {Y}', $false),
        @('Navisworks', '%APPDATA%\Autodesk Navisworks Manage {Y}', $true),
        @('Navisworks', '%ProgramData%\Autodesk\Navisworks Manage {Y}', $false),
        @('DesktopConnector', '%ProgramFiles%\Autodesk\Desktop Connector', $false),
        @('DesktopConnector', '%LOCALAPPDATA%\Autodesk\Desktop Connector', $true)
    )
    foreach ($template in $templates) {
        if ($Group -notcontains $template[0]) { continue }
        $years = @($null)
        if ($template[1].Contains('{Y}')) { $years = $Year }
        foreach ($y in $years) {
            if ($null -ne $y -and ($y -lt 2010 -or $y -gt 2099)) { throw 'Invalid product year.' }
            [pscustomobject]@{ Path = [Environment]::ExpandEnvironmentVariables($template[1].Replace('{Y}', [string]$y))
                Kind = $(if ($template[1] -like 'HKCU:*') { 'RegistryKey' } else { 'Folder' })
                Group = $template[0]; Year = $y; UserData = $template[2]; Reason = 'Product fully uninstalled' }
        }
    }
    if ($InfrastructureRemoved -and @($Packages).Count -eq 0) {
        foreach ($path in @('%ProgramFiles%\Autodesk\AdODIS', '%ProgramData%\Autodesk\ODIS',
            '%ProgramFiles(x86)%\Common Files\Autodesk Shared\AdskLicensing',
            '%ProgramData%\Autodesk\AdskLicensingService', '%ProgramFiles(x86)%\Autodesk\Genuine Service',
            '%ProgramFiles%\Autodesk\AdskIdentityManager', '%ProgramFiles%\Autodesk\Autodesk Access')) {
            [pscustomobject]@{ Path = [Environment]::ExpandEnvironmentVariables($path); Kind = 'Folder'
                Group = 'Infrastructure'; Year = $null; UserData = $false; Reason = 'No Autodesk package remains' }
        }
    }
}

function Assert-AdskRemnantPath {
    param([string]$Path)
    if ($Path -match '^HKCU:\\Software\\Autodesk\\Revit\\Autodesk Revit 20\d\d$') { return }
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[%*?]' -or $Path -match '(?:^|\\)\.\.(?:\\|$)') {
        throw "Unsafe remnant path: $Path"
    }
    $normalized = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $roots = @('%ProgramFiles%\Autodesk', '%ProgramFiles(x86)%\Autodesk',
        '%ProgramFiles%\Common Files\Autodesk Shared', '%ProgramFiles(x86)%\Common Files\Autodesk Shared',
        '%ProgramData%\Autodesk', '%APPDATA%\Autodesk', '%LOCALAPPDATA%\Autodesk', '%USERPROFILE%')
    if ($normalized -match '^[A-Za-z]:$') { throw "Unsafe remnant root: $Path" }
    foreach ($root in $roots) {
        $expanded = [Environment]::ExpandEnvironmentVariables($root).TrimEnd('\')
        if ($normalized -eq $expanded) { throw "Unsafe remnant root: $Path" }
    }
    foreach ($workspace in @('DC', 'ACCDocs')) {
        $protected = "$env:USERPROFILE\$workspace"
        if ($normalized -eq $protected -or $normalized.StartsWith($protected + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Protected workspace: $Path"
        }
    }
}

function Get-AdskRemnant {
    param([AllowEmptyCollection()][object[]]$Packages = @(), [AllowEmptyCollection()][object[]]$Removed = @(),
        [switch]$IncludeUserData, [switch]$InfrastructureRemoved)
    $catalog = @(Get-AdskRemnantCatalog -InfrastructureRemoved:$InfrastructureRemoved -Packages $Packages)
    foreach ($item in $catalog) {
        Assert-AdskRemnantPath $item.Path
        if ($item.Group -eq 'Infrastructure') {
            if (-not $InfrastructureRemoved -or @($Packages).Count -gt 0) { continue }
        } else {
            if (-not @($Removed | Where-Object { $_.Group -eq $item.Group -and $_.Year -eq $item.Year }).Count) { continue }
            if (@($Packages | Where-Object { $_.Group -eq $item.Group -and $_.Year -eq $item.Year }).Count) { continue }
        }
        if ($item.UserData -and -not $IncludeUserData) { continue }
        $inUse = $false
        foreach ($package in $Packages) {
            if ([string]::IsNullOrWhiteSpace($package.InstallLocation)) { continue }
            $installed = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($package.InstallLocation)).TrimEnd('\')
            $candidate = $item.Path.TrimEnd('\')
            if ($installed -eq $candidate -or $installed.StartsWith($candidate + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $candidate.StartsWith($installed + '\', [StringComparison]::OrdinalIgnoreCase)) { $inUse = $true; break }
        }
        if (-not $inUse -and (Test-AdskPath -Path $item.Path)) { $item }
    }
}

function Get-AdskQuarantineDestination {
    param([string]$Path, [string]$RunId, [string]$QuarantineRoot)
    if ($RunId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid quarantine RunId.' }
    $registry = $Path -match '^HK(?:CU|LM):?\\'
    $drive = if ($registry) { [IO.Path]::GetPathRoot($env:ProgramData) } else { [IO.Path]::GetPathRoot($Path) }
    if ($drive -notmatch '^[A-Za-z]:\\$') { throw 'Quarantine requires a local drive.' }
    $root = $drive + 'AutodeskCleaner.Quarantine'
    if ($QuarantineRoot) {
        $root = [IO.Path]::GetFullPath($QuarantineRoot).TrimEnd('\')
        if ([IO.Path]::GetPathRoot($root) -ne $drive -or $root -eq $drive.TrimEnd('\')) { throw 'Quarantine must be on the same drive, below its root.' }
    }
    $relative = if ($registry) { 'Registry\' + ($Path -replace ':', '') + '.reg' } else { $Path.Substring(3) }
    $destination = "$root\$RunId\$relative"
    if ($destination.StartsWith($Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Quarantine cannot be inside the source.' }
    $destination
}

function Invoke-AdskRemnantCleanup {
    param([AllowEmptyCollection()][object[]]$Remnant = @(), [Parameter(Mandatory = $true)][string]$RunId,
        [switch]$DryRun, [string]$QuarantineRoot)
    foreach ($item in $Remnant) {
        $destination = $null
        $action = 'Failed'
        $errorText = $null
        try {
            Assert-AdskRemnantPath $item.Path
            # Only catalog entries can enter the write path; never accept arbitrary registry keys or roots.
            $allowed = @(Get-AdskRemnantCatalog -InfrastructureRemoved)
            if (-not @($allowed | Where-Object { $_.Path -eq $item.Path -and $_.Kind -eq $item.Kind }).Count) { throw 'Path is not a catalog remnant.' }
            $destination = Get-AdskQuarantineDestination -Path $item.Path -RunId $RunId -QuarantineRoot $QuarantineRoot
            if ($DryRun) { $action = 'DryRun' }
            else {
                if (Test-AdskPath -Path $destination) { throw 'Quarantine destination already exists.' }
                $null = New-AdskDirectory -Path ([IO.Path]::GetDirectoryName($destination))
                if ($item.Kind -eq 'RegistryKey') {
                    $null = Export-AdskRegistryKey -Path ($item.Path -replace ':', '') -Destination $destination
                    Remove-AdskRegistryKey -Path $item.Path
                    $action = 'Exported+Deleted'
                } else {
                    Move-AdskItem -Path $item.Path -Destination $destination
                    $action = 'Moved'
                }
            }
        } catch { $errorText = $_.Exception.Message }
        [pscustomobject]@{ Path = $item.Path; Action = $action; Destination = $destination; Error = $errorText }
    }
}
