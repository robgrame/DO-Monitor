using namespace System.Net

param($Request, $TriggerMetadata)

# Validate request body
$Body = $Request.Body

if (-not $Body -or -not $Body.DeviceName) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = @{ error = "Invalid payload. DeviceName is required." } | ConvertTo-Json
        Headers    = @{ "Content-Type" = "application/json" }
    })
    return
}

# Enrich with ingestion timestamp
$Body | Add-Member -NotePropertyName "IngestedAt" -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force

# Forward to Service Bus
$Message = $Body | ConvertTo-Json -Depth 10 -Compress
Push-OutputBinding -Name ServiceBusMessage -Value $Message

# Return success
Write-Host "Received DO data from $($Body.DeviceName) with $($Body.JobCount) jobs"

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::Accepted
    Body       = @{ status = "accepted"; device = $Body.DeviceName; jobs = $Body.JobCount } | ConvertTo-Json
    Headers    = @{ "Content-Type" = "application/json" }
})
