# Autodesk Cleaner

Công cụ Windows PowerShell 5.1 giúp gỡ sản phẩm Autodesk theo nhóm/năm, kiểm tra phần dư và phát hiện các mục chặn cài lại. Luôn bắt đầu ở **DryRun ON**. Công cụ dùng bộ gỡ đã đăng ký của hãng; không bảo đảm mọi bộ cài hỏng đều sửa được.

Phạm vi inventory và kế hoạch: Revit, AutoCAD và các vertical, Navisworks, Desktop Connector, Civil 3D, Inventor, 3ds Max, Maya và các thành phần dùng chung/licensing (Access, ODIS, Identity, Genuine, Material Library...). SDK, công cụ phát triển và thành phần bên thứ ba mặc định được giữ lại. Danh mục dọn thư mục dư hiện tập trung vào Revit, AutoCAD, Navisworks, Desktop Connector và một số hạ tầng; không quét xóa mọi thư mục Autodesk.

## Các quy tắc an toàn

So với công cụ tham chiếu được phân tích trong [tài liệu thiết kế](docs/DESIGN.md):

| Quy tắc | Hành vi của công cụ này |
|---|---|
| Không ép xóa registry đăng ký cài đặt | Không xóa tay Uninstall/Installer Products, Features, UpgradeCodes, UserData sau khi gỡ thất bại. Chỉ có ngoại lệ ARP được sửa riêng khi tệp gỡ mất, không còn đăng ký MSI và đã xuất `.reg`. |
| Quarantine có thể khôi phục | Chuyển phần dư đã biết vào `<ổ>:\AutodeskCleaner.Quarantine\<RunId>\` trên cùng ổ; registry được xuất `.reg` trước khi xóa. Không xóa cả gốc Autodesk. |
| Hạ tầng gỡ sau cùng | Chỉ chọn Shared/Infrastructure khi không giữ lại sản phẩm Autodesk cần chúng. Một nhóm/năm gỡ lỗi sẽ chặn dọn nhóm/năm đó và chặn bước hạ tầng. |
| Kiểm tra sẵn sàng cài lại | Báo cache MSI thiếu, ARP mồ côi, dịch vụ hỏng, RunOnce cũ, IFEO, khóa ODIS, MSI bận và yêu cầu khởi động lại; chỉ sửa từng mục được cho phép. |
| Không dừng tiến trình theo tên chung | Chỉ xét đường dẫn dưới InstallLocation được chọn, hỏi trước khi đóng; DryRun không đóng gì. |
| Giữ dữ liệu người dùng | Chỉ chọn cấu hình/add-in khi có `-IncludeUserData`; không đụng workspace Desktop Connector `DC`/`ACCDocs`. |
| Giữ Windows an toàn | Không xóa toàn bộ TEMP, cache Windows Installer, FLEXlm, runtime VC++/.NET/WebView2, cờ reboot hay PendingFileRenameOperations; không dùng Win32_Product. |

## Chạy bằng npx

Cần Node.js 18 trở lên trên máy Windows:

```powershell
npx @cazorlas/autodesk-cleaner            # mở menu (hỏi UAC)
npx @cazorlas/autodesk-cleaner -Scan      # chỉ quét, không cần admin
npx @cazorlas/autodesk-cleaner -Readiness # kiểm tra sẵn sàng cài lại, không cần admin
npx @cazorlas/autodesk-cleaner -Group Revit -Year 2025          # xem trước (DryRun)
npx @cazorlas/autodesk-cleaner -Group Revit -Year 2025 -Execute # gỡ thật
```

## Chạy bằng nhấp đúp

`-All` giữ lại Licensing/ODIS khi không có entry gỡ cài đặt hoặc dịch vụ của chúng vẫn được đăng ký (thư mục chứa binary dịch vụ không được dọn). Đây là chủ ý để việc cài lại tiếp tục hoạt động.

1. Giải nén toàn bộ thư mục, giữ `src` cạnh `AutodeskCleaner.ps1`.
2. Nhấp đúp `Start-AutodeskCleaner.bat`, chấp nhận UAC. Script từ chối chạy nếu thiếu quyền quản trị.
3. Chọn **1** để quét, **2** để kiểm tra cài lại, **3** để chọn nhóm và năm bằng các số phân cách dấu phẩy, **4** để chọn toàn bộ (hỏi xác nhận lần hai).
4. Đọc trạng thái DryRun trên đầu menu. **5** bật/tắt xem trước. Khi OFF, mỗi lần gỡ/sửa thật phải nhập chính xác `GO`.
5. Đọc kế hoạch Steps, Kept, Skipped, SharedRemoved. Xác nhận đóng ứng dụng và chuyển phần dư nếu được hỏi. **6** mở log/quarantine; **0** thoát.

Đóng công việc và lưu mô hình trước khi cho phép đóng ứng dụng. DryRun vẫn ghi log/báo cáo, nhưng không gỡ, dừng tiến trình, sửa registry hay chuyển phần dư. Trong DryRun, phần dư được dự kiến từ các gói đã chọn; các gói được giữ lại vẫn chặn dọn thư mục. Thư mục log mặc định: `%ProgramData%\AutodeskCleaner\Logs\yyyyMMdd-HHmmss`; có transcript và `summary.txt` cho flow gỡ. Báo cáo ghi kết quả từng bước, cleanup và readiness. Cùng một giây có thể dùng chung thư mục log.

## Chạy bằng tham số

Mở Windows PowerShell **Run as administrator** tại thư mục công cụ:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutodeskCleaner.ps1 -Scan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutodeskCleaner.ps1 -Readiness
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutodeskCleaner.ps1 -Group Revit -Year 2025 -Yes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutodeskCleaner.ps1 -All -Yes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AutodeskCleaner.ps1 -Group Revit -Year 2025 -Execute
```

Hai ví dụ `-Yes` trên vẫn là **xem trước**. `-Yes` trả lời yes cho các câu hỏi y/N; chạy thật với `-Execute` vẫn yêu cầu gõ `GO`. `-IncludeUserData` chọn thêm cấu hình người dùng; `-IncludeThirdParty` chọn thêm package bên thứ ba/DevTool trong phạm vi. Không kết hợp `-All` với `-Group`/`-Year`. Không chỉ định năm nghĩa là chọn mọi năm thuộc nhóm.

Để truyền nhiều nhóm/năm, gọi script ngay trong PowerShell (mảng PowerShell):

```powershell
.\AutodeskCleaner.ps1 -Group Revit,Navisworks -Year 2024,2025 -Yes
```

API module cũng hỗ trợ `-LogRoot` và callback xác nhận:

```powershell
Import-Module .\src\AutodeskCleaner.psm1
Invoke-AdskCleanerFlow -Group Revit -Year 2025 -LogRoot E:\CleanerLogs -Confirm { param($message) (Read-Host "$message (y/N)") -eq 'y' }
```

Khi báo **Khởi động lại máy trước khi cài lại**, hãy reboot rồi kiểm tra readiness lại. Thành công của bộ gỡ chưa chứng minh cài lại thành công; cần cài và mở ứng dụng để xác nhận.

## Khôi phục từ quarantine

Đọc `summary.txt`, cột Destination của Cleanup và kết quả Repair. Tạm dừng việc cài/gỡ, kiểm tra không có dữ liệu mới cần giữ ở đường dẫn gốc. Di chuyển thư mục từ `<ổ>:\AutodeskCleaner.Quarantine\<RunId>\Program Files\...` về đúng đường dẫn gốc tương ứng; không ghi đè mù dữ liệu mới. Với bản sao registry, kiểm tra nội dung `.reg`, rồi chọn **Merge** hoặc chạy `reg.exe import "đường-dẫn-bản-sao.reg"` bằng quyền phù hợp. Khôi phục registry có thể đưa mục chặn trở lại; chỉ làm khi cần hoàn tác và hiểu nội dung. Quarantine không hoàn tác sản phẩm đã gỡ bằng bộ gỡ: cần bộ cài chính thức để cài lại.

## Máy đã bị lỗi cài lại

Không cần gỡ thêm để kiểm tra: chạy `-Readiness` hoặc menu **2**, đọc Code, Target, Message, Fix. Lần đầu giữ DryRun để xem đề xuất. Muốn sửa thật, dùng menu **5** tắt DryRun rồi chọn **2**, hoặc `-Readiness -Execute`; xác nhận **Sửa? (y/N)** theo từng mục và gõ `GO`.

Đặc biệt, `OldToolRunOnce` là giá trị `RunOnce\AutodeskCleanup` do công cụ cũ để lại, có thể xóa thư mục Autodesk ở lần đăng nhập tiếp theo và làm mất bộ cài mới. Sửa mục này trước khi đăng nhập lại/cài lại: công cụ xuất khóa `.reg`, chỉ xóa giá trị AutodeskCleanup, không tạo lịch RunOnce mới. Các sửa hỗ trợ khác là `IfeoDebugger`, `OdisLock`, và `OrphanArp` đủ điều kiện; mục ARP vẫn có MSI hoặc còn tệp gỡ sẽ bị từ chối. Cache MSI thiếu, đăng ký MSI không ARP, dịch vụ mất binary cần sửa bằng bộ cài đúng phiên bản/hỗ trợ Autodesk hoặc Microsoft. Không xóa tay registry MSI để che lỗi. Chạy readiness lại sau khi sửa.

## Test bằng máy ảo Hyper-V

Thử nghiệm gỡ/cài lại trong VM trước khi dùng trên máy làm việc. Cần Windows có Hyper-V (ví dụ Pro/Enterprise) và bật ảo hóa phần cứng.

1. Trong PowerShell quản trị, bật Hyper-V rồi khởi động lại:

   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
   ```

2. Trong Hyper-V Manager tạo VM **Generation 2**, lưu VM và **VHDX trên ổ lớn E:**, RAM **8–12 GB**, **4 vCPU**, đĩa **150 GB**. Cấu hình mạng và ISO Windows 11, TPM/Secure Boot theo yêu cầu cài Windows 11.
3. Cài Windows 11, cập nhật và cài Revit, AutoCAD, Navisworks, Desktop Connector với quyền sử dụng hợp lệ. Sao chép công cụ vào VM.
4. Tắt VM sạch rồi tạo **checkpoint** trước khi gỡ. Bật VM; chạy quét/readiness/DryRun và đọc báo cáo trước.
5. Chạy thật công cụ trong VM; kiểm tra kết quả gỡ, quarantine, readiness, reboot nếu được yêu cầu.
6. Cài lại Revit bằng bộ cài chính thức, **mở Revit** và kiểm tra hoạt động thực tế; lưu log/evidence cần giữ ra ngoài checkpoint.
7. Revert checkpoint để thử lại từ cùng trạng thái ban đầu.

**Windows Sandbox không phù hợp** cho ca này: không hỗ trợ chu trình reboot giữ trạng thái cần thiết, không có checkpoint Hyper-V để quay về bộ sản phẩm đã cài, và dữ liệu Sandbox nằm trên ổ C: thay vì VHDX chủ động đặt trên E:.

Test mock phát triển (Pester 3.4.0):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
```

Test mock không chứng minh gỡ/cài lại hoặc UI hoạt động trên host thật.
