@echo off
rem Builds ReWasp with Visual Studio (any edition with "Desktop development with C++"):
rem   build\x64\Wasp_x64.dll     64-bit FL Studio plugin (replaces Image-Line's placeholder)
rem   build\x86\WaspHost32.exe   32-bit helper that runs the original Wasp.dll
rem   build\x64\test_host64.exe  test host: loads the plugin like FL does and renders a note
rem Then, if Inno Setup 6 is installed: installer\Output\ReWasp-Setup-<version>.exe
setlocal
cd /d "%~dp0"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (echo Visual Studio not found. & exit /b 1)
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio with C++ tools not found. & exit /b 1)
set "VCVARS=%VS%\VC\Auxiliary\Build"
if not exist build\x86 mkdir build\x86
if not exist build\x64 mkdir build\x64
set "CFLAGS=/nologo /O2 /EHsc /MT /W3 /D_CRT_SECURE_NO_WARNINGS"

setlocal
call "%VCVARS%\vcvars32.bat" >nul
cl %CFLAGS% /Fobuild\x86\ src\helper32.cpp src\flhost.cpp /Fe:build\x86\WaspHost32.exe user32.lib ole32.lib shell32.lib /link /SUBSYSTEM:WINDOWS || exit /b 1
endlocal

setlocal
call "%VCVARS%\vcvars64.bat" >nul
cl %CFLAGS% /LD /Fobuild\x64\ src\native64.cpp /Fe:build\x64\Wasp_x64.dll user32.lib ole32.lib || exit /b 1
cl %CFLAGS% /Fobuild\x64\ src\test_host.cpp src\flhost.cpp /Fe:build\x64\test_host64.exe user32.lib ole32.lib || exit /b 1
endlocal

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" ("%ISCC%" /Q installer\ReWasp.iss || exit /b 1) else (echo Inno Setup 6 not found: skipped the installer.)
echo BUILD OK
