# ---------------------------------------------------------------------------
# Render config\config.json from a .env file and config\config.json.template.
#
#   usage: powershell -ExecutionPolicy Bypass -File scripts\render-config.ps1 [-EnvFile ..] [-Template ..] [-Output ..]
#   defaults:  EnvFile  = <repo>\.env
#              Template = <repo>\config\config.json.template
#              Output   = <repo>\config\config.json
#
# Only the parameters documented in .env.example are configurable; everything
# else is baked into the template as a default. INBOUND_MODE is always "both"
# (the template ships both a tun and a mixed inbound), so it is not read here.
# ---------------------------------------------------------------------------
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$Template,
    [string]$Output
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $EnvFile)  { $EnvFile  = Join-Path $root '.env' }
if (-not $Template) { $Template = Join-Path $root 'config\config.json.template' }
if (-not $Output)   { $Output   = Join-Path $root 'config\config.json' }

if (-not (Test-Path -LiteralPath $EnvFile))  { throw "render-config: env file not found: $EnvFile" }
if (-not (Test-Path -LiteralPath $Template)) { throw "render-config: template not found: $Template" }

# ----- load .env ------------------------------------------------------------
$envVars = @{}
foreach ($line in (Get-Content -LiteralPath $EnvFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    $v = $t.Substring($i + 1).Trim()
    if ($v.Length -ge 2 -and
        (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    $envVars[$k] = $v
}

function Get-Var($name, $default) {
    if ($envVars.ContainsKey($name) -and $envVars[$name] -ne '') { return $envVars[$name] }
    return $default
}
function ConvertTo-JsonString($s) { return ($s -replace '\\', '\\' -replace '"', '\"') }

# ----- defaults (for anything .env did not set) -----------------------------
$PROXY_PORT       = Get-Var 'PROXY_PORT'       '8888'
$LISTEN_ADDR      = Get-Var 'LISTEN_ADDR'      '0.0.0.0'
$EXT_SERVER       = Get-Var 'EXT_SERVER'       ''
$EXT_PORT         = Get-Var 'EXT_PORT'         '8080'
$EXT_USERNAME     = Get-Var 'EXT_USERNAME'     ''
$EXT_PASSWORD     = Get-Var 'EXT_PASSWORD'     ''
$EXT_TLS          = Get-Var 'EXT_TLS'          'false'
$EXT_TLS_INSECURE = Get-Var 'EXT_TLS_INSECURE' 'false'
$DNS_TYPE         = Get-Var 'DNS_TYPE'         'https'
$DNS_SERVER       = Get-Var 'DNS_SERVER'       '1.1.1.1'
$LOG_LEVEL        = Get-Var 'LOG_LEVEL'        'info'
$TUN_ADDR         = Get-Var 'TUN_ADDR'         '192.168.30.1/30'

# ----- dns-remote server object ---------------------------------------------
switch -casesensitive ($DNS_TYPE) {
    'local' { $DNS_REMOTE = '{ "type": "local", "tag": "dns-remote" }' }
    { $_ -cin 'https', 'tls', 'udp', 'tcp' } {
        $DNS_REMOTE = '{ "type": "' + $DNS_TYPE + '", "tag": "dns-remote", "server": "' + (ConvertTo-JsonString $DNS_SERVER) + '" }'
    }
    default { throw "render-config: unknown DNS_TYPE='$DNS_TYPE' (use: https, tls, udp, tcp, local)" }
}

# ----- optional auth / tls fragments ----------------------------------------
if ($EXT_USERNAME -ne '') {
    $EXT_AUTH = ', "username": "' + (ConvertTo-JsonString $EXT_USERNAME) + '", "password": "' + (ConvertTo-JsonString $EXT_PASSWORD) + '"'
} else {
    $EXT_AUTH = ''
}

if ($EXT_TLS -ceq 'true') {
    $EXT_TLS_BLOCK = ', "tls": { "enabled": true, "server_name": "' + (ConvertTo-JsonString $EXT_SERVER) + '", "insecure": ' + $EXT_TLS_INSECURE + ' }'
} else {
    $EXT_TLS_BLOCK = ''
}

if ($EXT_SERVER -eq '') { Write-Warning 'render-config: EXT_SERVER is empty -> external outbound has no server.' }

# ----- substitute -----------------------------------------------------------
$map = [ordered]@{
    '__LOG_LEVEL__'   = $LOG_LEVEL
    '__DNS_REMOTE__'  = $DNS_REMOTE
    '__TUN_ADDR__'    = $TUN_ADDR
    '__LISTEN_ADDR__' = $LISTEN_ADDR
    '__PROXY_PORT__'  = $PROXY_PORT
    '__EXT_SERVER__'  = (ConvertTo-JsonString $EXT_SERVER)
    '__EXT_PORT__'    = $EXT_PORT
    '__EXT_AUTH__'    = $EXT_AUTH
    '__EXT_TLS__'     = $EXT_TLS_BLOCK
}

$content = Get-Content -LiteralPath $Template -Raw
foreach ($k in $map.Keys) { $content = $content.Replace($k, [string]$map[$k]) }

# Always write LF without BOM: the file is consumed by sing-box inside Linux.
# Strip trailing whitespace too (an empty auth/tls fragment leaves a blank line).
$content = $content -replace "`r`n", "`n" -replace '[ \t]+(\n)', '$1'
[System.IO.File]::WriteAllText($Output, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "render-config: wrote $Output"
