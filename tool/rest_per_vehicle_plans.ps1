# Focused live E2E for the per-vehicle rental plans refactor (migration 006).
# Requires the backend running on 127.0.0.1:8080 with the real PostgreSQL DB.
# Creates its own rows and deletes the parkings it creates (best-effort).
$ErrorActionPreference = 'Stop'
$base    = 'http://127.0.0.1:8080'
$stamp   = [DateTime]::Now.ToString('yyyyMMddHHmmssfff')
$email   = "planowner$stamp@example.com"
$password = 'secret123'
$pngPath = 'C:\Parkshare_new\assets\test\parking_photo.png'
$passed = 0; $failed = 0; $failures = @()
function Check($name, $ok, $extra = '') {
  if ($ok) { $script:passed++; Write-Output "PASS  $name" }
  else { $script:failed++; $script:failures += $name; Write-Output "FAIL  $name  $extra" }
}
function PostJson($uri, $body, $token) {
  $h = @{ 'Content-Type' = 'application/json' }
  if ($token) { $h['Authorization'] = "Bearer $token" }
  try { return Invoke-RestMethod -Uri $uri -Method Post -Headers $h -Body ($body | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec 20 } catch { return $null }
}
function GetJson($uri, $token) {
  try { return Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20 } catch { return $null }
}
function RawCode($uri, $method, $body, $token) {
  $h = @{}; if ($token) { $h['Authorization'] = "Bearer $token" }; $h['Content-Type'] = 'application/json'
  $b = if ($null -ne $body) { $body | ConvertTo-Json -Depth 8 -Compress } else { $null }
  try { return [int](Invoke-WebRequest -Uri $uri -Method $method -Headers $h -Body $b -TimeoutSec 20 -UseBasicParsing).StatusCode }
  catch { try { return [int]$_.Exception.Response.StatusCode.value__ } catch { return 0 } }
}
function DelCode($uri, $token) {
  try { return [int](Invoke-WebRequest -Uri $uri -Method Delete -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20 -UseBasicParsing).StatusCode }
  catch { try { return [int]$_.Exception.Response.StatusCode.value__ } catch { return 0 } }
}

# health + owner
$health = Invoke-RestMethod -Uri "$base/health" -TimeoutSec 10
Check 'GET /health -> ok' ($health.data.status -eq 'ok')
$reg = PostJson "$base/api/auth/register" @{ name = 'Plan Owner'; email = $email; phone = '9876500101'; password = $password; role = 'owner'; upiId = "planowner$stamp@okbank" } $null
$ownerToken = $reg.data.accessToken; $ownerId = $reg.data.user.id
Check 'register owner -> token' ($null -ne $ownerToken)

# upload a photo
$boundary = "----PSBoundary$([guid]::NewGuid().ToString('N'))"
$ms = New-Object System.IO.MemoryStream
$hdr = [System.Text.Encoding]::ASCII.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"test.png`"`r`nContent-Type: image/png`r`n`r`n")
$f = [System.IO.File]::ReadAllBytes($pngPath)
$ms.Write($hdr, 0, $hdr.Length); $ms.Write($f, 0, $f.Length)
$trl = [System.Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n"); $ms.Write($trl, 0, $trl.Length)
$upRes = Invoke-RestMethod -Uri "$base/api/uploads" -Method Post -Headers @{ Authorization = "Bearer $ownerToken"; 'Content-Type' = "multipart/form-data; boundary=$boundary" } -Body $ms.ToArray() -TimeoutSec 30
$photoUrl = $upRes.data.url
Check 'upload photo -> 201' ($photoUrl -like '*/uploads/*')

$parkingA = $null; $parkingB = $null
try {
  # ---- A: fully independent per-vehicle plans (cars monthly only, bikes yearly only)
  $a = PostJson "$base/api/parkings" @{
    parkingName = "PlanGreen $stamp"; address = '1 Plan Lane'; city = 'Chennai'; state = 'Tamil Nadu'
    latitude = 13.0827; longitude = 80.2707; parkingType = 'COVERED'
    lengthM = 5.0; widthM = 2.5; heightM = 2.0; entranceWidthM = 2.8; entranceHeightM = 2.2
    vehicleType = 'BOTH'; maximumCars = 1; maximumBikes = 1
    carMonthlyEnabled = $true; carMonthlyRent = 3500
    carYearlyEnabled = $false
    bikeMonthlyEnabled = $false
    bikeYearlyEnabled = $true; bikeYearlyRent = 25000
    accessHours = '24/7'; description = 'per-vehicle plans'; conditions = ''
    autoApproval = $true; amenities = @('CCTV'); photoUrls = @($photoUrl)
    spaces = @(
      @{ spaceCode = 'C1'; spaceName = ''; vehicleType = 'CAR'; lengthM = 5.0; widthM = 2.5; heightM = 2.0; isActive = $true },
      @{ spaceCode = 'B1'; spaceName = ''; vehicleType = 'BIKE'; lengthM = 2.5; widthM = 1.0; heightM = 2.0; isActive = $true }
    )
  } $ownerToken
  $parkingA = $a
  $aId = $a.data.id
  Check 'POST /api/parkings with per-vehicle plans -> 201' ($null -ne $aId)

  $aBack = GetJson "$base/api/parkings/$aId" $ownerToken; $d = $aBack.data
  Check 'car monthly survives round trip' ($d.carMonthlyEnabled -eq $true -and $d.carMonthlyRent -eq 3500)
  Check 'car yearly stays disabled' ($d.carYearlyEnabled -eq $false -and $d.carYearlyRent -eq $null)
  Check 'bike monthly stays disabled' ($d.bikeMonthlyEnabled -eq $false)
  Check 'bike yearly survives round trip' ($d.bikeYearlyEnabled -eq $true -and $d.bikeYearlyRent -eq 25000)
  Check 'derived legacy pair = car-first union' ($d.monthlyEnabled -eq $true -and $d.monthlyRent -eq 3500 -and $d.yearlyEnabled -eq $true -and $d.yearlyRent -eq 25000)

  # ---- B: legacy-only payload -> per-vehicle fields fall back to the shared pair
  $b = PostJson "$base/api/parkings" @{
    parkingName = "PlanLegacy $stamp"; address = '2 Plan Lane'; city = 'Chennai'; state = 'Tamil Nadu'
    latitude = 13.0870; longitude = 80.2780; parkingType = 'NON_COVERED'
    lengthM = 5.0; widthM = 2.5; heightM = 2.0; entranceWidthM = 2.8; entranceHeightM = 2.2
    vehicleType = 'BOTH'; maximumCars = 1; maximumBikes = 1
    monthlyEnabled = $true; monthlyRent = 1500; yearlyEnabled = $false
    accessHours = '24/7'; description = 'legacy payload'; conditions = ''
    autoApproval = $true; amenities = @(); photoUrls = @($photoUrl)
    spaces = @(
      @{ spaceCode = 'C1'; spaceName = ''; vehicleType = 'CAR'; lengthM = 5.0; widthM = 2.5; heightM = 2.0; isActive = $true }
    )
  } $ownerToken
  $parkingB = $b
  $bId = $b.data.id
  Check 'POST /api/parkings legacy payload -> 201' ($null -ne $bId)

  $bBack = GetJson "$base/api/parkings/$bId" $ownerToken
  Check 'legacy row reports the plan for BOTH types' ($bBack.data.carMonthlyEnabled -eq $true -and $bBack.data.bikeMonthlyEnabled -eq $true -and $bBack.data.carMonthlyRent -eq 1500)

  # ---- C: an enabled per-vehicle plan without a rent is rejected server-side
  $cCode = RawCode "$base/api/parkings" 'Post' @{
    parkingName = "PlanBad $stamp"; address = '3 Plan Lane'; city = 'Chennai'; state = 'Tamil Nadu'
    latitude = 13.0900; longitude = 80.2850; parkingType = 'NON_COVERED'
    lengthM = 5.0; widthM = 2.5; heightM = 2.0; entranceWidthM = 2.8; entranceHeightM = 2.2
    vehicleType = 'BOTH'; carMonthlyEnabled = $true; carMonthlyRent = $null
    accessHours = '24/7'; amenities = @(); photoUrls = @($photoUrl)
  } $ownerToken
  Check 'enabled per-vehicle plan without rent -> 400' ($cCode -eq 400)
}
finally {
  if ($parkingA) { DelCode "$base/api/parkings/$($parkingA.data.id)" $ownerToken | Out-Null }
  if ($parkingB) { DelCode "$base/api/parkings/$($parkingB.data.id)" $ownerToken | Out-Null }
}

Write-Output ''
Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { $failures | ForEach-Object { Write-Output "  - $_" }; exit 1 }
exit 0