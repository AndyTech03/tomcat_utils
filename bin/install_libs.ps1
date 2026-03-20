param (
    [String] $GroupId,
    [Switch] $Silent
)
$groupId = $GroupId.Trim()
if ([String]::IsNullOrEmpty($groupId)) {
    Write-Error "[ERROR] GroupId is null!"
    exit 1
}
# $groupId = 'you.group.id'
# Путь до mvn
$mvn = Join-Path ($env:MAVEN_HOME.Trim('"')) '\bin\mvn'
$projectName = $pwd | Split-Path -Leaf
$version = "1.0.0-$projectName"
$libDir = Join-Path $PWD 'src\main\webapp\WEB-INF\lib'

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
    $processArgs = @{
        FilePath     = "$mvn.cmd"
        ArgumentList = "install:install-file `"-Dfile=$file`" `"-DgroupId=$groupId`" `"-DartifactId=$artifactId`" `"-Dversion=$version`" `"-Dpackaging=jar`""
        NoNewWindow  = $true
        Wait         = $true
    }
    # Если включен режим Silent, добавляем перенаправление потоков в $null
    if ($Silent) {
        $processArgs["RedirectStandardOutput"] = "NUL" # В Windows используется NUL
        $processArgs["RedirectStandardError"]  = "NUL"
    }

    Start-Process @processArgs
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
