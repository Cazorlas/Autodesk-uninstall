function ConvertTo-AdskPackedGuid {
    param([Parameter(Mandatory = $true)][string]$ProductCode)
    $guid = [guid]::Parse($ProductCode).ToString('N').ToUpperInvariant()
    $indices = @(7,6,5,4,3,2,1,0,11,10,9,8,15,14,13,12,17,16,19,18,21,20,23,22,25,24,27,26,29,28,31,30)
    -join ($indices | ForEach-Object { $guid[$_] })
}

function ConvertFrom-AdskPackedGuid {
    param([Parameter(Mandatory = $true)][string]$PackedGuid)
    if ($PackedGuid -notmatch '^[0-9a-f]{32}$') { throw 'Invalid MSI packed GUID.' }
    $indices = @(7,6,5,4,3,2,1,0,11,10,9,8,15,14,13,12,17,16,19,18,21,20,23,22,25,24,27,26,29,28,31,30)
    $text = -join ($indices | ForEach-Object { $PackedGuid[$_] })
    '{' + [guid]::ParseExact($text, 'N').ToString().ToUpperInvariant() + '}'
}

# Read-only source boundaries. Keep each source independently mockable.
function Get-AdskReadinessUserDataSids {
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
    if (Test-AdskPath $root) {
        Get-ChildItem -LiteralPath $root -ErrorAction Stop | ForEach-Object { $root + '\' + $_.PSChildName }
    }
}

function Get-AdskReadinessInstallerProducts {
    foreach ($root in @('HKLM:\SOFTWARE\Classes\Installer\Products', 'HKCU:\SOFTWARE\Microsoft\Installer\Products')) {
        if (-not (Test-AdskPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            if ($key.PSChildName -notmatch '^[0-9a-f]{32}$') { continue }
            $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            [pscustomobject]@{ ProductCode = ConvertFrom-AdskPackedGuid $key.PSChildName
                PackedGuid = $key.PSChildName; ProductName = $properties.ProductName; Path = $key.PSPath }
        }
    }
    foreach ($sid in Get-AdskReadinessUserDataSids) {
        $root = "$sid\Products"
        if (-not (Test-AdskPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction Stop) {
            if ($key.PSChildName -notmatch '^[0-9a-f]{32}$') { continue }
            $path = "$root\$($key.PSChildName)\InstallProperties"
            $properties = $null
            if (Test-AdskPath $path) { $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop }
            [pscustomobject]@{ ProductCode = ConvertFrom-AdskPackedGuid $key.PSChildName
                PackedGuid = $key.PSChildName; ProductName = $properties.DisplayName; Path = "$root\$($key.PSChildName)" }
        }
    }
}

function Get-AdskReadinessInstallProperties {
    param([string]$PackedGuid)
    if ($PackedGuid -notmatch '^[0-9a-f]{32}$') { throw 'Invalid MSI packed GUID.' }
    foreach ($sid in Get-AdskReadinessUserDataSids) {
        $path = "$sid\Products\$PackedGuid\InstallProperties"
        if (Test-AdskPath $path) { Get-ItemProperty -LiteralPath $path -ErrorAction Stop }
    }
}

function Get-AdskReadinessRunOnce {
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')) {
        if (-not (Test-AdskPath $path)) { continue }
        $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        if ($null -ne $properties.PSObject.Properties['AutodeskCleanup']) {
            [pscustomobject]@{ Path = $path; Name = 'AutodeskCleanup'; Value = $properties.AutodeskCleanup }
        }
    }
}

function Get-AdskReadinessIfeo {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options')) {
        foreach ($exe in @('Revit.exe', 'acad.exe', 'Roamer.exe', 'Freedom.exe', 'AdskLicensingService.exe',
            'AdskIdentityManager.exe', 'AdskAccessUIHost.exe', 'DesktopConnector.exe')) {
            $path = "$root\$exe"
            if (-not (Test-AdskPath $path)) { continue }
            $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            if ($null -ne $properties.PSObject.Properties['Debugger']) {
                [pscustomobject]@{ Path = $path; Name = 'Debugger'; Value = $properties.Debugger }
            }
        }
    }
}

function Get-AdskReadinessPendingReboot {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    if (Test-AdskPath $path) {
        $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        if (@($properties.PendingFileRenameOperations | Where-Object { $_ }).Count) { $path + '\PendingFileRenameOperations' }
    }
    foreach ($flag in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-AdskPath $flag) { $flag }
    }
}

function New-AdskReadinessFinding {
    param([string]$Severity, [string]$Code, [string]$Message, [string]$Target, [string]$Fix,
        [string]$ProductCode, [bool]$UninstallerMissing = $false)
    [pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message; Target = $Target; Fix = $Fix
        ProductCode = $ProductCode; UninstallerMissing = $UninstallerMissing }
}

function Get-AdskReadinessArpPath {
    param($Row)
    $branch = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    if ($Row.Hive -eq 'HKLM' -and $Row.View -eq '32') { $branch = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' }
    '{0}:\{1}\{2}' -f $Row.Hive, $branch, $Row.KeyName
}

function Test-AdskReinstallReadiness {
    $rows = @(Get-AdskRegistryRows)
    $registered = @(Get-AdskReadinessInstallerProducts)
    $arpCodes = @()
    foreach ($row in $rows) {
        $package = ConvertTo-AdskPackage $row
        $code = $package.ProductCode
        if (-not $code -and $row.KeyName -match '^\{[0-9a-f-]{36}\}$') { $code = $row.KeyName }
        if ($code) { $arpCodes += $code }
        $missingExe = $false
        $missingManifest = $false
        if ($package.Kind -in @('ODIS', 'Helper', 'Exe') -and $package.Exe) {
            $missingExe = -not (Test-AdskPath ([Environment]::ExpandEnvironmentVariables($package.Exe)))
        }
        if ($package.Kind -eq 'ODIS' -and $package.Arguments -match '(?:^|\s)-m\s+(?:"([^"]+)"|(\S+))') {
            $manifest = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            $missingManifest = -not (Test-AdskPath ([Environment]::ExpandEnvironmentVariables($manifest)))
        }
        if ($missingExe -or $missingManifest) {
            New-AdskReadinessFinding -Severity Error -Code OrphanArp -Target (Get-AdskReadinessArpPath $row) -ProductCode $code -UninstallerMissing $missingExe `
                -Message "Đăng ký gỡ cài đặt của $($package.DisplayName) trỏ tới tệp hoặc manifest không còn tồn tại." `
                -Fix 'Khôi phục bộ cài đúng phiên bản để sửa/gỡ bằng công cụ Autodesk. Chỉ xóa mục ARP sau khi sao lưu, tệp gỡ bị mất và không còn đăng ký MSI.'
        }
    }
    foreach ($registration in ($registered | Group-Object ProductCode)) {
        $product = $registration.Group[0]
        $properties = @(Get-AdskReadinessInstallProperties -PackedGuid $product.PackedGuid)
        $autodesk = @($registration.Group | Where-Object { $_.ProductName -match 'Autodesk|Revit|AutoCAD|Navisworks|Desktop Connector|Civil 3D|Inventor|3ds Max|Maya' }).Count -gt 0 -or
            @($properties | Where-Object { $_.Publisher -match 'Autodesk' }).Count -gt 0 -or $arpCodes -contains $product.ProductCode
        if (-not $autodesk) { continue }
        foreach ($entry in $properties) {
            if (-not [string]::IsNullOrWhiteSpace($entry.LocalPackage) -and -not (Test-AdskPath $entry.LocalPackage)) {
                New-AdskReadinessFinding -Severity Error -Code MsiCacheMissing -Target $product.ProductCode `
                    -Message "Thiếu bộ đệm MSI cho $($product.ProductName): $($entry.LocalPackage)." `
                    -Fix 'Dùng bộ cài đúng sản phẩm và phiên bản để sửa Windows Installer hoặc liên hệ Autodesk/Microsoft. Không xóa đăng ký MSI hay thư mục Windows Installer.'
            }
        }
        if ($arpCodes -notcontains $product.ProductCode) {
            New-AdskReadinessFinding -Severity Error -Code MsiNoArp -Target $product.ProductCode `
                -Message "Sản phẩm MSI $($product.ProductName) còn đăng ký nhưng thiếu mục gỡ cài đặt ARP." `
                -Fix 'Khôi phục hoặc sửa sản phẩm bằng bộ cài đúng phiên bản, sau đó gỡ bằng Windows Installer. Không xóa khóa Installer thủ công.'
        }
    }
    foreach ($service in Get-AdskService) {
        if ($service.Name -notmatch 'Adsk|Autodesk|AdAppMgr|Genuine' -and $service.DisplayName -notmatch 'Autodesk' -and $service.PathName -notmatch '\\Autodesk(?: Shared)?\\') { continue }
        $binary = (Split-AdskCommand ([Environment]::ExpandEnvironmentVariables([string]$service.PathName))).Exe
        if (-not $binary -or -not (Test-AdskPath $binary)) {
            New-AdskReadinessFinding -Severity Error -Code ServiceBinaryMissing -Target $service.Name `
                -Message "Dịch vụ $($service.Name) thiếu tệp thực thi: $binary." `
                -Fix 'Cài lại hoặc sửa thành phần Autodesk sở hữu dịch vụ bằng bộ cài chính thức, rồi gỡ bằng công cụ của hãng nếu cần.'
        }
    }
    foreach ($target in Get-AdskReadinessPendingReboot) {
        New-AdskReadinessFinding -Severity Warning -Code PendingReboot -Target $target `
            -Message 'Windows đang chờ khởi động lại.' -Fix 'Khởi động lại Windows trước khi cài lại. Không xóa cờ khởi động lại hoặc PendingFileRenameOperations.'
    }
    foreach ($entry in Get-AdskReadinessRunOnce) {
        New-AdskReadinessFinding -Severity Error -Code OldToolRunOnce -Target $entry.Path `
            -Message 'RunOnce AutodeskCleanup còn tồn tại và có thể xóa bộ cài mới ở lần đăng nhập tiếp theo.' `
            -Fix 'Sao lưu khóa RunOnce thành .reg rồi chỉ xóa giá trị AutodeskCleanup trước khi đăng nhập lại hoặc cài lại.'
    }
    foreach ($entry in Get-AdskReadinessIfeo) {
        New-AdskReadinessFinding -Severity Error -Code IfeoDebugger -Target $entry.Path `
            -Message 'Giá trị IFEO Debugger có thể chặn ứng dụng Autodesk khởi chạy.' `
            -Fix 'Kiểm tra nguồn gốc Debugger, sao lưu khóa IFEO thành .reg rồi chỉ xóa giá trị Debugger của ứng dụng bị ảnh hưởng.'
    }
    $lock = "$env:ProgramData\Autodesk\ODIS\AdODISInstaller.run.lock"
    if ((Test-AdskPath $lock) -and -not @(Get-AdskProcessByPath -Path "$env:ProgramFiles\Autodesk\AdODIS" | Where-Object { $_.Path -match '\\Installer\.exe$' }).Count) {
        New-AdskReadinessFinding -Severity Error -Code OdisLock -Target $lock `
            -Message 'Tệp khóa ODIS còn tồn tại khi không có trình cài AdODIS đang chạy.' `
            -Fix 'Kiểm tra không còn Installer.exe dưới AdODIS, rồi chuyển tệp khóa vào quarantine để có thể khôi phục.'
    }
    if (Test-AdskMsiBusy) {
        New-AdskReadinessFinding -Severity Warning -Code MsiBusy -Target 'Global\_MSIExecute' `
            -Message 'Windows Installer đang bận.' -Fix 'Đợi tác vụ cài/gỡ hiện tại hoàn tất rồi kiểm tra lại. Không dừng cưỡng bức trình cài đặt.'
    }
}

function Repair-AdskReinstallBlocker {
    param([Parameter(Mandatory = $true)]$Finding, [switch]$DryRun)
    if ($Finding.Code -notin @('OldToolRunOnce', 'IfeoDebugger', 'OdisLock', 'OrphanArp')) { return $Finding.Fix }
    if ($DryRun) { return [pscustomobject]@{ Path = $Finding.Target; Action = 'DryRun'; Destination = $null; Error = $null; Fix = $Finding.Fix } }
    $destination = $null
    $action = 'Refused'
    $errorText = $null
    try {
        # Findings are advisory snapshots, never authorization to delete an arbitrary supplied path.
        $current = @(Test-AdskReinstallReadiness | Where-Object { $_.Code -eq $Finding.Code -and $_.Target -eq $Finding.Target })
        if ($current.Count -ne 1) { throw 'Mục chặn không còn tồn tại hoặc không xác định được an toàn.' }
        if ($Finding.Code -eq 'OrphanArp') {
            $codes = @($Finding.ProductCode, $current[0].ProductCode) | Where-Object { $_ }
            $registered = @(Get-AdskReadinessInstallerProducts)
            if (-not $current[0].UninstallerMissing -or @($registered | Where-Object { $codes -contains $_.ProductCode }).Count) {
                throw 'Từ chối xóa ARP: tệp gỡ vẫn tồn tại hoặc sản phẩm vẫn đăng ký trong Windows Installer.'
            }
        }
        if ($Finding.Code -eq 'OdisLock' -and @(Get-AdskProcessByPath -Path "$env:ProgramFiles\Autodesk\AdODIS" | Where-Object { $_.Path -match '\\Installer\.exe$' }).Count) {
            throw 'Trình cài AdODIS đang chạy; giữ nguyên tệp khóa.'
        }
        $runId = 'repair-' + [guid]::NewGuid().ToString('N')
        $destination = Get-AdskQuarantineDestination -Path $Finding.Target -RunId $runId
        $null = New-AdskDirectory -Path ([IO.Path]::GetDirectoryName($destination))
        if ($Finding.Code -eq 'OdisLock') {
            Move-AdskItem -Path $Finding.Target -Destination $destination
            $action = 'Moved'
        } else {
            $null = Export-AdskRegistryKey -Path ($Finding.Target -replace ':', '') -Destination $destination
            if ($Finding.Code -eq 'OrphanArp') { Remove-AdskRegistryKey -Path $Finding.Target }
            else {
                $name = if ($Finding.Code -eq 'OldToolRunOnce') { 'AutodeskCleanup' } else { 'Debugger' }
                Remove-AdskRegistryValue -Path $Finding.Target -Name $name
            }
            $action = 'Exported+Deleted'
        }
    } catch { $errorText = $_.Exception.Message }
    [pscustomobject]@{ Path = $Finding.Target; Action = $action; Destination = $destination; Error = $errorText; Fix = $Finding.Fix }
}
