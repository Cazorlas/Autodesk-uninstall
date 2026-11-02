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

function ConvertTo-AdskNormalizedPath {
    param([string]$Path)
    $normalized = [Environment]::ExpandEnvironmentVariables($Path.Trim()) -replace '\\+', '\'
    if ($normalized -match '^[A-Za-z]:\\') { $normalized = [IO.Path]::GetFullPath($normalized) }
    $normalized.TrimEnd('\')
}

function Test-AdskProtectedRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $normalized = ConvertTo-AdskNormalizedPath -Path $Path
    if ($normalized -match '^[A-Za-z]:$' -or
        $normalized -match '^[A-Za-z]:\\(?:Program Files(?: \(x86\))?|ProgramData|Users(?:\\[^\\]+(?:\\AppData\\(?:Roaming|Local))?)?)$' -or
        $normalized -match '(?:^|\\)(?:Autodesk|Autodesk Shared|Common Files)$') { return $true }
    if ($env:USERPROFILE -and $normalized -eq (ConvertTo-AdskNormalizedPath -Path $env:USERPROFILE)) { return $true }
    return $false
}

function Assert-AdskRemnantPath {
    param([string]$Path)
    if ($Path -match '^HKCU:\\Software\\Autodesk\\Revit\\Autodesk Revit 20\d\d$') { return }
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[%*?]' -or $Path -match '(?:^|\\)\.\.(?:\\|$)') {
        throw "Unsafe remnant path: $Path"
    }
    $normalized = ConvertTo-AdskNormalizedPath -Path $Path
    if (Test-AdskProtectedRoot -Path $normalized) { throw "Unsafe remnant root: $Path" }
    foreach ($workspace in @('DC', 'ACCDocs')) {
        $protected = "$env:USERPROFILE\$workspace"
        if ($normalized -eq $protected -or $normalized.StartsWith($protected + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Protected workspace: $Path"
        }
    }
}

function Get-AdskRemnant {
    param([AllowEmptyCollection()][object[]]$Packages = @(), [AllowEmptyCollection()][object[]]$Removed = @(),
        [switch]$IncludeUserData, [switch]$InfrastructureRemoved,
        [AllowEmptyCollection()][object[]]$RemovedPackages = @())
    $catalog = @(Get-AdskRemnantCatalog -InfrastructureRemoved:$InfrastructureRemoved -Packages $Packages)
    foreach ($package in $RemovedPackages) {
        if (-not @($Removed | Where-Object { $_.Group -eq $package.Group -and $_.Year -eq $package.Year }).Count) { continue }
        if (Test-AdskProtectedRoot -Path $package.InstallLocation) { continue }
        $catalog += [pscustomobject]@{ Path = (ConvertTo-AdskNormalizedPath -Path $package.InstallLocation)
            Kind = 'Folder'; Group = $package.Group; Year = $package.Year; UserData = $false
            Reason = 'install location of removed package' }
    }
    $seen = @{}
    foreach ($item in $catalog) {
        Assert-AdskRemnantPath $item.Path
        $item.Path = ConvertTo-AdskNormalizedPath -Path $item.Path
        if ($seen.ContainsKey($item.Path)) { continue }
        if ($item.Group -eq 'Infrastructure') {
            if (-not $InfrastructureRemoved -or @($Packages).Count -gt 0) { continue }
        } else {
            if (-not @($Removed | Where-Object { $_.Group -eq $item.Group -and $_.Year -eq $item.Year }).Count) { continue }
            if (@($Packages | Where-Object {
                $_.Group -eq $item.Group -and $_.Year -eq $item.Year -and -not $_.ThirdParty -and $_.Role -ne 'DevTool'
            }).Count) { continue }
        }
        if ($item.UserData -and -not $IncludeUserData) { continue }
        $inUse = $false
        foreach ($package in $Packages) {
            if (Test-AdskProtectedRoot -Path $package.InstallLocation) { continue }
            $installed = ConvertTo-AdskNormalizedPath -Path $package.InstallLocation
            $candidate = $item.Path.TrimEnd('\')
            if ($installed -eq $candidate -or $installed.StartsWith($candidate + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $candidate.StartsWith($installed + '\', [StringComparison]::OrdinalIgnoreCase)) { $inUse = $true; break }
        }
        if (-not $inUse -and (Test-AdskPath -Path $item.Path)) { $seen[$item.Path] = $true; $item }
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
            # Accept catalog entries and guarded install-location folders; registry keys still require the catalog.
            $allowed = @(Get-AdskRemnantCatalog -InfrastructureRemoved)
            if (-not @($allowed | Where-Object { (ConvertTo-AdskNormalizedPath -Path $_.Path) -eq (ConvertTo-AdskNormalizedPath -Path $item.Path) -and $_.Kind -eq $item.Kind }).Count -and
                -not ($item.Kind -eq 'Folder' -and $item.Reason -eq 'install location of removed package' -and
                    -not $item.UserData)) { throw 'Path is not a catalog remnant.' }
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
