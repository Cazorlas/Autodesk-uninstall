Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force

Describe 'T3 readiness and per-item repairs' {
    BeforeEach {
        Mock Get-AdskRegistryRows { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessInstallerProducts { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessInstallProperties { $null } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessRunOnce { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessIfeo { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessPendingReboot { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskService { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskProcessByPath { @() } -ModuleName AutodeskCleaner
        Mock Test-AdskMsiBusy { $false } -ModuleName AutodeskCleaner
        Mock Test-AdskPath { $false } -ModuleName AutodeskCleaner
        Mock New-AdskDirectory {} -ModuleName AutodeskCleaner
        Mock Move-AdskItem {} -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey {} -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryKey {} -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryValue {} -ModuleName AutodeskCleaner
    }

    It '09 detects the missing ODIS -m manifest even when Installer.exe exists' {
        Mock Get-AdskRegistryRows {
            [pscustomobject]@{ Hive = 'HKLM'; View = '64'; KeyName = 'revit'; DisplayName = 'Autodesk Revit 2025';
                Publisher = 'Autodesk'; UninstallString = '"C:\Program Files\Autodesk\AdODIS\V1\Installer.exe" -i uninstall -m "C:\missing manifest.xml"' }
        } -ModuleName AutodeskCleaner
        Mock Test-AdskPath { $Path -like '*Installer.exe' } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OrphanArp
        $finding.Severity | Should BeExactly 'Error'
        $finding.UninstallerMissing | Should Be $false
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '10 detects a registered MSI with a missing LocalPackage' {
        Mock Get-AdskReadinessInstallerProducts {
            [pscustomobject]@{ ProductCode = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; PackedGuid = '87654321BA09FEDC2143658709BADCFE'; ProductName = 'Autodesk Revit' }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessInstallProperties { [pscustomobject]@{ LocalPackage = 'C:\Windows\Installer\abc.msi'; Publisher = 'Autodesk' } } -ModuleName AutodeskCleaner
        $findings = @(Test-AdskReinstallReadiness)
        @($findings | Where-Object { $_.Code -eq 'MsiCacheMissing' -and $_.Severity -eq 'Error' }).Count | Should Be 1
        @($findings | Where-Object Code -eq MsiNoArp).Count | Should Be 1
    }

    It '11 detects RunOnce and exports before deleting only AutodeskCleanup' {
        Mock Get-AdskReadinessRunOnce { [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Name = 'AutodeskCleanup'; Value = 'old-tool.cmd' } } -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey { $script:t3RunOnceExported = $true } -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryValue { if (-not $script:t3RunOnceExported) { throw 'Export first' } } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OldToolRunOnce
        $finding.Severity | Should BeExactly 'Error'
        (Repair-AdskReinstallBlocker $finding -DryRun).Action | Should BeExactly 'DryRun'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Exported+Deleted'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -eq 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'AutodeskCleanup' -and $Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '12 detects an Autodesk service with a missing binary' {
        Mock Get-AdskService { [pscustomobject]@{ Name = 'AdskLicensingService'; DisplayName = 'Autodesk Licensing'; PathName = '"C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\service.exe" --service' } } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq ServiceBinaryMissing
        $finding.Severity | Should BeExactly 'Error'
        $finding.Target | Should BeExactly 'AdskLicensingService'
    }

    It '13 reports pending rename as warning and returns guidance without writes' {
        Mock Get-AdskReadinessPendingReboot { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations' } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq PendingReboot
        $finding.Severity | Should BeExactly 'Warning'
        Repair-AdskReinstallBlocker $finding | Should BeExactly $finding.Fix
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled New-AdskDirectory -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '14 converts the known MSI packed GUID and round-trips valid GUIDs' {
        ConvertTo-AdskPackedGuid '{12345678-90AB-CDEF-1234-567890ABCDEF}' | Should BeExactly '87654321BA09FEDC2143658709BADCFE'
        ConvertFrom-AdskPackedGuid '87654321BA09FEDC2143658709BADCFE' | Should BeExactly '{12345678-90AB-CDEF-1234-567890ABCDEF}'
        foreach ($guid in @('{00000000-0000-0000-0000-000000000000}', '{ABCDEF01-2345-6789-ABCD-EF0123456789}')) {
            ConvertFrom-AdskPackedGuid (ConvertTo-AdskPackedGuid $guid) | Should BeExactly $guid
        }
        { ConvertFrom-AdskPackedGuid 'not-packed' } | Should Throw
        { ConvertTo-AdskPackedGuid 'not-guid' } | Should Throw
    }

    It '15 refuses orphan ARP repair while its ProductCode is still registered' {
        Mock Get-AdskRegistryRows {
            [pscustomobject]@{ Hive = 'HKLM'; View = '64'; KeyName = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; DisplayName = 'Autodesk Revit 2025'; Publisher = 'Autodesk'; UninstallString = 'C:\missing.exe' }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessInstallerProducts {
            [pscustomobject]@{ ProductCode = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; PackedGuid = '87654321BA09FEDC2143658709BADCFE'; ProductName = 'Autodesk Revit' }
        } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OrphanArp
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'repairs a missing-executable ARP entry only after export when no MSI remains' {
        Mock Get-AdskRegistryRows { [pscustomobject]@{ Hive = 'HKLM'; View = '32'; KeyName = 'orphan'; DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; UninstallString = 'C:\missing.exe' } } -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey { $script:t3ArpExported = $true } -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryKey { if (-not $script:t3ArpExported) { throw 'Export first' } } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OrphanArp
        $finding.Target | Should BeExactly 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\orphan'
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Exported+Deleted'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
    }

    It 'backs up IFEO and removes only Debugger' {
        Mock Get-AdskReadinessIfeo { [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Revit.exe'; Name = 'Debugger'; Value = 'bad.exe' } } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq IfeoDebugger
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Exported+Deleted'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Name -eq 'Debugger' }
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'does not delete any value after a failed export' {
        Mock Get-AdskReadinessRunOnce { [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Name = 'AutodeskCleanup'; Value = 'old.cmd' } } -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey { throw 'export failed' } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OldToolRunOnce
        (Repair-AdskReinstallBlocker $finding).Error | Should BeExactly 'export failed'
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'quarantines a stale ODIS lock but refuses when an AdODIS installer starts' {
        Mock Test-AdskPath { $Path -like '*AdODISInstaller.run.lock' } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OdisLock
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Moved'
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -like '*AdODISInstaller.run.lock' }
        Mock Get-AdskProcessByPath { [pscustomobject]@{ Path = "$env:ProgramFiles\Autodesk\AdODIS\V1\Installer.exe" } } -ModuleName AutodeskCleaner
        @(Test-AdskReinstallReadiness | Where-Object Code -eq OdisLock).Count | Should Be 0
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
    }

    It 'reports MSI busy without invoking any side effect' {
        Mock Test-AdskMsiBusy { $true } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq MsiBusy
        $finding.Severity | Should BeExactly 'Warning'
        Repair-AdskReinstallBlocker $finding | Should BeExactly $finding.Fix
        Assert-MockCalled New-AdskDirectory -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryValue -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'rejects a stale or forged repair target' {
        $finding = [pscustomobject]@{ Code = 'OrphanArp'; Target = 'HKLM:\SOFTWARE'; Fix = 'guidance'; ProductCode = $null }
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'ignores unrelated MSI and services' {
        Mock Get-AdskReadinessInstallerProducts { [pscustomobject]@{ ProductCode = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; PackedGuid = '87654321BA09FEDC2143658709BADCFE'; ProductName = 'Other vendor' } } -ModuleName AutodeskCleaner
        Mock Get-AdskService { [pscustomobject]@{ Name = 'OtherService'; DisplayName = 'Other'; PathName = 'C:\missing.exe' } } -ModuleName AutodeskCleaner
        @(Test-AdskReinstallReadiness).Count | Should Be 0
    }
}

Describe 'T3 MSI registration sources across user SIDs' {
    BeforeEach {
        # Exercise the real MSI source helpers, with registry/file provider reads fully mocked.
        Mock Test-AdskPath { $Path -like 'HK*' -or $Path -eq 'C:\Windows\Installer\per-user.msi' } -ModuleName AutodeskCleaner
        Mock Get-ChildItem {
            if ($LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData') {
                [pscustomobject]@{ PSChildName = 'S-1-5-18' }
                [pscustomobject]@{ PSChildName = 'S-1-5-21-111-222-333-1001' }
            } elseif ($LiteralPath -like '*\S-1-5-21-111-222-333-1001\Products') {
                [pscustomobject]@{ PSChildName = '87654321BA09FEDC2143658709BADCFE' }
            }
        } -ModuleName AutodeskCleaner
        Mock Get-ItemProperty {
            if ($LiteralPath -like '*\S-1-5-21-111-222-333-1001\Products\*\InstallProperties') {
                [pscustomobject]@{ DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; LocalPackage = 'C:\Windows\Installer\per-user.msi' }
            }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskRegistryRows {
            [pscustomobject]@{ Hive = 'HKCU'; View = '64'; KeyName = '{12345678-90AB-CDEF-1234-567890ABCDEF}';
                DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; UninstallString = 'MsiExec.exe /X{12345678-90AB-CDEF-1234-567890ABCDEF}' }
        } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessRunOnce { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessIfeo { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskReadinessPendingReboot { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskService { @() } -ModuleName AutodeskCleaner
        Mock Get-AdskProcessByPath { @() } -ModuleName AutodeskCleaner
        Mock Test-AdskMsiBusy { $false } -ModuleName AutodeskCleaner
        Mock New-AdskDirectory {} -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey {} -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryKey {} -ModuleName AutodeskCleaner
    }

    It 'a finds a per-user SID cache after S-1-5-18 and emits no finding when it exists' {
        @(Test-AdskReinstallReadiness).Count | Should Be 0
        Assert-MockCalled Get-ItemProperty -ModuleName AutodeskCleaner -Scope It -Times 2 -Exactly -ParameterFilter {
            $LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-21-111-222-333-1001\Products\87654321BA09FEDC2143658709BADCFE\InstallProperties'
        }
    }

    It 'b emits no finding for an empty LocalPackage in an existing registration' {
        Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; LocalPackage = '' } } -ModuleName AutodeskCleaner
        @(Test-AdskReinstallReadiness).Count | Should Be 0
        Assert-MockCalled Test-AdskPath -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly -ParameterFilter { [string]::IsNullOrWhiteSpace($Path) }
    }

    It 'c refuses ARP repair when the product exists only in HKCU Installer Products' {
        Mock Get-ChildItem {
            if ($LiteralPath -eq 'HKCU:\SOFTWARE\Microsoft\Installer\Products') {
                [pscustomobject]@{ PSChildName = '87654321BA09FEDC2143658709BADCFE'; PSPath = 'HKCU:\SOFTWARE\Microsoft\Installer\Products\87654321BA09FEDC2143658709BADCFE' }
            }
        } -ModuleName AutodeskCleaner
        Mock Get-ItemProperty { [pscustomobject]@{ ProductName = 'Autodesk Revit' } } -ModuleName AutodeskCleaner
        Mock Get-AdskRegistryRows {
            [pscustomobject]@{ Hive = 'HKCU'; View = '64'; KeyName = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; UninstallString = 'C:\missing.exe' }
        } -ModuleName AutodeskCleaner
        $registered = @(Get-AdskReadinessInstallerProducts)
        $registered.Count | Should Be 1
        $registered[0].Path | Should BeExactly 'HKCU:\SOFTWARE\Microsoft\Installer\Products\87654321BA09FEDC2143658709BADCFE'
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OrphanArp
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'refuses ARP repair when only a UserData SID registration remains' {
        Mock Get-AdskRegistryRows {
            [pscustomobject]@{ Hive = 'HKLM'; View = '64'; KeyName = '{12345678-90AB-CDEF-1234-567890ABCDEF}'; DisplayName = 'Autodesk Revit'; Publisher = 'Autodesk'; UninstallString = 'C:\missing.exe' }
        } -ModuleName AutodeskCleaner
        $finding = Test-AdskReinstallReadiness | Where-Object Code -eq OrphanArp
        (Repair-AdskReinstallBlocker $finding).Action | Should BeExactly 'Refused'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'does not report cache missing when no InstallProperties registration is found' {
        Mock Get-ChildItem {
            if ($LiteralPath -eq 'HKCU:\SOFTWARE\Microsoft\Installer\Products') {
                [pscustomobject]@{ PSChildName = '87654321BA09FEDC2143658709BADCFE'; PSPath = 'HKCU:\SOFTWARE\Microsoft\Installer\Products\87654321BA09FEDC2143658709BADCFE' }
            }
        } -ModuleName AutodeskCleaner
        Mock Get-ItemProperty { [pscustomobject]@{ ProductName = 'Autodesk Revit' } } -ModuleName AutodeskCleaner
        @(Test-AdskReinstallReadiness).Count | Should Be 0
    }

    It 'deduplicates MsiNoArp when a product is registered in HKCU and UserData' {
        Mock Get-AdskRegistryRows { @() } -ModuleName AutodeskCleaner
        Mock Get-ChildItem {
            if ($LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData') {
                [pscustomobject]@{ PSChildName = 'S-1-5-21-111-222-333-1001' }
            } elseif ($LiteralPath -eq 'HKCU:\SOFTWARE\Microsoft\Installer\Products' -or $LiteralPath -like '*\S-1-5-21-111-222-333-1001\Products') {
                [pscustomobject]@{ PSChildName = '87654321BA09FEDC2143658709BADCFE'; PSPath = 'HKCU:\SOFTWARE\Microsoft\Installer\Products\87654321BA09FEDC2143658709BADCFE' }
            }
        } -ModuleName AutodeskCleaner
        $findings = @(Test-AdskReinstallReadiness)
        $findings.Count | Should Be 1
        $findings[0].Code | Should BeExactly 'MsiNoArp'
    }
}
