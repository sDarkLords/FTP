<#
  .SYNOPSIS
  Tworzenia kopii zapasowych z kompresją i wysyłką przez FTP
  
  .DESCRIPTION
  Skrypt tworzy archiwum ZIP z wybranych plików/folderyów i przesyła je na serwer FTP
  
  .PARAMETER SourcePaths 
  Parametr określa ścieżki do plików/folderyów, które użytkownik chce wysłać na serwer FTP

  .PARAMETER BackupName
  Parametr określa nazwę folderu, do któgo skrypt przenosi pliki/foldery i tworzy z niego archiwum ZIP
  
  .PARAMETER FtpServer 
  Parametr określa adres serwera FTP 

  .PARAMETER FtpUser
  Parametr określa nazwę użytkownika do logowania
  
  .PARAMETER FtpPassword
  Parametr określa hasło do logowania
  
  .PARAMETER TempFolder
  Parametr określa tymczasowy folder, w którym będzie tworzone archiwum ZIP przed wysłaniem go na serwer FTP
  
  .PARAMETER CompressionLevel
  Parametr określa poziom kompresji dla tworzonego archiwum ZIP

#>

param (
    [Parameter(Mandatory=$true)]
    [string[]]$SourcePaths,
    [string]$BackupName = "Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [string]$FtpServer = "ftp.dlptest.com",
    [string]$FtpUser = "dlpuser",
    [string]$FtpPassword = "rNrKYTX9g7z3RgJRmxWuGHbeu",
    [string]$FtpDirectory = "/",
    [string]$TempFolder = $env:TEMP,
    [int]$CompressionLevel = 5
)

function Test-FtpConnection {
    param (
        [string]$Server,
        [string]$User,
        [string]$Password
    )
    try {
        Write-Host "Testowanie polaczenia z $Server"
        $request = [System.Net.FtpWebRequest]::Create("ftp://$Server/")
        $request.Credentials = New-Object System.Net.NetworkCredential($User, $Password)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Timeout = 5000
        
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        Write-Host "Blad polaczenia: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function New-BackupArchive {
    param (
        [string[]]$Paths,
        [string]$Destination
    )
    try {
        $archivePath = Join-Path $Destination "$BackupName.zip"
        Compress-Archive -Path $Paths -DestinationPath $archivePath -CompressionLevel Optimal -Force
        return $archivePath
    }
    catch {
        throw "Blad tworzenia archiwum: $_"
    }
}

function Send-FtpFile {
    param (
        [string]$LocalFile,
        [string]$RemoteServer,
        [string]$RemotePath,
        [string]$User,
        [string]$Password
    )
    try {
        $uri = "ftp://$RemoteServer/$($RemotePath.Trim('/'))/$([System.IO.Path]::GetFileName($LocalFile))"
        $webClient = New-Object System.Net.WebClient
        $webClient.Credentials = New-Object System.Net.NetworkCredential($User, $Password)
        $webClient.UploadFile($uri, $LocalFile)
        return $true
    }
    catch {
        Write-Host "Blad wysylania: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

# GŁÓWNA LOGIKA
try {
    # 1. Sprawdź źródła
    foreach ($path in $SourcePaths) {
        if (-not (Test-Path $path)) {
            throw "Nie znaleziono sciezki: $path"
        }
    }

    # 2. Test FTP
    if (-not (Test-FtpConnection -Server $FtpServer -User $FtpUser -Password $FtpPassword)) {
        throw "Nie mozna polaczyc sie z FTP. Sprawdz dane i firewall."
    }

    # 3. Utwórz archiwum
    Write-Host "Tworzenie archiwum"
    $archivePath = New-BackupArchive -Paths $SourcePaths -Destination $TempFolder
    Write-Host "Utworzono: $archivePath" -ForegroundColor Cyan

    # 4. Wyślij
    if ((Send-FtpFile -LocalFile $archivePath -RemoteServer $FtpServer -RemotePath $FtpDirectory -User $FtpUser -Password $FtpPassword)) {
        Write-Host "Backup wyslany pomyslnie!" -ForegroundColor Green
    }
    else {
        Write-Host "Backup utworzony lokalnie, ale nie wyslany." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "KRYTYCZNY BLAD: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # Sprzątanie
    if ($archivePath -and (Test-Path $archivePath)) {
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    }
}