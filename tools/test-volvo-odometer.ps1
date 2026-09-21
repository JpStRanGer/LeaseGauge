# Read-only local check against Volvo's Connected Vehicle API.
# Secrets are prompted locally, never passed as command arguments or saved.
param([switch]$RealCar)
$ErrorActionPreference = 'Stop'

function Read-SecretText([string]$Prompt) {
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $secure.Dispose()
    }
}

$apiKey = $null
$accessToken = $null
try {
    if ($RealCar) {
        Write-Host 'Volvo real-car odometer check (read only). Nothing is saved.'
    }
    else {
        Write-Host 'Volvo demo odometer check (read only). Nothing is saved.'
    }
    $apiKey = Read-SecretText 'LeaseGauge VCC API key (Primary)'
    $accessToken = Read-SecretText $(if ($RealCar) { 'My Volvo car access token' } else { 'Demo car access token' })
    if ([string]::IsNullOrWhiteSpace($apiKey) -or [string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'Both the API key and access token are required.'
    }

    $headers = @{
        Accept = 'application/json'
        Authorization = "Bearer $accessToken"
        'vcc-api-key' = $apiKey
    }
    $vehicles = Invoke-RestMethod -Method Get -Uri 'https://api.volvocars.com/connected-vehicle/v2/vehicles' -Headers $headers -TimeoutSec 20
    $vehicleList = @($vehicles.data)
    if ($vehicleList.Count -eq 0) {
        throw 'No vehicle was returned for this token.'
    }
    if ($RealCar -and $vehicleList.Count -ne 1) {
        Write-Host "The Volvo ID has $($vehicleList.Count) vehicles. No car was selected; the check stops safely."
        return
    }
    $vin = [string]$vehicleList[0].vin
    if ([string]::IsNullOrWhiteSpace($vin)) {
        throw 'The vehicle list did not contain a VIN.'
    }
    Write-Host "Vehicle found. Checking odometer for the first of $($vehicleList.Count) vehicle(s)."

    $safeVin = [Uri]::EscapeDataString($vin)
    $odometer = Invoke-RestMethod -Method Get -Uri "https://api.volvocars.com/connected-vehicle/v2/vehicles/$safeVin/odometer" -Headers $headers -TimeoutSec 20
    $reading = $odometer.data.odometer
    if ($null -eq $reading -or $null -eq $reading.value) {
        throw 'The odometer endpoint returned no reading.'
    }
    Write-Host "Odometer: $($reading.value) $($reading.unit)"
    Write-Host "Last vehicle update: $($reading.timestamp)"
    if ($RealCar) {
        Write-Host 'Real-car odometer check succeeded. Verify the reading against the car dashboard.'
    }
    else {
        Write-Host 'Demo test succeeded. This does not prove EX30 compatibility yet.'
    }
}
catch {
    $status = $_.Exception.Response.StatusCode
    if ($null -ne $status) {
        Write-Host "Volvo API returned HTTP $([int]$status). No secrets or VIN were printed."
        if ([int]$status -eq 401) {
            try {
                $errorText = [string]$_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($errorText) -and $_.Exception.Response -is [System.Net.WebResponse]) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errorText = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                $errorText = $errorText.ToLowerInvariant()
                if ($errorText -match 'invalid vcc-api-key|invalid api key|api key is invalid|subscription key|missing header vcc-api-key') {
                    Write-Host 'Volvo reports an API key problem. Copy the LeaseGauge Primary key again.'
                }
                elseif ($errorText -match 'token|bearer|expired|scope') {
                    Write-Host 'Volvo reports a token or permission problem. Generate a fresh demo token.'
                }
                else {
                    Write-Host 'Volvo did not identify which credential failed. Check both values and token expiry.'
                }
            }
            catch {
                Write-Host 'Check the API key, token, and token expiry.'
            }
        }
    }
    else {
        Write-Host 'The check did not complete. No secrets or VIN were printed.'
    }
    exit 1
}
finally {
    $apiKey = $null
    $accessToken = $null
    $headers = $null
}
