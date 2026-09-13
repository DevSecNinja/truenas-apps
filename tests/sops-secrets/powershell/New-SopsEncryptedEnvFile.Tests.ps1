Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Import-Module (Join-Path $repositoryRoot 'scripts\SopsSecrets.psm1') -Force

$sopsPath = ([string] (mise which sops)).Trim()
$ageKeygenPath = ([string] (mise which age-keygen)).Trim()
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('sops-powershell-test-' + [guid]::NewGuid().ToString('N'))
$keyFile = Join-Path $testRoot 'age.key'
$configFile = Join-Path $testRoot '.sops.yaml'
$target = Join-Path $testRoot 'secret.sops.env'
$failedTarget = Join-Path $testRoot 'failed.sops.env'
$mockSopsPath = Join-Path $testRoot 'mock-sops.ps1'
$templatePathLog = Join-Path $testRoot 'template-path.log'
$oldAgeKey = $env:SOPS_AGE_KEY
$oldAgeKeyCommand = $env:SOPS_AGE_KEY_CMD
$oldAgeKeyFile = $env:SOPS_AGE_KEY_FILE
$oldTemplatePathLog = $env:SOPS_TEST_TEMPLATE_PATH_LOG

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    & $ageKeygenPath -o $keyFile 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create disposable Age identity'
    }
    $recipient = ((& $ageKeygenPath -y $keyFile) | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($recipient)) {
        throw 'Failed to derive disposable Age recipient'
    }

    [IO.File]::WriteAllLines(
        $configFile,
        @(
            '---'
            'creation_rules:'
            '  - path_regex: secret[.]sops[.]env$'
            "    age: $recipient"
        ),
        [Text.UTF8Encoding]::new($false)
    )

    $env:SOPS_AGE_KEY = 'prior-inline-key'
    $env:SOPS_AGE_KEY_CMD = 'prior-key-command'
    $env:SOPS_AGE_KEY_FILE = 'prior-key-file'

    New-SopsEncryptedEnvFile `
        -TargetPath $target `
        -AgeKeyFile $keyFile `
        -SopsPath $sopsPath `
        -SopsConfigPath $configFile `
        -FilenameOverride 'secret.sops.env' `
        -TemplateValues ([ordered] @{
            DOMAINNAME = 'example.invalid'
            FIRST_SECRET = 'GENERATE'
            SECOND_SECRET = 'GENERATE'
            OPTIONAL_VALUE = ''
        }) `
        -GeneratedSecrets ([ordered] @{
            FIRST_SECRET = 16
            SECOND_SECRET = 36
        }) `
        -RequiredVariables @('DOMAINNAME', 'FIRST_SECRET', 'SECOND_SECRET')

    if ($env:SOPS_AGE_KEY -ne 'prior-inline-key' -or
        $env:SOPS_AGE_KEY_CMD -ne 'prior-key-command' -or
        $env:SOPS_AGE_KEY_FILE -ne 'prior-key-file') {
        throw 'Prior SOPS environment variables were not restored'
    }

    $ciphertextHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    $overwriteRejected = $false
    try {
        New-SopsEncryptedEnvFile `
            -TargetPath $target `
            -AgeKeyFile $keyFile `
            -SopsPath $sopsPath `
            -SopsConfigPath $configFile `
            -FilenameOverride 'secret.sops.env' `
            -TemplateValues ([ordered] @{
                DOMAINNAME = 'replacement.invalid'
            })
    }
    catch {
        if ($_.Exception.Message -notmatch '^Refusing to overwrite existing file:') {
            throw
        }
        $overwriteRejected = $true
    }
    if (-not $overwriteRejected) {
        throw 'An existing target was not rejected'
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $ciphertextHash) {
        throw 'The existing target changed during the overwrite check'
    }

    $env:SOPS_AGE_KEY_FILE = $keyFile
    $env:SOPS_AGE_KEY = $null
    $env:SOPS_AGE_KEY_CMD = $null
    $decrypted = & $sopsPath decrypt --input-type dotenv --output-type dotenv $target
    if ($LASTEXITCODE -ne 0) {
        throw 'Disposable encrypted file could not be decrypted'
    }

    $values = @{}
    foreach ($line in $decrypted) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }

    if ($values.DOMAINNAME -ne 'example.invalid') {
        throw 'DOMAINNAME was not preserved'
    }
    if ($values.FIRST_SECRET -notmatch '^[0-9a-f]{32}$') {
        throw 'FIRST_SECRET does not contain 16 random bytes as hexadecimal'
    }
    if ($values.SECOND_SECRET -notmatch '^[0-9a-f]{72}$') {
        throw 'SECOND_SECRET does not contain 36 random bytes as hexadecimal'
    }
    if ($values.OPTIONAL_VALUE -ne '') {
        throw 'Empty optional value was not preserved'
    }
    if ($decrypted -match 'GENERATE|CHANGE_ME') {
        throw 'An unresolved sentinel remains'
    }

    [IO.File]::WriteAllLines(
        $mockSopsPath,
        @(
            'Set-StrictMode -Version Latest'
            '$outputIndex = [Array]::IndexOf([object[]] $args, ''--output'')'
            'if ($outputIndex -lt 0 -or $outputIndex + 1 -ge $args.Count) { exit 2 }'
            '[IO.File]::WriteAllText($args[$outputIndex + 1], ''partial plaintext'')'
            '[IO.File]::WriteAllText($env:SOPS_TEST_TEMPLATE_PATH_LOG, $args[-1])'
            'exit 1'
        ),
        [Text.UTF8Encoding]::new($false)
    )
    $env:SOPS_TEST_TEMPLATE_PATH_LOG = $templatePathLog
    $encryptionFailureObserved = $false
    try {
        New-SopsEncryptedEnvFile `
            -TargetPath $failedTarget `
            -AgeKeyFile $keyFile `
            -SopsPath $mockSopsPath `
            -FilenameOverride 'secret.sops.env' `
            -TemplateValues ([ordered] @{
                DOMAINNAME = 'example.invalid'
            })
    }
    catch {
        if ($_.Exception.Message -ne 'SOPS encryption failed') {
            throw
        }
        $encryptionFailureObserved = $true
    }
    if (-not $encryptionFailureObserved) {
        throw 'A failing SOPS encryption command was not rejected'
    }
    if (Test-Path -LiteralPath $failedTarget) {
        throw 'A partial target remained after SOPS encryption failed'
    }
    $templatePath = [IO.File]::ReadAllText($templatePathLog)
    if (Test-Path -LiteralPath $templatePath) {
        throw 'The plaintext template remained after SOPS encryption failed'
    }
    if ($null -ne $env:SOPS_AGE_KEY -or
        $null -ne $env:SOPS_AGE_KEY_CMD -or
        $env:SOPS_AGE_KEY_FILE -ne $keyFile) {
        throw 'Prior SOPS environment variables were not restored after encryption failed'
    }

    Write-Output 'PowerShell SOPS bootstrap integration test passed.'
}
finally {
    $env:SOPS_AGE_KEY = $oldAgeKey
    $env:SOPS_AGE_KEY_CMD = $oldAgeKeyCommand
    $env:SOPS_AGE_KEY_FILE = $oldAgeKeyFile
    $env:SOPS_TEST_TEMPLATE_PATH_LOG = $oldTemplatePathLog
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
