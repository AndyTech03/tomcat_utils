param (
    [String] $JavaVersion,
    [Switch] $Silent
)
Add-Type -AssemblyName "System.Web.Extensions"

class TomcatConfigs {
    [String] $TOMCAT_DIR
    [String] $JAVA_DIR
    [System.Collections.Generic.Dictionary[string, TomcatConfig]] $JAVA_VERSIONS
}

class TomcatConfig {
    $CONNECTORS
    $JAVA_HOME
    $CATALINA_HOME
    $MAVEN_HOME
}

function Set-UserEnvQuick {
    param($Name, $Value)
    $current = [System.Environment]::GetEnvironmentVariable($Name, "User")
    if ($current -ne $Value) {
        [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
    }
}

$JavaVersion = $JavaVersion.Trim()
if ([String]::IsNullOrEmpty($JavaVersion)) {
    Write-Error "[ERROR] JavaVersion is null!"
    exit 1
}

$binDir = $PSScriptRoot
$rootDir = $binDir | Split-Path
$tomcat_configs_path = "$rootDir\tomcat_configs.json"
if (-not (Test-Path $tomcat_configs_path)) {
    Write-Error "[ERROR] Config file not found at $tomcat_configs_path"
    exit 1
}

$serializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
[TomcatConfigs] $tomcat_configs = $serializer.Deserialize((Get-Content -Path $tomcat_configs_path), [TomcatConfigs])
[TomcatConfig] $tomcat_config = $tomcat_configs.JAVA_VERSIONS[$JavaVersion]
if ($null -eq $tomcat_config) {
    Write-Error "[ERROR] Config for JavaVersion='$($JavaVersion)' not found in $tomcat_configs_path"
    exit 1
}

$env:CATALINA_HOME = $tomcat_config.CATALINA_HOME
$env:JAVA_HOME = $tomcat_config.JAVA_HOME
$env:MAVEN_HOME = $tomcat_config.MAVEN_HOME
$env:TOMCAT_HOST = "http://localhost:$($tomcat_config.CONNECTORS['HTTP/1.1'])"

Set-UserEnvQuick "CATALINA_HOME" $env:CATALINA_HOME
Set-UserEnvQuick "JAVA_HOME"     $env:JAVA_HOME
Set-UserEnvQuick "MAVEN_HOME"    $env:MAVEN_HOME

if (!$Silent) {
    Write-Host "[INFO] Envoirement setuped for JavaVersion='$JavaVersion'"
    Write-Host "[INFO] CATALINA_HOME = $( $env:CATALINA_HOME )"
    Write-Host "[INFO] JAVA_HOME = $( $env:JAVA_HOME )"
    Write-Host "[INFO] MAVEN_HOME = $( $env:MAVEN_HOME )"
    Write-Host "[INFO] TOMCAT_HOST = $( $env:TOMCAT_HOST )"
}