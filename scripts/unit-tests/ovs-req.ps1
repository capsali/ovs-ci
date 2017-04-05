# Make directory structure
$redistDir = "C:\Openstack\OpenvSwitch\Redist\"
if (Test-Path $redistDir) {
        Remove-Item -Recurse -Force $redistDir
    }
New-Item -ItemType directory -Path $redistDir

# Download installers
Invoke-WebRequest -Uri "http://www.7-zip.org/a/7z1602-x64.msi" -OutFile "$redistDir\7zip-x64.msi"
Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.8.3.windows.1/Git-2.8.3-64-bit.exe" -OutFile "$redistDir\git-x64.exe"
Invoke-WebRequest -Uri "https://cmake.org/files/v3.5/cmake-3.5.2-win32-x86.msi" -OutFile "$redistDir\cmake.msi"
Invoke-WebRequest -Uri "https://wix.codeplex.com/downloads/get/1540240" -OutFile "$redistDir\wix310.exe"
Invoke-WebRequest -Uri "http://freefr.dl.sourceforge.net/project/mingw/Installer/mingw-get/mingw-get-0.6.2-beta-20131004-1/mingw-get-0.6.2-mingw32-beta-20131004-1-bin.zip" -OutFile "$redistDir\msys.zip"
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/2.7.11/python-2.7.11.amd64.msi" -OutFile "$redistDir\python-2.7.1.amd64.msi"
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.6.0/python-3.6.0-embed-amd64.zip" -OutFile "$redistDir\python-3.6.0.amd64.zip"
Invoke-WebRequest -Uri "https://download.microsoft.com/download/9/6/4/96442E58-C65C-4122-A956-CCA83EECCD03/wdexpress_full.exe" -OutFile "$redistDir\wdexpress_full.exe"
Invoke-WebRequest -Uri "https://download.microsoft.com/download/0/8/C/08C7497F-8551-4054-97DE-60C0E510D97A/wdk/wdksetup.exe" -OutFile "$redistDir\wdksetup.exe"
Invoke-WebRequest -Uri "https://netix.dl.sourceforge.net/project/pthreads4w/pthreads-w32-2-9-1-release.zip" -OutFile "$redistDir\pthreads-w32.zip"
Invoke-WebRequest -Uri "http://downloads.activestate.com/ActivePerl/releases/5.24.1.2402/ActivePerl-5.24.1.2402-MSWin32-x64-401627.exe" -OutFile "$redistDir\activeperl-x64.exe"
Invoke-WebRequest -Uri "http://download.microsoft.com/download/A/A/D/AAD1AA11-FF9A-4B3C-8601-054E89260B78/vs_community.exe" -OutFile "$redistDir\vs_community.exe"
Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/0.67/x86/putty-0.67-installer.msi" -OutFile "$redistDir\putty.msi"

# Install prerequisite
Set-Location C:\Openstack\OpenvSwitch\Redist\

# Install 7zip-x64
$7zip_msi = "$redistDir\7zip-x64.msi"
Start-Process -FilePath msiexec.exe -ArgumentList "/q","/i","$7zip_msi" -Wait -PassThru

# Install Git
$git_exe = "$redistDir\git-x64.exe"
Start-Process -FilePath $git_exe -ArgumentList "/SILENT","/COMPONENTS='icons,ext\reg\shellhere,assoc,assoc_sh'","/i" -Wait -PassThru

# Install Putty
$putty_msi = "$redistDir\putty.msi"
Start-Process -FilePath $putty_msi -ArgumentList "/q" -Wait -PassThru

# Install cmake
$cmake_msi = "$redistDir\cmake.msi"
Start-Process -FilePath msiexec.exe -ArgumentList "/q","/i","$cmake_msi" -Wait -PassThru

# Install Python2.7
$python_msi = "$redistDir\python-2.7.1.amd64.msi"
Start-Process -FilePath msiexec.exe -ArgumentList "/qn","/i","$python_msi" -Wait -PassThru

# Install Python3
$python3_zip = "$redistDir\python-3.6.0.amd64.zip"
Get-ChildItem $python3_zip | % {& "C:\Program Files\7-Zip\7z.exe" "x" $_.fullname "-oC:\Python3"}
Rename-Item C:\Python3\python.exe python3.exe

# Install six for python
$ENV:PATH += ";C:\Python27"
python -m pip install six
python -m pip install pypiwin32

# Install ActivePerl
$activeperl_exe = "$redistDir\activeperl-x64.exe"
Start-Process -FilePath $activeperl_exe -ArgumentList "/q","/i" -Wait -PassThru

# Install Pthreads
$pthreads_zip = "$redistDir\pthreads-w32.zip"
Get-ChildItem $pthreads_zip | % {& "C:\Program Files\7-Zip\7z.exe" "x" $_.fullname "-oC:\Openstack\OpenvSwitch\Redist\pthreads"}
Move-Item $redistDir\pthreads\Pre-built.2 C:\Openstack\OpenvSwitch\pthread
# Copy pthread.dll to system path.
Copy-Item C:\Openstack\OpenvSwitch\pthread\dll\x64\* C:\Windows

# Install Vstudio2013
$vs_exe = "$redistDir\vs_community.exe"
Start-Process -FilePath $vs_exe -ArgumentList "/Quiet","/Norestart" -Wait -PassThru

# Install WDK
$wdk_exe = "$redistDir\wdksetup.exe"
Start-Process -FilePath $wdk_exe -ArgumentList "/q" -Wait -PassThru

# Install WIX
$wix_exe = "$redistDir\wix310.exe"
Start-Process -FilePath $wix_exe -ArgumentList "/q" -Wait -PassThru

# Install Msys
Get-ChildItem $redistDir\msys.zip | % {& "C:\Program Files\7-Zip\7z.exe" "x" $_.fullname "-oC:\mingw"}

# Install Msys req
$ENV:PATH += ";C:\mingw\bin"

mingw-get update

mingw-get upgrade

mingw-get install msys msys-coreutils 

mingw-get install msys-binutils msys-libtool msys-automake msys-autoconf msys-make msys-patch

mingw-get upgrade msys-core-bin=1.0.17-1

# Mount /mingw into msys (not sure is needed at all!)
#Rename-Item C:\mingw\msys\1.0\etc\fstab.sample fstab

# Make sure msys get the link.exe from VS12 and not the default one.
Rename-Item -Force C:\mingw\msys\1.0\bin\link.exe linkbak.exe

# Set WinRM concurrent processes per shell
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config/winrs '@{MaxProcessesPerShell="10000"}'
winrm set winrm/config/winrs '@{MaxShellsPerUser="100"}'

# Set power scheme to performance
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# Restart Windows so that all $env variables are set.
Restart-Computer
