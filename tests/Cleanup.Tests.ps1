Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force

Describe 'T3 remnant selection' {
    BeforeEach {
        Mock Test-AdskPath { $true } -ModuleName AutodeskCleaner
        $removed = @(@{ Group = 'Revit'; Year = 2025 })
        $remaining = @([pscustomobject]@{ Group = 'Revit'; Year = 2024; InstallLocation = $null })
    }

    It '01 selects only fully removed 2025 non-user paths while 2024 remains' {
        $items = @(Get-AdskRemnant -Packages $remaining -Removed $removed)
        $items.Count | Should Be 6
        @($items | Where-Object { $_.Year -ne 2025 -or $_.UserData }).Count | Should Be 0
        @($items | Where-Object { $_.Path -eq "$env:ProgramData\Autodesk\RVT 2025" }).Count | Should Be 1
    }

    It '02 includes explicit user data but never Desktop Connector workspaces' {
        $items = @(Get-AdskRemnant -Packages $remaining -Removed $removed -IncludeUserData)
        @($items | Where-Object UserData).Count | Should Be 5
        $catalog = @(Get-AdskRemnantCatalog -Year 2025)
        @($catalog | Where-Object { $_.Path -like "$env:USERPROFILE\DC*" -or $_.Path -like "$env:USERPROFILE\ACCDocs*" }).Count | Should Be 0
        @($catalog | Where-Object { $_.Group -eq 'DesktopConnector' -and $null -ne $_.Year }).Count | Should Be 0
    }

    It '03 protects a remaining install with trailing slash even in another group' {
        $remaining += [pscustomobject]@{ Group = 'Other'; Year = $null; InstallLocation = "$env:ProgramFiles\Autodesk\Revit 2025\" }
        $items = @(Get-AdskRemnant -Packages $remaining -Removed $removed)
        @($items | Where-Object { $_.Path -eq "$env:ProgramFiles\Autodesk\Revit 2025" }).Count | Should Be 0
    }

    It 'protects a child install and does not confuse neighboring folder names' {
        $remaining += [pscustomobject]@{ Group = 'Other'; Year = $null; InstallLocation = "$env:ProgramFiles\Autodesk\Revit 2025\Child" }
        @((Get-AdskRemnant -Packages $remaining -Removed $removed) | Where-Object { $_.Path -eq "$env:ProgramFiles\Autodesk\Revit 2025" }).Count | Should Be 0
        $remaining[-1].InstallLocation = "$env:ProgramFiles\Autodesk\Revit 20250"
        @((Get-AdskRemnant -Packages $remaining -Removed $removed) | Where-Object { $_.Path -eq "$env:ProgramFiles\Autodesk\Revit 2025" }).Count | Should Be 1
    }

    It '04 gates all infrastructure on the flag and an empty inventory' {
        @(Get-AdskRemnant -Removed @(@{ Group = 'Infrastructure'; Year = $null })).Count | Should Be 0
        @(Get-AdskRemnant -InfrastructureRemoved -Packages $remaining).Count | Should Be 0
        @(Get-AdskRemnant -InfrastructureRemoved).Count | Should Be 7
    }

    It 'returns only existing paths' {
        Mock Test-AdskPath { $false } -ModuleName AutodeskCleaner
        @(Get-AdskRemnant -Removed $removed -IncludeUserData).Count | Should Be 0
    }

    It 'expands environment variables when called, not at module import' {
        $original = $env:ProgramData
        try {
            $env:ProgramData = "$TestDrive\dynamic"
            @((Get-AdskRemnantCatalog -Group Revit -Year 2025) | Where-Object { $_.Path -eq "$TestDrive\dynamic\Autodesk\RVT 2025" }).Count | Should Be 1
        } finally { $env:ProgramData = $original }
    }

    It 'covers all required product catalogs' {
        $catalog = @(Get-AdskRemnantCatalog -Year 2025)
        @($catalog | Where-Object Group -eq Revit).Count | Should Be 11
        @($catalog | Where-Object Group -eq AutoCAD).Count | Should Be 4
        @($catalog | Where-Object Group -eq Navisworks).Count | Should Be 6
        @($catalog | Where-Object Group -eq DesktopConnector).Count | Should Be 2
    }
}

Describe 'T3 root guard' {
    It '05 throws if a catalog entry resolves to an Autodesk root' {
        Mock Get-AdskRemnantCatalog { [pscustomobject]@{ Path = "$env:ProgramData\Autodesk"; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false } } -ModuleName AutodeskCleaner
        { Get-AdskRemnant -Removed @(@{ Group = 'Revit'; Year = 2025 }) } | Should Throw
    }
}

Describe 'T3 quarantine writes' {
    BeforeEach {
        Mock Test-AdskPath { $false } -ModuleName AutodeskCleaner
        Mock New-AdskDirectory {} -ModuleName AutodeskCleaner
        Mock Move-AdskItem {} -ModuleName AutodeskCleaner
        Mock Export-AdskRegistryKey {} -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryKey {} -ModuleName AutodeskCleaner
        $folder = @(Get-AdskRemnantCatalog -Group Revit -Year 2025)[0]
        $registry = Get-AdskRemnantCatalog -Group Revit -Year 2025 | Where-Object Kind -eq RegistryKey
    }

    It '06 dry run invokes no write wrapper including directory creation and export' {
        $results = @(Invoke-AdskRemnantCleanup -Remnant @($folder, $registry) -RunId r1 -DryRun)
        @($results | Where-Object Action -ne DryRun).Count | Should Be 0
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled New-AdskDirectory -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It '07 moves into same-drive quarantine preserving the source path' {
        $result = Invoke-AdskRemnantCleanup -Remnant $folder -RunId r1
        $expected = [IO.Path]::GetPathRoot($folder.Path) + 'AutodeskCleaner.Quarantine\r1\' + $folder.Path.Substring(3)
        $result.Action | Should BeExactly 'Moved'
        $result.Destination | Should BeExactly $expected
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Destination -eq $expected }
    }

    It '08 exports a registry key before deleting it, passing reg.exe native syntax' {
        Mock Export-AdskRegistryKey { $script:t3Exported = $true } -ModuleName AutodeskCleaner
        Mock Remove-AdskRegistryKey { if (-not $script:t3Exported) { throw 'Export must precede deletion' } } -ModuleName AutodeskCleaner
        (Invoke-AdskRemnantCleanup -Remnant $registry -RunId r1).Action | Should BeExactly 'Exported+Deleted'
        Assert-MockCalled Export-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -eq 'HKCU\Software\Autodesk\Revit\Autodesk Revit 2025' }
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly
    }

    It 'keeps the source and continues after a failed move' {
        Mock Move-AdskItem { throw 'locked' } -ModuleName AutodeskCleaner
        $results = @(Invoke-AdskRemnantCleanup -Remnant @($folder, $registry) -RunId r1)
        $results[0].Action | Should BeExactly 'Failed'
        $results[0].Error | Should BeExactly 'locked'
        $results[1].Action | Should BeExactly 'Exported+Deleted'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 1 -Exactly -ParameterFilter { $Path -like 'HKCU:*' }
    }

    It 'does not delete after export failure or overwrite an existing quarantine item' {
        Mock Export-AdskRegistryKey { throw 'export failed' } -ModuleName AutodeskCleaner
        (Invoke-AdskRemnantCleanup -Remnant $registry -RunId r1).Action | Should BeExactly 'Failed'
        Assert-MockCalled Remove-AdskRegistryKey -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Mock Test-AdskPath { $true } -ModuleName AutodeskCleaner
        (Invoke-AdskRemnantCleanup -Remnant $folder -RunId r1).Action | Should BeExactly 'Failed'
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }

    It 'rejects roots, arbitrary registry keys, traversal and cross-drive quarantine' {
        foreach ($path in @("$env:ProgramData\Autodesk", "$env:USERPROFILE\DC", 'C:\', 'HKLM:\SOFTWARE\Classes\Installer\Products')) {
            (Invoke-AdskRemnantCleanup -Remnant @([pscustomobject]@{ Path = $path; Kind = 'Folder' }) -RunId r1).Action | Should BeExactly 'Failed'
        }
        (Invoke-AdskRemnantCleanup -Remnant $folder -RunId '..\escape').Action | Should BeExactly 'Failed'
        $otherDrive = if ($folder.Path -like 'Z:*') { 'Y:\quarantine' } else { 'Z:\quarantine' }
        (Invoke-AdskRemnantCleanup -Remnant $folder -RunId r1 -QuarantineRoot $otherDrive).Action | Should BeExactly 'Failed'
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }
}

Describe 'T6 protected roots on every drive' {
    It 'protects roots after trimming, expanding variables and collapsing separators' {
        foreach ($path in @('D:\Program Files\Autodesk', 'D:\Program Files\Autodesk\',
            'D:\Program Files\Autodesk\\', 'C:\Program Files (x86)\Common Files\Autodesk Shared',
            'E:\', 'D:\Program Files', 'D:\Program Files (x86)', 'D:\ProgramData', 'D:\Users',
            'D:\Users\owner', 'D:\Users\owner\AppData\Roaming', 'D:\Users\owner\AppData\Local',
            'D:\Common Files', '  D:\Program Files\Autodesk\\  ', '%USERPROFILE%')) {
            Test-AdskProtectedRoot -Path $path | Should Be $true
        }
    }

    It 'allows product folders with trailing or doubled separators' {
        foreach ($path in @('D:\Program Files\Autodesk\Revit 2025\',
            'D:\Program Files\Autodesk\\Carbon Insights for Revit 2024\')) {
            Test-AdskProtectedRoot -Path $path | Should Be $false
        }
    }

    It 'keeps the catalog root guard effective on another drive' {
        Mock Get-AdskRemnantCatalog { [pscustomobject]@{ Path = 'D:\Program Files\Autodesk\\'; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false } } -ModuleName AutodeskCleaner
        { Get-AdskRemnant -Removed @(@{ Group = 'Revit'; Year = 2025 }) } | Should Throw
    }
}

Describe 'T6 removed install locations' {
    BeforeEach {
        $removed = @(@{ Group = 'Revit'; Year = 2025 })
        $package = [pscustomobject]@{ Group = 'Revit'; Year = 2025; InstallLocation = 'D:\Program Files\Autodesk\\Revit 2025\' }
        Mock Test-AdskPath { $Path -eq 'D:\Program Files\Autodesk\Revit 2025' } -ModuleName AutodeskCleaner
    }

    It 'finds one normalized install folder on D with the required metadata' {
        $items = @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package, $package))
        $items.Count | Should Be 1
        $items[0].Path | Should BeExactly 'D:\Program Files\Autodesk\Revit 2025'
        $items[0].Kind | Should BeExactly 'Folder'
        $items[0].Reason | Should BeExactly 'install location of removed package'
        $items[0].UserData | Should Be $false
    }

    It 'ignores protected install roots without throwing' {
        $package.InstallLocation = 'D:\Program Files\Autodesk\\'
        @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package)).Count | Should Be 0
    }

    It 'requires both the removed group-year and an existing folder' {
        @(Get-AdskRemnant -RemovedPackages @($package)).Count | Should Be 0
        Mock Test-AdskPath { $false } -ModuleName AutodeskCleaner
        @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package)).Count | Should Be 0
    }

    It 'protects equal, parent and child locations of remaining packages' {
        foreach ($location in @('D:\Program Files\Autodesk\Revit 2025\',
            'D:\Program Files\Autodesk\\Revit 2025\AddIns\X\')) {
            $remaining = @([pscustomobject]@{ Group = 'Other'; Year = $null; InstallLocation = $location })
            @(Get-AdskRemnant -Packages $remaining -Removed $removed -RemovedPackages @($package)).Count | Should Be 0
        }
    }

    It 'protects a child of a remaining product folder' {
        $package.InstallLocation = 'D:\Program Files\Autodesk\Revit 2025\Product'
        Mock Test-AdskPath { $Path -eq 'D:\Program Files\Autodesk\Revit 2025\Product' } -ModuleName AutodeskCleaner
        $remaining = @([pscustomobject]@{ Group = 'Other'; Year = $null; InstallLocation = 'D:\Program Files\Autodesk\Revit 2025\' })
        @(Get-AdskRemnant -Packages $remaining -Removed $removed -RemovedPackages @($package)).Count | Should Be 0
    }

    It 'ignores protected remaining roots when selecting a removed product folder' {
        foreach ($location in @('D:\Program Files\Autodesk', 'D:\Program Files\Autodesk\\', 'D:\Program Files')) {
            $remaining = @([pscustomobject]@{ Group = 'Revit'; Year = 2024; InstallLocation = $location })
            $items = @(Get-AdskRemnant -Packages $remaining -Removed $removed -RemovedPackages @($package))
            $items.Count | Should Be 1
            $items[0].Path | Should BeExactly 'D:\Program Files\Autodesk\Revit 2025'
        }
    }

    It 'does not confuse neighboring product folder names' {
        $remaining = @([pscustomobject]@{ Group = 'Other'; Year = $null; InstallLocation = 'D:\Program Files\Autodesk\Revit 20250' })
        @(Get-AdskRemnant -Packages $remaining -Removed $removed -RemovedPackages @($package)).Count | Should Be 1
    }

    It 'deduplicates normalized catalog and package locations' {
        Mock Get-AdskRemnantCatalog { [pscustomobject]@{ Path = 'D:\Program Files\Autodesk\\Revit 2025\'; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false; Reason = 'Product fully uninstalled' } } -ModuleName AutodeskCleaner
        @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package)).Count | Should Be 1
    }

    It 'accepts a normalized catalog folder when previewing quarantine' {
        Mock Get-AdskRemnantCatalog { [pscustomobject]@{ Path = 'D:\Program Files\Autodesk\\Revit 2025\'; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false; Reason = 'Product fully uninstalled' } } -ModuleName AutodeskCleaner
        $items = @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package))
        $result = Invoke-AdskRemnantCleanup -Remnant $items -RunId t6 -DryRun
        $result.Action | Should BeExactly 'DryRun'
        $result.Destination | Should BeExactly 'D:\AutodeskCleaner.Quarantine\t6\Program Files\Autodesk\Revit 2025'
        [string]$result.Error | Should BeExactly ''
    }

    It 'previews quarantine on the product drive without any write' {
        $items = @(Get-AdskRemnant -Removed $removed -RemovedPackages @($package))
        Mock New-AdskDirectory {} -ModuleName AutodeskCleaner
        Mock Move-AdskItem {} -ModuleName AutodeskCleaner
        $result = Invoke-AdskRemnantCleanup -Remnant $items -RunId t6 -DryRun
        $result.Action | Should BeExactly 'DryRun'
        $result.Destination | Should BeExactly 'D:\AutodeskCleaner.Quarantine\t6\Program Files\Autodesk\Revit 2025'
        Assert-MockCalled New-AdskDirectory -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
        Assert-MockCalled Move-AdskItem -ModuleName AutodeskCleaner -Scope It -Times 0 -Exactly
    }
}

Describe 'T6 third-party and developer-tool remnants' {
    BeforeEach {
        $removed = @(@{ Group = 'Revit'; Year = 2025 })
        $removedPackage = [pscustomobject]@{ Group = 'Revit'; Year = 2025; InstallLocation = 'D:\Program Files\Autodesk\Revit 2025\' }
        $remainingPackage = [pscustomobject]@{ Group = 'Revit'; Year = 2025; ThirdParty = $true; Role = 'Main'; InstallLocation = 'C:\Program Files\NREL\X\' }
        Mock Test-AdskPath { $true } -ModuleName AutodeskCleaner
        Mock Get-AdskRemnantCatalog {
            [pscustomobject]@{ Path = "$env:ProgramData\Autodesk\RVT 2025"; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false; Reason = 'Product fully uninstalled' }
        } -ModuleName AutodeskCleaner
    }

    It 'allows catalog and install-location remnants when a third-party package of the same group-year remains' {
        $items = @(Get-AdskRemnant -Packages @($remainingPackage) -Removed $removed -RemovedPackages @($removedPackage))
        $items.Count | Should Be 2
        @($items | Where-Object { $_.Path -eq "$env:ProgramData\Autodesk\RVT 2025" }).Count | Should Be 1
        @($items | Where-Object { $_.Path -eq 'D:\Program Files\Autodesk\Revit 2025' }).Count | Should Be 1
    }

    It 'also ignores a DevTool without a third-party publisher for the group-year gate' {
        $remainingPackage.ThirdParty = $false
        $remainingPackage.Role = 'DevTool'
        $items = @(Get-AdskRemnant -Packages @($remainingPackage) -Removed $removed -RemovedPackages @($removedPackage))
        $items.Count | Should Be 2
    }

    It 'still blocks the group-year when an Autodesk product remains' {
        $remainingPackage.ThirdParty = $false
        @(Get-AdskRemnant -Packages @($remainingPackage) -Removed $removed -RemovedPackages @($removedPackage)).Count | Should Be 0
    }

    It 'protects third-party and DevTool folders and their parents and children in both candidate sources' {
        Mock Get-AdskRemnantCatalog {
            foreach ($path in @('C:\Program Files\NREL\X', 'C:\Program Files\NREL', 'C:\Program Files\NREL\X\AddIns')) {
                [pscustomobject]@{ Path = $path; Kind = 'Folder'; Group = 'Revit'; Year = 2025; UserData = $false; Reason = 'Product fully uninstalled' }
            }
        } -ModuleName AutodeskCleaner
        foreach ($role in @('Main', 'DevTool')) {
            $remainingPackage.ThirdParty = $role -eq 'Main'
            $remainingPackage.Role = $role
            foreach ($path in @('C:\Program Files\NREL\X', 'C:\Program Files\NREL', 'C:\Program Files\NREL\X\AddIns')) {
                $removedPackage.InstallLocation = $path
                @(Get-AdskRemnant -Packages @($remainingPackage) -Removed $removed -RemovedPackages @($removedPackage)).Count | Should Be 0
            }
        }
    }
}
