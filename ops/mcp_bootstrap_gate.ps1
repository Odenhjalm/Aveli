param(
    [string]$BackendBaseUrl = "http://127.0.0.1:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$EnvPath = Join-Path $RootDir ".env"
$McpPath = Join-Path $RootDir ".vscode/mcp.json"

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
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

    $config = $raw | ConvertFrom-Json
    $servers = $config.servers

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
        if (-not ($servers.PSObject.Properties.Name -contains $name)) {
            Fail "mcp.json missing server: $name"
        }
    }

    foreach ($name in @("context7", "supabase")) {
        $server = $servers.$name
        if ($server.type -ne "http") {
            Fail "$name must use http transport"
        }
        if (-not ([string]$server.url -match '^https?://')) {
            Fail "$name URL is not absolute"
        }
        if (-not ([string]$server.headers.Authorization -match '^Bearer\s+\S+')) {
            Fail "$name Authorization header is missing a Bearer token"
        }
    }

    $figma = $servers.figma
    if ($figma.type -ne "stdio" -or $figma.command -ne "npx") {
        Fail "figma must use stdio transport through npx"
    }
    $figmaArgs = @($figma.args)
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

    $playwright = $servers.playwright
    if ($playwright.type -ne "stdio" -or $playwright.command -ne "npx") {
        Fail "playwright must use stdio transport through npx"
    }
    if (-not ((@($playwright.args) -join " ") -match '@playwright/mcp')) {
        Fail "playwright args do not reference @playwright/mcp"
    }
}

$envValues = Read-EnvFile $EnvPath
$requiredEnvKeys = @(
    "SUPABASE_PROJECT_REF",
    "SUPABASE_ACCESS_TOKEN",
    "CONTEXT7_URL",
    "CONTEXT7_TOKEN",
    "FIGMA_ACCESS_TOKEN"
)
$forbiddenEnvKeys = @(
    "SUPABASE_ACCES_TOKEN",
    "CONTEXT7_MCP_URL",
    "CONTEXT7_API_KEY",
    "FIGMA_ACCES_TOKEN"
)

foreach ($key in $requiredEnvKeys) {
    if (-not $envValues.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$envValues[$key])) {
        Fail "Missing required env key: $key"
    }
}
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
