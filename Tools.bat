@echo off
setlocal EnableExtensions
title IT Tools v2026.11.20 - All-in-One Windows Troubleshooter
color 0B

:: User-context tasks: started by the elevated tool through explorer.exe so
:: they run as the logged-on user (needed for OneDrive, mapped drives,
:: saved credentials, Start menu packages). No admin rights in this mode.
set "ITSELF=%~f0"
if /i "%~1"=="/user" goto USERMODE

:: ------------------------------------------------------------
::  Require administrator rights (relaunch elevated if needed)
:: ------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Administrator permission is required.
    echo  Requesting administrator access...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        rem Keep /console or /opt N when relaunching as admin
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

:: Window size + large scroll buffer so long output is not lost
mode con cols=112 lines=48
powershell -NoProfile -Command "try { $h=$Host.UI.RawUI; $h.BufferSize = New-Object Management.Automation.Host.Size(112,5000) } catch {}" >nul 2>&1

:: ------------------------------------------------------------
::  Paths: reports + log go to a fixed folder (not user profile)
:: ------------------------------------------------------------
set "ITROOT=%SystemDrive%\ITTools"
set "REPORTROOT=%ITROOT%\Reports"
set "LOGFILE=%ITROOT%\ITTools.log"
if not exist "%ITROOT%" (
    mkdir "%ITROOT%" >nul 2>&1
    rem Admins + SYSTEM full control, normal users read-only. SIDs = any language.
    icacls "%ITROOT%" /inheritance:r /grant:r *S-1-5-32-544:^(OI^)^(CI^)F *S-1-5-18:^(OI^)^(CI^)F *S-1-5-32-545:^(OI^)^(CI^)RX >nul 2>&1
)
if not exist "%REPORTROOT%" mkdir "%REPORTROOT%" >nul 2>&1
if not exist "%ITROOT%\bin" mkdir "%ITROOT%\bin" >nul 2>&1
:: Copy of this script that the logged-on user can run for user-context tasks.
:: Then continue from that copy, so temp cleanup can never delete the running
:: script (the web loader starts it from %TEMP%).
if /i not "%~dp0"=="%ITROOT%\bin\" (
    copy /y "%~f0" "%ITROOT%\bin\Tools.bat" >nul 2>&1
    if exist "%ITROOT%\bin\Tools.bat" (
        "%ITROOT%\bin\Tools.bat" %*
        exit /b
    )
)

:: ------------------------------------------------------------
::  ACCESS PASSWORD (optional)
::  Asks for a password before the tool opens. Leave PWHASH empty for no
::  password. To set one, put the SHA-256 hash of your password below.
::  Get the hash (run once, any PC), then paste the result as PWHASH:
::    powershell -NoProfile -Command "[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('YOUR-PASSWORD'))).Replace('-','')"
::  Asked once per run; tools opened from the window inherit the sign-in.
:: ------------------------------------------------------------
set "PWHASH=6EE32AD748778F2485E75BADAD714CC0346F15FABACCB915C3726416CED7E58E"
if not defined PWHASH goto AUTHOK
if defined ITTOOLS_AUTH goto AUTHOK
set "ITPWH=%PWHASH%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$want=$env:ITPWH; for($i=1;$i -le 3;$i++){ $s=Read-Host 'Enter IT Tools password' -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try{$p=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}; $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($p))).Replace('-',''); if($h -ieq $want){exit 0}; Write-Host 'Wrong password.' -ForegroundColor Yellow }; exit 1"
if errorlevel 1 (
    echo.
    echo  Access denied.
    timeout /t 2 >nul
    exit /b
)
set "ITTOOLS_AUTH=1"
:AUTHOK
set "ITPWH="

:: ------------------------------------------------------------
::  Windows setup (OOBE) - Shift+F10 during setup, then run Tools.bat.
::  While setup runs only the local-account menu is shown. Tools.bat /oobe
::  opens the same menu on purpose.
:: ------------------------------------------------------------
set "OOBEFLAG="
for /f "tokens=3" %%A in ('reg query "HKLM\SYSTEM\Setup" /v OOBEInProgress 2^>nul ^| find /i "OOBEInProgress"') do set "OOBEFLAG=%%A"
if /i "%OOBEFLAG%"=="0x1" goto OOBEMENU
if /i "%~1"=="/oobe" goto OOBEMENU

:: ------------------------------------------------------------
::  Target user = owner of explorer.exe in THIS session. Per-user fixes
::  (Temp, Teams, Outlook, browser cache...) use this user's profile even
::  when the tech elevated with a different admin account.
:: ------------------------------------------------------------
set "TUSER=" & set "TSID=" & set "TPROFILE=" & set "TROAMING=" & set "TLOCAL=" & set "TEXPLORER="
for /f "usebackq tokens=1-6 delims=|" %%A in (`powershell -NoProfile -Command "$s=(Get-Process -Id $PID).SessionId; $e=Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $s | Select-Object -First 1; $x='0'; if ($e) { $w=Get-CimInstance Win32_Process -Filter ('ProcessId=' + $e.Id); $o=Invoke-CimMethod -InputObject $w -MethodName GetOwner; $u=$o.Domain + '\' + $o.User; $sid=(Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid).Sid; $x='1' } else { $i=[Security.Principal.WindowsIdentity]::GetCurrent(); $u=$i.Name; $sid=$i.User.Value }; $p=(Get-CimInstance Win32_UserProfile -Filter ('SID=''' + $sid + '''')).LocalPath; if (-not $p) { $p=$env:USERPROFILE }; $sf=Get-ItemProperty ('Registry::HKEY_USERS\' + $sid + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders') -ErrorAction SilentlyContinue; $r=$sf.AppData; $l=$sf.'Local AppData'; if (-not $r) { $r=$p + '\AppData\Roaming' }; if (-not $l) { $l=$p + '\AppData\Local' }; $u + '|' + $sid + '|' + $p + '|' + $r + '|' + $l + '|' + $x"`) do (
    set "TUSER=%%A"
    set "TSID=%%B"
    set "TPROFILE=%%C"
    set "TROAMING=%%D"
    set "TLOCAL=%%E"
    set "TEXPLORER=%%F"
)
if not defined TPROFILE set "TPROFILE=%USERPROFILE%"
if not defined TLOCAL set "TLOCAL=%LOCALAPPDATA%"
if not defined TROAMING set "TROAMING=%APPDATA%"
if not defined TUSER set "TUSER=%USERDOMAIN%\%USERNAME%"
set "PROFILEWARN="
if /i not "%TUSER%"=="%USERDOMAIN%\%USERNAME%" set "PROFILEWARN=1"

call :LOG "IT Tools started - target user %TUSER%"

:: Every option number that has an :OPTn label. Page links 42 and 69 are handled separately.
set "ALLOPTS=1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87"

:: ------------------------------------------------------------
::  Start mode
::    Tools.bat            window (mouse + keyboard + search) - default
::    Tools.bat /console   text menu
::    Tools.bat /opt 64    run one option in this window, then close
::                         (the window starts every tool this way)
:: ------------------------------------------------------------
set "GUIRUN="
if /i "%~1"=="/opt" goto RUNOPT
if /i "%~1"=="/console" goto MENU
echo.
echo  Opening the IT Tools window...   (text menu: Tools.bat /console)
call :RUNPSI GUI
:: 10 = window closed, 11 = "Text menu" button, anything else = window could not start
if errorlevel 11 goto MENU
if errorlevel 10 goto END
echo  The window could not start on this PC - using the text menu.
timeout /t 3 >nul
goto MENU

:RUNOPT
set "GUIRUN=1"
set "choice=%~2"
title IT Tools - option %choice%
type nul >"%ITROOT%\bin\optstart.flag" 2>nul
for %%N in (%ALLOPTS%) do if "%choice%"=="%%N" goto OPT%%N
echo  Unknown option: %choice%
pause
goto END

:MENU
:: Started by the window for one option: close instead of showing the menu
if defined GUIRUN goto END
cls
set "choice="
echo.
echo  ==========================================================================================================
echo                                   IT TOOLS - WINDOWS TROUBLESHOOTER
echo  ==========================================================================================================
echo   Computer: %COMPUTERNAME%     Admin: %USERDOMAIN%\%USERNAME%     User fixes apply to: %TUSER%
if defined PROFILEWARN echo   [i] Elevated with a different account - per-user fixes still target %TUSER% profile.
call :RUNPS HEALTH
echo  ----------------------------------------------------------------------------------------------------------
echo    NETWORK                                         SYSTEM REPAIR
echo     [1]  Fix Internet / Network - full reset         [9]  Repair System Files - DISM + SFC
echo     [2]  Show Network Information                    [10] Reset Windows Update Components
echo     [3]  Flush DNS Cache                             [11] Force Group Policy Update + Report
echo     [4]  Network Connectivity Test                   [12] Check Disk C: for Errors - chkdsk scan
echo     [5]  Restart Network Adapters                    [13] Create System Restore Point
echo     [6]  Wi-Fi Report + Profiles                     [14] Restart Windows Explorer
echo     [7]  Active Connections / Listening Ports        [15] Open Windows Troubleshoot Settings
echo     [8]  Sync Windows Time                           [16] Reset Microsoft Store Cache
echo.
echo    CLEANUP                                          HARDWARE / DEVICES
echo     [17] Clean Temporary Files                       [21] Battery Health Report
echo     [18] Empty Recycle Bin                           [22] Disk Health - SMART / wear
echo     [19] Show Disk Space                             [23] Problem Devices / Drivers
echo     [20] Clear Microsoft Teams Cache                 [24] Restart Audio Services
echo                                                      [25] Power / Sleep Diagnostics
echo    PRINTERS                                         APPS / ACCOUNTS
echo     [26] Restart Print Spooler                       [28] Open Outlook in Safe Mode
echo     [27] Clear Stuck Print Queue                     [29] Open Credential Manager
echo                                                      [30] Activation Center - Windows + Office
echo    INFO / REPORTS                                    [31] Windows Activation Status
echo     [33] System Information + Uptime                 [32] BitLocker Status
echo     [34] Recent Errors - Event Log 24h
echo     [35] Startup Programs                            TOOLS
echo     [36] Export Installed Software List              [38] Admin Consoles Shortcuts
echo     [37] Generate FULL IT Report - for ticket        [39] Open Reports Folder
echo                                                      [40] Restart Computer
echo                                                      [41] Update IT Tools from Web
echo.
echo     [42] MORE TOOLS: Outlook/Teams, Office, OneDrive, Drives, Domain, Speed, Accounts, SECURITY, REMOTE ^>^>
echo     [69] NEW DIAGNOSTICS ^& ADMIN CENTER - Hardware, BSOD, Performance, Drivers, Security, Network
echo.
echo     [0]  Exit
echo  ==========================================================================================================
set /p "choice=  Option number (69 = NEW DIAGNOSTICS), or search - e.g. printer, slow, outlook: "
if not defined choice goto MENU
set "SEARCHQ=%choice%"
set "choice=%choice: =%"
:: Marker: reports newer than this file belong to the option that runs now
type nul >"%ITROOT%\bin\optstart.flag" 2>nul

for %%N in (%ALLOPTS%) do (
    if "%choice%"=="%%N" goto OPT%%N
)
if "%choice%"=="42" goto MENU2
if "%choice%"=="69" goto MENU3
if "%choice%"=="0" goto END
set "SEARCHBACK=MENU"
goto SEARCH

:: ============================================================
::  NETWORK
:: ============================================================
:OPT1
cls
echo  Fix Internet and Network Problems
echo  ---------------------------------
echo  This releases the IP address, resets Winsock and the TCP/IP stack.
echo  WARNING: the network will drop. Remote / RDP sessions will disconnect.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Network full reset"
ipconfig /flushdns
ipconfig /release
ipconfig /renew
ipconfig /registerdns
netsh winsock reset
netsh int ip reset
echo.
echo  Network repair commands completed. A RESTART is required for Winsock/IP reset.
call :DONE
goto MENU

:OPT2
cls
echo  Network Information
echo  -------------------
ipconfig /all
echo.
echo  --- Routing table ---
route print -4
call :DONE
goto MENU

:OPT3
cls
call :LOG "Flush DNS"
echo  Flushing DNS Cache...
echo.
ipconfig /flushdns
echo.
echo  DNS cache cleared.
call :DONE
goto MENU

:OPT4
cls
call :LOG "Connectivity test"
echo  Network Connectivity Test
echo  -------------------------
set "GATEWAY="
for /f "usebackq delims=" %%G in (`powershell -NoProfile -Command "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop"`) do set "GATEWAY=%%G"
echo.
if defined GATEWAY (
    echo  [1/5] Ping default gateway %GATEWAY%
    ping -n 3 %GATEWAY%
) else (
    echo  [1/5] No default gateway found - check cable / Wi-Fi / DHCP.
)
echo.
echo  [2/5] Ping public IP 8.8.8.8 - tests internet without DNS
ping -n 3 8.8.8.8
echo.
echo  [3/5] DNS lookup www.microsoft.com
nslookup www.microsoft.com
echo.
echo  [4/5] HTTPS port 443 test to www.microsoft.com
powershell -NoProfile -Command "Test-NetConnection www.microsoft.com -Port 443 -WarningAction SilentlyContinue | Select-Object ComputerName, RemoteAddress, TcpTestSucceeded | Format-List"
echo  [5/5] Proxy setting
netsh winhttp show proxy
echo.
echo  Tips: gateway fails = local network/cable/Wi-Fi.  8.8.8.8 fails = ISP/firewall.
echo        DNS fails but 8.8.8.8 OK = DNS problem - try option 3 or check DNS servers.
call :DONE
goto MENU

:OPT5
cls
echo  Restart Network Adapters
echo  ------------------------
echo  WARNING: the network will drop briefly. Remote / RDP sessions may disconnect.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Restart network adapters"
powershell -NoProfile -Command "Get-NetAdapter | Where-Object {$_.Status -ne 'Disabled'} | ForEach-Object { Write-Host ('  Restarting ' + $_.Name + ' ...'); Restart-NetAdapter -Name $_.Name -Confirm:$false }; Start-Sleep 5; Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize"
call :DONE
goto MENU

:OPT6
cls
call :LOG "Wi-Fi report"
echo  Wi-Fi Report
echo  ------------
netsh wlan show interfaces
echo.
echo  --- Saved Wi-Fi profiles ---
netsh wlan show profiles
echo.
echo  Generating WLAN report (HTML)...
netsh wlan show wlanreport >nul 2>&1
if exist "%ProgramData%\Microsoft\Windows\WlanReport\wlan-report-latest.html" (
    copy /y "%ProgramData%\Microsoft\Windows\WlanReport\wlan-report-latest.html" "%REPORTROOT%\%COMPUTERNAME%_WlanReport.html" >nul
    echo  Saved: %REPORTROOT%\%COMPUTERNAME%_WlanReport.html
    start "" "%REPORTROOT%\%COMPUTERNAME%_WlanReport.html"
) else (
    echo  WLAN report not available - no Wi-Fi adapter or WLAN service stopped.
)
call :DONE
goto MENU

:OPT7
cls
call :LOG "Active connections"
echo  Listening Ports with Process
echo  ----------------------------
powershell -NoProfile -Command "Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess, @{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} | Sort-Object LocalPort | Format-Table -AutoSize"
echo  Established Connections
echo  -----------------------
powershell -NoProfile -Command "Get-NetTCPConnection -State Established | Select-Object LocalPort, RemoteAddress, RemotePort, @{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} | Sort-Object Process | Format-Table -AutoSize"
call :DONE
goto MENU

:OPT8
cls
call :LOG "Time sync"
echo  Sync Windows Time
echo  -----------------
echo  Wrong time breaks domain login, Outlook/Teams sign-in and HTTPS sites.
echo.
sc config w32time start= auto >nul
net start w32time >nul 2>&1
w32tm /resync /force
echo.
w32tm /query /status
echo.
echo  Current time: %date% %time%
call :DONE
goto MENU

:: ============================================================
::  SYSTEM REPAIR
:: ============================================================
:OPT9
cls
call :LOG "DISM + SFC"
echo  Windows System Repair - this can take 15-30 minutes.
echo.
echo  Running DISM RestoreHealth...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
echo  Running System File Checker...
sfc /scannow
echo.
echo  System repair scan completed. Restart if files were repaired.
call :DONE
goto MENU

:OPT10
cls
echo  Reset Windows Update Components
echo  -------------------------------
echo  Stops update services, renames SoftwareDistribution and catroot2, restarts services.
echo  Use when updates are stuck, fail repeatedly or show error codes.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Reset Windows Update"
net stop wuauserv /y
net stop bits /y
net stop cryptsvc /y
net stop msiserver /y
if exist "%SystemRoot%\SoftwareDistribution.old" rd /s /q "%SystemRoot%\SoftwareDistribution.old"
if exist "%SystemRoot%\System32\catroot2.old" rd /s /q "%SystemRoot%\System32\catroot2.old"
ren "%SystemRoot%\SoftwareDistribution" SoftwareDistribution.old
ren "%SystemRoot%\System32\catroot2" catroot2.old
net start cryptsvc
net start bits
net start wuauserv
net start msiserver
echo.
echo  Windows Update reset done. Open Settings - Windows Update and check again.
call :DONE
goto MENU

:OPT11
cls
call :LOG "gpupdate"
echo  Force Group Policy Update
echo  -------------------------
gpupdate /force
echo.
call :STAMP
echo  Creating Group Policy result report...
gpresult /h "%REPORTROOT%\%COMPUTERNAME%_GPResult_%STAMP%.html" /f >nul 2>&1
if errorlevel 1 gpresult /scope computer /h "%REPORTROOT%\%COMPUTERNAME%_GPResult_%STAMP%.html" /f >nul 2>&1
if exist "%REPORTROOT%\%COMPUTERNAME%_GPResult_%STAMP%.html" (
    echo  Saved: %REPORTROOT%\%COMPUTERNAME%_GPResult_%STAMP%.html
) else (
    echo  GP report not created - device may not be domain joined.
)
call :DONE
goto MENU

:OPT12
cls
call :LOG "chkdsk scan"
echo  Check Disk C: for Errors - online scan, no restart needed
echo  ---------------------------------------------------------
chkdsk %SystemDrive% /scan
echo.
echo  If errors are found, run:  chkdsk %SystemDrive% /f   - it will be scheduled for next restart.
call :DONE
goto MENU

:OPT13
cls
call :LOG "Restore point"
echo  Create System Restore Point
echo  ---------------------------
echo  Note: Windows allows only one new restore point every 24 hours by default.
echo.
powershell -NoProfile -Command "try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue; Checkpoint-Computer -Description 'IT Tools manual restore point' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Host '  Restore point created.' -ForegroundColor Green } catch { Write-Host ('  Failed: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
powershell -NoProfile -Command "Get-ComputerRestorePoint | Select-Object -Last 5 SequenceNumber, Description, @{n='Created';e={$_.ConvertToDateTime($_.CreationTime)}} | Format-Table -AutoSize"
call :DONE
goto MENU

:OPT14
cls
call :LOG "Restart Explorer"
echo  Restarting Windows Explorer for this session...
call :KILLAPP explorer
call :ENSUREEXPLORER
echo  Windows Explorer restarted.
call :DONE
goto MENU

:OPT15
cls
echo  Opening Windows Troubleshooting Settings...
start ms-settings:troubleshoot
timeout /t 2 >nul
goto MENU

:OPT16
cls
call :LOG "wsreset"
echo  Resetting Microsoft Store cache - Store will open when finished...
start "" wsreset.exe
timeout /t 3 >nul
goto MENU

:: ============================================================
::  CLEANUP
:: ============================================================
:OPT17
cls
call :LOG "Clean temp"
echo  Cleaning temporary files...
echo.
set "TTEMP=%TLOCAL%\Temp"
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "'{0:N0} MB' -f ((Get-ChildItem $env:TEMP, $env:TTEMP, (Join-Path $env:WINDIR 'Temp') -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)"`) do echo  Temp size before: %%S
del /f /s /q "%TEMP%\*" >nul 2>&1
for /d %%D in ("%TEMP%\*") do rd /s /q "%%D" >nul 2>&1
if exist "%TTEMP%\" (
    del /f /s /q "%TTEMP%\*" >nul 2>&1
    for /d %%D in ("%TTEMP%\*") do rd /s /q "%%D" >nul 2>&1
)
del /f /s /q "%WINDIR%\Temp\*" >nul 2>&1
for /d %%D in ("%WINDIR%\Temp\*") do rd /s /q "%%D" >nul 2>&1
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "'{0:N0} MB' -f ((Get-ChildItem $env:TEMP, $env:TTEMP, (Join-Path $env:WINDIR 'Temp') -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)"`) do echo  Temp size after:  %%S
echo.
echo  Temporary file cleanup completed. Files in use are skipped.
echo  For deeper cleanup - update cache, dumps, Windows.old - use option 61 Deep Clean.
call :DONE
goto MENU

:OPT18
cls
call :CONFIRM "Empty the Recycle Bin on all drives?" || goto MENU
call :LOG "Empty recycle bin"
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"
echo  Recycle Bin emptied.
call :DONE
goto MENU

:OPT19
cls
echo  Disk Space
echo  ----------
powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}}, @{n='FreePct';e={[math]::Round($_.FreeSpace*100/$_.Size,0)}} | Format-Table -AutoSize"
echo  Under 10 FreePct on C: causes slowness and failed updates.
call :DONE
goto MENU

:OPT20
cls
echo  Clear Microsoft Teams Cache - for user %TUSER%
echo  ------------------------------------------------
echo  Teams will be closed. User stays signed in, settings are kept.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Clear Teams cache"
call :KILLAPP ms-teams
call :KILLAPP Teams
timeout /t 3 >nul
rem New Teams
if exist "%TLOCAL%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams" (
    rd /s /q "%TLOCAL%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams" >nul 2>&1
    echo  New Teams cache cleared.
)
rem Classic Teams
if exist "%TROAMING%\Microsoft\Teams" (
    for %%F in ("Cache" "blob_storage" "databases" "GPUCache" "IndexedDB" "Local Storage" "tmp" "Code Cache" "Service Worker") do rd /s /q "%TROAMING%\Microsoft\Teams\%%~F" >nul 2>&1
    echo  Classic Teams cache cleared.
)
echo.
echo  Done. Start Teams again from the Start menu.
call :DONE
goto MENU

:: ============================================================
::  HARDWARE / DEVICES
:: ============================================================
:OPT21
cls
call :LOG "Battery report"
call :STAMP
echo  Generating Battery Health Report...
powercfg /batteryreport /output "%REPORTROOT%\%COMPUTERNAME%_Battery_%STAMP%.html"
if exist "%REPORTROOT%\%COMPUTERNAME%_Battery_%STAMP%.html" start "" "%REPORTROOT%\%COMPUTERNAME%_Battery_%STAMP%.html"
echo.
echo  Compare DESIGN CAPACITY vs FULL CHARGE CAPACITY. Below ~60 percent = replace battery.
call :DONE
goto MENU

:OPT22
cls
call :LOG "Disk health"
echo  Disk Health
echo  -----------
powershell -NoProfile -Command "Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, HealthStatus, OperationalStatus | Format-Table -AutoSize"
echo  Reliability counters - Wear 0 is new, 100 is worn out:
powershell -NoProfile -Command "Get-PhysicalDisk | ForEach-Object { $d=$_; $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Disk=$d.FriendlyName; TempC=$r.Temperature; Wear=$r.Wear; PowerOnHours=$r.PowerOnHours; ReadErrors=$r.ReadErrorsUncorrected; WriteErrors=$r.WriteErrorsUncorrected} } | Format-Table -AutoSize"
echo  Empty values = not reported by this drive/controller.
call :DONE
goto MENU

:OPT23
cls
call :LOG "Problem devices"
echo  Devices with Problems
echo  ---------------------
powershell -NoProfile -Command "$p = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' }; if ($p) { $p | Group-Object Status, Class, FriendlyName | Select-Object Count, @{n='Status';e={$_.Group[0].Status}}, @{n='Class';e={$_.Group[0].Class}}, @{n='Device';e={$_.Group[0].FriendlyName}}, @{n='ProblemCode';e={$_.Group[0].Problem}} | Sort-Object Status | Format-Table -AutoSize -Wrap } else { Write-Host '  No problem devices found.' -ForegroundColor Green }"
echo.
call :CONFIRM "Open Device Manager?" && start devmgmt.msc
goto MENU

:OPT24
cls
call :LOG "Restart audio"
echo  Restarting Windows Audio Services...
echo.
net stop Audiosrv /y
net stop AudioEndpointBuilder /y
net start AudioEndpointBuilder
net start Audiosrv
echo.
echo  Audio services restarted. If still no sound, check default device: mmsys.cpl
call :DONE
goto MENU

:OPT25
cls
call :LOG "Power diagnostics"
echo  Power / Sleep Diagnostics
echo  -------------------------
echo  --- What is preventing sleep right now ---
powercfg /requests
echo  --- Last wake source ---
powercfg /lastwake
echo  --- Wake timers ---
powercfg /waketimers
echo  --- Devices allowed to wake the PC ---
powercfg /devicequery wake_armed
echo  --- Active power plan ---
powercfg /getactivescheme
call :DONE
goto MENU

:: ============================================================
::  PRINTERS
:: ============================================================
:OPT26
cls
call :LOG "Restart spooler"
echo  Restarting Print Spooler...
net stop spooler /y
net start spooler
echo.
echo  Print Spooler restarted. Existing print jobs were kept.
echo.
powershell -NoProfile -Command "Get-Printer | Select-Object Name, PrinterStatus, PortName, Shared | Format-Table -AutoSize"
call :DONE
goto MENU

:OPT27
cls
echo  Clear Stuck Print Queue
echo  -----------------------
echo  ALL pending print jobs for ALL printers on this PC will be deleted.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Clear print queue"
net stop spooler /y
del /f /q "%SystemRoot%\System32\spool\PRINTERS\*.*" >nul 2>&1
net start spooler
echo.
echo  Print queue cleared and spooler restarted.
call :DONE
goto MENU

:: ============================================================
::  APPS / ACCOUNTS
:: ============================================================
:OPT28
cls
call :LOG "Outlook safe mode"
echo  Starting Outlook in Safe Mode - add-ins disabled...
echo  If Outlook works in Safe Mode, disable add-ins: File - Options - Add-ins.
call :KILLAPP outlook
timeout /t 2 >nul
rem Start as the logged-on user, not elevated
call :LAUNCHUSER OUTLOOKSAFE
timeout /t 3 >nul
goto MENU

:OPT29
cls
echo  Opening Credential Manager - remove old Office / Outlook / network passwords here.
start "" control /name Microsoft.CredentialManager
timeout /t 2 >nul
goto MENU

:OPT30
cls
set "act="
echo.
echo  ACTIVATION CENTER - official Microsoft tools only
echo  -------------------------------------------------
echo   WINDOWS                                   OFFICE - volume license / LTSC
echo   [1] Windows activation status             [6] Office license status
echo   [2] Enter Windows key + activate          [7] Enter Office key + activate
echo   [3] Activate Windows with current key     [8] Activate Office with current key
echo   [4] Use OEM key stored in BIOS/firmware
echo   [5] Open Activation settings and          MICROSOFT 365 - subscription
echo       troubleshooter                        [9] Open Word to sign in - File, Account
echo.
echo   [0] Back
echo.
set /p "act=  Select: "
if "%act%"=="1" goto ACT_WINSTATUS
if "%act%"=="2" goto ACT_WINKEY
if "%act%"=="3" goto ACT_WINATO
if "%act%"=="4" goto ACT_WINOEM
if "%act%"=="5" start "" ms-settings:activation
if "%act%"=="6" goto ACT_OFFSTATUS
if "%act%"=="7" goto ACT_OFFKEY
if "%act%"=="8" goto ACT_OFFACT
if "%act%"=="9" goto ACT_M365
if "%act%"=="0" goto MENU
goto OPT30

:ACT_WINSTATUS
cls
echo  Windows Activation Status
echo  -------------------------
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /dli
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /xpr
pause
goto OPT30

:ACT_WINKEY
cls
echo  Install Windows Product Key
echo  ---------------------------
echo  Use your company MAK/retail key - from Microsoft 365 admin center or VLSC.
echo  The key is NOT saved or logged.
echo.
call :READKEY || goto OPT30
call :LOG "Windows key installed + activation attempted"
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /ipk %PKEY%
set "PKEY="
echo.
echo  Activating online...
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /ato
pause
goto OPT30

:ACT_WINATO
cls
call :LOG "Windows activation attempted"
echo  Activating Windows with installed key...
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /ato
echo.
echo  Common errors: 0xC004C003 key blocked, 0xC004C008 key used too many times,
echo  0x8007232B KMS host not found - KMS key needs company network/VPN.
pause
goto OPT30

:ACT_WINOEM
cls
echo  OEM Key from BIOS / Firmware
echo  ----------------------------
set "OEMKEY="
for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command "(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey"`) do set "OEMKEY=%%K"
if not defined OEMKEY (
    echo  No OEM key stored in this PC's firmware.
    pause
    goto OPT30
)
echo  This PC has a manufacturer key in firmware ending in: %OEMKEY:~-5%
echo  Note: it only matches the edition the PC shipped with - usually Home or Pro.
echo.
call :CONFIRM "Install this key and activate?" || goto OPT30
call :LOG "OEM firmware key installed + activation attempted"
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /ipk %OEMKEY%
set "OEMKEY="
cscript //nologo "%SystemRoot%\System32\slmgr.vbs" /ato
pause
goto OPT30

:ACT_OFFSTATUS
cls
echo  Office License Status
echo  ---------------------
call :FINDOSPP || goto OPT30
cscript //nologo "%OSPP%" /dstatus
echo  Microsoft 365 subscriptions show in Word - File - Account, not always here.
pause
goto OPT30

:ACT_OFFKEY
cls
echo  Install Office Product Key - volume / LTSC editions
echo  ----------------------------------------------------
echo  The key is NOT saved or logged.
echo.
call :FINDOSPP || goto OPT30
call :READKEY || goto OPT30
call :LOG "Office key installed + activation attempted"
cscript //nologo "%OSPP%" /inpkey:%PKEY%
set "PKEY="
echo.
echo  Activating online...
cscript //nologo "%OSPP%" /act
pause
goto OPT30

:ACT_OFFACT
cls
call :FINDOSPP || goto OPT30
call :LOG "Office activation attempted"
echo  Activating Office with installed key...
cscript //nologo "%OSPP%" /act
pause
goto OPT30

:ACT_M365
cls
echo  Microsoft 365 activates by signing in with the user's work account.
echo  In Word go to File - Account - Sign in. Close other Office apps first.
start "" winword.exe
timeout /t 3 >nul
goto OPT30

:OPT31
cls
echo  Windows Activation Status
echo  -------------------------
powershell -NoProfile -Command "Get-CimInstance SoftwareLicensingProduct -Filter 'PartialProductKey IS NOT NULL' | Where-Object { $_.Name -like 'Windows*' } | Select-Object Name, Description, PartialProductKey, @{n='Status';e={ @('Unlicensed','Licensed','OOB Grace','OOT Grace','Non-Genuine Grace','Notification','Extended Grace')[$_.LicenseStatus] }} | Format-List"
call :DONE
goto MENU

:OPT32
cls
echo  BitLocker Status
echo  ----------------
manage-bde -status
call :DONE
goto MENU

:: ============================================================
::  INFO / REPORTS
:: ============================================================
:OPT33
cls
echo  System Information
echo  ------------------
powershell -NoProfile -Command "$o=Get-CimInstance Win32_OperatingSystem; $c=Get-CimInstance Win32_ComputerSystem; $b=Get-CimInstance Win32_BIOS; $u=(Get-Date)-$o.LastBootUpTime; [pscustomobject]@{Computer=$env:COMPUTERNAME; Domain=$c.Domain; LoggedOnUser=$c.UserName; Model=($c.Manufacturer+' '+$c.Model); SerialNumber=$b.SerialNumber; OS=$o.Caption; Version=$o.Version; RAM_GB=[math]::Round($c.TotalPhysicalMemory/1GB,1); LastBoot=$o.LastBootUpTime; Uptime=('{0}d {1}h {2}m' -f $u.Days,$u.Hours,$u.Minutes)} | Format-List"
echo  Uptime over 7 days? Restart first - fixes many issues.
echo.
call :CONFIRM "Show full systeminfo output too?" && systeminfo
call :DONE
goto MENU

:OPT34
cls
echo  Critical and Error events - last 24 hours - System + Application
echo  -----------------------------------------------------------------
powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 40 -ErrorAction SilentlyContinue | Select-Object TimeCreated, LogName, ProviderName, Id, @{n='Message';e={($_.Message -split [Environment]::NewLine)[0]}} | Format-Table -AutoSize -Wrap"
echo  Unexpected shutdowns - Kernel-Power 41 / EventLog 6008 - last 30 days:
powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName | Format-Table -AutoSize"
call :DONE
goto MENU

:OPT35
cls
echo  Startup Programs
echo  ----------------
powershell -NoProfile -Command "Get-CimInstance Win32_StartupCommand | Select-Object Name, User, Location, Command | Format-Table -AutoSize -Wrap"
echo  Disable unwanted items: Task Manager - Startup apps.
call :CONFIRM "Open Task Manager?" && start "" taskmgr.exe
goto MENU

:OPT36
cls
call :LOG "Export installed software"
call :STAMP
set "OUT=%REPORTROOT%\%COMPUTERNAME%_InstalledSoftware_%STAMP%.csv"
echo  Exporting installed software list...
powershell -NoProfile -Command "$k='HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; $a = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName -Unique; $a | Export-Csv -NoTypeInformation -Encoding UTF8 -Path '%OUT%'; Write-Host ('  ' + $a.Count + ' programs exported.')"
echo  Saved: %OUT%
call :DONE
goto MENU

:OPT37
cls
call :LOG "Full IT report"
call :STAMP
set "RDIR=%REPORTROOT%\%COMPUTERNAME%_%STAMP%"
mkdir "%RDIR%" >nul 2>&1
echo  Generating FULL IT Report - takes 1-3 minutes...
echo  Folder: %RDIR%
echo.
echo  [1/9] System info...
systeminfo > "%RDIR%\01_SystemInfo.txt" 2>&1
echo  [2/9] Network config...
( ipconfig /all & echo. & route print & echo. & netsh winhttp show proxy ) > "%RDIR%\02_Network.txt" 2>&1
echo  [3/9] Disks...
powershell -NoProfile -Command "Get-PhysicalDisk | Format-Table FriendlyName, MediaType, HealthStatus, OperationalStatus -AutoSize | Out-String -Width 200; Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Format-Table DeviceID, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}} -AutoSize | Out-String -Width 200" > "%RDIR%\03_Disks.txt" 2>&1
echo  [4/9] Event log errors - last 7 days...
powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 300 -ErrorAction SilentlyContinue | Select-Object TimeCreated, LogName, ProviderName, Id, Message | Export-Csv -NoTypeInformation -Encoding UTF8 '%RDIR%\04_EventErrors_7days.csv'"
echo  [5/9] Installed software...
powershell -NoProfile -Command "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName -Unique | Export-Csv -NoTypeInformation -Encoding UTF8 '%RDIR%\05_InstalledSoftware.csv'"
echo  [6/9] Drivers and problem devices...
driverquery /v /fo csv > "%RDIR%\06_Drivers.csv" 2>&1
powershell -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' } | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize | Out-String -Width 250" > "%RDIR%\06_ProblemDevices.txt" 2>&1
echo  [7/9] Services set to Automatic but not running...
powershell -NoProfile -Command "Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } | Format-Table Name, DisplayName, State -AutoSize | Out-String -Width 200" > "%RDIR%\07_StoppedAutoServices.txt" 2>&1
echo  [8/9] Windows updates installed...
powershell -NoProfile -Command "Get-HotFix | Sort-Object InstalledOn -Descending | Format-Table HotFixID, Description, InstalledOn -AutoSize | Out-String -Width 200" > "%RDIR%\08_Updates.txt" 2>&1
echo  [9/9] Group Policy + battery report...
gpresult /h "%RDIR%\09_GPResult.html" /f >nul 2>&1
powercfg /batteryreport /output "%RDIR%\09_Battery.html" >nul 2>&1
echo.
echo  Building the summary page...
call :RUNPS FULLINDEX
echo  ----------------------------------------------------------------------------------------------------------
echo   FINISHED.  Summary page: %RDIR%\index.html
echo   Full bundle folder:     %RDIR%   (attach this folder to the support ticket)
echo  ----------------------------------------------------------------------------------------------------------
choice /c OM /n /m "  [O] Open the summary in the browser    [M] Back to menu: "
if errorlevel 2 goto MENU
if exist "%RDIR%\index.html" start "" "%RDIR%\index.html"
if not exist "%RDIR%\index.html" start "" "%RDIR%"
goto MENU

:: ============================================================
::  TOOLS
:: ============================================================
:OPT38
cls
set "sub="
echo.
echo  ADMIN CONSOLES
echo  --------------
echo   [1] Device Manager           [7]  Programs and Features
echo   [2] Services                 [8]  Network Connections
echo   [3] Event Viewer             [9]  Printers and Scanners
echo   [4] Computer Management      [10] Local Users and Groups
echo   [5] Disk Management          [11] System Configuration - msconfig
echo   [6] Task Manager             [12] Sound Settings
echo.
echo   [0] Back
echo.
set /p "sub=  Select: "
if "%sub%"=="1" start "" devmgmt.msc
if "%sub%"=="2" start "" services.msc
if "%sub%"=="3" start "" eventvwr.msc
if "%sub%"=="4" start "" compmgmt.msc
if "%sub%"=="5" start "" diskmgmt.msc
if "%sub%"=="6" start "" taskmgr.exe
if "%sub%"=="7" start "" appwiz.cpl
if "%sub%"=="8" start "" ncpa.cpl
if "%sub%"=="9" start "" ms-settings:printers
if "%sub%"=="10" start "" lusrmgr.msc
if "%sub%"=="11" start "" msconfig.exe
if "%sub%"=="12" start "" mmsys.cpl
if "%sub%"=="0" goto MENU
goto OPT38

:OPT39
start "" "%REPORTROOT%"
goto MENU

:OPT40
cls
echo  Restart Computer
echo  ----------------
echo  Save all open work first. The computer will restart in 30 seconds.
echo.
call :CONFIRM "Restart now?" || goto MENU
call :LOG "Restart computer"
shutdown /r /t 30 /c "Restart started by IT Tools"
echo  Restart scheduled. To cancel type:  shutdown /a
call :DONE
goto MENU

:OPT41
cls
echo  Update IT Tools
echo  ---------------
echo  Downloads the latest version from https://get.snapsbilling.com and restarts it.
echo.
call :CONFIRM "Continue?" || goto MENU
call :LOG "Update from web"
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://get.snapsbilling.com | iex"
if errorlevel 1 (
    echo  Update failed - check internet connection.
    pause
    goto MENU
)
goto END

:: ============================================================
::  PAGE 2 - MORE TOOLS
:: ============================================================
:MENU2
if defined GUIRUN goto END
cls
set "choice="
echo.
echo  ==========================================================================================================
echo                                     IT TOOLS - MORE TOOLS - PAGE 2
echo  ==========================================================================================================
echo   Computer: %COMPUTERNAME%     Admin: %USERDOMAIN%\%USERNAME%     User fixes apply to: %TUSER%
echo  ----------------------------------------------------------------------------------------------------------
echo    OFFICE / OUTLOOK / TEAMS                          NETWORK SHARES / DOMAIN
echo     [43] Fix Outlook / Teams Not Opening or Hanging  [50] Network Drives - list / map / reconnect
echo     [44] Office Repair - Quick or Online             [51] Clear Saved Credentials for a Server
echo     [45] Clear Office Sign-in Cache                  [52] Domain / VPN Test + Trust Repair
echo     [46] Rebuild Outlook Cache - OST
echo     [47] Outlook Mail Profiles                       BROWSER / PROFILE
echo                                                      [53] Clear Edge + Chrome Cache
echo    ONEDRIVE                                          [54] User Profile Check - temp profile, size
echo     [48] OneDrive Status + Backed-up Folders
echo     [49] Reset OneDrive                              REMOTE HELP
echo                                                      [55] Quick Assist + IP Info
echo    WINDOWS SHELL
echo     [56] Fix Start Menu + Search                     SPEED / STORAGE
echo     [57] Rebuild Search Index                        [60] Optimize Windows - stop bandwidth, ads, tips
echo     [58] Fix Icon + Thumbnail Cache                  [61] Deep Clean - junk, update cache, dumps
echo     [59] Fix Lock - Win+L / Lock button missing      [62] Remove Preinstalled Consumer Apps
echo                                                      [68] Disk Space Analyzer - what fills the drive
echo.
echo    USER ACCOUNTS                                     SECURITY
echo     [63] Microsoft Account to Local Admin            [64] Security Check - hacked / malware triage
echo                                                      [65] Spam Email Trace - find + stop mail sender
echo                                                      [66] Stop + Block a Process - PID / firewall
echo                                                      [67] Remote Connections - who is connected now
echo.
echo     [69] DIAGNOSTICS ^& ADMIN CENTER  - hardware, BSOD, performance, drivers, security, network ^>^>
echo.
echo     [0]  Back to main menu
echo  ==========================================================================================================
set /p "choice=  Option number, or a word to search - e.g. onedrive, remote, disk: "
if not defined choice goto MENU2
set "SEARCHQ=%choice%"
set "choice=%choice: =%"
type nul >"%ITROOT%\bin\optstart.flag" 2>nul
if "%choice%"=="69" goto MENU3
for %%N in (%ALLOPTS%) do (
    if "%choice%"=="%%N" goto OPT%%N
)
if "%choice%"=="0" goto MENU
set "SEARCHBACK=MENU2"
goto SEARCH

:: ============================================================
::  PAGE 3 - DIAGNOSTICS & ADMIN CENTER
:: ============================================================
:MENU3
if defined GUIRUN goto END
cls
set "choice="
echo.
echo  ==========================================================================================================
echo                              IT TOOLS - DIAGNOSTICS ^& ADMIN CENTER - PAGE 3
echo  ==========================================================================================================
echo   Computer: %COMPUTERNAME%     Admin: %USERDOMAIN%\%USERNAME%     Reports: %REPORTROOT%
echo  ----------------------------------------------------------------------------------------------------------
echo    HARDWARE / CRASHES                               PERFORMANCE / DRIVERS
echo     [70] Hardware + Disk Health Report               [72] Performance Snapshot
echo     [71] BSOD + Unexpected Shutdown Analyzer         [73] Driver Audit + Export
echo.
echo    WINDOWS / SECURITY                               NETWORK / EVENT INTELLIGENCE
echo     [74] Windows Update Health Check                 [75] Advanced Network Diagnostics
echo     [76] Security Baseline Audit                     [77] Recurring Event Error Analyzer
echo     [84] Windows Image Health - DISM diagnose / clean / repair + SFC
echo     [86] Firewall Center - status, ports, rules, backup / restore
echo.
echo    USB
echo     [78] USB Virus Removal - shortcut virus, autorun  [79] USB Storage - enable / disable / read-only
echo.
echo    WINDOWS SETUP                                    LAN / WI-FI
echo     [80] Windows 11 Setup - local account, Shift+F10  [81] Network Device Scan - who is on the network
echo                                                      [82] Wi-Fi Signal + Interference - dBm, channel
echo                                                      [83] Bandwidth - top talkers, router, SNMP
echo                                                      [87] Device Type Scan - NVR / DVR / cameras / fingerprint
echo.
echo    FILES
echo     [85] File Organizer - sort a folder into type subfolders - safe, with Undo
echo.
echo     [0]  Back to More Tools
echo  ==========================================================================================================
set /p "choice=  Option number, or a word to search - e.g. crash, driver, network, security: "
if not defined choice goto MENU3
set "SEARCHQ=%choice%"
set "choice=%choice: =%"
type nul >"%ITROOT%\bin\optstart.flag" 2>nul
for %%N in (%ALLOPTS%) do (
    if "%choice%"=="%%N" goto OPT%%N
)
if "%choice%"=="0" goto MENU2
set "SEARCHBACK=MENU3"
goto SEARCH

:: ------------------------------------------------------------
::  Keyword search - typed from either menu. Matches option names
::  plus common problem words (slow, hacked, printer...).
:: ------------------------------------------------------------
:SEARCH
cls
call :RUNPS SEARCH
set "choice="
echo.
set /p "choice=  Option number to run, or Enter to go back: "
if not defined choice goto %SEARCHBACK%
set "SEARCHQ=%choice%"
set "choice=%choice: =%"
type nul >"%ITROOT%\bin\optstart.flag" 2>nul
for %%N in (%ALLOPTS%) do (
    if "%choice%"=="%%N" goto OPT%%N
)
if "%choice%"=="42" goto MENU2
if "%choice%"=="69" goto MENU3
if "%choice%"=="0" goto %SEARCHBACK%
goto SEARCH

:: ---------------- OFFICE / OUTLOOK / TEAMS ----------------
:OPT43
cls
echo  Fix Outlook / Teams Not Opening or Hanging - user %TUSER%
echo  ---------------------------------------------------------
echo  Closes ALL hidden Outlook / Teams processes - Task Manager often misses them,
echo  removes bad compatibility / run-as-admin flags, clears Teams cache and Outlook
echo  temp cache, and checks WebView2, Office updates and disk space.
echo  Mail, calendar, contacts, chats and email autocomplete are NOT deleted.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Fix Outlook / Teams hang"
call :RUNPS OUTLOOKTEAMS
:OPT43_START
echo.
echo   Now start the app on the user desktop:
echo   [1] Start Outlook                    [2] Outlook Safe Mode - add-ins off
echo   [3] Outlook + reset navigation pane  [4] Start Teams
echo   [5] Reset Teams app - full reset, user signs in again
echo   [0] Back
echo.
echo   Outlook OK only in Safe Mode = bad add-in: File - Options - Add-ins - COM Add-ins - Go.
echo   Outlook still stuck on Loading Profile = use 46 Rebuild OST or 47 new Mail profile.
set "ot="
set /p "ot=  Select: "
if "%ot%"=="1" call :LAUNCHUSER OUTLOOKNORMAL
if "%ot%"=="2" call :LAUNCHUSER OUTLOOKSAFE
if "%ot%"=="3" call :LAUNCHUSER OUTLOOKNAV
if "%ot%"=="4" call :LAUNCHUSER TEAMSSTART
if "%ot%"=="5" call :LAUNCHUSER TEAMSRESET
if "%ot%"=="0" goto MENU2
goto OPT43_START

:OPT44
cls
echo  Office Repair
echo  -------------
set "C2R=%CommonProgramFiles%\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"
if not exist "%C2R%" goto OPT44_MSI
set "C2RPLAT=x64"
set "C2RCULT=en-us"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" /v Platform 2^>nul ^| find /i "Platform"') do set "C2RPLAT=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" /v ClientCulture 2^>nul ^| find /i "ClientCulture"') do set "C2RCULT=%%B"
echo  Office Click-to-Run found: %C2RPLAT% / %C2RCULT%
echo.
echo   [Q] Quick Repair  - few minutes, offline, fixes most problems
echo   [O] Online Repair - full reinstall, needs internet, 20+ minutes
echo   [C] Cancel
echo.
choice /c QOC /n /m "  Select [Q/O/C]: "
if errorlevel 3 goto MENU2
if errorlevel 2 (set "RTYPE=FullRepair") else set "RTYPE=QuickRepair"
echo  All Office apps will be closed - save work first.
call :CONFIRM "Start %RTYPE%?" || goto MENU2
call :LOG "Office %RTYPE%"
start "" "%C2R%" scenario=Repair platform=%C2RPLAT% culture=%C2RCULT% forceappshutdown=True RepairType=%RTYPE% DisplayLevel=True
echo  Repair started - follow the Office repair window.
call :DONE
goto MENU2
:OPT44_MSI
echo  Click-to-Run Office not found. For MSI Office use Programs and Features - Change - Repair.
start "" appwiz.cpl
call :DONE
goto MENU2

:OPT45
cls
echo  Clear Office Sign-in Cache - user %TUSER%
echo  -----------------------------------------
echo  Fixes repeated password prompts, wrong account signed in, licence errors after account change.
echo  All Office apps and Teams will close. The user must sign in again.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Clear Office identity cache"
call :KILLAPP "winword,excel,powerpnt,outlook,onenote,msaccess,mspub,lync,ms-teams,Teams,olk"
timeout /t 2 >nul
if defined TSID reg delete "HKU\%TSID%\Software\Microsoft\Office\16.0\Common\Identity" /f >nul 2>&1
for %%F in ("%TLOCAL%\Microsoft\OneAuth" "%TLOCAL%\Microsoft\IdentityCache") do if exist "%%~F" rd /s /q "%%~F" >nul 2>&1
echo  Office identity registry and token cache cleared.
echo  Removing saved Office credentials in a window on the user desktop...
call :LAUNCHUSER OFFICECRED
echo.
echo  Done. Open Word or Outlook and sign in with the work account.
call :DONE
goto MENU2

:OPT46
cls
echo  Rebuild Outlook Cache - OST - user %TUSER%
echo  ------------------------------------------
echo  Outlook closes. OST files are renamed to .old and Outlook downloads the mailbox again.
echo  Large mailboxes can take hours to sync. PST files are NOT touched.
echo  Applies to classic Outlook only, not new Outlook - olk.exe.
echo.
if not exist "%TLOCAL%\Microsoft\Outlook\*.ost" (
    echo  No OST files found in %TLOCAL%\Microsoft\Outlook
    pause
    goto MENU2
)
dir /b "%TLOCAL%\Microsoft\Outlook\*.ost"
echo.
call :CONFIRM "Rename these OST files?" || goto MENU2
call :LOG "Rebuild OST"
call :KILLAPP outlook
timeout /t 3 >nul
call :STAMP
for %%F in ("%TLOCAL%\Microsoft\Outlook\*.ost") do ren "%%~F" "%%~nxF.old_%STAMP%" && echo  Renamed %%~nxF
echo.
echo  Done. Start Outlook - it will rebuild the cache. Delete the .old files after it works.
call :DONE
goto MENU2

:OPT47
cls
echo  Outlook Mail Profiles
echo  ---------------------
echo  Opening Mail profiles on the user desktop.
echo  Fix a broken profile: Add a new profile, set it to Always use this profile, start Outlook.
call :LAUNCHUSER MAILPROFILES
call :DONE
goto MENU2

:: ---------------- ONEDRIVE ----------------
:OPT48
cls
echo  OneDrive Status - user %TUSER%
echo  ------------------------------
powershell -NoProfile -Command "$k='Registry::HKEY_USERS\' + $env:TSID + '\Software\Microsoft\OneDrive\Accounts'; $a=Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { $p=Get-ItemProperty $_.PSPath; if ($p.UserFolder) { [pscustomobject]@{Account=$_.PSChildName; Email=$p.UserEmail; Folder=$p.UserFolder} } }; if ($a) { $a | Format-Table -AutoSize -Wrap | Out-String | Write-Host } else { Write-Host '  No OneDrive account configured for this user.' -ForegroundColor Yellow }; $s=(Get-Process -Id $PID).SessionId; if (Get-Process OneDrive -ErrorAction SilentlyContinue | Where-Object SessionId -eq $s) { Write-Host '  OneDrive is running.' -ForegroundColor Green } else { Write-Host '  OneDrive is NOT running.' -ForegroundColor Red }; $f=Get-ItemProperty ('Registry::HKEY_USERS\' + $env:TSID + '\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders') -ErrorAction SilentlyContinue; Write-Host ''; Write-Host '  Known folders - path inside OneDrive means backed up:'; foreach ($n in 'Desktop','Personal','My Pictures') { Write-Host ('   ' + $n.PadRight(12) + ' ' + $f.$n) }"
echo.
echo  Sync errors: check the OneDrive cloud icon in the taskbar. Stuck sync: use option 49.
call :DONE
goto MENU2

:OPT49
cls
echo  Reset OneDrive - user %TUSER%
echo  -----------------------------
echo  Disconnects and reconnects sync. Files are NOT deleted. Full resync can take a while.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Reset OneDrive"
call :LAUNCHUSER ONEDRIVERESET
echo  Reset is running in a window on the user desktop.
call :DONE
goto MENU2

:: ---------------- NETWORK SHARES / DOMAIN ----------------
:OPT50
cls
echo  Network Drives - user %TUSER%
echo  -----------------------------
echo  Saved mapped drives:
powershell -NoProfile -Command "$d=Get-ChildItem ('Registry::HKEY_USERS\' + $env:TSID + '\Network') -ErrorAction SilentlyContinue | ForEach-Object { $p=Get-ItemProperty $_.PSPath; [pscustomobject]@{Drive=($_.PSChildName.ToUpper() + ':'); Path=$p.RemotePath; SavedUser=$p.UserName} }; if ($d) { $d | Format-Table -AutoSize | Out-String | Write-Host } else { Write-Host '   none' }"
echo  Opening the drive tool on the user desktop - list, map, remove, reconnect.
echo  Drives must be mapped as the user - drives mapped as admin are invisible to the user.
call :LAUNCHUSER NETDRIVES
call :DONE
goto MENU2

:OPT51
cls
echo  Clear Saved Credentials for a Server - user %TUSER%
echo  ---------------------------------------------------
echo  Use after a password change, or when a share asks for a password / says access denied.
echo.
set "SRV="
set /p "SRV=  Server name or IP, e.g. fileserver01: "
if not defined SRV goto MENU2
powershell -NoProfile -Command "if ($env:SRV.Trim() -match '^[A-Za-z0-9._-]{1,253}$') { exit 0 } else { exit 1 }" <nul
if errorlevel 1 (
    echo  Invalid server name.
    pause
    goto MENU2
)
set "SRV=%SRV: =%"
call :LOG "Clear credentials for %SRV%"
call :LAUNCHUSER CLEARCRED %SRV%
echo  Cleanup is running in a window on the user desktop.
call :DONE
goto MENU2

:OPT52
cls
call :LOG "Domain / VPN test"
echo  Domain / VPN Test
echo  -----------------
powershell -NoProfile -Command "$cs=Get-CimInstance Win32_ComputerSystem; Write-Host ('  Domain joined: ' + $cs.PartOfDomain + '    Domain/Workgroup: ' + $cs.Domain); $v=Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'VPN|TAP-|Fortinet|Cisco|AnyConnect|WireGuard|Wintun|Pulse|Juniper|GlobalProtect|PANGP|SonicWall|OpenVPN|Zscaler|Check Point' }; Write-Host ''; Write-Host '  VPN adapters:'; if ($v) { $v | Format-Table Name, InterfaceDescription, Status -AutoSize | Out-String | Write-Host } else { Write-Host '   none found' }; $w=Get-VpnConnection -ErrorAction SilentlyContinue; if ($w) { Write-Host '  Windows VPN connections:'; $w | Format-Table Name, ServerAddress, ConnectionStatus -AutoSize | Out-String | Write-Host }; if ($cs.PartOfDomain) { Write-Host ''; Write-Host '  Domain controller lookup:'; nltest /dsgetdc:$($cs.Domain); $ok=Test-ComputerSecureChannel -ErrorAction SilentlyContinue; Write-Host ''; Write-Host ('  Secure channel / trust OK: ' + $ok); if ($ok) { exit 0 } else { exit 2 } } else { exit 3 }"
set "DRC=%errorlevel%"
echo.
if "%DRC%"=="3" (
    echo  Not domain joined - domain checks skipped.
    pause
    goto MENU2
)
if "%DRC%"=="0" (
    echo  Domain connection OK. If no DC found while remote, connect VPN first.
    pause
    goto MENU2
)
echo  [!] Trust problem. User may see: The trust relationship between this workstation and the primary domain failed.
echo      Repair needs the PC to reach a domain controller - office network or VPN.
echo.
call :CONFIRM "Repair domain trust now? Needs domain admin account" || goto MENU2
call :LOG "Repair domain trust"
powershell -NoProfile -Command "try { if (Test-ComputerSecureChannel -Repair -Credential (Get-Credential -Message 'Domain admin account') -ErrorAction Stop) { Write-Host '  Trust repaired. Restart the PC.' -ForegroundColor Green } else { Write-Host '  Repair failed.' -ForegroundColor Red } } catch { Write-Host ('  Failed: ' + $_.Exception.Message) -ForegroundColor Red }"
call :DONE
goto MENU2

:: ---------------- BROWSER / PROFILE ----------------
:OPT53
cls
echo  Clear Edge + Chrome Cache - user %TUSER%
echo  ----------------------------------------
echo  Browsers will close. Passwords, cookies, history and bookmarks are KEPT.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Clear browser cache"
call :KILLAPP "msedge,chrome"
timeout /t 3 >nul
for %%B in ("%TLOCAL%\Microsoft\Edge\User Data" "%TLOCAL%\Google\Chrome\User Data") do if exist "%%~B\" for /d %%P in ("%%~B\*") do for %%C in ("Cache" "Code Cache" "GPUCache" "Service Worker\CacheStorage" "Service Worker\ScriptCache") do if exist "%%~P\%%~C\" rd /s /q "%%~P\%%~C" >nul 2>&1
echo  Edge and Chrome cache cleared for all browser profiles.
call :DONE
goto MENU2

:OPT54
cls
echo  User Profile Check
echo  ------------------
powershell -NoProfile -Command "Write-Host ('  User: ' + $env:TUSER); Write-Host ('  Profile path: ' + $env:TPROFILE); if ($env:TPROFILE -match '\\TEMP(\.|$)') { Write-Host '  [!] TEMPORARY PROFILE - changes will be lost at sign-out!' -ForegroundColor Red }; $bak=Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' | Where-Object PSChildName -like '*.bak'; if ($bak) { Write-Host '  [!] ProfileList has .bak entries - sign of a corrupted profile:' -ForegroundColor Red; $bak | ForEach-Object { Write-Host ('     ' + $_.PSChildName + '  ' + (Get-ItemProperty $_.PSPath).ProfileImagePath) } } else { Write-Host '  ProfileList: no .bak entries - OK' -ForegroundColor Green }; $ev=Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-User Profiles Service'; Level=2,3; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 10 -ErrorAction SilentlyContinue; if ($ev) { Write-Host ''; Write-Host '  Profile service warnings/errors - last 7 days:'; $ev | Format-Table TimeCreated, Id, @{n='Message';e={($_.Message -split [Environment]::NewLine)[0]}} -AutoSize -Wrap | Out-String | Write-Host }; Write-Host ''; Write-Host '  All profiles on this PC:'; Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | Sort-Object LastUseTime -Descending | Format-Table LocalPath, Loaded, LastUseTime -AutoSize | Out-String | Write-Host"
call :CONFIRM "Calculate folder sizes for this profile? Can take a few minutes" || goto MENU2
powershell -NoProfile -Command "Get-ChildItem -LiteralPath $env:TPROFILE -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $sz=(Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; [pscustomobject]@{Folder=$_.Name; SizeGB=[math]::Round($sz/1GB,2)} } | Sort-Object SizeGB -Descending | Format-Table -AutoSize"
echo  OneDrive size includes online-only files that are not using local disk.
call :DONE
goto MENU2

:: ---------------- REMOTE HELP ----------------
:OPT55
cls
echo  Remote Help - Quick Assist
echo  --------------------------
powershell -NoProfile -Command "Write-Host ('  Computer name: ' + $env:COMPUTERNAME); Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { Write-Host ('  IP: ' + $_.IPAddress + '   on ' + $_.InterfaceAlias) }; try { Write-Host ('  Public IP: ' + (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 5)) } catch { Write-Host '  Public IP: not available' }"
echo.
echo  Starting Quick Assist on the user desktop.
echo  Helper: Help someone - gives a code.   User: enter the code under Get help.
call :LAUNCHUSER QUICKASSIST
call :DONE
goto MENU2

:: ---------------- WINDOWS SHELL ----------------
:OPT56
cls
echo  Fix Start Menu + Search - user %TUSER%
echo  --------------------------------------
echo  Re-registers Start, Search and taskbar packages for the user and restarts them.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Fix Start menu"
call :LAUNCHUSER STARTMENU
echo  Running in a window on the user desktop. If still broken, sign out and in again.
call :DONE
goto MENU2

:OPT57
cls
echo  Rebuild Windows Search Index
echo  ----------------------------
echo  Use when search finds nothing or Outlook search is incomplete.
echo  Indexing restarts from zero and runs in the background - can take hours.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Rebuild search index"
net stop wsearch /y
reg add "HKLM\SOFTWARE\Microsoft\Windows Search" /v SetupCompletedSuccessfully /t REG_DWORD /d 0 /f >nul
net start wsearch
echo.
echo  Search index rebuild started.
call :DONE
goto MENU2

:OPT58
cls
echo  Fix Icon + Thumbnail Cache - user %TUSER%
echo  -----------------------------------------
echo  Fixes blank, wrong or old icons and broken thumbnails. Explorer restarts.
echo.
call :CONFIRM "Continue?" || goto MENU2
call :LOG "Fix icon cache"
call :KILLAPP explorer
timeout /t 2 >nul
del /f /q /a "%TLOCAL%\IconCache.db" >nul 2>&1
del /f /q /a "%TLOCAL%\Microsoft\Windows\Explorer\iconcache_*.db" >nul 2>&1
del /f /q /a "%TLOCAL%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
call :ENSUREEXPLORER
echo  Icon and thumbnail cache cleared. Restart the PC if some icons are still wrong.
call :DONE
goto MENU2

:: ---------------- SPEED / STORAGE ----------------
:OPT60
cls
echo  Optimize Windows - user %TUSER%
echo  -------------------------------
echo  Turns off Microsoft background features that use bandwidth, CPU or show ads:
echo  update sharing to other PCs, news widgets, suggested apps, tips, web search in Start,
echo  telemetry above Required level, Edge preloading, Xbox recording, Recall.
echo  Security updates, Defender, Store and Office updates are NOT affected.
echo  Company Group Policy / Intune settings always win over these.
echo.
set "OPTMODE=STATUS"
call :RUNPS OPTIMIZE
echo.
echo   [A] Apply recommended     [R] Restore Microsoft defaults     [C] Cancel
choice /c ARC /n /m "  Select [A/R/C]: "
if errorlevel 3 goto MENU2
if errorlevel 2 (set "OPTMODE=REVERT") else set "OPTMODE=APPLY"
call :LOG "Optimize Windows %OPTMODE%"
call :RUNPS OPTIMIZE
echo.
echo  Done. Restart the PC so every setting takes effect.
call :DONE
goto MENU2

:OPT61
cls
echo  Deep Clean - junk files
echo  -----------------------
echo  Removes: temp files, Windows Update download cache, Delivery Optimization cache,
echo  error reports, crash dumps, graphics shader cache. Documents, Downloads, Desktop
echo  and Recycle Bin are NOT touched.
echo.
call :CONFIRM "Start Deep Clean?" || goto MENU2
call :LOG "Deep clean"
call :RUNPS DEEPCLEAN
echo.
echo  Optional - Windows Disk Cleanup for old Windows versions - Windows.old - and
echo  installed-update leftovers. After this you cannot roll back to the previous Windows version.
call :CONFIRM "Run Windows Disk Cleanup now?" || goto OPT61_DISM
call :RUNPS CLEANMGRFLAGS
echo  Disk Cleanup is running - this can take 5-30 minutes...
start /wait "" cleanmgr.exe /sagerun:77
:OPT61_DISM
echo.
echo  Optional - shrink the WinSxS component store with DISM. Takes 5-20 minutes.
call :CONFIRM "Run DISM component cleanup?" || goto OPT61_HIBER
DISM /Online /Cleanup-Image /StartComponentCleanup
:OPT61_HIBER
powershell -NoProfile -Command "if (-not (Get-CimInstance Win32_Battery) -and (Test-Path ($env:SystemDrive + '\hiberfil.sys'))) { exit 0 } else { exit 1 }" <nul
if errorlevel 1 goto OPT61_DONE
echo.
echo  This is a desktop PC with hibernation on - hiberfil.sys uses several GB.
call :CONFIRM "Turn off hibernation to free that space?" && powercfg /h off
:OPT61_DONE
echo.
powershell -NoProfile -Command "$d=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID=''' + $env:SystemDrive + ''''); Write-Host ('  ' + $env:SystemDrive + ' free space now: ' + [math]::Round($d.FreeSpace/1GB,1) + ' GB of ' + [math]::Round($d.Size/1GB,1) + ' GB') -ForegroundColor Green"
echo  Still low? Check Downloads and big files with option 54, empty Recycle Bin with option 18.
call :DONE
goto MENU2

:OPT62
cls
echo  Remove Preinstalled Consumer Apps
echo  ---------------------------------
echo  Removes games, news, weather, ad apps and similar - for all users and new users.
echo  Store, Calculator, Photos, Paint, Notepad, Snipping Tool, Office and Teams work are kept.
echo.
set "APPMODE=LIST"
call :RUNPS REMOVEAPPS
if errorlevel 1 (
    pause
    goto MENU2
)
echo.
call :CONFIRM "Remove the apps listed above?" || goto MENU2
call :LOG "Remove consumer apps"
set "APPMODE=REMOVE"
call :RUNPS REMOVEAPPS
echo.
echo  Done. Removed apps can be installed again from Microsoft Store.
call :DONE
goto MENU2

:OPT59
cls
echo  Fix Lock - Win+L and Lock button - user %TUSER%
echo  -----------------------------------------------
set "LOCKMODE=STATUS"
call :RUNPS LOCKFIX
if errorlevel 1 (
    echo.
    echo  No blocking setting found. If Win+L still fails, check the keyboard:
    echo  gaming keyboards have a Win-key lock / Game Mode button or Fn+Win shortcut.
    pause
    goto MENU2
)
echo.
call :CONFIRM "Fix the problems listed above?" || goto MENU2
call :LOG "Fix lock workstation"
set "LOCKMODE=FIX"
call :RUNPS LOCKFIX
echo.
echo  Done. The user must SIGN OUT and back in - restart if the keyboard remap was removed.
powershell -NoProfile -Command "if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) { exit 0 } else { exit 1 }" <nul
if not errorlevel 1 (
    echo.
    echo  [!] Domain PC: if the problem returns after gpupdate, a Group Policy sets it.
    echo      Ask the domain admin to check: User Configuration - Administrative Templates -
    echo      System - Ctrl+Alt+Del Options - Remove Lock Computer = Not Configured.
)
call :DONE
goto MENU2

:: ---------------- USER ACCOUNTS ----------------
:OPT63
cls
set "acc="
echo.
echo  Microsoft Account to Local Administrator
echo  ----------------------------------------
echo   SAME USER, KEEP EVERYTHING - recommended: option [5]. While signed in AS that user,
echo   Settings switches the Microsoft account to a local account. Files, apps, settings stay.
echo.
echo   REPLACE THE ACCOUNT - in this order:
echo     [2] create local admin, user signs in to it once, [3] copy files, [4] remove Microsoft account
echo.
echo   [1] List accounts and profiles
echo   [2] Create local administrator account
echo   [3] Copy user files from one profile to another
echo   [4] Remove a Microsoft account user
echo   [5] Switch signed-in user to a local account - Settings, keeps all data
echo   [0] Back
echo.
set /p "acc=  Select: "
if "%acc%"=="1" goto OPT63_RUN
if "%acc%"=="2" goto OPT63_RUN
if "%acc%"=="3" goto OPT63_RUN
if "%acc%"=="4" goto OPT63_RUN
if "%acc%"=="5" goto OPT63_SWITCH
if "%acc%"=="0" goto MENU2
goto OPT63
:OPT63_RUN
if "%acc%"=="1" set "ACCTMODE=LIST"
if "%acc%"=="2" set "ACCTMODE=CREATE"
if "%acc%"=="3" set "ACCTMODE=COPY"
if "%acc%"=="4" set "ACCTMODE=REMOVE"
call :LOG "Accounts %ACCTMODE%"
call :RUNPSI ACCOUNTS
pause
goto OPT63
:OPT63_SWITCH
echo.
echo  Opening Settings - Your info on the user desktop.
echo  Click: Sign in with a local account instead - then set the local user name and password.
echo  To make that user a local administrator afterwards: Settings - Accounts - Other users,
echo  or Computer Management - Local Users and Groups - Administrators.
call :LAUNCHUSER ACCOUNTINFO
pause
goto OPT63

:: ---------------- SECURITY ----------------
:OPT64
cls
echo  Security Check - hacked / malware triage
echo  ----------------------------------------
echo  Read-only scan. Nothing is changed or deleted. Takes 1-3 minutes.
echo  Report is saved in %REPORTROOT%
echo.
call :LOG "Security check"
call :RUNPS SECCHECK
:OPT64_AV
echo.
echo   Microsoft Defender:  [Q] Quick scan   [F] Full scan   [O] Offline scan - restarts PC
echo                        [U] Update virus definitions
echo   Trusted list:        [T] Mark a program as trusted - hides it in future reports
echo                        [C] Close
choice /c QFOUTC /n /m "  Select: "
if errorlevel 6 goto MENU2
if errorlevel 5 goto OPT64_TRUST
if errorlevel 4 set "AVACT=UPDATE"
if errorlevel 4 goto OPT64_DO
if errorlevel 3 set "AVACT=OFFLINE"
if errorlevel 3 goto OPT64_OFF
if errorlevel 2 set "AVACT=FULL"
if errorlevel 2 goto OPT64_DO
set "AVACT=QUICK"
goto OPT64_DO
:OPT64_OFF
echo  Offline scan restarts the PC now and scans before Windows starts - about 15 minutes.
call :CONFIRM "Save work and restart for offline scan?" || goto OPT64_AV
:OPT64_DO
call :LOG "Defender %AVACT%"
call :RUNPS DEFENDER
goto OPT64_AV
:OPT64_TRUST
call :LOG "Trusted list edit"
call :RUNPSI TRUST
goto OPT64_AV

:OPT65
cls
set "sp="
echo.
echo  Spam Email Trace - find and stop what sends emails from this PC
echo  ---------------------------------------------------------------
echo   [1] Scan this PC - SMTP connections, Outlook macros/add-ins, mail scripts, tasks
echo   [2] Live monitor - watch 3 minutes for any program sending mail
echo   [3] BLOCK outbound mail ports 25/465/587/2525 on this PC - stops a spam bot now
echo   [4] Remove the mail port block
echo   [5] Microsoft 365 / mail server checklist - hacked mailbox steps
echo   [0] Back
echo.
set /p "sp=  Select: "
if "%sp%"=="1" set "SPMODE=SCAN"
if "%sp%"=="2" set "SPMODE=MONITOR"
if "%sp%"=="3" set "SPMODE=BLOCK"
if "%sp%"=="4" set "SPMODE=UNBLOCK"
if "%sp%"=="5" set "SPMODE=CHECKLIST"
if "%sp%"=="0" goto MENU2
if not "%sp%"=="1" if not "%sp%"=="2" if not "%sp%"=="3" if not "%sp%"=="4" if not "%sp%"=="5" goto OPT65
if "%sp%"=="3" (
    echo.
    echo  Microsoft 365 Outlook uses port 443 and keeps working.
    echo  Only IMAP/POP accounts that send through SMTP ports, scanners and old apps are blocked.
    call :CONFIRM "Block outbound mail ports on this PC?" || goto OPT65
)
call :LOG "Spam trace %SPMODE%"
call :RUNPS SPAMTRACE
pause
goto OPT65

:OPT66
cls
set "bp="
echo.
echo  Stop + Block a Process
echo  ----------------------
echo  Get the PID from option 64 or 65, or from Task Manager - Details tab.
echo.
echo   [1] Stop a process by PID, block it from the internet, scan it with Defender
echo   [2] List programs blocked by IT Tools
echo   [3] Remove a block
echo   [4] REMOVE AN INFECTED FILE - stops it, removes startup links and deletes the file
echo       - DANGEROUS: only use after confirmed malware detection; this permanently removes items
echo   [0] Back
echo.
set /p "bp=  Select: "
if "%bp%"=="1" set "BPMODE=STOP"
if "%bp%"=="2" set "BPMODE=LIST"
if "%bp%"=="3" set "BPMODE=UNBLOCK"
if "%bp%"=="4" set "BPMODE=REMOVEFILE"
if "%bp%"=="0" goto MENU2
if not "%bp%"=="1" if not "%bp%"=="2" if not "%bp%"=="3" if not "%bp%"=="4" goto OPT66
call :LOG "Block process %BPMODE%"
call :RUNPSI BLOCKPROC
pause
goto OPT66

:OPT67
cls
echo  Remote Connections - who is connected to this PC
echo  ------------------------------------------------
echo  Read-only. Shows remote sessions active NOW, incoming connections in the last
echo  30 days, and every way someone can connect in without the user accepting.
echo  Report is saved in %REPORTROOT%
echo.
call :LOG "Remote connection check"
call :RUNPS REMOTECHECK
echo.
echo  Cut off a remote session now: option 66 [1] with the PID shown above, or unplug the network.
call :DONE
goto MENU2

:OPT68
cls
echo  Disk Space Analyzer - what fills the drive
echo  ------------------------------------------
echo  Shows where the space went, explains each big item, then lets you clean the SAFE ones.
echo  Nothing is deleted without your Y. The scan takes 1-5 minutes on a full drive.
echo.
call :LOG "Disk space analyzer"
call :RUNPSI DISKSCAN
call :DONE
goto MENU2

:: ============================================================
::  PAGE 3 - READ-ONLY DIAGNOSTICS AND REPORTS
:: ============================================================
:OPT70
cls
echo  Hardware + Disk Health Report
echo  ------------------------------
echo  Read-only inventory. SMART values depend on storage/controller support.
call :LOG "Hardware and disk health report"
call :RUNPS HARDWAREREPORT
call :DONE
goto MENU3

:OPT71
cls
echo  BSOD + Unexpected Shutdown Analyzer
echo  ------------------------------------
echo  Reviews BugCheck, Kernel-Power, EventLog and minidump evidence.
call :LOG "BSOD and shutdown analysis"
call :RUNPS BSODREPORT
call :DONE
goto MENU3

:OPT72
cls
echo  Performance Snapshot
echo  --------------------
echo  Captures CPU, memory, disk, top processes and startup inventory.
call :LOG "Performance snapshot"
call :RUNPS PERFORMANCE
call :DONE
goto MENU3

:OPT73
cls
echo  Driver Audit + Export
echo  ---------------------
echo  Read-only driver inventory, problem devices and unsigned-driver review.
call :LOG "Driver audit"
call :RUNPS DRIVERREPORT
call :DONE
goto MENU3

:OPT74
cls
echo  Windows Update Health Check
echo  ---------------------------
echo  Read-only check of update services, pending reboot and recent update errors.
call :LOG "Windows Update health check"
call :RUNPS UPDATEHEALTH
call :DONE
goto MENU3

:OPT75
cls
echo  Advanced Network Diagnostics
echo  -----------------------------
echo  Read-only adapter, route, DNS, proxy and connectivity checks.
call :LOG "Advanced network diagnostics"
call :RUNPS NETWORKREPORT
call :DONE
goto MENU3

:OPT76
cls
echo  Security Baseline Audit
echo  -----------------------
echo  Read-only review. Does not disable protections or remove files.
call :LOG "Security baseline audit"
call :RUNPS SECURITYAUDIT
call :DONE
goto MENU3

:OPT77
cls
echo  Recurring Event Error Analyzer
echo  ------------------------------
echo  Groups recurring System and Application errors over the last 7 days.
call :LOG "Recurring event error analysis"
call :RUNPS EVENTINTEL
call :DONE
goto MENU3

:OPT78
cls
echo  USB Virus Removal
echo  -----------------
echo  Only REMOVABLE USB drives are touched - never C:, D: or other fixed disks.
echo  Shows what it found first, cleans only after you say Y, then Defender scans the drive.
echo.
call :LOG "USB virus removal"
call :RUNPSI USBCLEAN
call :DONE
goto MENU3

:OPT79
cls
set "usb="
echo  USB Storage Control
echo  -------------------
echo  Blocks USB flash drives and external disks only. Keyboard, mouse, printer
echo  and phone charging keep working. A drive that is plugged in now must be
echo  unplugged and plugged in again before the change applies to it.
echo.
set "USBMODE="
call :RUNPS USBSTATUS
echo.
echo   [1] DISABLE USB storage - flash drives and external disks will not open
echo   [2] ENABLE USB storage
echo   [3] READ-ONLY - USB drives open, but nothing can be copied TO them
echo   [4] Remove read-only
echo   [0] Back
echo.
set /p "usb=  Select: "
if "%usb%"=="1" set "USBMODE=DISABLE"
if "%usb%"=="2" set "USBMODE=ENABLE"
if "%usb%"=="3" set "USBMODE=READONLY"
if "%usb%"=="4" set "USBMODE=WRITABLE"
if "%usb%"=="0" goto MENU3
if not "%usb%"=="1" if not "%usb%"=="2" if not "%usb%"=="3" if not "%usb%"=="4" goto OPT79
call :LOG "USB storage %USBMODE%"
call :RUNPS USBSTATUS
call :DONE
goto MENU3

:OPT80
goto OOBEMENU

:OPT81
cls
echo  Network Device Scan - who is on the network
echo  -------------------------------------------
echo  Lists every device on this LAN - IP, MAC, name and maker. Read-only.
echo  Takes 1-2 minutes. Devices that ignore ping may not show.
echo.
call :LOG "Network device scan"
call :RUNPS NETSCAN
call :DONE
goto MENU3

:OPT82
cls
echo  Wi-Fi Signal + Interference
echo  ---------------------------
echo  Signal strength (dBm), band, channel, and other Wi-Fi nearby on the same
echo  channel. Read-only. Best run on the PC that has the weak Wi-Fi.
echo.
call :LOG "Wi-Fi signal check"
call :RUNPS WIFISIGNAL
call :DONE
goto MENU3

:OPT83
cls
set "bw="
echo  Bandwidth - who is using the network
echo  ------------------------------------
echo  One PC sees only its OWN traffic. For other devices, read the router.
echo.
echo   [1] Top talkers on THIS PC - live, per program - no router needed
echo   [2] Open the router page + where per-device traffic is shown
echo   [3] Poll the router / switch by SNMP - per-port bytes - needs SNMP on
echo   [0] Back
echo.
set /p "bw=  Select: "
if "%bw%"=="1" set "BWMODE=LOCAL"
if "%bw%"=="2" set "BWMODE=ROUTER"
if "%bw%"=="3" set "BWMODE=SNMP"
if "%bw%"=="0" goto MENU3
if not "%bw%"=="1" if not "%bw%"=="2" if not "%bw%"=="3" goto OPT83
call :LOG "Bandwidth %BWMODE%"
call :RUNPSI BANDWIDTH
call :DONE
goto MENU3

:OPT84
cls
set "dm="
echo  Windows Image Health - DISM + SFC
echo  ---------------------------------
echo  Checks and repairs the Windows system image. [1] only reads - it changes nothing.
echo.
echo   [1] Diagnose - read-only health check + component store size (HTML report)
echo   [2] Clean up component store - shrink WinSxS, remove superseded updates
echo   [3] Repair ONLINE - DISM RestoreHealth from Windows Update, then SFC (needs internet)
echo   [4] Repair from a Windows ISO / install.wim - when there is no internet or WU is blocked
echo   [5] SFC only - scan and fix protected system files
echo   [0] Back
echo.
set /p "dm=  Select: "
if "%dm%"=="1" set "DISMMODE=DIAGNOSE"
if "%dm%"=="2" set "DISMMODE=CLEANUP"
if "%dm%"=="3" set "DISMMODE=REPAIR"
if "%dm%"=="4" set "DISMMODE=SOURCE"
if "%dm%"=="5" set "DISMMODE=SFC"
if "%dm%"=="0" goto MENU3
if not "%dm%"=="1" if not "%dm%"=="2" if not "%dm%"=="3" if not "%dm%"=="4" if not "%dm%"=="5" goto OPT84
call :LOG "DISM %DISMMODE%"
call :RUNPSI DISM
if /i "%DISMMODE%"=="DIAGNOSE" goto OPT84_REPORT
echo.
pause
goto OPT84
:OPT84_REPORT
call :DONE
goto OPT84

:OPT85
cls
set "og="
echo  File Organizer - sort a folder by type
echo  --------------------------------------
echo  Moves files in a folder YOU choose into subfolders (Images, Videos, PDFs, Word...).
echo  Never touches system folders. Never overwrites - same names are renamed. Can undo.
echo.
echo   [1] Organize a folder
echo   [2] Undo the last organize of a folder
echo   [0] Back
echo.
set /p "og=  Select: "
if "%og%"=="1" set "ORGMODE=ORGANIZE"
if "%og%"=="2" set "ORGMODE=UNDO"
if "%og%"=="0" goto MENU3
if not "%og%"=="1" if not "%og%"=="2" goto OPT85
call :LOG "File organizer %ORGMODE%"
call :RUNPSI FILEORG
if /i "%ORGMODE%"=="ORGANIZE" goto OPT85_REPORT
echo.
pause
goto OPT85
:OPT85_REPORT
call :DONE
goto OPT85

:OPT86
cls
set "fw="
echo  Firewall Center - Windows Defender Firewall
echo  -------------------------------------------
echo   [1]  Check firewall status             [7]  Display custom rules
echo   [2]  Enable firewall - all profiles    [8]  Backup firewall configuration
echo   [3]  Disable firewall - all profiles   [9]  Restore Windows default firewall
echo   [4]  Block an inbound port             [10] Import firewall configuration
echo   [5]  Allow an inbound port             [11] View network firewall profiles
echo   [6]  Remove a custom rule
echo   [0]  Back
echo.
set /p "fw=  Select: "
set "FWMODE="
if "%fw%"=="1" set "FWMODE=STATUS"
if "%fw%"=="2" set "FWMODE=ENABLE"
if "%fw%"=="3" set "FWMODE=DISABLE"
if "%fw%"=="4" set "FWMODE=BLOCKPORT"
if "%fw%"=="5" set "FWMODE=ALLOWPORT"
if "%fw%"=="6" set "FWMODE=REMOVERULE"
if "%fw%"=="7" set "FWMODE=LISTRULES"
if "%fw%"=="8" set "FWMODE=BACKUP"
if "%fw%"=="9" set "FWMODE=RESTORE"
if "%fw%"=="10" set "FWMODE=IMPORT"
if "%fw%"=="11" set "FWMODE=PROFILES"
if "%fw%"=="0" goto MENU3
if not defined FWMODE goto OPT86
call :LOG "Firewall %FWMODE%"
call :RUNPSI FIREWALL
if /i "%FWMODE%"=="STATUS" goto OPT86_REPORT
if /i "%FWMODE%"=="LISTRULES" goto OPT86_REPORT
if /i "%FWMODE%"=="PROFILES" goto OPT86_REPORT
echo.
pause
goto OPT86
:OPT86_REPORT
call :DONE
goto OPT86

:OPT87
cls
echo  Device Type Scan - what kind of device each IP is
echo  -------------------------------------------------
echo  Finds devices on the LAN and identifies them by their open ports:
echo  Hikvision / Dahua NVR-DVR, IP cameras, ZKTeco fingerprint / access control,
echo  printers, PCs, routers and switches. Read-only. Takes 1-3 minutes.
echo.
call :LOG "Device type scan"
call :RUNPS NETDEVID
call :DONE
goto MENU3

:: ============================================================
::  WINDOWS 11 SETUP - LOCAL ACCOUNT INSTEAD OF MICROSOFT ACCOUNT
::  Reached automatically during Windows setup (OOBE), or by option 80.
:: ============================================================
:OOBEMENU
cls
set "oo="
echo.
echo  ==========================================================================================================
echo                      WINDOWS 11 SETUP - LOCAL ACCOUNT, NO MICROSOFT ACCOUNT NEEDED
echo  ==========================================================================================================
if /i "%OOBEFLAG%"=="0x1" echo   Windows setup is running on this PC - these options work now.
if /i not "%OOBEFLAG%"=="0x1" echo   [i] Windows setup is already finished here. To turn an account into a local admin use option 63.
echo  ----------------------------------------------------------------------------------------------------------
echo   [1] Show the "I don't have internet" button - RESTARTS setup. Unplug network cable / Wi-Fi first.
echo       After restart: I don't have internet, Continue with limited setup, type a local user name.
echo.
echo   [2] Open the local account window now - Windows 11 24H2 and newer, no restart.
echo.
echo   [3] Create a local ADMIN account here, then finish setup - RESTARTS the PC.
echo       Use this when [1] and [2] do not work on this Windows build.
echo.
echo   [0] Exit
echo  ==========================================================================================================
set /p "oo=  Select: "
if "%oo%"=="1" set "OOBEMODE=ALLOWNRO"
if "%oo%"=="2" set "OOBEMODE=LOCALONLY"
if "%oo%"=="3" set "OOBEMODE=CREATE"
if "%oo%"=="0" goto OOBEEXIT
if not "%oo%"=="1" if not "%oo%"=="2" if not "%oo%"=="3" goto OOBEMENU
call :RUNPSI OOBE
echo.
pause
goto OOBEMENU
:OOBEEXIT
if /i "%OOBEFLAG%"=="0x1" exit /b
if defined GUIRUN goto END
if /i "%~1"=="/oobe" goto END
goto MENU3

:END
call :LOG "IT Tools closed"
endlocal
exit /b

:: ============================================================
::  HELPERS
:: ============================================================
:CONFIRM
choice /c YN /n /m "  %~1 [Y/N]: "
if errorlevel 2 exit /b 1
exit /b 0

:READKEY
:: Ask for a 25-char product key XXXXX-XXXXX-XXXXX-XXXXX-XXXXX into PKEY
set "PKEY="
set /p "PKEY=  Product key: "
if not defined PKEY exit /b 1
:: Validate in PowerShell via the environment - raw input is never expanded
:: by cmd, so characters like & | < > cannot run commands.
powershell -NoProfile -Command "if ($env:PKEY.Trim() -match '^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$') { exit 0 } else { exit 1 }" <nul
if errorlevel 1 goto READKEY_BAD
set "PKEY=%PKEY: =%"
exit /b 0
:READKEY_BAD
echo  Invalid key format. Expected XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
set "PKEY="
pause
exit /b 1

:FINDOSPP
:: Locate Office ospp.vbs - 64-bit or 32-bit Office
set "OSPP="
for %%P in ("%ProgramFiles%\Microsoft Office\Office16\ospp.vbs" "%ProgramFiles(x86)%\Microsoft Office\Office16\ospp.vbs" "%ProgramFiles%\Microsoft Office\Office15\ospp.vbs" "%ProgramFiles(x86)%\Microsoft Office\Office15\ospp.vbs") do if exist %%P if not defined OSPP set "OSPP=%%~P"
if defined OSPP exit /b 0
echo  Office licensing script ospp.vbs not found - Office not installed,
echo  or it is Microsoft 365 only - use option 9 to sign in.
pause
exit /b 1

:DONE
:: Shared end of an option: FINISHED banner + the report this option wrote, if any.
:: Reports newer than optstart.flag (touched when the option was picked) belong to it.
set "LASTREPORT="
for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$s=(Get-Item -LiteralPath ($env:ITROOT + '\bin\optstart.flag') -ErrorAction SilentlyContinue).LastWriteTime; if (-not $s) { $s=(Get-Date).AddMinutes(-10) }; $f=Get-ChildItem -LiteralPath $env:REPORTROOT -File -Recurse -ErrorAction SilentlyContinue | Where-Object LastWriteTime -ge $s | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($f) { $f.FullName }"`) do set "LASTREPORT=%%R"
echo.
echo  ----------------------------------------------------------------------------------------------------------
if defined LASTREPORT goto DONE_REPORT
echo   FINISHED - read the messages above. Press any key to go back to the menu.
echo  ----------------------------------------------------------------------------------------------------------
pause >nul
exit /b 0
:DONE_REPORT
:: Turn the plain report into a styled HTML page and open that instead.
set "REPORTTXT=%LASTREPORT%"
set "REPORTHTML=%LASTREPORT:.txt=.html%"
if /i not "%LASTREPORT%"=="%REPORTHTML%" call :RUNPS HTMLREPORT
if exist "%REPORTHTML%" set "LASTREPORT=%REPORTHTML%"
echo   FINISHED.  Report: %LASTREPORT%
echo  ----------------------------------------------------------------------------------------------------------
choice /c OM /n /m "  [O] Open the report in the browser    [M] Back to menu: "
if errorlevel 2 exit /b 0
start "" "%LASTREPORT%"
exit /b 0

:STAMP
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"`) do set "STAMP=%%T"
exit /b 0

:LOG
>>"%LOGFILE%" echo [%date% %time%] %COMPUTERNAME% %USERDOMAIN%\%USERNAME% - %~1
exit /b 0

:KILLAPP
:: Close programs (comma list, no .exe) only in THIS session - other
:: users on the same PC / RDP server are not affected.
set "KAPPS=%~1"
powershell -NoProfile -Command "$s=(Get-Process -Id $PID).SessionId; Get-Process -Name ($env:KAPPS -split ',') -ErrorAction SilentlyContinue | Where-Object SessionId -eq $s | Stop-Process -Force -ErrorAction SilentlyContinue" <nul
exit /b 0

:ENSUREEXPLORER
:: Windows restarts Explorer itself after it is closed. Start it only if
:: it did not come back.
timeout /t 4 >nul
powershell -NoProfile -Command "$s=(Get-Process -Id $PID).SessionId; if (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $s) { exit 0 } else { exit 1 }" <nul
if errorlevel 1 start "" "%SystemRoot%\explorer.exe"
exit /b 0

:RUNPS
:: Run a PowerShell block embedded at the end of this file, between
:: ::PS-NAME-BEGIN and ::PS-NAME-END. Exit code of the block is returned.
set "PSBLOCK=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:ITSELF); $r='(?ms)^::PS-' + $env:PSBLOCK + '-BEGIN\r?\n(.*?)^::PS-' + $env:PSBLOCK + '-END'; if ($t -match $r) { $sb=[ScriptBlock]::Create($Matches[1]); & $sb; exit 0 } else { Write-Host ('  Script block missing: ' + $env:PSBLOCK) -ForegroundColor Red; exit 9 }" <nul
exit /b %errorlevel%

:RUNPSI
:: Same as :RUNPS but keeps the keyboard connected for interactive blocks
set "PSBLOCK=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:ITSELF); $r='(?ms)^::PS-' + $env:PSBLOCK + '-BEGIN\r?\n(.*?)^::PS-' + $env:PSBLOCK + '-END'; if ($t -match $r) { $sb=[ScriptBlock]::Create($Matches[1]); & $sb; exit 0 } else { Write-Host ('  Script block missing: ' + $env:PSBLOCK) -ForegroundColor Red; exit 9 }"
exit /b %errorlevel%

:LAUNCHUSER
:: Run a USER_ task as the logged-on user, non-elevated. explorer.exe hands
:: the file to the user's running desktop shell, so it runs with the user's
:: own rights, drives and credentials. %1 = task, %2 = validated argument.
>"%ITROOT%\bin\run.cmd" echo @call "%ITROOT%\bin\Tools.bat" /user %~1 %~2
if "%TEXPLORER%"=="1" (
    start "" "%SystemRoot%\explorer.exe" "%ITROOT%\bin\run.cmd"
) else (
    echo  User desktop not found - running in this window as %USERNAME% instead.
    call "%ITROOT%\bin\Tools.bat" /user %~1 %~2
)
exit /b 0

:: ============================================================
::  USER MODE - runs as the logged-on user, NOT as admin.
::  Started only through :LAUNCHUSER.  Tools.bat /user TASK [ARG]
:: ============================================================
:USERMODE
set "UTASK=%~2"
set "UARG=%~3"
title IT Tools - %USERNAME% - %UTASK%
color 0B
for %%T in (OUTLOOKSAFE OUTLOOKNORMAL OUTLOOKNAV TEAMSSTART TEAMSRESET MAILPROFILES OFFICECRED ONEDRIVERESET NETDRIVES CLEARCRED QUICKASSIST STARTMENU ACCOUNTINFO) do (
    if /i "%UTASK%"=="%%T" goto USER_%%T
)
echo  Unknown user task: %UTASK%
pause
exit /b 1

:USER_OUTLOOKSAFE
start "" outlook.exe /safe
exit /b 0

:USER_OUTLOOKNORMAL
start "" outlook.exe
exit /b 0

:USER_OUTLOOKNAV
start "" outlook.exe /resetnavpane
exit /b 0

:USER_TEAMSSTART
powershell -NoProfile -Command "if (Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" <nul
if not errorlevel 1 (
    start "" "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
    exit /b 0
)
if exist "%LOCALAPPDATA%\Microsoft\Teams\Update.exe" (
    start "" "%LOCALAPPDATA%\Microsoft\Teams\Update.exe" --processStart "Teams.exe"
    exit /b 0
)
echo  Microsoft Teams is not installed for %USERNAME%.
pause
exit /b 1

:USER_TEAMSRESET
echo.
echo  Resetting new Microsoft Teams for %USERDOMAIN%\%USERNAME%...
powershell -NoProfile -Command "$p=Get-AppxPackage -Name MSTeams -ErrorAction SilentlyContinue; if (-not $p) { Write-Host '  New Teams is not installed for this user.' -ForegroundColor Yellow; exit 1 }; Get-Process ms-teams -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; try { $p | Reset-AppxPackage -ErrorAction Stop; Write-Host '  Teams app reset done.' -ForegroundColor Green } catch { Write-Host '  Automatic reset not available - opening Settings: Microsoft Teams - Advanced options - Reset.' -ForegroundColor Yellow; Start-Process 'ms-settings:appsfeatures'; exit 1 }"
if errorlevel 1 (
    pause
    exit /b 1
)
start "" "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
echo  Teams is starting - sign in with the work account.
timeout /t 8
exit /b 0

:USER_ACCOUNTINFO
start "" ms-settings:yourinfo
exit /b 0

:USER_MAILPROFILES
start "" control.exe mlcfg32.cpl
exit /b 0

:USER_QUICKASSIST
where quickassist.exe >nul 2>&1
if errorlevel 1 (start "" "ms-windows-store://pdp/?ProductId=9P7BP5VNWKX5") else start "" quickassist.exe
exit /b 0

:USER_OFFICECRED
echo.
echo  Removing saved Office / Teams credentials for %USERDOMAIN%\%USERNAME%...
set "CREDFILTER=MicrosoftOffice,msteams"
call :USER_DELCRED
echo.
echo  Done. Sign in to Office again.
timeout /t 8
exit /b 0

:USER_CLEARCRED
echo.
echo  Clearing saved credentials and connections for server: %UARG%
echo  ------------------------------------------------------------
set "CREDFILTER=%UARG%"
call :USER_DELCRED
set "SRV=%UARG%"
powershell -NoProfile -Command "Get-SmbMapping -ErrorAction SilentlyContinue | Where-Object { $_.RemotePath -like ('\\' + $env:SRV + '\*') } | ForEach-Object { Write-Host ('  Disconnecting ' + $_.LocalPath + ' ' + $_.RemotePath); Remove-SmbMapping -RemotePath $_.RemotePath -Force -UpdateProfile -ErrorAction SilentlyContinue }"
echo  Clearing Kerberos tickets - Windows gets new ones automatically...
klist purge >nul 2>&1
echo.
echo  Done. Open \\%UARG% again - Windows will ask for the new password if needed.
pause
exit /b 0

:USER_DELCRED
:: Delete Credential Manager entries whose target contains any CREDFILTER word
powershell -NoProfile -Command "$f=$env:CREDFILTER -split ','; $n=0; cmdkey /list | Select-String 'target=(.+)$' | ForEach-Object { $t=$_.Matches[0].Groups[1].Value.Trim(); foreach ($w in $f) { if ($t -like ('*' + $w + '*')) { Write-Host ('  Removing ' + $t); cmdkey /delete:$t | Out-Null; $n++; break } } }; Write-Host ('  ' + $n + ' saved credential(s) removed.')"
exit /b 0

:USER_ONEDRIVERESET
set "OD="
for %%P in ("%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe" "%ProgramFiles%\Microsoft OneDrive\OneDrive.exe" "%ProgramFiles(x86)%\Microsoft OneDrive\OneDrive.exe") do if exist %%P if not defined OD set "OD=%%~P"
if not defined OD (
    echo  OneDrive is not installed for this user.
    pause
    exit /b 1
)
echo  Resetting OneDrive for %USERDOMAIN%\%USERNAME%...
"%OD%" /reset
echo  Waiting for OneDrive to restart...
timeout /t 45
tasklist /fi "imagename eq OneDrive.exe" | find /i "OneDrive.exe" >nul || start "" "%OD%"
echo.
echo  Done. OneDrive resyncs now - check the cloud icon in the taskbar.
pause
exit /b 0

:USER_STARTMENU
echo.
echo  Re-registering Start menu, Search and taskbar packages...
powershell -NoProfile -ExecutionPolicy Bypass -Command "foreach ($n in 'Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.ShellExperienceHost','MicrosoftWindows.Client.CBS','Microsoft.Windows.Search','Microsoft.Windows.Cortana') { Get-AppxPackage -Name $n -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('  ' + $_.Name); Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $_.InstallLocation 'AppXManifest.xml') -ErrorAction SilentlyContinue } }; Get-Process StartMenuExperienceHost, SearchHost, SearchApp, ShellExperienceHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
echo.
echo  Done. Click Start to test. If still broken, sign out and in again.
pause
exit /b 0

:USER_NETDRIVES
cls
echo.
echo  Network Drives - %USERDOMAIN%\%USERNAME%
echo  ----------------------------------------
net use
echo   [1] Map a drive    [2] Remove a drive    [3] Reconnect all saved drives    [0] Close
echo.
set "nd="
set /p "nd=  Select: "
if "%nd%"=="1" goto USER_ND_MAP
if "%nd%"=="2" goto USER_ND_DEL
if "%nd%"=="3" goto USER_ND_RECON
exit /b 0

:USER_ND_MAP
set "NDL="
set "NDP="
set /p "NDL=  Drive letter, e.g. S: "
set /p "NDP=  Share path, e.g. \\server\share: "
if not defined NDL goto USER_NETDRIVES
if not defined NDP goto USER_NETDRIVES
powershell -NoProfile -Command "if (($env:NDL.Trim() -match '^[A-Za-z]:?$') -and ($env:NDP.Trim() -match '^\\\\[\w.-]+(\\[\w .$-]+)+\\?$')) { exit 0 } else { exit 1 }" <nul
if errorlevel 1 goto USER_ND_BAD
set "NDL=%NDL: =%"
set "NDL=%NDL::=%"
net use %NDL%: "%NDP%" /persistent:yes
pause
goto USER_NETDRIVES

:USER_ND_DEL
set "NDL="
set /p "NDL=  Drive letter to remove, e.g. S: "
if not defined NDL goto USER_NETDRIVES
powershell -NoProfile -Command "if ($env:NDL.Trim() -match '^[A-Za-z]:?$') { exit 0 } else { exit 1 }" <nul
if errorlevel 1 goto USER_ND_BAD
set "NDL=%NDL: =%"
set "NDL=%NDL::=%"
net use %NDL%: /delete /y
pause
goto USER_NETDRIVES

:USER_ND_RECON
powershell -NoProfile -Command "Get-ChildItem HKCU:\Network -ErrorAction SilentlyContinue | ForEach-Object { $l=$_.PSChildName.ToUpper() + ':'; $p=(Get-ItemProperty $_.PSPath).RemotePath; if (Test-Path ($l + '\')) { Write-Host ('  ' + $l + ' OK  ' + $p) } else { Write-Host ('  Reconnecting ' + $l + ' ' + $p); net use $l /delete /y 2>$null | Out-Null; net use $l $p /persistent:yes } }"
pause
goto USER_NETDRIVES

:USER_ND_BAD
echo  Invalid input. Example: drive S and path \\fileserver\shared
pause
goto USER_NETDRIVES

:: ============================================================
::  EMBEDDED POWERSHELL BLOCKS - read and run by :RUNPS.
::  cmd never executes these lines.
:: ============================================================
exit /b 0

::PS-HARDWAREREPORT-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$base = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Hardware_' + $stamp)
$txt = $base + '.txt'
Start-Transcript -Path $txt -Force | Out-Null
Write-Host '=== SYSTEM ===' -ForegroundColor Cyan
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,SystemType,TotalPhysicalMemory | Format-List
Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,SerialNumber,ReleaseDate | Format-List
Write-Host '=== CPU ===' -ForegroundColor Cyan
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,LoadPercentage | Format-Table -AutoSize
Write-Host '=== MEMORY MODULES ===' -ForegroundColor Cyan
Get-CimInstance Win32_PhysicalMemory | Select-Object DeviceLocator,Manufacturer,PartNumber,@{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,2)}},Speed,ConfiguredClockSpeed | Format-Table -AutoSize
Write-Host '=== PHYSICAL DISKS ===' -ForegroundColor Cyan
Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,@{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize
Write-Host '=== STORAGE RELIABILITY (WHEN SUPPORTED) ===' -ForegroundColor Cyan
Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object { $d=$_; try { Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop | Select-Object @{n='Disk';e={$d.FriendlyName}},Temperature,TemperatureMax,Wear,PowerOnHours,ReadErrorsTotal,WriteErrorsTotal } catch { [pscustomobject]@{Disk=$d.FriendlyName;Note='Reliability counters unsupported by this device/controller'} } } | Format-Table -AutoSize
Write-Host '=== PNP PROBLEM DEVICES ===' -ForegroundColor Cyan
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -ne 'OK' | Select-Object Status,Class,FriendlyName,InstanceId | Format-Table -Wrap -AutoSize
Stop-Transcript | Out-Null
Write-Host ('Report saved: ' + $txt) -ForegroundColor Green
# Report is opened as an HTML page by :DONE.
::PS-HARDWAREREPORT-END

::PS-BSODREPORT-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_BSOD_' + $stamp + '.txt')
$since = (Get-Date).AddDays(-30)
$events = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,1001,6008; StartTime=$since} -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message)
$wer = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$since} -MaxEvents 100 -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message)
$dumps = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter '*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 30 FullName,Length,LastWriteTime)
$full = @(Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime)
$lines = @('BSOD / CRASH ANALYSIS - last 30 days','Computer: ' + $env:COMPUTERNAME,'Generated: ' + (Get-Date),'','=== BugCheck / Kernel-Power / Unexpected Shutdown ===')
$lines += if ($events) { $events | Format-List * | Out-String -Width 240 } else { 'No matching events found in the selected period.' }
$lines += '=== Windows Error Reporting ==='
$lines += if ($wer) { $wer | Format-List * | Out-String -Width 240 } else { 'No WER events found.' }
$lines += '=== Minidump files ==='
$lines += if ($dumps) { $dumps | Format-Table -AutoSize | Out-String -Width 240 } else { 'No minidump files found.' }
$lines += '=== Full memory dump ==='
$lines += if ($full) { $full | Format-List | Out-String } else { 'No MEMORY.DMP found.' }
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Found ' + $events.Count + ' relevant system events, ' + $wer.Count + ' WER events, and ' + $dumps.Count + ' minidump files.')
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-BSODREPORT-END

::PS-PERFORMANCE-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Performance_' + $stamp + '.txt')
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average
$memTotal = [double]$os.TotalVisibleMemorySize * 1KB
$memFree = [double]$os.FreePhysicalMemory * 1KB
$disk = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,@{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},@{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}},@{n='FreePct';e={if ($_.Size) {[math]::Round(100*$_.FreeSpace/$_.Size,1)} else {0}}}
$topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name,Id,CPU,WorkingSet64
$topMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name,Id,@{n='MemoryMB';e={[math]::Round($_.WorkingSet64/1MB,1)}}
$lines = @('PERFORMANCE SNAPSHOT','Computer: ' + $env:COMPUTERNAME,'Generated: ' + (Get-Date),'OS: ' + $os.Caption + ' ' + $os.Version,'Uptime: ' + ((Get-Date)-$os.LastBootUpTime),'CPU average load: ' + [math]::Round($cpu.Average,1) + '%','Memory used: ' + [math]::Round(100*(1-$memFree/$memTotal),1) + '%','')
$lines += '=== Logical disks ==='; $lines += $disk | Format-Table -AutoSize | Out-String
$lines += '=== Top CPU (cumulative process CPU time) ==='; $lines += $topCpu | Format-Table -AutoSize | Out-String
$lines += '=== Top memory ==='; $lines += $topMem | Format-Table -AutoSize | Out-String
$lines += '=== Startup entries ==='; $lines += Get-CimInstance Win32_StartupCommand | Select-Object Name,Location,User,Command | Format-Table -Wrap -AutoSize | Out-String
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-PERFORMANCE-END

::PS-DRIVERREPORT-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
# CSV detail goes in a subfolder; the .txt summary (written LAST) is what :DONE turns into HTML.
$dir = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Drivers_' + $stamp)
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$all = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Select-Object DeviceName,DeviceClass,Manufacturer,DriverProviderName,DriverVersion,DriverDate,InfName,IsSigned)
$all | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $dir 'DriverInventory.csv')
$problem = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -ne 'OK' | Select-Object Status,Class,FriendlyName,InstanceId)
$problem | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $dir 'ProblemDevices.csv')
$unsigned = @($all | Where-Object { $_.IsSigned -eq $false })
$unsigned | Select-Object DeviceName,DeviceClass,Manufacturer,DriverProviderName,DriverVersion,InfName | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $dir 'UnsignedDrivers.csv')
# Drivers older than 3 years - worth updating
$old = @($all | Where-Object { $_.DriverDate -and ([datetime]$_.DriverDate) -lt (Get-Date).AddYears(-3) -and $_.DriverProviderName -ne 'Microsoft' } | Sort-Object { [datetime]$_.DriverDate })
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Drivers_' + $stamp + '.txt')
$lines = @('DRIVER AUDIT','Computer: ' + $env:COMPUTERNAME,'Generated: ' + (Get-Date),'')
$lines += '== Summary'
$lines += ('   Total drivers: ' + $all.Count)
$lines += ('   Problem devices: ' + $problem.Count)
$lines += ('   Unsigned driver records: ' + $unsigned.Count)
$lines += ('   Drivers over 3 years old (non-Microsoft): ' + $old.Count)
$lines += ('   Full CSV detail: ' + $dir)
$lines += ''
$lines += '== Problem devices (status not OK)'
$lines += if ($problem.Count) { $problem | Format-Table Status,Class,FriendlyName -AutoSize | Out-String -Width 200 } else { '   OK - no problem devices.' }
$lines += '== Unsigned drivers - verify the source, not automatically malware'
$lines += if ($unsigned.Count) { $unsigned | Format-Table DeviceName,Manufacturer,DriverVersion,InfName -AutoSize | Out-String -Width 220 } else { '   OK - all present drivers are signed.' }
$lines += '== Oldest non-Microsoft drivers (update candidates)'
$lines += if ($old.Count) { $old | Select-Object -First 25 DeviceName,DriverProviderName,DriverVersion,@{n='DriverDate';e={([datetime]$_.DriverDate).ToString('yyyy-MM-dd')}} | Format-Table -AutoSize | Out-String -Width 220 } else { '   None over 3 years old.' }
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Drivers: ' + $all.Count + '   Problem devices: ' + $problem.Count + '   Unsigned: ' + $unsigned.Count + '   Old (3y+): ' + $old.Count)
Write-Host ('CSV detail saved in: ' + $dir) -ForegroundColor Green
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
Write-Host 'Note: an unsigned driver is not automatically malicious; verify its source and hardware role.' -ForegroundColor Yellow
::PS-DRIVERREPORT-END

::PS-UPDATEHEALTH-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_WindowsUpdate_' + $stamp + '.txt')
$svc = Get-CimInstance Win32_Service -Filter "Name='wuauserv' OR Name='bits' OR Name='cryptsvc' OR Name='usosvc'" -ErrorAction SilentlyContinue | Select-Object Name,State,StartMode
$pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
$ev = @(Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 500 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'WindowsUpdate|Update' -or $_.Message -match 'Windows Update|update failed' } | Select-Object -First 80 TimeCreated,Id,ProviderName,Message)
$lines = @('WINDOWS UPDATE HEALTH','Generated: ' + (Get-Date),'Pending reboot: ' + $pending,'','=== Update services ===')
$lines += $svc | Format-Table -AutoSize | Out-String
$lines += '=== Recent update-related System events (7 days) ==='
$lines += if ($ev) { $ev | Format-List * | Out-String -Width 220 } else { 'No matching update-related System events found.' }
$lines += '=== Recent installed hotfixes ==='
$lines += Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 25 HotFixID,Description,InstalledOn | Format-Table -AutoSize | Out-String
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Pending reboot: ' + $pending) -ForegroundColor $(if ($pending) {'Yellow'} else {'Green'})
$svc | Format-Table -AutoSize
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-UPDATEHEALTH-END

::PS-NETWORKREPORT-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_NetworkDeep_' + $stamp + '.txt')
$lines = @('ADVANCED NETWORK DIAGNOSTICS','Generated: ' + (Get-Date),'')
$lines += '=== Adapters ==='; $lines += Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress | Format-Table -AutoSize | Out-String
$lines += '=== IP configuration ==='; $lines += ipconfig /all | Out-String
$lines += '=== Default routes ==='; $lines += Get-NetRoute -DestinationPrefix '0.0.0.0/0','::/0' -ErrorAction SilentlyContinue | Select-Object DestinationPrefix,NextHop,InterfaceAlias,RouteMetric | Format-Table -AutoSize | Out-String
$lines += '=== DNS servers ==='; $lines += Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Where-Object ServerAddresses | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | Format-List | Out-String
$lines += '=== Proxy ==='; $lines += netsh winhttp show proxy | Out-String
$lines += '=== Connectivity ==='
foreach ($hostName in @('1.1.1.1','8.8.8.8','www.microsoft.com','www.google.com')) { try { $r=Test-NetConnection -ComputerName $hostName -Port 443 -WarningAction SilentlyContinue; $lines += ($hostName + ' TCP/443: ' + $r.TcpTestSucceeded + ' Remote=' + $r.RemoteAddress) } catch { $lines += ($hostName + ': test failed - ' + $_.Exception.Message) } }
$lines += '=== DNS resolution ==='; foreach ($name in @('www.microsoft.com','www.google.com')) { try { $lines += (Resolve-DnsName $name -ErrorAction Stop | Select-Object -First 3 Name,Type,IPAddress | Format-Table -AutoSize | Out-String) } catch { $lines += ($name + ': DNS lookup failed - ' + $_.Exception.Message) } }
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-NETWORKREPORT-END

::PS-SECURITYAUDIT-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_SecurityAudit_' + $stamp + '.txt')
$lines = @('READ-ONLY SECURITY BASELINE AUDIT','Generated: ' + (Get-Date),'')
$lines += '=== Microsoft Defender ==='
try { $lines += Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,AntivirusSignatureLastUpdated,AntivirusSignatureAge | Format-List | Out-String } catch { $lines += 'Defender status unavailable (another AV may be active or cmdlets unavailable).' }
$lines += '=== Firewall profiles ==='; $lines += Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction | Format-Table -AutoSize | Out-String
$lines += '=== BitLocker ==='; $lines += manage-bde -status 2>&1 | Out-String
$lines += '=== Local Administrators ==='; try { $lines += Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object Name,ObjectClass,PrincipalSource | Format-Table -AutoSize | Out-String } catch { $lines += 'Could not enumerate local Administrators group with Get-LocalGroupMember.' }
$rdp = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue
$lines += 'RDP connections allowed by registry: ' + ($rdp.fDenyTSConnections -eq 0)
$lines += '=== Pending reboot ==='; $lines += ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'))
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Read-only audit saved: ' + $out) -ForegroundColor Green
Write-Host 'Review findings in context. This audit does not label unsigned software as malware or change security settings.' -ForegroundColor Yellow
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-SECURITYAUDIT-END

::PS-EVENTINTEL-BEGIN
$stamp = Get-Date -Format yyyyMMdd_HHmmss
$out = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_RecurringEvents_' + $stamp + '.txt')
$since = (Get-Date).AddDays(-7)
$events = @(Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=$since} -MaxEvents 3000 -ErrorAction SilentlyContinue)
$groups = $events | Group-Object ProviderName,Id,LogName | Sort-Object Count -Descending | Select-Object -First 40
$lines = @('RECURRING EVENT ERROR ANALYSIS - last 7 days','Computer: ' + $env:COMPUTERNAME,'Generated: ' + (Get-Date),'Total collected errors/critical events: ' + $events.Count,'','=== Most frequent sources ===')
foreach ($g in $groups) { $e=$g.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1; $lines += ('Count: ' + $g.Count + ' | Provider: ' + $e.ProviderName + ' | Event ID: ' + $e.Id + ' | Log: ' + $e.LogName + ' | Latest: ' + $e.TimeCreated); $lines += ('Latest message: ' + (($e.Message -replace '\s+',' ').Trim())); $lines += '' }
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Analyzed ' + $events.Count + ' error/critical events; grouped into ' + @($groups).Count + ' recurring sources.') -ForegroundColor Cyan
Write-Host ('Report saved: ' + $out) -ForegroundColor Green
# Report is opened as an HTML page by :DONE - do not open the .txt here.
::PS-EVENTINTEL-END

::PS-OPTIMIZE-BEGIN
# Mode from $env:OPTMODE: STATUS | APPLY | REVERT
# Each entry: registry path, value name, recommended DWORD, description.
# HKLM entries are local policies. User entries go to the target user hive.
$m   = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft'
$u   = 'Registry::HKEY_USERS\' + $env:TSID
$cdm = $u + '\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$adv = $u + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$list = @(
    @("$m\Windows\DeliveryOptimization", 'DODownloadMode', 0, 'Update sharing: no upload of updates to other PCs'),
    @("$m\Windows\DataCollection", 'AllowTelemetry', 1, 'Diagnostic data: Required only'),
    @("$m\Windows\DataCollection", 'DoNotShowFeedbackNotifications', 1, 'Feedback request popups off'),
    @("$m\Windows\CloudContent", 'DisableWindowsConsumerFeatures', 1, 'Auto-installed suggested apps/games off'),
    @("$m\Windows\CloudContent", 'DisableSoftLanding', 1, 'Windows tips off'),
    @("$m\Windows\AdvertisingInfo", 'DisabledByGroupPolicy', 1, 'Advertising ID off'),
    @("$m\Windows\System", 'PublishUserActivities', 0, 'Activity history off'),
    @("$m\Windows\System", 'UploadUserActivities', 0, 'Activity history upload off'),
    @("$m\Dsh", 'AllowNewsAndInterests', 0, 'Widgets news feed off - Win 11'),
    @("$m\Windows\Windows Feeds", 'EnableFeeds', 0, 'News and interests off - Win 10'),
    @("$m\Windows\Windows Search", 'DisableWebSearch', 1, 'Bing web results in Windows search off'),
    @("$m\Windows\Windows Search", 'ConnectedSearchUseWeb', 0, 'Connected web search off'),
    @("$m\Windows\Windows Search", 'AllowCortana', 0, 'Cortana off'),
    @("$m\Windows\Maps", 'AutoDownloadAndUpdateMapData', 0, 'Offline maps auto download off'),
    @("$m\Windows\GameDVR", 'AllowGameDVR', 0, 'Xbox background game recording off'),
    @("$m\Windows\WindowsAI", 'DisableAIDataAnalysis', 1, 'Recall screen snapshots off'),
    @("$m\Edge", 'StartupBoostEnabled', 0, 'Edge preloading at sign-in off'),
    @("$m\Edge", 'BackgroundModeEnabled', 0, 'Edge keeps running after close - off')
)
if ($env:TSID) {
    $list += @(
        @("$u\Software\Policies\Microsoft\Windows\Explorer", 'DisableSearchBoxSuggestions', 1, 'User: Bing suggestions in Start search off'),
        @("$u\Software\Microsoft\Windows\CurrentVersion\Search", 'BingSearchEnabled', 0, 'User: Bing search off'),
        @($cdm, 'SilentInstalledAppsEnabled', 0, 'User: silent install of promoted apps off'),
        @($cdm, 'SystemPaneSuggestionsEnabled', 0, 'User: Start menu suggestions off'),
        @($cdm, 'SoftLandingEnabled', 0, 'User: tips about Windows off'),
        @($cdm, 'SubscribedContent-338388Enabled', 0, 'User: Start suggested content off'),
        @($cdm, 'SubscribedContent-338389Enabled', 0, 'User: tips and tricks notifications off'),
        @($cdm, 'SubscribedContent-310093Enabled', 0, 'User: welcome screen after updates off'),
        @($cdm, 'SubscribedContent-353694Enabled', 0, 'User: Settings app suggestions off'),
        @($cdm, 'SubscribedContent-353696Enabled', 0, 'User: Settings app suggestions 2 off'),
        @($adv, 'Start_IrisRecommendations', 0, 'User: Start menu recommendations/ads off'),
        @($adv, 'ShowSyncProviderNotifications', 0, 'User: File Explorer promo notices off'),
        @("$u\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement", 'ScoobeSystemSettingEnabled', 0, 'User: Finish setting up your device nag off')
    )
}

$mode = $env:OPTMODE
$good = 0
foreach ($e in $list) {
    $path, $name, $want, $desc = $e
    $cur = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name

    if ($mode -eq 'APPLY') {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value $want -PropertyType DWord -Force | Out-Null
        Write-Host ('  [set]     ' + $desc) -ForegroundColor Green
    }
    elseif ($mode -eq 'REVERT') {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        Write-Host ('  [default] ' + $desc) -ForegroundColor Yellow
    }
    else {
        if ($null -ne $cur -and [int]$cur -eq $want) {
            $good++
            Write-Host ('  [OK]  ' + $desc) -ForegroundColor Green
        } else {
            Write-Host ('  [--]  ' + $desc) -ForegroundColor DarkYellow
        }
    }
}
if ($mode -eq 'STATUS') {
    Write-Host ''
    Write-Host ('  ' + $good + ' of ' + $list.Count + ' recommended settings already applied.')
}
if ($mode -eq 'APPLY') {
    # Delivery Optimization picks up the new mode on service restart
    Restart-Service DoSvc -Force -ErrorAction SilentlyContinue
}
exit 0
::PS-OPTIMIZE-END

::PS-DEEPCLEAN-BEGIN
# Measures and deletes the CONTENTS of known junk folders. Locked files are skipped.
function Get-Size($paths) {
    $s = 0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $s += (Get-ChildItem -Path $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        }
    }
    return [double]$s
}
function Clear-Junk($title, $paths) {
    $before = Get-Size $paths
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $after = Get-Size $paths
    $freed = [math]::Max(0, $before - $after) / 1MB
    Write-Host ('  {0,-42} {1,10:N0} MB freed' -f $title, $freed)
    return $freed
}

$sys   = $env:SystemRoot
$tl    = $env:TLOCAL
$drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'")
$startFree = $drive.FreeSpace
$total = 0

Write-Host ''
$total += Clear-Junk 'Temp files - user, admin, Windows' @("$tl\Temp", $env:TEMP, "$sys\Temp")

Write-Host '  Stopping Windows Update service for cache cleanup...' -ForegroundColor DarkGray
Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
$total += Clear-Junk 'Windows Update download cache' @("$sys\SoftwareDistribution\Download")
Start-Service bits, wuauserv -ErrorAction SilentlyContinue

$doBefore = Get-Size @("$sys\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache")
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
$doAfter = Get-Size @("$sys\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache")
$doFreed = [math]::Max(0, $doBefore - $doAfter) / 1MB
Write-Host ('  {0,-42} {1,10:N0} MB freed' -f 'Delivery Optimization cache', $doFreed)
$total += $doFreed

$total += Clear-Junk 'Windows error reports' @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:ProgramData\Microsoft\Windows\WER\Temp", "$tl\Microsoft\Windows\WER")
$total += Clear-Junk 'Crash dumps' @("$sys\Minidump", "$sys\LiveKernelReports", "$tl\CrashDumps")
if (Test-Path "$sys\MEMORY.DMP") {
    $md = (Get-Item "$sys\MEMORY.DMP" -Force).Length / 1MB
    Remove-Item "$sys\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
    Write-Host ('  {0,-42} {1,10:N0} MB freed' -f 'Full memory dump - MEMORY.DMP', $md)
    $total += $md
}
$total += Clear-Junk 'Graphics shader cache' @("$tl\D3DSCache", "$tl\NVIDIA\DXCache", "$tl\NVIDIA\GLCache", "$tl\AMD\DxCache", "$tl\AMD\DxcCache")

$drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'")
Write-Host ''
Write-Host ('  Total cleaned: {0:N0} MB.   {1} free: {2:N1} GB' -f $total, $env:SystemDrive, ($drive.FreeSpace / 1GB)) -ForegroundColor Green

# Information only - never deleted automatically
$dl = Get-Size @("$env:TPROFILE\Downloads")
$rb = Get-Size @("$env:SystemDrive\`$Recycle.Bin")
Write-Host ('  Info: user Downloads folder {0:N1} GB, Recycle Bin {1:N1} GB - not touched.' -f ($dl / 1GB), ($rb / 1GB))
exit 0
::PS-DEEPCLEAN-END

::PS-CLEANMGRFLAGS-BEGIN
# Select Disk Cleanup categories for: cleanmgr /sagerun:77
$cats = 'Active Setup Temp Folders','D3D Shader Cache','Delivery Optimization Files',
        'Device Driver Packages','Diagnostic Data Viewer database files','Downloaded Program Files',
        'Internet Cache Files','Old ChkDsk Files','Previous Installations','Setup Log Files',
        'System error memory dump files','System error minidump files','Temporary Files',
        'Temporary Setup Files','Update Cleanup','Upgrade Discarded Files',
        'Windows Error Reporting Files','Windows ESD installation files','Windows Upgrade Log Files'
$base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
foreach ($c in $cats) {
    if (Test-Path "$base\$c") {
        New-ItemProperty -Path "$base\$c" -Name 'StateFlags0077' -Value 2 -PropertyType DWord -Force | Out-Null
    }
}
exit 0
::PS-CLEANMGRFLAGS-END

::PS-OUTLOOKTEAMS-BEGIN
# Runs elevated. Targets the logged-on user via TSID / TLOCAL / TROAMING.
$session = (Get-Process -Id $PID).SessionId
$tl = $env:TLOCAL
$tr = $env:TROAMING
$u  = 'Registry::HKEY_USERS\' + $env:TSID
$warn = 0

Write-Host ''
Write-Host '  1. Checking Office update / repair...'
if (Get-Process OfficeC2RClient -ErrorAction SilentlyContinue) {
    Write-Host '     [!] Office update or repair is running - Office apps stay blocked until it finishes.' -ForegroundColor Yellow
    $warn++
} else { Write-Host '     OK - no Office update running.' -ForegroundColor Green }

Write-Host '  2. Closing hidden Outlook / Teams processes in this session...'
$names = 'OUTLOOK','olk','ms-teams','ms-teamsupdate','Teams','ucmapi','lync'
$procs = @(Get-Process -Name $names -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
# WebView2 helpers that belong to new Teams / new Outlook - they keep the app "stuck"
$wv = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $session -and $_.CommandLine -match 'ms-teams\.exe|olk\.exe|MSTeams|OutlookForWindows' })
foreach ($p in $procs) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
foreach ($p in $wv)    { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
$left = @(Get-Process -Name $names -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
Write-Host ('     Closed ' + $procs.Count + ' app process(es) and ' + $wv.Count + ' WebView2 helper(s).') -ForegroundColor Green
if ($left.Count -gt 0) {
    Write-Host ('     [!] Could not close: ' + (($left.Name | Sort-Object -Unique) -join ', ') + ' - restart the PC.') -ForegroundColor Red
    $warn++
}

Write-Host '  3. Removing compatibility mode / run-as-admin flags...'
$removed = 0
foreach ($root in @($u, 'Registry::HKEY_LOCAL_MACHINE')) {
    $k = $root + '\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($props) {
        foreach ($pr in $props.PSObject.Properties) {
            if ($pr.Name -match '\\(OUTLOOK|ms-teams|Teams|olk)\.exe$') {
                Remove-ItemProperty -Path $k -Name $pr.Name -ErrorAction SilentlyContinue
                Write-Host ('     Removed flag ' + $pr.Value + ' on ' + $pr.Name) -ForegroundColor Yellow
                $removed++
            }
        }
    }
}
if ($removed -eq 0) { Write-Host '     OK - no flags found.' -ForegroundColor Green }

Write-Host '  4. Clearing Teams cache...'
$newTeams = "$tl\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
if (Test-Path $newTeams) { Remove-Item $newTeams -Recurse -Force -ErrorAction SilentlyContinue; Write-Host '     New Teams cache cleared.' -ForegroundColor Green }
$classic = "$tr\Microsoft\Teams"
if (Test-Path $classic) {
    foreach ($d in 'Cache','blob_storage','databases','GPUCache','IndexedDB','Local Storage','tmp','Code Cache','Service Worker') {
        Remove-Item (Join-Path $classic $d) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host '     Classic Teams cache cleared.' -ForegroundColor Green
}

Write-Host '  5. Clearing Outlook temp cache - autocomplete kept...'
$roam = "$tl\Microsoft\Outlook\RoamCache"
if (Test-Path $roam) {
    Get-ChildItem $roam -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'Stream_Autocomplete*' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
$sec = (Get-ItemProperty ($u + '\Software\Microsoft\Office\16.0\Outlook\Security') -Name OutlookSecureTempFolder -ErrorAction SilentlyContinue).OutlookSecureTempFolder
if ($sec -and (Test-Path $sec)) {
    Get-ChildItem $sec -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '     Outlook attachment temp folder cleared.' -ForegroundColor Green
}
Write-Host '     Done.' -ForegroundColor Green

Write-Host '  6. Checking Microsoft Edge WebView2 Runtime - needed by new Teams / new Outlook...'
$wvGuid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$wvKeys = @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$wvGuid",
            "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$wvGuid",
            "$u\Software\Microsoft\EdgeUpdate\Clients\$wvGuid")
$wvVer = $null
foreach ($k in $wvKeys) { $v = (Get-ItemProperty $k -Name pv -ErrorAction SilentlyContinue).pv; if ($v -and $v -ne '0.0.0.0') { $wvVer = $v; break } }
if ($wvVer) { Write-Host ('     OK - WebView2 ' + $wvVer) -ForegroundColor Green }
else {
    Write-Host '     [!] WebView2 Runtime MISSING - new Teams and new Outlook cannot open.' -ForegroundColor Red
    Write-Host '         Install: https://go.microsoft.com/fwlink/p/?LinkId=2124703' -ForegroundColor Red
    $warn++
}

Write-Host '  7. Checking Teams installation...'
$t = Get-AppxPackage -Name MSTeams -User $env:TSID -ErrorAction SilentlyContinue
if ($t) { Write-Host ('     New Teams ' + $t.Version + ' installed.') -ForegroundColor Green }
elseif (Test-Path "$tl\Microsoft\Teams\Update.exe") { Write-Host '     Classic Teams installed - retired by Microsoft, install new Teams.' -ForegroundColor Yellow; $warn++ }
else { Write-Host '     [!] Teams not installed for this user.' -ForegroundColor Yellow; $warn++ }

Write-Host '  8. Checking free disk space...'
$d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'")
$freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
if ($freeGB -lt 5) {
    Write-Host ('     [!] Only ' + $freeGB + ' GB free on ' + $env:SystemDrive + ' - Outlook and Teams hang when the disk is full. Use option 61.') -ForegroundColor Red
    $warn++
} else { Write-Host ('     OK - ' + $freeGB + ' GB free.') -ForegroundColor Green }

Write-Host ''
if ($warn -eq 0) { Write-Host '  All checks passed - start the app below.' -ForegroundColor Green }
else { Write-Host ('  ' + $warn + ' warning(s) above - fix them first if the app still will not open.') -ForegroundColor Yellow }
exit 0
::PS-OUTLOOKTEAMS-END

::PS-ACCOUNTS-BEGIN
# Mode from $env:ACCTMODE: LIST | CREATE | COPY | REMOVE.  Interactive, runs elevated.
$ErrorActionPreference = 'Stop'
$adminSid = 'S-1-5-32-544'
$usersSid = 'S-1-5-32-545'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

# Folders copied / backed up from a profile (paths relative to the profile root)
$dataFolders = 'Desktop','Documents','Downloads','Pictures','Videos','Music','Favorites','Links','Contacts',
               'AppData\Roaming\Microsoft\Signatures',
               'AppData\Roaming\Microsoft\Sticky Notes',
               'AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState'
$bookmarkFiles = 'AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks',
                 'AppData\Local\Google\Chrome\User Data\Default\Bookmarks'

function Get-AdminSids {
    try { return @((Get-LocalGroupMember -SID $adminSid).SID.Value) }
    catch {
        # Fallback when the group contains orphaned / cloud members (known cmdlet bug)
        $g = [ADSI]('WinNT://./' + (Get-LocalGroup -SID $adminSid).Name + ',group')
        return @($g.psbase.Invoke('Members') | ForEach-Object {
            $b = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
            (New-Object Security.Principal.SecurityIdentifier($b, 0)).Value })
    }
}
function Get-Profiles {
    @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -like '*\Users\*' } |
      ForEach-Object {
        $n = try { (New-Object Security.Principal.SecurityIdentifier($_.SID)).Translate([Security.Principal.NTAccount]).Value } catch { '(unknown - deleted account)' }
        [pscustomobject]@{ Account = $n; SID = $_.SID; Path = $_.LocalPath; SignedIn = $_.Loaded; LastUsed = $_.LastUseTime }
      })
}
function Show-Accounts {
    $admins = Get-AdminSids
    $profiles = Get-Profiles
    Write-Host ''
    Write-Host '  LOCAL USERS' -ForegroundColor Cyan
    Get-LocalUser | ForEach-Object {
        $sid = $_.SID.Value
        [pscustomobject]@{
            User     = $_.Name
            Type     = $(if ($_.PrincipalSource -eq 'MicrosoftAccount') { 'MICROSOFT account' } else { 'Local' })
            Admin    = $(if ($admins -contains $sid) { 'Yes' } else { '' })
            Enabled  = $_.Enabled
            SignedIn = $(if (($profiles | Where-Object SID -eq $sid).SignedIn) { 'Yes' } else { '' })
            Profile  = ($profiles | Where-Object SID -eq $sid).Path
        }
    } | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    $other = $profiles | Where-Object { -not (Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue) }
    if ($other) {
        Write-Host '  OTHER PROFILES - domain / Entra ID work accounts, or deleted users' -ForegroundColor Cyan
        $other | Format-Table Account, Path, SignedIn, LastUsed -AutoSize | Out-String -Width 200 | Write-Host
    }
}
function Read-Choice($prompt, $max) {
    $a = Read-Host $prompt
    $n = 0
    if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $max) { return $n }
    return 0
}
function Copy-ProfileData($src, $dst) {
    foreach ($f in $dataFolders) {
        $s = Join-Path $src $f
        if (Test-Path -LiteralPath $s) {
            Write-Host ('  Copying ' + $f + ' ...')
            robocopy $s (Join-Path $dst $f) /E /XJ /R:1 /W:1 /MT:8 /NP /NFL /NDL /NJH /NJS | Out-Null
            if ($LASTEXITCODE -ge 8) { Write-Host ('    [!] Some files in ' + $f + ' could not be copied - locked or no access.') -ForegroundColor Yellow }
        }
    }
    foreach ($b in $bookmarkFiles) {
        $s = Join-Path $src $b
        if (Test-Path -LiteralPath $s) {
            $d = Join-Path $dst $b
            New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
            if (Test-Path -LiteralPath $d) { Copy-Item -LiteralPath $d ($d + '.before_ITTools') -Force }
            Copy-Item -LiteralPath $s $d -Force
            Write-Host ('  Copied browser bookmarks: ' + ($b -split '\\')[3])
        }
    }
    $od = Get-ChildItem -LiteralPath $src -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -like 'OneDrive*'
    if ($od) {
        Write-Host ('  [i] OneDrive folders were NOT copied - ' + (($od.Name) -join ', ') + '.') -ForegroundColor Yellow
        Write-Host '      Sign in to OneDrive in the new account and the files sync back from the cloud.' -ForegroundColor Yellow
    }
}

try {
switch ($env:ACCTMODE) {

'LIST' { Show-Accounts }

'CREATE' {
    Write-Host ''
    Write-Host '  Create Local Administrator' -ForegroundColor Cyan
    $name = (Read-Host '  New user name - letters, numbers, . _ - , max 20').Trim()
    if ($name -notmatch '^[A-Za-z0-9._-]{1,20}$') { Write-Host '  Invalid user name.' -ForegroundColor Red; break }
    if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) { Write-Host '  That user already exists.' -ForegroundColor Red; break }
    $full = (Read-Host '  Full name - optional, press Enter to skip').Trim()

    Write-Host '  Enter the password in the window that opens...'
    $c1 = Get-Credential -UserName $name -Message 'Password for the new local administrator'
    if (-not $c1) { Write-Host '  Cancelled.'; break }
    $c2 = Get-Credential -UserName $name -Message 'Type the same password again to confirm'
    if (-not $c2) { Write-Host '  Cancelled.'; break }
    $p1 = $c1.GetNetworkCredential().Password
    $p2 = $c2.GetNetworkCredential().Password
    if ($p1 -ne $p2) { Write-Host '  Passwords do not match - nothing created.' -ForegroundColor Red; break }
    if ($p1.Length -lt 8) { Write-Host '  Password must be at least 8 characters - nothing created.' -ForegroundColor Red; break }
    $p1 = $null; $p2 = $null

    $params = @{ Name = $name; Password = $c1.Password; PasswordNeverExpires = $true; Description = 'Created by IT Tools' }
    if ($full) { $params.FullName = $full }
    New-LocalUser @params | Out-Null
    Add-LocalGroupMember -SID $adminSid -Member $name
    try { Add-LocalGroupMember -SID $usersSid -Member $name } catch {}
    Write-Host ''
    Write-Host ('  Local administrator "' + $name + '" created.') -ForegroundColor Green
    Write-Host '  NEXT: sign in once as this user so Windows creates the profile,'
    Write-Host '        then come back and use [3] to copy the files into it.'
}

'COPY' {
    $profiles = Get-Profiles
    Write-Host ''
    Write-Host '  Profiles on this PC:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        Write-Host ('   [{0}] {1,-35} {2,-30} {3}' -f ($i + 1), $p.Account, $p.Path, $(if ($p.SignedIn) { 'signed in' } else { '' }))
    }
    $s = Read-Choice '  Copy FROM profile number' $profiles.Count
    $d = Read-Choice '  Copy TO profile number' $profiles.Count
    if ($s -eq 0 -or $d -eq 0 -or $s -eq $d) { Write-Host '  Invalid selection.' -ForegroundColor Red; break }
    $src = $profiles[$s - 1]; $dst = $profiles[$d - 1]
    Write-Host ('  From: ' + $src.Path)
    Write-Host ('  To:   ' + $dst.Path)
    Write-Host '  Copies Desktop, Documents, Downloads, Pictures, Videos, Music, Favorites, Outlook signatures,'
    Write-Host '  Sticky Notes and Edge/Chrome bookmarks. Nothing is deleted from the source.'
    if ($dst.SignedIn) { Write-Host '  Tip: close the browsers in the target account first.' -ForegroundColor Yellow }
    if ((Read-Host '  Start copy? [Y/N]') -notmatch '^[Yy]') { Write-Host '  Cancelled.'; break }
    Copy-ProfileData $src.Path $dst.Path
    Write-Host ''
    Write-Host '  Copy finished.' -ForegroundColor Green
}

'REMOVE' {
    $ms = @(Get-LocalUser | Where-Object PrincipalSource -eq 'MicrosoftAccount')
    if ($ms.Count -eq 0) { Write-Host ''; Write-Host '  No Microsoft account users on this PC.' -ForegroundColor Green; break }
    $profiles = Get-Profiles
    $admins = Get-AdminSids
    Write-Host ''
    Write-Host '  Microsoft account users:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $pp = $profiles | Where-Object SID -eq $ms[$i].SID.Value
        Write-Host ('   [{0}] {1,-20} {2,-28} {3}' -f ($i + 1), $ms[$i].Name, $pp.Path, $(if ($pp.SignedIn) { 'SIGNED IN' } else { '' }))
    }
    $n = Read-Choice '  Remove user number' $ms.Count
    if ($n -eq 0) { Write-Host '  Cancelled.'; break }
    $user = $ms[$n - 1]
    $sid  = $user.SID.Value
    $prof = $profiles | Where-Object SID -eq $sid

    # Safety checks
    if ($sid -eq $me) { Write-Host '  You are running this tool as that account - sign in with another admin first.' -ForegroundColor Red; break }
    if ($prof.SignedIn) { Write-Host '  That user is signed in. Sign them out or restart the PC, then run this again.' -ForegroundColor Red; break }
    $otherAdmins = @(Get-LocalUser | Where-Object { $_.Enabled -and $_.SID.Value -ne $sid -and $admins -contains $_.SID.Value })
    if ($otherAdmins.Count -eq 0) {
        Write-Host '  This is the only enabled local administrator. Create a local admin first with [2].' -ForegroundColor Red; break
    }
    Write-Host ('  Remaining local admins: ' + (($otherAdmins.Name) -join ', ')) -ForegroundColor Green

    if ($prof -and (Read-Host '  Back up this user''s files before removing? Recommended [Y/N]') -match '^[Yy]') {
        $bk = Join-Path $env:ITROOT ('Backup\' + $user.Name + '_' + (Get-Date -Format yyyyMMdd_HHmmss))
        Write-Host ('  Backing up to ' + $bk)
        Copy-ProfileData $prof.Path $bk
        Write-Host '  Backup done.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host ('  [!] The account "' + $user.Name + '" will be deleted.') -ForegroundColor Red
    $typed = Read-Host ('  Type the user name ' + $user.Name + ' to confirm')
    if ($typed -cne $user.Name) { Write-Host '  Name did not match - nothing removed.' -ForegroundColor Yellow; break }

    Remove-LocalUser -SID $sid
    Write-Host ('  Account ' + $user.Name + ' removed.') -ForegroundColor Green

    if ($prof) {
        $ans = Read-Host ('  Also delete the profile folder ' + $prof.Path + ' and free its space? [Y/N]')
        if ($ans -match '^[Yy]') {
            Get-CimInstance Win32_UserProfile -Filter ("SID='" + $sid + "'") | Remove-CimInstance
            Write-Host '  Profile folder deleted.' -ForegroundColor Green
        } else {
            Write-Host ('  Profile folder kept: ' + $prof.Path)
        }
    }
}
}
} catch {
    Write-Host ('  Failed: ' + $_.Exception.Message) -ForegroundColor Red
}
exit 0
::PS-ACCOUNTS-END

::PS-SECCHECK-BEGIN
# Read-only compromise triage. Writes a transcript report. Runs elevated.
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_SecurityCheck_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
try { Start-Transcript -Path $report -Force | Out-Null } catch {}
$flags = New-Object System.Collections.ArrayList
# Trusted list - programs the IT team confirmed as safe (one path or name per line)
$trustFile = Join-Path (Split-Path $env:REPORTROOT) 'trusted.txt'
$trusted = @(Get-Content $trustFile -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' })
$trustedHits = New-Object System.Collections.ArrayList
function Flag($t) {
    foreach ($tr in $trusted) { if ($t -like ('*' + $tr + '*')) { [void]$trustedHits.Add($t); Write-Host ('   [trusted] ' + $t) -ForegroundColor DarkGreen; return } }
    [void]$flags.Add($t); Write-Host ('   [!] ' + $t) -ForegroundColor Red
}
# High-confidence infected items - listed at the end with path, PID, launcher and remove commands
$suspects = New-Object System.Collections.ArrayList
function Add-Suspect($kind, $target, $why) {
    if (-not $target) { return }
    $tg = [Environment]::ExpandEnvironmentVariables(([string]$target).Trim().Trim('"'))
    if (-not ($suspects | Where-Object { $_.Target -eq $tg })) { [void]$suspects.Add([pscustomobject]@{ Kind = $kind; Target = $tg; Why = $why }) }
}
function Info($t) { Write-Host ('   ' + $t) }
function Sec($t)  { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
$sigCache = @{}
function Get-Sig($path) {
    if (-not $path) { return 'no path' }
    if ($sigCache.ContainsKey($path)) { return $sigCache[$path] }
    $s = try {
        # Store apps are signed through their package, not the file itself
        if ($path -like "$env:ProgramFiles\WindowsApps\*") { 'Signed: Store app package' }
        else {
            $a = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
            if ($a.Status -eq 'Valid') { 'Signed: ' + $a.SignerCertificate.GetNameInfo('SimpleName', $false) } else { 'UNSIGNED' }
        }
    } catch {
        # Defender blocks reading files it has detected as malware
        if ($_.Exception.Message -match 'virus|unwanted') { 'BLOCKED-BY-ANTIVIRUS' } else { 'unreadable' }
    }
    $sigCache[$path] = $s
    return $s
}
function Get-ExePath($cmd) {
    if (-not $cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c -match '^"([^"]+)"') { return $Matches[1] }
    if ($c -match '^(.+?\.(exe|com|bat|cmd|vbs|js|ps1|dll|scr|hta))(\s|,|$)') { return $Matches[1] }
    return ($c -split '\s')[0]
}
$userPath   = '\\AppData\\|\\Temp\\|\\Users\\Public\\|\\Downloads\\|\\\$Recycle|\\ProgramData\\[^\\]+$'
$badCmd     = '-enc\s|-encodedcommand|frombase64string|downloadstring|downloadfile|invoke-expression|\biex\b|bitsadmin.+/transfer|mshta\s+(http|vbscript|javascript)|regsvr32.+/i:http|rundll32.+javascript|certutil.+-urlcache|-w(indowstyle)?\s+hidden'
function Is-Private($ip) { $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|169\.254\.|0\.0\.0\.0|::1$|::$|fe80:|f[cd])' }

$procs = @{}
Get-CimInstance Win32_Process | ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
# This tool's own process chain - never flag ourselves
$self = @{}
$cur = $PID
while ($cur -and $procs.ContainsKey([int]$cur) -and -not $self.ContainsKey([int]$cur)) { $self[[int]$cur] = $true; $cur = $procs[[int]$cur].ParentProcessId }

Write-Host ''
Write-Host ('  Security check - ' + $env:COMPUTERNAME + ' - ' + (Get-Date)) -ForegroundColor White

# 1 ---------------------------------------------------------------
Sec '1. Programs connected to the INTERNET - PID, program, remote address'
$rows = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { -not (Is-Private $_.RemoteAddress) } | ForEach-Object {
    $p = $procs[[int]$_.OwningProcess]
    [pscustomobject]@{ PID = $_.OwningProcess; Program = $p.Name; Remote = ($_.RemoteAddress + ':' + $_.RemotePort); Port = $_.RemotePort
                       Signature = (Get-Sig $p.ExecutablePath); Path = $p.ExecutablePath }
})
if ($rows) { $rows | Sort-Object Program, Remote | Format-Table PID, Program, Remote, Signature, Path -AutoSize | Out-String -Width 250 | Write-Host }
else { Info 'No internet connections right now.' }
foreach ($r in ($rows | Sort-Object PID -Unique)) {
    if ($r.Signature -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') { Flag ('Unsigned program online: ' + $r.Program + ' PID ' + $r.PID + ' - ' + $r.Path) }
    if ($r.Signature -eq 'BLOCKED-BY-ANTIVIRUS') { Add-Suspect 'File' $r.Path 'Antivirus detected it - and it is connected to the internet' }
}
foreach ($r in ($rows | Where-Object { $_.Port -in 25,465,587,2525 })) { Flag ('Mail-sending connection: ' + $r.Program + ' PID ' + $r.PID + ' to ' + $r.Remote + ' - use option 65') }
foreach ($r in ($rows | Where-Object { $_.Port -in 4444,1337,6666,6667,31337,9001,9050,9150 })) { Flag ('Connection on hacker/Tor port: ' + $r.Program + ' PID ' + $r.PID + ' to ' + $r.Remote) }

# 2 ---------------------------------------------------------------
Sec '2. Programs accepting connections FROM the network'
$lis = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in '0.0.0.0','::' } | Sort-Object OwningProcess -Unique
$cnt = 0
foreach ($l in $lis) {
    $p = $procs[[int]$l.OwningProcess]
    if ($p.ExecutablePath -and (Get-Sig $p.ExecutablePath) -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') { $cnt++; Flag ('Unsigned program listening on port ' + $l.LocalPort + ': ' + $p.Name + ' PID ' + $p.ProcessId + ' - ' + $p.ExecutablePath) }
}
if ($cnt -eq 0) { Info 'OK - no unsigned programs listening.' }

# 3 ---------------------------------------------------------------
Sec '3. Suspicious running processes'
$cnt = 0
$sysNames = @{ 'svchost.exe'='System32'; 'lsass.exe'='System32'; 'csrss.exe'='System32'; 'winlogon.exe'='System32'; 'services.exe'='System32'; 'smss.exe'='System32'; 'spoolsv.exe'='System32'; 'explorer.exe'='Windows' }
foreach ($p in $procs.Values) {
    if ($self.ContainsKey([int]$p.ProcessId)) { continue }
    $path = $p.ExecutablePath
    if ($p.CommandLine -and $p.CommandLine -match $badCmd) { $cnt++; Flag ('Suspicious command line: ' + $p.Name + ' PID ' + $p.ProcessId + ' - ' + $p.CommandLine.Substring(0, [Math]::Min(180, $p.CommandLine.Length))) }
    if ($path -and $sysNames.ContainsKey($p.Name.ToLower())) {
        $okDir = if ($sysNames[$p.Name.ToLower()] -eq 'Windows') { $env:SystemRoot } else { Join-Path $env:SystemRoot 'System32' }
        if ((Split-Path $path) -ne $okDir -and $path -notlike "$env:SystemRoot\SysWOW64\*") { $cnt++; Flag ('FAKE system process: ' + $p.Name + ' PID ' + $p.ProcessId + ' running from ' + $path); Add-Suspect 'File' $path 'Fake Windows system process' }
    }
}
# One line per program file, with all its PIDs
$procs.Values | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -match $userPath -and -not $self.ContainsKey([int]$_.ProcessId) } |
    Group-Object ExecutablePath | ForEach-Object {
        if ((Get-Sig $_.Name) -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') {
            $cnt++
            $ids = ($_.Group.ProcessId | Sort-Object) -join ', '
            Flag ('Unsigned program running from user folder: ' + $_.Group[0].Name + ' - PID ' + $ids + ' - ' + $_.Name)
        }
    }
if ($cnt -eq 0) { Info 'OK - nothing suspicious running.' }

# 4 ---------------------------------------------------------------
Sec '4. Programs that start automatically - persistence'
$u = 'Registry::HKEY_USERS\' + $env:TSID
$runKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', "$u\Software\Microsoft\Windows\CurrentVersion\Run",
             "$u\Software\Microsoft\Windows\CurrentVersion\RunOnce")
$auto = @()
foreach ($k in $runKeys) {
    $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($props) { foreach ($pr in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
        $exe = Get-ExePath ([string]$pr.Value)
        $auto += [pscustomobject]@{ Source = ($k -replace '^.*\\(Run|RunOnce)$', 'Registry $1') + $(if ($k -like '*HKEY_USERS*') { ' - user' } else { ' - machine' }); Name = $pr.Name; Command = [string]$pr.Value; Exe = $exe }
    } }
}
foreach ($sf in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp", "$env:TROAMING\Microsoft\Windows\Start Menu\Programs\Startup")) {
    Get-ChildItem -LiteralPath $sf -File -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object {
        $auto += [pscustomobject]@{ Source = 'Startup folder'; Name = $_.Name; Command = $_.FullName; Exe = $_.FullName }
        if ($_.Extension -match '^\.(vbs|vbe|js|jse|ps1|bat|cmd|hta|wsf|scr)$') { Flag ('Script in Startup folder: ' + $_.FullName); Add-Suspect 'File' $_.FullName 'Script that runs at every sign-in' }
    }
}
$auto | Format-Table Source, Name, Command -AutoSize -Wrap | Out-String -Width 250 | Write-Host
foreach ($a in $auto) {
    if ($a.Source -ne 'Startup folder' -and $a.Exe -and $a.Exe -match '\\Users\\Public\\|\\Temp\\|\\\$Recycle') { Flag ('Auto-start from Public/Temp folder - typical for malware: ' + $a.Name + ' - ' + $a.Command); if (Test-Path -LiteralPath $a.Exe -ErrorAction SilentlyContinue) { Add-Suspect 'File' $a.Exe 'Starts automatically from a Public/Temp folder' } }
    elseif ($a.Source -ne 'Startup folder' -and $a.Exe -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $a.Exe -ErrorAction SilentlyContinue)) { Info ('Leftover auto-start - file missing, safe to delete: ' + $a.Name + ' - ' + $a.Exe) }
    if ($a.Command -match $badCmd) { Flag ('Suspicious auto-start command: ' + $a.Name + ' - ' + $a.Command) }
    elseif ($a.Exe -and (Test-Path -LiteralPath $a.Exe -ErrorAction SilentlyContinue) -and $a.Exe -match '\.exe$' -and (Get-Sig $a.Exe) -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') { Flag ('Unsigned auto-start program: ' + $a.Name + ' - ' + $a.Exe) }
}

Info 'Scheduled tasks - checking...'
$tcnt = 0
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object State -ne 'Disabled')) {
    foreach ($ac in $t.Actions) {
        if (-not $ac.Execute) { continue }
        $line = ($ac.Execute + ' ' + $ac.Arguments).Trim()
        $exe = [Environment]::ExpandEnvironmentVariables($ac.Execute.Trim('"'))
        $bad = $false
        if ($line -match $badCmd -or $line -match 'GetEnvironmentVariable|InvokeScript|\[Array\]::Reverse|FromBase64') { $bad = $true; $why = 'suspicious command' }
        if (-not $t.Author -and $t.TaskPath -like '\Microsoft\*' -and $ac.Execute -match '(powershell|pwsh|wscript|cscript|mshta|cmd)(\.exe)?$') {
            # Real Windows tasks may run a Microsoft-signed script from System32 - only flag when that is not the case
            $script = $null
            if ($ac.Arguments -match '(%systemroot%|%windir%|[A-Z]:\\Windows)\\system32\\[^\s"]+\.(cmd|bat|ps1|vbs|js)') { $script = [Environment]::ExpandEnvironmentVariables($Matches[0]) }
            $msScript = $script -and (Test-Path -LiteralPath $script) -and (Get-Sig $script) -like 'Signed: Microsoft*'
            if (-not $msScript) { $bad = $true; $why = 'FAKE Microsoft task running a script host' }
        }
        elseif ($exe -match $userPath -or $line -match '\\AppData\\|\\Users\\Public\\|\\Temp\\') {
            if (-not (Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue) -or (Get-Sig $exe) -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS' -or $exe -match '(powershell|wscript|cscript|mshta|cmd)\.exe$') { $bad = $true; $why = 'runs from user folder' }
        }
        if ($bad) {
            $tcnt++; Flag ('Scheduled task ' + $t.TaskPath + $t.TaskName + ' - ' + $why + ': ' + $line.Substring(0, [Math]::Min(200, $line.Length)))
            if ($why -ne 'runs from user folder' -or (Get-Sig $exe) -eq 'BLOCKED-BY-ANTIVIRUS') { Add-Suspect 'Task' ($t.TaskPath + $t.TaskName) $why }
        }
    }
}
if ($tcnt -eq 0) { Info 'OK - no suspicious scheduled tasks.' }

# Non-Microsoft tasks that run an unsigned or antivirus-blocked program from anywhere
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' })) {
    foreach ($ac in $t.Actions) {
        if (-not $ac.Execute) { continue }
        $exe = [Environment]::ExpandEnvironmentVariables($ac.Execute.Trim('"'))
        if ($exe -match $userPath) { continue }
        if ((Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue)) {
            $sg = Get-Sig $exe
            if ($sg -eq 'BLOCKED-BY-ANTIVIRUS') { Flag ('MALWARE scheduled task - antivirus blocks its program: ' + $t.TaskPath + $t.TaskName + ' - ' + $exe); Add-Suspect 'File' $exe 'Antivirus detected it - started by a scheduled task' }
            elseif ($sg -eq 'UNSIGNED') { Flag ('Scheduled task runs unsigned program: ' + $t.TaskPath + $t.TaskName + ' - ' + $exe) }
        }
    }
}

Info 'DLL side-loading - fake Windows DLLs inside program folders - checking...'
$sysDll = 'winhttp|version|wininet|userenv|cryptbase|winmm|msimg32|iphlpapi|dwmapi|uxtheme|wtsapi32|secur32|netapi32|profapi|dbgcore|wldp|ieapi|sspicli|mswsock|amsi|dpapi|propsys|oleacc'
$dcnt = 0
foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ }) {
    Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -File -Filter '*.dll' -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match "^($sysDll)$" -and $_.FullName -notmatch '\\(WindowsApps|Windows Defender|Microsoft Office|Windows NT|Common Files\\microsoft shared)\\' } |
        ForEach-Object {
            $sg = Get-Sig $_.FullName
            if ($sg -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') { $dcnt++; Flag ('Fake Windows DLL in program folder - DLL side-loading, typical for cracks/malware: ' + $_.FullName + ' [' + $sg + ', ' + $_.CreationTime.ToString('yyyy-MM-dd') + ']'); Add-Suspect 'File' $_.FullName 'Fake Windows DLL - loaded by the program in the same folder' }
        }
}
if ($dcnt -eq 0) { Info 'OK - no fake Windows DLLs found.' }

Info 'Services - checking...'
$scnt = 0
foreach ($s in (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
    $exe = Get-ExePath $s.PathName
    if (-not $exe) { continue }
    if ($exe -match $userPath) { $scnt++; Flag ('Service runs from user folder: ' + $s.Name + ' - ' + $s.PathName) }
    elseif ($s.PathName -match $badCmd) { $scnt++; Flag ('Service with suspicious command: ' + $s.Name + ' - ' + $s.PathName) }
    elseif ((Test-Path -LiteralPath $exe -ErrorAction SilentlyContinue) -and (Get-Sig $exe) -in 'UNSIGNED','BLOCKED-BY-ANTIVIRUS') { $scnt++; Flag ('Unsigned service: ' + $s.Name + ' - ' + $exe) }
}
if ($scnt -eq 0) { Info 'OK - no suspicious services.' }

$wmi = @(Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue) +
       @(Get-CimInstance -Namespace root\subscription -ClassName ActiveScriptEventConsumer -ErrorAction SilentlyContinue)
foreach ($w in ($wmi | Where-Object { $_ })) { Flag ('WMI persistence - hidden auto-run: ' + $w.Name + ' - ' + $w.CommandLineTemplate + $w.ScriptText); Add-Suspect 'WMI' $w.Name 'Hidden WMI auto-run' }
if (-not ($wmi | Where-Object { $_ })) { Info 'OK - no WMI persistence.' }

# 5 ---------------------------------------------------------------
Sec '5. Antivirus'
$avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
if ($avs) { Info ('Installed antivirus: ' + (($avs.displayName | Sort-Object -Unique) -join ', ')) }
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) {
    Info ('Defender mode: ' + $mp.AMRunningMode + '   Real-time: ' + $mp.RealTimeProtectionEnabled + '   Definitions age: ' + $mp.AntivirusSignatureAge + ' day(s)   Tamper protection: ' + $mp.IsTamperProtected)
    if ($mp.AMRunningMode -eq 'Normal' -and -not $mp.RealTimeProtectionEnabled) { Flag 'Defender real-time protection is OFF' }
    if ($mp.AMRunningMode -eq 'Normal' -and $mp.AntivirusSignatureAge -gt 3) { Flag ('Defender definitions are ' + $mp.AntivirusSignatureAge + ' days old - update with [U]') }
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    $ex = @($pref.ExclusionPath) + @($pref.ExclusionProcess) + @($pref.ExclusionExtension) | Where-Object { $_ -and $_ -notmatch '^N/A' }
    $highRisk = 'RegAsm|InstallUtil|MSBuild|AppLaunch|vbc\.exe|aspnet_compiler|iexplore|Internet Explorer|powershell|cmd\.exe|rundll32|regsvr32|mshta|wscript|svchost|\\Windows\\?$|\\System32|\\SysWOW64|\\AppData|\\Temp|\\Users\\Public|^[A-Z]:\\?$|AAct|KMS|Spp|crack|activat'
    foreach ($e in $ex) {
        if ($e -match $highRisk) { Flag ('HIGH-RISK Defender exclusion - used by malware/cracks to hide, remove it: ' + $e) }
        else { Flag ('Defender exclusion - confirm it is yours: ' + $e) }
    }
    $det = Get-MpThreatDetection -ErrorAction SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10
    if ($det) {
        $names = @{}; $active = @{}
        Get-MpThreat -ErrorAction SilentlyContinue | ForEach-Object { $names[$_.ThreatID] = $_.ThreatName; $active[$_.ThreatID] = $_.IsActive }
        Info 'Recent threats found by Defender:'
        foreach ($d in ($det | Sort-Object ThreatID -Unique)) {
            $what = $names[$d.ThreatID] + ' on ' + $d.InitialDetectionTime + ' - ' + (($d.Resources | Select-Object -First 1) -replace '^file:_', '')
            if ($active[$d.ThreatID]) {
                Flag ('ACTIVE threat - not removed yet, run [F] full scan: ' + $what)
                foreach ($res in $d.Resources) { if ($res -match '^file:_(.+)$') { Add-Suspect 'File' $Matches[1] ('Defender: ' + $names[$d.ThreatID]) } }
            }
            elseif ($d.InitialDetectionTime -gt (Get-Date).AddDays(-7)) { Flag ('Malware found + removed by Defender in last 7 days - run [F] full scan, it may have left other files: ' + $what) }
            else { Info ('Removed by Defender: ' + $what) }
        }
    } else { Info 'No threats recorded by Defender.' }
} else { Info 'Defender status not available - another antivirus may be in control.' }

# 6 ---------------------------------------------------------------
Sec '6. Network settings attackers change - hosts file, proxy, DNS'
$hosts = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*[^#\s]' } |
         ForEach-Object { ($_ -replace '#.*$', '' -replace '\s+', ' ').Trim() } | Where-Object { $_ } | Sort-Object -Unique
if ($hosts) {
    Info ('Hosts file has ' + @($hosts).Count + ' entries:')
    $hosts | ForEach-Object { Info ('  ' + $_) }
    $own = 'activatorcounter\.com'   # blocks added by IT Tools
    $sec = @($hosts | Where-Object { $_ -match '(windowsupdate|update\.microsoft|defender|smartscreen|wdcp|malwarebytes|mwbsys|kaspersky|eset|avast|avg\.com|norton|mcafee|bitdefender|sophos|virustotal)' })
    foreach ($h in $sec) { Flag ('Hosts file blocks Windows Update / antivirus - malware does this: ' + $h) }
    $lic = @($hosts | Where-Object { $_ -notmatch $own -and $_ -match '(licen|genuine|activat|crack|keygen|serial|adobe|autodesk|corel|sublime|jetbrains|mobiledit|devolutions|sqlbak|recoverlostpassword|wondershare|idm|internetdownloadmanager)' })
    foreach ($h in $lic) { Flag ('Hosts file blocks a licence check - cracked software on this PC: ' + $h) }
    $redir = @($hosts | Where-Object { $_ -notmatch '^(0\.0\.0\.0|127\.0\.0\.1|::1)\s' })
    foreach ($h in $redir) { Flag ('Hosts file REDIRECTS a site to another server - check it: ' + $h) }
    if (-not ($sec + $lic + $redir)) { Info 'OK - only local dev sites and ad/telemetry blocks.' }
} else { Info 'OK - hosts file has no entries.' }
$ie = Get-ItemProperty ($u + '\Software\Microsoft\Windows\CurrentVersion\Internet Settings') -ErrorAction SilentlyContinue
if ($ie.ProxyEnable -eq 1) { Flag ('User proxy is ON: ' + $ie.ProxyServer + ' - confirm it is the company proxy') }
if ($ie.AutoConfigURL) { Flag ('Proxy script set: ' + $ie.AutoConfigURL + ' - confirm it is the company proxy') }
$wh = (netsh winhttp show proxy) -join ' '
if ($wh -notmatch 'Direct access') { Info ('System proxy: ' + (($wh -replace '\s+', ' ').Trim())) }
$dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses }
foreach ($d in $dns) { Info ('DNS on ' + $d.InterfaceAlias + ': ' + ($d.ServerAddresses -join ', ')) }

# 7 ---------------------------------------------------------------
Sec '7. Accounts and sign-in events'
try { $adm = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name } } catch { $adm = net localgroup (Get-LocalGroup -SID 'S-1-5-32-544').Name | Select-Object -Skip 6 | Where-Object { $_ -and $_ -notmatch 'command completed' } }
Info ('Local administrators: ' + ($adm -join ', '))
$since = (Get-Date).AddDays(-7)
function Count-Ev($log, $ids, $from) { @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = $ids; StartTime = $from } -ErrorAction SilentlyContinue) }
$e = Count-Ev 'Security' 4720 $since;       if ($e.Count) { Flag ($e.Count.ToString() + ' new user account(s) created in last 7 days') }
$e = Count-Ev 'Security' 4732 $since
foreach ($x in $e) { if ($x.Properties[2].Value -eq 'S-1-5-32-544') { Flag ('User added to Administrators on ' + $x.TimeCreated + ': ' + $x.Properties[0].Value + $x.Properties[1].Value) } }
$e = Count-Ev 'System' 7045 $since;         foreach ($x in $e) { Info ('New service installed ' + $x.TimeCreated + ': ' + $x.Properties[0].Value + ' - ' + $x.Properties[1].Value) }
$e = Count-Ev 'Security' 1102 $since;       if ($e.Count) { Flag 'Security log was CLEARED in last 7 days - attackers do this to hide' }
$e = Count-Ev 'System' 104 $since;          if ($e.Count) { Flag 'System log was CLEARED in last 7 days' }
$e = Count-Ev 'Security' 4625 (Get-Date).AddDays(-1)
if ($e.Count -gt 0) {
    $top = $e | ForEach-Object { $_.Properties[19].Value } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5
    $msg = $e.Count.ToString() + ' failed sign-ins in last 24h. From: ' + (($top | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', ')
    if ($e.Count -gt 20) { Flag ($msg + ' - possible password guessing') } else { Info $msg }
}

# 8 ---------------------------------------------------------------
Sec '8. Remote access'
$ra = 'anydesk|teamviewer|rustdesk|ultraviewer|screenconnect|connectwise|splashtop|logmein|atera|ngrok|radmin|tvnserver|winvnc|vncserver|remoting_host|ammyy|supremo|zohoassist|meshagent|dwservice|getscreen|aeroadmin|remotepc|parsec|remotewebcontrol|nomachine|nxservice|litemanager|todesk|sunlogin|awesun'
$found = $procs.Values | Where-Object { $_.Name -match $ra } | Sort-Object Name -Unique
foreach ($f in $found) { Flag ('Remote access tool running: ' + $f.Name + ' PID ' + $f.ProcessId + ' - confirm it is approved by IT') }
if (-not $found) { Info 'OK - no remote access tools running.' }
$tools = @($found | ForEach-Object { $_.Name.ToLower() -replace '(_?service\d*|_desktop|server|_tray)?\.exe$', '' } | Sort-Object -Unique)
if ($tools.Count -ge 3) { Flag ($tools.Count.ToString() + ' different remote access tools running - keep ONE approved tool, uninstall the rest') }
$ie = $procs.Values | Where-Object { $_.Name -eq 'iexplore.exe' }
foreach ($i in $ie) { Flag ('Internet Explorer is running hidden in the background - PID ' + $i.ProcessId + ' - IE is retired; check which program uses it') }
# Who is connected now / recently + unattended access - shared with option 67
if ([IO.File]::ReadAllText($env:ITSELF) -match '(?ms)^::PS-REMOTECHECK-BEGIN\r?\n(.*?)^::PS-REMOTECHECK-END') { . ([ScriptBlock]::Create($Matches[1])) }
foreach ($fw in (Get-NetFirewallProfile -ErrorAction SilentlyContinue)) { if (-not $fw.Enabled) { Flag ('Windows Firewall is OFF for ' + $fw.Name + ' network') } }

# 9 ---------------------------------------------------------------
Sec '9. INFECTED / MALWARE ITEMS - where they are, what runs them, how to remove'
if ($suspects.Count -eq 0) {
    Write-Host '   None - no confirmed malware files, tasks or hidden auto-runs found.' -ForegroundColor Green
} else {
    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    $allSvc   = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
    $runKeys2 = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', "$u\Software\Microsoft\Windows\CurrentVersion\Run",
                  "$u\Software\Microsoft\Windows\CurrentVersion\RunOnce")
    $n = 0
    foreach ($s in $suspects) {
        $n++
        Write-Host ''
        Write-Host ('  [' + $n + '] ' + $s.Target) -ForegroundColor Red
        Write-Host ('      Why: ' + $s.Why) -ForegroundColor Yellow

        if ($s.Kind -eq 'Task') {
            $tk = $allTasks | Where-Object { ($_.TaskPath + $_.TaskName) -eq $s.Target } | Select-Object -First 1
            if ($tk) {
                foreach ($ac in $tk.Actions) { Write-Host ('      Runs:  ' + $ac.Execute + ' ' + $ac.Arguments) }
                Write-Host ('      Task state: ' + $tk.State)
            }
            Write-Host '      REMOVE:' -ForegroundColor Cyan
            Write-Host ('        schtasks /end /tn "' + $s.Target + '"')
            Write-Host ('        schtasks /delete /tn "' + $s.Target + '" /f')
            continue
        }
        if ($s.Kind -eq 'WMI') {
            Write-Host '      REMOVE in PowerShell as admin:' -ForegroundColor Cyan
            Write-Host ("        Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer | Where-Object Name -eq '" + $s.Target + "' | Remove-CimInstance")
            continue
        }

        # File: running processes, launchers, remove commands
        $file = $s.Target
        $leaf = Split-Path $file -Leaf
        $dir  = Split-Path $file
        $exists = Test-Path -LiteralPath $file
        Write-Host ('      File exists: ' + $(if ($exists) { 'YES' } else { 'no - already removed or quarantined' }))
        $isDll = $leaf -match '\.dll$'
        $running = @($procs.Values | Where-Object {
            ($_.ExecutablePath -and $_.ExecutablePath -eq $file) -or
            ($isDll -and $_.ExecutablePath -and (Split-Path $_.ExecutablePath) -eq $dir) -or
            ($_.CommandLine -and $_.CommandLine -like ('*' + $leaf + '*') -and -not $self.ContainsKey([int]$_.ProcessId)) })
        foreach ($r in $running) { Write-Host ('      RUNNING: ' + $r.Name + ' PID ' + $r.ProcessId + $(if ($isDll) { ' - loads this DLL' } else { '' })) -ForegroundColor Red }
        if (-not $running) { Write-Host '      Running now: no' }

        $cmds = New-Object System.Collections.ArrayList
        foreach ($r in $running) { [void]$cmds.Add('taskkill /f /pid ' + $r.ProcessId) }
        foreach ($tk in $allTasks) {
            foreach ($ac in $tk.Actions) {
                if (($ac.Execute + ' ' + $ac.Arguments) -like ('*' + $leaf + '*')) {
                    Write-Host ('      Started by scheduled task: ' + $tk.TaskPath + $tk.TaskName)
                    [void]$cmds.Add('schtasks /delete /tn "' + $tk.TaskPath + $tk.TaskName + '" /f')
                }
            }
        }
        foreach ($sv in ($allSvc | Where-Object { $_.PathName -like ('*' + $leaf + '*') })) {
            Write-Host ('      Started by service: ' + $sv.Name + ' - ' + $sv.DisplayName + ' - ' + $sv.State)
            [void]$cmds.Add('sc stop "' + $sv.Name + '"'); [void]$cmds.Add('sc delete "' + $sv.Name + '"')
        }
        foreach ($k in $runKeys2) {
            $props = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
            if ($props) { foreach ($pr in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and [string]$_.Value -like ('*' + $leaf + '*') }) {
                $regPath = ($k -replace '^Registry::', '' -replace '^HKLM:', 'HKLM' -replace '^HKEY_USERS', 'HKU')
                Write-Host ('      Started by registry Run: ' + $regPath + ' - ' + $pr.Name)
                [void]$cmds.Add('reg delete "' + $regPath + '" /v "' + $pr.Name + '" /f')
            } }
        }
        if ($isDll) { Write-Host '      Loaded by: the program in the same folder - remove or reinstall that program.' }
        if ($exists) {
            [void]$cmds.Add('del /f /q "' + $file + '"')
            Write-Host ('      Open folder: explorer /select,"' + $file + '"')
        }
        Write-Host '      REMOVE - run these in an admin Command Prompt, in this order:' -ForegroundColor Cyan
        foreach ($c in $cmds) { Write-Host ('        ' + $c) }
    }
    Write-Host ''
    Write-Host '  Easier: option 66 [4] removes a file AND everything that starts it, then has Defender scan it.' -ForegroundColor Green
}

# Summary ---------------------------------------------------------
Write-Host ''
Write-Host '  ===================================================================' -ForegroundColor White
if ($suspects.Count -gt 0) {
    Write-Host ('  MALWARE: ' + $suspects.Count + ' infected item(s) found - see section 9 for path, PID and how to remove.') -ForegroundColor Red
} else {
    Write-Host '  MALWARE: none found.' -ForegroundColor Green
}
if ($trustedHits.Count -gt 0) { Write-Host ('  TRUSTED: ' + $trustedHits.Count + ' item(s) skipped - on your trusted list ' + $trustFile) -ForegroundColor DarkGreen }
if ($flags.Count -eq 0) {
    Write-Host '  RESULT: no signs of compromise found.' -ForegroundColor Green
} else {
    Write-Host ('  REVIEW: ' + $flags.Count + ' item(s) to check - most are normal programs, confirm each one:') -ForegroundColor Yellow
    $flags | ForEach-Object { Write-Host ('   - ' + $_) -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  Not every item is malware - check each one. To stop a bad program use option 66 with its PID.'
    Write-Host '  Confirmed infection: disconnect the network, change the user passwords from ANOTHER device, run [O] offline scan.'
}
try { Stop-Transcript | Out-Null } catch {}
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-SECCHECK-END

::PS-REMOTECHECK-BEGIN
# Who is connected to this PC remotely - now, last 30 days, and always-on access. Read-only.
# Option 67 runs it alone. Option 64 dot-sources it and shares Flag / Info / Sec / $procs.
$rcAlone = -not (Get-Command Flag -ErrorAction SilentlyContinue)
if ($rcAlone) {
    $report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_RemoteCheck_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
    try { Start-Transcript -Path $report -Force | Out-Null } catch {}
    $flags = New-Object System.Collections.ArrayList
    function Flag($t) { [void]$flags.Add($t); Write-Host ('   [!] ' + $t) -ForegroundColor Red }
    function Info($t) { Write-Host ('   ' + $t) }
    function Sec($t)  { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
    function Is-Private($ip) { $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|169\.254\.|0\.0\.0\.0|::1$|::$|fe80:|f[cd])' }
    $procs = @{}
    Get-CimInstance Win32_Process | ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
    Write-Host ''
    Write-Host ('  Remote connection check - ' + $env:COMPUTERNAME + ' - ' + (Get-Date)) -ForegroundColor White
}
$rcLive = 0
$since30 = (Get-Date).AddDays(-30)
function Read-AnyText($f) {
    # Some remote tools write UTF-16 logs without a BOM
    $b = [IO.File]::ReadAllBytes($f)
    if ($b.Length -gt 1 -and ($b[1] -eq 0 -or ($b[0] -eq 0xFF -and $b[1] -eq 0xFE))) { [Text.Encoding]::Unicode.GetString($b).TrimStart([char]0xFEFF) } else { [Text.Encoding]::UTF8.GetString($b) }
}
function Who-Proc($procId) { $p = $procs[[int]$procId]; if ($p) { $p.Name + ' PID ' + $procId } else { 'PID ' + $procId } }

# A ---------------------------------------------------------------
Sec 'Remote sessions ACTIVE RIGHT NOW'
# Remote Desktop sessions (session names are not translated)
$qs = @(query session 2>$null)
foreach ($l in $qs) {
    if ($l -match '^\s*>?(rdp-tcp#\d+)\s+(\S+)\s+(\d+)\s+(\S+)') { $rcLive++; Flag ('Remote Desktop session ACTIVE: user ' + $Matches[2] + ' - session ' + $Matches[3] + ' ' + $Matches[4]) }
}
# Someone connected IN to a port this PC listens on
$lisPorts = @{}
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -notmatch '^(127\.|::1$)' } | ForEach-Object { $lisPorts[[int]$_.LocalPort] = $true }
$inb = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $lisPorts.ContainsKey([int]$_.LocalPort) -and $_.RemoteAddress -notmatch '^(127\.|::1$|::ffff:127\.)' -and $_.LocalPort -lt 49152 })
$remotePorts = 3389, 5900, 5901, 5800, 5938, 7070, 21118, 21119, 4899, 5650, 22, 5985, 5986
foreach ($c in $inb) {
    $who = Who-Proc $c.OwningProcess
    $from = $c.RemoteAddress + ':' + $c.RemotePort
    if (-not (Is-Private $c.RemoteAddress)) { $rcLive++; Flag ('INTERNET address connected IN to this PC: ' + $from + ' -> port ' + $c.LocalPort + ' - ' + $who) }
    elseif ($c.LocalPort -in $remotePorts) { $rcLive++; Flag ('Network device connected IN for remote control: ' + $from + ' -> port ' + $c.LocalPort + ' - ' + $who) }
    else { Info ('Local network connection in: ' + $from + ' -> port ' + $c.LocalPort + ' - ' + $who) }
}
# Processes that only run while a remote session is open
$live = @(
    @{ N = '^TeamViewer_Desktop\.exe$'; C = '';            T = 'TeamViewer session open - someone is viewing or controlling this PC' },
    @{ N = '^rustdesk\.exe$';           C = '--cm';        T = 'RustDesk incoming session open - connection manager is running' },
    @{ N = '^ScreenConnect\.WindowsClient\.exe$'; C = '';  T = 'ScreenConnect / ConnectWise session open' },
    @{ N = '^msra\.exe$';               C = '';            T = 'Windows Remote Assistance is open' },
    @{ N = '^QuickAssist\.exe$';        C = '';            T = 'Quick Assist is open - a helper may be connected' },
    @{ N = '^wsmprovhost\.exe$';        C = '';            T = 'PowerShell Remoting session open - someone runs commands on this PC' },
    @{ N = '^rdpclip\.exe$';            C = '';            T = 'Remote Desktop clipboard running - an RDP session exists' }
)
foreach ($lv in $live) {
    foreach ($p in ($procs.Values | Where-Object { $_.Name -match $lv.N -and (-not $lv.C -or ($_.CommandLine -and $_.CommandLine -like ('*' + $lv.C + '*'))) })) {
        $rcLive++; Flag ($lv.T + ' - ' + $p.Name + ' PID ' + $p.ProcessId)
    }
}
# Reverse tunnels let someone outside reach this PC through the firewall
foreach ($p in ($procs.Values | Where-Object { $_.Name -match '^(ngrok|cloudflared|frpc|chisel|plink|ligolo|revsocks|bore|localtonet|zrok|tailscaled|zerotier)' -or ($_.Name -eq 'ssh.exe' -and $_.CommandLine -match '\s-R\s') })) {
    Flag ('Tunnel program running - can open this PC to the internet: ' + $p.Name + ' PID ' + $p.ProcessId + ' - ' + $p.ExecutablePath)
}
if ($rcLive -eq 0) { Write-Host '   OK - nobody is connected to this PC right now.' -ForegroundColor Green }
Info 'Remote tools keep one idle connection to their own server - that alone is NOT a session.'

# B ---------------------------------------------------------------
Sec 'Incoming remote connections - last 30 days'
$hist = New-Object System.Collections.ArrayList
function Add-Hist($tool, $when, $from, $extra) { [void]$hist.Add([pscustomobject]@{ Time = $when; Tool = $tool; From = $from; Detail = $extra }) }
# Remote Desktop - successful sign-ins (1149 works even when Security auditing is off)
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; Id = 1149; StartTime = $since30 } -ErrorAction SilentlyContinue | ForEach-Object {
    Add-Hist 'Remote Desktop' $_.TimeCreated $_.Properties[2].Value ('user ' + $_.Properties[1].Value + '\' + $_.Properties[0].Value)
}
# Windows sign-ins over the network: type 10 = RDP, type 3 from internet = exposed share / service
$xp = "*[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) <= 2592000000]] and EventData[Data[@Name='LogonType']='10' or Data[@Name='LogonType']='3']]"
try {
    Get-WinEvent -LogName Security -FilterXPath $xp -MaxEvents 4000 -ErrorAction Stop | ForEach-Object {
        $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        $ip = [string]$d['IpAddress']
        if ($d['LogonType'] -eq '10') { Add-Hist 'Windows RDP sign-in' $_.TimeCreated $ip ('user ' + $d['TargetDomainName'] + '\' + $d['TargetUserName']) }
        elseif ($ip -and $ip -ne '-' -and -not (Is-Private $ip)) { Add-Hist 'Network sign-in FROM INTERNET' $_.TimeCreated $ip ('user ' + $d['TargetDomainName'] + '\' + $d['TargetUserName']) }
    }
} catch { if ($_.Exception.Message -notmatch 'No events were found') { Info 'Security log not readable - run as Administrator for Windows sign-in history.' } }
# AnyDesk - connection_trace.txt (service + user copy)
foreach ($f in @("$env:ProgramData\AnyDesk\connection_trace.txt", "$env:TROAMING\AnyDesk\connection_trace.txt") | Where-Object { Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue }) {
    foreach ($l in ((Read-AnyText $f) -split "`r?`n")) {
        if ($l -match '^\s*Incoming\s+(\d{4}-\d{2}-\d{2}),\s*(\d{1,2}:\d{2})\s+(\S+)\s+(\d+)') {
            $t = [datetime]::ParseExact($Matches[1] + ' ' + $Matches[2], 'yyyy-MM-dd H:mm', $null)
            if ($t -gt $since30) { Add-Hist 'AnyDesk' $t ('AnyDesk ID ' + $Matches[4]) ('accepted by: ' + $Matches[3]) }
        }
    }
}
# TeamViewer - Connections_incoming.txt: ID, name, start, end, user, type
foreach ($f in @("$env:ProgramFiles\TeamViewer\Connections_incoming.txt", "${env:ProgramFiles(x86)}\TeamViewer\Connections_incoming.txt") | Where-Object { $_ -and (Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue) }) {
    foreach ($l in ((Read-AnyText $f) -split "`r?`n" | Where-Object { $_.Trim() })) {
        $c = $l -split "`t"
        $t = $null; try { $t = [datetime]::ParseExact($c[2].Trim(), 'dd-MM-yyyy HH:mm:ss', $null) } catch {}
        if (-not $t -or $t -gt $since30) { Add-Hist 'TeamViewer' $t ('TeamViewer ID ' + $c[0] + ' ' + $c[1]) ('until ' + $c[3] + ' - ' + $c[5]) }
    }
}
# UltraViewer - ConnectionLog.log: dd/MM/yy HH:mm:ss|in|seconds|ID
$uv = "${env:ProgramFiles(x86)}\UltraViewer\ConnectionLog.log"
if (Test-Path -LiteralPath $uv -ErrorAction SilentlyContinue) {
    foreach ($l in (Get-Content -LiteralPath $uv -ErrorAction SilentlyContinue)) {
        $c = $l -split '\|'
        if ($c.Count -ge 4 -and $c[1] -eq 'in') {
            $t = $null; try { $t = [datetime]::ParseExact($c[0].Trim(), 'dd/MM/yy HH:mm:ss', $null) } catch {}
            if (-not $t -or $t -gt $since30) { Add-Hist 'UltraViewer' $t ('UltraViewer ID ' + $c[3]) ('lasted ' + $c[2] + ' s') }
        }
    }
}
# RustDesk - service and user logs: "Connection opened from <ip>"
$rdLogs = @("$env:SystemRoot\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log", "$env:TROAMING\RustDesk\log")
foreach ($lf in (Get-ChildItem -LiteralPath $rdLogs -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object LastWriteTime -gt $since30)) {
    foreach ($m in (Select-String -LiteralPath $lf.FullName -Pattern 'Connection opened from\s+(\S+)' -ErrorAction SilentlyContinue)) {
        $t = $null; if ($m.Line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $t = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) }
        if (-not $t -or $t -gt $since30) { Add-Hist 'RustDesk' $t ($m.Matches[0].Groups[1].Value.TrimEnd('.')) '' }
    }
}
if ($hist.Count -eq 0) { Write-Host '   OK - no incoming remote connections recorded in the last 30 days.' -ForegroundColor Green }
else {
    $hist | Sort-Object Time -Descending | Select-Object -First 40 | Format-Table Time, Tool, From, Detail -AutoSize | Out-String -Width 250 | Write-Host
    foreach ($g in ($hist | Group-Object Tool)) {
        $last = ($g.Group | Sort-Object Time -Descending | Select-Object -First 1)
        Flag ($g.Name + ': ' + $g.Count + ' incoming connection(s) in 30 days, last ' + $last.Time + ' from ' + $last.From + ' - confirm each one was IT / you')
    }
    $recent = @($hist | Where-Object { $_.Time -and $_.Time -gt (Get-Date).AddHours(-3) })
    foreach ($r in $recent) { Flag ('Started in the last 3 hours - may still be connected: ' + $r.Tool + ' from ' + $r.From + ' at ' + $r.Time) }
}

# C ---------------------------------------------------------------
Sec 'Ways someone can connect in WITHOUT the user accepting'
$raRx = 'anydesk|teamviewer|rustdesk|ultraviewer|screenconnect|connectwise|splashtop|logmein|atera|radmin|tvnserver|winvnc|vncserver|uvnc|remoting_host|chrome remote|ammyy|supremo|zoho|meshagent|dwservice|getscreen|aeroadmin|remotepc|parsec|nomachine|nxservice|litemanager|todesk|sunlogin|awesun|kaseya|ninja|n-able|gotoassist|beyondtrust|bomgar|dameware|netsupport|action1|level\.io|tactical'
$raSvc = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { ($_.Name + ' ' + $_.DisplayName + ' ' + $_.PathName) -match $raRx })
if ($raSvc) {
    Info 'Remote access services installed - these start with Windows, before anyone signs in:'
    $raSvc | Sort-Object DisplayName | Format-Table @{ n = 'Service'; e = { $_.DisplayName } }, State, StartMode, @{ n = 'Program'; e = { $_.PathName } } -AutoSize | Out-String -Width 250 | Write-Host
    $kinds = @($raSvc | ForEach-Object { ([regex]::Match(($_.Name + ' ' + $_.DisplayName).ToLower(), $raRx)).Value } | Sort-Object -Unique)
    if ($kinds.Count -ge 2) { Flag ($kinds.Count.ToString() + ' different remote access tools installed as services (' + ($kinds -join ', ') + ') - keep ONE approved tool, uninstall the rest') }
} else { Info 'OK - no remote access services installed.' }
# AnyDesk unattended access = a saved password lets anyone with it connect any time
$adc = "$env:ProgramData\AnyDesk\system.conf"
if ((Test-Path -LiteralPath $adc -ErrorAction SilentlyContinue) -and ((Read-AnyText $adc) -match 'pwd_hash["\s]*[:=]\s*"?[0-9a-fA-F]{16,}')) { Flag 'AnyDesk UNATTENDED ACCESS password is set - anyone with it can connect without the user accepting. Remove it in AnyDesk - Settings - Security if not needed' }
# TeamViewer permanent password
foreach ($k in 'HKLM:\SOFTWARE\TeamViewer', 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer') {
    $tv = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if ($tv -and ($tv.SecurityPasswordAES -or $tv.PermanentPassword -or $tv.SecurityPasswordExported)) { Flag 'TeamViewer PERSONAL / UNATTENDED password is set - connects without the user accepting. Check TeamViewer - Extras - Options - Security'; break }
}
# RustDesk permanent password
foreach ($f in @("$env:SystemRoot\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml", "$env:TROAMING\RustDesk\config\RustDesk.toml") | Where-Object { Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue }) {
    if ((Read-AnyText $f) -match "(?m)^\s*password\s*=\s*'[^']+'") { Flag ('RustDesk PERMANENT password is set - connects without the user accepting: ' + $f); break }
}
# VNC - TightVNC server settings
$vnc = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\TightVNC\Server' -ErrorAction SilentlyContinue
if ($vnc) {
    if ($vnc.UseVncAuthentication -eq 0 -or -not $vnc.Password) { Flag 'TightVNC server has NO PASSWORD - anyone on the network can take control. Set a password or uninstall it' }
    elseif ($vnc.LoopbackOnly -ne 1) { Flag 'TightVNC server accepts connections from the network (port 5900) - VNC passwords are weak, max 8 characters. Remove it if not needed' }
}
foreach ($p in ($procs.Values | Where-Object { $_.Name -match '^(tvnserver|winvnc|vncserver|uvnc_service)' } | Sort-Object Name -Unique)) {
    $lp = @(Get-NetTCPConnection -State Listen -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' } | ForEach-Object LocalPort | Sort-Object -Unique)
    if ($lp) { Flag ('VNC server listening for the whole network on port ' + ($lp -join ', ') + ': ' + $p.Name + ' PID ' + $p.ProcessId) }
}
# Remote Desktop
$ts = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
$rdpTcp = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue
if ($ts.fDenyTSConnections -eq 0) {
    $msg = 'Remote Desktop is ENABLED on port ' + $rdpTcp.PortNumber
    if ($rdpTcp.UserAuthentication -eq 0) { Flag ($msg + ' WITHOUT Network Level Authentication - turn NLA on or disable RDP') } else { Info ($msg + ' - NLA on. Members of Administrators / Remote Desktop Users can sign in.') }
    try { $rdu = @(Get-LocalGroupMember -SID 'S-1-5-32-555' -ErrorAction Stop | ForEach-Object Name); if ($rdu) { Info ('Remote Desktop Users: ' + ($rdu -join ', ')) } } catch {}
} else { Info 'Remote Desktop: disabled' }
$rah = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -ErrorAction SilentlyContinue
if ($rah.fAllowFullControl -eq 1 -and $rah.fAllowToGetHelp -eq 1) { Info 'Remote Assistance invitations with full control are allowed.' }
# Other remote command doors
foreach ($sn in 'sshd', 'WinRM', 'RemoteRegistry', 'TlntSvr') {
    $s = Get-Service -Name $sn -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') {
        if ($sn -eq 'WinRM') {
            $wl = @(Get-NetTCPConnection -State Listen -LocalPort 5985, 5986 -ErrorAction SilentlyContinue)
            if ($wl) { Info 'PowerShell Remoting (WinRM) is listening - normal on domain PCs managed by IT.' }
        } elseif ($sn -eq 'sshd') { Flag 'OpenSSH server is running - anyone with a password can run commands. Stop it if not needed: sc stop sshd' }
        elseif ($sn -eq 'TlntSvr') { Flag 'Telnet server is running - unencrypted remote access, remove it' }
        else { Info 'Remote Registry service is running.' }
    }
}

if ($rcAlone) {
    Write-Host ''
    Write-Host '  ===================================================================' -ForegroundColor White
    if ($rcLive -gt 0) { Write-Host ('  CONNECTED NOW: ' + $rcLive + ' remote session(s) / connection(s) - see first section.') -ForegroundColor Red }
    else { Write-Host '  CONNECTED NOW: nobody.' -ForegroundColor Green }
    if ($flags.Count -eq 0) { Write-Host '  RESULT: no remote access risks found.' -ForegroundColor Green }
    else {
        Write-Host ('  REVIEW: ' + $flags.Count + ' item(s):') -ForegroundColor Yellow
        $flags | ForEach-Object { Write-Host ('   - ' + $_) -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '  Unknown session? Unplug the network, stop the tool with option 66, change passwords from ANOTHER device,'
        Write-Host '  then run option 64 for a full malware check.'
    }
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
    exit 0
}
::PS-REMOTECHECK-END

::PS-GUI-BEGIN
# IT Tools window - mouse, arrow keys and search. Every tool runs in its own
# console window as "Tools.bat /opt N", so this window stays open.
# Exit 10 = closed, 11 = "Text menu". Any error -> the batch uses the text menu.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
$txt = [IO.File]::ReadAllText($env:ITSELF)

# Tool names come from the console menus, so new options show up here by themselves.
$names = @{}
foreach ($blk in [regex]::Matches($txt, '(?ms)^:MENU[23]?\r?\n(.*?)^set /p')) {
    foreach ($line in ($blk.Groups[1].Value -split "`r?`n" | Where-Object { $_ -match '^echo ' })) {
        foreach ($m in [regex]::Matches($line, '\[(\d+)\]\s+(.+?)(?=\s{2,}|\s*$)')) {
            $n = [int]$m.Groups[1].Value
            if ($n -gt 0 -and $n -ne 42 -and $n -ne 69) { $names[$n] = ($m.Groups[2].Value -replace '\^', '').Trim() }
        }
    }
}
# Category | description. A new option without a line here shows under "Other".
$info = @{
    1 = 'Network|Full network reset - Winsock, TCP/IP, DNS and adapters. Fixes most no-internet problems.'
    2 = 'Network|IP address, gateway, DNS servers and adapter details.'
    3 = 'Network|Clears cached DNS names - fixes sites that do not open after a change.'
    4 = 'Network|Ping, DNS and web tests that show where the connection breaks.'
    5 = 'Network|Turns the network adapters off and on again.'
    6 = 'Network|Wi-Fi history report and the saved Wi-Fi networks.'
    7 = 'Network|Which programs are connected or listening on ports.'
    8 = 'Network|Syncs the clock - fixes sign-in and certificate errors.'
    9 = 'System Repair|Repairs damaged Windows files with DISM and SFC. Takes 15-30 minutes.'
    10 = 'System Repair|Resets Windows Update when updates fail or hang.'
    11 = 'System Repair|Applies Group Policy now and saves a policy report.'
    12 = 'System Repair|Scans drive C: for file system errors.'
    13 = 'System Repair|Creates a restore point before you change something.'
    14 = 'System Repair|Restarts the taskbar and File Explorer.'
    15 = 'System Repair|Opens the built-in Windows troubleshooters.'
    16 = 'System Repair|Fixes Microsoft Store when it does not open or download.'
    17 = 'Cleanup & Storage|Deletes temp files of the user and of Windows.'
    18 = 'Cleanup & Storage|Empties the Recycle Bin.'
    19 = 'Cleanup & Storage|Free and used space on every drive.'
    20 = 'Apps & Office|Clears the Teams cache - fixes Teams that does not load or sign in.'
    21 = 'Hardware|Battery wear and capacity report.'
    22 = 'Hardware|Disk health - SMART status, wear and errors.'
    23 = 'Hardware|Devices with driver problems or errors.'
    24 = 'Hardware|Restarts Windows audio - fixes no sound.'
    25 = 'Hardware|Why the PC does not sleep, or wakes up by itself.'
    26 = 'Printers|Restarts the print service.'
    27 = 'Printers|Clears stuck print jobs.'
    28 = 'Apps & Office|Starts Outlook without add-ins.'
    29 = 'Accounts|Opens saved Windows and web passwords.'
    30 = 'Accounts|Windows and Office keys, activation and licence status.'
    31 = 'Accounts|Shows whether Windows is activated.'
    32 = 'Security & Remote|Drive encryption status.'
    33 = 'Reports|Hardware, Windows version, uptime and serial number.'
    34 = 'Reports|Errors from the event log in the last 24 hours.'
    35 = 'Reports|Programs that start with Windows.'
    36 = 'Reports|Saves the list of installed programs.'
    37 = 'Reports|One full report for an IT ticket - every check in one file.'
    38 = 'Tools|Shortcuts to Device Manager, Services, Event Viewer and more.'
    39 = 'Tools|Opens the folder with all saved reports.'
    40 = 'Tools|Restarts the computer.'
    41 = 'Tools|Downloads the newest version of IT Tools.'
    43 = 'Apps & Office|Fixes Outlook or Teams that does not open or hangs.'
    44 = 'Apps & Office|Quick or online repair of Microsoft Office.'
    45 = 'Apps & Office|Clears the Office sign-in - fixes licence and account prompts.'
    46 = 'Apps & Office|Rebuilds the Outlook mailbox cache (OST).'
    47 = 'Apps & Office|Lists and creates Outlook mail profiles.'
    48 = 'Apps & Office|OneDrive sync status and backed-up folders.'
    49 = 'Apps & Office|Resets OneDrive when sync is stuck.'
    50 = 'Shares & Domain|List, map and reconnect network drives.'
    51 = 'Shares & Domain|Removes saved passwords for a server or share.'
    52 = 'Shares & Domain|Tests domain and VPN, repairs the computer trust.'
    53 = 'Apps & Office|Clears the Edge and Chrome cache.'
    54 = 'Accounts|Finds temporary profiles and shows profile size.'
    55 = 'Security & Remote|Starts Quick Assist and shows this PC''s IP address.'
    56 = 'System Repair|Fixes the Start menu and Windows search.'
    57 = 'System Repair|Rebuilds the search index.'
    58 = 'System Repair|Fixes blank icons and thumbnails.'
    59 = 'System Repair|Fixes Win+L and the missing Lock option.'
    60 = 'Cleanup & Storage|Stops background bandwidth use, ads and tips.'
    61 = 'Cleanup & Storage|Deep clean - junk, update cache, crash dumps, component store.'
    62 = 'Cleanup & Storage|Removes preinstalled consumer apps.'
    63 = 'Accounts|Turns a Microsoft account into a local administrator.'
    64 = 'Security & Remote|Malware and hacked-PC check - connections, auto-starts, Defender.'
    65 = 'Security & Remote|Finds programs sending spam email and blocks them.'
    66 = 'Security & Remote|Stops a process, blocks it in the firewall, removes infected files.'
    67 = 'Security & Remote|Who is connected remotely now, in the last 30 days, and always-on access.'
    68 = 'Cleanup & Storage|What fills the drive, then safe cleanup of caches and leftovers.'
    70 = 'Hardware|Hardware and disk health report.'
    71 = 'Hardware|Blue screens and unexpected shutdowns explained.'
    72 = 'Hardware|CPU, memory and disk usage snapshot.'
    73 = 'Hardware|Driver list, old drivers and export.'
    74 = 'System Repair|Windows Update health check.'
    75 = 'Network|Advanced network diagnostics.'
    76 = 'Security & Remote|Security baseline audit - firewall, UAC, updates, policies.'
    77 = 'Reports|Recurring event log errors grouped by cause.'
    78 = 'USB|Removes the USB shortcut virus - unhides your files, deletes autorun and virus shortcuts, Defender scan.'
    79 = 'USB|Turn USB flash drives and external disks off, on or read-only. Keyboard and mouse keep working.'
    80 = 'Accounts|Windows 11 setup with a local account instead of a Microsoft account. In setup: Shift+F10, then run Tools.bat - this menu opens by itself.'
    81 = 'Network|Scans the LAN and lists every device - IP, MAC, name, maker and count. See who is on the network.'
    82 = 'Network|Wi-Fi signal in dBm, band and channel, plus other Wi-Fi nearby on your channel, with how to fix weak or crowded Wi-Fi.'
    83 = 'Network|Who uses the bandwidth - top programs on this PC, open the router page, or poll the router/switch by SNMP for per-port traffic.'
    84 = 'System Repair|Windows image health with DISM and SFC - diagnose (read-only HTML report), clean up WinSxS, or repair online from Windows Update or offline from an ISO.'
    85 = 'Tools|File Organizer - sorts the files in a folder you choose into type subfolders (Images, Videos, PDFs, Word...). Safe: never touches system folders, never overwrites, and can undo.'
    86 = 'Security & Remote|Firewall Center - status, enable/disable, block or allow an inbound port, add/remove/list custom rules, back up / restore / import the firewall configuration, and view network profiles.'
    87 = 'Network|Device Type Scan - identifies what each IP on the LAN is by its open ports and MAC: Hikvision/Dahua NVR, DVR and cameras, ZKTeco fingerprint/access control, printers, PCs, routers and switches.'
}
$tools = @(foreach ($n in ($names.Keys | Sort-Object)) {
    $p = if ($info[$n]) { $info[$n] -split '\|', 2 } else { @('Other', '') }
    [pscustomobject]@{ N = [int]$n; Name = $names[$n]; Desc = $p[1]; Cat = $p[0] }
})
# Problem words (slow, hacked...) are shared with the text-menu search
$tags = @{}
if ($txt -match '(?ms)^::PS-SEARCH-BEGIN(.*?)^::PS-SEARCH-END') { foreach ($m in [regex]::Matches($Matches[1], "'([a-z0-9]+)'\s*=\s*'([0-9 ]+)'")) { $tags[$m.Groups[1].Value] = @($m.Groups[2].Value -split ' ') } }
$stop = 'my','pc','is','the','it','me','to','of','and','in','on','at','for','computer','laptop','working','work','problem','issue','please','help','cant','can','does','dont','doesnt','very','too','so','what','why','how','not','no','all','time','times','again','keeps','always'
$recentFile = if ($env:ITROOT) { Join-Path $env:ITROOT 'bin\recent.txt' } else { $null }
$state = @{ Cat = 'All tools'; Exit = 10; Tick = 0; Recent = @() }
if ($recentFile -and (Test-Path -LiteralPath $recentFile)) { $state.Recent = @(Get-Content -LiteralPath $recentFile | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }) }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="IT Tools" Width="1200" Height="760" MinWidth="960" MinHeight="580" WindowStartupLocation="CenterScreen"
        Background="#0E1120" Foreground="#E6E8F2" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#2C3358"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Nav" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#B9BED6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="Bd" CornerRadius="8" Padding="12,9" Margin="0,1" Background="Transparent"><ContentPresenter/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#171B31"/></Trigger>
            <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#22284A"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Row" TargetType="ListBoxItem">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="Bd" CornerRadius="10" Padding="12,10" Margin="0,0,6,6" Background="#121630" BorderBrush="#1C2142" BorderThickness="1"><ContentPresenter/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#171C38"/></Trigger>
            <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#1E2550"/><Setter TargetName="Bd" Property="BorderBrush" Value="#6366F1"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#E6E8F2"/>
      <Setter Property="Background" Value="#1B2040"/>
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.7"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/><ColumnDefinition Width="330"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

    <Border Grid.RowSpan="2" Background="#0A0D1A" BorderBrush="#1D2240" BorderThickness="0,0,1,0">
      <DockPanel Margin="14,18,14,14">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,0,0,18">
          <Border Width="36" Height="36" CornerRadius="10" Background="#6366F1">
            <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="11,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="IT Tools" FontSize="17" FontWeight="Bold"/>
            <TextBlock x:Name="Ver" Foreground="#7D84A6" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <TextBlock x:Name="Pc" DockPanel.Dock="Bottom" Foreground="#7D84A6" FontSize="11" TextWrapping="Wrap" Margin="6,10,0,0" LineHeight="17"/>
        <ListBox x:Name="Cats" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" KeyboardNavigation.TabNavigation="Once">
          <ListBox.ItemTemplate><DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <TextBlock Text="{Binding Icon}" FontFamily="Segoe MDL2 Assets" FontSize="14" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="{Binding Name}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="{Binding Count}" Foreground="#5E6590" FontSize="11" VerticalAlignment="Center"/>
            </Grid>
          </DataTemplate></ListBox.ItemTemplate>
        </ListBox>
      </DockPanel>
    </Border>

    <DockPanel Grid.Column="1" Margin="22,18,16,0">
      <Border DockPanel.Dock="Top" Background="#141831" CornerRadius="10" BorderBrush="#2A3160" BorderThickness="1">
        <Grid>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="#7D84A6" FontSize="15" Margin="15,0,0,0" VerticalAlignment="Center"/>
          <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" Foreground="#E6E8F2" CaretBrush="#A5B4FC" FontSize="15" Padding="42,12,12,12" VerticalContentAlignment="Center"/>
          <TextBlock x:Name="Hint" Text="Type to search - slow, printer, usb, hacked, outlook, or an option number" Foreground="#5E6590" FontSize="15" Margin="45,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        </Grid>
      </Border>
      <WrapPanel x:Name="Chips" DockPanel.Dock="Top" Margin="0,12,0,0"/>
      <TextBlock x:Name="Heading" DockPanel.Dock="Top" FontSize="12" Foreground="#7D84A6" Margin="2,8,0,8"/>
      <Grid>
        <ListBox x:Name="List" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel">
          <ListBox.ItemTemplate><DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="50"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <Border Width="38" Height="38" CornerRadius="9" Background="#20264A" HorizontalAlignment="Left">
                <TextBlock Text="{Binding N}" Foreground="#A5B4FC" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Grid.Column="1" VerticalAlignment="Center">
                <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold" Foreground="#E6E8F2" TextTrimming="CharacterEllipsis"/>
                <TextBlock Text="{Binding Desc}" Foreground="#8A90AD" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/>
              </StackPanel>
              <Border Grid.Column="2" CornerRadius="6" Background="#1A1F3B" Padding="8,3" Margin="12,0,0,0" VerticalAlignment="Center">
                <TextBlock Text="{Binding Cat}" Foreground="#7D84A6" FontSize="11"/>
              </Border>
            </Grid>
          </DataTemplate></ListBox.ItemTemplate>
        </ListBox>
        <TextBlock x:Name="Empty" Text="No tool matches. Try another word - internet, disk, printer, usb, outlook." Foreground="#7D84A6" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,40,0,0" Visibility="Collapsed"/>
      </Grid>
    </DockPanel>

    <Border Grid.Column="2" Margin="0,18,18,0" Background="#141831" CornerRadius="12" BorderBrush="#252B4D" BorderThickness="1" Padding="22">
      <DockPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <Button x:Name="RunBtn" Style="{StaticResource Btn}" Background="#6366F1" FontSize="14" Padding="14,13">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="Run tool"/>
              <TextBlock Text="   Enter" Foreground="#C7D2FE" FontWeight="Normal"/>
            </StackPanel>
          </Button>
          <TextBlock Text="Opens in its own window - you can start more tools while it runs." Foreground="#7D84A6" FontSize="11" TextWrapping="Wrap" Margin="2,10,0,0"/>
        </StackPanel>
        <StackPanel>
          <Border HorizontalAlignment="Left" CornerRadius="8" Background="#232A55" Padding="10,4">
            <TextBlock x:Name="DCat" Foreground="#A5B4FC" FontSize="11" FontWeight="SemiBold"/>
          </Border>
          <TextBlock x:Name="DName" FontSize="21" FontWeight="Bold" TextWrapping="Wrap" Margin="0,16,0,0"/>
          <TextBlock x:Name="DNum" Foreground="#7D84A6" Margin="0,5,0,0"/>
          <TextBlock x:Name="DDesc" Foreground="#B9BED6" FontSize="14" TextWrapping="Wrap" Margin="0,16,0,0" LineHeight="21"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <DockPanel Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Margin="22,12,18,14">
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="ReportsBtn" Style="{StaticResource Btn}" Margin="8,0,0,0" Content="Reports folder"/>
        <Button x:Name="TextBtn" Style="{StaticResource Btn}" Margin="8,0,0,0" Content="Text menu"/>
      </StackPanel>
      <StackPanel VerticalAlignment="Center">
        <TextBlock x:Name="Status" Foreground="#A5B4FC" FontSize="12" TextTrimming="CharacterEllipsis"/>
        <TextBlock Foreground="#5E6590" FontSize="11" Margin="0,3,0,0" Text="&#x2191; &#x2193;  move      Enter  run      Double-click  run      Esc  clear search      Ctrl+&#x2191; &#x2193;  category"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Ver', 'Pc', 'Cats', 'Search', 'Hint', 'Chips', 'Heading', 'List', 'Empty', 'RunBtn', 'DCat', 'DName', 'DNum', 'DDesc', 'ReportsBtn', 'TextBtn', 'Status') { $ui[$n] = $win.FindName($n) }
$bc = New-Object Windows.Media.BrushConverter
function Brush($c) { $bc.ConvertFromString($c) }

if ($txt -match '(?m)^title IT Tools (v[0-9.]+)') { $ui.Ver.Text = $Matches[1] } else { $ui.Ver.Text = 'Windows troubleshooter' }
$ui.Pc.Text = $env:COMPUTERNAME + "`nAdmin: " + $env:USERDOMAIN + '\' + $env:USERNAME + $(if ($env:TUSER) { "`nUser: " + $env:TUSER } else { '' })

# Categories in a fixed order, with Segoe MDL2 icons
$catOrder = [ordered]@{ 'All tools' = 0xE8FD; 'Recent' = 0xE81C; 'Network' = 0xE701; 'System Repair' = 0xE90F; 'Cleanup & Storage' = 0xE74D; 'Hardware' = 0xE772
    'USB' = 0xE88E; 'Printers' = 0xE749; 'Apps & Office' = 0xE71D; 'Accounts' = 0xE77B; 'Security & Remote' = 0xE72E; 'Shares & Domain' = 0xE8CE
    'Reports' = 0xE9D9; 'Tools' = 0xE713; 'Other' = 0xE10C }
function Update-Cats {
    $sel = $state.Cat
    $list = foreach ($c in $catOrder.Keys) {
        $cnt = if ($c -eq 'All tools') { $tools.Count } elseif ($c -eq 'Recent') { $state.Recent.Count } else { @($tools | Where-Object Cat -eq $c).Count }
        if ($cnt -gt 0 -or $c -eq 'All tools') { [pscustomobject]@{ Name = $c; Icon = [string][char]$catOrder[$c]; Count = $cnt } }
    }
    $ui.Cats.ItemsSource = @($list)
    $ui.Cats.SelectedItem = @($list | Where-Object Name -eq $sel)[0]
}
function Get-Score($t, $words, $q) {
    if ($q -match '^\d+$') { if ($t.N -eq [int]$q) { return 100 } elseif ([string]$t.N -like ($q + '*')) { return 5 } else { return 0 } }
    $s = 0
    foreach ($w in $words) {
        $rx = '(?i)(^|[^a-z0-9])' + [regex]::Escape($w)
        if ($t.Name -match $rx) { $s += 3 } elseif ($t.Desc -match $rx -or $t.Cat -match $rx) { $s += 1 }
        foreach ($tg in $tags.Keys) {
            if ($tg.StartsWith($w) -or ($w.Length -ge 4 -and $w.StartsWith($tg))) {
                $ix = [array]::IndexOf($tags[$tg], [string]$t.N)
                if ($ix -ge 0) { $s += [Math]::Max(1, 2 - $ix) }
            }
        }
    }
    return $s
}
function Update-List {
    $q = $ui.Search.Text.Trim().ToLower()
    $ui.Hint.Visibility = $(if ($ui.Search.Text) { 'Collapsed' } else { 'Visible' })
    if ($q) {
        $words = @($q -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 2 -and $stop -notcontains $_ })
        if ($q -match '^\d+$') { $words = @() }
        $hits = foreach ($t in $tools) { $sc = Get-Score $t $words $q; if ($sc -gt 0) { [pscustomobject]@{ T = $t; S = $sc } } }
        $items = @($hits | Sort-Object @{ e = { $_.S }; Descending = $true }, @{ e = { $_.T.N } } | ForEach-Object { $_.T })
        $ui.Heading.Text = $items.Count.ToString() + ' result(s) for "' + $ui.Search.Text.Trim() + '" - best match first'
    } elseif ($state.Cat -eq 'Recent') {
        $items = @(foreach ($r in $state.Recent) { $tools | Where-Object N -eq $r })
        $ui.Heading.Text = 'Recently used'
    } elseif ($state.Cat -eq 'All tools') {
        $items = $tools
        $ui.Heading.Text = 'All tools - ' + $tools.Count
    } else {
        $items = @($tools | Where-Object Cat -eq $state.Cat)
        $ui.Heading.Text = $state.Cat + ' - ' + $items.Count + ' tool(s)'
    }
    $ui.List.ItemsSource = @($items)
    $ui.Empty.Visibility = $(if ($items.Count) { 'Collapsed' } else { 'Visible' })
    if ($items.Count) { $ui.List.SelectedIndex = 0; $ui.List.ScrollIntoView($ui.List.SelectedItem) } else { Show-Detail $null }
}
function Show-Detail($t) {
    if (-not $t) { $ui.DCat.Text = 'IT Tools'; $ui.DName.Text = 'Pick a tool'; $ui.DNum.Text = ''; $ui.DDesc.Text = 'Search or choose a category on the left, then press Enter or double-click a tool.'; $ui.RunBtn.IsEnabled = $false; return }
    $ui.DCat.Text = $t.Cat.ToUpper(); $ui.DName.Text = $t.Name; $ui.DNum.Text = 'Option ' + $t.N
    $ui.DDesc.Text = $(if ($t.Desc) { $t.Desc } else { $t.Name })
    $ui.RunBtn.IsEnabled = $true
}
function Move-Sel($d) {
    $c = $ui.List.Items.Count; if (-not $c) { return }
    $ui.List.SelectedIndex = [Math]::Max(0, [Math]::Min($c - 1, $ui.List.SelectedIndex + $d))
    $ui.List.ScrollIntoView($ui.List.SelectedItem)
}
function Start-Tool {
    $t = $ui.List.SelectedItem
    if (-not $t) { return }
    try {
        Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ""' + $env:ITSELF + '" /opt ' + [int]$t.N + '"') -ErrorAction Stop
        $ui.Status.Text = 'Started  [' + $t.N + ']  ' + $t.Name + '  -  running in its own window.'
        $state.Recent = @(@([int]$t.N) + @($state.Recent | Where-Object { $_ -ne $t.N }) | Select-Object -First 10)
        if ($recentFile) { try { [IO.File]::WriteAllLines($recentFile, [string[]]$state.Recent) } catch {} }
        $keep = $ui.List.SelectedIndex
        Update-Cats
        $ui.List.SelectedIndex = $keep
    } catch { $ui.Status.Text = 'Could not start the tool: ' + $_.Exception.Message }
}

# Status chips - the HEALTH block runs in the background so the window opens at once
$hcode = if ($txt -match '(?ms)^::PS-HEALTH-BEGIN\r?\n(.*?)^::PS-HEALTH-END') { $Matches[1] } else { '' }
$health = @{ PS = $null; AR = $null }
function Start-Health {
    if (-not $hcode -or $health.PS) { return }
    $p = [PowerShell]::Create(); [void]$p.AddScript($hcode); $health.PS = $p; $health.AR = $p.BeginInvoke()
}
function Show-Chips {
    if (-not $env:ITROOT) { return }
    $f = Join-Path $env:ITROOT 'bin\health.cache'
    if (-not (Test-Path -LiteralPath $f)) { return }
    $ui.Chips.Children.Clear()
    foreach ($l in (Get-Content -LiteralPath $f)) {
        $c = $l -split '\|', 3; if ($c.Count -lt 3) { continue }
        $tb = New-Object Windows.Controls.TextBlock; $tb.FontSize = 12
        $r1 = New-Object Windows.Documents.Run ($c[0] + '  '); $r1.Foreground = Brush '#7D84A6'
        $r2 = New-Object Windows.Documents.Run $c[1]; $r2.FontWeight = 'SemiBold'
        $r2.Foreground = Brush $(switch ($c[2]) { 'Green' { '#34D399' } 'Yellow' { '#FBBF24' } 'Red' { '#F87171' } default { '#9CA3AF' } })
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $b = New-Object Windows.Controls.Border; $b.Background = Brush '#141831'; $b.BorderBrush = Brush '#22284A'; $b.BorderThickness = 1
        $b.CornerRadius = 8; $b.Padding = '10,5'; $b.Margin = '0,0,8,4'; $b.Child = $tb
        [void]$ui.Chips.Children.Add($b)
    }
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if ($health.PS -and $health.AR.IsCompleted) { try { [void]$health.PS.EndInvoke($health.AR) } catch {}; $health.PS.Dispose(); $health.PS = $null; Show-Chips }
    $state.Tick++
    if ($state.Tick -ge 150) { $state.Tick = 0; Start-Health }   # refresh every 60 seconds
})

# Events
$ui.Search.Add_TextChanged({ Update-List })
$ui.Cats.Add_SelectionChanged({
    $c = $ui.Cats.SelectedItem
    if ($c -and $c.Name -ne $state.Cat) { $state.Cat = $c.Name; if ($ui.Search.Text) { $ui.Search.Text = '' } else { Update-List } }
})
$ui.List.Add_SelectionChanged({ Show-Detail $ui.List.SelectedItem })
$ui.List.Add_MouseDoubleClick({ param($s, $e) if ($e.OriginalSource -is [Windows.FrameworkElement] -and $e.OriginalSource.DataContext -and $e.OriginalSource.DataContext.N) { Start-Tool } })
$ui.RunBtn.Add_Click({ Start-Tool; $ui.Search.Focus() })
$ui.ReportsBtn.Add_Click({ if ($env:REPORTROOT) { Start-Process explorer.exe $env:REPORTROOT } })
$ui.TextBtn.Add_Click({ $state.Exit = 11; $win.Close() })
$win.Add_PreviewKeyDown({
    param($s, $e)
    $k = $e.Key
    $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
    if ($e.OriginalSource -is [Windows.Controls.Button] -and ($k -eq 'Return' -or $k -eq 'Space')) { return }
    if ($ctrl -and $k -eq 'F') { $ui.Search.Focus(); $ui.Search.SelectAll(); $e.Handled = $true; return }
    if ($ctrl -and ($k -eq 'Up' -or $k -eq 'Down')) {
        $c = $ui.Cats.Items.Count
        $ui.Cats.SelectedIndex = [Math]::Max(0, [Math]::Min($c - 1, $ui.Cats.SelectedIndex + $(if ($k -eq 'Up') { -1 } else { 1 })))
        $e.Handled = $true; return
    }
    if ($k -eq 'Return') { Start-Tool; $e.Handled = $true; return }
    if ($k -eq 'Escape') { if ($ui.Search.Text) { $ui.Search.Text = '' }; $ui.Search.Focus(); $e.Handled = $true; return }
    if ($ui.Search.IsKeyboardFocusWithin -or $ui.List.IsKeyboardFocusWithin) {
        switch ($k) {
            'Down'     { Move-Sel 1;  $e.Handled = $true }
            'Up'       { Move-Sel -1; $e.Handled = $true }
            'PageDown' { Move-Sel 6;  $e.Handled = $true }
            'PageUp'   { Move-Sel -6; $e.Handled = $true }
        }
    }
})
# Typing anywhere goes to the search box
$win.Add_PreviewTextInput({
    param($s, $e)
    if (-not $ui.Search.IsKeyboardFocusWithin -and $e.Text -match '^[A-Za-z0-9 ]$' -and -not ($e.OriginalSource -is [Windows.Controls.Button])) {
        $ui.Search.Focus(); $ui.Search.Text += $e.Text; $ui.Search.CaretIndex = $ui.Search.Text.Length; $e.Handled = $true
    }
})

# Hide the black console behind the window while it is open
$con = [IntPtr]::Zero
try {
    Add-Type -Namespace ITTools -Name Con -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);' -ErrorAction Stop
    $con = [ITTools.Con]::GetConsoleWindow()
} catch {}
$win.Add_Loaded({
    if ($con -ne [IntPtr]::Zero -and -not $env:ITTOOLS_KEEPCONSOLE) { [void][ITTools.Con]::ShowWindow($con, 0) }
    $ui.Search.Focus(); Start-Health; $timer.Start()
})

Update-Cats
Update-List
$ui.Status.Text = 'Ready - ' + $tools.Count + ' tools. Start typing to search.'
try { [void]$win.ShowDialog() }
finally {
    $timer.Stop()
    if ($con -ne [IntPtr]::Zero) { [void][ITTools.Con]::ShowWindow($con, 5) }
}
exit $state.Exit
::PS-GUI-END

::PS-NETDEVID-BEGIN
# Identify WHAT each device on the LAN is, by its open ports + MAC maker + web banner.
# Read-only. Finds Hikvision/Dahua NVR-DVR, IP cameras, ZKTeco fingerprint/access,
# printers, PCs, routers/switches. Writes an HTML report.
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_DeviceTypes_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
try { Start-Transcript -Path $report -Force | Out-Null } catch {}
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
# MAC maker -> a hint about the device kind (OUI prefix)
$ouiType = @{
    'B422C7' = 'Hikvision'; '4CBD8F' = 'Hikvision'; 'BCAD28' = 'Hikvision'; 'C056E3' = 'Hikvision'; '44191C' = 'Dahua'; '3CEF8C' = 'Dahua'; '902B34' = 'Dahua'; 'E0509D' = 'Dahua'
    '001567' = 'ZKTeco'; '0017610' = 'ZKTeco'; '003E7A' = 'Axis-Camera'; 'ACCC8E' = 'Axis-Camera'; '00408C' = 'Axis-Camera'; 'E86A64' = 'Uniview'; '481A84' = 'Uniview'
    '0004FF' = 'Printer-HP'; '3822E2' = 'Printer-HP'; '70106F' = 'Printer-HP'; '001708' = 'Printer-HP'; '00904C' = 'Printer-Epson'; 'A4E7E4' = 'Printer-Epson'; '001986' = 'Printer-Epson'
    '0017C8' = 'Printer-Kyocera'; '001D72' = 'Printer-Kyocera'; '0021B7' = 'Printer-Lexmark'; '008088' = 'Printer-Brother'; '30055C' = 'Printer-Brother'; '001BA9' = 'Printer-Brother'; '002673' = 'Printer-Canon'
    '00156D' = 'Ubiquiti'; '245A4C' = 'Ubiquiti'; 'FCECDA' = 'Ubiquiti'; '788A20' = 'Ubiquiti'; 'CC32E5' = 'MikroTik'; '4C5E0C' = 'MikroTik'; '6C3B6B' = 'MikroTik'
    '50C7BF' = 'TP-Link'; 'C46E1F' = 'TP-Link'; 'A842A1' = 'TP-Link'; '000FB5' = 'Netgear'; '000B86' = 'Aruba'; '6CF37F' = 'Aruba'
    'B827EB' = 'Raspberry-Pi'; 'DCA632' = 'Raspberry-Pi'; '001132' = 'Synology'; '0011D8' = 'Asustek'
}
function MakerType($mac) { if (-not $mac) { return '' }; $p = ($mac -replace '[-:]', '').ToUpper(); if ($p.Length -ge 6 -and $ouiType.ContainsKey($p.Substring(0, 6))) { return $ouiType[$p.Substring(0, 6)] }; return '' }

# Ports we probe, with what they usually mean
$ports = 80, 443, 8080, 8000, 8899, 554, 37777, 37778, 4370, 9100, 515, 631, 445, 139, 22, 3389, 23, 5000, 88
$portName = @{ 80 = 'http'; 443 = 'https'; 8080 = 'http-alt'; 8000 = 'Hik-SDK'; 8899 = 'web'; 554 = 'RTSP'; 37777 = 'Dahua'; 37778 = 'Dahua'; 4370 = 'ZKTeco'; 9100 = 'print'; 515 = 'LPD'; 631 = 'IPP'; 445 = 'SMB'; 139 = 'NetBIOS'; 22 = 'SSH'; 3389 = 'RDP'; 23 = 'telnet'; 5000 = 'web'; 88 = 'Hik-alt' }

$nets = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    ForEach-Object { $a = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue; if ($a.Status -eq 'Up' -and -not $a.Virtual -and $a.InterfaceDescription -notmatch 'Hyper-V|Virtual|WSL|Loopback|VPN|TAP|Default Switch') { [pscustomobject]@{ IP = $_.IPAddress; If = $a.Name } } } | Sort-Object IP -Unique)
if (-not $nets) { Write-Host '  No real network found. Connect to the LAN and run again.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch {}; exit 0 }

function Grab-Server($ip, $port) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        if (-not $c.ConnectAsync($ip, $port).Wait(500)) { $c.Close(); return '' }
        $s = $c.GetStream(); $s.ReadTimeout = 700
        $req = [Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.0`r`nHost: $ip`r`nUser-Agent: ITTools`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 1024; $n = $s.Read($buf, 0, 1024); $c.Close()
        $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
        $srv = ''; if ($txt -match '(?im)^Server:\s*(.+)$') { $srv = $Matches[1].Trim() }
        $realm = ''; if ($txt -match '(?im)^WWW-Authenticate:.*realm="?([^"\r]+)') { $realm = $Matches[1].Trim() }
        $title = ''; if ($txt -match '(?is)<title>(.*?)</title>') { $title = ($Matches[1] -replace '\s+', ' ').Trim() }
        return (@($srv, $realm, $title) | Where-Object { $_ } | Select-Object -First 1)
    } catch { return '' }
}
function Classify($openList, $makerType, $server) {
    $o = @{}; foreach ($p in $openList) { $o[$p] = $true }
    $sv = ([string]$server).ToLower()
    if ($sv -match 'hikvision|app-webs|dnvrs|web server 1\.0' -or $o[8000]) { return 'Hikvision camera / NVR / DVR' }
    if ($sv -match 'dahua|boa' -and ($o[37777] -or $o[554]) ) { return 'Dahua camera / NVR / DVR' }
    if ($o[37777] -or $o[37778]) { return 'Dahua NVR / DVR' }
    if ($o[4370]) { return 'Fingerprint / access control (ZKTeco)' }
    if ($makerType -eq 'ZKTeco') { return 'Fingerprint / access control (ZKTeco)' }
    if ($makerType -match 'Hikvision|Dahua|Axis|Uniview') { return ($makerType + ' camera / NVR') }
    if ($o[554]) { return 'IP camera (RTSP)' }
    if ($o[9100] -or $o[515] -or $o[631] -or $makerType -like 'Printer-*') { return ('Printer' + $(if ($makerType -like 'Printer-*') { ' (' + ($makerType -replace 'Printer-', '') + ')' } else { '' })) }
    if ($makerType -match 'Ubiquiti|MikroTik|TP-Link|Netgear|Aruba') { return ('Network device - ' + $makerType) }
    if ($o[3389] -or ($o[445] -and $o[139])) { return 'Windows PC / Server' }
    if ($makerType -eq 'Synology') { return 'Synology NAS' }
    if ($o[5000] -and $o[22]) { return 'NAS / Linux device' }
    if ($o[22]) { return 'Linux / device (SSH)' }
    if ($o[23]) { return 'Old device (Telnet) - DVR / switch' }
    if ($o[443] -or $o[80] -or $o[8080] -or $o[8899]) { return 'Web device' }
    return 'Unknown' }

foreach ($net in $nets) {
    $o = $net.IP.Split('.'); $base = $o[0] + '.' + $o[1] + '.' + $o[2] + '.'
    Sec ('Network ' + $base + '0  on ' + $net.If + '  (this PC: ' + $net.IP + ')')
    Write-Host '  Finding devices (ping sweep)...' -ForegroundColor DarkGray
    $pings = 1..254 | ForEach-Object { (New-Object Net.NetworkInformation.Ping).SendPingAsync(($base + $_), 500) }
    try { [Threading.Tasks.Task]::WaitAll($pings) } catch {}
    $alive = New-Object System.Collections.Generic.HashSet[string]
    for ($i = 0; $i -lt 254; $i++) { try { if ($pings[$i].Result.Status -eq 'Success') { [void]$alive.Add($base + ($i + 1)) } } catch {} }
    $arp = @{}
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -and $_.State -in 'Reachable', 'Stale', 'Permanent', 'Delay' -and $_.IPAddress -like ($base + '*') -and $_.LinkLayerAddress -notmatch '^(FF-FF|01-00-5E|33-33)' } | ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress; [void]$alive.Add($_.IPAddress) }
    $hosts = @($alive | Where-Object { $_.Split('.')[3] -notin '0', '255' } | Sort-Object { [int]($_.Split('.')[3]) })
    if (-not $hosts) { Write-Host '  No devices answered.' -ForegroundColor Yellow; continue }
    $gw = (Get-NetRoute -InterfaceAlias $net.If -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
    Write-Host ('  ' + $hosts.Count + ' device(s) found. Checking open ports to identify each one...') -ForegroundColor DarkGray

    # Launch all port probes together, then wait once
    $jobs = New-Object System.Collections.ArrayList
    foreach ($ip in $hosts) { foreach ($p in $ports) { $cli = New-Object Net.Sockets.TcpClient; [void]$jobs.Add([pscustomobject]@{ IP = $ip; Port = $p; Cli = $cli; Task = $cli.ConnectAsync($ip, $p) }) } }
    Start-Sleep -Milliseconds 900
    $openByIp = @{}
    foreach ($j in $jobs) { try { if ($j.Task.IsCompleted -and $j.Cli.Connected) { if (-not $openByIp[$j.IP]) { $openByIp[$j.IP] = New-Object System.Collections.ArrayList }; [void]$openByIp[$j.IP].Add($j.Port) } } catch {}; try { $j.Cli.Close() } catch {} }

    $rows = foreach ($ip in $hosts) {
        $open = @($openByIp[$ip] | Sort-Object)
        $mac = $arp[$ip]; $mt = MakerType $mac
        $server = ''
        foreach ($wp in 80, 8000, 8080, 8899, 88) { if ($open -contains $wp) { $server = Grab-Server $ip $wp; if ($server) { break } } }
        $name = ''; try { $name = (([Net.Dns]::GetHostEntryAsync($ip).Result).HostName -split '\.')[0] } catch {}
        $type = Classify $open $mt $server
        if ($ip -eq $gw) { $type = 'Router / gateway' + $(if ($mt) { ' - ' + $mt } else { '' }) }
        [pscustomobject]@{
            IP = $ip; Name = $name; MAC = $(if ($mac) { $mac.ToUpper() } else { '' })
            Device = $type
            Ports = (($open | ForEach-Object { if ($portName[$_]) { $portName[$_] } else { [string]$_ } }) -join ',')
            Web = $server
            This = $(if ($ip -eq $net.IP) { '<< this PC' } else { '' })
        }
    }
    $rows | Format-Table IP, Device, Name, MAC, Ports, This -AutoSize | Out-String -Width 230 | Write-Host
    Write-Host '  Web banners (helps confirm cameras / NVRs):' -ForegroundColor DarkGray
    foreach ($r in ($rows | Where-Object { $_.Web })) { Write-Host ('     ' + $r.IP.PadRight(16) + $r.Web) -ForegroundColor DarkGray }
    # Summary by type
    Write-Host ''
    Write-Host '  Count by device type:' -ForegroundColor Cyan
    $rows | Group-Object Device | Sort-Object Count -Descending | ForEach-Object { Write-Host ('     ' + ([string]$_.Count).PadLeft(3) + '  ' + $_.Name) }
}
Write-Host ''
Write-Host '  Tips to confirm a device:'
Write-Host '   - Hikvision: open http://<IP> in a browser, or use the SADP tool. Port 8000 = Hikvision.'
Write-Host '   - Dahua: port 37777, or the ConfigTool. - ZKTeco fingerprint: port 4370.'
Write-Host '   - A device set to ignore ping will still show if it has an open port and is in the ARP table.'
Write-Host '   - For a full client list (names/leases), read the router - option 83 [2].'
try { Stop-Transcript | Out-Null } catch {}
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-NETDEVID-END

::PS-NETSCAN-BEGIN
# Who is on the LAN. Read-only: ping sweep + ARP table + name + MAC maker.
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_NetworkScan_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
try { Start-Transcript -Path $report -Force | Out-Null } catch {}
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
# Common MAC makers - first 3 bytes (OUI). Unknown makers show blank.
$oui = @{
    '001122'='Cisco'; '00000C'='Cisco'; 'F4CFE2'='Cisco'; '00156D'='Ubiquiti'; '245A4C'='Ubiquiti'; 'FCECDA'='Ubiquiti'; '6478BE'='Ubiquiti'
    '0418D6'='Ubiquiti'; 'E063DA'='Ubiquiti'; '788A20'='Ubiquiti'; '002722'='TP-Link'; '50C7BF'='TP-Link'; 'C46E1F'='TP-Link'; 'EC086B'='TP-Link'
    '14CC20'='TP-Link'; 'A842A1'='TP-Link'; '003192'='TP-Link'; '001D0F'='TP-Link'; 'B0487A'='TP-Link'; 'CC32E5'='MikroTik'; '4C5E0C'='MikroTik'
    'E48D8C'='MikroTik'; '6C3B6B'='MikroTik'; '08557'='MikroTik'; '001DAA'='D-Link'; '00179A'='D-Link'; '1CBDB9'='D-Link'; 'C8D3A3'='D-Link'
    '000FB5'='Netgear'; '20E52A'='Netgear'; 'A040A0'='Netgear'; '9CD36D'='Netgear'; '000C42'='Routerboard'; '001E58'='Aruba'; '6CF37F'='Aruba'
    '000B86'='Aruba'; '00904C'='Epson'; '001986'='Epson'; 'A4E7E4'='Epson'; '000048'='Seiko-Epson'; '0017C8'='Kyocera'; '001D72'='Kyocera'
    '0021B7'='Lexmark'; '0004FF'='HP'; '001E0B'='HP'; '3822E2'='HP'; '70106F'='HP'; '9C8E99'='HP'; 'E4E749'='HP'; '001B78'='HP'; '001708'='HP-Printer'
    '001320'='Intel'; '001517'='Intel'; '3C970E'='Intel'; '8086F2'='Intel'; 'A0A8CD'='Intel'; '00E04C'='Realtek'; '525400'='VM/QEMU'
    '080027'='VirtualBox'; '000569'='VMware'; '000C29'='VMware'; '005056'='VMware'; '0003FF'='Microsoft'; '001DD8'='Microsoft'; '0017FA'='Microsoft'
    '7C1E52'='Microsoft'; '0050F2'='Microsoft'; '28187C'='Apple'; '3C0754'='Apple'; 'A8667F'='Apple'; 'F0DBE2'='Apple'; '001451'='Apple'
    '0017F2'='Apple'; '001EC2'='Apple'; 'DC2B2A'='Apple'; 'B8C75D'='Apple'; '00265E'='Samsung'; '0012FB'='Samsung'; '5CF6DC'='Samsung'
    'E8508B'='Samsung'; '8425DB'='Samsung'; 'F008F1'='Samsung'; '002454'='Samsung'; '0024E9'='Samsung'; 'AC5F3E'='Samsung'
    '001A11'='Google'; 'F4F5E8'='Google'; '3C5AB4'='Google'; '00C049'='U.S.Robotics'; '001632'='Samsung'; 'B827EB'='Raspberry Pi'
    'DCA632'='Raspberry Pi'; 'E45F01'='Raspberry Pi'; '2CCF67'='Raspberry Pi'; '001132'='Synology'; '0011D8'='Asustek'; '2C56DC'='Asustek'
    '1C872C'='Asustek'; '04D4C4'='Asustek'; '50465D'='Asustek'; '00E018'='Asustek'; '7824AF'='Asustek'; '04421A'='Asustek'; 'AC220B'='Asustek'
    'FCAA14'='Giga-Byte'; '000423'='Intel'; '0016EA'='Intel'; '9CB6D0'='Realtek'; '000E2E'='Edimax'; '801F02'='Edimax'; '74DA38'='Edimax'
    'C83A35'='Tenda'; 'C8787D'='Tenda'; '0023CD'='Tenda'; 'DC5726'='Huawei'; '00259E'='Huawei'; '283152'='Huawei'; '4C5499'='Huawei'
    '001E10'='Huawei'; '005A13'='Huawei'; '041027'='Dell'; '00188B'='Dell'; '14FEB5'='Dell'; '18A99B'='Dell'; 'B8CA3A'='Dell'; 'F8BC12'='Dell'
    '0024E8'='Dell'; '008088'='Brother'; '30055C'='Brother'; '001BA9'='Brother'; '0080777'='Brother'; 'B422C7'='Hikvision'; '4CBD8F'='Hikvision'
    'BCAD28'='Hikvision'; '44191C'='Dahua'; '3CEF8C'='Dahua'; '902B34'='Giga-Byte'; 'C037AC'='Grandstream'; '000B82'='Grandstream'
}
function Maker($mac) {
    if (-not $mac) { return '' }
    $p = ($mac -replace '[-:]', '').ToUpper()
    if ($p.Length -lt 6) { return '' }
    if ($oui.ContainsKey($p.Substring(0, 6))) { return $oui[$p.Substring(0, 6)] }
    # Locally-administered bit set = random/private MAC (phones use these)
    $b = [Convert]::ToInt32($p.Substring(0, 2), 16)
    if ($b -band 2) { return '(random/private MAC)' }
    return ''
}
# Pick the active IPv4 networks to scan
$nets = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
    ForEach-Object { $a = Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue; if ($a.Status -eq 'Up' -and -not $a.Virtual -and $a.InterfaceDescription -notmatch 'Hyper-V|Virtual|WSL|Loopback|VPN|TAP|Default Switch') { [pscustomobject]@{ IP = $_.IPAddress; Prefix = $_.PrefixLength; If = $a.Name } } } | Sort-Object IP -Unique)
if (-not $nets) { Write-Host '  Only virtual adapters are up (Hyper-V / WSL / VPN). Connect to a real network and run again.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch {}; exit 0 }
if (-not $nets) { Write-Host '  No active network found.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch {}; exit 0 }
foreach ($net in $nets) {
    $o = $net.IP.Split('.')
    $base = $o[0] + '.' + $o[1] + '.' + $o[2] + '.'
    Sec ('Network ' + $base + '0/' + $net.Prefix + '  on ' + $net.If + '  (this PC: ' + $net.IP + ')')
    if ($net.Prefix -lt 24) { Write-Host ('  Large network - scanning ' + $base + '1-254 only (the ' + $net.IP + ' block).') -ForegroundColor DarkGray }
    elseif ($net.Prefix -gt 24) { Write-Host '  Scanning the whole small subnet.' -ForegroundColor DarkGray }
    Write-Host '  Pinging 1-254 ...' -ForegroundColor DarkGray
    # Async ping sweep - fills the ARP cache even for hosts we do not list
    $pings = 1..254 | ForEach-Object { (New-Object Net.NetworkInformation.Ping).SendPingAsync(($base + $_), 500) }
    try { [Threading.Tasks.Task]::WaitAll($pings) } catch {}
    $alive = @{}
    for ($i = 0; $i -lt 254; $i++) { try { if ($pings[$i].Result.Status -eq 'Success') { $alive[$base + ($i + 1)] = $pings[$i].Result.RoundtripTime } } catch {} }
    # ARP table gives MAC for everything that answered
    $arp = @{}
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.LinkLayerAddress -and $_.State -in 'Reachable', 'Stale', 'Permanent', 'Delay' -and $_.IPAddress -like ($base + '*') } | ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress }
    # Drop the network (.0) and broadcast (.255) addresses
    $ips = @($alive.Keys + $arp.Keys | Sort-Object -Unique { [int]($_.Split('.')[3]) } | Where-Object { $_.Split('.')[3] -notin '0', '255' })
    $rows = foreach ($ip in $ips) {
        $mac = $arp[$ip]
        if ($mac -match '^(FF-FF-FF-FF-FF-FF|FFFFFFFFFFFF)$' -or $mac -match '^(01-00-5E|33-33|01-00)') { continue }
        $name = ''
        try { $name = ([Net.Dns]::GetHostEntryAsync($ip).Result).HostName } catch {}
        if ($name -eq $ip) { $name = '' }
        [pscustomobject]@{
            IP = $ip
            Name = $(if ($name) { ($name -split '\.')[0] } else { '' })
            MAC = $(if ($mac) { $mac.ToUpper() } else { '' })
            Maker = Maker $mac
            ms = $(if ($alive.ContainsKey($ip)) { [string]$alive[$ip] } else { '-' })
            This = $(if ($ip -eq $net.IP) { '<< this PC' } elseif ($ip -eq (Get-NetRoute -InterfaceAlias $net.If -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop) { '<< router' } else { '' })
        }
    }
    $rows | Format-Table @{ n = 'IP'; e = { $_.IP } }, @{ n = 'Name'; e = { $_.Name } }, MAC, Maker, @{ n = 'Ping'; e = { $_.ms } }, This -AutoSize | Out-String -Width 200 | Write-Host
    Write-Host ('  Devices found on this network: ' + $rows.Count) -ForegroundColor Green
    $rand = @($rows | Where-Object { $_.Maker -eq '(random/private MAC)' }).Count
    if ($rand) { Write-Host ('  ' + $rand + ' use a random/private MAC - usually phones with "private address" Wi-Fi on. Normal.') -ForegroundColor DarkGray }
    Write-Host '  Device you do not recognise? Match its MAC maker, or turn devices off one by one to see which drops.'
}
Write-Host ''
Write-Host '  Note: the true count of connected users is on the router (DHCP client list / Wi-Fi client list).'
Write-Host '  A ping scan misses devices set to ignore ping. Option 83 [2] opens the router.'
try { Stop-Transcript | Out-Null } catch {}
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-NETSCAN-END

::PS-WIFISIGNAL-BEGIN
# Wi-Fi signal quality and interference. Read-only.
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_WiFiSignal_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
try { Start-Transcript -Path $report -Force | Out-Null } catch {}
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
function Flag($t) { Write-Host ('   [!] ' + $t) -ForegroundColor Yellow }
function Pct2dBm($p) { if ($p -le 0) { return -100 } elseif ($p -ge 100) { return -50 } else { return [int](($p / 2) - 100) } }
$raw = (netsh wlan show interfaces) 2>$null
if (-not ($raw -match 'SSID')) { Write-Host '  No Wi-Fi adapter, or Wi-Fi is off. This PC may be on a cable.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch {}; exit 0 }
function Field($name) { $m = $raw | Select-String ('^\s*' + $name + '\s*:\s*(.+)$') | Select-Object -First 1; if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { '' } }
$ssid = Field 'SSID'; $bssid = Field 'BSSID'; $band = Field 'Band'; $chan = Field 'Channel'; $radio = Field 'Radio type'
$rx = Field 'Receive rate \(Mbps\)'; $tx = Field 'Transmit rate \(Mbps\)'; $sigPct = (Field 'Signal') -replace '%', ''
Sec 'This PC Wi-Fi'
if (-not $ssid) { Write-Host '  Not connected to Wi-Fi right now.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch {}; exit 0 }
$dbm = if ($sigPct) { Pct2dBm ([int]$sigPct) } else { $null }
Write-Host ('   Network:  ' + $ssid + '   Radio: ' + $radio + '   Band: ' + $band + '   Channel: ' + $chan)
Write-Host ('   Speed:    receive ' + $rx + ' Mbps   send ' + $tx + ' Mbps')
$rating = if ($dbm -ge -60) { 'Green' } elseif ($dbm -ge -70) { 'Yellow' } else { 'Red' }
$word = if ($dbm -ge -50) { 'excellent' } elseif ($dbm -ge -60) { 'good' } elseif ($dbm -ge -67) { 'OK' } elseif ($dbm -ge -70) { 'weak' } else { 'very weak' }
Write-Host ('   Signal:   ' + $sigPct + '%  =  about ' + $dbm + ' dBm  (' + $word + ')') -ForegroundColor $rating
Write-Host '   Guide: -50 excellent, -60 good, -67 fine for video calls, -70 weak, -80 drops.' -ForegroundColor DarkGray
if ($dbm -lt -67) { Flag 'Signal is weak here. Move closer to the router / access point, or add an access point or mesh node on this floor.' }
if ($dbm -lt -70) { Flag 'At this level video calls and file copies will stall. A wire or a closer AP is the real fix - a repeater halves speed.' }
if ($band -match '2\.4') { Write-Host '   On 2.4 GHz: longer range but slower and more crowded. If the device is near the router, switch it to 5 GHz.' -ForegroundColor DarkGray }

Sec 'Other Wi-Fi nearby - interference'
$nraw = (netsh wlan show networks mode=bssid) 2>$null
$aps = New-Object System.Collections.ArrayList; $cur = $null
foreach ($l in $nraw) {
    if ($l -match '^SSID\s+\d+\s*:\s*(.*)$') { $cur = @{ SSID = $Matches[1].Trim() } }
    elseif ($cur -and $l -match '^\s*Signal\s*:\s*(\d+)%') { $cur.Pct = [int]$Matches[1] }
    elseif ($cur -and $l -match '^\s*Channel\s*:\s*(\d+)') { $cur.Ch = [int]$Matches[1]; [void]$aps.Add([pscustomobject]@{ SSID = $(if ($cur.SSID) { $cur.SSID } else { '(hidden)' }); Ch = $cur.Ch; Pct = $cur.Pct; dBm = Pct2dBm $cur.Pct }); $cur.SSID2 = $true }
}
$mine = [int]($chan -as [int])
Write-Host ('   ' + $aps.Count + ' Wi-Fi networks in range. This PC is on channel ' + $mine + '.')
$aps | Sort-Object Pct -Descending | Select-Object -First 15 | ForEach-Object {
    $mark = if ($_.Ch -eq $mine -and $_.SSID -ne $ssid) { '  <-- SAME channel as you' } elseif ($_.SSID -eq $ssid) { '  (your network)' } else { '' }
    $c = if ($_.Ch -eq $mine -and $_.SSID -ne $ssid) { 'Yellow' } else { 'Gray' }
    Write-Host ('     ch ' + ([string]$_.Ch).PadLeft(3) + '   ' + ([string]$_.dBm).PadLeft(4) + ' dBm   ' + $_.SSID + $mark) -ForegroundColor $c
}
$same = @($aps | Where-Object { $_.Ch -eq $mine -and $_.SSID -ne $ssid })
if ($same.Count -ge 1 -and $mine) {
    Flag ($same.Count.ToString() + ' other network(s) share your channel ' + $mine + ' - this slows Wi-Fi and causes drops.')
    if ($band -match '2\.4') {
        $use = @{}; 1..11 | ForEach-Object { $use[$_] = 0 }
        foreach ($a in $aps) { foreach ($ch in 1, 6, 11) { if ([Math]::Abs($a.Ch - $ch) -le 2) { $use[$ch] += [Math]::Max(1, $a.Pct) } } }
        $best = 1, 6, 11 | Sort-Object { $use[$_] } | Select-Object -First 1
        Write-Host ('   Fix: in the router Wi-Fi settings set the 2.4 GHz channel to ' + $best + ' (least busy of 1/6/11 here). Use only 1, 6 or 11.') -ForegroundColor Green
    } else {
        Write-Host '   Fix: set the 5 GHz channel to Auto, or pick a high channel (149-161) that no one above uses. 5 GHz has many free channels.' -ForegroundColor Green
    }
} else { Write-Host '   OK - no other Wi-Fi on your exact channel.' -ForegroundColor Green }
Write-Host ''
Write-Host '  Weak signal on many PCs = too few access points for the area. One router cannot cover a whole office -'
Write-Host '  add access points or a mesh so every room is better than -67 dBm. Thick walls and metal cut signal most.'
try { Stop-Transcript | Out-Null } catch {}
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-WIFISIGNAL-END

::PS-BANDWIDTH-BEGIN
# Who is using bandwidth. $env:BWMODE: LOCAL | ROUTER | SNMP
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
$gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop

if ($env:BWMODE -eq 'LOCAL') {
    Sec 'Top talkers on THIS PC - live'
    Write-Host '  Only this PC is measured. Watching 5 seconds...' -ForegroundColor DarkGray
    # Total throughput from the active adapter
    $ad = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Sort-Object LinkSpeed -Descending | Select-Object -First 1
    $s1 = Get-NetAdapterStatistics -Name $ad.Name -ErrorAction SilentlyContinue
    # Per-process bytes via the TCP/UDP ETW counters if present, else connection count as a guide
    $have = Get-Counter -ListSet 'Network Interface' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    $s2 = Get-NetAdapterStatistics -Name $ad.Name -ErrorAction SilentlyContinue
    if ($s1 -and $s2) {
        $down = ($s2.ReceivedBytes - $s1.ReceivedBytes) / 5 / 1KB
        $up = ($s2.SentBytes - $s1.SentBytes) / 5 / 1KB
        Write-Host ('   ' + $ad.Name + ':  download ' + ('{0:N0}' -f $down) + ' KB/s   upload ' + ('{0:N0}' -f $up) + ' KB/s') -ForegroundColor White
    }
    # Processes with internet connections = the likely bandwidth users
    $procs = @{}; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object { $procs[[int]$_.ProcessId] = $_.Name }
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|fe80)' }
    $byProc = $conns | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 12
    if ($byProc) {
        Write-Host ''
        Write-Host '   Programs with the most internet connections right now:'
        $byProc | ForEach-Object {
            $nm = $procs[[int]$_.Name]; if (-not $nm) { $nm = 'PID ' + $_.Name }
            Write-Host ('     ' + ([string]$_.Count).PadLeft(3) + ' connection(s)   ' + $nm)
        }
        Write-Host ''
        Write-Host '   Exact per-program KB/s: opening Resource Monitor - Network tab (sort by Total B/sec).' -ForegroundColor Green
        Start-Process resmon.exe -ErrorAction SilentlyContinue
    } else { Write-Host '   No internet connections right now.' }
    Write-Host ''
    Write-Host '   To cap or stop a heavy program use option 66. For OTHER devices on the network use [2] or [3].'
    exit 0
}

if ($env:BWMODE -eq 'ROUTER') {
    Sec 'Read bandwidth from the router'
    if (-not $gw) { Write-Host '  No router (gateway) found.' -ForegroundColor Yellow; exit 0 }
    Write-Host ('   Your router address: http://' + $gw) -ForegroundColor White
    Write-Host '   Opening it in the browser. Sign in with the router admin password'
    Write-Host '   (on a sticker under the router, or ask whoever set it up).'
    Start-Process ('http://' + $gw) -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '   Where to look (names change by brand):'
    Write-Host '     - Connected users / count:  "Attached Devices", "Client List", "DHCP Clients", "Device Map"'
    Write-Host '     - Per-device bandwidth:     "Traffic Monitor", "QoS", "Bandwidth Control", "Traffic Meter", "Statistics"'
    Write-Host '     - Limit a device:           "QoS" or "Bandwidth Control" - set a max up/down per IP or MAC'
    Write-Host '     - Wi-Fi channel (option 82): "Wireless" - "Channel"'
    Write-Host ''
    Write-Host '   Many basic routers show the client list but NOT per-device bandwidth. For that you need a'
    Write-Host '   router with traffic monitoring (MikroTik, Ubiquiti, ASUS, pfSense) or a managed switch - then use [3].'
    Write-Host '   Tip: give important devices a fixed IP (DHCP reservation) so the names stay readable.'
    exit 0
}

if ($env:BWMODE -eq 'SNMP') {
    Sec 'Per-port bandwidth by SNMP'
    Write-Host '  Works only if the router / switch has SNMP turned on (v1 or v2c) and you know the community string.'
    Write-Host '  SNMP is usually off by default - turn it on in the device first, read-only community is enough.'
    Write-Host ''
    $target = Read-Host ('  Router / switch IP [' + $gw + ']'); if (-not $target) { $target = $gw }
    if (-not $target) { Write-Host '  No address given.' -ForegroundColor Yellow; exit 0 }
    $comm = Read-Host '  SNMP community string [public]'; if (-not $comm) { $comm = 'public' }
    # --- Minimal SNMP v2c GET-NEXT walker (no external tools) ---
    function New-Len($n) { if ($n -lt 128) { return , [byte]$n } $b = @(); while ($n -gt 0) { $b = , [byte]($n -band 0xFF) + $b; $n = $n -shr 8 }; return @([byte](0x80 -bor $b.Count)) + $b }
    function Enc-OID($oid) {
        $p = $oid.TrimStart('.').Split('.') | ForEach-Object { [int]$_ }
        $b = New-Object Collections.Generic.List[byte]; $b.Add([byte](40 * $p[0] + $p[1]))
        for ($i = 2; $i -lt $p.Count; $i++) { $v = $p[$i]; if ($v -lt 128) { $b.Add([byte]$v) } else { $s = New-Object Collections.Generic.List[byte]; $s.Insert(0, [byte]($v -band 0x7F)); $v = $v -shr 7; while ($v -gt 0) { $s.Insert(0, [byte](($v -band 0x7F) -bor 0x80)); $v = $v -shr 7 }; $b.AddRange($s) } }
        return @([byte]0x06) + @(New-Len $b.Count) + $b.ToArray()
    }
    function Enc-Int($n) { $b = [BitConverter]::GetBytes([int]$n); [array]::Reverse($b); $i = 0; while ($i -lt 3 -and $b[$i] -eq 0 -and ($b[$i + 1] -band 0x80) -eq 0) { $i++ }; $b = $b[$i..3]; return @([byte]0x02) + @(New-Len $b.Count) + $b }
    function Enc-Str($s) { $by = [Text.Encoding]::ASCII.GetBytes($s); return @([byte]0x04) + @(New-Len $by.Count) + $by }
    function Enc-Seq($tag, $payload) { return @([byte]$tag) + @(New-Len $payload.Count) + $payload }
    $reqId = 1
    function SnmpNext($oid) {
        $vb = Enc-Seq 0x30 (@(Enc-OID $oid) + @([byte]0x05, [byte]0x00))
        $vbl = Enc-Seq 0x30 $vb
        $pdu = Enc-Seq 0xA1 (@(Enc-Int ($script:reqId++)) + @(Enc-Int 0) + @(Enc-Int 0) + $vbl)
        $msg = Enc-Seq 0x30 (@(Enc-Int 1) + @(Enc-Str $comm) + $pdu)
        $u = New-Object Net.Sockets.UdpClient; $u.Client.ReceiveTimeout = 2000
        try {
            $u.Connect($target, 161); [void]$u.Send([byte[]]$msg, $msg.Count)
            $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any), 0
            $resp = $u.Receive([ref]$ep)
        } catch { return $null } finally { $u.Close() }
        return $resp
    }
    function Parse-TLV($bytes, [ref]$pos) {
        $tag = $bytes[$pos.Value]; $pos.Value++
        $len = $bytes[$pos.Value]; $pos.Value++
        if ($len -band 0x80) { $n = $len -band 0x7F; $len = 0; for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $bytes[$pos.Value]; $pos.Value++ } }
        $val = $bytes[$pos.Value..($pos.Value + $len - 1)]; $pos.Value += $len
        return @{ Tag = $tag; Val = $val }
    }
    function Read-OIDval($resp) {
        # returns @{ OID=..; Type=..; Int=..; Str=.. } of the first varbind, or $null
        try {
            $p = 0; $seq = Parse-TLV $resp ([ref]$p)              # outer seq - descend
            $pp = 0; $b = $seq.Val
            $null = Parse-TLV $b ([ref]$pp)                        # version
            $null = Parse-TLV $b ([ref]$pp)                        # community
            $pduT = Parse-TLV $b ([ref]$pp)                        # PDU
            $pb = $pduT.Val; $q = 0
            $null = Parse-TLV $pb ([ref]$q); $err = Parse-TLV $pb ([ref]$q); $null = Parse-TLV $pb ([ref]$q)
            if ($err.Val[0] -ne 0) { return @{ Err = $err.Val[0] } }
            $vbl = Parse-TLV $pb ([ref]$q); $vb = $vbl.Val; $r = 0
            $one = Parse-TLV $vb ([ref]$r); $ob = $one.Val; $s = 0
            $oidT = Parse-TLV $ob ([ref]$s)
            # decode OID
            $ov = $oidT.Val; $oid = '' + [int]($ov[0] / 40) + '.' + [int]($ov[0] % 40); $i = 1
            while ($i -lt $ov.Count) { $v = 0; do { $v = ($v -shl 7) -bor ($ov[$i] -band 0x7F); $c = $ov[$i] -band 0x80; $i++ } while ($c); $oid += '.' + $v }
            $valT = Parse-TLV $ob ([ref]$s)
            $out = @{ OID = $oid; Tag = $valT.Tag }
            if ($valT.Tag -in 0x02, 0x41, 0x42, 0x43, 0x46) { $n = [uint64]0; foreach ($byte in $valT.Val) { $n = ($n -shl 8) -bor $byte }; $out.Int = $n }
            elseif ($valT.Tag -eq 0x04) { $out.Str = [Text.Encoding]::ASCII.GetString($valT.Val) }
            return $out
        } catch { return $null }
    }
    function Walk($rootOid) {
        $res = @{}; $cur = $rootOid; $guard = 0
        while ($guard -lt 300) {
            $guard++
            $resp = SnmpNext $cur
            if (-not $resp) { return $null }   # no reply = SNMP off / wrong community / blocked
            $v = Read-OIDval $resp
            if (-not $v -or $v.Err) { break }
            if ($v.OID -notlike ($rootOid + '.*')) { break }
            $res[$v.OID.Substring($rootOid.Length + 1)] = $v
            $cur = $v.OID
        }
        return $res
    }
    Write-Host ('  Asking ' + $target + ' for interface names...') -ForegroundColor DarkGray
    $descr = Walk '1.3.6.1.2.1.2.2.1.2'           # ifDescr
    if ($null -eq $descr) {
        Write-Host '  No SNMP reply. Likely: SNMP is off on the device, the community string is wrong, or a firewall blocks UDP 161.' -ForegroundColor Yellow
        Write-Host '  Turn on SNMP (read-only) on the router/switch and try again, or use [2] to read the web page.'
        exit 0
    }
    if ($descr.Count -eq 0) { Write-Host '  SNMP replied but returned no interfaces.' -ForegroundColor Yellow; exit 0 }
    # 64-bit counters first (ifHCInOctets/ifHCOutOctets), fall back to 32-bit
    function Snap {
        $in = Walk '1.3.6.1.2.1.31.1.1.1.6'; $out = Walk '1.3.6.1.2.1.31.1.1.1.10'
        if (-not $in -or $in.Count -eq 0) { $in = Walk '1.3.6.1.2.1.2.2.1.10'; $out = Walk '1.3.6.1.2.1.2.2.1.16' }
        return @{ In = $in; Out = $out; T = Get-Date }
    }
    $a = Snap
    Write-Host '  Measuring for 5 seconds...' -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
    $b = Snap
    $secs = ($b.T - $a.T).TotalSeconds
    Write-Host ''
    $rows = foreach ($k in ($descr.Keys | Sort-Object { [int]$_ })) {
        $name = $descr[$k].Str
        if (-not $a.In[$k] -or -not $b.In[$k]) { continue }
        $di = [double]($b.In[$k].Int - $a.In[$k].Int); $do = [double]($b.Out[$k].Int - $a.Out[$k].Int)
        if ($di -lt 0 -or $do -lt 0) { continue }   # counter wrapped
        [pscustomobject]@{ Port = $name; DownKBs = [math]::Round($di / $secs / 1KB, 1); UpKBs = [math]::Round($do / $secs / 1KB, 1) }
    }
    $rows = @($rows | Where-Object { $_.DownKBs -gt 0 -or $_.UpKBs -gt 0 } | Sort-Object { $_.DownKBs + $_.UpKBs } -Descending)
    if ($rows) {
        $rows | Format-Table @{ n = 'Port / Interface'; e = { $_.Port } }, @{ n = 'Download KB/s'; e = { '{0:N1}' -f $_.DownKBs } }, @{ n = 'Upload KB/s'; e = { '{0:N1}' -f $_.UpKBs } } -AutoSize | Out-String -Width 200 | Write-Host
        Write-Host '  On a switch each port is one device/room. The busiest port is the heaviest user.' -ForegroundColor Green
        Write-Host '  Match a port to a device in the switch admin page, then limit it there (QoS / rate limit).'
    } else { Write-Host '  SNMP worked but no traffic moved during the 5 seconds. Try again under load.' -ForegroundColor Yellow }
    exit 0
}
::PS-BANDWIDTH-END

::PS-OOBE-BEGIN
# Windows 11 setup without a Microsoft account. $env:OOBEMODE: ALLOWNRO | LOCALONLY | CREATE
# Microsoft keeps removing these workarounds in new builds, so the menu offers three.
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
Write-Host ('  Windows: ' + $cv.ProductName + '  ' + $cv.DisplayVersion + '  build ' + $cv.CurrentBuild + '.' + $cv.UBR) -ForegroundColor DarkGray
Write-Host ''
switch ($env:OOBEMODE) {
    'ALLOWNRO' {
        # Same switch the old OOBE\BYPASSNRO command set
        try {
            New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name BypassNRO -Value 1 -Type DWord -ErrorAction Stop
            Write-Host '  Done. Setup restarts in 10 seconds.' -ForegroundColor Green
            Write-Host '  Keep the network UNPLUGGED. On the network screen click "I don''t have internet",'
            Write-Host '  then "Continue with limited setup", and type the local user name.'
            Write-Host '  No such button after restart? This build ignores it - press Shift+F10 again and use [2] or [3].' -ForegroundColor Yellow
            & shutdown.exe /r /t 10
        } catch { Write-Host ('  Could not set it: ' + $_.Exception.Message) -ForegroundColor Red }
    }
    'LOCALONLY' {
        try {
            Start-Process 'ms-cxh:localonly' -ErrorAction Stop
            Write-Host '  The "Create a user for this PC" window should open now.' -ForegroundColor Green
            Write-Host '  Type the user name and password there, then setup continues with that local account.'
            Write-Host '  Nothing opened? This build does not have it - use [1] or [3].' -ForegroundColor Yellow
        } catch { Write-Host '  This Windows build does not have the local account window - use [1] or [3].' -ForegroundColor Yellow }
    }
    'CREATE' {
        $reserved = 'administrator', 'guest', 'defaultaccount', 'wdagutilityaccount', 'defaultuser0', 'user', 'users', 'admin'
        do {
            $name = (Read-Host '  New user name - letters, numbers, . _ - (max 20)').Trim()
            $ok = $name -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$' -and $reserved -notcontains $name.ToLower()
            if ($ok -and (Get-LocalUser -Name $name -ErrorAction SilentlyContinue)) { Write-Host '  That user already exists.' -ForegroundColor Yellow; $ok = $false }
            elseif (-not $ok) { Write-Host '  Not allowed. Use letters and numbers, e.g. anees or it.admin' -ForegroundColor Yellow }
        } until ($ok)
        do {
            $p1 = Read-Host '  Password (hidden, Enter = no password)' -AsSecureString
            $p2 = Read-Host '  Type the password again' -AsSecureString
            $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1); $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
            try { $same = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1) -ceq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) }
            if (-not $same) { Write-Host '  The passwords do not match - try again.' -ForegroundColor Yellow }
        } until ($same)
        try {
            if ($p1.Length -gt 0) { New-LocalUser -Name $name -Password $p1 -FullName $name -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null }
            else { New-LocalUser -Name $name -NoPassword -FullName $name -AccountNeverExpires -ErrorAction Stop | Out-Null; Set-LocalUser -Name $name -PasswordNeverExpires $true -ErrorAction SilentlyContinue }
            # Administrators and Users by SID - works in every Windows language
            Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $name -ErrorAction Stop
            Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $name -ErrorAction SilentlyContinue
            Write-Host ('  Local administrator "' + $name + '" created.') -ForegroundColor Green
        } catch { Write-Host ('  Could not create the user: ' + $_.Exception.Message) -ForegroundColor Red; return }
        if ($env:OOBEFLAG -ne '0x1') { Write-Host '  Windows setup is not running, so nothing else is needed - sign in with the new account.'; return }
        Write-Host ''
        Write-Host '  Next: setup restarts and finishes. Sign in with this account at the login screen.'
        Write-Host '  If setup asks for a Microsoft account again after the restart, press Shift+F10 and use [1].' -ForegroundColor Yellow
        $go = Read-Host '  Restart and finish setup now? [Y/N]'
        if ($go -match '^[Yy]') {
            $oobe = Join-Path $env:SystemRoot 'System32\oobe\msoobe.exe'
            if (Test-Path -LiteralPath $oobe) { Start-Process -FilePath $oobe -WorkingDirectory (Split-Path $oobe) -Wait -ErrorAction SilentlyContinue }
            & shutdown.exe /r /t 5
            Write-Host '  Restarting...' -ForegroundColor Green
        }
    }
}
::PS-OOBE-END

::PS-USBCLEAN-BEGIN
# USB "shortcut virus" removal. Interactive, runs elevated.
# The worm hides the real files, drops autorun.inf / scripts, and adds .lnk
# shortcuts that start it. Only USB drives are touched - never the system disk
# or internal disks. Nothing is changed before the tech says Y.
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
$letters = @()
$letters += @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue | Where-Object Size | ForEach-Object { $_.DeviceID.TrimEnd(':') })
# External USB hard disks report as fixed disks - find them by bus type
$letters += @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsSystem -and -not $_.IsBoot } | Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { [string]$_.DriveLetter })
$letters = @($letters | Where-Object { $_ -and ($_ + ':') -ne $env:SystemDrive } | Sort-Object -Unique)
if (-not $letters) { Write-Host '  No USB drive found. Plug it in, wait until it shows in File Explorer, then run this again.' -ForegroundColor Yellow; exit 0 }
foreach ($l in $letters) { $v = Get-Volume -DriveLetter $l -ErrorAction SilentlyContinue; Write-Host ('  USB drive ' + $l + ':  ' + $v.FileSystemLabel + '  ' + ('{0:N1} GB' -f ($v.Size / 1GB))) }
if ($letters.Count -gt 1) {
    $pick = Read-Host ('  Which drive? ' + ($letters -join ', ') + ' - or A for all')
    if ($pick -notmatch '^[Aa]$') { $letters = @($letters | Where-Object { $_ -eq $pick.Trim().TrimEnd(':').ToUpper() }) }
    if (-not $letters) { Write-Host '  No such USB drive.' -ForegroundColor Yellow; exit 0 }
}
$scriptExt = '\.(vbs|vbe|js|jse|wsf|wsh|hta|scr|pif)$'
$hostRx    = '(cmd|wscript|cscript|rundll32|mshta|powershell|pwsh|regsvr32)\.exe'
$skipRx    = '^(System Volume Information|\$RECYCLE\.BIN)$'
$sh = New-Object -ComObject WScript.Shell
$plan = New-Object System.Collections.ArrayList
$unhide = New-Object System.Collections.ArrayList
foreach ($l in $letters) {
    $root = $l + ':\'
    Sec ('Checking ' + $root)
    $top = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $skipRx })
    $dirs = @($top | Where-Object PSIsContainer | ForEach-Object Name)
    foreach ($f in ($top | Where-Object { -not $_.PSIsContainer })) {
        $hid = [bool]($f.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))
        $why = $null
        if ($f.Name -ieq 'autorun.inf') { $why = 'autorun.inf - starts the virus when the drive is opened' }
        elseif ($f.Name -match $scriptExt) { $why = 'script file in the drive root - typical USB worm' }
        elseif ($f.Extension -ieq '.lnk') {
            $lk = $null; try { $lk = $sh.CreateShortcut($f.FullName) } catch {}
            $tgt = [string]$lk.TargetPath; $arg = [string]$lk.Arguments
            if ($tgt -match $hostRx -or $arg -match $scriptExt) { $why = 'shortcut runs ' + (Split-Path $tgt -Leaf) + ' ' + $arg.Substring(0, [Math]::Min(60, $arg.Length)) }
            elseif ($tgt -like ($root + '*') -and $tgt -match '\.(exe|com|scr)$') { $why = 'shortcut runs a program on the USB: ' + $tgt }
        }
        elseif ($f.Extension -match '^\.(exe|com|scr)$' -and ($hid -or $dirs -contains $f.BaseName)) { $why = $(if ($hid) { 'hidden program in the drive root' } else { 'program with the same name as a folder - folder virus' }) }
        elseif ($f.Extension -match '^\.(bat|cmd|ps1)$' -and $hid) { $why = 'hidden script in the drive root' }
        if ($why) { [void]$plan.Add([pscustomobject]@{ Path = $f.FullName; Why = $why }) }
    }
    # Deeper: folder-named programs and hidden scripts inside folders
    Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName.TrimEnd('\') -ne $root.TrimEnd('\') -and $_.FullName -notmatch '\\(System Volume Information|\$RECYCLE\.BIN)\\' } | ForEach-Object {
        $hid = [bool]($_.Attributes -band [IO.FileAttributes]::Hidden)
        if ($_.Extension -match '^\.(exe|scr)$' -and $_.BaseName -ieq (Split-Path $_.DirectoryName -Leaf)) { [void]$plan.Add([pscustomobject]@{ Path = $_.FullName; Why = 'program named like its folder - folder virus' }) }
        elseif ($hid -and $_.Name -match $scriptExt) { [void]$plan.Add([pscustomobject]@{ Path = $_.FullName; Why = 'hidden script inside a folder' }) }
    }
    # Everything the virus hid
    Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(System Volume Information|\$RECYCLE\.BIN)(\\|$)' -and ($_.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) } | ForEach-Object { if (-not ($plan | Where-Object Path -eq $_.FullName)) { [void]$unhide.Add($_) } }
}
Sec 'Found'
if ($plan.Count -eq 0) { Write-Host '   No virus files found.' -ForegroundColor Green }
else { $plan | ForEach-Object { Write-Host ('   DELETE  ' + $_.Path) -ForegroundColor Red; Write-Host ('           ' + $_.Why) -ForegroundColor DarkGray } }
if ($unhide.Count -gt 0) {
    Write-Host ('   UNHIDE  ' + $unhide.Count + ' hidden file(s) / folder(s) - your real files the virus hid, e.g.:') -ForegroundColor Yellow
    $unhide | Select-Object -First 8 | ForEach-Object { Write-Host ('           ' + $_.FullName) -ForegroundColor DarkGray }
}
if ($plan.Count -gt 0 -or $unhide.Count -gt 0) {
    Write-Host ''
    $ok = Read-Host '   Delete the virus files and unhide your files? [Y/N]'
    if ($ok -match '^[Yy]') {
        $del = 0; $bad = 0
        foreach ($p in $plan) {
            try { $i = Get-Item -LiteralPath $p.Path -Force -ErrorAction Stop; $i.Attributes = 'Normal'; Remove-Item -LiteralPath $p.Path -Force -ErrorAction Stop; $del++ }
            catch { $bad++; Write-Host ('   Could not delete ' + $p.Path + ' - ' + $_.Exception.Message) -ForegroundColor Yellow }
        }
        $un = 0
        foreach ($u in $unhide) { try { $u.Attributes = $u.Attributes -band -bnot ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System); $un++ } catch { $bad++ } }
        Write-Host ('   Deleted ' + $del + ' virus file(s), unhid ' + $un + ' item(s)' + $(if ($bad) { ', ' + $bad + ' failed' } else { '' }) + '.') -ForegroundColor Green
        # Vaccine: a folder named autorun.inf stops most worms from writing their autorun.inf again
        foreach ($l in $letters) {
            $ai = $l + ':\autorun.inf'
            if (-not (Test-Path -LiteralPath $ai)) { try { $d = New-Item -ItemType Directory -Path $ai -ErrorAction Stop; $d.Attributes = 'Hidden, System, ReadOnly' } catch {} }
        }
    } else { Write-Host '   Nothing changed.' }
}
Sec 'Microsoft Defender scan of the USB drive'
if (Get-Command Start-MpScan -ErrorAction SilentlyContinue) {
    $since = Get-Date
    foreach ($l in $letters) {
        Write-Host ('   Scanning ' + $l + ':\ - this can take a few minutes...')
        try { Start-MpScan -ScanType CustomScan -ScanPath ($l + ':\') -ErrorAction Stop } catch { Write-Host ('   Scan failed: ' + $_.Exception.Message) -ForegroundColor Yellow }
    }
    $hits = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $since.AddSeconds(-5) })
    if ($hits) {
        $names = @{}; Get-MpThreat -ErrorAction SilentlyContinue | ForEach-Object { $names[$_.ThreatID] = $_.ThreatName }
        foreach ($h in $hits) { Write-Host ('   Defender removed: ' + $names[$h.ThreatID] + ' - ' + (($h.Resources | Select-Object -First 1) -replace '^file:_', '')) -ForegroundColor Red }
    } else { Write-Host '   Defender found nothing.' -ForegroundColor Green }
} else { Write-Host '   Defender is not available - scan the drive with the installed antivirus.' -ForegroundColor Yellow }
# Stop USB viruses from starting by themselves on this PC
$ex = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if ((Get-ItemProperty -LiteralPath $ex -ErrorAction SilentlyContinue).NoDriveTypeAutoRun -ne 255) {
    Write-Host ''
    $ar = Read-Host '   AutoRun is not fully off on this PC. Turn it off for all drives - recommended? [Y/N]'
    if ($ar -match '^[Yy]') {
        if (-not (Test-Path -LiteralPath $ex)) { New-Item -Path $ex -Force | Out-Null }
        Set-ItemProperty -LiteralPath $ex -Name NoDriveTypeAutoRun -Value 255 -Type DWord
        Write-Host '   AutoRun turned off for all drives.' -ForegroundColor Green
    }
} else { Write-Host ''; Write-Host '   AutoRun is already off on this PC.' -ForegroundColor Green }
Write-Host ''
Write-Host '  If the PC itself ran the virus, also run option 64 - Security Check.'
::PS-USBCLEAN-END

::PS-USBSTATUS-BEGIN
# USB storage control. $env:USBMODE: empty = status only | DISABLE | ENABLE | READONLY | WRITABLE
# Uses the USB storage driver (USBSTOR) plus the Removable Disks policy, the same
# setting Group Policy writes. Keyboards, mice and printers are not affected.
$svc = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
function Set-Pol($read, $write) {
    if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force | Out-Null }
    Set-ItemProperty -LiteralPath $pol -Name Deny_Read -Value $read -Type DWord
    Set-ItemProperty -LiteralPath $pol -Name Deny_Write -Value $write -Type DWord
}
try {
    switch ($env:USBMODE) {
        'DISABLE'  { Set-ItemProperty -LiteralPath $svc -Name Start -Value 4 -Type DWord; Set-Pol 1 1; Write-Host '  USB storage DISABLED.' -ForegroundColor Yellow }
        'ENABLE'   { Set-ItemProperty -LiteralPath $svc -Name Start -Value 3 -Type DWord; Set-Pol 0 0; Write-Host '  USB storage ENABLED.' -ForegroundColor Green }
        'READONLY' { Set-ItemProperty -LiteralPath $svc -Name Start -Value 3 -Type DWord; Set-Pol 0 1; Write-Host '  USB storage is now READ-ONLY.' -ForegroundColor Yellow }
        'WRITABLE' { Set-Pol ([int](Get-ItemProperty -LiteralPath $pol -ErrorAction SilentlyContinue).Deny_Read) 0; Write-Host '  Read-only removed.' -ForegroundColor Green }
    }
    if ($env:USBMODE) { Write-Host '  Unplug and plug in the USB drive again for the change to apply to it.' }
} catch { Write-Host ('  Could not change the setting: ' + $_.Exception.Message) -ForegroundColor Red }
$start = (Get-ItemProperty -LiteralPath $svc -ErrorAction SilentlyContinue).Start
$p = Get-ItemProperty -LiteralPath $pol -ErrorAction SilentlyContinue
$all = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices' -ErrorAction SilentlyContinue).Deny_All
$state = if ($start -eq 4 -or $p.Deny_Read -eq 1 -or $all -eq 1) { 'DISABLED' } elseif ($p.Deny_Write -eq 1) { 'READ-ONLY' } else { 'ENABLED' }
Write-Host ''
Write-Host '  Current USB storage state: ' -NoNewline
Write-Host $state -ForegroundColor $(switch ($state) { 'ENABLED' { 'Green' } 'READ-ONLY' { 'Yellow' } default { 'Red' } })
if ($all -eq 1) { Write-Host '  Policy "All removable storage: deny all access" is ON - set by domain or local Group Policy, remove it there.' -ForegroundColor Yellow }
$usb = @(Get-CimInstance Win32_DiskDrive -Filter "InterfaceType='USB'" -ErrorAction SilentlyContinue)
if ($usb) { foreach ($u in $usb) { Write-Host ('  Plugged in now: ' + $u.Model + '  ' + ('{0:N1} GB' -f ($u.Size / 1GB))) } }
else { Write-Host '  No USB drive plugged in right now.' }
::PS-USBSTATUS-END

::PS-FIREWALL-BEGIN
# Windows Defender Firewall center. $env:FWMODE sets the action.
# STATUS / LISTRULES / PROFILES are read-only and write an HTML report.
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
# A "custom" rule = one you or an app made (built-in Windows rules have a Group like @file.dll,-123)
function Get-CustomRules { Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { -not $_.Group -or $_.Group -notmatch '^@' } }
# Fetch ALL port/app filters once and index by InstanceID - per-rule filter calls are far too slow
$script:portMap = @{}; $script:appMap = @{}; $script:filtersReady = $false
function Init-Filters {
    if ($script:filtersReady) { return }
    Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | ForEach-Object { $script:portMap[$_.InstanceID] = $_ }
    Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | ForEach-Object { $script:appMap[$_.InstanceID] = $_ }
    $script:filtersReady = $true
}
function Rule-Line($r) {
    $pf = $script:portMap[$r.InstanceID]; $ap = $script:appMap[$r.InstanceID]
    $det = if ($pf -and $pf.LocalPort -and $pf.LocalPort -ne 'Any') { $pf.Protocol + ' port ' + ($pf.LocalPort -join ',') } elseif ($ap -and $ap.Program -and $ap.Program -ne 'Any') { 'program ' + $ap.Program } else { 'any' }
    [pscustomobject]@{ Name = $r.DisplayName; Dir = $r.Direction; Action = $r.Action; On = $r.Enabled; What = $det }
}
function Read-Port {
    do { $p = Read-Host '  Port number (1-65535)'; $okp = $p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le 65535; if (-not $okp) { Write-Host '  Enter a number 1-65535.' -ForegroundColor Yellow } } until ($okp)
    return [int]$p
}
function Read-Proto { $pr = Read-Host '  Protocol - T = TCP (default), U = UDP'; if ($pr -match '^[Uu]') { 'UDP' } else { 'TCP' } }

switch ($env:FWMODE) {
    'STATUS' {
        $report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Firewall_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
        $L = New-Object System.Collections.ArrayList; function A($s) { [void]$L.Add([string]$s) }
        A('WINDOWS FIREWALL STATUS'); A('Computer: ' + $env:COMPUTERNAME); A('Generated: ' + (Get-Date)); A('')
        Sec 'Firewall profiles'; A('== Firewall profiles')
        $prof = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $tbl = $prof | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction | Format-Table -AutoSize | Out-String -Width 120
        Write-Host $tbl; A($tbl)
        $off = @($prof | Where-Object { -not $_.Enabled })
        if ($off) { foreach ($o in $off) { $m = '   [!] Firewall is OFF for the ' + $o.Name + ' network - turn it on with option 86 [2].'; Write-Host $m -ForegroundColor Red; A($m) } }
        else { $m = '   OK - firewall is ON for all profiles.'; Write-Host $m -ForegroundColor Green; A($m) }
        Sec 'Active network'; A(''); A('== Active network')
        foreach ($c in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) { $m = '   ' + $c.InterfaceAlias + ' : ' + $c.Name + '  (category: ' + $c.NetworkCategory + ')'; Write-Host $m; A($m) }
        Sec 'Rule counts'; A(''); A('== Rule counts')
        $all = @(Get-NetFirewallRule -ErrorAction SilentlyContinue)
        $cust = @(Get-CustomRules)
        $m = '   Total rules: ' + $all.Count + '   Enabled: ' + @($all | Where-Object Enabled).Count + '   Custom (yours): ' + $cust.Count
        Write-Host $m; A($m)
        A(''); A('== Your custom rules')
        if ($cust.Count) { Init-Filters; $ct = ($cust | ForEach-Object { Rule-Line $_ } | Format-Table Name, Dir, Action, On, What -AutoSize | Out-String -Width 200); Write-Host $ct; A($ct) } else { A('   None.') }
        $L | Set-Content -LiteralPath $report -Encoding UTF8
        Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
    }
    'PROFILES' {
        $report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_FirewallProfiles_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
        $L = New-Object System.Collections.ArrayList; function A($s) { [void]$L.Add([string]$s) }
        A('WINDOWS FIREWALL - NETWORK PROFILES'); A('Generated: ' + (Get-Date)); A('')
        Sec 'Profiles (Domain / Private / Public)'; A('== Profiles')
        foreach ($p in (Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
            $blk = @('   ' + $p.Name, '     Firewall on         : ' + $p.Enabled, '     Default inbound     : ' + $p.DefaultInboundAction, '     Default outbound    : ' + $p.DefaultOutboundAction, '     Notify on block     : ' + $p.NotifyOnListen, '     Allow local rules   : ' + $p.AllowLocalFirewallRules, '')
            $blk | ForEach-Object { Write-Host $_; A($_) }
        }
        Sec 'Which profile is active now'; A('== Active profile')
        foreach ($c in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) { $m = '   ' + $c.InterfaceAlias + ' -> ' + $c.NetworkCategory + ' (' + $c.Name + ')'; Write-Host $m; A($m) }
        $L | Set-Content -LiteralPath $report -Encoding UTF8
        Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
    }
    'LISTRULES' {
        $report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_FirewallRules_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
        $L = New-Object System.Collections.ArrayList; function A($s) { [void]$L.Add([string]$s) }
        A('WINDOWS FIREWALL - CUSTOM RULES'); A('Generated: ' + (Get-Date)); A('Built-in Windows rules are not listed - only rules you or IT Tools created.'); A('')
        Sec 'Custom rules'; A('== Custom rules')
        $cust = @(Get-CustomRules)
        if ($cust.Count) { Init-Filters; $ct = ($cust | ForEach-Object { Rule-Line $_ } | Sort-Object Dir, Name | Format-Table Name, Dir, Action, On, What -AutoSize | Out-String -Width 220); Write-Host $ct; A($ct); A('   Total custom rules: ' + $cust.Count) }
        else { $m = '   None - no custom firewall rules on this PC.'; Write-Host $m -ForegroundColor Green; A($m) }
        $L | Set-Content -LiteralPath $report -Encoding UTF8
        Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
    }
    'ENABLE' {
        Sec 'Enable the firewall for all profiles'
        Set-NetFirewallProfile -All -Enabled True -ErrorAction SilentlyContinue
        Write-Host '  Firewall turned ON for Domain, Private and Public.' -ForegroundColor Green
        Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table -AutoSize
    }
    'DISABLE' {
        Sec 'Disable the firewall'
        Write-Host '  WARNING: turning the firewall OFF exposes this PC on the network. Only do this briefly, to test.' -ForegroundColor Red
        if ((Read-Host '  Really turn the firewall OFF for all profiles? [Y/N]') -match '^[Yy]') {
            Set-NetFirewallProfile -All -Enabled False -ErrorAction SilentlyContinue
            Write-Host '  Firewall turned OFF for all profiles. Turn it back on with option 86 [2].' -ForegroundColor Yellow
            Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table -AutoSize
        } else { Write-Host '  Left unchanged.' }
    }
    'BLOCKPORT' {
        Sec 'Block an inbound port'
        $port = Read-Port; $proto = Read-Proto
        $name = 'IT Tools FW - Block in ' + $proto + ' ' + $port
        if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Host '  That block rule already exists.' -ForegroundColor Yellow }
        else { New-NetFirewallRule -DisplayName $name -Description 'Created by IT Tools' -Direction Inbound -Protocol $proto -LocalPort $port -Action Block -Profile Any | Out-Null; Write-Host ('  Blocked inbound ' + $proto + ' port ' + $port + '.') -ForegroundColor Green }
    }
    'ALLOWPORT' {
        Sec 'Allow an inbound port'
        $port = Read-Port; $proto = Read-Proto
        $name = 'IT Tools FW - Allow in ' + $proto + ' ' + $port
        if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { Write-Host '  That allow rule already exists.' -ForegroundColor Yellow }
        else { New-NetFirewallRule -DisplayName $name -Description 'Created by IT Tools' -Direction Inbound -Protocol $proto -LocalPort $port -Action Allow -Profile Any | Out-Null; Write-Host ('  Allowed inbound ' + $proto + ' port ' + $port + '. Only needed if the firewall default blocks inbound.') -ForegroundColor Green }
    }
    'REMOVERULE' {
        Sec 'Remove a custom rule'
        $cust = @(Get-CustomRules | Sort-Object Direction, DisplayName)
        if (-not $cust.Count) { Write-Host '  No custom rules to remove.' -ForegroundColor Green; break }
        Init-Filters
        $i = 0; foreach ($r in $cust) { $i++; $d = Rule-Line $r; Write-Host ('   [' + $i + '] ' + $d.Dir + '  ' + $d.Action + '  ' + $d.Name + '  (' + $d.What + ')') }
        $sel = Read-Host '  Number to remove (blank = cancel)'
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $cust.Count) {
            $r = $cust[[int]$sel - 1]
            if ((Read-Host ('  Remove "' + $r.DisplayName + '"? [Y/N]')) -match '^[Yy]') { $r | Remove-NetFirewallRule -ErrorAction SilentlyContinue; Write-Host '  Rule removed.' -ForegroundColor Green } else { Write-Host '  Left in place.' }
        } else { Write-Host '  Cancelled.' }
    }
    'BACKUP' {
        Sec 'Backup the firewall configuration'
        $file = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_Firewall_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.wfw')
        $r = netsh advfirewall export "$file" 2>&1
        if (Test-Path -LiteralPath $file) { Write-Host ('  Saved: ' + $file) -ForegroundColor Green; Write-Host '  Restore it later with option 86 [10] Import.' } else { Write-Host ('  Backup failed: ' + ($r -join ' ')) -ForegroundColor Red }
    }
    'IMPORT' {
        Sec 'Import a firewall configuration'
        Write-Host '  This REPLACES all current firewall rules with the ones in the backup file.' -ForegroundColor Yellow
        $file = (Read-Host '  Path to the .wfw backup file').Trim('"')
        if (-not (Test-Path -LiteralPath $file)) { Write-Host '  File not found.' -ForegroundColor Yellow; break }
        if ((Read-Host '  Replace the current firewall config with this file? [Y/N]') -match '^[Yy]') {
            $r = netsh advfirewall import "$file" 2>&1
            Write-Host ('  ' + ($r -join ' ')) -ForegroundColor Green
        } else { Write-Host '  Cancelled.' }
    }
    'RESTORE' {
        Sec 'Restore Windows default firewall'
        Write-Host '  WARNING: this DELETES every custom rule and returns the firewall to Windows defaults.' -ForegroundColor Red
        Write-Host '  Tip: run option 86 [8] Backup first.' -ForegroundColor DarkGray
        if ((Read-Host '  Reset the firewall to defaults now? [Y/N]') -match '^[Yy]') {
            $r = netsh advfirewall reset 2>&1
            Write-Host ('  ' + ($r -join ' ')) -ForegroundColor Green
            Write-Host '  Firewall reset to Windows defaults (firewall left ON).' -ForegroundColor Green
        } else { Write-Host '  Cancelled.' }
    }
}
::PS-FIREWALL-END

::PS-FILEORG-BEGIN
# File organizer. $env:ORGMODE: ORGANIZE | UNDO
# Safe: only a folder the tech picks, never system folders, never overwrites
# (same names get _1, _2...), writes a manifest so the move can be undone.
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
# Extension -> category. One extension in ONE place only.
$map = [ordered]@{
    Images      = 'jpg jpeg png gif bmp webp svg ico heic heif tif tiff'
    Videos      = 'mp4 mov mkv avi wmv flv webm m4v mpg mpeg 3gp'
    Audio       = 'mp3 wav aac m4a flac ogg oga wma opus mid'
    PDFs        = 'pdf'
    Word        = 'doc docx dot dotx rtf odt'
    Excel       = 'xls xlsx xlsm xlsb ods'
    PowerPoint  = 'ppt pptx pps ppsx odp'
    CSV         = 'csv tsv'
    Text        = 'txt md log ini cfg conf'
    Archives    = 'zip rar 7z tar gz bz2 xz tgz'
    DiskImages  = 'iso img vhd vhdx'
    Apps        = 'exe msi apk appx appxbundle msix'
    Installers  = 'msu cab'
    Emails      = 'msg eml'
    Fonts       = 'ttf otf woff woff2'
    Torrents    = 'torrent'
    Database    = 'db sqlite sqlite3 sql mdb accdb ora bak'
    Code        = 'php js ts jsx tsx html htm css json xml py java c cpp h hpp cs go rb rs sh bat cmd ps1 vbs yml yaml'
    Adobe       = 'psd psb ai eps indd indt idml xd aep prproj abr atn'
    Shortcuts   = 'lnk url'
}
$ext2cat = @{}
foreach ($k in $map.Keys) { foreach ($e in ($map[$k] -split ' ')) { $ext2cat['.' + $e] = $k } }

# Folders we must never reorganize
function Is-Protected($p) {
    $f = $p.TrimEnd('\').ToLower()
    if ($f -match '^[a-z]:$') { return $true }                      # drive root
    $bad = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:windir, 'c:\users', (Split-Path $env:USERPROFILE), $env:ITROOT) | Where-Object { $_ }
    foreach ($b in $bad) { if ($f -eq $b.TrimEnd('\').ToLower()) { return $true } }
    # the user profile root itself (but allow its subfolders like Downloads/Desktop)
    if ($f -eq $env:USERPROFILE.TrimEnd('\').ToLower() -or $f -eq $env:TPROFILE.TrimEnd('\').ToLower()) { return $true }
    if ($f -like ($env:SystemRoot.ToLower() + '\*') -or $f -like ($env:ProgramFiles.ToLower() + '\*')) { return $true }
    return $false
}
function Resolve-Folder($raw) {
    $raw = $raw.Trim().Trim('"')
    if (-not $raw) { return $null }
    $q = @{ 'd' = (Join-Path $env:TPROFILE 'Downloads'); 'e' = (Join-Path $env:TPROFILE 'Desktop'); 'o' = (Join-Path $env:TPROFILE 'Documents') }
    if ($q.ContainsKey($raw.ToLower())) { $raw = $q[$raw.ToLower()] }
    try { $r = (Resolve-Path -LiteralPath $raw -ErrorAction Stop).Path } catch { return $null }
    return $r
}

if ($env:ORGMODE -eq 'UNDO') {
    Sec 'Undo the last organize'
    $raw = Read-Host '  Folder that was organized (full path, or D=Downloads E=Desktop O=Documents)'
    $folder = Resolve-Folder $raw
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { Write-Host '  Folder not found.' -ForegroundColor Yellow; exit 0 }
    $man = Get-ChildItem -LiteralPath $folder -Filter '.ITTools_Organize_*.csv' -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $man) { Write-Host '  No organize history found in that folder - nothing to undo.' -ForegroundColor Yellow; exit 0 }
    $rows = @(Import-Csv -LiteralPath $man.FullName)
    Write-Host ('  Undoing ' + $rows.Count + ' move(s) from ' + $man.Name) -ForegroundColor DarkGray
    $back = 0; $miss = 0
    foreach ($r in ($rows | Sort-Object { $_.To } -Descending)) {
        if (Test-Path -LiteralPath $r.To) {
            $dest = $r.From
            if (Test-Path -LiteralPath $dest) { $dest = Join-Path (Split-Path $r.From) ([IO.Path]::GetFileNameWithoutExtension($r.From) + '_restored' + [IO.Path]::GetExtension($r.From)) }
            try { Move-Item -LiteralPath $r.To -Destination $dest -Force:$false -ErrorAction Stop; $back++ } catch { $miss++ }
        } else { $miss++ }
    }
    # Remove now-empty category folders
    foreach ($cat in (@($map.Keys) + 'NoExtension', 'Others')) {
        $cp = Join-Path $folder $cat
        if ((Test-Path -LiteralPath $cp) -and -not (Get-ChildItem -LiteralPath $cp -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $cp -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $man.FullName -Force -ErrorAction SilentlyContinue
    Write-Host ('  Restored ' + $back + ' file(s)' + $(if ($miss) { ', ' + $miss + ' could not be restored' } else { '' }) + '.') -ForegroundColor Green
    exit 0
}

# ORGANIZE
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_FileOrganizer_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
$L = New-Object System.Collections.ArrayList
function Add($s) { [void]$L.Add([string]$s) }
Sec 'Choose a folder to organize'
Write-Host '  Type a full path, or a quick pick:  D = Downloads   E = Desktop   O = Documents'
$raw = Read-Host '  Folder'
$folder = Resolve-Folder $raw
if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { Write-Host '  That folder was not found.' -ForegroundColor Yellow; exit 0 }
if (Is-Protected $folder) { Write-Host ('  REFUSED - ' + $folder + ' is a system / profile-root folder. Pick a normal folder like Downloads.') -ForegroundColor Red; exit 0 }
$files = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '.ITTools_Organize_*' })
if ($files.Count -eq 0) { Write-Host '  No files to organize in that folder (subfolders are left alone).' -ForegroundColor Yellow; exit 0 }
Write-Host ''
Write-Host ('  Folder: ' + $folder) -ForegroundColor White
Write-Host ('  Files to sort: ' + $files.Count + '   (only top-level files move; existing subfolders are not touched)')
$ok = Read-Host '  Organize this folder now? [Y/N]'
if ($ok -notmatch '^[Yy]') { Write-Host '  Cancelled.'; exit 0 }

Add('FILE ORGANIZER'); Add('Computer: ' + $env:COMPUTERNAME); Add('Generated: ' + (Get-Date)); Add('Folder: ' + $folder); Add('Files before: ' + $files.Count); Add('')
$moves = New-Object System.Collections.ArrayList
$counts = @{}
function Unique-Dest($dir, $name) {
    $dest = Join-Path $dir $name
    if (-not (Test-Path -LiteralPath $dest)) { return $dest }
    $b = [IO.Path]::GetFileNameWithoutExtension($name); $x = [IO.Path]::GetExtension($name); $i = 1
    do { $dest = Join-Path $dir ($b + '_' + $i + $x); $i++ } while (Test-Path -LiteralPath $dest)
    return $dest
}
foreach ($f in $files) {
    $cat = if ($f.Extension -eq '') { 'NoExtension' } elseif ($ext2cat.ContainsKey($f.Extension.ToLower())) { $ext2cat[$f.Extension.ToLower()] } else { 'Others' }
    $catDir = Join-Path $folder $cat
    if (-not (Test-Path -LiteralPath $catDir)) { New-Item -ItemType Directory -Path $catDir -Force | Out-Null }
    $dest = Unique-Dest $catDir $f.Name
    try {
        Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
        [void]$moves.Add([pscustomobject]@{ From = $f.FullName; To = $dest })
        $counts[$cat] = [int]$counts[$cat] + 1
    } catch { Add('   Could not move: ' + $f.Name + ' - ' + $_.Exception.Message) }
}
# Manifest for undo (hidden)
if ($moves.Count) {
    $manPath = Join-Path $folder ('.ITTools_Organize_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.csv')
    $moves | Export-Csv -LiteralPath $manPath -NoTypeInformation -Encoding UTF8
    (Get-Item -LiteralPath $manPath -Force).Attributes = 'Hidden'
}
Sec 'Moved'
Add('== Moved')
foreach ($c in ($counts.Keys | Sort-Object { -$counts[$_] })) { $line = '   ' + ([string]$counts[$c]).PadLeft(5) + '  ' + $c; Write-Host $line -ForegroundColor Green; Add($line) }
Write-Host ''
$total = ($counts.Values | Measure-Object -Sum).Sum
Sec 'Result'; Add(''); Add('== Result')
$msg = 'Moved ' + $total + ' file(s) into ' + $counts.Keys.Count + ' folder(s) in ' + $folder
Write-Host ('  ' + $msg) -ForegroundColor Green; Add('   ' + $msg)
Write-Host '  Undo: option 85 [2], then enter the same folder.'; Add('   Undo available: option 85 [2] on this folder.')
$L | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-FILEORG-END

::PS-DISM-BEGIN
# Windows image health. $env:DISMMODE: DIAGNOSE | CLEANUP | REPAIR | SOURCE | SFC
# DIAGNOSE is read-only and writes an HTML report. The others change the system and run live.
$ErrorActionPreference = 'Continue'
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
# Run dism/sfc, show clean output (drop the [====] progress-bar lines), return the text.
# sfc.exe writes UTF-16, so switch the console encoding for it, then restore.
function RunTool($exe, $arglist) {
    Write-Host ('  > ' + $exe + ' ' + ($arglist -join ' ')) -ForegroundColor DarkGray
    $prev = [Console]::OutputEncoding
    if ($exe -match 'sfc') { try { [Console]::OutputEncoding = [Text.Encoding]::Unicode } catch {} }
    try { $out = & $exe @arglist 2>&1 | ForEach-Object { [string]$_ } }
    finally { try { [Console]::OutputEncoding = $prev } catch {} }
    $clean = $out | Where-Object { $_ -notmatch '^\s*\[=*\s*[0-9.]*%?\s*=*\]\s*$' -and $_ -notmatch '^\[=+' -and $_ -notmatch '^\x00*$' }
    foreach ($l in $clean) { if ($l.Trim()) { Write-Host ('    ' + $l) } }
    return @{ Text = ($clean -join "`n"); Code = $LASTEXITCODE }
}
$store = 'DISM'   # dism.exe is in PATH on every supported Windows

if ($env:DISMMODE -eq 'DIAGNOSE') {
    $report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_ImageHealth_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
    $L = New-Object System.Collections.ArrayList
    function Add($s) { [void]$L.Add([string]$s); Write-Host ('  ' + $s) }
    Write-Host ''
    Write-Host ('  Windows image health - read-only - ' + $env:COMPUTERNAME + ' - ' + (Get-Date)) -ForegroundColor White
    [void]$L.Add('WINDOWS IMAGE HEALTH (read-only)'); [void]$L.Add('Computer: ' + $env:COMPUTERNAME); [void]$L.Add('Generated: ' + (Get-Date)); [void]$L.Add('')

    Sec '1. Quick flag check - CheckHealth (1 second)'; [void]$L.Add('== 1. CheckHealth')
    $r = RunTool dism.exe @('/online', '/cleanup-image', '/checkhealth'); [void]$L.Add($r.Text)
    $checkBad = $r.Text -match '(?i)repairable|corrupt|non-repairable'

    Sec '2. Deep scan - ScanHealth (read-only, a few minutes)'; [void]$L.Add(''); [void]$L.Add('== 2. ScanHealth')
    $r2 = RunTool dism.exe @('/online', '/cleanup-image', '/scanhealth'); [void]$L.Add($r2.Text)
    $repairable = $r2.Text -match '(?i)The component store is repairable'
    $healthy = $r2.Text -match '(?i)No component store corruption detected'

    Sec '3. Component store size - WinSxS'; [void]$L.Add(''); [void]$L.Add('== 3. Component store (WinSxS) size')
    $r3 = RunTool dism.exe @('/online', '/cleanup-image', '/analyzecomponentstore'); [void]$L.Add($r3.Text)
    $cleanRec = $r3.Text -match '(?i)Component Store Cleanup Recommended\s*:\s*Yes'

    Sec '4. System file check - verify only (read-only)'; [void]$L.Add(''); [void]$L.Add('== 4. SFC verify-only')
    $r4 = RunTool sfc.exe @('/verifyonly'); [void]$L.Add($r4.Text)
    $sfcBad = $r4.Text -match '(?i)found integrity violations'

    # Recent "cannot repair" lines from the CBS log
    Sec '5. Recent corruption notes in CBS log'; [void]$L.Add(''); [void]$L.Add('== 5. CBS log - recent problems')
    try {
        $cbs = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
        $hits = @(Get-Content -LiteralPath $cbs -Tail 6000 -ErrorAction Stop | Where-Object { $_ -match '(?i)cannot repair|corrupt|SR Repairing|unavailable repair' } | Select-Object -Last 15)
        if ($hits) { foreach ($h in $hits) { Add ('   ' + ($h -replace '\s+', ' ').Trim()) } } else { Add '   OK - no recent corruption notes in CBS log.' }
    } catch { Add '   CBS log not readable right now.' }

    Sec 'Result'; [void]$L.Add(''); [void]$L.Add('== Result')
    if ($healthy -and -not $sfcBad) { $msg = 'HEALTHY - no image corruption found. No repair needed.' }
    elseif ($repairable -or $checkBad -or $sfcBad) { $msg = 'CORRUPTION FOUND - repair needed. Use option 84 [3] (online) or [4] (from ISO).' }
    else { $msg = 'Scan finished - read the sections above.' }
    Write-Host ('  ' + $msg) -ForegroundColor $(if ($msg -like 'HEALTHY*') { 'Green' } elseif ($msg -like 'CORRUPTION*') { 'Red' } else { 'Yellow' }); [void]$L.Add('   ' + $msg)
    if ($cleanRec) { $m2 = 'Component store cleanup is recommended - use option 84 [2] to shrink WinSxS.'; Write-Host ('  ' + $m2) -ForegroundColor Yellow; [void]$L.Add('   ' + $m2) }
    $L | Set-Content -LiteralPath $report -Encoding UTF8
    Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
    exit 0
}

if ($env:DISMMODE -eq 'CLEANUP') {
    Sec 'Component store (WinSxS) - size before'
    [void](RunTool dism.exe @('/online', '/cleanup-image', '/analyzecomponentstore'))
    Write-Host ''
    Write-Host '  StartComponentCleanup removes superseded update files. Safe, but takes 5-20 minutes.'
    $base = Read-Host '  Also run /ResetBase? It makes the cleanup deeper but you can NO LONGER uninstall current updates [y/N]'
    Sec 'Cleaning - please wait'
    $args = @('/online', '/cleanup-image', '/startcomponentcleanup')
    if ($base -match '^[Yy]') { $args += '/resetbase' }
    $r = RunTool dism.exe $args
    Sec 'Component store - size after'
    [void](RunTool dism.exe @('/online', '/cleanup-image', '/analyzecomponentstore'))
    if ($r.Code -eq 0) { Write-Host '  Cleanup finished.' -ForegroundColor Green } else { Write-Host ('  DISM exit code ' + $r.Code + ' - see messages above.') -ForegroundColor Yellow }
    exit 0
}

if ($env:DISMMODE -eq 'REPAIR') {
    Sec 'Repair the Windows image ONLINE (from Windows Update)'
    Write-Host '  Needs a working internet connection. Takes 10-30 minutes. Do not close the window.'
    Write-Host '  If this fails with 0x800f081f, Windows Update is blocked or offline - use option 84 [4] with an ISO.' -ForegroundColor DarkGray
    $r = RunTool dism.exe @('/online', '/cleanup-image', '/restorehealth')
    Sec 'System File Checker'
    $s = RunTool sfc.exe @('/scannow')
    Write-Host ''
    if ($r.Code -eq 0 -and $s.Text -notmatch '(?i)could not|unable to fix') { Write-Host '  Repair finished. If problems remain, reboot and run [1] Diagnose again.' -ForegroundColor Green }
    else { Write-Host '  Repair finished with warnings - read the messages. If it could not fix everything, use option 84 [4] (from ISO).' -ForegroundColor Yellow }
    exit 0
}

if ($env:DISMMODE -eq 'SOURCE') {
    Sec 'Repair from a Windows image file (no internet needed)'
    Write-Host '  First mount the Windows ISO (double-click it) OR have install.wim / install.esd ready.'
    Write-Host '  The ISO must match this Windows version and build.' -ForegroundColor DarkGray
    # Auto-find install.wim / install.esd on all drives
    $found = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
        foreach ($n in 'install.wim', 'install.esd') { $p = Join-Path ($d.Root + 'sources') $n; if (Test-Path -LiteralPath $p) { $found += $p } }
    }
    if ($found) { Write-Host ''; Write-Host '  Found these Windows image files:'; $i = 0; foreach ($f in $found) { $i++; Write-Host ('   [' + $i + '] ' + $f) } }
    $src = Read-Host '  Enter the number above, or type the full path to install.wim / install.esd (blank = cancel)'
    if (-not $src) { Write-Host '  Cancelled.'; exit 0 }
    if ($src -match '^\d+$' -and [int]$src -ge 1 -and [int]$src -le $found.Count) { $src = $found[[int]$src - 1] }
    if (-not (Test-Path -LiteralPath $src)) { Write-Host ('  File not found: ' + $src) -ForegroundColor Red; exit 0 }
    $kind = if ($src -match '\.esd$') { 'esd' } else { 'wim' }
    $sourceArg = '/source:' + $kind + ':' + $src + ':1'
    Sec 'Repairing from the image - please wait'
    Write-Host ('  Using ' + $src + ' (index 1). /LimitAccess stops it from also trying Windows Update.') -ForegroundColor DarkGray
    $r = RunTool dism.exe @('/online', '/cleanup-image', '/restorehealth', $sourceArg, '/limitaccess')
    Sec 'System File Checker'
    $s = RunTool sfc.exe @('/scannow')
    Write-Host ''
    if ($r.Code -eq 0) { Write-Host '  Repair from image finished. Reboot, then run [1] Diagnose to confirm.' -ForegroundColor Green }
    else { Write-Host ('  DISM exit code ' + $r.Code + '. If it says index not found, the ISO edition does not match - try :2 or another ISO.') -ForegroundColor Yellow }
    exit 0
}

if ($env:DISMMODE -eq 'SFC') {
    Sec 'System File Checker - scan and fix protected system files'
    Write-Host '  Takes 5-15 minutes. Do not close the window.'
    $s = RunTool sfc.exe @('/scannow')
    Write-Host ''
    if ($s.Text -match '(?i)did not find any integrity violations') { Write-Host '  OK - no problems found.' -ForegroundColor Green }
    elseif ($s.Text -match '(?i)successfully repaired') { Write-Host '  Found and repaired problems. Reboot.' -ForegroundColor Green }
    elseif ($s.Text -match '(?i)could not|unable to fix') { Write-Host '  Could not fix everything - run option 84 [3] (DISM online) then SFC again.' -ForegroundColor Yellow }
    else { Write-Host '  Finished - read the messages above.' -ForegroundColor Yellow }
    exit 0
}
::PS-DISM-END

::PS-FULLINDEX-BEGIN
# Builds a styled index.html for the FULL IT report bundle ($env:RDIR) and links every file.
try {
    $dir = $env:RDIR
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
    function Enc2($s) { if ('System.Web.HttpUtility' -as [type]) { [Web.HttpUtility]::HtmlEncode([string]$s) } else { ([string]$s) -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' } }
    $nice = @{
        '01_SystemInfo.txt' = 'System information'; '02_Network.txt' = 'Network configuration'; '03_Disks.txt' = 'Disks'
        '04_EventErrors_7days.csv' = 'Event log errors (7 days)'; '05_InstalledSoftware.csv' = 'Installed software'
        '06_Drivers.csv' = 'Drivers'; '06_ProblemDevices.txt' = 'Problem devices'; '07_StoppedAutoServices.txt' = 'Stopped automatic services'
        '08_Updates.txt' = 'Installed Windows updates'; '09_GPResult.html' = 'Group Policy report'; '09_Battery.html' = 'Battery report'
    }
    $files = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -ne 'index.html' } | Sort-Object Name
    $rows = foreach ($f in $files) {
        $label = if ($nice[$f.Name]) { $nice[$f.Name] } else { $f.Name }
        $kb = '{0:N0} KB' -f [math]::Max(1, $f.Length / 1KB)
        '<a class="file" href="./' + [Uri]::EscapeDataString($f.Name) + '"><span class="fn">' + (Enc2 $label) + '</span><span class="fmeta">' + (Enc2 $f.Name) + ' &middot; ' + $kb + '</span></a>'
    }
    $when = (Get-Date).ToString('dddd, dd MMM yyyy  HH:mm')
    $doc = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Full IT Report - $(Enc2 $env:COMPUTERNAME)</title>
<style>
:root{--bg:#0E1120;--card:#141831;--line:#222845;--ink:#E6E8F2;--dim:#8A90AD;--accent:#6366F1}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:'Segoe UI',system-ui,Arial,sans-serif;line-height:1.5}
.wrap{max-width:820px;margin:0 auto;padding:30px 20px 60px}
header{display:flex;align-items:center;gap:15px;margin-bottom:6px}
.logo{width:46px;height:46px;border-radius:12px;background:linear-gradient(135deg,#6366F1,#8B5CF6);display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;font-size:19px}
h1{font-size:22px;margin:0}.sub{color:var(--dim);font-size:13px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0 22px}
.chip{background:var(--card);border:1px solid var(--line);border-radius:9px;padding:7px 12px;font-size:12.5px;color:var(--dim)}.chip b{color:var(--ink)}
.file{display:flex;justify-content:space-between;align-items:center;gap:12px;background:var(--card);border:1px solid var(--line);border-radius:11px;padding:14px 16px;margin-bottom:10px;text-decoration:none;color:var(--ink)}
.file:hover{border-color:var(--accent)}
.fn{font-weight:600;font-size:14.5px}.fmeta{color:var(--dim);font-size:12px}
footer{color:var(--dim);font-size:12px;margin-top:22px;text-align:center}
@media print{body{background:#fff;color:#000}.file,.chip{border-color:#ccc;background:#fff}}
</style></head><body><div class="wrap">
<header><div class="logo">IT</div><div><h1>Full IT Report</h1><div class="sub">Support bundle - $(Enc2 $env:COMPUTERNAME)</div></div></header>
<div class="chips"><div class="chip">Computer <b>$(Enc2 $env:COMPUTERNAME)</b></div><div class="chip">Generated <b>$(Enc2 $when)</b></div><div class="chip">Files <b>$($files.Count)</b></div></div>
<p style="color:var(--dim);font-size:13px;margin:0 0 16px">Click any item to open it. Keep the whole folder together when sending to support.</p>
$($rows -join "`n")
<footer>Generated by IT Tools - get.snapsbilling.com</footer>
</div></body></html>
"@
    [IO.File]::WriteAllText((Join-Path $dir 'index.html'), $doc, (New-Object Text.UTF8Encoding $false))
} catch { }
::PS-FULLINDEX-END

::PS-HTMLREPORT-BEGIN
# Turns a plain report (written by Start-Transcript) into a styled HTML page.
# Called by :DONE for every option that saved a report. $env:REPORTTXT = the .txt.
# A failure here never breaks the tool - :DONE then just opens the .txt.
try {
    try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
    function Enc($s) {
        if ($null -ne ([Web.HttpUtility]).ToString -and ('System.Web.HttpUtility' -as [type])) { return [Web.HttpUtility]::HtmlEncode([string]$s) }
        return (([string]$s) -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
    }
    $txt = $env:REPORTTXT
    if (-not $txt -or -not (Test-Path -LiteralPath $txt) -or $txt -notmatch '\.txt$') { return }
    $html = $txt -replace '\.txt$', '.html'
    $raw = Get-Content -LiteralPath $txt -Raw -ErrorAction Stop
    $all = $raw -split "`r?`n"

    # Drop the PowerShell transcript boilerplate (header / footer blocks)
    $skip = '^\*{5,}$|^Windows PowerShell transcript|^Transcript (started|stopped)|^Start time:|^End time:|^Username:|^RunAs User:|^Config(uration)? Name:|^Machine:|^Host Application:|^Process ID:|^PSVersion:|^PSEdition:|^PSCompatibleVersions:|^BuildVersion:|^CLRVersion:|^WSManStackVersion:|^PSRemotingProtocolVersion:|^SerializationVersion:|^Output file is|^PS [A-Z]:.*>\s*$'
    $body = $all | Where-Object { $_ -notmatch $skip }

    # Report type + time from the file name:  COMPUTER_TypeName_yyyyMMdd_HHmmss
    $base = [IO.Path]::GetFileNameWithoutExtension($txt)
    $parts = $base -split '_'
    $computer = $parts[0]
    $when = ''; $type = 'Report'
    if ($parts.Count -ge 4 -and $parts[-2] -match '^\d{8}$' -and $parts[-1] -match '^\d{6}$') {
        try { $when = [datetime]::ParseExact($parts[-2] + $parts[-1], 'yyyyMMddHHmmss', $null).ToString('dddd, dd MMM yyyy  HH:mm') } catch {}
        $type = ($parts[1..($parts.Count - 3)] -join ' ')
    } elseif ($parts.Count -ge 2) { $type = ($parts[1..($parts.Count - 1)] -join ' ') }
    $type = [regex]::Replace($type, '(?<=[a-z0-9])(?=[A-Z])', ' ')   # SecurityCheck -> Security Check
    if (-not $when) { $when = (Get-Item -LiteralPath $txt).LastWriteTime.ToString('dddd, dd MMM yyyy  HH:mm') }

    $warn = @($body | Where-Object { $_ -match '\[!\]' }).Count
    $statusWord = if ($warn -eq 0) { 'All clear' } else { ($warn.ToString() + ' item(s) to review') }
    $statusCls = if ($warn -eq 0) { 'good' } else { 'attn' }

    # Build cards, one per "== section"; lines before the first section go in Overview
    $sb = New-Object System.Text.StringBuilder
    $open = $false
    $pending = New-Object System.Collections.ArrayList
    foreach ($ln in $body) {
        $t = $ln.TrimEnd()
        if ($t -match '^\s*[-=]{5,}\s*$') { continue }
        # Section header in either style:  "== Title"  or  "=== Title ==="
        if ($t -match '^\s*={2,}\s*(.+?)\s*$') {
            $sectitle = ($Matches[1] -replace '\s*=+\s*$', '').Trim()
            if ($sectitle) {
                if ($pending.Count -and -not $open) { [void]$sb.Append('<section class="card"><h2>Overview</h2><div class="body">'); foreach ($p in $pending) { [void]$sb.Append($p) }; [void]$sb.Append('</div></section>'); $pending.Clear() }
                if ($open) { [void]$sb.Append('</div></section>') }
                [void]$sb.Append('<section class="card"><h2>' + (Enc $sectitle) + '</h2><div class="body">'); $open = $true; continue
            }
        }
        $cls = 'ln'
        if ($t -match '\[!\]') { $cls = 'ln warn' }
        elseif ($t -match '(?i)\b(REVIEW:|ACTIVE threat|HIGH-RISK|FAILED|was CLEARED|INFECTED|^\s*DELETE\b|REMOVE:)') { $cls = 'ln bad' }
        elseif ($t -match '(?i)(^\s*OK\b|no signs|none found|MALWARE: none|No threats|No virus|nobody is connected|RESULT: no|verified|Freed:|^\s*None\b|Devices found)') { $cls = 'ln ok' }
        elseif ($t -match '^\s{5,}\S') { $cls = 'ln dim' }
        $enc = Enc $t
        if ($enc.Trim() -eq '') { $enc = '&nbsp;' }
        $div = '<div class="' + $cls + '">' + $enc + '</div>'
        if ($open) { [void]$sb.Append($div) } else { [void]$pending.Add($div) }
    }
    if ($pending.Count -and -not $open) { [void]$sb.Append('<section class="card"><h2>Report</h2><div class="body">'); foreach ($p in $pending) { [void]$sb.Append($p) }; [void]$sb.Append('</div></section>') }
    elseif ($open) { [void]$sb.Append('</div></section>') }

    $head = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(Enc $type) - $(Enc $computer)</title>
<style>
:root{--bg:#0E1120;--card:#141831;--line:#222845;--ink:#E6E8F2;--dim:#8A90AD;--accent:#6366F1;--ok:#34D399;--warn:#FBBF24;--bad:#F87171}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:'Segoe UI',system-ui,Arial,sans-serif;font-size:14px;line-height:1.5}
.wrap{max-width:1060px;margin:0 auto;padding:26px 20px 60px}
header{display:flex;flex-wrap:wrap;align-items:center;gap:16px;margin-bottom:8px}
.logo{width:46px;height:46px;border-radius:12px;background:linear-gradient(135deg,#6366F1,#8B5CF6);display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff;font-size:19px}
h1{font-size:22px;margin:0}
.sub{color:var(--dim);font-size:13px;margin-top:2px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0 20px}
.chip{background:var(--card);border:1px solid var(--line);border-radius:9px;padding:7px 12px;font-size:12.5px;color:var(--dim)}
.chip b{color:var(--ink);font-weight:600}
.chip.good{border-color:#1f6a4e}.chip.good b{color:var(--ok)}
.chip.attn{border-color:#7a5b16}.chip.attn b{color:var(--warn)}
.bar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin-bottom:18px}
#q{flex:1;min-width:200px;background:var(--card);border:1px solid var(--line);border-radius:9px;color:var(--ink);padding:10px 13px;font-size:14px;outline:none}
#q:focus{border-color:var(--accent)}
.btn{background:var(--card);border:1px solid var(--line);color:var(--ink);border-radius:9px;padding:10px 14px;font-size:13px;cursor:pointer;font-weight:600}
.btn:hover{border-color:var(--accent)}
.card{background:var(--card);border:1px solid var(--line);border-radius:13px;padding:4px 20px 14px;margin:0 0 16px}
.card h2{font-size:15px;color:#A5B4FC;border-bottom:1px solid var(--line);padding:14px 0 10px;margin:0 0 8px}
.body{font-family:'Cascadia Mono',Consolas,'Courier New',monospace;font-size:13px;white-space:pre-wrap;word-break:break-word}
.ln{padding:1px 0}
.ln.dim{color:var(--dim)}
.ln.ok{color:var(--ok)}
.ln.warn{color:var(--warn);background:rgba(251,191,36,.07);border-left:3px solid var(--warn);padding-left:8px;margin:2px 0;border-radius:3px}
.ln.bad{color:var(--bad);font-weight:600}
.hidden{display:none}
footer{color:var(--dim);font-size:12px;margin-top:24px;text-align:center}
mark{background:#4425a3;color:#fff;border-radius:2px}
@media print{body{background:#fff;color:#000}.bar{display:none}.card,.chip{border-color:#ccc;background:#fff}.card h2{color:#2222aa}.ln.dim{color:#555}.ln.ok{color:#0a7a46}.ln.warn{color:#8a5a00;background:#fff8e6}.ln.bad{color:#b00020}}
</style></head><body><div class="wrap">
<header><div class="logo">IT</div><div><h1>$(Enc $type)</h1><div class="sub">IT Tools report</div></div></header>
<div class="chips">
<div class="chip">Computer <b>$(Enc $computer)</b></div>
<div class="chip">Generated <b>$(Enc $when)</b></div>
<div class="chip $statusCls">Status <b>$statusWord</b></div>
</div>
<div class="bar">
<input id="q" placeholder="Filter the report - type to show only matching lines">
<button class="btn" onclick="clr()">Clear</button>
<button class="btn" onclick="window.print()">Print / Save as PDF</button>
</div>
$($sb.ToString())
<footer>Generated by IT Tools - get.snapsbilling.com - static file, safe to email or print.</footer>
</div>
"@
    $js = @'
<script>
var q=document.getElementById('q');
function esc(s){return s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
function clr(){q.value='';flt();}
function flt(){
 var s=q.value.trim().toLowerCase();
 document.querySelectorAll('.card').forEach(function(card){
  var any=false;
  card.querySelectorAll('.ln').forEach(function(l){
   var t=(l.textContent||'').toLowerCase();
   var hit=(!s)||t.indexOf(s)>=0;
   l.classList.toggle('hidden',!hit);
   if(hit)any=true;
   if(s&&hit){l.innerHTML=l.textContent.replace(new RegExp('('+esc(s)+')','ig'),'<mark>$1</mark>');}
   else{l.innerHTML=l.textContent;}
  });
  card.classList.toggle('hidden',!any);
 });
}
q.addEventListener('input',flt);
</script></body></html>
'@
    [IO.File]::WriteAllText($html, ($head + $js), (New-Object Text.UTF8Encoding $false))
} catch { }
::PS-HTMLREPORT-END

::PS-HEALTH-BEGIN
# One colored status line under the main menu header. Runs every time the menu
# is drawn: the result is cached for 60 seconds so going back to the menu is instant.
$cache = if ($env:ITROOT) { Join-Path $env:ITROOT 'bin\health.cache' } else { $null }
if ($cache -and (Test-Path -LiteralPath $cache) -and (Get-Item -LiteralPath $cache).LastWriteTime -gt (Get-Date).AddSeconds(-60)) {
    Write-Host ' ' -NoNewline
    foreach ($l in (Get-Content -LiteralPath $cache)) { $c = $l -split '\|', 3; Write-Host ('  ' + $c[0] + ': ') -NoNewline -ForegroundColor Gray; Write-Host $c[1] -NoNewline -ForegroundColor $c[2] }
    Write-Host ''
    return
}
$saved = New-Object System.Collections.ArrayList
function Part($label, $value, $color) {
    Write-Host ('  ' + $label + ': ') -NoNewline -ForegroundColor Gray; Write-Host $value -NoNewline -ForegroundColor $color
    [void]$saved.Add($label + '|' + $value + '|' + $color)
}
Write-Host ' ' -NoNewline
$d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'") -ErrorAction SilentlyContinue
if ($d -and $d.Size) {
    $pct = [int](100 * $d.FreeSpace / $d.Size)
    Part ('Drive ' + $env:SystemDrive.TrimEnd(':')) ('{0:N0} GB free ({1}%)' -f ($d.FreeSpace / 1GB), $pct) $(if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Green' })
}
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) { $up = (Get-Date) - $os.LastBootUpTime; Part 'Up' ('{0}d {1}h' -f $up.Days, $up.Hours) $(if ($up.TotalDays -gt 14) { 'Yellow' } else { 'Green' }) }
$rb = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
Part 'Restart needed' $(if ($rb) { 'YES' } else { 'no' }) $(if ($rb) { 'Yellow' } else { 'Green' })
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp -and $mp.AMRunningMode -eq 'Normal') {
    $av = if (-not $mp.RealTimeProtectionEnabled) { 'OFF' } elseif ($mp.AntivirusSignatureAge -gt 3) { 'old definitions' } else { 'OK' }
    Part 'Defender' $av $(if ($av -eq 'OK') { 'Green' } else { 'Red' })
} else { Part 'Antivirus' 'other product' 'Gray' }
$net = $false
foreach ($h in @(@('1.1.1.1', 443), @('8.8.8.8', 53))) {
    try { $c = New-Object Net.Sockets.TcpClient; if ($c.ConnectAsync($h[0], $h[1]).Wait(700) -and $c.Connected) { $net = $true }; $c.Close() } catch {}
    if ($net) { break }
}
Part 'Internet' $(if ($net) { 'OK' } else { 'NO' }) $(if ($net) { 'Green' } else { 'Red' })
$rs = @()
if (@(query session 2>$null) -match 'rdp-tcp#\d+\s+\S+\s+\d+\s+Active') { $rs += 'RDP' }
$pn = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object Name)
if ($pn -contains 'TeamViewer_Desktop') { $rs += 'TeamViewer' }
if ($pn -contains 'ScreenConnect.WindowsClient') { $rs += 'ScreenConnect' }
if ($pn -contains 'rustdesk' -and (Get-CimInstance Win32_Process -Filter "Name='rustdesk.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*--cm*' })) { $rs += 'RustDesk' }
Part 'Remote' $(if ($rs) { 'CONNECTED ' + ($rs -join '+') + ' - option 67' } else { 'none' }) $(if ($rs) { 'Red' } else { 'Green' })
Write-Host ''
if ($cache) { try { [IO.File]::WriteAllLines($cache, [string[]]$saved) } catch {} }
::PS-HEALTH-END

::PS-SEARCH-BEGIN
# Keyword search over the menu text of :MENU and :MENU2, plus problem words.
# Query comes from $env:SEARCHQ (never expanded by cmd).
$q = ([string]$env:SEARCHQ).Trim().ToLower()
$txt = [IO.File]::ReadAllText($env:ITSELF)
$opts = @{}
foreach ($blk in [regex]::Matches($txt, '(?ms)^:MENU(?:2|3)?\r?\n(.*?)^set /p')) {
    foreach ($line in ($blk.Groups[1].Value -split "`r?`n" | Where-Object { $_ -match '^echo ' })) {
        foreach ($m in [regex]::Matches($line, '\[(\d+)\]\s+(.+?)(?=\s{2,}|\s*$)')) {
            $n = [int]$m.Groups[1].Value
            if ($n -gt 0) { $opts[$n] = ($m.Groups[2].Value -replace '\^', '').Trim() }
        }
    }
}
# Problem words -> options. Keep numbers in step with the menus.
$tags = @{
    'slow' = '72 60 61 68 17 35 25 22'; 'speed' = '72 60 61 68 83'; 'hang' = '43 14 9 34 77'; 'freeze' = '71 77 34 9 23 22'; 'crash' = '71 77 34 9 23'
    'internet' = '1 4 2 3 5 6 7'; 'network' = '1 2 4 5 7 50 52'; 'dns' = '3 1'; 'vpn' = '52'; 'domain' = '52 11'; 'ip' = '2 55 81'
    'disk' = '70 68 19 61 17 12 22'; 'space' = '68 19 61 17 18'; 'full' = '68 61 17'; 'storage' = '68 19 61'; 'clean' = '17 18 61 68 53 20'
    'junk' = '61 17 68'; 'temp' = '17 61 68'; 'hibernate' = '68 25'; 'wsl' = '68'
    'hacked' = '64 67 66 65'; 'virus' = '64 78 66'; 'malware' = '64 66'; 'trojan' = '64 66'; 'remote' = '67 55 64'; 'anydesk' = '67'
    'teamviewer' = '67'; 'rdp' = '67'; 'spam' = '65'; 'security' = '76 64 67 66 32'; 'defender' = '64'; 'antivirus' = '64'
    'print' = '26 27'; 'scanner' = '26 23'; 'sound' = '24'; 'audio' = '24'; 'mic' = '24 23'
    'battery' = '21 25'; 'sleep' = '25'; 'power' = '25 21'; 'usb' = '78 79 70 73 23'; 'flash' = '78 79'; 'pendrive' = '78 79'; 'shortcut' = '78'; 'autorun' = '78'; 'oobe' = '80'; 'bypass' = '80'; 'setup' = '80'; 'install' = '80'; 'local' = '80 63'; 'microsoft' = '80 63'; 'block' = '79 66'; 'driver' = '73 23'; 'device' = '70 73 23'; 'hardware' = '70 73'; 'bsod' = '71'; 'blue' = '71'; 'performance' = '72'; 'update' = '74 10 41'; 'firewall' = '86 76 64'; 'port' = '86 66 7'; 'rule' = '86'; 'rules' = '86'; 'ports' = '86'; 'allow' = '86'; 'inbound' = '86'; 'outbound' = '86 66'; 'event' = '77 71 34'; 'latency' = '75'; 'wifi' = '82 75 6 5 1'; 'signal' = '82'; 'dbm' = '82'; 'channel' = '82'; 'interference' = '82'; 'bandwidth' = '83 72'; 'scan' = '87 81'; 'devices' = '87 81'; 'lan' = '87 81'; 'nvr' = '87'; 'dvr' = '87'; 'camera' = '87'; 'cctv' = '87'; 'hikvision' = '87'; 'dahua' = '87'; 'fingerprint' = '87'; 'zkteco' = '87'; 'biometric' = '87'; 'printer' = '87 26 27'; 'ipcamera' = '87'; 'identify' = '87'; 'users' = '81 83'; 'connected' = '81 67'; 'snmp' = '83'; 'router' = '83 1'
    'outlook' = '43 46 47 28 45'; 'teams' = '43 20'; 'office' = '44 45 30'; 'word' = '44 45'; 'excel' = '44 45'
    'email' = '43 46 47 65'; 'mail' = '43 46 47 65'; 'onedrive' = '48 49'; 'sharepoint' = '48 45'
    'activate' = '30 31'; 'activation' = '30 31'; 'license' = '30 31'; 'key' = '30'; 'bitlocker' = '32'
    'start' = '56 14'; 'search' = '56 57'; 'icon' = '58'; 'thumbnail' = '58'; 'lock' = '59'; 'explorer' = '14'; 'taskbar' = '14 56'
    'store' = '16 62'; 'apps' = '62 36'; 'password' = '29 51 63'; 'credential' = '29 51'; 'account' = '63 54'; 'profile' = '54 47'
    'drive' = '50 19 68'; 'share' = '50 51'; 'map' = '50'; 'time' = '8'; 'clock' = '8'; 'restart' = '40 14 5'; 'startup' = '35'
    'boot' = '35 25'; 'report' = '37 39 33'; 'error' = '34 9 23'; 'repair' = '84 9 44 10'; 'dism' = '84'; 'sfc' = '84 9'; 'corrupt' = '84 12'; 'image' = '84'; 'winsxs' = '84 61'; 'restorehealth' = '84'; 'componentstore' = '84'; 'organize' = '85'; 'organizer' = '85'; 'sort' = '85'; 'tidy' = '85'; 'messy' = '85'; 'downloads' = '85'; 'folder' = '85'; 'arrange' = '85'; 'browser' = '53'; 'chrome' = '53'; 'edge' = '53'
}
Write-Host ''
if ($q -match '^\d+$') { Write-Host ('  Option ' + $q + ' does not exist. Options are 1-77 (69 opens Diagnostics & Admin).') -ForegroundColor Yellow }
$stop = 'my','pc','is','the','it','me','to','of','and','in','on','at','for','computer','laptop','working','work','problem','issue','please','help','cant','can','does','dont','doesnt','very','too','so','what','why','how','not','no','all','time','times','again','keeps','always'
$words = @($q -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 2 -and $stop -notcontains $_ })
$score = @{}
foreach ($w in $words) {
    # Word start only: "disk" matches "Disk Space", "is" never matches "Disk"
    foreach ($k in $opts.Keys) { if ($opts[$k] -match ('(?i)(^|[^a-z0-9])' + [regex]::Escape($w))) { $score[$k] += 3 } }
    foreach ($tg in $tags.Keys) {
        if ($tg.StartsWith($w) -or ($w.Length -ge 4 -and $w.StartsWith($tg))) {
            $i = 0
            foreach ($n in ($tags[$tg] -split ' ')) { $score[[int]$n] += [Math]::Max(1, 2 - $i); $i++ }
        }
    }
}
$hits = @($score.GetEnumerator() | Where-Object { $opts.ContainsKey([int]$_.Key) } | Sort-Object @{ e = { $_.Value }; Descending = $true }, @{ e = { [int]$_.Key } } | Select-Object -First 14)
if ($hits.Count -eq 0) {
    if ($q -notmatch '^\d+$') { Write-Host ('  Nothing matches "' + $q + '".') -ForegroundColor Yellow }
    Write-Host '  Try a word like: internet, slow, disk, printer, outlook, onedrive, hacked, remote, battery, activation'
} else {
    Write-Host ('  Options for "' + $q + '":') -ForegroundColor Cyan
    Write-Host ''
    $first = $true
    foreach ($h in $hits) {
        $n = [int]$h.Key
        Write-Host ('    [' + $n.ToString().PadLeft(2) + ']  ' + $opts[$n]) -ForegroundColor $(if ($first) { 'Green' } else { 'White' })
        $first = $false
    }
}
::PS-SEARCH-END

::PS-DISKSCAN-BEGIN
# Disk Space Analyzer. Interactive, runs elevated. Explains the big items; only the
# SAFE list (section 6) can be cleaned, and only after the tech picks it and says Y.
$report = Join-Path $env:REPORTROOT ($env:COMPUTERNAME + '_DiskSpace_' + (Get-Date -Format yyyyMMdd_HHmmss) + '.txt')
try { Start-Transcript -Path $report -Force | Out-Null } catch {}
$sd   = $env:SystemDrive
$prof = $env:TPROFILE.TrimEnd('\')
$loc  = $env:TLOCAL
$roam = $env:TROAMING
function GB($b) { '{0,7:N2} GB' -f ([double]$b / 1GB) }
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
function Line($size, $what, $note, $color) {
    if (-not $color) { $color = 'White' }
    Write-Host ('   ' + (GB $size) + '  ') -NoNewline -ForegroundColor $(if ($size -ge 10GB) { 'Red' } elseif ($size -ge 3GB) { 'Yellow' } else { 'Gray' })
    Write-Host ($what.PadRight(44) + ' ') -NoNewline -ForegroundColor $color
    Write-Host $note -ForegroundColor DarkGray
}
# Online-only OneDrive / cloud files use no disk space - never count them
$cloud = 0x400000 -bor 0x40000 -bor 0x1000
function Size($p) {
    if (-not $p -or -not (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { return [double]0 }
    $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($it -and -not $it.PSIsContainer) { return [double]$it.Length }
    $s = [double]0
    Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { if (-not ([int]$_.Attributes -band $cloud)) { $s += $_.Length } }
    return $s
}
function Short($p) { if ($p.Length -gt 44) { '...' + $p.Substring($p.Length - 41) } else { $p } }

Write-Host ''
Write-Host ('  Disk space analysis - ' + $env:COMPUTERNAME + ' - user ' + $env:TUSER + ' - ' + (Get-Date)) -ForegroundColor White
$freeBefore = (Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $sd + "'")).FreeSpace

# 1 ---------------------------------------------------------------
Sec '1. Drives'
foreach ($v in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
    if (-not $v.Size) { continue }
    $pct = [int](100 * $v.FreeSpace / $v.Size)
    $n = [int][Math]::Round(40 * ($v.Size - $v.FreeSpace) / $v.Size)
    Write-Host ('   ' + $v.DeviceID + '  [' + ('#' * $n) + ('.' * (40 - $n)) + ']  ' + (GB $v.FreeSpace).Trim() + ' free of ' + (GB $v.Size).Trim() + '  (' + $pct + '% free)') -ForegroundColor $(if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Green' })
}

# 2 ---------------------------------------------------------------
Sec ('2. Where the space on ' + $sd + ' goes - scanning, please wait...')
$rows = New-Object System.Collections.ArrayList
function Row($what, $bytes, $note) { if ($bytes -gt 50MB) { [void]$rows.Add([pscustomobject]@{ Size = [double]$bytes; Item = $what; Note = $note }) } }
foreach ($f in (Get-ChildItem -LiteralPath ($sd + '\') -Force -File -ErrorAction SilentlyContinue)) {
    switch ($f.Name) {
        'hiberfil.sys' { Row $f.Name $f.Length 'Hibernate file - needed for Hibernate. Only removable: powercfg /h off' }
        'pagefile.sys' { Row $f.Name $f.Length 'Virtual memory - Windows manages it, leave it' }
        'swapfile.sys' { Row $f.Name $f.Length 'Store-app swap file - leave it' }
        default        { Row $f.Name $f.Length 'File in the root of the drive' }
    }
}
$cvol = Get-CimInstance Win32_Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter -eq $sd
$shadow = [double]0
foreach ($ss in (Get-CimInstance Win32_ShadowStorage -ErrorAction SilentlyContinue)) { if ($cvol -and $ss.Volume.DeviceID -eq $cvol.DeviceID) { $shadow += $ss.UsedSpace } }
Row 'Restore points + shadow copies' $shadow 'Old restore points - Disk Cleanup, More Options tab'
$notes = @{
    'Windows' = 'Windows + update store - option 61 runs DISM cleanup'; 'Program Files' = 'Installed 64-bit programs - uninstall unused in Settings, Apps'
    'Program Files (x86)' = 'Installed 32-bit programs - uninstall unused in Settings, Apps'; 'ProgramData' = 'Program data for all users'
    '$Recycle.Bin' = 'Recycle Bin - all users'; 'Windows.old' = 'Previous Windows after upgrade - Disk Cleanup removes it'
    '$WINDOWS.~BT' = 'Windows upgrade files - Disk Cleanup removes them'; 'MSOCache' = 'Old Office install cache'
}
$agg = @{}; $big = New-Object System.Collections.ArrayList; $profTotal = [double]0
foreach ($d in (Get-ChildItem -LiteralPath ($sd + '\') -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'System Volume Information' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
    if ($d.Name -ne 'Users') { Row $d.Name (Size $d.FullName) $notes[$d.Name]; continue }
    foreach ($u in (Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
        if ($u.FullName.TrimEnd('\') -ne $prof) { Row ('Users\' + $u.Name) (Size $u.FullName) 'Other user profile'; continue }
        # Target user: one pass, totals per folder (AppData one level deeper) + every file over 1 GB
        $cut = $prof.Length + 1
        Get-ChildItem -LiteralPath $prof -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ([int]$_.Attributes -band $cloud) { return }
            $len = $_.Length; $profTotal += $len
            $parts = $_.FullName.Substring($cut).Split('\')
            $k = if ($parts.Count -ge 4 -and $parts[0] -eq 'AppData') { $parts[0] + '\' + $parts[1] + '\' + $parts[2] } elseif ($parts.Count -ge 2) { $parts[0] } else { '(files in profile folder)' }
            $agg[$k] += $len
            if ($len -gt 1GB) { [void]$big.Add($_) }
        }
        Row ('Users\' + $u.Name) $profTotal 'Signed-in user - see section 3'
    }
}
$rows | Sort-Object Size -Descending | ForEach-Object { Line $_.Size $_.Item $_.Note }

# 3 ---------------------------------------------------------------
Sec ('3. Biggest folders in ' + $prof)
$pnote = @{
    'AppData\Local\wsl' = 'WSL Linux disks - see section 5'; 'AppData\Local\Docker' = 'Docker disks + images'
    'AppData\Roaming\Mozilla' = 'Firefox profile - mostly website storage, section 5'; 'AppData\Local\Mozilla' = 'Firefox cache'
    'AppData\Local\Google' = 'Chrome profile + cache'; 'AppData\Local\Microsoft' = 'Edge, Outlook, OneDrive, Teams data'
    'AppData\Roaming\Code' = 'VS Code caches + workspace data'; 'AppData\Local\npm-cache' = 'npm download cache - safe to clean'
    'AppData\Local\SquirrelTemp' = 'Installer leftovers - safe to clean'; 'AppData\Local\Temp' = 'Temp files - safe to clean'
    'AppData\Roaming\Apple Computer' = 'iTunes - phone backups + update files'; 'AppData\Local\Android' = 'Android SDK + emulators'
    'AppData\Local\Packages' = 'Store apps data'; 'AppData\Local\pip' = 'Python pip cache - safe to clean'
    'Downloads' = 'Downloaded files - old installers can go'; 'OneDrive' = 'OneDrive files kept on this PC'
    '.vscode' = 'VS Code extensions'; '.gradle' = 'Gradle build cache'; '.android' = 'Android emulators'
}
$agg.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object { Line $_.Value $_.Key $pnote[$_.Key] }

# 4 ---------------------------------------------------------------
Sec '4. Single files over 1 GB in the user profile'
if ($big.Count -eq 0) { Write-Host '   None.' }
$big | Sort-Object Length -Descending | Select-Object -First 15 | ForEach-Object { Line $_.Length (Short $_.FullName) ('changed ' + $_.LastWriteTime.ToString('yyyy-MM-dd')) }

# 5 ---------------------------------------------------------------
Sec '5. Known space hogs - explained (not cleaned automatically)'
$hog = 0
# WSL / Docker virtual disks grow and never shrink by themselves
$distro = @{}
Get-ChildItem ('Registry::HKEY_USERS\' + $env:TSID + '\Software\Microsoft\Windows\CurrentVersion\Lxss') -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
    if ($p.BasePath) { $distro[($p.BasePath -replace '^\\\\\?\\', '').TrimEnd('\')] = $p.DistributionName }
}
$vhd = @(Get-ChildItem -LiteralPath "$loc\wsl", "$loc\Docker", "$loc\Packages" -Recurse -Depth 4 -File -Filter '*.vhdx' -Force -ErrorAction SilentlyContinue)
foreach ($x in $vhd) {
    $hog++
    $name = $distro[$x.DirectoryName.TrimEnd('\')]; if (-not $name) { $name = if ($x.FullName -match 'Docker') { 'Docker' } else { Split-Path $x.DirectoryName -Leaf } }
    Line $x.Length ('WSL disk: ' + $name) ('last used ' + $x.LastWriteTime.ToString('yyyy-MM-dd'))
}
if ($vhd) {
    Write-Host '      Linux disks only grow. Shrink one (keeps data):  wsl --shutdown  then  wsl --manage NAME --set-sparse true' -ForegroundColor DarkGray
    Write-Host '      Remove an unused one (DELETES it):               wsl --unregister NAME' -ForegroundColor DarkGray
}
# Website storage in browsers - WhatsApp / Telegram Web keep all media
foreach ($fp in (Get-ChildItem -LiteralPath "$roam\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue)) {
    foreach ($site in (Get-ChildItem -LiteralPath "$($fp.FullName)\storage\default" -Directory -ErrorAction SilentlyContinue)) {
        $s = Size $site.FullName
        if ($s -gt 300MB) { $hog++; Line $s ('Firefox site: ' + ($site.Name -replace '^https?\+\+\+', '' -replace '\^userContextId=', ' container ')) 'Clear: Firefox Settings, Privacy, Manage Data' }
    }
}
foreach ($br in @(@('Chrome', "$loc\Google\Chrome\User Data"), @('Edge', "$loc\Microsoft\Edge\User Data"))) {
    foreach ($bp in (Get-ChildItem -LiteralPath $br[1] -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^(Default|Profile \d+)$')) {
        $s = (Size "$($bp.FullName)\IndexedDB") + (Size "$($bp.FullName)\Service Worker")
        if ($s -gt 300MB) { $hog++; Line $s ($br[0] + ' website storage - ' + $bp.Name) 'Clear: Settings, Privacy, Site data' }
    }
}
# Phone backups are personal data - point to them, never delete
foreach ($bk in @("$roam\Apple Computer\MobileSync\Backup", "$prof\Apple\MobileSync\Backup")) {
    foreach ($b in (Get-ChildItem -LiteralPath $bk -Directory -ErrorAction SilentlyContinue)) { $hog++; Line (Size $b.FullName) 'iPhone / iPad backup' ('made ' + $b.LastWriteTime.ToString('yyyy-MM-dd') + ' - delete old ones in iTunes / Apple Devices') }
}
# Mail data files
foreach ($o in (Get-ChildItem -LiteralPath "$loc\Microsoft\Outlook", "$prof\Documents\Outlook Files", "$prof\OneDrive\Documents\Outlook Files" -File -Include '*.ost', '*.pst' -Recurse -Depth 1 -Force -ErrorAction SilentlyContinue | Where-Object Length -gt 1GB)) {
    $hog++; Line $o.Length ('Outlook: ' + $o.Name) $(if ($o.Extension -eq '.ost') { 'Mail cache - option 46 rebuilds it smaller' } else { 'Mail archive - personal data, keep or move' })
}
# Old installers in Downloads
$dl = @(Get-ChildItem -LiteralPath "$prof\Downloads" -Recurse -File -Force -Include '*.exe', '*.msi', '*.iso', '*.zip', '*.rar', '*.7z' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) })
$dls = ($dl | Measure-Object Length -Sum).Sum
if ($dls -gt 500MB) { $hog++; Line $dls ('Downloads: ' + $dl.Count + ' old installers / archives') '90+ days old - check and delete by hand' }
$avd = Size "$prof\.android\avd"
if ($avd -gt 1GB) { $hog++; Line $avd 'Android emulators' 'Delete unused ones in Android Studio, Device Manager' }
if ($hog -eq 0) { Write-Host '   None found.' }

# 6 ---------------------------------------------------------------
Sec '6. SAFE to clean - caches and leftovers, no personal files'
$cutoff = (Get-Date).AddDays(-60)
$oldWs = @(); $wsNames = @()
foreach ($w in (Get-ChildItem -LiteralPath "$roam\Code\User\workspaceStorage" -Directory -ErrorAction SilentlyContinue)) {
    $db = Get-Item -LiteralPath "$($w.FullName)\state.vscdb" -ErrorAction SilentlyContinue
    $last = if ($db) { $db.LastWriteTime } else { $w.LastWriteTime }
    if ($last -lt $cutoff) {
        $oldWs += $w.FullName
        $wj = Get-Content -LiteralPath "$($w.FullName)\workspace.json" -Raw -ErrorAction SilentlyContinue
        if ($wj -match '"(folder|workspace)"\s*:\s*"([^"]+)"') { $wsNames += [uri]::UnescapeDataString($Matches[2]) -replace '^file:///', '' }
    }
}
$brCache = @()
foreach ($root in "$loc\Google\Chrome\User Data", "$loc\Microsoft\Edge\User Data") {
    foreach ($bp in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^(Default|Profile \d+)$')) { $brCache += "$($bp.FullName)\Cache", "$($bp.FullName)\Code Cache", "$($bp.FullName)\GPUCache" }
}
$brCache += @(Get-ChildItem -LiteralPath "$loc\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\cache2" })
$ipsw = @(Get-ChildItem -LiteralPath "$roam\Apple Computer\iTunes" -Recurse -File -Filter '*.ipsw' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$doCache = "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
# Empty = delete everything INSIDE these folders.  Remove = delete these files / folders.
$safe = @(
    @{ N = 'User temp files';                          Empty = @("$loc\Temp") },
    @{ N = 'Windows temp files';                       Empty = @("$env:SystemRoot\Temp") },
    @{ N = 'Installer leftovers - SquirrelTemp';       Empty = @("$loc\SquirrelTemp") },
    @{ N = 'Old iPhone / iPad update files (.ipsw)';   Remove = $ipsw },
    @{ N = 'Crash dumps + error reports';              Empty = @("$loc\CrashDumps", "$env:SystemRoot\Minidump", "$env:SystemRoot\LiveKernelReports", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Remove = @("$env:SystemRoot\MEMORY.DMP") },
    @{ N = 'Windows Update download cache';            Empty = @("$env:SystemRoot\SoftwareDistribution\Download") },
    @{ N = 'Delivery Optimization cache';              Empty = @($doCache); DO = $true },
    @{ N = 'Recycle Bin - this drive';                 Empty = @(); Recycle = $true },
    @{ N = 'Developer download caches - npm/yarn/pip/composer'; Empty = @("$loc\npm-cache", "$loc\Yarn\Cache", "$loc\pip\cache", "$loc\Composer\files", "$loc\Composer\repo") },
    @{ N = 'VS Code caches';                           Empty = @("$roam\Code\Cache", "$roam\Code\CachedData", "$roam\Code\CachedExtensionVSIXs", "$roam\Code\logs") },
    @{ N = ('VS Code data of ' + $oldWs.Count + ' project(s) unused 60+ days'); Remove = $oldWs; Info = $wsNames },
    @{ N = 'Browser caches - Chrome, Edge, Firefox';   Empty = $brCache; Note = 'close the browsers first' }
)
$list = @()
foreach ($e in $safe) {
    $s = [double]0
    foreach ($p in @($e.Empty)) { $s += Size $p }
    foreach ($p in @($e.Remove)) { $s += Size $p }
    if ($e.Recycle) { $s += Size ($sd + '\$Recycle.Bin') }
    if ($s -gt 20MB) { $e.Size = $s; $list += $e }
}
if ($list.Count -eq 0) { Write-Host '   Nothing worth cleaning - caches are already small.' -ForegroundColor Green }
else {
    $i = 0
    foreach ($e in $list) {
        $i++
        Write-Host ('   [' + $i.ToString().PadLeft(2) + '] ') -NoNewline -ForegroundColor Cyan
        Line $e.Size $e.N $e.Note
        foreach ($nm in (@($e.Info) | Where-Object { $_ } | Select-Object -First 5)) { Write-Host ('                       - ' + $nm) -ForegroundColor DarkGray }
    }
    $tot = ($list | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
    Write-Host ''
    Write-Host ('   Total that can be freed: ' + (GB $tot).Trim()) -ForegroundColor Green
    Write-Host ''
    $ans = Read-Host '   Numbers to clean, e.g. 1 3 5 - A = all - Enter = nothing'
    $idx = if ($ans -match '^\s*[Aa]\s*$') { 1..$list.Count } else { @($ans -split '[^0-9]+' | Where-Object { $_ } | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 1 -and $_ -le $list.Count }) }
    $pick = @($idx | Sort-Object -Unique | ForEach-Object { $list[$_ - 1] })
    if ($pick.Count -gt 0) {
        Write-Host ''
        foreach ($e in $pick) { Write-Host ('     - ' + $e.N + '  (' + (GB $e.Size).Trim() + ')') }
        $ok = Read-Host '   Delete these permanently - they do NOT go to the Recycle Bin? [Y/N]'
        if ($ok -match '^[Yy]') {
            $before = (Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $sd + "'")).FreeSpace
            foreach ($e in $pick) {
                Write-Host ('   Cleaning: ' + $e.N + ' ...') -NoNewline
                $skip = 0
                if ($e.DO -and (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { $skip++ } }
                if ($e.Recycle) { try { Clear-RecycleBin -DriveLetter $sd.TrimEnd(':') -Force -ErrorAction Stop } catch { $skip++ } }
                foreach ($p in @($e.Empty)) {
                    if (-not $p -or -not (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { continue }
                    foreach ($c in (Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction Stop } catch { $skip++ } }
                }
                foreach ($p in @($e.Remove)) {
                    if (-not $p -or -not (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { continue }
                    try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } catch { $skip++ }
                }
                if ($skip) { Write-Host (' done - ' + $skip + ' item(s) in use, skipped') -ForegroundColor Yellow } else { Write-Host ' done' -ForegroundColor Green }
            }
            $after = (Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $sd + "'")).FreeSpace
            Write-Host ''
            Write-Host ('   Freed: ' + (GB ([Math]::Max(0, $after - $before))).Trim() + '   Free now: ' + (GB $after).Trim()) -ForegroundColor Green
        } else { Write-Host '   Nothing deleted.' }
    } else { Write-Host '   Nothing deleted.' }
}

# Summary ---------------------------------------------------------
Write-Host ''
Write-Host '  ===================================================================' -ForegroundColor White
$top = $rows | Sort-Object Size -Descending | Select-Object -First 3
Write-Host ('  Biggest on ' + $sd + ' - ' +(($top | ForEach-Object { $_.Item + ' ' + (GB $_.Size).Trim() }) -join ', ')) -ForegroundColor Yellow
Write-Host '  More space: section 5 items (by hand), option 61 Deep Clean (Windows store + restore points),'
Write-Host '  and uninstall unused programs in Settings, Apps.'
try { Stop-Transcript | Out-Null } catch {}
Write-Host ('  Report saved: ' + $report) -ForegroundColor Green
exit 0
::PS-DISKSCAN-END

::PS-DEFENDER-BEGIN
try {
    switch ($env:AVACT) {
        'UPDATE'  { Write-Host '  Updating Defender definitions...'; Update-MpSignature -ErrorAction Stop; Write-Host '  Definitions updated.' -ForegroundColor Green }
        'QUICK'   { Write-Host '  Quick scan running - a few minutes...'; Start-MpScan -ScanType QuickScan -ErrorAction Stop; Write-Host '  Quick scan finished.' -ForegroundColor Green }
        'FULL'    { Write-Host '  Full scan running - can take 1 hour or more. Leave this window open...'; Start-MpScan -ScanType FullScan -ErrorAction Stop; Write-Host '  Full scan finished.' -ForegroundColor Green }
        'OFFLINE' { Write-Host '  Restarting for offline scan...'; Start-MpWDOScan -ErrorAction Stop }
    }
    if ($env:AVACT -in 'QUICK','FULL') {
        $d = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddHours(-3) }
        if ($d) { Write-Host ('  ' + @($d).Count + ' threat(s) found - Defender removed or quarantined them. See Windows Security - Protection history.') -ForegroundColor Red }
        else { Write-Host '  No threats found.' -ForegroundColor Green }
    }
} catch {
    Write-Host ('  Defender action failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '  If another antivirus is installed, run the scan from that antivirus instead.' -ForegroundColor Yellow
}
exit 0
::PS-DEFENDER-END

::PS-SPAMTRACE-BEGIN
# Mode from $env:SPMODE: SCAN | MONITOR | BLOCK | UNBLOCK | CHECKLIST
$smtpPorts = 25, 465, 587, 2525
$ruleName  = 'IT Tools - Block outbound mail SMTP'
function Sec($t) { Write-Host ''; Write-Host ('  == ' + $t) -ForegroundColor Cyan }
function Get-Sig($path) {
    if (-not $path) { return 'no path' }
    try { $a = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop; if ($a.Status -eq 'Valid') { 'Signed: ' + $a.SignerCertificate.GetNameInfo('SimpleName', $false) } else { 'UNSIGNED' } } catch { 'unreadable' }
}
function Get-SmtpConns {
    Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.RemotePort -in $smtpPorts } | ForEach-Object {
        $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $_.OwningProcess) -ErrorAction SilentlyContinue
        [pscustomobject]@{ Time = (Get-Date -Format HH:mm:ss); PID = $_.OwningProcess; Program = $p.Name; Remote = ($_.RemoteAddress + ':' + $_.RemotePort)
                           State = $_.State; Signature = (Get-Sig $p.ExecutablePath); Path = $p.ExecutablePath; CommandLine = $p.CommandLine }
    }
}
$u  = 'Registry::HKEY_USERS\' + $env:TSID
$tr = $env:TROAMING

switch ($env:SPMODE) {

'SCAN' {
    $hits = 0
    Sec '1. Programs connected to mail servers RIGHT NOW - ports 25 / 465 / 587 / 2525'
    $c = @(Get-SmtpConns)
    if ($c) { $hits += $c.Count; $c | Format-Table PID, Program, Remote, State, Signature, Path -AutoSize | Out-String -Width 250 | Write-Host
              Write-Host '   [!] Stop the sender with option 66 using the PID above.' -ForegroundColor Red }
    else { Write-Host '   None right now. Spam bots send in bursts - also run [2] Live monitor.' }

    Sec '2. Mail servers this PC looked up recently - DNS cache'
    $dnsHits = Get-DnsClientCache -ErrorAction SilentlyContinue | Where-Object { $_.Entry -match '(^|\.)(smtp|mail|mx\d*|relay|mta|out)\.|smtp\.office365|smtp\.gmail' } | Sort-Object Entry -Unique
    if ($dnsHits) { $dnsHits | Format-Table Entry, Data -AutoSize | Out-String -Width 200 | Write-Host } else { Write-Host '   None.' }

    Sec '3. Outlook macros and add-ins - a common way to auto-send mail'
    $otm = Join-Path $tr 'Microsoft\Outlook\VbaProject.OTM'
    if (Test-Path -LiteralPath $otm) {
        $f = Get-Item -LiteralPath $otm -Force
        $hits++; Write-Host ('   [!] Outlook VBA macros exist: ' + $otm + ' - ' + [math]::Round($f.Length/1KB) + ' KB, changed ' + $f.LastWriteTime) -ForegroundColor Red
        Write-Host '       Check in Outlook: Alt+F11. Unknown macro = rename this file to .old with Outlook closed.' -ForegroundColor Yellow
    } else { Write-Host '   OK - no Outlook macros.' }
    $addinKeys = "$u\Software\Microsoft\Office\Outlook\Addins", 'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins'
    $addins = foreach ($k in $addinKeys) { Get-ChildItem -Path $k -ErrorAction SilentlyContinue | ForEach-Object { $p = Get-ItemProperty $_.PSPath; [pscustomobject]@{ AddIn = $_.PSChildName; Name = $p.FriendlyName; LoadAtStart = ($p.LoadBehavior -eq 3) } } }
    if ($addins) { Write-Host '   Outlook add-ins - remove any you do not recognise:'; $addins | Format-Table -AutoSize | Out-String -Width 200 | Write-Host }

    Sec '4. Script programs running now - wscript, cscript, powershell, mshta, python'
    $sh = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(wscript|cscript|mshta|powershell|pwsh|python|pythonw|node)\.exe$' -and $_.ProcessId -ne $PID -and $_.CommandLine -notmatch 'ReadAllText\(\$env:ITSELF\)' }
    if ($sh) { foreach ($s in $sh) { $hits++; Write-Host ('   [!] ' + $s.Name + ' PID ' + $s.ProcessId + ': ' + $s.CommandLine) -ForegroundColor Yellow } } else { Write-Host '   None.' }

    Sec '5. Scripts and tasks containing mail-sending code - last 60 days'
    Write-Host '   Searching user folders, Temp, Public, ProgramData... about 1 minute'
    $pattern = 'Send-MailMessage|System\.Net\.Mail|SmtpClient|CDO\.Message|Outlook\.Application|\.CreateItem\(0\)|MAPI\.Session|smtp\.office365|smtp\.gmail|sendmail'
    $roots = @($env:TPROFILE, $env:TEMP, "$env:SystemDrive\Users\Public", $env:ProgramData) | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
    $since = (Get-Date).AddDays(-60)
    $files = foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(ps1|psm1|vbs|vbe|js|jse|wsf|hta|bat|cmd|py)$' -and $_.LastWriteTime -gt $since -and $_.Length -lt 2MB -and $_.FullName -notmatch '\\ITTools\\' }
    }
    $mailScripts = foreach ($f in $files) { if (Select-String -LiteralPath $f.FullName -Pattern $pattern -Quiet -ErrorAction SilentlyContinue) { $f } }
    if ($mailScripts) { foreach ($m in $mailScripts) { $hits++; Write-Host ('   [!] ' + $m.FullName + '  - changed ' + $m.LastWriteTime) -ForegroundColor Red } } else { Write-Host '   None found.' }
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object State -ne 'Disabled' | Where-Object { ($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -match ($pattern + '|wscript|cscript|mshta|\.vbs|\.js\b|-enc') -and $_.TaskPath -notlike '\Microsoft\*' }
    foreach ($t in $tasks) { $hits++; Write-Host ('   [!] Scheduled task ' + $t.TaskPath + $t.TaskName + ': ' + (($t.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' ; ')) -ForegroundColor Red }

    Sec '6. Mail port block on this PC'
    if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) { Write-Host '   Outbound mail ports are BLOCKED by IT Tools.' -ForegroundColor Green } else { Write-Host '   Not blocked. Use [3] to stop any program on this PC from sending mail directly.' }

    Write-Host ''
    if ($hits -eq 0) {
        Write-Host '  Nothing on this PC is sending mail directly.' -ForegroundColor Green
        Write-Host '  Spam sent "from" a user with nothing found here = the MAILBOX is hacked, not the PC. See [5] checklist.' -ForegroundColor Yellow
    } else { Write-Host ('  ' + $hits + ' item(s) found above - stop them with option 66, then run option 64 Security Check.') -ForegroundColor Red }
}

'MONITOR' {
    $seconds = 180
    Write-Host ''
    Write-Host ('  Watching for mail connections for ' + $seconds + ' seconds - press Ctrl+C to stop early.') -ForegroundColor Cyan
    $seen = @{}
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) {
        foreach ($c in @(Get-SmtpConns)) {
            $key = [string]$c.PID + '|' + $c.Remote
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $c
                Write-Host ('  [' + $c.Time + '] PID ' + $c.PID + '  ' + $c.Program + '  ->  ' + $c.Remote + '  ' + $c.Signature) -ForegroundColor Red
                Write-Host ('            ' + $c.Path) -ForegroundColor Yellow
                if ($c.CommandLine) { Write-Host ('            ' + $c.CommandLine) -ForegroundColor DarkYellow }
            }
        }
        Start-Sleep -Milliseconds 1500
    }
    Write-Host ''
    if ($seen.Count -eq 0) { Write-Host '  No program sent mail during the watch.' -ForegroundColor Green }
    else { Write-Host ('  ' + $seen.Count + ' mail connection(s) caught - stop the PID with option 66.') -ForegroundColor Red }
}

'BLOCK' {
    if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) { Write-Host '  Already blocked.' -ForegroundColor Green; break }
    New-NetFirewallRule -DisplayName $ruleName -Description 'Created by IT Tools - stops spam bots sending mail directly' -Direction Outbound -Protocol TCP -RemotePort $smtpPorts -Action Block -Profile Any | Out-Null
    Write-Host '  Outbound mail ports 25 / 465 / 587 / 2525 are now BLOCKED on this PC.' -ForegroundColor Green
}

'UNBLOCK' {
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    Write-Host '  Mail port block removed.' -ForegroundColor Green
}

'CHECKLIST' {
    Write-Host ''
    Write-Host '  SPAM FROM A COMPANY ADDRESS - most often the MAILBOX is hacked, not the PC' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Stop it now - Microsoft 365 admin center / Entra admin center:'
    Write-Host '   1. Block sign-in for the user, then reset the password from a CLEAN device.'
    Write-Host '   2. Revoke all sessions: Entra - Users - user - Revoke sessions.'
    Write-Host '   3. Turn on MFA for the user - and for every user if not done yet.'
    Write-Host ''
    Write-Host '  Find what the attacker changed - Outlook on the web / Exchange admin center:'
    Write-Host '   4. Inbox rules: delete rules that move, delete or forward mail - often named . or ..'
    Write-Host '   5. Forwarding: Exchange admin - mailbox - Mail flow settings - remove external forwarding.'
    Write-Host '   6. Enterprise apps / consent: Entra - Enterprise applications - remove unknown apps the user approved.'
    Write-Host '   7. Sign-in logs: Entra - Sign-in logs - look for foreign countries or unknown devices.'
    Write-Host ''
    Write-Host '  Trace who sent what - Exchange admin center - Mail flow - Message trace:'
    Write-Host '   8. Filter by sender, last 2 days. Shows every recipient and the time of each message.'
    Write-Host '      PowerShell: Connect-ExchangeOnline; Get-MessageTraceV2 -SenderAddress user@company.com -StartDate (Get-Date).AddDays(-2)'
    Write-Host '   9. Check the user is not blocked: Microsoft Defender portal - Restricted entities.'
    Write-Host ''
    Write-Host '  Company mail server / firewall:'
    Write-Host '  10. Look in the mail server or firewall logs for the SOURCE IP sending on port 25 - that is the infected device.'
    Write-Host '      Printers, scanners and old servers with SMTP relay are common culprits.'
    Write-Host '  11. Block port 25 outbound at the firewall for every device except the mail server.'
    Write-Host ''
    Write-Host '  On each suspected PC: option 65 [1] + [2], then option 64 Security Check.'
}
}
exit 0
::PS-SPAMTRACE-END

::PS-BLOCKPROC-BEGIN
# Mode from $env:BPMODE: STOP | LIST | UNBLOCK.  Interactive.
$prefix = 'IT Tools - Blocked program: '
switch ($env:BPMODE) {

'STOP' {
    $in = Read-Host '  PID of the process to stop'
    $procId = 0
    if (-not [int]::TryParse($in, [ref]$procId) -or $procId -le 4) { Write-Host '  Invalid PID.' -ForegroundColor Red; break }
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $procId) -ErrorAction SilentlyContinue
    if (-not $p) { Write-Host '  No process with that PID - it may have closed already.' -ForegroundColor Yellow; break }
    $path = $p.ExecutablePath
    $sig = if ($path) { $a = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction SilentlyContinue; if ($a.Status -eq 'Valid') { 'Signed by ' + $a.SignerCertificate.GetNameInfo('SimpleName', $false) } else { 'UNSIGNED' } } else { 'unknown' }
    Write-Host ''
    Write-Host ('  Process:   ' + $p.Name + '  PID ' + $procId)
    Write-Host ('  Path:      ' + $path)
    Write-Host ('  Signature: ' + $sig)
    Write-Host ('  Command:   ' + $p.CommandLine)
    $conns = Get-NetTCPConnection -OwningProcess $procId -ErrorAction SilentlyContinue | Where-Object RemoteAddress -notin '0.0.0.0','::','127.0.0.1','::1'
    if ($conns) { Write-Host ('  Connected: ' + (($conns | ForEach-Object { $_.RemoteAddress + ':' + $_.RemotePort } | Sort-Object -Unique) -join ', ')) }
    $critical = 'System','smss.exe','csrss.exe','wininit.exe','winlogon.exe','services.exe','lsass.exe','svchost.exe','explorer.exe','dwm.exe'
    if ($p.Name -in $critical) { Write-Host '  This is a Windows system process - stopping it would crash Windows. Not stopped.' -ForegroundColor Red; break }
    Write-Host ''
    if ((Read-Host '  Stop this process? [Y/N]') -notmatch '^[Yy]') { Write-Host '  Cancelled.'; break }
    $kids = Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $procId) -ErrorAction SilentlyContinue
    foreach ($k in $kids) { Stop-Process -Id $k.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    if (Get-Process -Id $procId -ErrorAction SilentlyContinue) { Write-Host '  Could not stop it - try again after restart in Safe Mode.' -ForegroundColor Red }
    else { Write-Host ('  Stopped ' + $p.Name + $(if ($kids) { ' and ' + @($kids).Count + ' child process(es)' } else { '' }) + '.') -ForegroundColor Green }
    if ($path) {
        if ((Read-Host '  Block this program from network access in the firewall? [Y/N]') -match '^[Yy]') {
            $rn = $prefix + $path
            if (-not (Get-NetFirewallRule -DisplayName $rn -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName $rn -Direction Outbound -Program $path -Action Block -Profile Any | Out-Null
                New-NetFirewallRule -DisplayName $rn -Direction Inbound  -Program $path -Action Block -Profile Any | Out-Null
            }
            Write-Host '  Blocked in and out.' -ForegroundColor Green
        }
        if ((Read-Host '  Scan this file with Microsoft Defender? [Y/N]') -match '^[Yy]') {
            try { Start-MpScan -ScanType CustomScan -ScanPath $path -ErrorAction Stop
                  $d = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-10) }
                  if ($d) { Write-Host '  [!] Defender found a threat and handled it - see Windows Security - Protection history.' -ForegroundColor Red } else { Write-Host '  Defender found nothing in this file.' -ForegroundColor Green } }
            catch { Write-Host ('  Scan failed: ' + $_.Exception.Message) -ForegroundColor Red }
        }
        Write-Host ''
        Write-Host '  Next: run option 64 Security Check - remove its auto-start entry so it does not come back.'
    }
}

'REMOVEFILE' {
    $file = (Read-Host '  Full path of the infected file - copy it from option 64 section 9').Trim().Trim('"')
    if (-not $file) { Write-Host '  Cancelled.'; break }
    $file = [Environment]::ExpandEnvironmentVariables($file)
    $leaf = Split-Path $file -Leaf
    $dir  = Split-Path $file
    # Safety: never touch Windows itself or Microsoft-signed files
    $protected = '^[A-Za-z]:\\Windows\\(System32|SysWOW64|WinSxS|servicing)\\|\\Windows Defender\\|\\Microsoft Office\\'
    if ($file -match $protected) { Write-Host '  That is a protected Windows / Defender / Office location - not removed. Use Defender full scan [F] or option 9 Repair instead.' -ForegroundColor Red; break }
    if ($leaf -match '^(svchost|lsass|csrss|winlogon|services|smss|explorer|powershell|cmd|wscript|cscript|rundll32|regsvr32|mshta)\.exe$' -and $file -match '^[A-Za-z]:\\Windows\\') { Write-Host '  Windows system program - not removed.' -ForegroundColor Red; break }
    $exists = Test-Path -LiteralPath $file
    if ($exists) {
        $sig = try { $a = Get-AuthenticodeSignature -LiteralPath $file -ErrorAction Stop; if ($a.Status -eq 'Valid') { $a.SignerCertificate.GetNameInfo('SimpleName', $false) } else { 'UNSIGNED' } } catch { if ($_.Exception.Message -match 'virus|unwanted') { 'BLOCKED-BY-ANTIVIRUS' } else { 'unreadable' } }
        if ($sig -like 'Microsoft*') { Write-Host ('  File is signed by ' + $sig + ' - not malware, not removed.') -ForegroundColor Yellow; break }
        Write-Host ('  File: ' + $file + '   [' + $sig + ']')
    } else { Write-Host '  File not found - will still clean up anything that tries to start it.' -ForegroundColor Yellow }

    # Find everything related
    $isDll = $leaf -match '\.dll$'
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath -eq $file) -or
        ($isDll -and $_.ExecutablePath -and (Split-Path $_.ExecutablePath) -eq $dir) -or
        ($_.CommandLine -and $_.CommandLine -like ('*' + $leaf + '*') -and $_.ProcessId -ne $PID -and $_.CommandLine -notmatch 'ReadAllText\(\$env:ITSELF\)') })
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -like ('*' + $leaf + '*') })
    $svcs  = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -like ('*' + $leaf + '*') })
    $runHits = @()
    $runKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
    if ($env:TSID) { $runKeys += @(('Registry::HKEY_USERS\' + $env:TSID + '\Software\Microsoft\Windows\CurrentVersion\Run'), ('Registry::HKEY_USERS\' + $env:TSID + '\Software\Microsoft\Windows\CurrentVersion\RunOnce')) }
    foreach ($k in $runKeys) {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($p) { foreach ($pr in $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and [string]$_.Value -like ('*' + $leaf + '*') }) { $runHits += [pscustomobject]@{ Key = $k; Name = $pr.Name } } }
    }

    Write-Host ''
    Write-Host '  Will remove:' -ForegroundColor Cyan
    foreach ($p in $procs)   { Write-Host ('   - stop process ' + $p.Name + ' PID ' + $p.ProcessId) }
    foreach ($t in $tasks)   { Write-Host ('   - delete scheduled task ' + $t.TaskPath + $t.TaskName) }
    foreach ($s in $svcs)    { Write-Host ('   - stop and delete service ' + $s.Name + ' - ' + $s.DisplayName) }
    foreach ($h in $runHits) { Write-Host ('   - delete startup entry ' + $h.Name) }
    if ($exists) { Write-Host ('   - delete file ' + $file) }
    if (-not ($procs + $tasks + $svcs + $runHits) -and -not $exists) { Write-Host '  Nothing to remove.' -ForegroundColor Green; break }
    Write-Host ''
    if ((Read-Host '  Remove all of the above? [Y/N]') -notmatch '^[Yy]') { Write-Host '  Cancelled.'; break }

    # Evidence record first
    $ev = Join-Path $env:ITROOT ('Evidence\Removed_' + (Get-Date -Format yyyyMMdd_HHmmss))
    New-Item -ItemType Directory -Force -Path $ev | Out-Null
    $rec = @('File: ' + $file)
    if ($exists) { $rec += 'SHA256: ' + $(try { (Get-FileHash -LiteralPath $file -ErrorAction Stop).Hash } catch { 'blocked by antivirus' }) }
    foreach ($t in $tasks) { try { Export-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName | Set-Content (Join-Path $ev ('task_' + $t.TaskName + '.xml.txt')) } catch {} }
    $rec | Set-Content (Join-Path $ev 'removed.txt')

    foreach ($t in $tasks) { try { Stop-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue } catch {} }
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('  Stopped PID ' + $p.ProcessId) -ForegroundColor Green }
    foreach ($s in $svcs)  { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue; sc.exe delete $s.Name | Out-Null; Write-Host ('  Deleted service ' + $s.Name) -ForegroundColor Green }
    foreach ($t in $tasks) { Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue; Write-Host ('  Deleted task ' + $t.TaskName) -ForegroundColor Green }
    foreach ($h in $runHits) { Remove-ItemProperty -Path $h.Key -Name $h.Name -ErrorAction SilentlyContinue; Write-Host ('  Deleted startup entry ' + $h.Name) -ForegroundColor Green }
    Start-Sleep 1
    if ($exists) {
        try { Start-MpScan -ScanType CustomScan -ScanPath $file -ErrorAction SilentlyContinue; Remove-MpThreat -ErrorAction SilentlyContinue } catch {}
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $file) {
            Write-Host '  File is locked - it will be deleted at next restart.' -ForegroundColor Yellow
            $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $cur = @((Get-ItemProperty $k -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations)
            Set-ItemProperty $k -Name PendingFileRenameOperations -Value (@($cur | Where-Object { $_ }) + @(('\??\' + $file), '')) -Type MultiString
        } else { Write-Host '  File deleted.' -ForegroundColor Green }
    }
    Write-Host ''
    Write-Host ('  Done. Record saved in ' + $ev) -ForegroundColor Green
    Write-Host '  Run option 64 again to confirm, then a Defender full scan [F].'
}

'LIST' {
    $r = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ($prefix + '*') -or $_.DisplayName -like 'IT Tools - Block outbound mail*' }
    if ($r) { $r | Sort-Object DisplayName -Unique | ForEach-Object { Write-Host ('   ' + $_.DisplayName + '  [' + $_.Direction + ']') } }
    else { Write-Host '  No programs blocked by IT Tools.' }
}

'UNBLOCK' {
    $r = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ($prefix + '*') } | Sort-Object DisplayName -Unique)
    if (-not $r) { Write-Host '  No programs blocked by IT Tools.'; break }
    for ($i = 0; $i -lt $r.Count; $i++) { Write-Host ('   [' + ($i + 1) + '] ' + $r[$i].DisplayName.Substring($prefix.Length)) }
    $n = 0
    if (-not [int]::TryParse((Read-Host '  Number to unblock'), [ref]$n) -or $n -lt 1 -or $n -gt $r.Count) { Write-Host '  Cancelled.'; break }
    Get-NetFirewallRule -DisplayName $r[$n - 1].DisplayName | Remove-NetFirewallRule
    Write-Host '  Block removed.' -ForegroundColor Green
}
}
exit 0
::PS-BLOCKPROC-END

::PS-TRUST-BEGIN
# Add / remove entries in the trusted list used by option 64
$file = Join-Path $env:ITROOT 'trusted.txt'
if (-not (Test-Path $file)) { "# IT Tools trusted list - one program path or name per line. Lines starting with # are ignored." | Set-Content $file -Encoding UTF8 }
$items = @(Get-Content $file | Where-Object { $_.Trim() -and $_ -notmatch '^#' })
Write-Host ''
Write-Host '  Trusted list:' -ForegroundColor Cyan
if ($items) { for ($i = 0; $i -lt $items.Count; $i++) { Write-Host ('   [' + ($i + 1) + '] ' + $items[$i]) } } else { Write-Host '   empty' }
Write-Host ''
Write-Host '  Type a program path or name to TRUST it, e.g.  C:\Users\anees\AppData\Local\lerd\bin\lerd.exe  or  httpd.exe'
Write-Host '  Type - and a number to REMOVE an entry, e.g.  -2      Press Enter to go back.'
$in = (Read-Host '  ').Trim().Trim('"')
if (-not $in) { exit 0 }
if ($in -match '^-(\d+)$') {
    $n = [int]$Matches[1]
    if ($n -ge 1 -and $n -le $items.Count) {
        $rm = $items[$n - 1]
        (Get-Content $file | Where-Object { $_ -ne $rm }) | Set-Content $file -Encoding UTF8
        Write-Host ('  Removed: ' + $rm) -ForegroundColor Green
    } else { Write-Host '  Invalid number.' -ForegroundColor Red }
    exit 0
}
if ($in.Length -lt 5) { Write-Host '  Too short - use the full path or full file name.' -ForegroundColor Red; exit 0 }
if ($in -match '^(svchost|lsass|powershell|cmd|rundll32|regsvr32|mshta|wscript|cscript|explorer)(\.exe)?$') { Write-Host '  Windows system programs cannot be trusted by name - malware hides behind these names.' -ForegroundColor Red; exit 0 }
if ($items -contains $in) { Write-Host '  Already trusted.'; exit 0 }
Add-Content $file $in -Encoding UTF8
Write-Host ('  Trusted: ' + $in + ' - it will show as [trusted] in the next report.') -ForegroundColor Green
exit 0
::PS-TRUST-END

::PS-LOCKFIX-BEGIN
# Mode from $env:LOCKMODE: STATUS | FIX.  STATUS exits 1 when nothing is wrong.
$u   = 'Registry::HKEY_USERS\' + $env:TSID
$hlm = 'Registry::HKEY_LOCAL_MACHINE'
$fix = ($env:LOCKMODE -eq 'FIX')
$found = 0

function Get-Val($path, $name) {
    (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
}
function Report($bad, $text) {
    if ($bad) { Write-Host ('  [PROBLEM] ' + $text) -ForegroundColor Red }
    else      { Write-Host ('  [OK]      ' + $text) -ForegroundColor Green }
}

# 1 + 2: Remove Lock Computer policy - user and machine
foreach ($p in @("$u\Software\Microsoft\Windows\CurrentVersion\Policies\System",
                 "$hlm\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System")) {
    $v = Get-Val $p 'DisableLockWorkstation'
    $bad = ($null -ne $v -and [int]$v -ne 0)
    $where = $(if ($p -like '*HKEY_USERS*') { 'user' } else { 'machine' })
    Report $bad ('Lock Computer policy - ' + $where + ' - DisableLockWorkstation')
    if ($bad) { $found++; if ($fix) { Remove-ItemProperty -Path $p -Name 'DisableLockWorkstation' -ErrorAction SilentlyContinue } }
}

# 3: Lock hidden in Start account menu
$fm = "$hlm\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
$v = Get-Val $fm 'ShowLockOption'
$bad = ($null -ne $v -and [int]$v -eq 0)
Report $bad 'Lock shown in Start menu - FlyoutMenuSettings ShowLockOption'
if ($bad) { $found++; if ($fix) { Set-ItemProperty -Path $fm -Name 'ShowLockOption' -Value 1 -Type DWord } }

$pe = "$hlm\SOFTWARE\Policies\Microsoft\Windows\Explorer"
$v = Get-Val $pe 'ShowLockOption'
$bad = ($null -ne $v -and [int]$v -eq 0)
Report $bad 'Lock shown in Start menu - policy ShowLockOption'
if ($bad) { $found++; if ($fix) { Remove-ItemProperty -Path $pe -Name 'ShowLockOption' -ErrorAction SilentlyContinue } }

# 4: All Windows-key shortcuts disabled
foreach ($p in @("$u\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
                 "$hlm\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
    $v = Get-Val $p 'NoWinKeys'
    $bad = ($null -ne $v -and [int]$v -ne 0)
    $where = $(if ($p -like '*HKEY_USERS*') { 'user' } else { 'machine' })
    Report $bad ('Windows-key shortcuts - ' + $where + ' - NoWinKeys')
    if ($bad) { $found++; if ($fix) { Remove-ItemProperty -Path $p -Name 'NoWinKeys' -ErrorAction SilentlyContinue } }
}

# 5: Win+L disabled in DisabledHotkeys - letters list
$adv = "$u\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$v = Get-Val $adv 'DisabledHotkeys'
$bad = ($v -is [string] -and $v.ToUpper().Contains('L'))
Report $bad 'Win+L hotkey - DisabledHotkeys'
if ($bad) {
    $found++
    if ($fix) {
        $new = ($v.ToCharArray() | Where-Object { $_ -ne 'L' -and $_ -ne 'l' }) -join ''
        if ($new) { Set-ItemProperty -Path $adv -Name 'DisabledHotkeys' -Value $new }
        else      { Remove-ItemProperty -Path $adv -Name 'DisabledHotkeys' -ErrorAction SilentlyContinue }
    }
}

# 6: Keyboard remap that kills the Win keys - Scancode Map maps E05B / E05C to 0
$kl = "$hlm\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
$sm = Get-Val $kl 'Scancode Map'
$bad = $false
if ($sm -is [byte[]] -and $sm.Length -ge 16) {
    $count = [BitConverter]::ToInt32($sm, 8)
    for ($i = 0; $i -lt ($count - 1); $i++) {
        $o = 12 + ($i * 4)
        if ($o + 3 -ge $sm.Length) { break }
        $target = [BitConverter]::ToUInt16($sm, $o)
        $source = [BitConverter]::ToUInt16($sm, $o + 2)
        if ($target -eq 0 -and ($source -eq 0xE05B -or $source -eq 0xE05C)) { $bad = $true }
    }
}
Report $bad 'Windows key not disabled by keyboard remap - Scancode Map'
if ($bad) {
    $found++
    if ($fix) {
        Write-Host '            Removing Scancode Map - any other key remaps on this PC are removed too.' -ForegroundColor Yellow
        Remove-ItemProperty -Path $kl -Name 'Scancode Map' -ErrorAction SilentlyContinue
    }
}

if (-not $fix) {
    Write-Host ''
    if ($found -eq 0) { exit 1 }
    Write-Host ('  ' + $found + ' problem(s) found.') -ForegroundColor Yellow
} else {
    Write-Host ''
    Write-Host ('  ' + $found + ' problem(s) fixed.') -ForegroundColor Green
}
exit 0
::PS-LOCKFIX-END

::PS-REMOVEAPPS-BEGIN
# Mode from $env:APPMODE: LIST | REMOVE. Exit 1 when nothing to remove.
# Only clear consumer apps. Work apps (Store, Office, Teams work, Outlook,
# Calculator, Photos, Paint, Notepad, Snipping Tool, Terminal) are never listed.
$patterns = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.News',
    'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.ZuneVideo', 'Microsoft.People', 'Microsoft.WindowsFeedbackHub', 'Microsoft.Getstarted',
    'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp', 'Microsoft.Microsoft3DViewer',
    'Microsoft.Print3D', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.OneConnect',
    'Microsoft.WindowsMaps', 'Clipchamp.Clipchamp', 'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.549981C3F5F10', 'MicrosoftTeams',
    '*CandyCrush*', 'king.com.*', '*Spotify*', '*Disney*', '*TikTok*', '*Facebook*', '*Instagram*',
    '*AmazonPrimeVideo*', '*PrimeVideo*', '*Netflix*', '*BytedancePte*', '*Twitter*', '*Hulu*',
    '*RoyalRevolt*', '*MarchofEmpires*', '*HiddenCity*', '*BubbleWitch*', '*FarmVille*'
)
function Test-Bloat($name) {
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }
    return $false
}

$installed   = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { Test-Bloat $_.Name })
$provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { Test-Bloat $_.DisplayName })
$names = @($installed.Name) + @($provisioned.DisplayName) | Where-Object { $_ } | Sort-Object -Unique

if (-not $names) {
    Write-Host '  No consumer apps found - this PC is already clean.' -ForegroundColor Green
    exit 1
}

if ($env:APPMODE -ne 'REMOVE') {
    Write-Host '  Found:'
    $names | ForEach-Object { Write-Host ('   - ' + $_) }
    exit 0
}

foreach ($a in $installed) {
    Write-Host ('  Removing ' + $a.Name)
    Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}
foreach ($p in $provisioned) {
    Write-Host ('  Deprovisioning for new users: ' + $p.DisplayName)
    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
}
exit 0
::PS-REMOVEAPPS-END
