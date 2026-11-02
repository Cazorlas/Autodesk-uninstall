Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force

Describe 'T4 flow contract' {
    BeforeEach {
        $global:FlowPackages = @(
            [pscustomobject]@{ Group = 'Revit'; Year = 2024; DisplayName = 'Revit 2024'; InstallLocation = 'C:\Autodesk\Revit 2024' },
            [pscustomobject]@{ Group = 'Revit'; Year = 2025; DisplayName = 'Revit 2025'; InstallLocation = 'C:\Autodesk\Revit 2025' })
        $global:FlowRemaining = @()
        $global:FlowKept = @()
        $global:FlowStatuses = @('Succeeded', 'Succeeded')
        $global:FlowReads = 0
        $global:FlowFailed = @()
        $global:FlowShared = $false
        $global:FlowReboot = $false
        Mock Start-Transcript {} -ModuleName AutodeskCleaner
        Mock Stop-Transcript {} -ModuleName AutodeskCleaner
        Mock Get-AdskPackage { $global:FlowReads++; if ($global:FlowReads -eq 1) { $global:FlowPackages } else { $global:FlowRemaining } } -ModuleName AutodeskCleaner
        Mock New-AdskRemovalPlan {
            [pscustomobject]@{ Steps = @($global:FlowPackages | ForEach-Object { [pscustomobject]@{ Order = 1; Package = $_; Action = 'Uninstall'; Reason = 'test' } }); Kept = $global:FlowKept; Skipped = @(); SharedRemoved = $global:FlowShared }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskProcessByPath { @() } -ModuleName AutodeskCleaner
        Mock Stop-AdskProcess {} -ModuleName AutodeskCleaner
        Mock Invoke-AdskRemovalPlan {
            $steps = @(for ($i = 0; $i -lt $Plan.Steps.Count; $i++) {
                [pscustomobject]@{ Step = $Plan.Steps[$i]; Status = $global:FlowStatuses[$i] }
            })
            [pscustomobject]@{ FailedGroups = $global:FlowFailed; RebootRequired = $global:FlowReboot; Steps = $steps; Stopped = $false }
        } -ModuleName AutodeskCleaner
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
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Times 1 -Exactly -Scope It -ParameterFilter { @($Removed).Count -eq 1 -and $Removed[0].Year -eq 2024 -and $Removed[0].Group -eq 'Revit' -and @($RemovedPackages).Count -eq 1 -and $RemovedPackages[0].Year -eq 2024 }
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

Describe 'T6 flow path and remnant scope' {
    BeforeEach {
        $global:T6Packages = @(
            [pscustomobject]@{ Group = 'Revit'; Year = 2025; DisplayName = 'Autodesk Revit 2025'; InstallLocation = 'D:\Program Files\Autodesk' },
            [pscustomobject]@{ Group = 'Revit'; Year = 2025; DisplayName = 'Revit 2025'; InstallLocation = 'D:\Program Files\Autodesk\\Revit 2025\' })
        $global:T6Kept = @()
        $global:T6Failed = @()
        $global:T6Statuses = @('Succeeded', 'AlreadyGone')
        Mock Start-Transcript {} -ModuleName AutodeskCleaner
        Mock Stop-Transcript {} -ModuleName AutodeskCleaner
        Mock Get-AdskPackage { $global:T6Packages } -ModuleName AutodeskCleaner
        Mock New-AdskRemovalPlan {
            [pscustomobject]@{ Steps = @($global:T6Packages | ForEach-Object { [pscustomobject]@{ Order = 1; Package = $_; Action = 'Uninstall'; Reason = 'test' } }); Kept = $global:T6Kept; Skipped = @(); SharedRemoved = $false }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskProcessByPath { @() } -ModuleName AutodeskCleaner
        Mock Invoke-AdskRemovalPlan {
            $steps = @(for ($i = 0; $i -lt $Plan.Steps.Count; $i++) {
                [pscustomobject]@{ Step = $Plan.Steps[$i]; Status = $global:T6Statuses[$i] }
            })
            [pscustomobject]@{ Steps = $steps; FailedGroups = $global:T6Failed; Stopped = $false; RebootRequired = $false }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskRemnant { @() } -ModuleName AutodeskCleaner
        Mock Test-AdskReinstallReadiness { @() } -ModuleName AutodeskCleaner
    }

    It 'probes only the normalized product folder, deduplicated, never the root' {
        $global:T6Packages += [pscustomobject]@{ Group = 'Revit'; Year = 2025; DisplayName = 'duplicate'; InstallLocation = ' D:\Program Files\Autodesk\Revit 2025\ ' }
        $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Get-AdskProcessByPath -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
        Assert-MockCalled Get-AdskProcessByPath -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -eq 'D:\Program Files\Autodesk\Revit 2025' }
    }

    It 'never probes an equal kept location or its parent' {
        $global:T6Packages[1].InstallLocation = 'D:\Program Files\Autodesk\Revit 2024\'
        foreach ($location in @('D:\Program Files\Autodesk\\Revit 2024\', 'D:\Program Files\Autodesk\Revit 2024\AddIns\X\')) {
            $global:T6Kept = @([pscustomobject]@{ Package = [pscustomobject]@{ InstallLocation = $location }; Reason = 'kept' })
            $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -LogRoot $TestDrive -Confirm { $false }
        }
        Assert-MockCalled Get-AdskProcessByPath -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'ignores a kept Autodesk root and still prompts for the selected product process' {
        $global:T6Kept = @([pscustomobject]@{ Package = [pscustomobject]@{ Group = 'Revit'; Year = 2024; InstallLocation = 'D:\Program Files\Autodesk\\' }; Reason = 'kept' })
        $global:T6ConfirmSeen = $false
        Mock Get-AdskProcessByPath { [pscustomobject]@{ Id = 64408; Path = 'D:\Program Files\Autodesk\Revit 2025\Revit.exe' } } -ModuleName AutodeskCleaner
        Mock Stop-AdskProcess {} -ModuleName AutodeskCleaner
        $summary = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -LogRoot $TestDrive -Confirm { $global:T6ConfirmSeen = $true; $false }
        Assert-MockCalled Get-AdskProcessByPath -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
        Assert-MockCalled Get-AdskProcessByPath -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -eq 'D:\Program Files\Autodesk\Revit 2025' }
        $global:T6ConfirmSeen | Should Be $true
        ($null -eq $summary.Result) | Should Be $true
        Assert-MockCalled Invoke-AdskRemovalPlan -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Stop-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'passes planned packages and the projected remaining inventory in preview' {
        $global:T6Kept = @([pscustomobject]@{ Package = [pscustomobject]@{ Group = 'Revit'; Year = 2024; InstallLocation = 'D:\Program Files\Autodesk\Revit 2024' }; Reason = 'kept' })
        $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter {
            @($RemovedPackages).Count -eq 2 -and @($Packages).Count -eq 1 -and $Packages[0].Year -eq 2024
        }
    }

    It 'passes succeeded and already-gone packages after execution' {
        $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -Execute -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { @($RemovedPackages).Count -eq 2 }
    }

    It 'excludes every package in a failed group even if its own step succeeded' {
        $global:T6Failed = @([pscustomobject]@{ Group = 'Revit'; Year = 2025 })
        $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -Execute -LogRoot $TestDrive -Confirm { $false }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { @($RemovedPackages).Count -eq 0 }
    }

    It 'excludes skipped, failed, timed-out and DryRun step statuses during execution' {
        foreach ($status in @('Skipped', 'Failed', 'TimedOut', 'DryRun')) {
            $global:T6Statuses = @($status, $status)
            $null = Invoke-AdskCleanerFlow -Group Revit -Year 2025 -Execute -LogRoot $TestDrive -Confirm { $false }
        }
        Assert-MockCalled Get-AdskRemnant -ModuleName AutodeskCleaner -Scope It -Times 4 -Exactly -ParameterFilter { @($RemovedPackages).Count -eq 0 }
    }
}
