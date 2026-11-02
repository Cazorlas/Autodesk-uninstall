function Split-AdskCommand {
    param([AllowNull()][AllowEmptyString()][string]$Command)
    $exe = $null
    $arguments = ''
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $commandText = $Command.Trim()
        if ($commandText -match '^"([^"]+)"\s*(.*)$' -or
            $commandText -match '^(.+?\.exe)(?=\s|$)\s*(.*)$' -or
            $commandText -match '^(\S+)\s*(.*)$') {
            $exe = $Matches[1]
            $arguments = $Matches[2]
        }
    }
    [pscustomobject]@{ Exe = $exe; Arguments = $arguments }
}

function ConvertTo-AdskPackage {
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)][psobject]$Row)
    process {
        $name = [string]$Row.DisplayName
        $command = $Row.UninstallString
        if (-not [string]::IsNullOrWhiteSpace($Row.QuietUninstallString)) { $command = $Row.QuietUninstallString }
        $split = Split-AdskCommand $command
        $guidPattern = '\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}'
        $productCode = $null
        $kind = 'None'
        if ($split.Exe) {
            $kind = 'Exe'
            if ($split.Exe -match '\\AdODIS\\V1\\Installer\.exe$') { $kind = 'ODIS' }
            elseif ($split.Exe -match '(^|\\)AdskUninstallHelper\.exe$') { $kind = 'Helper' }
            elseif ($split.Exe -match '(^|\\)msiexec(?:\.exe)?$') {
                if ($split.Arguments -match $guidPattern) { $productCode = $Matches[0] }
                elseif ($Row.KeyName -match "^$guidPattern`$") { $productCode = $Row.KeyName }
                if ($productCode) { $kind = 'MSI' }
            }
        }
        $year = $null
        if ($name -match '\b(20\d\d)\b' -and [int]$Matches[1] -ge 2010) { $year = [int]$Matches[1] }
        $group = 'Other'
        $groups = [ordered]@{
            DesktopConnector = 'Desktop Connector'
            Navisworks = 'Navisworks'
            Revit = 'Revit|RSA |REX |Results Explorer|Generative Design For Revit|Personal Accelerator'
            Civil3D = 'Civil 3D'
            AutoCAD = 'AutoCAD|ACAD|AutoCAD Open in Desktop'
            Inventor = 'Inventor'
            '3dsMax' = '3ds Max'
            Maya = 'Maya'
            Infrastructure = 'Licensing|Genuine Service|Autodesk Access|Single Sign On|Identity Manager|Desktop App|App Manager|ODIS|Autodesk Installer'
            Shared = 'Material Library|RealDWG|Interoperability Engine|CER|Featured Apps|Save to Web|Autodesk Shared'
        }
        foreach ($entry in $groups.GetEnumerator()) {
            if ($name -match $entry.Value) { $group = $entry.Key; break }
        }
        $role = 'Main'
        if ($name -match 'SDK$|\bSDK\b|RevitLookup|RevitAddinManager|pyRevit') { $role = 'DevTool' }
        elseif ($group -eq 'Infrastructure') { $role = 'Infrastructure' }
        elseif ($name -match 'Material Library') { $role = 'MaterialLibrary' }
        elseif ($group -eq 'Shared') { $role = 'Shared' }
        elseif ($name -match '\bUpdate\b') { $role = 'Update' }
        elseif ($name -match 'Language Pack|LanguagePack') { $role = 'LanguagePack' }
        elseif ($name -match 'Content|Colorbooks|Unit Schemas') { $role = 'Content' }
        elseif ($name -match 'Carbon Insights|Add-?Ins? Manager|Converter|VBA Enabler|eTransmit|Batch Print|Worksharing Monitor|Cloud Models|IFC Parameters|Product Feedback|Generative Design|Personal Accelerator|^RSA |^REX |Results Explorer|Open in Desktop|Exporters') { $role = 'Addon' }
        [pscustomobject]@{
            Id = '{0}\{1}\{2}' -f $Row.Hive, $Row.View, $Row.KeyName
            DisplayName = $name
            Version = $Row.DisplayVersion
            Publisher = $Row.Publisher
            InstallLocation = $Row.InstallLocation
            Year = $year
            Hidden = ($Row.SystemComponent -eq 1)
            Kind = $kind
            ProductCode = $productCode
            Exe = $split.Exe
            Arguments = $split.Arguments
            ThirdParty = (-not [string]::IsNullOrWhiteSpace($Row.Publisher) -and $Row.Publisher -notmatch 'Autodesk')
            Group = $group
            Role = $role
        }
    }
}

function Get-AdskPackage {
    Get-AdskRegistryRows | ConvertTo-AdskPackage
}
