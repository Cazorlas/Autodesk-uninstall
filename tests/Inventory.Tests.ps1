Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'Inventory contract' {
    It '01 splits an unquoted executable path with spaces' {
        $result = Split-AdskCommand 'C:\Program Files\Autodesk\AdODIS\V1\Installer.exe -i uninstall --trigger_point system -m C:\ProgramData\x.xml'
        $result.Exe | Should BeExactly 'C:\Program Files\Autodesk\AdODIS\V1\Installer.exe'
        $result.Arguments | Should BeExactly '-i uninstall --trigger_point system -m C:\ProgramData\x.xml'
    }

    It '02 splits a quoted executable path' {
        $result = Split-AdskCommand '"C:\a b\un.exe" --mode unattended'
        $result.Exe | Should BeExactly 'C:\a b\un.exe'
        $result.Arguments | Should BeExactly '--mode unattended'
    }

    It '03 identifies MSI product codes for both X and I commands' {
        foreach ($verb in @('X', 'I')) {
            $row = @(Get-FixtureRows)[0]
            $row.UninstallString = "MsiExec.exe /$verb{11111111-2222-3333-4444-555555555555}"
            $row.QuietUninstallString = $null
            $result = ConvertTo-AdskPackage $row
            $result.Kind | Should BeExactly 'MSI'
            $result.ProductCode | Should BeExactly '{11111111-2222-3333-4444-555555555555}'
        }
    }

    It '04 identifies the visible Revit 2025 ODIS main bundle' {
        $package = Get-FixturePackage 'Autodesk Revit 2025'
        $package.Group | Should BeExactly 'Revit'
        $package.Year | Should Be 2025
        $package.Kind | Should BeExactly 'ODIS'
        $package.Role | Should BeExactly 'Main'
        $package.Hidden | Should Be $false
    }

    It '05 identifies the Revit 2024 update' {
        $package = Get-FixturePackage 'Autodesk Revit 2024.3.5 Update'
        $package.Group | Should BeExactly 'Revit'
        $package.Year | Should Be 2024
        $package.Role | Should BeExactly 'Update'
    }

    It '06 identifies a hidden Navisworks language pack' {
        $package = Get-FixturePackage 'Autodesk Navisworks Exporters 2024 - English Language Pack'
        $package.Group | Should BeExactly 'Navisworks'
        $package.Year | Should Be 2024
        $package.Role | Should BeExactly 'LanguagePack'
        $package.Hidden | Should Be $true
    }

    It '07 separates developer tools and third-party publishers' {
        $pyRevit = Get-FixturePackage 'pyRevit version 6.5.3.26176'
        $pyRevit.Role | Should BeExactly 'DevTool'
        $pyRevit.ThirdParty | Should Be $true
        ($null -eq $pyRevit.Year) | Should Be $true
        $sdk = Get-FixturePackage 'Revit 2027 SDK'
        $sdk.Role | Should BeExactly 'DevTool'
        $sdk.Year | Should Be 2027
        foreach ($lookup in @(Get-FixturePackage 'RevitLookup')) {
            $lookup.Role | Should BeExactly 'DevTool'
            if ($lookup.Publisher -eq 'Lookup Foundation') {
                $lookup.ThirdParty | Should Be $true
            } else {
                $lookup.Publisher | Should BeExactly 'Autodesk'
                $lookup.ThirdParty | Should Be $false
            }
        }
    }

    It '08 identifies Access infrastructure without deriving a year from its version' {
        $package = Get-FixturePackage 'Autodesk Access 2.24.0.516'
        $package.Group | Should BeExactly 'Infrastructure'
        $package.Role | Should BeExactly 'Infrastructure'
        ($null -eq $package.Year) | Should Be $true
    }

    It '09 identifies Material Library and RealDWG as shared packages' {
        $material = Get-FixturePackage 'Autodesk Material Library 2023'
        $material.Group | Should BeExactly 'Shared'
        $material.Role | Should BeExactly 'MaterialLibrary'
        $realDwg = Get-FixturePackage 'Autodesk RealDWG Shared 2024'
        $realDwg.Group | Should BeExactly 'Shared'
        $realDwg.Role | Should BeExactly 'Shared'
    }

    It '10 leaves a registration without a command as Kind None' {
        (Get-FixturePackage 'ACAD Private').Kind | Should BeExactly 'None'
    }

    It 'prefers QuietUninstallString and supports helper and generic exe commands' {
        $row = @(Get-FixtureRows)[0]
        $row.QuietUninstallString = '"C:\Vendor\AdskUninstallHelper.exe" -q'
        $package = ConvertTo-AdskPackage $row
        $package.Kind | Should BeExactly 'Helper'
        $package.Arguments | Should BeExactly '-q'
        $row.QuietUninstallString = '"C:\Vendor\uninstall.exe" --silent'
        (ConvertTo-AdskPackage $row).Kind | Should BeExactly 'Exe'
    }

    It 'uses the MSI key fallback only for a valid MSI command' {
        $row = @(Get-FixtureRows)[0]
        $row.UninstallString = 'MsiExec.exe /x'
        $row.QuietUninstallString = $null
        $package = ConvertTo-AdskPackage $row
        $package.Kind | Should BeExactly 'MSI'
        $package.ProductCode | Should BeExactly $row.KeyName
        $row.UninstallString = $null
        $package = ConvertTo-AdskPackage $row
        $package.Kind | Should BeExactly 'None'
        ($null -eq $package.ProductCode) | Should Be $true
    }

    It 'gets all 163 fixture rows through a mocked registry boundary without deduplicating names' {
        Mock Get-AdskRegistryRows {
            $moduleDir = Split-Path (Get-Module AutodeskCleaner).Path
            $rows = Get-Content -LiteralPath (Join-Path $moduleDir '../tests/fixtures/arp-host.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $rows
        } -ModuleName AutodeskCleaner
        $packages = @(Get-AdskPackage)
        $packages.Count | Should Be 163
        @($packages.Id | Select-Object -Unique).Count | Should Be 163
        @($packages | Where-Object { $_.DisplayName -eq 'Autodesk Navisworks Manage 2024' }).Count | Should Be 2
        Assert-MockCalled Get-AdskRegistryRows -ModuleName AutodeskCleaner -Times 1 -Exactly
    }

    It 'exports all ten side-effect wrappers without invoking any of them' {
        foreach ($name in @('Get-AdskRegistryRows', 'Invoke-AdskProcess', 'Test-AdskPath',
            'Move-AdskItem', 'Export-AdskRegistryKey', 'Remove-AdskRegistryKey', 'Get-AdskService',
            'Get-AdskProcessByPath', 'Stop-AdskProcess', 'Test-AdskMsiBusy')) {
            $command = Get-Command $name -Module AutodeskCleaner
            $command.Name | Should BeExactly $name
        }
    }
}
