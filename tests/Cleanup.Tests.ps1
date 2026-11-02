Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force

Describe 'T3 remnant selection' {
    BeforeEach {
        Mock Test-AdskPath { $true } -ModuleName AutodeskCleaner
        $removed = @(@{ Group = 'Revit'; Year = 2025 })
        $remaining = @([pscustomobject]@{ Group = 'Revit'; Year = 2024; InstallLocation = $null })
    }

    It '01 selects only fully removed 2025 non-user paths while 2024 remains' {
        $items = @(Get-AdskRemnant -Packages $remaining -Removed $removed)
        $items.Count | Should Be 3
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
        @($catalog | Where-Object Group -eq Revit).Count | Should Be 8
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
