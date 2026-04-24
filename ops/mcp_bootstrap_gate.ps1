param(
    [string]$BackendBaseUrl = "http://127.0.0.1:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$EnvPath = Join-Path $RootDir ".env"
$McpPath = Join-Path $RootDir ".vscode/mcp.json"

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Test-ObjectProperty([object]$Object, [string]$Name) {
    if ($null -eq $Object) {
        return $false
    }

    $properties = $Object.PSObject.Properties
    if ($null -eq $properties) {
        return $false
    }

    return $properties.Name -contains $Name
}

function Get-RequiredProperty([object]$Object, [string]$Name, [string]$Context) {
    if ($null -eq $Object) {
        Fail "$Context is missing"
    }

    if (-not (Test-ObjectProperty -Object $Object -Name $Name)) {
        Fail "$Context missing property: $Name"
    }

    return $Object.PSObject.Properties[$Name].Value
}

function Assert-NonEmptyConfiguredValue([object]$Value, [string]$Context) {
    if ($null -eq $Value) {
        Fail "$Context is null"
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        Fail "$Context is empty"
    }
    if ($text -match '\$\{[^}]+\}') {
        Fail "$Context contains unresolved placeholders"
    }

    return $text
}

function Assert-ValidCredentialValue([object]$Value, [string]$Context) {
    $text = Assert-NonEmptyConfiguredValue -Value $Value -Context $Context
    if ($text -ieq "local_token") {
        Fail "$Context must not use local_token"
    }
    if ($text.Length -lt 20) {
        Fail "$Context is shorter than 20 characters"
    }

    return $text
}

function Get-RequiredEnvValue([hashtable]$Values, [string]$Key) {
    if (-not $Values.ContainsKey($Key)) {
        Fail "Missing required env key: $Key"
    }

    return $Values[$Key]
}

function Assert-ValidEnvValue([hashtable]$Values, [string]$Key) {
    $value = Get-RequiredEnvValue -Values $Values -Key $Key
    return Assert-NonEmptyConfiguredValue -Value $value -Context "env key $Key"
}

function Assert-ValidEnvCredential([hashtable]$Values, [string]$Key) {
    $value = Get-RequiredEnvValue -Values $Values -Key $Key
    return Assert-ValidCredentialValue -Value $value -Context "env key $Key"
}

function Assert-BearerCredential([object]$Value, [string]$Context) {
    $header = Assert-NonEmptyConfiguredValue -Value $Value -Context $Context
    $match = [System.Text.RegularExpressions.Regex]::Match($header, '^Bearer\s+(.+)$')
    if (-not $match.Success) {
        Fail "$Context is missing a Bearer token"
    }

    [void](Assert-ValidCredentialValue -Value $match.Groups[1].Value -Context "$Context token")
}

function Read-EnvFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "Missing env file: $Path"
    }

    $values = @{}
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            continue
        }

        if ($line.StartsWith("export ")) {
            $line = $line.Substring(7).Trim()
        }

        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($key) {
            $values[$key] = $value
        }
    }

    return $values
}

function Assert-HttpOk([string]$Path) {
    $uri = "$BackendBaseUrl$Path"
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5
        if ([int]$response.StatusCode -ne 200) {
            Fail "$uri returned HTTP $($response.StatusCode)"
        }
    }
    catch {
        Fail "$uri is not reachable: $($_.Exception.Message)"
    }
}

function Assert-NodeRuntime {
    $nodeDir = "C:\Program Files\nodejs"
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -and
        (Test-Path -LiteralPath (Join-Path $nodeDir "node.exe"))) {
        $env:Path = "$nodeDir;$env:Path"
    }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
    if (-not $node) {
        Fail "node.exe is not installed or not resolvable"
    }
    if (-not $npx) {
        Fail "npx.cmd is not installed or not resolvable"
    }

    & $node.Source -v | Out-Null
    & $npx.Source -v | Out-Null
}

function Assert-McpConfig {
    if (-not (Test-Path -LiteralPath $McpPath)) {
        Fail "Missing MCP config: $McpPath"
    }

    $raw = Get-Content -LiteralPath $McpPath -Raw
    if ($raw -match '\$\{[^}]+\}') {
        Fail "mcp.json contains unresolved placeholders"
    }

    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        Fail "mcp.json is not valid JSON: $($_.Exception.Message)"
    }

    $servers = Get-RequiredProperty -Object $config -Name "servers" -Context "mcp.json root"

    foreach ($name in @(
        "aveli-logs",
        "aveli-media-control-plane",
        "aveli-domain-observability",
        "aveli-verification",
        "context7",
        "supabase",
        "playwright",
        "figma"
    )) {
        [void](Get-RequiredProperty -Object $servers -Name $name -Context "mcp.json servers")
    }

    foreach ($name in @("context7", "supabase")) {
        $server = Get-RequiredProperty -Object $servers -Name $name -Context "mcp.json servers"
        $serverType = [string](Get-RequiredProperty -Object $server -Name "type" -Context $name)
        if ($serverType -ne "http") {
            Fail "$name must use http transport"
        }
        $serverUrl = Assert-NonEmptyConfiguredValue -Value (Get-RequiredProperty -Object $server -Name "url" -Context $name) -Context "$name url"
        if (-not ($serverUrl -match '^https?://')) {
            Fail "$name URL is not absolute"
        }

        if ($name -eq "supabase") {
            if (Test-ObjectProperty -Object $server -Name "headers") {
                Fail "supabase must not define headers; use SUPABASE_PAT from the environment"
            }
            continue
        }

        $headers = Get-RequiredProperty -Object $server -Name "headers" -Context $name
        $authorization = Get-RequiredProperty -Object $headers -Name "Authorization" -Context "$name headers"
        Assert-BearerCredential -Value $authorization -Context "$name Authorization header"
    }

    $figma = Get-RequiredProperty -Object $servers -Name "figma" -Context "mcp.json servers"
    $figmaType = [string](Get-RequiredProperty -Object $figma -Name "type" -Context "figma")
    $figmaCommand = [string](Get-RequiredProperty -Object $figma -Name "command" -Context "figma")
    if ($figmaType -ne "stdio" -or $figmaCommand -ne "npx") {
        Fail "figma must use stdio transport through npx"
    }
    $figmaArgs = @(Get-RequiredProperty -Object $figma -Name "args" -Context "figma")
    if (-not ($figmaArgs -contains "figma-developer-mcp") -or
        -not ($figmaArgs -contains "--stdio") -or
        -not ($figmaArgs -contains "--figma-api-key")) {
        Fail "figma stdio args are missing the verified package, stdio flag, or API key flag"
    }
    $keyIndex = [Array]::IndexOf($figmaArgs, "--figma-api-key")
    if ($keyIndex -lt 0 -or $keyIndex -ge ($figmaArgs.Count - 1) -or
        [string]::IsNullOrWhiteSpace([string]$figmaArgs[$keyIndex + 1])) {
        Fail "figma API key arg is empty"
    }
    [void](Assert-ValidCredentialValue -Value $figmaArgs[$keyIndex + 1] -Context "figma API key arg")

    $playwright = Get-RequiredProperty -Object $servers -Name "playwright" -Context "mcp.json servers"
    $playwrightType = [string](Get-RequiredProperty -Object $playwright -Name "type" -Context "playwright")
    $playwrightCommand = [string](Get-RequiredProperty -Object $playwright -Name "command" -Context "playwright")
    if ($playwrightType -ne "stdio" -or $playwrightCommand -ne "npx") {
        Fail "playwright must use stdio transport through npx"
    }
    $playwrightArgs = @(Get-RequiredProperty -Object $playwright -Name "args" -Context "playwright")
    if (-not (($playwrightArgs -join " ") -match '@playwright/mcp')) {
        Fail "playwright args do not reference @playwright/mcp"
    }
}

try {
    $envValues = Read-EnvFile $EnvPath
    $forbiddenEnvKeys = @(
        "SUPABASE_ACCES_TOKEN",
        "CONTEXT7_MCP_URL",
        "CONTEXT7_API_KEY",
        "FIGMA_ACCES_TOKEN"
    )

    [void](Assert-ValidEnvValue -Values $envValues -Key "SUPABASE_PROJECT_REF")
    [void](Assert-ValidEnvCredential -Values $envValues -Key "SUPABASE_PAT")
    [void](Assert-ValidEnvValue -Values $envValues -Key "CONTEXT7_URL")
    [void](Assert-ValidEnvCredential -Values $envValues -Key "CONTEXT7_TOKEN")
    [void](Assert-ValidEnvCredential -Values $envValues -Key "FIGMA_ACCESS_TOKEN")
    foreach ($key in $forbiddenEnvKeys) {
        if ($envValues.ContainsKey($key)) {
            Fail "Forbidden near-miss env key is still present: $key"
        }
    }

    Assert-NodeRuntime
    Assert-McpConfig

    foreach ($path in @(
        "/healthz",
        "/mcp/logs",
        "/mcp/verification",
        "/mcp/media-control-plane",
        "/mcp/domain-observability"
    )) {
        Assert-HttpOk $path
    }

    Write-Output "MCP_BOOTSTRAP_GATE_OK"
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "Unexpected bootstrap gate failure"
    }
    Fail $message
}
