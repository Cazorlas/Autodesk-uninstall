Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

function New-ExecutorTestStep {
    param([int]$Order = 1, [string]$Group = 'Revit', [int]$Year = 2025)
    $package = Get-FixturePackage 'Autodesk Revit 2025'
    $package.Group = $Group
    $package.Year = $Year
    [pscustomobject]@{ Order = $Order; Package = $package; Action = 'Uninstall'; Reason = 'test' }
}

Describe 'Executor contract' {
    BeforeEach {
        Mock Invoke-AdskProcess { @{ ExitCode = 0; TimedOut = $false } } -ModuleName AutodeskCleaner
        Mock Test-AdskMsiBusy { $false } -ModuleName AutodeskCleaner
        Mock Get-AdskRegistryRows { throw 'Unexpected registry read' } -ModuleName AutodeskCleaner
        Mock Start-Sleep {} -ModuleName AutodeskCleaner
        $step = New-ExecutorTestStep
        $plan = [pscustomobject]@{ Steps = @($step) }
    }

    It '01 builds the MSI quiet command with restart suppression and a quoted log' {
        $package = [pscustomobject]@{ Kind = 'MSI'; ProductCode = '{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}' }
        $command = Get-AdskUninstallCommand $package -LogFile 'C:\logs with spaces\1.log'
        $command.FilePath | Should BeExactly 'msiexec.exe'
        $command.ArgumentList | Should BeExactly '/x {AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA} /qn /norestart REBOOT=ReallySuppress /L*v "C:\logs with spaces\1.log"'
    }

    It '02 appends only a missing ODIS quiet token' {
        $package = [pscustomobject]@{ Kind = 'ODIS'; Exe = 'C:\Installer.exe'; Arguments = '-i uninstall -m C:\m.xml' }
        (Get-AdskUninstallCommand $package).ArgumentList | Should BeExactly '-i uninstall -m C:\m.xml -q'
        $package.Arguments += ' -q'
        (Get-AdskUninstallCommand $package).ArgumentList | Should BeExactly $package.Arguments
        $package.Arguments = '-quiet -m C:\m.xml'
        (Get-AdskUninstallCommand $package).ArgumentList | Should BeExactly '-quiet -m C:\m.xml -q'
    }

    It '03 skips a generic exe without quiet-command provenance' {
        $step.Package.Kind = 'Exe'
        $step.Package.HasQuietCommand = $false
        ($null -eq (Get-AdskUninstallCommand $step.Package)) | Should Be $true
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        $result.Steps[0].Status | Should BeExactly 'Skipped'
        $result.Steps[0].Reason | Should BeExactly 'no silent uninstall'
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '04 previews all three steps without processes or registry reads' {
        $plan.Steps = @(New-ExecutorTestStep 3; New-ExecutorTestStep 1; New-ExecutorTestStep 2)
        $plan.Steps[0].Action = 'UninstallIfPresent'
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive -DryRun
        $result.Steps.Count | Should Be 3
        @($result.Steps | Where-Object { $_.Status -eq 'DryRun' -and $_.Command.FilePath }).Count | Should Be 3
        ($result.Steps.Step.Order -join ',') | Should BeExactly '1,2,3'
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Get-AdskRegistryRows -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Test-AdskMsiBusy -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '05 protects a failed group-year and all shared infrastructure while another year runs' {
        Mock Invoke-AdskProcess { @{ ExitCode = 1603; TimedOut = $false } } -ModuleName AutodeskCleaner -ParameterFilter { $Arguments -like '*addon*' }
        $step.Package.Arguments = '-i uninstall addon'
        $plan.Steps = @($step; New-ExecutorTestStep 2; New-ExecutorTestStep 3 Revit 2024; New-ExecutorTestStep 4 Infrastructure; New-ExecutorTestStep 5 Shared)
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        ($result.Steps.Status -join ',') | Should BeExactly 'Failed,Skipped,Succeeded,Skipped,Skipped'
        $result.Steps[1].Reason | Should BeExactly 'earlier step failed'
        $result.FailedGroups.Count | Should Be 1
        $result.FailedGroups[0].Group | Should BeExactly 'Revit'
        $result.FailedGroups[0].Year | Should Be 2025
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 2 -Exactly
    }

    It '06 treats both reboot exit codes as success and requests a reboot' {
        foreach ($code in @(3010, 1641)) {
            $global:ExecutorTestExitCode = $code
            Mock Invoke-AdskProcess { @{ ExitCode = $global:ExecutorTestExitCode; TimedOut = $false } } -ModuleName AutodeskCleaner
            $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
            $result.Steps[0].Status | Should BeExactly 'Succeeded'
            $result.Steps[0].ExitCode | Should Be $code
            $result.RebootRequired | Should Be $true
        }
    }

    It '07 treats both absent-product exit codes as AlreadyGone' {
        foreach ($code in @(1605, 1614)) {
            $global:ExecutorTestExitCode = $code
            Mock Invoke-AdskProcess { @{ ExitCode = $global:ExecutorTestExitCode; TimedOut = $false } } -ModuleName AutodeskCleaner
            $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
            $result.Steps[0].Status | Should BeExactly 'AlreadyGone'
            $result.FailedGroups.Count | Should Be 0
        }
    }

    It '08 rechecks hidden registrations and does not run a missing child' {
        Mock Get-AdskRegistryRows { @() } -ModuleName AutodeskCleaner
        $step.Action = 'UninstallIfPresent'
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        $result.Steps[0].Status | Should BeExactly 'AlreadyGone'
        Assert-MockCalled Get-AdskRegistryRows -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '09 stops the run after a process timeout without starting later steps' {
        Mock Invoke-AdskProcess { @{ ExitCode = $null; TimedOut = $true } } -ModuleName AutodeskCleaner
        $plan.Steps += New-ExecutorTestStep 2 Revit 2024
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        $result.Steps[0].Status | Should BeExactly 'TimedOut'
        $result.Stopped | Should Be $true
        $result.Steps[1].Status | Should BeExactly 'Skipped'
        $result.Steps[1].Reason | Should BeExactly 'run stopped after timeout'
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
    }

    It '10 waits for two busy polls then starts the vendor command' {
        $global:ExecutorBusyPolls = 0
        Mock Test-AdskMsiBusy { $global:ExecutorBusyPolls++; $global:ExecutorBusyPolls -le 2 } -ModuleName AutodeskCleaner
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        $result.Steps[0].Status | Should BeExactly 'Succeeded'
        Assert-MockCalled Start-Sleep -ModuleName AutodeskCleaner -Scope It -Times 2 -Exactly
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*Installer.exe' -and $Arguments -match '-q$' -and $TimeoutSeconds -gt 0
        }
    }

    It 'stops when the MSI busy wait exhausts the timeout' {
        Mock Test-AdskMsiBusy { $true } -ModuleName AutodeskCleaner
        $plan.Steps += New-ExecutorTestStep 2
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive -TimeoutMinutes 0.001
        $result.Steps[0].Status | Should BeExactly 'TimedOut'
        $result.Steps[1].Reason | Should BeExactly 'run stopped after timeout'
        $result.Stopped | Should Be $true
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'runs quiet generic exes verbatim and gives helpers only the quiet flag' {
        $step.Package.Kind = 'Exe'
        $step.Package.HasQuietCommand = $true
        $step.Package.Arguments = '--silent'
        (Get-AdskUninstallCommand $step.Package).ArgumentList | Should BeExactly '--silent'
        (Invoke-AdskRemovalPlan $plan -LogDir $TestDrive).Steps[0].Status | Should BeExactly 'Succeeded'
        $step.Package.Kind = 'Helper'
        (Get-AdskUninstallCommand $step.Package).ArgumentList | Should BeExactly '-q'
    }

    It 'runs a hidden child only when the exact hive view and key remain' {
        Mock Get-AdskRegistryRows { Get-Content (Join-Path (Split-Path (Get-Module AutodeskCleaner).Path) '../tests/fixtures/arp-host.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ } } -ModuleName AutodeskCleaner
        $step.Action = 'UninstallIfPresent'
        (Invoke-AdskRemovalPlan $plan -LogDir $TestDrive).Steps[0].Status | Should BeExactly 'Succeeded'
        Assert-MockCalled Invoke-AdskProcess -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
    }

    It 'protects dependants if launching the vendor process throws' {
        Mock Invoke-AdskProcess { throw 'launch failed' } -ModuleName AutodeskCleaner
        $plan.Steps += New-ExecutorTestStep 2
        $result = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        $result.Steps[0].Status | Should BeExactly 'Failed'
        $result.Steps[0].Reason | Should BeExactly 'launch failed'
        $result.Steps[1].Status | Should BeExactly 'Skipped'
    }

    It 'writes one plain-text run log line per step' {
        $plan.Steps += New-ExecutorTestStep 2
        $before = @(Get-Content (Join-Path $TestDrive 'run.log') -ErrorAction SilentlyContinue).Count
        $null = Invoke-AdskRemovalPlan $plan -LogDir $TestDrive
        (@(Get-Content (Join-Path $TestDrive 'run.log')).Count - $before) | Should Be 2
        @(Get-ChildItem $TestDrive).Count | Should Be 1
    }
}
