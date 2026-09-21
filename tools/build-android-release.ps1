[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KeyStorePath,

    [Parameter(Mandatory = $true)]
    [string]$KeyAlias,

    [string]$FlutterPath = 'C:\dev\flutter\bin\flutter.bat',

    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber,

    [switch]$EnableVolvoTesting
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw 'Flutter was not found. Supply -FlutterPath pointing to flutter.bat.'
}
if (-not (Test-Path -LiteralPath $KeyStorePath -PathType Leaf)) {
    throw 'Keystore file was not found. Supply the existing upload keystore path.'
}
if ([string]::IsNullOrWhiteSpace($KeyAlias)) {
    throw 'Supply the alias stored in the upload keystore.'
}
$resolvedKeyStore = (Resolve-Path -LiteralPath $KeyStorePath).Path

function ConvertFrom-PrivateInput([Security.SecureString]$Value) {
    $buffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($buffer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($buffer)
    }
}

$signingVariables = @(
    'LEASEGAUGE_KEYSTORE_PATH',
    'LEASEGAUGE_KEY_ALIAS',
    'LEASEGAUGE_STORE_PASSWORD',
    'LEASEGAUGE_KEY_PASSWORD'
)
$previousEnvironment = @{}
foreach ($variableName in $signingVariables) {
    $previousEnvironment[$variableName] = [Environment]::GetEnvironmentVariable($variableName, 'Process')
}
$storePasswordInput = $null
$keyPasswordInput = $null
$storePasswordText = $null
$keyPasswordText = $null

Push-Location -LiteralPath $projectDirectory
try {
    & $FlutterPath analyze
    if ($LASTEXITCODE -ne 0) { throw 'Analysis failed; no release was built.' }
    & $FlutterPath test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed; no release was built.' }

    Write-Host 'Building LeaseGauge with the selected upload key. The keystore is not changed.'
    Write-Host 'Passwords are entered locally, not saved in the repository or passed as command arguments.'
    $storePasswordInput = Read-Host 'Keystore password (from your password manager)' -AsSecureString
    if ($storePasswordInput.Length -eq 0) { throw 'A keystore password is required.' }
    $keyPasswordInput = Read-Host 'Key password (press Enter if it is the same)' -AsSecureString
    $storePasswordText = ConvertFrom-PrivateInput $storePasswordInput
    $keyPasswordText = if ($keyPasswordInput.Length -eq 0) {
        $storePasswordText
    } else {
        ConvertFrom-PrivateInput $keyPasswordInput
    }

    [Environment]::SetEnvironmentVariable('LEASEGAUGE_KEYSTORE_PATH', $resolvedKeyStore, 'Process')
    [Environment]::SetEnvironmentVariable('LEASEGAUGE_KEY_ALIAS', $KeyAlias, 'Process')
    [Environment]::SetEnvironmentVariable('LEASEGAUGE_STORE_PASSWORD', $storePasswordText, 'Process')
    [Environment]::SetEnvironmentVariable('LEASEGAUGE_KEY_PASSWORD', $keyPasswordText, 'Process')

    $buildArguments = @('build', 'appbundle', '--release')
    if ($PSBoundParameters.ContainsKey('BuildNumber')) {
        $buildArguments += "--build-number=$BuildNumber"
    }
    if ($EnableVolvoTesting) {
        Write-Host 'Including Volvo connection for the internal Play test build.'
        $buildArguments += '--dart-define=LEASEGAUGE_VOLVO_ENABLED=true'
    }
    & $FlutterPath @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed. Do not upload any older bundle.' }

    $bundleDirectory = Join-Path $projectDirectory 'build\app\outputs\bundle\release'
    Write-Host "Release build succeeded. Find the .aab in: $bundleDirectory"
    Write-Host 'Nothing has been uploaded or published. This is not confirmation of AAOS Play eligibility.'
}
finally {
    foreach ($variableName in $signingVariables) {
        [Environment]::SetEnvironmentVariable($variableName, $previousEnvironment[$variableName], 'Process')
    }
    $storePasswordText = $null
    $keyPasswordText = $null
    if ($null -ne $storePasswordInput) { $storePasswordInput.Dispose() }
    if ($null -ne $keyPasswordInput) { $keyPasswordInput.Dispose() }
    Pop-Location
}
