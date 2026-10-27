# Builds the release APK to .\Mimbar.apk.
# Cloud sync is compiled in only when mimbar\supabase.json exists (see README).
# 'Continue': flutter writes harmless warnings to stderr, which 'Stop' treats
# as fatal in Windows PowerShell. Failure is checked via the exit code instead.
$ErrorActionPreference = 'Continue'
$env:JAVA_HOME = 'C:\dev\jdk-17'
$env:ANDROID_HOME = 'C:\dev\android-sdk'
$env:Path = "C:\dev\flutter\bin;C:\dev\jdk-17\bin;$env:Path"

Push-Location "$PSScriptRoot\mimbar"
try {
    $defines = @()
    if (Test-Path supabase.json) {
        $defines = @('--dart-define-from-file=supabase.json')
    } else {
        Write-Warning 'mimbar\supabase.json not found: building without cloud sync.'
    }
    flutter build apk --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
    Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\Mimbar.apk -Force
    Write-Host ("Mimbar.apk: {0:N1} MB" -f ((Get-Item ..\Mimbar.apk).Length / 1MB))
} finally {
    Pop-Location
}
