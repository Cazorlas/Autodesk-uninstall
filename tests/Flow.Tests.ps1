Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force

Describe 'T4 flow contract' {
    BeforeEach {
        $global:FlowPackages = @(
            [pscustomobject]@{ Group = 'Revit'; Year = 2024; DisplayName = 'Revit 2024'; InstallLocation = 'C:\Autodesk\Revit 2024' },
            [pscustomobject]@{ Group = 'Revit'; Year = 2025; DisplayName = 'Revit 2025'; InstallLocation = 'C:\Autodesk\Revit 2025' })
        $global:FlowRemaining = @()
        $global:FlowReads = 0
        $global:FlowFailed = @()
        $global:FlowShared = $false
        $global:FlowReboot = $false
        Mock Start-Transcript {} -ModuleName AutodeskCleaner
        Mock Stop-Transcript {} -ModuleName AutodeskCleaner
        Mock Get-AdskPackage { $global:FlowReads++; if ($global:FlowReads -eq 1) { $global:FlowPackages } else { $global:FlowRemaining } } -ModuleName AutodeskCleaner
        Mock New-AdskRemovalPlan {
            [pscustomobject]@{ Steps = @($global:FlowPackages | ForEach-Object { [pscustomobject]@{ Order = 1; Package = $_; Action = 'Uninstall'; Reason = 'test' } }); Kept = @(); Skipped = @(); SharedRemoved = $global:FlowShared }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskProcessByPath { @() } -ModuleName AutodeskCleaner
        Mock Stop-AdskProcess {} -ModuleName AutodeskCleaner
        Mock Invoke-AdskRemovalPlan { [pscustomobject]@{ FailedGroups = $global:FlowFailed; RebootRequired = $global:FlowReboot; Steps = @(); Stopped = $false } } -ModuleName AutodeskCleaner
        Mock Get-AdskRemnant { [pscustomobject]@{ Path = 'C:\Autodesk\Revit 2024'; Kind = 'Folder'; Group = 'Revit'; Year = 2024 } } -ModuleName AutodeskCleaner
        Mock Invoke-AdskRemnantCleanup { [pscustomobject]@{ Action = 'DryRun' } } -ModuleName AutodeskCleaner
        Mock Test-AdskReinstallReadiness { @() } -ModuleName AutodeskCleaner
    }

    It '01 defaults both executors to DryRun and writes a summary' {
        $summary = Invoke-AdskCleanerFlow -Group Revit -LogRoot $TestDrive -Confirm { $true }
        Assert-MockCalled Invoke-AdskRemovalPlan -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { $DryRun }
        Assert-MockCalled Invoke-AdskRemnantCleanup -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { $DryRun }
        (Test-Path (Join-Path $summary.LogDir 'summary.txt')) | Should Be $true
    }
    It '02 aborts before uninstall or stopping a process when declined' {
        Mock Get-AdskProcessByPath { [pscustomobject]@{ Id = 123; Path = 'C:\Autodesk\Revit 2025\Revit.exe' } } -ModuleName AutodeskCleaner
        $summary = Invoke-AdskCleanerFlow -Group Revit -Execute -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Invoke-AdskRemovalPlan -ModuleName AutodeskCleaner -Times 0 -Exactly -Scope It
        Assert-MockCalled Stop-AdskProcess -ModuleName AutodeskCleaner -Times 0 -Exactly -Scope It
        ($null -eq $summary.Result) | Should Be $true
    }
    It '03 excludes failed group-year pairs from remnant selection' {
        $global:FlowFailed = @([pscustomobject]@{ Group = 'Revit'; Year = 2025 })
        $null = Invoke-AdskCleanerFlow -Group Revit -Execute -LogRoot $TestDrive -Confirm { $true }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { @($Removed).Count -eq 1 -and $Removed[0].Year -eq 2024 -and $Removed[0].Group -eq 'Revit' }
    }
    It '04 enables infrastructure cleanup only after complete removal' {
        $global:FlowShared = $true
        $null = Invoke-AdskCleanerFlow -All -Execute -LogRoot $TestDrive -Confirm { $true }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { $InfrastructureRemoved }
    }
    It '05 keeps infrastructure when any package remains' {
        $global:FlowShared = $true
        $global:FlowRemaining = @($global:FlowPackages[0])
        $null = Invoke-AdskCleanerFlow -All -Execute -LogRoot $TestDrive -Confirm { $true }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { -not $InfrastructureRemoved }
    }
    It '06 does not clean remnants when declined' {
        $null = Invoke-AdskCleanerFlow -Group Revit -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Invoke-AdskRemnantCleanup -ModuleName AutodeskCleaner -Times 0 -Exactly -Scope It
    }
    It '07 preserves the executor reboot requirement' {
        $global:FlowReboot = $true
        (Invoke-AdskCleanerFlow -Group Revit -LogRoot $TestDrive -Confirm { $true }).RebootRequired | Should Be $true
    }
    It 'never stops a process during preview even when accepted' {
        Mock Get-AdskProcessByPath { [pscustomobject]@{ Id = 123; Path = 'C:\Autodesk\Revit 2025\Revit.exe' } } -ModuleName AutodeskCleaner
        $null = Invoke-AdskCleanerFlow -Group Revit -LogRoot $TestDrive -Confirm { $true }
        Assert-MockCalled Stop-AdskProcess -ModuleName AutodeskCleaner -Times 0 -Exactly -Scope It
    }
}
