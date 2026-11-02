param(
    [switch]$Scan, [switch]$Readiness, [string[]]$Group, [string[]]$Year,
    [switch]$All, [switch]$Execute, [switch]$IncludeUserData,
    [switch]$IncludeThirdParty, [switch]$Yes
)
# -File (the .bat / npx launcher) passes "Revit,AutoCAD" and "2024,2025" as one string each.
$Group = @($Group | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
$Year = [int[]]@($Year | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$readOnlyMode = ($Scan -or $Readiness) -and -not $Execute -and -not $Group -and -not $All
if (-not $readOnlyMode -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Cần quyền quản trị để đọc đầy đủ đăng ký, chạy bộ gỡ và sao lưu an toàn. Hãy mở Start-AutodeskCleaner.bat và chấp nhận UAC.'
    exit 1
}
Import-Module (Join-Path $PSScriptRoot 'src/AutodeskCleaner.psm1') -Force
$script:preview = -not $Execute
$script:logRoot = "$env:ProgramData\AutodeskCleaner\Logs"
$script:confirmAction = {
    param($message)
    if ($Yes) { return $true }
    (Read-Host "$message (y/N)") -eq 'y'
}
function Show-Inventory {
    @(Get-AdskPackage) | Group-Object Group, Year | ForEach-Object {
        [pscustomobject]@{ Group = $_.Group[0].Group; Year = $_.Group[0].Year
            Products = (@($_.Group | Where-Object { -not $_.Hidden -and $_.Role -ne 'DevTool' } |
                Select-Object -ExpandProperty DisplayName -Unique) | Select-Object -First 4) -join '; '
            Packages = $_.Count }
    } | Sort-Object Group, Year | Format-Table -AutoSize | Out-Host
}
function Invoke-Readiness {
    $findings = @(Test-AdskReinstallReadiness)
    if (-not $findings.Count) { Write-Host 'Không phát hiện mục chặn trong các kiểm tra hiện có.' }
    foreach ($finding in $findings) {
        $finding | Format-List Severity, Code, Message, Target, Fix | Out-Host
        if ($finding.Code -in @('OldToolRunOnce', 'IfeoDebugger', 'OdisLock', 'OrphanArp')) {
            if (& $script:confirmAction 'Sửa?') {
                if (-not $script:preview -and (Read-Host 'Nhập GO để sửa thật') -cne 'GO') { Write-Host 'Đã hủy sửa.'; continue }
                Repair-AdskReinstallBlocker -Finding $finding -DryRun:$script:preview | Format-List * | Out-Host
            }
        }
    }
    if (@($findings | Where-Object Code -eq 'PendingReboot').Count) { Write-Host 'Khởi động lại máy trước khi cài lại' }
}
function Invoke-ConsoleAction {
    param([scriptblock]$Action)
    $logDir = Join-Path $script:logRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    $null = New-Item -Path $logDir -ItemType Directory -Force
    $null = Start-Transcript -LiteralPath (Join-Path $logDir ('console-' + [guid]::NewGuid().ToString('N') + '.txt'))
    try { & $Action } finally { $null = Stop-Transcript }
}
function Invoke-SelectedFlow {
    param([string[]]$SelectedGroup, [int[]]$SelectedYear, [switch]$Everything)
    if ($Everything -and -not (& $script:confirmAction 'Xác nhận lần hai: chọn gỡ toàn bộ Autodesk và thành phần dùng chung đủ điều kiện?')) { return }
    if (-not $script:preview -and (Read-Host 'Nhập GO để chạy thật') -cne 'GO') { Write-Host 'Đã hủy.'; return }
    $summary = Invoke-AdskCleanerFlow -Group $SelectedGroup -Year $SelectedYear -All:$Everything -Execute:(-not $script:preview) -IncludeUserData:$IncludeUserData -IncludeThirdParty:$IncludeThirdParty -LogRoot $script:logRoot -Confirm $script:confirmAction
    Write-Host "Báo cáo: $($summary.LogDir)\summary.txt"
    if ($summary.RebootRequired) { Write-Host 'Khởi động lại máy trước khi cài lại' }
}
function Select-Numbers {
    param([object[]]$Items, [string]$Prompt)
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $Items[$i]) }
    $text = Read-Host "$Prompt (số cách nhau bằng dấu phẩy; Enter để hủy)"
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $numbers = @($text -split '[,;\s]+' | Where-Object { $_ })
    foreach ($number in $numbers) {
        $index = 0
        if (-not [int]::TryParse($number, [ref]$index) -or $index -lt 1 -or $index -gt $Items.Count) { throw 'Lựa chọn không hợp lệ.' }
    }
    $numbers | ForEach-Object { $Items[[int]$_ - 1] } | Select-Object -Unique
}
try {
    if ($PSBoundParameters.Count) {
        if (($Scan -and $Readiness) -or (($Scan -or $Readiness) -and ($All -or $Group -or $Year)) -or ($All -and ($Group -or $Year))) { throw 'Không kết hợp các chế độ quét, kiểm tra, gỡ toàn bộ và gỡ theo nhóm.' }
        & {
            if ($Scan) { Invoke-ConsoleAction { Show-Inventory } }
            elseif ($Readiness) { Invoke-ConsoleAction { Invoke-Readiness } }
            elseif ($All -or $Group) { Invoke-SelectedFlow -SelectedGroup $Group -SelectedYear $Year -Everything:$All }
            else { throw 'Hãy chọn -Scan, -Readiness, -Group hoặc -All.' }
        }
        exit 0
    }
    while ($true) {
        Write-Host "`nAutodesk Cleaner | DryRun: $(if ($script:preview) { 'ON - xem trước' } else { 'OFF - chạy thật' })"
        Write-Host '1 Quét sản phẩm'
        Write-Host '2 Kiểm tra sẵn sàng cài lại'
        Write-Host '3 Gỡ theo nhóm'
        Write-Host '4 Gỡ sạch toàn bộ Autodesk'
        Write-Host '5 Bật/tắt chế độ xem trước (DryRun)'
        Write-Host '6 Mở thư mục log / quarantine'
        Write-Host '0 Thoát'
        $choice = Read-Host 'Chọn'
        if ($choice -eq '0') { break }
        try {
            switch ($choice) {
                '1' { Invoke-ConsoleAction { Show-Inventory } }
                '2' { Invoke-ConsoleAction { Invoke-Readiness } }
                '3' {
                    $packages = @(Get-AdskPackage)
                    $groups = @($packages.Group | Where-Object { $_ -notin @('Shared', 'Infrastructure') } | Sort-Object -Unique)
                    if (-not $groups.Count) { Write-Host 'Không tìm thấy nhóm sản phẩm.'; continue }
                    $selected = @(Select-Numbers -Items $groups -Prompt 'Chọn nhóm')
                    if (-not $selected.Count) { continue }
                    $years = @($packages | Where-Object { $selected -contains $_.Group -and $null -ne $_.Year } | Select-Object -ExpandProperty Year | Sort-Object -Unique)
                    $selectedYears = @()
                    if ($years.Count) {
                        $selectedYears = @(Select-Numbers -Items $years -Prompt 'Chọn năm (chọn mọi số nếu muốn mọi năm)')
                        if (-not $selectedYears.Count) { continue }
                    }
                    Invoke-SelectedFlow -SelectedGroup $selected -SelectedYear $selectedYears
                }
                '4' {
                    if (& $script:confirmAction 'Chọn gỡ sạch toàn bộ Autodesk?') { Invoke-SelectedFlow -Everything }
                }
                '5' { $script:preview = -not $script:preview }
                '6' {
                    Write-Host "Log: $script:logRoot"
                    if (Test-Path -LiteralPath $script:logRoot) { Start-Process explorer.exe -ArgumentList ('"' + $script:logRoot + '"') }
                    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                        $path = Join-Path $_.Root 'AutodeskCleaner.Quarantine'
                        if (Test-Path -LiteralPath $path) { Write-Host "Quarantine: $path"; Start-Process explorer.exe -ArgumentList ('"' + $path + '"') }
                    }
                }
                default { Write-Host 'Chọn một số từ 0 đến 6.' }
            }
        } catch { Write-Host "Lỗi: $($_.Exception.Message)" }
    }
} catch { Write-Host "Lỗi: $($_.Exception.Message)"; exit 1 }
