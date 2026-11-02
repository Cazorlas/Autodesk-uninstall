Import-Module (Join-Path $PSScriptRoot '../src/AutodeskCleaner.psm1') -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'Removal plan contract' {
    BeforeEach {
        $packages = @(Get-FixtureRows | ConvertTo-AdskPackage)
    }

    It '11 selects Revit 2025 only, orders addons before main and hidden children after main' {
        $plan = New-AdskRemovalPlan -Packages $packages -Group Revit -Year 2025
        $main = $plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Autodesk Revit 2025' }
        $addon = $plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Carbon Insights for Revit 2025' }
        $main.Action | Should BeExactly 'Uninstall'
        $addon.Action | Should BeExactly 'Uninstall'
        ($addon.Order -lt $main.Order) | Should Be $true
        foreach ($name in @('Revit 2025', 'Batch Print for Autodesk Revit 2025')) {
            $child = @($plan.Steps | Where-Object { $_.Package.DisplayName -eq $name })
            $child.Count | Should Be 1
            $child[0].Action | Should BeExactly 'UninstallIfPresent'
            ($child[0].Order -gt $main.Order) | Should Be $true
        }
        @($plan.Steps | Where-Object { $_.Package.Year -ne 2025 }).Count | Should Be 0
        @($plan.Steps | Where-Object { $_.Package.Group -ne 'Revit' }).Count | Should Be 0
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Generative Design For Revit' }).Count | Should Be 0
        $plan.SharedRemoved | Should Be $false
        @($plan.Kept | Where-Object { $_.Package.DisplayName -eq 'Autodesk Access 2.24.0.516' -and $_.Reason }).Count | Should Be 1
    }

    It '12 selects every Revit year and year-less members while keeping other groups' {
        $plan = New-AdskRemovalPlan -Packages $packages -Group Revit
        foreach ($year in 2023..2026) {
            @($plan.Steps | Where-Object { $_.Package.DisplayName -eq "Autodesk Revit $year" }).Count | Should Be 1
        }
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Generative Design For Revit' }).Count | Should Be 4
        @($plan.Steps | Where-Object { $_.Package.Group -ne 'Revit' }).Count | Should Be 0
        @($plan.Kept | Where-Object { $_.Package.Group -eq 'AutoCAD' }).Count | Should BeGreaterThan 0
        @($plan.Kept | Where-Object { $_.Package.Group -eq 'Navisworks' }).Count | Should BeGreaterThan 0
        $plan.SharedRemoved | Should Be $false
    }

    It '13 selects All with material and shared packages after products and infrastructure last' {
        $plan = New-AdskRemovalPlan -Packages $packages -All
        $plan.SharedRemoved | Should Be $true
        @($plan.Steps | Where-Object { $_.Package.ThirdParty -or $_.Package.Role -eq 'DevTool' }).Count | Should Be 0
        @($plan.Skipped | Where-Object { $_.Package.DisplayName -eq 'ACAD Private' -and $_.Reason }).Count | Should Be 1
        $products = @($plan.Steps | Where-Object { $_.Package.Group -notin @('Shared', 'Infrastructure') })
        $material = @($plan.Steps | Where-Object { $_.Package.Role -eq 'MaterialLibrary' })
        $shared = @($plan.Steps | Where-Object { $_.Package.Group -eq 'Shared' -and $_.Package.Role -ne 'MaterialLibrary' })
        $infrastructure = @($plan.Steps | Where-Object { $_.Package.Group -eq 'Infrastructure' })
        $material.Count | Should BeGreaterThan 0
        $shared.Count | Should BeGreaterThan 0
        ($material[0].Order -gt $products[-1].Order) | Should Be $true
        ($shared[0].Order -gt $material[-1].Order) | Should Be $true
        ($infrastructure[0].Order -gt $shared[-1].Order) | Should Be $true
        $access = $infrastructure | Where-Object { $_.Package.DisplayName -like 'Autodesk Access*' }
        $genuine = $infrastructure | Where-Object { $_.Package.DisplayName -eq 'Autodesk Genuine Service' }
        ($access.Order -lt $genuine.Order) | Should Be $true
        ($plan.Steps.Order -join ',') | Should BeExactly ((1..$plan.Steps.Count) -join ',')
    }

    It '14 includes pyRevit and RevitLookup only with IncludeThirdParty' {
        $plan = New-AdskRemovalPlan -Packages $packages -All -IncludeThirdParty
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'pyRevit version 6.5.3.26176' }).Count | Should Be 1
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'RevitLookup' }).Count | Should Be 2
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Revit 2027 SDK' }).Count | Should Be 1
    }

    It '15 computes shared eligibility from every remaining Autodesk product' {
        $plan = New-AdskRemovalPlan -Packages $packages -Group Revit,AutoCAD,Navisworks
        $selectedIds = @($plan.Steps | ForEach-Object { $_.Package.Id }) + @($plan.Skipped | ForEach-Object { $_.Package.Id })
        $remaining = @($packages | Where-Object {
            $_.Group -notin @('Shared', 'Infrastructure') -and $_.Role -ne 'DevTool' -and
            -not $_.ThirdParty -and $selectedIds -notcontains $_.Id
        })
        $remaining.Count | Should Be 0
        $plan.SharedRemoved | Should Be ($remaining.Count -eq 0)
        $plan.SharedRemoved | Should Be $true
        @($plan.Steps | Where-Object { $_.Package.Group -eq 'Shared' }).Count | Should BeGreaterThan 0
        @($plan.Steps | Where-Object { $_.Package.Group -eq 'Infrastructure' }).Count | Should BeGreaterThan 0
    }

    It 'keeps year-less members until every eligible year is explicitly selected' {
        $plan = New-AdskRemovalPlan -Packages $packages -Group Revit -Year 2023,2024,2025,2026
        @($plan.Steps | Where-Object { $_.Package.DisplayName -eq 'Generative Design For Revit' }).Count | Should Be 4
    }

    It 'protects shared components when an unselected Autodesk product is added' {
        $row = @(Get-FixtureRows)[0]
        $row.KeyName = 'new-inventor'
        $row.DisplayName = 'Autodesk Inventor 2025'
        $packages += ConvertTo-AdskPackage $row
        $plan = New-AdskRemovalPlan -Packages $packages -Group Revit,AutoCAD,Navisworks
        $plan.SharedRemoved | Should Be $false
        @($plan.Steps | Where-Object { $_.Package.Group -in @('Shared', 'Infrastructure') }).Count | Should Be 0
    }

    It 'does not let explicit Infrastructure or Shared groups bypass retained products' {
        $plan = New-AdskRemovalPlan -Packages $packages -Group Shared,Infrastructure
        $plan.Steps.Count | Should Be 0
        $plan.SharedRemoved | Should Be $false
    }

    It 'requires an explicit scope and rejects contradictory All filters' {
        { New-AdskRemovalPlan -Packages $packages } | Should Throw
        { New-AdskRemovalPlan -Packages $packages -All -Group Revit } | Should Throw
        { New-AdskRemovalPlan -Packages $packages -All -Year 2025 } | Should Throw
    }
}
