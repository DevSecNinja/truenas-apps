Set-StrictMode -Version Latest

function New-SopsEncryptedEnvFile {
    <#
    .SYNOPSIS
    Creates and validates a SOPS-encrypted dotenv file.

    .DESCRIPTION
    Writes non-secret configuration and GENERATE sentinels to a temporary
    template, encrypts it with SOPS, fills generated secrets through stdin, and
    validates the resulting ciphertext without printing decrypted values.

    The recommended parameter set obtains the Age identity through 1Password.
    AgeKeyFile exists for controlled fallback and disposable tests.

    .EXAMPLE
    New-SopsEncryptedEnvFile `
        -TargetPath 'services/example/secret.sops.env' `
        -AgeKeyReference 'op://Private/Age key/password' `
        -TemplateValues ([ordered] @{ DOMAINNAME = 'example.com'; APP_SECRET = 'GENERATE' }) `
        -GeneratedSecrets ([ordered] @{ APP_SECRET = 36 }) `
        -RequiredVariables @('DOMAINNAME', 'APP_SECRET')
    #>
    [CmdletBinding(DefaultParameterSetName = 'OnePassword', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string] $TargetPath,

        [Parameter(Mandatory, ParameterSetName = 'OnePassword')]
        [ValidatePattern('^op://[^"\r\n]+$')]
        [string] $AgeKeyReference,

        [Parameter(Mandatory, ParameterSetName = 'AgeKeyFile')]
        [string] $AgeKeyFile,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TemplateValues,

        [Parameter()]
        [System.Collections.IDictionary] $GeneratedSecrets = @{},

        [Parameter()]
        [string[]] $RequiredVariables = @(),

        [Parameter()]
        [string] $SopsPath,

        [Parameter()]
        [string] $SopsConfigPath,

        [Parameter()]
        [string] $FilenameOverride
    )

    $ErrorActionPreference = 'Stop'
    $minimumSecretBytes = 16
    $maximumSecretBytes = 1024

    if ($TemplateValues.Count -eq 0) {
        throw 'TemplateValues must contain at least one variable'
    }

    foreach ($entry in $TemplateValues.GetEnumerator()) {
        if ([string] $entry.Key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid dotenv variable name: $($entry.Key)"
        }
        if ($null -eq $entry.Value) {
            throw "Template value must not be null: $($entry.Key)"
        }
        if ([string] $entry.Value -match '[\r\n]') {
            throw "Template value must be a single line: $($entry.Key)"
        }
    }

    foreach ($entry in $GeneratedSecrets.GetEnumerator()) {
        $name = [string] $entry.Key
        $byteCount = 0
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid generated-secret variable name: $name"
        }
        if (-not $TemplateValues.Contains($name)) {
            throw "Generated secret is absent from TemplateValues: $name"
        }
        if ([string] $TemplateValues[$name] -ne 'GENERATE') {
            throw "Generated secret must use the GENERATE sentinel: $name"
        }
        if (-not [int]::TryParse([string] $entry.Value, [ref] $byteCount) -or
            $byteCount -lt $minimumSecretBytes -or
            $byteCount -gt $maximumSecretBytes) {
            throw "Generated-secret byte count for $name must be from $minimumSecretBytes to $maximumSecretBytes"
        }
    }

    foreach ($name in $RequiredVariables) {
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid required variable name: $name"
        }
        if (-not $TemplateValues.Contains($name)) {
            throw "Required variable is absent from TemplateValues: $name"
        }
    }

    if ([string]::IsNullOrWhiteSpace($SopsPath)) {
        $resolvedSops = Get-Command sops -ErrorAction SilentlyContinue
        if ($null -ne $resolvedSops) {
            $SopsPath = $resolvedSops.Source
        }
        else {
            $mise = Get-Command mise -ErrorAction SilentlyContinue
            if ($null -eq $mise) {
                throw 'SOPS was not found on PATH and mise is unavailable'
            }
            $SopsPath = ([string] (& $mise.Source which sops)).Trim()
            if ($LASTEXITCODE -ne 0) {
                throw 'mise could not resolve the SOPS executable'
            }
        }
    }

    if (-not (Test-Path -LiteralPath $SopsPath -PathType Leaf)) {
        throw "SOPS executable not found: $SopsPath"
    }
    $SopsPath = (Resolve-Path -LiteralPath $SopsPath).Path

    $resolvedTarget = [IO.Path]::GetFullPath($TargetPath)
    if (Test-Path -LiteralPath $resolvedTarget) {
        throw "Refusing to overwrite existing file: $resolvedTarget"
    }

    $targetDirectory = Split-Path -Parent $resolvedTarget
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        throw "Target directory does not exist: $targetDirectory"
    }

    if ([string]::IsNullOrWhiteSpace($FilenameOverride)) {
        $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $relativeTarget = [IO.Path]::GetRelativePath($repositoryRoot, $resolvedTarget)
        if ($relativeTarget.StartsWith('..')) {
            if ([string]::IsNullOrWhiteSpace($SopsConfigPath)) {
                throw 'Targets outside the repository require SopsConfigPath and FilenameOverride'
            }
            $FilenameOverride = Split-Path -Leaf $resolvedTarget
        }
        else {
            $FilenameOverride = $relativeTarget.Replace('\', '/')
        }
    }
    if ($FilenameOverride -match '[\r\n]') {
        throw 'FilenameOverride must be a single line'
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedTarget, 'Create and validate SOPS-encrypted dotenv file')) {
        return
    }

    $globalSopsArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($SopsConfigPath)) {
        if (-not (Test-Path -LiteralPath $SopsConfigPath -PathType Leaf)) {
            throw "SOPS config file not found: $SopsConfigPath"
        }
        $globalSopsArguments += @('--config', (Resolve-Path -LiteralPath $SopsConfigPath).Path)
    }

    $oldAgeKey = $env:SOPS_AGE_KEY
    $oldAgeKeyCommand = $env:SOPS_AGE_KEY_CMD
    $oldAgeKeyFile = $env:SOPS_AGE_KEY_FILE
    $template = [IO.Path]::GetTempFileName()
    $targetCreated = $false

    try {
        if ($PSCmdlet.ParameterSetName -eq 'OnePassword') {
            if ($null -eq (Get-Command op -ErrorAction SilentlyContinue)) {
                throw '1Password CLI was not found on PATH'
            }

            $totalOnePasswordSteps = $GeneratedSecrets.Count + 3
            Write-Information "[1Password 1/$totalOnePasswordSteps] Authenticating the CLI through 1Password Desktop." -InformationAction Continue
            & op signin | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw '1Password CLI sign-in failed'
            }

            Write-Information "[1Password 2/$totalOnePasswordSteps] Verifying that the CLI has an authenticated account." -InformationAction Continue
            & op whoami | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw '1Password CLI authentication failed'
            }

            $env:SOPS_AGE_KEY = $null
            $env:SOPS_AGE_KEY_FILE = $null
            $env:SOPS_AGE_KEY_CMD = "op read `"$AgeKeyReference`""
        }
        else {
            if (-not (Test-Path -LiteralPath $AgeKeyFile -PathType Leaf)) {
                throw "Age key file not found: $AgeKeyFile"
            }
            $env:SOPS_AGE_KEY = $null
            $env:SOPS_AGE_KEY_CMD = $null
            $env:SOPS_AGE_KEY_FILE = (Resolve-Path -LiteralPath $AgeKeyFile).Path
        }

        $lines = foreach ($entry in $TemplateValues.GetEnumerator()) {
            '{0}={1}' -f $entry.Key, $entry.Value
        }
        [IO.File]::WriteAllLines($template, $lines, [Text.UTF8Encoding]::new($false))

        $targetCreated = $true
        & $SopsPath @globalSopsArguments encrypt `
            --filename-override $FilenameOverride `
            --input-type dotenv `
            --output-type dotenv `
            --output $resolvedTarget `
            $template
        if ($LASTEXITCODE -ne 0) {
            throw 'SOPS encryption failed'
        }

        $generatedIndex = 0
        foreach ($entry in $GeneratedSecrets.GetEnumerator()) {
            $generatedIndex++
            $name = [string] $entry.Key
            $byteCount = [int] $entry.Value
            $bytes = [byte[]]::new($byteCount)
            try {
                [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
                $secret = [Convert]::ToHexString($bytes).ToLowerInvariant()
                $json = ConvertTo-Json -InputObject $secret -Compress
                if ($PSCmdlet.ParameterSetName -eq 'OnePassword') {
                    $step = $generatedIndex + 2
                    Write-Information "[1Password $step/$totalOnePasswordSteps] Retrieving the Age identity so SOPS can update $name." -InformationAction Continue
                }
                $json | & $SopsPath @globalSopsArguments set `
                    --input-type dotenv `
                    --output-type dotenv `
                    --value-stdin `
                    $resolvedTarget `
                    "[`"$name`"]" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "SOPS failed to set $name"
                }
            }
            finally {
                [Array]::Clear($bytes, 0, $bytes.Length)
                Remove-Variable secret, json -ErrorAction SilentlyContinue
            }
        }

        Write-Information '[Local check] Verifying SOPS encryption metadata; no key access.' -InformationAction Continue
        $status = & $SopsPath @globalSopsArguments filestatus $resolvedTarget | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $status.encrypted) {
            throw 'Target file is not SOPS-encrypted'
        }

        if ($PSCmdlet.ParameterSetName -eq 'OnePassword') {
            Write-Information "[1Password $totalOnePasswordSteps/$totalOnePasswordSteps] Retrieving the Age identity for final in-memory validation." -InformationAction Continue
        }

        $required = @{}
        foreach ($name in $RequiredVariables) {
            $required[$name] = $false
        }
        & $SopsPath @globalSopsArguments decrypt `
            --input-type dotenv `
            --output-type dotenv `
            $resolvedTarget |
            ForEach-Object {
                if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                    $name = $Matches[1]
                    $value = $Matches[2]
                    if ($required.ContainsKey($name) -and -not [string]::IsNullOrEmpty($value)) {
                        $required[$name] = $true
                    }
                    if ($value -in @('GENERATE', 'CHANGE_ME')) {
                        throw "An unresolved secret sentinel remains: $name"
                    }
                    $value = $null
                }
            } | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Target file cannot be decrypted'
        }
        $missing = @($required.GetEnumerator() | Where-Object { -not $_.Value })
        if ($missing.Count -gt 0) {
            throw "Required variables are missing: $($missing.Name -join ', ')"
        }

        Write-Information "Encrypted SOPS dotenv file created and validated: $resolvedTarget" -InformationAction Continue
    }
    catch {
        if ($targetCreated) {
            Remove-Item -LiteralPath $resolvedTarget -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $template -Force -ErrorAction SilentlyContinue
        $env:SOPS_AGE_KEY = $oldAgeKey
        $env:SOPS_AGE_KEY_CMD = $oldAgeKeyCommand
        $env:SOPS_AGE_KEY_FILE = $oldAgeKeyFile
    }
}

Export-ModuleMember -Function New-SopsEncryptedEnvFile
