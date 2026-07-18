# ============================================================
# install_agent_windows.ps1 _Installe l'agent Wazuh sur Windows
# A lancer dans PowerShell EN ADMINISTRATEUR
#
# Usage :
#   .\install_agent_windows.ps1 `
#     -ManagerIP 192.168.1.50 `exmple
#     -AgentName PC-COMPTA `
#     -AgentGroup windows-clients
# ============================================================
param(
    [Parameter(Mandatory=$true)][string]$ManagerIP,
    [Parameter(Mandatory=$true)][string]$AgentName,
    [string]$AgentGroup   = "windows-clients",
    [string]$WazuhVersion = "4.14.0-1"
)

$ErrorActionPreference = "Stop"

function Write-Ok   { param($m) Write-Host "[ OK ] $m" -ForegroundColor Green }
function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Err2 { param($m) Write-Host "[FAIL] $m" -ForegroundColor Red }

# Vérifie les droits admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Err2 "Lance PowerShell en tant qu'Administrateur."; exit 1 }

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BundleRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
$ConfSrc    = Join-Path $BundleRoot "configs\agents\ossec-windows.xml"
$OssecConf  = "C:\Program Files (x86)\ossec-agent\ossec.conf"

# Installation si absent
$service = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($null -eq $service) {
    Write-Info "Téléchargement de l'agent Wazuh $WazuhVersion..."
    $msiUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi"
    $msiPath = Join-Path $env:TEMP "wazuh-agent.msi"
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

    Write-Info "Installation (manager=$ManagerIP, nom=$AgentName, groupe=$AgentGroup)..."
    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /q WAZUH_MANAGER=`"$ManagerIP`" WAZUH_AGENT_GROUP=`"$AgentGroup`" WAZUH_AGENT_NAME=`"$AgentName`"" -Wait
} else {
    Write-Info "WazuhSvc déjà présent — mise à jour config uniquement."
}

# Arrêt avant modif config
Stop-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue; Start-Sleep 2

# Fusion config Windows dans ossec.conf
$conf     = Get-Content -Path $OssecConf -Raw
$addition = (Get-Content -Path $ConfSrc -Raw).Trim()
$marker   = "</ossec_config>"

if ($conf.Contains($addition)) {
    Write-Info "Config déjà présente, aucune modification."
} else {
    $backup = "$OssecConf.bak.$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $OssecConf $backup
    $last  = $conf.LastIndexOf($marker)
    $conf  = $conf.Substring(0, $last) + "`r`n" + $addition + "`r`n" + $marker
    Set-Content -Path $OssecConf -Value $conf -Encoding UTF8
    Write-Ok "Config rôle Windows appliquée."
}

# Démarrage
Set-Service -Name "WazuhSvc" -StartupType Automatic
Start-Service -Name "WazuhSvc"; Start-Sleep 2

if ((Get-Service "WazuhSvc").Status -eq "Running") {
    Write-Ok "Agent actif — nom: $AgentName | groupe: $AgentGroup | manager: $ManagerIP"
} else {
    Write-Err2 "Agent non démarré. Vérifie : C:\Program Files (x86)\ossec-agent\ossec.log"
    exit 1
}
