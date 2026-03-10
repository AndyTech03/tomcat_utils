# Путь до mvn

$mvn = Join-Path ($env:MAVEN_HOME.Trim('"')) '\bin\mvn'
$projectName = $pwd | Split-Path -Leaf
$groupId = 'ru.esstu.ls'
$version = "1.0.0-$projectName"
$libDir = Join-Path $PWD 'src\main\webapp\WEB-INF\lib'

$log = "
    <properties>
        <esstu.version>$($version)</esstu.version>
        ...
    </properties>
    <dependencies>"
Get-ChildItem $libDir -Filter *.jar | ForEach-Object {
    $file = $_.FullName
    $artifactId = $_.BaseName
    Start-Process -FilePath "$mvn.cmd" -ArgumentList "install:install-file `"-Dfile=$file`" `"-DgroupId=$groupId`" `"-DartifactId=$artifactId`" `"-Dversion=$version`" `"-Dpackaging=jar`"" -NoNewWindow -Wait
    $log += "
        <dependency>
            <groupId>$($groupId)</groupId>
            <artifactId>$($artifactId)</artifactId>
            <version>`${esstu.version}</version>
        </dependency>"
}
Write-Host $log "
        ...
    <dependencies>"
