# Checks only whether Volvo recognizes the LeaseGauge API key.
# A 401 with "missing Authorization" is the expected successful result.
$ErrorActionPreference = 'Stop'
$secure = Read-Host -Prompt 'LeaseGauge VCC API key (Primary)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $secure.Dispose()
}

try {
    Invoke-RestMethod -Method Get -Uri 'https://api.volvocars.com/connected-vehicle/v2/vehicles' -Headers @{
        Accept = 'application/json'
        'vcc-api-key' = $apiKey
    } -TimeoutSec 20 | Out-Null
    Write-Host 'Volvo recognized the API key.'
}
catch {
    $message = [string]$_.ErrorDetails.Message
    if ([string]::IsNullOrWhiteSpace($message) -and $_.Exception.Response -is [System.Net.WebResponse]) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        try { $message = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    }
    $message = $message.ToLowerInvariant()
    if ($message -match 'missing header authorization|missing authorization|missing bearer|authorization header') {
        Write-Host 'API key accepted. Volvo now asks for an access token (expected).'
    }
    elseif ($message -match 'invalid vcc-api-key|missing header vcc-api-key|invalid api key') {
        Write-Host 'API key rejected. Check that you copied LeaseGauge VCC API key - Primary.'
    }
    else {
        Write-Host "Key check inconclusive. HTTP status: $([int]$_.Exception.Response.StatusCode)."
    }
}
finally {
    $apiKey = $null
}
