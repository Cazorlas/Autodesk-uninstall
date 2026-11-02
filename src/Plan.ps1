function New-AdskRemovalPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Packages,
        [string[]]$Group,
        [ValidateRange(2010, 2099)][int[]]$Year,
        [switch]$All,
        [switch]$IncludeThirdParty
    )
    if ($All -and ($Group -or $Year)) { throw '-All cannot be combined with -Group or -Year.' }
    if (-not $All -and -not $Group) { throw 'Specify -Group or -All.' }
    $selected = @{}
    $reasons = @{}
    $eligible = @($Packages | Where-Object { $IncludeThirdParty -or (-not $_.ThirdParty -and $_.Role -ne 'DevTool') })
    foreach ($package in $Packages) {
        if ($eligible.Id -notcontains $package.Id) { $reasons[$package.Id] = 'DevTool or third-party package excluded'; continue }
        if ($package.Group -in @('Shared', 'Infrastructure')) { continue }
        if (-not $All -and $Group -notcontains $package.Group) { $reasons[$package.Id] = 'Group not selected'; continue }
        $yearSelected = $All -or -not $Year -or ($null -ne $package.Year -and $Year -contains $package.Year)
        if (-not $yearSelected -and $null -eq $package.Year) {
            $remainingYears = @($eligible | Where-Object {
                $_.Group -eq $package.Group -and $null -ne $_.Year -and $Year -notcontains $_.Year
            })
            $yearSelected = $remainingYears.Count -eq 0
        }
        if ($yearSelected) { $selected[$package.Id] = $true }
        else { $reasons[$package.Id] = 'Year not selected; year-less packages require every year' }
    }
    # Kind None still belongs to the selection (and Skipped); it has no command to execute.
    $outside = @($Packages | Where-Object {
        $_.Group -notin @('Shared', 'Infrastructure') -and -not $_.ThirdParty -and
        $_.Role -ne 'DevTool' -and -not $selected.ContainsKey($_.Id)
    })
    $sharedRemoved = $outside.Count -eq 0
    foreach ($package in $eligible) {
        if ($package.Group -in @('Shared', 'Infrastructure')) {
            if ($sharedRemoved) { $selected[$package.Id] = $true }
            else { $reasons[$package.Id] = 'Shared components required by retained Autodesk products' }
        }
    }
    $roleOrder = @{ Addon = 0; Content = 0; LanguagePack = 0; Update = 1; Main = 2; DevTool = 2 }
    $infrastructureOrder = @('Desktop App|App Manager', 'Autodesk Access', 'Single Sign On',
        'Identity Manager', 'Genuine Service', 'Licensing', 'ODIS|Autodesk Installer')
    $ordered = @($Packages | Where-Object { $selected.ContainsKey($_.Id) -and $_.Kind -ne 'None' } |
        Sort-Object @{ Expression = {
            if ($_.Group -eq 'Infrastructure') { 6 }
            elseif ($_.Role -eq 'MaterialLibrary') { 4 }
            elseif ($_.Group -eq 'Shared') { 5 }
            elseif ($_.Hidden) { 3 }
            else { $roleOrder[$_.Role] }
        } }, @{ Expression = {
            $rank = 0
            if ($_.Group -eq 'Infrastructure') {
                $rank = $infrastructureOrder.Count
                for ($i = 0; $i -lt $infrastructureOrder.Count; $i++) {
                    if ($_.DisplayName -match $infrastructureOrder[$i]) { $rank = $i; break }
                }
            } elseif ($_.Role -eq 'MaterialLibrary') {
                # Image libraries depend on the core library: Medium -> Low -> Base -> core (Advanced before plain).
                if ($_.DisplayName -match 'Medium Resolution') { $rank = 0 }
                elseif ($_.DisplayName -match 'Low Resolution') { $rank = 1 }
                elseif ($_.DisplayName -match 'Base Resolution') { $rank = 2 }
                else { $rank = 3 }
            }
            $rank
        } }, Group, Year, DisplayName, Id)
    $steps = @(for ($i = 0; $i -lt $ordered.Count; $i++) {
        $package = $ordered[$i]
        $action = 'Uninstall'
        $reason = 'Selected package'
        if ($package.Hidden) { $action = 'UninstallIfPresent'; $reason = 'Recheck hidden child after bundle uninstall' }
        [pscustomobject]@{ Order = $i + 1; Package = $package; Action = $action; Reason = $reason }
    })
    $skipped = @($Packages | Where-Object { $selected.ContainsKey($_.Id) -and $_.Kind -eq 'None' } |
        ForEach-Object { [pscustomobject]@{ Package = $_; Reason = 'No uninstall command' } })
    $kept = @($Packages | Where-Object { -not $selected.ContainsKey($_.Id) } |
        ForEach-Object { [pscustomobject]@{ Package = $_; Reason = $reasons[$_.Id] } })
    [pscustomobject]@{ Steps = $steps; Kept = $kept; Skipped = $skipped; SharedRemoved = $sharedRemoved }
}
