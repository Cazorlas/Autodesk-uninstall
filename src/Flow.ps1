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
        $plan.$section | Select-Object @{n='Product';e={$_.Package.DisplayName}}, Reason | Format-Table -AutoSize | Out-Host
    }
    Write-Host "SharedRemoved: $($plan.SharedRemoved) | DryRun: $(-not $Execute)"
    $result = $null
    $remnants = @()
    $cleanup = @()
    $aborted = $false
    $running = @($plan.Steps.Package.InstallLocation | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique | ForEach-Object { Get-AdskProcessByPath -Path ([Environment]::ExpandEnvironmentVariables($_)) } | Sort-Object Id -Unique)
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
        $removed = @($plan.Steps.Package | Select-Object Group, Year -Unique | Where-Object {
            $pair = $_
            -not @($result.FailedGroups | Where-Object { $_.Group -eq $pair.Group -and $_.Year -eq $pair.Year }).Count
        })
        # A timed-out installer may still be running; do not move its files.
        if (-not $result.Stopped) {
            $infra = $plan.SharedRemoved -and @($result.FailedGroups).Count -eq 0 -and $remaining.Count -eq 0
            $remnants = @(Get-AdskRemnant -Packages $remaining -Removed $removed -IncludeUserData:$IncludeUserData -InfrastructureRemoved:$infra)
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
