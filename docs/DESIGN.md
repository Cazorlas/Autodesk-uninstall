# AutodeskCleaner - design contract

Goal: remove Revit, AutoCAD (and verticals), Navisworks, Desktop Connector and the rest of the Autodesk stack
so that a **fresh reinstall works**. The reference tool (`docs/reference-tool-analysis.md`) breaks reinstalls
because it deletes registration and shared folders by force after failed uninstalls. This tool does the opposite:
the vendor uninstaller does the removal, we only order it, verify it, and clean what is provably orphaned.

Runtime: **Windows PowerShell 5.1** (`powershell.exe`), also loads in pwsh 7. Every `.ps1`/`.psm1` with non-ASCII
text is saved **UTF-8 with BOM**. Tests: **Pester 3.4.0** syntax only (`Should Be`, `Should BeExactly`, `Should Throw`,
`Mock`, `Assert-MockCalled`, `Context`/`It`, `BeforeEach`; no `BeforeAll`, no dash operators like `-Be`).
Test command: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1` (imports Pester 3.4.0, runs
`Invoke-Pester -Path tests -EnableExit`).

## Hard rules (every task)

1. Never delete an Uninstall (ARP) key or any `Installer\Products|Features|UpgradeCodes|UserData` key by hand. The
   only exception is `Repair-AdskReinstallBlocker` for an ARP key whose uninstaller file is missing AND has no MSI
   registration, opt-in per item, exported to `.reg` first.
2. A failed uninstall (exit not in 0, 1605, 1614, 3010, 1641) marks its **group+year failed**: no further steps and no
   remnant cleanup for that group+year, and no Shared/Infrastructure step for the whole run.
3. 3010/1641 set `RebootRequired`; the report says "reboot before reinstalling".
4. Never write RunOnce/Run entries, never touch `PendingFileRenameOperations`, CBS/WU reboot flags, `%TEMP%` as a
   whole, FLEXlm/Macrovision, VC++/.NET/WebView2 runtimes, `C:\Windows\Installer`, `SharedDLLs`.
5. Never kill processes by generic name (`Installer.exe`, `setup.exe`). Kill only processes whose `Path` is under an
   Autodesk folder being removed, and only after asking (UI) / when `-Force` is given.
6. Never use `Win32_Product` (it triggers MSI self-repair). Read the registry.
7. Shared / Infrastructure packages are removed only when the plan removes **every** non-Shared Autodesk package
   (i.e. nothing that needs them stays installed). Removing only Revit 2025 leaves Licensing, ODIS, Access, Genuine,
   Material Library, CER, SSO, RealDWG etc. in place.
8. Remnant cleanup **moves** folders into a quarantine on the same drive (`<drive>:\AutodeskCleaner.Quarantine\<runId>\`),
   never deletes; registry remnants are exported to `.reg` before delete. Only per-group, per-year paths, never a whole
   root (`C:\Program Files\Autodesk`, `Autodesk Shared`, `C:\ProgramData\Autodesk`).
9. User data (`%APPDATA%`/`%LOCALAPPDATA%` product settings, Revit add-in folders, Desktop Connector workspaces
   `%USERPROFILE%\DC`, `%USERPROFILE%\ACCDocs`) is never touched unless `-IncludeUserData`, and workspaces never.
10. `-DryRun` (default in the UI until the user confirms) changes nothing: no process, no registry write, no file move.
11. Every side effect goes through one small wrapper function so tests can `Mock` it:
    `Get-AdskRegistryRows`, `Invoke-AdskProcess`, `Test-AdskPath`, `Move-AdskItem`, `Export-AdskRegistryKey`,
    `Remove-AdskRegistryKey`, `Get-AdskService`, `Get-AdskProcessByPath`, `Stop-AdskProcess`, `Test-AdskMsiBusy`.

## Layout

```
Start-AutodeskCleaner.bat          double-click launcher, self-elevates, runs powershell.exe 5.1
AutodeskCleaner.ps1                console menu (Vietnamese UI)
src/AutodeskCleaner.psm1           dot-sources src/*.ps1, exports public functions
src/Wrappers.ps1                   side-effect wrappers (rule 11)
src/Inventory.ps1                  T1
src/Plan.ps1                       T1
src/Executor.ps1                   T2
src/Cleanup.ps1                    T3
src/Readiness.ps1                  T3
tests/run-tests.ps1, tests/*.Tests.ps1, tests/fixtures/arp-host.json
```

## Data contract

`Get-AdskRegistryRows` returns raw rows with exactly the fields of `tests/fixtures/arp-host.json`:
`Hive View KeyName DisplayName DisplayVersion Publisher UninstallString QuietUninstallString SystemComponent
WindowsInstaller InstallLocation ParentKeyName`, from `HKLM\...\Uninstall` (View 64), `HKLM\SOFTWARE\WOW6432Node\...\Uninstall`
(View 32) and `HKCU\...\Uninstall` (View 64). Rows kept: Publisher matches `Autodesk`, or DisplayName matches
`Autodesk|Revit|AutoCAD|Navisworks|Desktop Connector|Civil 3D|Inventor|3ds Max|Maya`.

`ConvertTo-AdskPackage` -> `[pscustomobject]` with:

| Field | Meaning |
|---|---|
| Id | `"<Hive>\<View>\<KeyName>"` |
| DisplayName, Version, Publisher, InstallLocation | copied |
| Year | int 2010-2099 from DisplayName (`\b(20\d\d)\b`), else `$null` |
| Hidden | `SystemComponent -eq 1` |
| Kind | `ODIS` (exe ends `\AdODIS\V1\Installer.exe`), `Helper` (`AdskUninstallHelper.exe`), `MSI` (`msiexec` with a `{GUID}`), `Exe` (any other command), `None` (no command) |
| ProductCode | `{GUID}` for MSI (from the command, else from KeyName when it is a GUID), else `$null` |
| Exe, Arguments | from `Split-AdskCommand` of `QuietUninstallString` if present, else `UninstallString` |
| ThirdParty | Publisher present and not matching `Autodesk` (pyRevit, RevitLookup, SDKs...) |
| Group | see below |
| Role | `Update`, `LanguagePack`, `Content`, `Addon`, `Main`, `MaterialLibrary`, `Shared`, `Infrastructure`, `DevTool` |

`Split-AdskCommand` handles: quoted exe (`"C:\a b\x.exe" args`), unquoted exe path with spaces up to the first
`.exe` (`C:\Program Files\Autodesk\AdODIS\V1\Installer.exe -i uninstall ...`), `MsiExec.exe /I{GUID}` / `/X{GUID}`.

Groups (first match wins, case-insensitive, on DisplayName):
`DesktopConnector` (`Desktop Connector`), `Navisworks` (`Navisworks`), `Revit` (`Revit|RSA |REX |Results Explorer|
Generative Design For Revit|Personal Accelerator`), `Civil3D` (`Civil 3D`), `AutoCAD` (`AutoCAD|ACAD|AutoCAD Open in
Desktop`), `Inventor`, `3dsMax` (`3ds Max`), `Maya`, `Infrastructure` (`Licensing|Genuine Service|Autodesk Access|
Single Sign On|Identity Manager|Desktop App|App Manager|ODIS|Autodesk Installer`), `Shared` (`Material Library|
RealDWG|Interoperability Engine|CER|Featured Apps|Save to Web|Autodesk Shared`), else `Other`.
Role `DevTool`: `SDK$|\bSDK\b|RevitLookup|RevitAddinManager|pyRevit`; these and ThirdParty are excluded from plans
unless `-IncludeThirdParty`.

## Plan contract

`New-AdskRemovalPlan -Packages <pkg[]> [-Group <string[]>] [-Year <int[]>] [-All] [-IncludeThirdParty]` ->
ordered `Step[]`: `Order Package Action Reason`. `Action` is `Uninstall` for visible packages (Hidden = false) and
`UninstallIfPresent` for Hidden packages of the same group+year (ODIS bundles remove their hidden MSI children; the
executor re-checks the key and skips when already gone). Kind `None` -> no step, listed in `Skipped`.
Order inside the run: Addon/Content/LanguagePack -> Update -> Main -> hidden leftovers -> (only with rule 7)
MaterialLibrary -> Shared -> Infrastructure in the fixed order `Desktop App/App Manager, Access, Single Sign On,
Identity Manager, Genuine Service, Licensing, ODIS`. Year-less group members (e.g. `Generative Design For Revit`) go
with the group only when every year of that group is selected or `-Year` is not given.
The plan object also carries `Kept` (packages left installed and why) and `SharedRemoved` (bool).

## Executor contract (T2)

`Invoke-AdskRemovalPlan -Plan -LogDir [-DryRun] [-TimeoutMinutes 60]` -> result per step:
`Step Status(Succeeded|AlreadyGone|Failed|Skipped|TimedOut|DryRun) ExitCode Command LogFile`, plus `RebootRequired`
and `FailedGroups`. MSI: `msiexec.exe /x {GUID} /qn /norestart REBOOT=ReallySuppress /L*v "<LogDir>\<n>-<code>.log"`.
ODIS: registered exe + args, `-q` appended when absent. Helper: exe + `-q`. Exe: registered command, no guessing,
QuietUninstallString preferred, otherwise step is `Skipped` with reason "no silent uninstall". Waits while
`Test-AdskMsiBusy` (the `Global\_MSIExecute` mutex) is held. A timeout stops the whole run (no next step).

## Cleanup + readiness contract (T3)

`Get-AdskRemnant -Packages <remaining> -Removed <group,year pairs> [-IncludeUserData]` -> candidate list
`Path Kind(Folder|RegistryKey) Group Year UserData Reason`, only for group+year pairs with no remaining package.
`Invoke-AdskRemnantCleanup -Remnant -RunId [-DryRun]` moves/exports+deletes per rule 8.
`Test-AdskReinstallReadiness` (read-only) -> findings `Severity Code Message Target Fix`:
`OrphanArp` (uninstaller exe or ODIS `-m` manifest missing), `MsiCacheMissing` (MSI product registered, its
`LocalPackage` under `C:\Windows\Installer` missing), `MsiNoArp` (Autodesk MSI registration without ARP entry),
`ServiceBinaryMissing` (Autodesk service whose ImagePath file is missing), `PendingReboot`, `OldToolRunOnce`
(`RunOnce\AutodeskCleanup` left by the reference tool - it deletes `C:\Program Files\Autodesk` at next logon and would
wipe a fresh install), `IfeoDebugger` (IFEO `Debugger` on Autodesk exes), `OdisLock` (stale
`C:\ProgramData\Autodesk\ODIS\AdODISInstaller.run.lock` with no installer running), `MsiBusy`.
`Repair-AdskReinstallBlocker -Finding <f> [-DryRun]` fixes only `OldToolRunOnce`, `IfeoDebugger`, `OdisLock`,
`OrphanArp` (rule 1 exception); others return guidance text only.
