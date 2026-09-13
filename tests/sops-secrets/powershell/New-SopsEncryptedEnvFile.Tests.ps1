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
$changeMeTarget = Join-Path $testRoot 'change-me.sops.env'
$mutationFailureTarget = Join-Path $testRoot 'mutation-failure.sops.env'
$validationFailureTarget = Join-Path $testRoot 'validation-failure.sops.env'
$failedTarget = Join-Path $testRoot 'failed.sops.env'
$mockSopsPath = Join-Path $testRoot 'mock-sops.ps1'
$mutationMockSopsPath = Join-Path $testRoot $(if ($IsWindows) { 'mutation-mock-sops.cmd' } else { 'mutation-mock-sops.sh' })
$mockEditorPath = Join-Path $testRoot 'mock-editor.ps1'
$editorLog = Join-Path $testRoot 'editor.log'
$templatePathLog = Join-Path $testRoot 'template-path.log'
$oldAgeKey = $env:SOPS_AGE_KEY
$oldAgeKeyCommand = $env:SOPS_AGE_KEY_CMD
$oldAgeKeyFile = $env:SOPS_AGE_KEY_FILE
$oldSopsEditor = $env:SOPS_EDITOR
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

    $firstSecretBefore = $values.FIRST_SECRET
    $secondSecretBefore = $values.SECOND_SECRET
    Add-SopsGeneratedEnvSecret `
        -TargetPath $target `
        -AgeKeyFile $keyFile `
        -SopsPath $sopsPath `
        -GeneratedSecrets ([ordered] @{
            THIRD_SECRET = 24
        }) `
        -RequiredVariables @('DOMAINNAME', 'FIRST_SECRET', 'SECOND_SECRET', 'THIRD_SECRET')

    $decrypted = & $sopsPath decrypt --input-type dotenv --output-type dotenv $target
    if ($LASTEXITCODE -ne 0) {
        throw 'Updated disposable encrypted file could not be decrypted'
    }
    $values = @{}
    foreach ($line in $decrypted) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    if ($values.FIRST_SECRET -ne $firstSecretBefore -or
        $values.SECOND_SECRET -ne $secondSecretBefore) {
        throw 'Updating the encrypted file rotated an existing secret'
    }
    if ($values.THIRD_SECRET -notmatch '^[0-9a-f]{48}$') {
        throw 'THIRD_SECRET does not contain 24 random bytes as hexadecimal'
    }

    $updatedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    Add-SopsGeneratedEnvSecret `
        -TargetPath $target `
        -AgeKeyFile $keyFile `
        -SopsPath $sopsPath `
        -GeneratedSecrets ([ordered] @{
            THIRD_SECRET = 24
        }) `
        -RequiredVariables @('DOMAINNAME', 'FIRST_SECRET', 'SECOND_SECRET', 'THIRD_SECRET')
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $updatedHash) {
        throw 'Idempotent update rewrote the encrypted file'
    }

    Copy-Item -LiteralPath $target -Destination $changeMeTarget
    '"CHANGE_ME"' | & $sopsPath set `
        --input-type dotenv `
        --output-type dotenv `
        --value-stdin `
        $changeMeTarget `
        '["BAD_SECRET"]' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to prepare the CHANGE_ME test fixture'
    }
    $changeMeHash = (Get-FileHash -LiteralPath $changeMeTarget -Algorithm SHA256).Hash
    $changeMeRejected = $false
    try {
        Add-SopsGeneratedEnvSecret `
            -TargetPath $changeMeTarget `
            -AgeKeyFile $keyFile `
            -SopsPath $sopsPath `
            -GeneratedSecrets ([ordered] @{
                BAD_SECRET = 16
            }) `
            -RequiredVariables @('DOMAINNAME', 'BAD_SECRET')
    }
    catch {
        if ($_.Exception.Message -notmatch '^Requested generated secret contains the CHANGE_ME sentinel:') {
            throw
        }
        $changeMeRejected = $true
    }
    if (-not $changeMeRejected) {
        throw 'A requested CHANGE_ME sentinel was not rejected'
    }
    if ((Get-FileHash -LiteralPath $changeMeTarget -Algorithm SHA256).Hash -ne $changeMeHash) {
        throw 'The CHANGE_ME fixture changed during the rejected update'
    }

    Copy-Item -LiteralPath $target -Destination $mutationFailureTarget
    if ($IsWindows) {
        [IO.File]::WriteAllLines(
            $mutationMockSopsPath,
            @(
                '@echo off'
                'if "%~1"=="set" ('
                '    echo corrupted>"%~7"'
                '    exit /b 91'
                ')'
                '"%SOPS_TEST_REAL_SOPS%" %*'
                'exit /b %ERRORLEVEL%'
            ),
            [Text.ASCIIEncoding]::new()
        )
    }
    else {
        [IO.File]::WriteAllLines(
            $mutationMockSopsPath,
            @(
                '#!/bin/sh'
                'if [ "$1" = "set" ]; then'
                '    printf "%s\n" corrupted >"$7"'
                '    exit 91'
                'fi'
                'exec "$SOPS_TEST_REAL_SOPS" "$@"'
            ),
            [Text.UTF8Encoding]::new($false)
        )
        & chmod +x $mutationMockSopsPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to make the mutation SOPS mock executable'
        }
    }
    $env:SOPS_TEST_REAL_SOPS = $sopsPath
    $mutationFailureHash = (Get-FileHash -LiteralPath $mutationFailureTarget -Algorithm SHA256).Hash
    $mutationFailureObserved = $false
    try {
        Add-SopsGeneratedEnvSecret `
            -TargetPath $mutationFailureTarget `
            -AgeKeyFile $keyFile `
            -SopsPath $mutationMockSopsPath `
            -GeneratedSecrets ([ordered] @{
                FOURTH_SECRET = 16
            }) `
            -RequiredVariables @('DOMAINNAME', 'FOURTH_SECRET')
    }
    catch {
        if ($_.Exception.Message -notmatch '^SOPS failed to add the GENERATE sentinel for FOURTH_SECRET') {
            throw
        }
        $mutationFailureObserved = $true
    }
    if (-not $mutationFailureObserved) {
        throw 'A failed SOPS mutation was not rejected'
    }
    if ((Get-FileHash -LiteralPath $mutationFailureTarget -Algorithm SHA256).Hash -ne $mutationFailureHash) {
        throw 'A failed encrypted mutation changed the original ciphertext'
    }
    $temporaryMutationFiles = @(Get-ChildItem -LiteralPath $testRoot -Filter 'mutation-failure.sops.env.generated.*')
    if ($temporaryMutationFiles.Count -ne 0) {
        throw 'A failed encrypted mutation left temporary ciphertext behind'
    }
    if ($null -ne $env:SOPS_AGE_KEY -or
        $null -ne $env:SOPS_AGE_KEY_CMD -or
        $env:SOPS_AGE_KEY_FILE -ne $keyFile) {
        throw 'Prior SOPS environment variables were not restored after encrypted mutation failed'
    }

    Copy-Item -LiteralPath $target -Destination $validationFailureTarget
    $validationFailureHash = (Get-FileHash -LiteralPath $validationFailureTarget -Algorithm SHA256).Hash
    $validationFailureObserved = $false
    try {
        Add-SopsGeneratedEnvSecret `
            -TargetPath $validationFailureTarget `
            -AgeKeyFile $keyFile `
            -SopsPath $sopsPath `
            -GeneratedSecrets ([ordered] @{
                FIFTH_SECRET = 16
            }) `
            -RequiredVariables @('DOMAINNAME', 'MISSING_REQUIRED', 'FIFTH_SECRET')
    }
    catch {
        if ($_.Exception.Message -notmatch '^Required variables are missing:') {
            throw
        }
        $validationFailureObserved = $true
    }
    if (-not $validationFailureObserved) {
        throw 'A missing required variable in final validation was not rejected'
    }
    if ((Get-FileHash -LiteralPath $validationFailureTarget -Algorithm SHA256).Hash -ne $validationFailureHash) {
        throw 'A final validation failure changed the original ciphertext'
    }
    $temporaryValidationFiles = @(Get-ChildItem -LiteralPath $testRoot -Filter 'validation-failure.sops.env.generated.*')
    if ($temporaryValidationFiles.Count -ne 0) {
        throw 'A final validation failure left temporary ciphertext behind'
    }

    [IO.File]::WriteAllLines(
        $mockEditorPath,
        @(
            'param([Parameter(Mandatory)] [string] $Path)'
            '[IO.File]::WriteAllText($env:SOPS_TEST_EDITOR_LOG, $Path)'
            '$content = [IO.File]::ReadAllText($Path)'
            '[IO.File]::WriteAllText($Path, $content.Replace(''DOMAINNAME=example.invalid'', ''DOMAINNAME=edited.invalid''))'
        ),
        [Text.UTF8Encoding]::new($false)
    )
    $env:SOPS_TEST_EDITOR_LOG = $editorLog
    $env:SOPS_EDITOR = 'prior-editor-command'
    $mockEditorCommandPath = $mockEditorPath.Replace('\', '/')
    $editorExecutable = if ($IsWindows) { 'powershell.exe' } else { 'pwsh' }
    Open-SopsEncryptedFile `
        -TargetPath $target `
        -AgeKeyFile $keyFile `
        -SopsPath $sopsPath `
        -EditorCommand "$editorExecutable -NoProfile -File `"$mockEditorCommandPath`""
    if (-not (Test-Path -LiteralPath $editorLog)) {
        throw 'SOPS did not invoke the configured editor'
    }
    if ([string]::IsNullOrWhiteSpace([IO.File]::ReadAllText($editorLog))) {
        throw 'The configured editor did not receive a temporary plaintext path'
    }
    if ($env:SOPS_EDITOR -ne 'prior-editor-command') {
        throw 'Prior SOPS_EDITOR value was not restored'
    }

    [IO.File]::WriteAllLines(
        $mockEditorPath,
        @(
            'param([Parameter(Mandatory)] [string] $Path)'
            '[IO.File]::WriteAllText($env:SOPS_TEST_EDITOR_LOG, $Path)'
        ),
        [Text.UTF8Encoding]::new($false)
    )
    Open-SopsEncryptedFile `
        -TargetPath $target `
        -AgeKeyFile $keyFile `
        -SopsPath $sopsPath `
        -EditorCommand "$editorExecutable -NoProfile -File `"$mockEditorCommandPath`""

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
    $env:SOPS_EDITOR = $oldSopsEditor
    Remove-Item Env:SOPS_TEST_EDITOR_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:SOPS_TEST_REAL_SOPS -ErrorAction SilentlyContinue
    $env:SOPS_TEST_TEMPLATE_PATH_LOG = $oldTemplatePathLog
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
