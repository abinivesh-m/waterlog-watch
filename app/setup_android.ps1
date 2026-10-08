# One-time setup: generates the Android project files and adds permissions.
# Run from this folder:  powershell -ExecutionPolicy Bypass -File .\setup_android.ps1
$ErrorActionPreference = "Stop"
flutter create --org com.waterlogwatch --project-name waterlog_watch --platforms android .

$manifest = "android\app\src\main\AndroidManifest.xml"
$xml = Get-Content $manifest -Raw
if ($xml -notmatch "ACCESS_FINE_LOCATION") {
  $perms = @"
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
"@
  $xml = $xml -replace '(<manifest[^>]*>)', "`$1`r`n$perms"
}
$xml = $xml -replace 'android:label="waterlog_watch"', 'android:label="Waterlog Watch"'
Set-Content -Path $manifest -Value $xml -Encoding UTF8
flutter pub get
Write-Host "`nAndroid project ready. Build with:" -ForegroundColor Green
Write-Host "  flutter build apk --release --dart-define=API_URL=<ApiUrl from the AWS deploy>"
