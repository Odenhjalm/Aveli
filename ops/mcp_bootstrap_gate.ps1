Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$EnvPath = Join-Path $RootDir ".env"
$McpPath = Join-Path $RootDir ".vscode/mcp.json"

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Test-StructuredObject([object]$Object) {
    return $null -ne $Object -and (
        $Object -is [pscustomobject] -or
        $Object -is [System.Collections.IDictionary]
    )
}

function Test-ObjectProperty([object]$Object, [string]$Name) {
    if (-not (Test-StructuredObject -Object $Object)) {
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
    if (-not (Test-StructuredObject -Object $Object)) {
        Fail "$Context is not an object"
    }

    if (-not (Test-ObjectProperty -Object $Object -Name $Name)) {
        Fail "$Context missing property: $Name"
    }

    return $Object.PSObject.Properties[$Name].Value
}

function Assert-NonEmptyConfiguredValue([object]$Value, [string]$Context) {
    $text = Assert-NonEmptyTextValue -Value $Value -Context $Context
    if ($text -match '\$\{[^}]+\}') {
        Fail "$Context contains unresolved placeholders"
    }

    return $text
}

function Assert-NonEmptyTextValue([object]$Value, [string]$Context) {
    if ($null -eq $Value) {
        Fail "$Context is null"
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        Fail "$Context is empty"
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
    return $match.Groups[1].Value
}

function Assert-ExactBinding(
    [object]$Value,
    [string]$ExpectedLiteral,
    [string]$FailureMessage,
    [string]$Context
) {
    $text = Assert-NonEmptyTextValue -Value $Value -Context $Context
    if ($text -cne $ExpectedLiteral) {
        Fail $FailureMessage
    }
}

function Assert-BearerBinding(
    [object]$Value,
    [string]$ExpectedTokenLiteral,
    [string]$FailureMessage,
    [string]$Context
) {
    $header = Assert-NonEmptyTextValue -Value $Value -Context $Context
    $expectedHeader = "Bearer $ExpectedTokenLiteral"
    if ($header -cne $expectedHeader) {
        Fail $FailureMessage
    }
}

function Assert-OnlyApprovedMcpBindings(
    [object]$Node,
    [string]$Path,
    [hashtable]$AllowedBindings
) {
    if ($null -eq $Node) {
        return
    }

    if ($Node -is [string]) {
        if ($Node -match '\$\{[^}]+\}') {
            if (-not $AllowedBindings.ContainsKey($Path) -or
                [string]$AllowedBindings[$Path] -cne $Node) {
                Fail "mcp.json contains unresolved placeholders"
            }
        }
        return
    }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) {
                [string]$key
            } else {
                "$Path.$key"
            }
            Assert-OnlyApprovedMcpBindings -Node $Node[$key] -Path $childPath -AllowedBindings $AllowedBindings
        }
        return
    }

    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) {
                $property.Name
            } else {
                "$Path.$($property.Name)"
            }
            Assert-OnlyApprovedMcpBindings -Node $property.Value -Path $childPath -AllowedBindings $AllowedBindings
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $index = 0
        foreach ($item in $Node) {
            $childPath = "$Path[$index]"
            Assert-OnlyApprovedMcpBindings -Node $item -Path $childPath -AllowedBindings $AllowedBindings
            $index += 1
        }
    }
}

function Get-OptionalMcpServerConfig([object]$Servers, [string]$Name) {
    if (-not (Test-ObjectProperty -Object $Servers -Name $Name)) {
        return $null
    }

    return Get-McpServerConfig -Servers $Servers -Name $Name
}

function Get-McpServerConfig([object]$Servers, [string]$Name) {
    if (-not (Test-ObjectProperty -Object $Servers -Name $Name)) {
        Fail "invalid MCP server config: $Name"
    }

    $server = $Servers.PSObject.Properties[$Name].Value
    if (-not (Test-StructuredObject -Object $server)) {
        Fail "invalid MCP server config: $Name"
    }

    if (-not (Test-ObjectProperty -Object $server -Name "type")) {
        Fail "invalid MCP server config: $Name"
    }

    $serverType = [string]$server.PSObject.Properties["type"].Value
    if ([string]::IsNullOrWhiteSpace($serverType)) {
        Fail "invalid MCP server config: $Name"
    }

    switch ($serverType) {
        "http" {
            if (-not (Test-ObjectProperty -Object $server -Name "url")) {
                Fail "invalid MCP server config: $Name"
            }
            [void](Assert-NonEmptyTextValue -Value $server.PSObject.Properties["url"].Value -Context "$Name url")
        }
        "stdio" {
            if (-not (Test-ObjectProperty -Object $server -Name "command") -or
                -not (Test-ObjectProperty -Object $server -Name "args")) {
                Fail "invalid MCP server config: $Name"
            }

            [void](Assert-NonEmptyTextValue -Value $server.PSObject.Properties["command"].Value -Context "$Name command")
            $args = @($server.PSObject.Properties["args"].Value)
            if ($args.Count -eq 0) {
                Fail "invalid MCP server config: $Name"
            }
            foreach ($arg in $args) {
                [void](Assert-NonEmptyTextValue -Value $arg -Context "$Name args")
            }
        }
        default {
            Fail "invalid MCP server config: $Name"
        }
    }

    return $server
}

function Get-SupabaseProjectRefFromUrl([string]$Url) {
    try {
        $uri = [System.Uri]$Url
    }
    catch {
        Fail "invalid MCP server config: supabase"
    }

    $hostMatch = [System.Text.RegularExpressions.Regex]::Match(
        $uri.Host,
        '^(?<project_ref>[A-Za-z0-9-]+)\.supabase\.co$'
    )
    if ($hostMatch.Success) {
        return $hostMatch.Groups["project_ref"].Value
    }

    if ($uri.Host -eq "mcp.supabase.com" -and -not [string]::IsNullOrWhiteSpace($uri.Query)) {
        foreach ($pair in $uri.Query.TrimStart("?").Split("&")) {
            if ([string]::IsNullOrWhiteSpace($pair)) {
                continue
            }

            $parts = $pair.Split("=", 2)
            $key = [System.Uri]::UnescapeDataString($parts[0])
            if ($key -ne "project_ref") {
                continue
            }

            $value = if ($parts.Count -gt 1) {
                [System.Uri]::UnescapeDataString($parts[1])
            } else {
                ""
            }
            return Assert-NonEmptyConfiguredValue -Value $value -Context "supabase project_ref"
        }
    }

    Fail "invalid MCP server config: supabase"
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

    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        Fail "invalid mcp.json (malformed JSON)"
    }

    $servers = Get-RequiredProperty -Object $config -Name "servers" -Context "mcp.json root"
    $validatedServers = @{}

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
        $validatedServers[$name] = Get-McpServerConfig -Servers $servers -Name $name
    }

    foreach ($name in @("stripe", "netlify")) {
        $optionalServer = Get-OptionalMcpServerConfig -Servers $servers -Name $name
        if ($null -ne $optionalServer) {
            $validatedServers[$name] = $optionalServer
        }
    }

    $figma = $validatedServers["figma"]
    $figmaArgs = @(Get-RequiredProperty -Object $figma -Name "args" -Context "figma")
    $figmaKeyIndex = [Array]::IndexOf($figmaArgs, "--figma-api-key")
    if ($figmaKeyIndex -lt 0 -or $figmaKeyIndex -ge ($figmaArgs.Count - 1)) {
        Fail "figma API key arg is empty"
    }
    $figmaAuthPath = "servers.figma.args[{0}]" -f ($figmaKeyIndex + 1)

    $allowedBindings = @{
        "servers.context7.headers.Authorization" = 'Bearer ${CONTEXT7_TOKEN}'
        ($figmaAuthPath) = '${FIGMA_ACCESS_TOKEN}'
    }

    if ($validatedServers.ContainsKey("stripe")) {
        $allowedBindings["servers.stripe.headers.Authorization"] = 'Bearer ${STRIPE_SECRET_KEY}'
    }

    Assert-OnlyApprovedMcpBindings -Node $config -Path "" -AllowedBindings $allowedBindings

    foreach ($name in @("context7", "supabase")) {
        $server = $validatedServers[$name]
        $serverType = [string](Get-RequiredProperty -Object $server -Name "type" -Context $name)
        if ($serverType -ne "http") {
            Fail "$name must use http transport"
        }
        $serverUrl = Assert-NonEmptyTextValue -Value (Get-RequiredProperty -Object $server -Name "url" -Context $name) -Context "$name url"
        if (-not ($serverUrl -match '^https?://')) {
            Fail "$name URL is not absolute"
        }

        if ($name -eq "supabase") {
            $supabaseProjectRef = Get-SupabaseProjectRefFromUrl -Url $serverUrl
            if ($supabaseProjectRef -ne $script:ExpectedSupabaseProjectRef) {
                Fail "supabase project mismatch"
            }
            if (Test-ObjectProperty -Object $server -Name "headers") {
                Fail "supabase must not define headers; use SUPABASE_PAT from the environment"
            }
            continue
        }

        if ($serverUrl -ne $script:ExpectedContext7Url) {
            Fail "context7 url mismatch"
        }

        if (-not (Test-ObjectProperty -Object $server -Name "headers")) {
            Fail "context7 auth not bound to CONTEXT7_TOKEN"
        }

        $headers = Get-RequiredProperty -Object $server -Name "headers" -Context $name
        $authorization = Get-RequiredProperty -Object $headers -Name "Authorization" -Context "$name headers"
        Assert-BearerBinding `
            -Value $authorization `
            -ExpectedTokenLiteral '${CONTEXT7_TOKEN}' `
            -FailureMessage "context7 auth not bound to CONTEXT7_TOKEN" `
            -Context "$name Authorization header"
    }

    $figmaType = [string](Get-RequiredProperty -Object $figma -Name "type" -Context "figma")
    $figmaCommand = [string](Get-RequiredProperty -Object $figma -Name "command" -Context "figma")
    if ($figmaType -ne "stdio" -or $figmaCommand -ne "npx") {
        Fail "figma must use stdio transport through npx"
    }
    if (-not ($figmaArgs -contains "figma-developer-mcp") -or
        -not ($figmaArgs -contains "--stdio") -or
        -not ($figmaArgs -contains "--figma-api-key")) {
        Fail "figma stdio args are missing the verified package, stdio flag, or API key flag"
    }
    if ([string]::IsNullOrWhiteSpace([string]$figmaArgs[$figmaKeyIndex + 1])) {
        Fail "figma API key arg is empty"
    }
    Assert-ExactBinding `
        -Value $figmaArgs[$figmaKeyIndex + 1] `
        -ExpectedLiteral '${FIGMA_ACCESS_TOKEN}' `
        -FailureMessage "figma auth not bound to FIGMA_ACCESS_TOKEN" `
        -Context "figma API key arg"

    $playwright = $validatedServers["playwright"]
    $playwrightType = [string](Get-RequiredProperty -Object $playwright -Name "type" -Context "playwright")
    $playwrightCommand = [string](Get-RequiredProperty -Object $playwright -Name "command" -Context "playwright")
    if ($playwrightType -ne "stdio" -or $playwrightCommand -ne "npx") {
        Fail "playwright must use stdio transport through npx"
    }
    $playwrightArgs = @(Get-RequiredProperty -Object $playwright -Name "args" -Context "playwright")
    if (-not (($playwrightArgs -join " ") -match '@playwright/mcp')) {
        Fail "playwright args do not reference @playwright/mcp"
    }

    if ($validatedServers.ContainsKey("stripe")) {
        $stripe = $validatedServers["stripe"]
        $stripeType = [string](Get-RequiredProperty -Object $stripe -Name "type" -Context "stripe")
        if ($stripeType -ne "http") {
            Fail "stripe must use http transport"
        }
        $stripeUrl = Assert-NonEmptyTextValue -Value (Get-RequiredProperty -Object $stripe -Name "url" -Context "stripe") -Context "stripe url"
        if (-not ($stripeUrl -match '^https?://')) {
            Fail "stripe URL is not absolute"
        }

        if (-not $script:HasStripeSecretKey) {
            Fail "stripe auth not bound to STRIPE_SECRET_KEY"
        }

        if (-not (Test-ObjectProperty -Object $stripe -Name "headers")) {
            Fail "stripe auth not bound to STRIPE_SECRET_KEY"
        }

        $headers = $stripe.PSObject.Properties["headers"].Value
        if (-not (Test-StructuredObject -Object $headers)) {
            Fail "stripe auth not bound to STRIPE_SECRET_KEY"
        }
        if (-not (Test-ObjectProperty -Object $headers -Name "Authorization")) {
            Fail "stripe auth not bound to STRIPE_SECRET_KEY"
        }

        $authorization = [string]$headers.PSObject.Properties["Authorization"].Value
        if ($authorization -cne 'Bearer ${STRIPE_SECRET_KEY}') {
            Fail "stripe auth not bound to STRIPE_SECRET_KEY"
        }
    }

    if ($validatedServers.ContainsKey("netlify")) {
        $netlify = $validatedServers["netlify"]
        $netlifyType = [string](Get-RequiredProperty -Object $netlify -Name "type" -Context "netlify")
        $netlifyCommand = [string](Get-RequiredProperty -Object $netlify -Name "command" -Context "netlify")
        if ($netlifyType -ne "stdio" -or $netlifyCommand -ne "npx") {
            Fail "netlify must use stdio transport through npx"
        }
        $netlifyArgs = @(Get-RequiredProperty -Object $netlify -Name "args" -Context "netlify")
        if (-not (($netlifyArgs -join " ") -match '@netlify/mcp')) {
            Fail "netlify args do not reference @netlify/mcp"
        }
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
    $script:ExpectedContext7Url = Assert-ValidEnvValue -Values $envValues -Key "CONTEXT7_URL"
    [void](Assert-ValidEnvCredential -Values $envValues -Key "CONTEXT7_TOKEN")
    [void](Assert-ValidEnvCredential -Values $envValues -Key "FIGMA_ACCESS_TOKEN")
    $script:ExpectedSupabaseProjectRef = [string]$envValues["SUPABASE_PROJECT_REF"]
    $script:ExpectedContext7Token = [string]$envValues["CONTEXT7_TOKEN"]
    $script:ExpectedFigmaAccessToken = [string]$envValues["FIGMA_ACCESS_TOKEN"]
    $script:HasStripeSecretKey = $envValues.ContainsKey("STRIPE_SECRET_KEY")
    if ($script:HasStripeSecretKey) {
        [void](Assert-ValidCredentialValue -Value $envValues["STRIPE_SECRET_KEY"] -Context "env key STRIPE_SECRET_KEY")
    }
    foreach ($key in $forbiddenEnvKeys) {
        if ($envValues.ContainsKey($key)) {
            Fail "Forbidden near-miss env key is still present: $key"
        }
    }

    Assert-NodeRuntime
    Assert-McpConfig

    Write-Output "MCP_BOOTSTRAP_GATE_OK"
    exit 0
}
catch {
    Fail "Unexpected bootstrap gate failure"
}
