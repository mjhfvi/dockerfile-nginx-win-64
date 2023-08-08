# escape=`

ARG BASE_OS_VERSION=mcr.microsoft.com/windows/servercore:ltsc2019
FROM ${BASE_OS_VERSION} AS INSTALLER

# Set default version if not provided during build
ARG DEFAULT_VERSION=1.24
ENV VERSION=${NGINX_BRANCH_VERSION:-$DEFAULT_VERSION}

# Restore the default Windows shell for correct batch processing.
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';"]

### Chocolatey Setup ####
# set chocolatey version
ENV chocolateyVersion=1.4.0

# Install Chocolatey
RUN Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Updates the environment variables of the current powershell session
RUN [Environment]::SetEnvironmentVariable('PATH', $env:PATH, [EnvironmentVariableTarget]::User)

# Verify Chocolatey is installed
RUN choco --version

# Install  Chocolatey Tools
RUN choco install git strawberryperl sed 7zip -y
### Chocolatey Setup ####

# Clone Nginx Repository
RUN git clone -b branches/stable-$env:VERSION https://github.com/nginx/nginx.git

# Install Build Tools
RUN New-Item -ItemType Directory -Path C:\nginx\objs\lib\ -Force; `
    Write-Host "Downloading MSYS2 Tool"; `
    Invoke-WebRequest -OutFile msys2-x86_64-latest.tar.xz -UseBasicParsing "http://repo.msys2.org/distrib/msys2-x86_64-latest.tar.xz"; `
    7z x msys2-x86_64-latest.tar.xz -y; `
    7z x msys2-x86_64-latest.tar -y;`
    Write-Host "Downloading NASM Tool"; `
    Invoke-WebRequest -OutFile nasm.zip -UseBasicParsing "https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/win64/nasm-2.15.05-win64.zip"; `
    Expand-Archive nasm.zip -DestinationPath C:\nasm-zip; `
	Move-Item -Path C:\nasm-zip\nasm-2.15.05 -Destination c:\nasm; `
    Write-Host "Downloading PCRE2 Tool"; `
    Invoke-WebRequest -OutFile pcre2.zip -UseBasicParsing "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.40/pcre2-10.40.zip"; `
    Expand-Archive pcre2.zip  -DestinationPath C:\pcre2-zip; `
	Move-Item -Path C:\pcre2-zip\pcre2-10.40 -Destination c:\nginx\objs\lib\pcre2; `
    Write-Host "Downloading ZLIB Tool"; `
    Invoke-WebRequest -OutFile zlib.zip -UseBasicParsing "https://zlib.net/zlib1213.zip"; `
    Expand-Archive zlib.zip  -DestinationPath C:\zlib-zip; `
	Move-Item -Path C:\zlib-zip\zlib-1.2.13 -Destination c:\nginx\objs\lib\zlib; `
    Write-Host "Downloading OpenSSL Tool"; `
    Invoke-WebRequest -OutFile openssl-1.1.1q.tar.gz -UseBasicParsing "https://www.openssl.org/source/openssl-1.1.1q.tar.gz"; `
    7z x openssl-1.1.1q.tar.gz -y; `
    7z x openssl-1.1.1q.tar -y; `
    Rename-Item -Path C:\openssl-1.1.1q -NewName openssl; `
	Move-Item -Path C:\openssl -Destination C:\nginx\objs\lib\; `
    Write-Host "Downloading Visual Studio Build Tools"; `
	Invoke-WebRequest -OutFile vs_buildtools.exe -UseBasicParsing "https://aka.ms/vs/15/release/vs_buildtools.exe"

# Install Visual Studio Build Tools, Change Tools: https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio
SHELL ["cmd", "/S", "/C"]
RUN c:\vs_buildtools.exe --noUpdateInstaller --quiet --wait --norestart --nocache --installPath "C:\\BuildTools"`
	--add Microsoft.VisualStudio.Workload.MSBuildTools `
	--add Microsoft.VisualStudio.Workload.VCTools `
	--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
	--add Microsoft.VisualStudio.Component.VC.CMake.Project `
	--add Microsoft.VisualStudio.Component.TestTools.BuildTools `
	--add Microsoft.VisualStudio.Component.VC.ASAN `
	--add Microsoft.VisualStudio.Component.VC.CMake.Project `
	--add Microsoft.VisualStudio.Component.VC.ATL `
	|| IF "%ERRORLEVEL%"=="3010" EXIT 0 `
    `
    # Cleanup
    && del /q vs_buildtools.exe

# Set System Variables
SHELL ["cmd", "/S", "/C"]
RUN setx /M path "%path%;C:\tools\msys64;c:\msys64;c:\nasm;C:\BuildTools\VC\Tools\MSVC\14.16.27023\bin\Hostx64\x64\"

# Change Shell Powrshell
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';"]

# Replace Default Document With Edit One
WORKDIR C:/nginx
COPY . .
RUN Remove-Item -Path c:/nginx/auto/lib/openssl/makefile.msvc; `
    Copy-Item makefile.msvc -Destination c:/nginx/auto/lib/openssl/ -Recurse -force; `
    Remove-Item -Path c:/nginx/auto/cc/msvc; `
    Copy-Item msvc -Destination c:/nginx/auto/cc/ -Recurse -force

# Run the Compile Process
SHELL ["cmd", "/S", "/C"]

RUN ["C:\\Program Files\\git\\bin\\sh.exe", "C:\\nginx\\compile-nginx.sh"]

# Change Shell x64 Native Tools Command Prompt
SHELL ["cmd", "/k", "\"C:\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat\"", "amd64", "&&"]

WORKDIR C:/nginx
USER ContainerAdministrator
RUN nmake.exe /f C:/nginx/objs/Makefile

# Verify the Nginx Version
RUN C:/nginx/objs/nginx.exe -v

# Build the Nginx Image for Windows Nano 2019
FROM mcr.microsoft.com/windows/nanoserver:ltsc2019

# Building Nginx Folder Structure
RUN mkdir C:\nginx C:\nginx\conf C:\nginx\logs C:\nginx\temp

# Getting the Nginx File from the Previous Build Stage
COPY --from=INSTALLER C:\nginx\objs\nginx.exe C:\nginx\
COPY --from=INSTALLER C:\nginx\conf\. C:\nginx\conf\

LABEL "NGINX_VERSION"="$env:VERSION"
LABEL "OS_VERSION"="nanoserver:ltsc2019"

WORKDIR C:/nginx

EXPOSE 80

ENTRYPOINT ["nginx"]

CMD ["-g", "daemon off;"]
