$binDir = $PSScriptRoot
$setup_tomcat_path = "$binDir\setup_tomcat.ps1"

#region env init
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$newPaths = @(
    $binDir,
    "%JAVA_HOME%\bin",
    "%CATALINA_HOME%\bin",
    "%MAVEN_HOME%\bin"
)

$isUpdated = $false
foreach ($path in $newPaths) {
    if ($userPath -notlike "*$path*") {
        $userPath = "$userPath;$path".Replace(";;", ";").Trim(';')
        $isUpdated = $true
    }
}

if ($isUpdated) {
    [System.Environment]::SetEnvironmentVariable("PATH", $userPath, "User")
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + $userPath
    Write-Host "[INFO] Environment variable PATH updated"
} else {
    Write-Warning "[WARN] All paths already exist in PATH"
}
#endregion

# Initial tomcat setup
. "$setup_tomcat_path"