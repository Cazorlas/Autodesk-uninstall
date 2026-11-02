## 1. Architecture map

**Scope:** Static, read-only analysis of `autodesk_complete_uninstaller.bat`, `CHANGELOG.md`, and `README.md` as currently on disk. All line references below refer to the batch file unless explicitly prefixed. No script, installer, build, or test was executed. The reported Revit reinstall failure cannot be attributed to one action without the affected machine’s installation logs.

**Principal finding:** Failed uninstallations are followed by forced removal of product registration and program files. This can leave inconsistent Windows Installer state while the script reports the machine ready for installation.

### Menu

The menu and dispatch occupy **143–201**.

| Option | Implementation | Purpose |
|---|---:|---|
| 1 | 322–526 | Scan installed products; classify installer and removal priority. |
| 2 | 531–631 | Uninstall selected products in the operator’s selection order. |
| 3 | 636–2109 | Uninstall all scanned products, then destructive cleanup. |
| 4 | 2114–2841 | Skip main product uninstall; remove shared components, files, services, and registration. |
| 5 | 4920–5400 | Seventeen-category remnant verification. |
| 6 | 206–317 | Optional System Restore point. |
| 7 | 2846–3402 | Fifteen-category remnant search, including C: drive directory search. |
| 8 | 3407–4077 | Footprint audit advertised as a preview. |
| 9 | 4082–4153 | Explicitly delete Desktop Connector workspaces. |
| 10 | 4158–4676 | Error 103 diagnostics and individually prompted repairs. |
| 11 | 4681–4796 | Clear global pending-reboot state. |
| 12 | 4801–4915 | Copy selected Autodesk user-data folders into a backup. |
| 0 | 197 | Exit. |

Startup **1–141** establishes shared lists, elevates, creates/truncates logs, and records basic infrastructure diagnostics.

### Full Clean: actual execution order

| Phase | Lines | Behavior |
|---|---:|---|
| Detection prerequisite | 322–434; 638–644 | Requires a previous scan; uses the stored inventory rather than automatically refreshing it. |
| Confirmation/options | 645–715 | Global YES confirmation; optional Downloads cleanup; separate Desktop Connector workspace opt-in. |
| A | 725–752 | Optional restore point; continues after failure. |
| Backup | 757–824 | Optional copy of current-user Roaming/Local Autodesk data and Public Documents Autodesk data. |
| B | 829–855 | Stop/disable named services, stop FlexNet/Genuine, forcibly kill named and path-matched processes. |
| C, pass 1 | 859–1102 | Priority-ordered ODIS/MSI/legacy/generic uninstall routing. |
| C, retries | 1104–1319 | Rescan both machine Uninstall trees; up to three additional passes, stopping early on no progress. Retry routing differs between registry views. |
| C2 | 1322–1379 | **Delete remaining Autodesk-published Uninstall keys even when uninstall failed.** |
| D | 1385–1438 | Run Desktop App, Identity Manager, ODIS, Licensing uninstallers; then run remaining product helpers; delete PIT and Genuine identity files. |
| E | 1444–1596 | Kill again, stop Windows Installer/Search, unregister shell DLLs, restart Explorer, delete whole Autodesk/shared/data roots; force ownership/ACLs on failure. |
| Optional cleanup | 1599–1650 | Delete selected Downloads/browser directories and optionally Desktop Connector workspaces. |
| E2 | 1653–1709 | Delete matching desktop, Start Menu, and taskbar shortcuts. |
| F | 1714–1756 | Delete license state, caches, login state, **all current `%temp%` contents**, and matching Windows Temp contents. |
| G | 1761–1800 | Delete named services; optional FlexNet service deletion; delete matching scheduled tasks and firewall rules. |
| H | 1805–1846 | Export/delete entire Autodesk and legacy licensing registry trees; remove license environment variables. |
| H2 | 1849–1921 | Delete selected class registrations, matching COM subkeys, MuiCache values, and shell approvals. |
| H3 | 1924–1943 | Remove IFEO `Debugger` values for a fixed executable list. |
| MSI product “ghosts” | 1946–1965 | Delete Installer Products keys whose `ProductName` contains Autodesk. No actual orphan test. |
| PATH | 1968–1976 | Remove every system PATH entry matching Autodesk or AdODIS. |
| Reboot state | 1979–2008 | Remove matching pending-rename pairs; erase Windows Update reboot flags; reset `UpdateExeVolatile`. |
| I | 2012–2020 | Stop/delete Genuine service and delete its folders again. |
| E3 | 2022–2068 | Retry locked roots, including file-by-file deletion and ownership/ACL changes. |
| Deferred cleanup | 2070–2088 | Generate root-directory deletion batch and register `RunOnce\AutodeskCleanup`. |
| Installer restart | 2090–2095 | Stop/start `msiserver`. |
| “J” verification | 2109 → 4920–5400 | Remnant checks; no install or repair validation. |

“Genuine Service LAST” is only approximate: Genuine-published products can already be uninstalled in priority 8, and its parent directories are deleted during E.

### Deep Clean Only: actual execution order

**2114–2841** is a separate implementation, not a call into Full Clean:

1. Confirmation/options/restore point: **2114–2201**.
2. Stop/disable services and kill processes: **2205–2228**.
3. Run four shared-component uninstallers: **2231–2253**.
4. Explicitly **do not run product uninstall helpers**: **2254–2261**.
5. Delete licensing/cache/temp state: **2262–2297**.
6. Kill again; unregister shell extensions; delete roots and optional data: **2300–2459**.
7. Shortcuts: **2462–2510**.
8. Services/tasks/firewall: **2513–2535**.
9. Registry/environment/Genuine/classes/IFEO/MSI Products/PATH/reboot-state cleanup: **2538–2713**.
10. Retry locked roots: **2715–2752**.
11. Offline other-user Autodesk registry/AppData cleanup: **2754–2816**.
12. Restart Windows Installer, declare installation readiness, then verify: **2819–2841**.

Unlike Full Clean, Deep Clean has **no C2 removal of machine Uninstall entries** and **no generated RunOnce cleanup**.

### Remnant search and verification

- **2846–3402:** registered products, processes, fixed services, fixed roots, C: directories named Autodesk, registry roots, COM/classes, shell approvals, Installer Products, shortcuts/tasks/environment, IFEO, pending renames/reboot flags, hosts.
- **3407–4077:** similar audit, plus folder sizes, shell DLLs, firewall, optional workspace visibility.
- **4920–5400:** seventeen checks, including Desktop Connector.
- These checks do **not** validate Windows Installer registration consistency, successful package repair, prerequisite health, or a fresh Autodesk installation.

`README.md:3, 63, 256–257` and `CHANGELOG.md:117, 137` claim zero-remnant results/no reboot. Those statements are not evidence that Revit reinstallation succeeds.

## 2. Detection and uninstall routing

### Product discovery

**338–364** enumerate:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
```

**371–404** enumerate:

```text
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
```

For each key returned by recursive `DisplayName` queries:

- Read `DisplayName`.
- Read `Publisher`.
- Require defined publisher containing case-insensitive **`Autodesk`** using `findstr /i`.
- Require defined display name.
- Read `UninstallString` and `DisplayVersion`.
- Store name, command, version, and source key.

The 32-bit pass suppresses an entry when its **display name equals an already collected display name** (**386–390**), regardless of different GUID, architecture, version, or registration.

There is no discovery of:

- `HKCU\...\Uninstall`.
- Other users’ Uninstall entries.
- MSI products through installer registration/API enumeration.
- Packages with missing/non-Autodesk Publisher.
- Custom installation directories from `InstallLocation`.
- Product relationships from ODIS manifests.

ODIS manifests and helper directories are **counted**, not converted into product inventory: **438–452**.

### Installer classification

**408–418:**

```text
Default: MSI
UninstallString contains Installer.exe: ODIS
UninstallString contains AdskUninstallHelper: ODIS
```

There is **no distinct BitRock classifier**, despite `README.md:45`.

Execution subsequently checks for `MsiExec`, then `Setup.exe`, otherwise applies the generic BitRock-style flag.

### Exact commands

**ODIS selected uninstall, 576–580:**

```bat
set "UCMD=!PUNINST!"
echo "!UCMD!" | findstr /i "\-q" >nul 2>&1
if !errorlevel! neq 0 set "UCMD=!UCMD! -q"
set "ODIS_ARGS=!UCMD:*Installer.exe=!"
"C:\Program Files\Autodesk\AdODIS\V1\Installer.exe"!ODIS_ARGS! >nul 2>&1
```

**ODIS Full Clean, 957–959:**

```bat
set "ODIS_ARGS=!UCMD:*Installer.exe=!"
start "" /b cmd /c ""C:\Program Files\Autodesk\AdODIS\V1\Installer.exe"!ODIS_ARGS! >"!LOGDIR!\odis_out.tmp" 2>&1 && echo 0 > "!LOGDIR!\odis_done.tmp" || echo 1 > "!LOGDIR!\odis_done.tmp""
```

**ODIS retry, 1183–1189:**

```bat
set "R_CMD=!R_US!"
echo "!R_CMD!" | findstr /i "\-q" >nul 2>&1
if !errorlevel! neq 0 set "R_CMD=!R_CMD! -q"
set "ODIS_ARGS=!R_CMD:*Installer.exe=!"
"C:\Program Files\Autodesk\AdODIS\V1\Installer.exe"!ODIS_ARGS! >"!LOGDIR!\odis_out.tmp" 2>&1
```

ODIS arguments come from the registry command, with `-q` appended if absent. The script does **not** construct a fixed `-i uninstall -m ...` command independently.

Full Clean checks XML-looking tokens exist before running ODIS (**934–951**, **1174–1181**); missing metadata causes a skip followed eventually by forced cleanup. Selected uninstall has no equivalent preflight.

**MSI, 595, 1013, 1214, 1275:**

```bat
msiexec /x "{!GUID!}" /qn /norestart REMOVE=ALL REBOOT=ReallySuppress
```

Retry-variable equivalent:

```bat
msiexec /x "{!R_GUID!}" /qn /norestart REMOVE=ALL REBOOT=ReallySuppress
```

The GUID is the second brace-delimited token in `UninstallString`, not a validated product-code lookup (**591–592**, **1007–1008**).

Selected uninstall retries unexpected MSI failures with basic UI (**603**):

```bat
msiexec /x "{!GUID!}" /qb /norestart REMOVE=ALL REBOOT=ReallySuppress
```

Recognized success-like MSI codes are `0`, `1605`, `1641`, and `3010`. Reboot-required codes are displayed but do not establish a reboot barrier.

**Legacy Setup, 614 / 1053:**

```bat
start /wait "" cmd /c "!PUNINST!" /q >nul 2>&1
```

**Generic/BitRock-style fallback, 622 / 1067:**

```bat
start /wait "" cmd /c "!PUNINST!" --mode unattended >nul 2>&1
```

Retry forms, **1241 / 1301:**

```bat
start /wait "" cmd /c "!R_US!" --mode unattended >nul 2>&1
```

The 32-bit retry recognizes only MSI versus generic; it has no dedicated ODIS branch (**1268–1303**).

**Explicit shared-component BitRock-style commands, 1391–1410; 2235–2251:**

```bat
start /wait "" "C:\Program Files (x86)\Autodesk\Autodesk Desktop App\removeAdAppMgr.exe" --mode unattended
start /wait "" "C:\Program Files\Autodesk\AdskIdentityManager\uninstall.exe" --mode unattended
start /wait "" "C:\Program Files\Autodesk\AdODIS\V1\RemoveODIS.exe" --mode unattended
start /wait "" "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\uninstall.exe" --mode unattended
```

**Remaining product helper, Full Clean only, 1429:**

```powershell
try { $p = Start-Process -FilePath '%%h\AdskUninstallHelper.exe' -ArgumentList '-q' -WindowStyle Hidden -PassThru; if (-not $p.WaitForExit(300000)) { $p.Kill() } } catch {}
```

## 3. Full inventory of cleanup targets

These are **attempted operations**; most failures are suppressed. External vendor uninstallers may make additional changes that cannot be inventoried from these three files.

### 3.1 Entire directory trees deleted unconditionally when present

The same list occurs at **1487–1507** and **2334–2353**:

```text
C:\Program Files\Autodesk
C:\Program Files\Common Files\Autodesk Shared
C:\Program Files\Common Files\Autodesk
C:\Program Files (x86)\Autodesk
C:\Program Files (x86)\Common Files\Autodesk Shared
C:\Program Files (x86)\Common Files\Autodesk
C:\ProgramData\Autodesk
C:\Users\Public\Documents\Autodesk
C:\Users\Public\Autodesk
C:\Autodesk
C:\Program Files\Common Files\Macrovision Shared
```

Current-user trees, **1521–1528**, **2362–2369**:

```text
%APPDATA%\Autodesk
%LOCALAPPDATA%\Autodesk
%LOCALAPPDATA%\Programs\Autodesk
```

Additional trees:

```text
%LOCALAPPDATA%\com.autodesk.cer-dialog
    1542–1552; 2378–2382

C:\Windows\assembly\NativeImages_v4.0.30319_64\Autodesk*
    1555–1567; 2385–2392

C:\Windows\assembly\NativeImages_v4.0.30319_32\Autodesk*
    1569–1581; 2393–2400

C:\Windows\System32\config\systemprofile\AppData\Local\Autodesk
    1583–1594; 2401–2405
```

The NativeImages patterns enumerate matching **directories** and delete their whole trees.

### 3.2 Explicit shared-component/license/cache paths

Some are redundant because their parent is already a whole-tree target:

| Exact path | Operation and lines |
|---|---|
| `%ProgramData%\Autodesk\SDS` | Delete before Desktop App uninstall: 1390, 2234. |
| `C:\ProgramData\Autodesk\ODIS\AdODISInstaller.run.lock` | Delete before RemoveODIS: 1402, 2244. |
| `C:\ProgramData\Autodesk\Adlm\ProductInformation.pit` | Delete: 1435, 2262. |
| `%LOCALAPPDATA%\Autodesk\Genuine Autodesk Service\id.dat` | Delete: 1436, 2263. |
| `C:\ProgramData\FLEXnet\adsk*` | Remove hidden/system/read-only attributes, then delete matching files: 1717–1721, 2267–2271. Does not delete the whole FLEXnet directory. |
| `C:\ProgramData\Autodesk\CLM` | Delete tree: 1723–1726, 2273–2276. |
| `%APPDATA%\Autodesk\ADUT` | Delete tree: 1728–1731, 2278–2281. |
| `%LOCALAPPDATA%\Temp\odis_download_dest` | Delete tree: 1733–1736, 2283. |
| `%LOCALAPPDATA%\Autodesk\Web Services\LoginState.xml` | Delete: 1738–1741, 2284. |
| `C:\Program Files (x86)\Autodesk\Genuine Service` | Delete tree again: 2017, 2574. |
| `%LOCALAPPDATA%\Programs\Autodesk\Genuine Service` | Delete tree again: 2018, 2575. |

Consequently, whole-parent deletion also removes, **if located beneath those parents**:

- ODIS program files under `C:\Program Files\Autodesk\AdODIS`, including `V1`.
- ODIS metadata/logs/cache under `C:\ProgramData\Autodesk\ODIS`.
- `C:\ProgramData\Autodesk\Uninstallers`, including product helpers.
- Licensing files under `C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing`.
- `C:\ProgramData\Autodesk\Adlm`, including files beyond the explicitly named PIT.
- Identity Manager under `C:\Program Files\Autodesk\AdskIdentityManager`.
- Autodesk Desktop App under `C:\Program Files (x86)\Autodesk\Autodesk Desktop App`.
- Autodesk Access, AdSSO, CER, product/content/add-in data **wherever they reside inside a deleted parent**.

The script does not have separate literal folder inventories for Access, AdSSO, Revit Interoperability, or most product-specific shared components.

### 3.3 Temporary files

**1743–1753**, **2285–2295**:

```text
%temp%\*
%temp%\*\                         every immediate subdirectory, recursively
C:\Windows\Temp\*Autodesk*         matching directories recursively and matching files
```

The `%temp%` cleanup has **no Autodesk ownership, age, or active-install filter**.

### 3.4 Optional Downloads/browser cleanup

**1600–1628**, **2409–2436** delete matching directories:

```text
%USERPROFILE%\Downloads\*Autodesk*
%USERPROFILE%\Downloads\*AutoCAD*
%USERPROFILE%\Downloads\*Revit*
%USERPROFILE%\Downloads\*Inventor*
%USERPROFILE%\Downloads\*Maya*
%USERPROFILE%\Downloads\*3dsMax*
%LOCALAPPDATA%\Google\Chrome\User Data\Default\IndexedDB\*autodesk*
```

These loops use `for /d`: they do not directly delete standalone downloaded EXE/ZIP files.

Edge/Firefox paths appear in audit classification (**3614–3619**, **3635**), but **there is no corresponding deletion loop**.

`C:\Autodesk` is deleted regardless of this opt-in.

### 3.5 Optional Desktop Connector workspace cleanup

**1631–1649**, **2439–2459**, standalone **4132–4150**:

```text
%USERPROFILE%\DC
%USERPROFILE%\ACCDocs
```

Entire trees are deleted after killing the two Desktop Connector processes and stopping `DesktopConnectorService`. No sync-status validation or custom-workspace discovery is implemented.

### 3.6 Other-user cleanup: Deep Clean Only

**2758–2782** enumerate:

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList
```

Select keys containing `S-1-5-21`, read `ProfileImagePath`, expand it, exclude current `%USERPROFILE%`, and skip an already loaded `HKU\<SID>`.

Load:

```text
!MU_PATH!\NTUSER.DAT
```

as:

```text
HKU\TEMP_!MU_NAME!
```

Delete:

```text
HKU\TEMP_!MU_NAME!\Software\Autodesk
```

Then unload the hive.

**2795–2816** delete for other, apparently logged-out profiles:

```text
!MU_PATH!\AppData\Roaming\Autodesk
!MU_PATH!\AppData\Local\Autodesk
```

No equivalent other-user pass exists in Full Clean. Other-user `Programs\Autodesk`, CER, classes, environment, and workspaces are not explicitly cleaned.

### 3.7 Shortcuts

**1657–1705**, **2464–2508**:

- Delete matching `*.lnk` files in:

```text
%USERPROFILE%\Desktop
C:\Users\Public\Desktop
```

- Delete entire trees:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Autodesk
%ProgramData%\Microsoft\Windows\Start Menu\Programs\Autodesk
```

- Delete matching immediate `*.lnk` children in:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs
%ProgramData%\Microsoft\Windows\Start Menu\Programs
```

- Delete matching `*.lnk` files in:

```text
%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar
```

Exact name filters:

```text
Desktop:
Autodesk | AutoCAD | Revit | Inventor | Civil 3D | Maya | Navisworks |
DWG | Alias | Moldflow | Fusion | Advance Steel | Design Review |
3ds Max | 3dsMax

Start Menu immediate shortcuts:
Autodesk | AutoCAD | Revit | Inventor | DWG | Design Review

Taskbar:
Autodesk | AutoCAD | Revit | Inventor | Maya | Navisworks | DWG |
Alias | Design Review | 3ds Max | 3dsMax
```

They inspect shortcut **names**, not targets or publisher.

### 3.8 Services

Shared list, **35**:

```text
AdskLicensingService
AdskAccessServiceHost
AdAppMgrSvc
AdskNLM
DesktopConnectorService
```

- Stop and disable: **833–839**, **2207–2213**.
- Delete registration using `sc delete`: **1765–1770**, **2515–2521**.
- Additional licensing fallback deletion: **1414–1418**.

Additional service strings:

```text
Autodesk Genuine Service
```

Stopped at **842**, **2216**; stopped/deleted at **2015–2016**; deleted at **2522**.

```text
FlexNet Licensing Service 64
```

Stopped **without its own confirmation** at **841**, **2215**. Full Clean offers deletion at **1773–1781**. Deep Clean does not offer/delete it.

Windows services affected but not deleted:

```text
msiserver
WSearch
```

Stopped at **1456–1457**, **2033–2034**, **2226**, **2307–2308**, **2724–2725**. `msiserver` is later restarted (**2092–2093**, **2822–2823**); no `WSearch` restart exists.

### 3.9 Scheduled tasks and firewall

**1785–1789**, **2527–2529**:

- Query `schtasks /query /fo csv /nh`.
- Select every CSV row containing case-insensitive **`Autodesk`**.
- Delete the task named in the first comma-delimited field.
- No fixed task-name list or action-path check.

**1794–1797**, **2531–2533**:

```powershell
(Get-NetFirewallRule -ErrorAction SilentlyContinue |
 Where-Object {
   $_.DisplayName -match 'Autodesk|AutoCAD|Revit|Inventor|Civil|Maya|3ds.?Max|Navisworks'
 }).DisplayName
```

Each returned display name is passed to:

```bat
netsh advfirewall firewall delete rule name="%%r"
```

No fixed firewall-rule inventory or executable-path validation.

### 3.10 Entire registry trees

Export then delete at **1810–1828**, **2539–2556**:

```text
HKLM\SOFTWARE\Autodesk
HKCU\SOFTWARE\Autodesk
HKCU\SOFTWARE\SOFTWARE\Autodesk
HKLM\SOFTWARE\WOW6432Node\Autodesk
HKLM\SOFTWARE\FLEXlm License Manager
HKCU\SOFTWARE\FLEXlm License Manager
HKLM\SOFTWARE\WOW6432Node\FLEXlm License Manager
HKLM\SOFTWARE\Macrovision
```

`UPI`, `UPI2`, and `ODIS` are **not individually named or reconciled**. If they exist as children of `HKLM\SOFTWARE\Autodesk`, successful parent deletion removes them.

**Full Clean only**, **1328–1367**:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\<matching key>
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\<matching key>
```

Delete remaining keys with defined `DisplayName` and Autodesk-matching `Publisher`. No pre-delete export occurs in C2.

### 3.11 Classes, file associations, COM, shell approvals

**1854–1917**, **2581–2641** search immediate key names beneath:

```text
HKCU\SOFTWARE\Classes
```

Delete keys matching `DWGTrueView`, `AutoCAD`, `acadlt`, and `Autodesk`. The Autodesk-name pass excludes:

```text
EncapsulatedPostscript
ErrorLogFile
ExportedToolPalettes
Ghostscript
WindowsMetafile
MuiCache
```

Explicit keys, from **38**, **1873–1883**, **2600–2609**:

```text
HKCU\SOFTWARE\Classes\AutodeskDGN
HKCU\SOFTWARE\Classes\AutoLISPFile
HKCU\SOFTWARE\Classes\3dsFile
HKCU\SOFTWARE\Classes\cdc_auto_file
HKCU\SOFTWARE\Classes\CompleteR16PlotConfigurationFile
HKCU\SOFTWARE\Classes\adsk.idmgr
HKCU\SOFTWARE\Classes\adskidmgr
HKCU\SOFTWARE\Classes\dwgviewr.9128.409
HKCU\SOFTWARE\Classes\.dgn
```

Recursive data searches for `Autodesk` delete the **returned matching key**, possibly a child such as `InprocServer32`, within:

```text
HKCU\SOFTWARE\Classes\CLSID
HKLM\SOFTWARE\Classes\CLSID
HKLM\SOFTWARE\Classes\TypeLib
```

References: **1885–1897**, **2611–2623**.

Delete matching property names or values under:

```text
HKCU\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache
```

References: **1900**, **2625**.

Delete matching value names under:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved
```

References: **1902–1904**, **2626–2628**.

Shell DLL unregistration, **1460–1467**, **2311–2318**:

```text
C:\Program Files\Common Files\Autodesk Shared\AcShellEx\AcShellExtension.dll
C:\Program Files (x86)\Common Files\Autodesk Shared\AcShellEx\AcShellExtension.dll
C:\Program Files\Common Files\Autodesk Shared\DwfShellEx\DwfShellExtension.dll
C:\Program Files (x86)\Common Files\Autodesk Shared\DwfShellEx\DwfShellExtension.dll
```

Command:

```bat
regsvr32 /u /s %%x
```

### 3.12 Windows Installer registration/cache

| Target | Actual behavior |
|---|---|
| `HKLM\SOFTWARE\Classes\Installer\Products` | Export entire tree; recursively locate `ProductName`; delete matching key if value contains Autodesk. **1949–1960**, **2665–2676**. |
| `HKCR\Installer\Products` | No explicit reference. Machine Classes Products contributes to the merged HKCR view, so machine-side deletions can affect what HKCR exposes. No independent per-user scan. |
| `HKLM\SOFTWARE\Classes\Installer\Features` | No direct cleanup or consistency check. |
| `HKLM\SOFTWARE\Classes\Installer\UpgradeCodes` | No direct cleanup or consistency check. |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products` | No direct cleanup or consistency check. |
| Other Installer `UserData` SIDs, Components, Patches | No direct inventory/reconciliation. |
| `C:\Windows\Installer` | **No direct cached MSI/MSP deletion.** |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs` | **No direct count deletion/modification.** |
| `C:\ProgramData\Package Cache` | No explicit cleanup. |

Vendor uninstallers may legitimately update these stores; that is separate from the batch’s manual deletions.

### 3.13 Environment variables and PATH

Delete each value from both locations (**1831–1843**, **2559–2569**):

```text
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment
HKCU\Environment
```

Values:

```text
ADSKFLEX_LICENSE_FILE
ADSK_LICENSE_FILE
AUTODESK_LICENSE_FILE
FLEXLM_TIMEOUT
```

System `Path` is rewritten at **1972**, **2686**:

- Split on semicolons.
- Drop every nonempty entry matching `Autodesk|AdODIS`.
- No existence/dead-path test.
- Write as `ExpandString`.
- User PATH is untouched.
- No environment-change broadcast is implemented.

### 3.14 IFEO

**1928–1934**, **2650–2656** delete only the `Debugger` value beneath:

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\<executable>
```

Exact executable list, **44**:

```text
ProcessManager.exe DownloadManager.exe InstallManager.exe
install_manager.exe install_helper_tool.exe AdODIS-installer.exe
GenuineService.exe AdskIdentityManager.exe Installer.exe
AdskAccessServiceHost.exe AdskAccessService.exe AdskAccessCore.exe
AdSSO.exe AdskLicensingService.exe LogAnalyzer.exe
```

Any existing `Debugger` value is removed; its content is not checked for `Blocked`.

### 3.15 Reboot-state registry changes and deferred deletion

**1982–1994**, **2695–2702**:

```text
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager
    PendingFileRenameOperations
```

Outer gate requires literal `Autodesk`. The subsequent PowerShell filter removes source/target pairs matching:

```text
Autodesk|AdODIS|AdskLicensing|adsk
```

**2001–2007**, **2706–2712** delete/reset:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired
HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\RebootRequired
HKLM\SOFTWARE\Microsoft\Updates
    UpdateExeVolatile = 0
```

Full Clean writes **2085**:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
    AutodeskCleanup
```

It runs a generated batch that recursively deletes still-locked roots after a ten-second delay.

Separate option 11 additionally deletes **all** `PendingFileRenameOperations` and:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending
```

References: **4770–4775**.

Restore-point options temporarily overwrite then delete:

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore
    SystemRestorePointCreationFrequency
```

References: **264–312**, **733–752**, **2183–2201**. Existing custom values are not restored.

### 3.16 Separate Error 103 repairs

These are not automatic Deep Clean phases:

- Delete ODIS lock: **4452**.
- Delete IFEO Debugger values: **4470–4472**.
- Stop/start `AdskAccessServiceHost`: **4495–4497**.
- Run RemoveODIS, delete:
  - `C:\ProgramData\Autodesk\ODIS`
  - `C:\Program Files\Autodesk\AdODIS`
  
  **4517–4535**.
- Delete a **different** PIT path:
  
  ```text
  %LOCALAPPDATA%\Autodesk\Web Services\ProductInformation.pit
  ```
  
  **4317**, **4549**.
- Rewrite `%WINDIR%\System32\drivers\etc\hosts`, dropping noncomment lines containing Autodesk: **4602–4625**.
- Delete the two Windows Update reboot keys: **4642–4643**.

### 3.17 Microsoft runtimes

- **VC++:** read-only query of:
  
  ```text
  HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64
      Major
  ```
  
  **4355–4366**. Displays a manual download URL at **4573**. **No explicit VC++ uninstall, repair, install, or runtime-file deletion.**
- **.NET:** directly deletes Autodesk-named directories in the two `.NET Framework v4` NativeImages caches, listed above. No explicit .NET runtime/framework uninstall.
- **WebView2:** no reference or direct removal.
- Microsoft-published ARP entries do not pass the Autodesk publisher filter. Effects inside third-party/vendor uninstallers are not established here.

## 4. Reinstall-breaking risks

The following are source-confirmed behaviors with reasoned failure modes; none is a live reproduction of the user’s failure.

### High severity

| Lines | Risk and concrete failure mode | Correct replacement behavior |
|---|---|---|
| **1322–1367** | **Deletes Uninstall registration after failure.** An MSI uninstall can fail, yet C2 removes its ARP key while Installer/UserData/component registration remains. This conceals the product without completing removal; subsequent setup may detect an existing product or enter a failing maintenance/upgrade path. | Preserve failed products and their uninstallers. Capture actual package codes/logs, repair missing source/cache through supported procedures, retry proper uninstall, and stop destructive dependent cleanup on unresolved failure. |
| **1949–1960; 2665–2676** | **Partial MSI registration deletion.** Autodesk in `ProductName` is treated as proof of an orphan. Live products qualify, especially under option 4. Products entries are removed without reconciling Features, UpgradeCodes, UserData, Components, patches, or ARP. | Never manually purge MSI registration by name. Use normal MSI removal and supported recovery tooling for demonstrably broken registration. |
| **2114–2125; 2254–2258; 2334–2369; 2665–2674** | **Deep Clean destroys installed products without uninstalling them.** There is no installed-product guard. It deletes executables, product helpers, shared infrastructure, and selected MSI registration while leaving machine ARP entries. | Refuse remnant cleanup when affected products remain installed; route them through product uninstall first. Permit only positively identified unowned remnants afterward. |
| **957–971** | **ODIS timeout does not terminate/wait for the installation transaction.** After roughly 600 waits, cleanup continues even if the started process remains active. Another product may start; later process kills and directory deletion can interrupt ongoing uninstall work. Shared completion-file names can also be written by an earlier timed-out process. | Track a process/job per operation; serialize installer transactions; on timeout diagnose and stop the cleanup sequence until a safe terminal state is known. |
| **1388–1429** | **Infrastructure removed before remaining product helpers.** Identity Manager, ODIS, and Licensing are removed before scanning `Uninstallers\*\AdskUninstallHelper.exe`. Those helpers may still need the infrastructure just removed. | Finish all dependent product/helper removal first; remove shared installation/licensing infrastructure only after dependency checks pass. |
| **1391–1412; 2235–2252; 1487–1507; 2334–2353** | **Component failures ignored, then their files deleted.** The four explicit component uninstallers print OK without checking exit code. Failed ODIS/Licensing removal can leave package registration or service state referencing deleted binaries. | Check exit codes and postconditions; retain files/registration on failure; repair/reinstall the component if needed before removing it properly. |
| **4519–4535** | **Error 103 “reset” can leave a registered ODIS/Access service pointing to missing files.** It stops `AdskAccessServiceHost`, optionally runs RemoveODIS without checking success, deletes both roots, and never directly deletes/verifies service registration. | Use a supported ODIS uninstall/repair flow; verify package and service outcomes before deleting remnants or declaring repair completed. |
| **833–852; 2207–2225** | **Disables/kills dependencies before uninstall.** Licensing/Access and other services are disabled, and all Autodesk-path processes plus generic installer names are killed before product uninstall. This can prevent uninstall custom actions from accessing needed services or interrupt another install. | Require installation quiescence; close applications gracefully; stop only proven lock owners as needed; preserve service startup configuration until the owning uninstaller completes. |
| **32; 845–852; 1448–1454; 2219–2225** | **System-wide process-name killing.** `Installer.exe`, `setup.exe`, `lmgrd.exe`, and `FNPLicensingService64.exe` are not Autodesk-exclusive. Unrelated installs/licensing sessions can be interrupted. | Resolve executable path, signature, owner package, and PID; never terminate by generic name alone. |
| **1487–1528; 2334–2369** | **Whole shared roots deleted regardless of surviving products.** `Autodesk Shared`, all Autodesk program roots, and all ProgramData Autodesk state are removed even after uninstall failures or missed detection. Other Autodesk products, plug-ins, and repair/uninstall sources can be destroyed. | Build an ownership/dependency inventory; uninstall all consumers; delete only verified unowned paths. |
| **1498; 2345; 1815–1818; 2544–2547** | **Non-Autodesk shared licensing data removed.** Entire `Macrovision Shared`, `Macrovision`, and FLEXlm License Manager trees are targeted without vendor/consumer ownership checks. | Preserve shared licensing components unless all consumers and exact ownership are established. |
| **2077–2085** | **Deferred root deletion can destroy a fresh reinstall.** `RunOnce` deletes whole locked roots such as `C:\Program Files\Autodesk` or `C:\ProgramData\Autodesk` at a later logon. A product installed before that action executes is inside the deletion target. | Require reboot/resume before reinstall; avoid delayed whole-root deletion; track exact owned remnants and invalidate cleanup if new installation state appears. |
| **1992; 2700** | **Cancels legitimate pending removals/replacements.** Filtering is pair-aware, but deleting scheduled Autodesk operations can leave old locked DLLs/files in place and prevent the uninstall from finishing. | Preserve legitimate pending operations and require a real reboot; distinguish stale operations only with evidence. |
| **2001–2007; 2706–2712; 4642–4643; 4770–4775** | **Erases global reboot/servicing state.** Option 11 deletes all pending renames, including unrelated software, and CBS reboot state. Flags disappearing does not complete replacement of loaded files or Windows servicing. | Report reboot requirements and restart; never clear global Windows servicing state to bypass installer checks. |
| **1435; 1720–1730; 2262; 2270–2280** | **Deletes activation/license state globally.** PIT, CLM, ADUT, and `FLEXnet\adsk*` removal can invalidate retained/legacy Autodesk activation and force reactivation; successful relicensing is not proven. | Keep license reset separate and explicit; use product/version-supported procedures and preserve required entitlement/configuration evidence. |
| **1744–1745; 2286–2287** | **Deletes every user TEMP item.** Removes unrelated installation staging/rollback files and Autodesk installer data if work is still active. | Delete only known abandoned Autodesk-owned temporary paths after installer quiescence, with age/ownership checks. |

### Medium severity

| Lines | Risk and concrete failure mode | Correct replacement behavior |
|---|---|---|
| **413–416; 579–580; 1188–1189** | **Helper misrouting.** `AdskUninstallHelper.exe` is classified as ODIS, but its registry command is routed to hardcoded `Installer.exe`; substring extraction expects `Installer.exe` to exist in that command. | Distinguish helper executables from ODIS Installer and invoke each executable’s documented arguments. |
| **579; 957; 1188** | **ODIS command reconstruction is brittle.** For an input `"C:\...\Installer.exe" -i ...`, removing through `Installer.exe` retains the closing quote at the start of `ODIS_ARGS`; appending it to a newly quoted executable introduces an extra quote. Nested `cmd /c` adds another quoting boundary. This is a source-level quoting concern, not runtime-verified here. | Parse executable and arguments explicitly, preserve argument boundaries, and test representative registered command forms. |
| **580; 959; 1189** | **Hardcoded ODIS executable.** Ignores the actual executable location in the registration; missing or differently located ODIS makes routing fail before forced cleanup. | Validate and use the registered/supported installer location; repair missing infrastructure before uninstalling dependents. |
| **934–951; 997–1000** | **Missing metadata triggers deletion rather than recovery.** A product whose manifest is missing cannot run its normal uninstall, then loses registration/files through C2/E. | Recover the matching product/ODIS manifest or installation source and retry supported uninstall. |
| **386–390** | **Display-name deduplication omits distinct packages.** Same-name 32/64-bit entries can represent separate products/components; skipped packages can survive until destructive cleanup. | Identify packages by product code, registry view, context, and version. |
| **338–397** | **Incomplete detection.** Per-user installs and damaged/missing Publisher entries are omitted. Custom installs outside fixed roots survive, while shared infrastructure is still deleted. | Enumerate both machine views and relevant user contexts; correlate MSI/ODIS/package metadata and installation paths. |
| **427–430** | **Incorrect priority matching remains.** `findstr /i "Desktop App"` matches Desktop **or** App; `"Single Sign"` matches Single **or** Sign. “Desktop Connector” can be assigned Desktop App priority. Material Base/Core share one priority; no graph establishes dependencies. | Use literal phrases and verified dependency relationships; reserve infrastructure for the end. |
| **889–897; 1155–1304** | **Retry passes lose ordering; infrastructure is ordinary inventory.** Access/ODIS/Licensing are not explicitly protected from early removal, and retries use registry enumeration order. | Preserve dependency ordering in every pass and block shared-infrastructure removal while dependents remain. |
| **1053–1058; 614–623; 1241–1243; 1301–1303** | **False success and unsuitable switches.** Legacy/generic routes sometimes print/count OK regardless of exit code. Non-BitRock executables receive `--mode unattended`; 32-bit ODIS retries also reach this fallback. | Classify known installer families, validate switches, capture exit codes and logs, and verify actual product state. |
| **959; 1013; 1067** | **Weak failure diagnostics.** ODIS first pass collapses every nonzero exit into `1`; MSI output is discarded and lacks `/L*v`. The original failure may be lost before forced removal. | Preserve exact exits and per-package verbose logs. |
| **599–600; 1025–1031; 2092–2093** | **Reboot-required outcomes are not enforced.** Service restart does not demonstrate that loaded DLLs or marked-for-deletion services have been finalized. | Persist reboot-required status, reboot/resume, then verify before reinstall. |
| **1768; 2015–2016; 2518–2522** | **Service deletion is not verified.** Stop failures, different service names, and pending deletion can leave registration or handles. Conversely, service deletion alone does not remove component package registration. | Discover actual service keys/ImagePaths; wait for stopped/deleted state and validate the owning package’s uninstall. |
| **841; 1773–1781; 2215** | **FlexNet is stopped even when deletion is declined.** Shared consumers can fail until restarted. Deep Clean leaves it stopped while removing shared licensing files. | Preserve shared service state; avoid stopping it unless required and restore it when retained. |
| **1457; 2033; 2226; 2308; 2724** | **Windows Search left stopped.** Both flows stop it but never restore its original state. | Restore service state in guaranteed cleanup/finally logic. |
| **1505–1507; 1526–1528; 2351–2353; 2367–2369** | **Ownership and Everyone full-control grants survive failed deletion.** Partially retained shared/install directories can become insecure or have unexpected ACLs during later setup. | Avoid broad ACL grants; use narrowly scoped recovery with ACL backup/restore and stop on unresolved failures. |
| **1831–1840; 2559–2567** | **Network-license configuration removed.** A fresh network-licensed install can succeed but fail to locate its server. `FLEXLM_TIMEOUT` is not Autodesk-exclusive. | Preserve/export license configuration and offer a separate reset with an explicit restore plan. |
| **1972; 2686** | **PATH cleanup removes live entries.** Despite “dead entries” messaging, every matching entry is removed. Retained/custom Autodesk tools can lose dependencies. | Remove only paths owned by successfully removed packages; preserve valid remaining entries and notify environment consumers. |
| **1885–1896; 2611–2622** | **COM cleanup can be partial.** Deletes returned matching child keys rather than necessarily a complete registration, and does not reconcile 32-bit COM views or all references. | Prefer owning package unregistration; target a verified complete registration/view only when genuinely orphaned. |
| **1882; 2609** | **`.dgn` association deleted without ownership check.** Can remove another CAD application’s association. Broad named class deletion has similar risks. | Check effective association and owner; restore an appropriate remaining handler. |
| **1467; 2318** | **Shell unregistration ignores architecture/failure.** The same `regsvr32` invocation handles both x86 and x64 DLL paths; failure is ignored before files are deleted. | Use matching-bitness unregistration or the owning package; check results. |
| **1794–1795; 2531–2532** | **Firewall deletion based only on display-name substring.** May remove enterprise/custom rules, and misses Autodesk rules with unrelated names. | Match executable/service/package ownership; export exact affected rules and handle managed rules appropriately. |
| **2754–2816** | **Other-user data deleted without backup.** Also leaves other-user classes/environment/per-user install registration inconsistent. Full Clean omits this pass entirely. | Inventory each user context and preserve user data; report skipped contexts and operate through supported uninstall ownership. |
| **757–820; 4880–4894** | **Partial backups do not block destructive cleanup.** Broad AppData trees can contain custom content and cloud/collaboration caches; other-profile data and ProgramData customization are not covered by these backups. | Separate user data from binaries; verify required backups and preserve unsynced/custom data by default. |
| **1637–1640; 2446–2449; 4136–4139** | **Workspace opt-in can permanently lose unsynced files.** Warning/confirmation exists, but no upload verification or backup does. | Keep workspace removal separate; confirm exact workspace/sync health and provide recoverable backup. |
| **4317–4323; 4549** | **PIT existence treated as corruption evidence.** Error 103 repair offers deletion merely because the file exists. | Diagnose corruption rather than infer it from existence; use supported reset only when warranted. |
| **4452; 1402; 2244** | **Lock removal lacks transaction ownership validation.** Deleting a live installation lock can permit conflicting operations. | Prove no relevant installation transaction is active before treating a lock as stale. |
| **4606–4622** | **Hosts repair drops entire matching lines.** A line can contain Autodesk and unrelated aliases or an Autodesk comment; all aliases on that noncomment line are removed. | Parse mappings/aliases and change only approved blocked Autodesk hostnames. |
| **4943–4964; 5192–5207; 5365–5371** | **False readiness inference.** Checks repeat the same narrow publisher/name predicates after those keys were deleted. No MSI consistency/cache/prerequisite or installation check exists. | Report removal, pending reboot, unresolved registrations, and install readiness separately; validate with a fresh supported installation and launch. |

### Low severity / evidence preservation

- **69–85; 1949; 2665:** logs are truncated at startup and backups overwritten with `/y`. Running Deep Clean after Full Clean can overwrite the most useful evidence/backups. Preserve timestamped immutable runs.
- **1825–1828; 2554–2556:** export/deletion failures are ignored while success is printed. Verify both operations and retain failure status.
- **264–312; 733–752; 2183–2201:** an existing restore-point frequency setting is overwritten then deleted. Restore its prior value/type.
- **2; 1429; 1972; 2773:** delayed expansion and interpolated command/PowerShell strings are fragile for paths containing characters such as `!` or apostrophes. A replacement should pass structured arguments and literal paths.
- **1660–1701:** shortcut deletion by name can remove unrelated/custom links and does not establish that product removal succeeded.

### Specific requested hypotheses: confirmed versus absent

- **Deleting cached MSI/MSP files in `C:\Windows\Installer`: not present.** Do not blame this batch’s direct cleanup for such deletion without machine evidence.
- **Partial Installer Products deletion: confirmed**, without reconciliation of related installer stores.
- **Deleting `SharedDLLs` counts: not present.** Do not port such deletion.
- **Leftover `UPI`/`UPI2`/`ODIS`: not deliberately preserved under a successfully deleted Autodesk parent.** However, deletion errors are suppressed, option 2 does no such cleanup, and registration outside that parent is not reconciled.
- **Uninstall entries pointing to deleted uninstallers: directly possible in option 4**, and for undiscovered/per-user entries in either cleanup flow.
- **ODIS service pointing to removed files: particularly clear in Error 103 repair**; Full/Deep Clean attempt a fixed service deletion later, but do not verify success or discover variants.
- **VC++ runtime removal: no explicit implementation.** Relevant Microsoft-side risks here are global reboot-state interference, generic installer termination, and deletion of arbitrary TEMP contents—not a dedicated VC++ purge.

## 5. Product/component coverage and gaps

| Product/component | Implemented coverage | Missing or unsafe boundaries |
|---|---|---|
| **Revit** | Autodesk-published machine ARP discovery; standard routing; `RevitAccelerator.exe` kill; broad Autodesk program/data roots; Revit shortcut/firewall matching. | No explicit `Revit.exe` in the kill/scan lists. Path kill can catch a standard Autodesk installation, but not a custom path lacking the matching strings. No Revit-specific dependency/version graph or reinstall proof. |
| **Revit Interoperability** | Eligible if machine ARP Publisher matches Autodesk; default priority 3 unless another pattern matches. Files under deleted parents are swept. | No explicit name pattern, GUID mapping, dependency handling, or distinct validation. |
| **Revit Content** | “Content Pack” matches priority 1; Autodesk-published ARP entries otherwise discovered generically. ProgramData/Public/Autodesk trees deleted. | Bare “Revit Content” is not a special priority rule. No per-year/content-package relationship or custom content location handling. User families/templates can be destroyed. |
| **Collaboration for Revit / Cloud Models** | Generic ARP and broad AppData deletion; Revit Accelerator process covered. | No explicit Collaboration/Cloud Models discovery, service inventory, add-in relationship, cache ownership, sync/unsynced-model preservation, or standalone checks. |
| **AutoCAD and verticals** | Autodesk Publisher covers registered verticals without a fixed name allowlist; `acad.exe` killed; AutoCAD/acadlt classes, shell DLLs, shortcuts/firewall handled; `AcEventSync.exe` killed. | No explicit Architecture/MEP/Mechanical/Electrical/Map 3D/Plant 3D dependency inventory. Civil 3D and Advance Steel appear in shortcut patterns, not dedicated uninstall logic. Custom install paths and additional vertical processes/services depend on generic detection. |
| **Navisworks** | Generic Autodesk ARP; broad roots; explicit Navisworks desktop/taskbar/firewall matching. | No `roamer.exe` in named kill/scan lists; no Navisworks-specific process/service/content/exporter inventory or product relationship. Generic path kill is the fallback. |
| **Desktop Connector** | Two exact processes; `DesktopConnectorService` stop/disable/delete; generic ARP uninstall; standard program folder removed by parent; fixed `DC`/`ACCDocs` workspace opt-in; explicit verify at 5336–5360. | No custom-workspace discovery, sync-status check, version-specific service/path discovery, or independent uninstall recovery. Standalone workspace option stops service without restarting it. |
| **Autodesk Access** | `AdskAccessServiceHost`, Access executable names; generic ARP; AdODIS root deletion; version probe at 4227. | No separate dedicated Access uninstaller beyond generic ARP and RemoveODIS. No service-variant discovery or component/package reconciliation. |
| **Autodesk Desktop App** | Dedicated `removeAdAppMgr.exe`; SDS removal; `AdAppMgrSvc`; two process names; parent deletion. | Uninstaller results ignored; Desktop/App priority matching is too broad. |
| **Genuine Service** | `GenuineService.exe`; generic ARP priority 8; service string `"Autodesk Genuine Service"`; PIT/id.dat removal; two explicit folders. | Hardcoded service identifier only. If actual service key differs, `sc` deletion can miss it; no discovery from ImagePath. “Last” is contradicted by earlier parent deletion. No package-state verification. |
| **Licensing Service** | Two process names; `AdskLicensingService`; explicit BitRock uninstall; sc-delete fallback; x86 shared parent removal; license state cleanup. | No verification of service/package disappearance, pending deletion, alternate versions/locations, or remaining consumers. Deletes activation state regardless of uninstall outcome. |
| **ODIS** | Hardcoded Installer/RemoveODIS paths; XML-presence preflight; metadata/helper counting; Access service handling; program/data root cleanup; Error 103 diagnostics. | No reliable helper-versus-Installer distinction; no metadata recovery; no dependency graph; unchecked RemoveODIS result; timeout can leave running transaction; Error 103 reset can orphan service registration. |
| **AdSSO / Identity Manager / CER** | `AdSSO.exe`, `AdskIdentityManager.exe`; explicit Identity Manager uninstall; URL classes; broad Autodesk roots; CER dialog directory. | No explicit AdSSO package/folder uninstaller path or CER package inventory. Coverage depends primarily on ARP and parent sweeping. |

Relevant definitions: **32–44**; generic inventory **338–434**; cleanup **1388–1594**, **2232–2405**. Desktop Connector additions are documented in `CHANGELOG.md:5–23` and `README.md:68–76`.

## 6. Things worth reusing

Reuse these as **inventory seeds**, with ownership verification—not as unconditional deletion rules.

### Product matching and identity

**338–397:**

```text
Publisher contains "Autodesk"
DisplayName
DisplayVersion
UninstallString
Source registry key + registry view
```

Keep publisher matching as one signal; expand discovery beyond it.

**421–432:**

```text
Enabler | Plugin | Add-in | Addon | Content Pack |
Language Pack | Service Pack | Material Library |
Medium Resolution | Genuine
```

Use literal phrases. Correct `"Desktop App"` and `"Single Sign"` to phrase matching. The script supplies **no reusable Autodesk product-GUID family patterns**: it merely extracts the first `{...}` token from an MSI command (**592**, **1008**). A replacement needs verified product-code data or package enumeration.

### Process names

Verbatim `KILL_PROCS`, **32**:

```text
AdSSO.exe AdskLicensingService.exe AdskLicensingAgent.exe
AdskIdentityManager.exe GenuineService.exe AdAppMgrSvc.exe
AutodeskDesktopApp.exe RevitAccelerator.exe acad.exe lmgrd.exe
adskflex.exe AdskAccessServiceHost.exe AdskAccessService.exe
AdskAccessCore.exe ADPClientService.exe AcEventSync.exe
FNPLicensingService64.exe Installer.exe setup.exe AdODIS.exe
DesktopConnector.Applications.Tray.exe
DesktopConnector.Core.Service.exe AdskAccessUIHost.exe
```

Treat `Installer.exe`, `setup.exe`, `lmgrd.exe`, and FlexNet processes as shared/generic until path and ownership are proven. Add product processes missing from this source only after separate verification.

### Service names

**35**, **841–842**:

```text
AdskLicensingService
AdskAccessServiceHost
AdAppMgrSvc
AdskNLM
DesktopConnectorService
Autodesk Genuine Service
FlexNet Licensing Service 64
```

Discover actual service keys, binary paths, dependencies, and consumers rather than assuming these strings are exhaustive.

### Folder inventory

The exact whole-root list in **3.1** is reusable as a **search/ownership boundary**. The explicit component paths in **3.2** are useful discovery seeds. Preserve the distinction between:

```text
Program binaries/shared components
Installer infrastructure and recovery metadata
Licensing/identity state
User settings/custom content
Cloud workspaces and unsynced data
```

The existing workspace opt-in concept is worth retaining: **697–715**, **2154–2172**, **4121–4130**. Add recoverable backup and sync validation.

### Operational ideas worth retaining with corrections

- Inventory and preview before mutation.
- Dependency-aware removal, extended to actual package relationships.
- Missing ODIS metadata detection, followed by recovery rather than forced erasure.
- Vendor uninstallers before remnant cleanup.
- Per-package logs with original exit codes and verbose MSI logging.
- Recognition of `3010`/`1641`, followed by a real reboot/resume barrier.
- Registry exports and user-data backups with verified success and immutable run directories.
- Pair-aware reading of pending rename operations for diagnostics; preserve legitimate operations.
- Separate reporting of user workspaces from removable remnants.
- Verification that distinguishes successful uninstall, unresolved state, reboot requirements, and demonstrated fresh-install success.