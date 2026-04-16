param (
    [String] $JavaVersion,
    [String] $GroupId,
    [Switch] $Silent
)
$groupId = $GroupId.Trim()
# $groupId = 'my.group.id'
if ([String]::IsNullOrEmpty($groupId)) {
    Write-Error "[ERROR] GroupId is null!"
    exit 1
}

# Enable selected env
$binDir = $PSScriptRoot
$activate_tomcat_env_path = "$binDir\activate_tomcat_env.ps1"
. "$activate_tomcat_env_path" $JavaVersion -Silent:$Silent

$mvnPath = Join-Path ($env:MAVEN_HOME.Trim('"')) "bin\mvn.cmd"
$projectName = $pwd | Split-Path -Leaf
$version = "1.0.0-$projectName"
$libDir = Join-Path $PWD 'src\main\webapp\WEB-INF\lib'

$mainArgs = @(
    "install:install-file",
    "-Dpackaging=jar"
)

if (!$Silent) {
    $propertiesXML = "
    <properties>
        <installed.libs.version>$($version)</installed.libs.version>
        ...
    </properties>
    <dependencies>"
}

Get-ChildItem $libDir -Filter *.jar | ForEach-Object {
    $file = $_.FullName
    $artifactId = $_.BaseName
#    $processArgs = @{
#        FilePath     = "$mvnPath.cmd"
#        ArgumentList = "install:install-file `"-Dfile=$file`" `"-DgroupId=$groupId`" `"-DartifactId=$artifactId`" `"-Dversion=$version`" `"-Dpackaging=jar`""
#        NoNewWindow  = $true
#        Wait         = $true
#    }
    $mvnArgs = @(
        "-Dfile=$file",
        "-DgroupId=$groupId",
        "-DartifactId=$artifactId",
        "-Dversion=$version"
    )
#    # Если включен режим Silent, добавляем перенаправление потоков в $null
#    if ($Silent) {
#        $processArgs["RedirectStandardOutput"] = "NUL" # В Windows используется NUL
#        $processArgs["RedirectStandardError"]  = "NUL"
#    }

    if ($Silent) {
        & $mvnPath $mainArgs $mvnArgs > $null 2>&1
    } else {
        & $mvnPath $mainArgs $mvnArgs
    }

#    Start-Process @processArgs
    if (!$Silent) {
        $propertiesXML += "
    <dependency>
        <groupId>$($groupId)</groupId>
        <artifactId>$($artifactId)</artifactId>
        <version>`${installed.libs.version}</version>
    </dependency>"
    }
}
if (!$Silent) {
    Write-Host $propertiesXML "
        ...
    <dependencies>"
}
