$catalina = "$env:CATALINA_HOME\bin\catalina.bat"
Write-Host "[INFO] env CATALINA_HOME = $($env:CATALINA_HOME)"
Write-Host "[INFO] env JAVA_HOME = $($env:JAVA_HOME)"
Write-Host "[INFO] catalina = $($catalina)"
Write-Host "`n"

try {
    & $catalina run
} catch {
    Write-Host "[ERROR] An error occurred while starting Tomcat: $_"
}

Write-Host "`n`nPress any button to close window..."
while ($true) {
    if ($Host.UI.RawUI.KeyAvailable) {
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        break
    }
    Start-Sleep -Milliseconds 100
}