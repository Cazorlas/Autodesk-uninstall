function Invoke-AdskCleanerFlow {
    param(
        [string[]]$Group,
        [int[]]$Year,
        [switch]$All,
        [switch]$Execute,
        [switch]$IncludeUserData,
        [switch]$IncludeThirdParty,
        [string]$LogRoot = "$env:ProgramData\AutodeskCleaner\Logs",
        [scriptblock]$Confirm = { param($message) (Read-Host "$message (y/N)") -eq 'y' }
    )
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logDir = Join-Path $LogRoot $runId
    $null = New-AdskDirectory -Path $logDir
    $null = Start-Transcript -LiteralPath (Join-Path $logDir ('console-' + [guid]::NewGuid().ToString('N') + '.txt')) -ErrorAction Stop
    try {
    $packages = @(Get-AdskPackage)
    $planOptions = @{ Packages = $packages; All = $All; IncludeThirdParty = $IncludeThirdParty }
    if ($Group) { $planOptions.Group = $Group }
    if ($Year) { $planOptions.Year = $Year }
    $plan = New-AdskRemovalPlan @planOptions
    Write-Host 'Kế hoạch gỡ cài đặt (Steps):'
    $plan.Steps | Select-Object Order, @{n='Product';e={$_.Package.DisplayName}}, Action, Reason | Format-Table -AutoSize | Out-Host
    foreach ($section in @('Kept', 'Skipped')) {
        Write-Host "${section}:"
        foreach ($entry in $plan.$section) {
            Write-Host ('{0} | {1}' -f $entry.Package.DisplayName, $entry.Reason)
        }
    }
    Write-Host "SharedRemoved: $($plan.SharedRemoved) | DryRun: $(-not $Execute)"
    $result = $null
    $remnants = @()
    $cleanup = @()
    $aborted = $false
    $selectedNoCommand = @($plan.Skipped | Where-Object { $_.Package.Kind -eq 'None' } | ForEach-Object { $_.Package })
    $selectedPackages = @($plan.Steps | ForEach-Object { $_.Package }) + $selectedNoCommand
    $probePaths = @($selectedPackages.InstallLocation | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { ConvertTo-AdskNormalizedPath -Path $_ } | Sort-Object -Unique | Where-Object {
            $candidate = $_
            $inUse = @(foreach ($kept in $plan.Kept) {
                if (Test-AdskProtectedRoot -Path $kept.Package.InstallLocation) { continue }
                $installed = ConvertTo-AdskNormalizedPath -Path $kept.Package.InstallLocation
                if ($installed -eq $candidate -or $installed.StartsWith($candidate + '\', [StringComparison]::OrdinalIgnoreCase)) { $kept }
            }).Count -gt 0
            -not (Test-AdskProtectedRoot -Path $candidate) -and -not $inUse
        })
    $running = @($probePaths | ForEach-Object { Get-AdskProcessByPath -Path $_ } | Sort-Object Id -Unique)
    if ($running.Count) {
        $running | Select-Object Id, Path | Format-Table -AutoSize | Out-Host
        if (-not (& $Confirm 'Đóng các tiến trình trong thư mục sản phẩm được chọn?')) {
            Write-Host 'Đã hủy; chưa gỡ sản phẩm nào.'
            $aborted = $true
        } elseif ($Execute) {
            foreach ($process in $running) { Stop-AdskProcess -Id $process.Id }
        }
    }
    if (-not $aborted) {
        $result = Invoke-AdskRemovalPlan -Plan $plan -LogDir $logDir -DryRun:(-not $Execute)
        $remaining = @(Get-AdskPackage)
        $removed = @($selectedPackages | Select-Object Group, Year -Unique | Where-Object {
            $pair = $_
            -not @($result.FailedGroups | Where-Object { $_.Group -eq $pair.Group -and $_.Year -eq $pair.Year }).Count
        })
        $removedPackages = @()
        $removedNoCommand = @($selectedNoCommand | Where-Object {
            $package = $_
            $groupSucceeded = @($removed | Where-Object { $_.Group -eq $package.Group -and $_.Year -eq $package.Year }).Count -gt 0
            $groupSucceeded -and (-not $Execute -or @($remaining | Where-Object { $_.Id -eq $package.Id }).Count -eq 0)
        })
        if (-not $Execute) {
            $removedPackages = @($plan.Steps.Package) + $removedNoCommand
            # Preview the inventory after the planned removals, without changing the host.
            $remaining = @($plan.Kept | ForEach-Object { $_.Package }) + @($plan.Skipped | Where-Object {
                $removedNoCommand.Id -notcontains $_.Package.Id
            } | ForEach-Object { $_.Package })
        } else {
            $removedPackages = @($result.Steps | Where-Object {
                $stepResult = $_
                $package = $stepResult.Step.Package
                $stepResult.Status -in @('Succeeded', 'AlreadyGone') -and
                    @($removed | Where-Object { $_.Group -eq $package.Group -and $_.Year -eq $package.Year }).Count -gt 0
            } | ForEach-Object { $_.Step.Package }) + $removedNoCommand
        }
        # A timed-out installer may still be running; do not move its files.
        if (-not $result.Stopped) {
            $infra = $plan.SharedRemoved -and @($result.FailedGroups).Count -eq 0 -and $remaining.Count -eq 0
            $remnants = @(Get-AdskRemnant -Packages $remaining -Removed $removed -RemovedPackages $removedPackages -IncludeUserData:$IncludeUserData -InfrastructureRemoved:$infra)
            Write-Host 'Phần dư có thể chuyển vào quarantine:'
            $remnants | Format-Table Path, Kind, Group, Year, UserData -AutoSize | Out-Host
            if ($remnants.Count -and (& $Confirm 'Chuyển phần dư đã liệt kê vào quarantine?')) {
                $cleanup = @(Invoke-AdskRemnantCleanup -Remnant $remnants -RunId $runId -DryRun:(-not $Execute))
                $cleanup | Format-Table -AutoSize | Out-Host
            }
        }
    }
    $findings = @(Test-AdskReinstallReadiness)
    Write-Host 'Kiểm tra sẵn sàng cài lại:'
    $findings | Format-List Severity, Code, Message, Target, Fix | Out-Host
    $summary = [pscustomobject]@{
        RunId = $runId; LogDir = $logDir; Plan = $plan; Result = $result
        Remnants = $remnants; Cleanup = $cleanup; Findings = $findings
        RebootRequired = [bool]($result.RebootRequired -or @($findings | Where-Object Code -eq 'PendingReboot').Count)
    }
    $report = @(
        "RunId: $runId", "LogDir: $logDir", "DryRun: $(-not $Execute)", "Aborted: $aborted",
        "RebootRequired: $($summary.RebootRequired)", "SharedRemoved: $($plan.SharedRemoved)",
        'Steps:', ($plan.Steps | Select-Object Order, @{n='Product';e={$_.Package.DisplayName}}, Action, Reason | Format-Table -AutoSize | Out-String -Width 240),
        'Kept:', ($plan.Kept | Format-List * | Out-String -Width 240),
        'Skipped:', ($plan.Skipped | Format-List * | Out-String -Width 240),
        'Result:', ($result | Format-List * | Out-String -Width 240),
        'Remnants:', ($remnants | Format-List * | Out-String -Width 240),
        'Cleanup:', ($cleanup | Format-List * | Out-String -Width 240),
        'Findings:', ($findings | Format-List * | Out-String -Width 240)
    )
    Set-Content -LiteralPath (Join-Path $logDir 'summary.txt') -Value $report -Encoding UTF8 -ErrorAction Stop
    $summary
    } finally { $null = Stop-Transcript }
}
