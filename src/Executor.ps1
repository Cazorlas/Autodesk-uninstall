function Get-AdskUninstallCommand {
    param(
        [Parameter(Mandatory = $true)][psobject]$Package,
        [string]$LogFile = 'uninstall.log'
    )
    switch ($Package.Kind) {
        'MSI' {
            return @{ FilePath = 'msiexec.exe'; ArgumentList = '/x {0} /qn /norestart REBOOT=ReallySuppress /L*v "{1}"' -f $Package.ProductCode, $LogFile }
        }
        'ODIS' {
            $arguments = [string]$Package.Arguments
            if ($arguments -notmatch '(?i)(?:^|\s)-q(?=\s|$)') { $arguments = $arguments.TrimEnd() + ' -q' }
            return @{ FilePath = $Package.Exe; ArgumentList = $arguments }
        }
        'Helper' { return @{ FilePath = $Package.Exe; ArgumentList = '-q' } }
        'Exe' {
            if ($Package.HasQuietCommand) {
                return @{ FilePath = $Package.Exe; ArgumentList = [string]$Package.Arguments }
            }
        }
    }
    return $null
}

function Invoke-AdskRemovalPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][psobject]$Plan,
        [Parameter(Mandatory = $true)][string]$LogDir,
        [switch]$DryRun,
        [ValidateRange(0.001, 35791)][double]$TimeoutMinutes = 60
    )
    # LogDir must already exist: run.log is the executor's only file write.
    $runLog = Join-Path $LogDir 'run.log'
    $results = @()
    $failedGroups = @()
    $rebootRequired = $false
    $stopped = $false
    foreach ($step in @($Plan.Steps | Sort-Object Order)) {
        $package = $step.Package
        $code = [string]$package.ProductCode
        if (-not $code) { $code = 'uninstall' }
        $code = $code -replace '[^a-zA-Z0-9{}-]', '_'
        $logFile = Join-Path $LogDir ('{0}-{1}.log' -f $step.Order, $code)
        $command = Get-AdskUninstallCommand -Package $package -LogFile $logFile
        $result = [pscustomobject]@{
            Step = $step; Status = $null; ExitCode = $null
            Command = $command; LogFile = $logFile; Reason = $null
        }
        $groupFailed = @($failedGroups | Where-Object { $_.Group -eq $package.Group -and $_.Year -eq $package.Year }).Count -gt 0
        if ($DryRun) { $result.Status = 'DryRun' }
        elseif ($stopped) { $result.Status = 'Skipped'; $result.Reason = 'run stopped after timeout' }
        elseif ($groupFailed -or ($failedGroups.Count -gt 0 -and $package.Group -in @('Shared', 'Infrastructure'))) {
            $result.Status = 'Skipped'; $result.Reason = 'earlier step failed'
        } elseif ($null -eq $command) {
            $result.Status = 'Skipped'; $result.Reason = 'no silent uninstall'
        } else {
            try {
                if ($step.Action -eq 'UninstallIfPresent') {
                    $present = @(Get-AdskRegistryRows | Where-Object {
                        ('{0}\{1}\{2}' -f $_.Hive, $_.View, $_.KeyName) -eq $package.Id
                    }).Count -gt 0
                    if (-not $present) { $result.Status = 'AlreadyGone' }
                }
                if (-not $result.Status) {
                    $timer = [System.Diagnostics.Stopwatch]::StartNew()
                    $limit = $TimeoutMinutes * 60
                    while (Test-AdskMsiBusy) {
                        $remaining = $limit - $timer.Elapsed.TotalSeconds
                        if ($remaining -le 0) { break }
                        Start-Sleep -Milliseconds ([int][Math]::Min(1000, [Math]::Ceiling($remaining * 1000)))
                    }
                    $remaining = $limit - $timer.Elapsed.TotalSeconds
                    if ($remaining -le 0) {
                        $result.Status = 'TimedOut'
                    } else {
                        $process = Invoke-AdskProcess -FilePath $command.FilePath -Arguments $command.ArgumentList -TimeoutSeconds ([int][Math]::Ceiling($remaining))
                        $result.ExitCode = $process.ExitCode
                        if ($process.TimedOut) { $result.Status = 'TimedOut' }
                        elseif ($process.ExitCode -in @(0, 3010, 1641)) {
                            $result.Status = 'Succeeded'
                            if ($process.ExitCode -in @(3010, 1641)) { $rebootRequired = $true }
                        } elseif ($process.ExitCode -in @(1605, 1614)) { $result.Status = 'AlreadyGone' }
                        else { $result.Status = 'Failed' }
                    }
                }
            } catch {
                # A launch/read failure must protect the same dependants as a failed uninstall.
                $result.Status = 'Failed'
                $result.Reason = $_.Exception.Message
            }
            if ($result.Status -eq 'TimedOut') { $stopped = $true }
            if ($result.Status -eq 'Failed') {
                $failedGroups += [pscustomobject]@{ Group = $package.Group; Year = $package.Year }
            }
        }
        Add-Content -LiteralPath $runLog -Value ('{0}: {1} | {2} | {3} {4} {5} | {6} {7}' -f $step.Order, $package.DisplayName, $package.Id, $result.Status, $result.ExitCode, $result.Reason, $(if ($result.Command) { $result.Command.FilePath } else { '' }), $(if ($result.Command) { $result.Command.ArgumentList } else { '' })) -Encoding UTF8 -ErrorAction Stop
        $results += $result
    }
    [pscustomobject]@{ Steps = $results; RebootRequired = $rebootRequired; FailedGroups = $failedGroups; Stopped = $stopped }
}
