param (
    [String] $JavaVersion,
    [String] [ValidateSet('deploy','start','stop')] $Mode,
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
}

class TomcatInstance {
    [String] $JavaVersion
    [Int64] $Pid
}


$JavaVersion = $JavaVersion.Trim()
if ([String]::IsNullOrEmpty($JavaVersion)) {
    Write-Error "[ERROR] JavaVersion is null!"
    exit 1
}

$binDir = $PSScriptRoot
$rootDir = $binDir | Split-Path
$tomcat_registry_path = "$rootDir\tomcat_registry.json"
$tomcat_wrapper_path = "$binDir\tomcat_wrapper.ps1"
$activate_tomcat_env_path = "$binDir\activate_tomcat_env.ps1"


function GetTomcatInstances {
    if (-not (Test-Path $tomcat_registry_path)) {
        New-Item -Path $tomcat_registry_path -ItemType File -Force | Out-Null
        if (!$Silent) {
            Write-Warning "[WARN] File $tomcat_registry_path not exists, created empty"
        }
    }
    $instances = @()
    $oldInstances = Get-Content $tomcat_registry_path | Out-String | ConvertFrom-Json
    if ($null -eq $oldInstances) {
        $oldInstances = @()
    }
    if (!$oldInstances.GetType().isArray) {
        $oldInstances = @($oldInstances)
    }
    if ($oldInstances) {
        $instances = $oldInstances | Where-Object {
            $processExists = Get-Process -Id $_.Pid -ErrorAction SilentlyContinue
            if (!$Silent -and !$processExists) {
                Write-Host "[INFO] Inactive Tomcat instance JavaVersion='$($_.JavaVersion)' Pid=$($_.Pid)"
            }
            $processExists
        }
    }
    if ($null -eq $instances) {
        $instances = @()
    } elseif (!$instances.GetType().isArray) {
        $instances = @($instances)
    }
    return $instances
}

function SaveTomcatInstances {
    param ($tomcatInstances)
    $jsonString = "[`n]"
    if ($tomcatInstances) {
        $jsonString = $tomcatInstances | ConvertTo-Json -Depth 10 -Debug
        if ($tomcatInstances.GetType().IsArray -eq $false `
            -or $tomcatInstances.Count -eq 1) {
            $jsonString = $jsonString -replace '^|\n', '$0    '
            $jsonString = "[`n$jsonString`n]"
        }
    }
    $jsonString | Set-Content $tomcat_registry_path
}

function RegisterTomcat {
    param($tomcatPid)
    $instances = GetTomcatInstances
    $newInstance = [TomcatInstance]@{
        "JavaVersion" = $JavaVersion
        "Pid" = $tomcatPid
    }
    if ($null -eq $instances) {
        $instances = @($newInstance)
    } elseif ($instances.GetType().IsArray) {
        $instances += $newInstance
    } else {
        $instances = @($instances, $newInstance)
    }
    SaveTomcatInstances $instances
}

function ChechTomcatIsOnline {
    $instances = GetTomcatInstances
    foreach ($instance in $instances) {
        if ($instance.JavaVersion -eq $JavaVersion) {
            $processExists = Get-Process -Id $instance.Pid -ErrorAction SilentlyContinue
            if ($processExists) {
                return $true
            }
        }
    }
    return $false
}

function Stop-Process-Recursive {
    param ($processId)
    Get-WmiObject win32_process | Where-Object { $_.ParentProcessId -eq $processId } | ForEach-Object {
        Stop-Process-Recursive $_.ProcessId
    }
    Stop-Process -Id $processId -Force
}

function RemoveTomcat {
    param ($SilentMode=$Silent)
    $oldInstances = GetTomcatInstances
    $instances = $oldInstances | Where-Object {
        $processExists = Get-Process -Id $_.Pid -ErrorAction SilentlyContinue
        $keepInstance = $processExists -and ($_.JavaVersion -ne $JavaVersion)
        if (!$keepInstance) {
            if ($processExists) {
                if (!$Silent) {
                    Write-Host "[INFO] Stopping and removing Tomcat instance JavaVersion='$($_.JavaVersion)' Pid=$($_.Pid)"
                }
                Stop-Process-Recursive $_.Pid
            } else {
                if (!$Silent) {
                    Write-Host "[INFO] Removing Tomcat instance JavaVersion='$($_.JavaVersion)' Pid=$($_.Pid)"
                }
            }
        }
        $keepInstance
    }
    SaveTomcatInstances $instances
}




function StopTomcat {
    param ($SilentMode=$Silent)
    if (!$SilentMode -and !$(ChechTomcatIsOnline)) {
        Write-Host "[INFO] Tomcat already stopped"
    }
    RemoveTomcat $SilentMode
}

function StartTomcat {
    if (ChechTomcatIsOnline) {
        if (!$Silent) {
            Write-Host "[INFO] Restarting Tomcat..."
        }
        StopTomcat $true
    }
    if (!$Silent) {
        Write-Host "[INFO] Preparing Tomcat..."
    }
    # Enable selected env
    . "$activate_tomcat_env_path" $JavaVersion -Silent:$Silent
    # Run catalina wrapper
    $catalinaProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$tomcat_wrapper_path`"" -PassThru
    $catalinaPid = $catalinaProcess.Id
    if (!$Silent) {
        Write-Host "[INFO] Tomcat process started with Pid=$catalinaPid"
        Write-Host "[INFO] Tomcat address: $env:TOMCAT_HOST"
    }
    RegisterTomcat $catalinaPid
}

function DeployTomcat {
    if (ChechTomcatIsOnline) {
        StopTomcat
    }
    mvn clean package -U
    $targetDir = "$(Get-Location)\target"
    if (-not (Test-Path $targetDir)) {
        Write-Error "[ERROR] Directory 'target' not found. Run 'mvn clean package' before deploying"
        exit 1
    }
    $warFiles = Get-ChildItem -Path $targetDir -Filter "*.war"
    if ($warFiles.Count -eq 0) {
        Write-Error "[ERROR] None '*.war' files were found in 'target' directory"
        exit 1
    } elseif ($warFiles.Count -ne 1) {
        $msg = "[ERROR] More than one '*.war' file was found in directory 'target':"
        $warFiles | ForEach-Object {
            $msg = $msg + "`n`t- " + $_.Name
        }
        Write-Error $msg
        exit 1
    }
    $warFile = $warFiles[0].Name
    if (-not ($warFile -match "(.*?)-.*\.war")) {
        Write-Error "[ERROR] Illegal war file format. File must match the format '<title>-*.war'"
        exit 1
    }
    $artifactName = $Matches[1]
    if (!$Silent) {
        Write-Host "[INFO] Deployung $($artifactName)..."
        Write-Host "[INFO] Make sure you run 'mvn clean package' before deploying"
    }
    $webapps = "$CATALINA_HOME\webapps"
    $artifactDir = "$webapps\$artifactName"
    if (Test-Path $artifactDir) {
        Remove-Item -Path $artifactDir -Force -Recurse
        if (!$Silent) {
            Write-Host "[INFO] Removed $($artifactDir)"
        }
    }
    $oldPath = "$targetDir\$warFile"
    $newPath = "$artifactDir.war"
    Copy-Item $oldPath $newPath
    if (!$Silent) {
        Write-Host "[INFO] Copied $($artifactName) into $webapps folder"
    }
    if (!$Silent) {
        Write-Host "[INFO] Deployment $($artifactName) finished"
    }
    StartTomcat
}


switch ($Mode) {
    'deploy' {
        DeployTomcat
        exit 0
    }
    'start' {
        StartTomcat
        exit 0
    }
    'stop' {
        StopTomcat
        exit 0
    }
    default {
        Write-Error "[ERROR] Invalid Mode='$Mode'. Please use 'deploy', 'start', or 'stop'"
        exit 1
    }
}