$rootDir = "$($PSScriptRoot | Split-Path)"
$tomcat_configs = Get-Content "$rootDir\tomcat_configs.json"  -Raw | ConvertFrom-Json
$TOMCAT_DIR = $tomcat_configs.TOMCAT_DIR
$MANAGER_USERS = $tomcat_configs.MANAGER_USERS
$JAVA_VERSIONS = $tomcat_configs.JAVA_VERSIONS

$tomcatDirs = Get-ChildItem -Path $TOMCAT_DIR
$tomcatDirsPaths = @()
foreach ($tomcatDir in $tomcatDirs) {
    $tomcatDirsPaths += "$($tomcat_configs.TOMCAT_DIR)\$tomcatDir"
}

$configuratedTomcatPaths = @()
$tomcatsJava = @{}
foreach ($config in $JAVA_VERSIONS.psobject.properties | Select-Object name, value) {
    $tomcatPath = $config.Value.CATALINA_HOME
    $configuratedTomcatPaths += $config.Value.CATALINA_HOME
    if ($($tomcatsJava.count) -ne 0) {
        if ($($tomcatsJava.Keys).indexof($tomcatPath) -ne -1) {
            Write-Warning "[WARN] $tomcatPath has unique JavaVersion`n+ Found $($tomcatsJava[$tomcatPath]) and $($config.Name)"
            continue
        }
    }
    $tomcatsJava[$tomcatPath] = $config.Name
}
$compare = Compare-Object -ReferenceObject $tomcatDirsPaths -DifferenceObject $configuratedTomcatPaths -IncludeEqual

$correctTomcats = @()
foreach ($item in $compare) {
    $tomcatPath = $item.InputObject
    if ($item.SideIndicator -eq "=>") {
        if (-not(Test-Path $item.InputObject)) {
            Write-Error "[ERROR] JavaVersion $($tomcatsJava[$tomcatPath]) config using non-existent tomcat $tomcatPath"
        }
        if (($item.InputObject | Split-Path) -ne $TOMCAT_DIR) {
            Write-Warning "[WARN] JavaVersion $($tomcatsJava[$tomcatPath]) config using tomcat instaled not in $TOMCAT_DIR directory"
        }
    } elseif ($item.SideIndicator -eq "<=") {
        Write-Warning "[WARN] $tomcatPath not used in any configuration"
    } else {
        $correctTomcats += $tomcatPath
    }

}
foreach ($tomcatPath in $correctTomcats) {
    Write-Host ""
    $javaVersion = $tomcatsJava[$tomcatPath]
    $shutdownPort = $JAVA_VERSIONS.$javaVersion.SHUTDOWN_PORT
    $serverPath = "$tomcatPath\conf\server.xml"
    [Xml] $server = Get-Content -Path $serverPath
    Write-Host "[INFO] Configurating Server JavaVersion=$javaVersion TomcatPath=$tomcatPath..."
    [System.Xml.XmlElement] $serverNode = $server.ChildNodes | Where-Object { $_.Name -eq "Server"}
    if ($serverNode.GetAttribute("port") -ne $shutdownPort) {
        Write-Warning "[WARN] Server has incorrect shutdown port"
        $serverNode.SetAttribute("port", $shutdownPort)
        Write-Host "[INFO] Set Server shutdown port port=$shutdownPort"
    }
    foreach ($connector in $JAVA_VERSIONS.$javaVersion.CONNECTORS.psobject.properties | Select-Object name, value) {
        $node = $server | Select-Xml -XPath "//Connector[@protocol='$($connector.Name)']"
        [System.Xml.XmlElement] $connectorNode = $node.Node
        if ($null -eq $connectorNode) {
            Write-Warning "[WARN] Connector $($connector.Name) not configurated in $serverPath"
            continue
        }
        if ($connectorNode.GetAttribute("port") -ne $connector.Value) {
            Write-Warning "[WARN] User $($connector.Name) has incorrect port"
            $connectorNode.SetAttribute("port", $connector.Value)
            Write-Host "[INFO] Set Connector $($connector.Name) port=$($connector.Value)"
        }
    }
    $server.Save($serverPath)
    Write-Host "[INFO] Configurating Server finished"

    Write-Host "[INFO] Configurating Users JavaVersion=$javaVersion TomcatPath=$tomcatPath..."
    $tomcatUsersPath = "$tomcatPath\conf\tomcat-users.xml"
    [Xml] $users = Get-Content -Path $tomcatUsersPath
    [System.Xml.XmlElement] $usersNode = $users.ChildNodes | Where-Object { $_.Name -eq "tomcat-users"}
    $namespace = $usersNode.NamespaceURI;
    foreach ($user in $MANAGER_USERS) {
        $nodes = $usersNode.ChildNodes | Where-Object {
            ($_.Name -eq "user")  -and ($_.GetAttribute("username") -eq $user.username)
        }
        if (($null -ne $nodes) -and ($nodes.GetType().IsArray)) {
            Write-Warning "[WARN] Too many Users with username $($user.username) [$($nodes.Count)] in $tomcatUsersPath"
            foreach ($node in $nodes) {
                $usersNode.RemoveChild($node) | Out-Null
            }
            $nodes = $null
            $isArray = $true
        }
        [System.Xml.XmlElement] $userNode = $nodes
        if ($null -eq $userNode) {
            if ($true -ne $isArray ) {
                Write-Warning "[WARN] User $($user.username) not configurated in $tomcatUsersPath"
            }
            Write-Host "[INFO] Creating new User..."
            $userNode = $users.CreateElement("user", $namespace)
            $usersNode.AppendChild($userNode) | Out-Null
            $userNode.SetAttribute("username", $user.username)
            $userNode.SetAttribute("password", $user.password)
            $userNode.SetAttribute("roles", $user.roles)
            Write-Host "[INFO] User created"
            continue
        }
        if ($userNode.GetAttribute("password") -ne $user.password) {
            Write-Warning "[WARN] User $($user.username) has incorrect password"
            $userNode.SetAttribute("password", $user.password)
            Write-Host "[INFO] User password changed"
        }
        if ($userNode.GetAttribute("roles") -ne $user.roles) {
            Write-Warning "[WARN] User $($user.username) has incorrect roles"
            $userNode.SetAttribute("roles", $user.roles)
            Write-Host "[INFO] User roles changed"
        }
        if ($userNode.HasAttribute("xmlns")) {
            $userNode.SetAttribute("xmlns", $namespace)
        }
    }
    $users.Save($tomcatUsersPath)
    Write-Host "[INFO] Configurating Users finished"
}