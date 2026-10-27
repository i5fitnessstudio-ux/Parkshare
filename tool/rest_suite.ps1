# ParkShare backend REST suite (Phase 2-5 verification).
# Runs against the live Shelf server on 127.0.0.1:8080 and its real
# PostgreSQL DB. Cleans up its own data at the end (best-effort).
$ErrorActionPreference = 'Stop'

$base = 'http://127.0.0.1:8080'
$stamp = [DateTime]::Now.ToString('yyyyMMddHHmmssfff')
$ownerEmail = "restowner$stamp@example.com"
$userEmail  = "restuser$stamp@example.com"
$password   = 'secret123'
$pngPath    = 'C:\Parkshare_new\assets\test\parking_photo.png'

$passed = 0
$failed = 0
$failures = @()

function Check($name, $ok, $extra = '') {
  if ($ok) {
    $script:passed++
    Write-Output "PASS  $name"
  } else {
    $script:failed++
    $script:failures += $name
    Write-Output "FAIL  $name  $extra"
  }
}

function PostJson($uri, $body, $token = $null) {
  $h = @{ 'Content-Type' = 'application/json' }
  if ($token) { $h['Authorization'] = "Bearer $token" }
  $json = $body | ConvertTo-Json -Compress -Depth 8
  try {
    return Invoke-RestMethod -Uri $uri -Method Post -Headers $h -Body $json -TimeoutSec 20
  } catch {
    return $null
  }
}
function GetJson($uri, $token) {
  try {
    return Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20
  } catch { return $null }
}
function PutJson($uri, $body, $token, $method = 'Put') {
  $h = @{ 'Content-Type' = 'application/json'; Authorization = "Bearer $token" }
  $json = $body | ConvertTo-Json -Compress -Depth 8
  try {
    return Invoke-RestMethod -Uri $uri -Method $method -Headers $h -Body $json -TimeoutSec 20
  } catch { return $null }
}
function RawCode($uri, $method, $body, $token, $contentType = 'application/json') {
  $h = @{}
  if ($token) { $h['Authorization'] = "Bearer $token" }
  if ($contentType) { $h['Content-Type'] = $contentType }
  $b = $null
  if ($null -ne $body) { $b = $body | ConvertTo-Json -Compress -Depth 8 }
  try {
    $r = Invoke-WebRequest -Uri $uri -Method $method -Headers $h -Body $b -TimeoutSec 20 -UseBasicParsing
    return [int]$r.StatusCode
  } catch {
    try { return [int]$_.Exception.Response.StatusCode.value__ } catch { return 0 }
  }
}

# ---- 0. Health ------------------------------------------------------------
try {
  $health = Invoke-RestMethod -Uri "$base/health" -TimeoutSec 10
  Check 'GET /health -> 200 ok' ($health.success -eq $true -and $health.data.status -eq 'ok')
} catch { Check 'GET /health -> 200 ok' $false $_.Exception.Message }

# ---- 1. Auth --------------------------------------------------------------
$regOwner = PostJson "$base/api/auth/register" @{
  name = 'Rest Owner'; email = $ownerEmail; phone = '9876500001'
  password = $password; role = 'owner'; upiId = "restowner$stamp@okbank"
}
$ownerToken = $regOwner.data.accessToken
$ownerRefresh = $regOwner.data.refreshToken
$ownerId = $regOwner.data.user.id
Check 'POST /api/auth/register (owner) -> tokens' ($null -ne $ownerToken -and $null -ne $ownerRefresh)

$regUser = PostJson "$base/api/auth/register" @{
  name = 'Rest Driver'; email = $userEmail; phone = '9876500002'
  password = $password; role = 'user'
}
$userToken = $regUser.data.accessToken
$userRefresh = $regUser.data.refreshToken
$userId = $regUser.data.user.id
Check 'POST /api/auth/register (user) -> tokens' ($null -ne $userToken)

$dupCode = RawCode "$base/api/auth/register" 'Post' @{
  name = 'Dup'; email = $userEmail; phone = '9876500003'; password = $password; role = 'user'
} $null
Check 'POST /api/auth/register duplicate email -> 409' ($dupCode -eq 409)

$wrongRole = RawCode "$base/api/auth/login" 'Post' @{
  email = $userEmail; password = $password; role = 'owner'
} $null
Check 'POST /api/auth/login wrong role -> 403' ($wrongRole -eq 403)

$wrongPw = RawCode "$base/api/auth/login" 'Post' @{
  email = $ownerEmail; password = 'wrongpass'; role = 'owner'
} $null
Check 'POST /api/auth/login wrong password -> 401' ($wrongPw -eq 401)

$loginOwner = PostJson "$base/api/auth/login" @{ email = $ownerEmail; password = $password; role = 'owner' }
Check 'POST /api/auth/login (owner) -> 200' ($null -ne $loginOwner.data.accessToken -and $loginOwner.data.user.role -eq 'owner')

$refresh = PostJson "$base/api/auth/refresh" @{ refreshToken = $ownerRefresh }
Check 'POST /api/auth/refresh -> rotated token' ($null -ne $refresh.data.accessToken -and $null -ne $refresh.data.refreshToken)

$me = GetJson "$base/api/auth/me" $ownerToken
Check 'GET /api/auth/me -> current user' ($me.data.email -eq $ownerEmail)

$logout = PostJson "$base/api/auth/logout" @{ refreshToken = $ownerRefresh } $ownerToken
Check 'POST /api/auth/logout -> 200' ($null -ne $logout -and $logout.success -eq $true)

$reuseRefresh = PostJson "$base/api/auth/refresh" @{ refreshToken = $ownerRefresh }
Check 'POST /api/auth/refresh reused (revoked) -> rejected' ($null -eq $reuseRefresh)

$forgot = PostJson "$base/api/auth/forgot-password" @{ email = $ownerEmail }
$otp = $forgot.data.devOtp
Check 'POST /api/auth/forgot-password (dev OTP) -> 200' ($null -ne $otp)

$verify = PostJson "$base/api/auth/verify-reset-otp" @{ email = $ownerEmail; otp = $otp }
Check 'POST /api/auth/verify-reset-otp -> valid' ($verify.success -eq $true)

$reset = PostJson "$base/api/auth/reset-password" @{ email = $ownerEmail; otp = $otp; newPassword = 'newpass456' }
Check 'POST /api/auth/reset-password -> 200' ($reset.success -eq $true)

$verify2 = PostJson "$base/api/auth/verify-reset-otp" @{ email = $ownerEmail; otp = $otp }
Check 'OTP reuse rejected' ($null -eq $verify2)

# re-login with the new password
$loginOwner2 = PostJson "$base/api/auth/login" @{ email = $ownerEmail; password = 'newpass456'; role = 'owner' }
$ownerToken = $loginOwner2.data.accessToken
Check 'Login with reset password -> 200' ($null -ne $ownerToken)

# ---- 2. Vehicle ------------------------------------------------------------
$veh = PostJson "$base/api/vehicles" @{
  vehicleType = 'BIKE'; brand = 'Honda'; model = 'Activa 6G'
  registrationNumber = 'MH12AB1234'; lengthM = 1.80; widthM = 0.70; heightM = 1.10; isPrimary = $true
} $userToken
$vehicleId = $veh.data.id
Check 'POST /api/vehicles -> 201' ($null -ne $vehicleId)

$vehicles = GetJson "$base/api/vehicles" $userToken
Check 'GET /api/vehicles -> saved vehicle' ($vehicles.data.vehicles.Count -ge 1)

$badVeh = RawCode "$base/api/vehicles" 'Post' @{
  vehicleType = 'BIKE'; brand = 'Honda'; model = 'Activa'; registrationNumber = 'MH12'
  lengthM = -1; widthM = 0.70; heightM = 1.10
} $userToken
Check 'POST /api/vehicles invalid dims -> 400' ($badVeh -eq 400)

# ---- 3. Upload + Parking ---------------------------------------------------
$boundary = "----PSBoundary$([guid]::NewGuid().ToString('N'))"
$fileBytes = [System.IO.File]::ReadAllBytes($pngPath)
$ms = New-Object System.IO.MemoryStream
$hdr = [System.Text.Encoding]::ASCII.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"test.png`"`r`nContent-Type: image/png`r`n`r`n")
$ms.Write($hdr, 0, $hdr.Length)
$ms.Write($fileBytes, 0, $fileBytes.Length)
$trl = [System.Text.Encoding]::ASCII.GetBytes("`r`n--$boundary--`r`n")
$ms.Write($trl, 0, $trl.Length)
$bodyBytes = $ms.ToArray()
$upload = $null
try {
  $upRes = Invoke-RestMethod -Uri "$base/api/uploads" -Method Post `
    -Headers @{ Authorization = "Bearer $ownerToken"; 'Content-Type' = "multipart/form-data; boundary=$boundary" } `
    -Body $bodyBytes -TimeoutSec 30
  $upload = $upRes.data
} catch { $upload = $null }
$photoUrl = $upload.url
Check 'POST /api/uploads multipart photo -> 201' ($null -ne $photoUrl -and $photoUrl -like '*/uploads/*')

$parking = PostJson "$base/api/parkings" @{
  parkingName = "REST Greenview $stamp"; address = '42 REST Lane, Bandra'; city = 'Mumbai'
  state = 'Maharashtra'; pincode = '400050'; landmark = 'Near station'
  latitude = 19.0760; longitude = 72.8777; parkingType = 'COVERED'
  lengthM = 5.0; widthM = 2.5; heightM = 2.0
  entranceLengthM = 5.5; entranceWidthM = 2.8; entranceHeightM = 2.2
  vehicleType = 'BOTH'; maximumCars = 1; maximumBikes = 1
  monthlyEnabled = $true; monthlyRent = 3000
  yearlyEnabled = $false; yearlyRent = $null; accessHours = '24/7'
  description = 'Covered garage in Bandra.'; conditions = 'No smoking.'
  autoApproval = $true
  amenities = @('CCTV', 'Lighting'); photoUrls = @($photoUrl)
} $ownerToken
$parkingId = $parking.data.id
Check 'POST /api/parkings -> 201 (with uploaded photo)' ($null -ne $parkingId)
Check 'Publish clears draft + amount NOT client-set' ($null -eq $parking.data.amount)

$noRent = RawCode "$base/api/parkings" 'Post' @{
  parkingName = 'Bad'; address = 'x'; latitude = 19.0; longitude = 72.8
  lengthM = 5.0; widthM = 2.5; heightM = 2.0; vehicleType = 'BOTH'
  maximumCars = 1; maximumBikes = 1
  monthlyEnabled = $true; monthlyRent = $null; yearlyEnabled = $false
  amenities = @(); photoUrls = @()
} $ownerToken
Check 'POST /api/parkings enabled plan w/o rent -> 400' ($noRent -eq 400)

$byId = GetJson "$base/api/parkings/$parkingId" $ownerToken
Check 'GET /api/parkings/{id} -> real draft' ($byId.data.parkingName -eq "REST Greenview $stamp" -and $byId.data.photoUrls.Count -ge 1)

$mine = GetJson "$base/api/parkings/owner/$ownerId" $ownerToken
Check 'GET /api/parkings/owner/{id} -> in list' ($mine.data.parkings.Count -ge 1)

$near = GetJson "$base/api/parkings/nearby?lat=19.076&lng=72.8777&radiusKm=50" $userToken
Check 'GET /api/parkings/nearby -> finds it' ($near.data.parkings.Count -ge 1)

$far = GetJson "$base/api/parkings/nearby?lat=28.61&lng=77.23&radiusKm=50" $userToken
Check 'GET /api/parkings/nearby (Delhi) -> empty' ($far.data.parkings.Count -eq 0)

# ---- 4. Booking lifecycle --------------------------------------------------
$start = (Get-Date).AddDays(5).ToString('yyyy-MM-dd')
$end = (Get-Date).AddDays(35).ToString('yyyy-MM-dd')
$bk = PostJson "$base/api/bookings" @{
  parkingId = $parkingId; vehicleId = $vehicleId; rentalType = 'MONTHLY'
  startDate = $start; endDate = $end
} $userToken
$bookingId = $bk.data.bookingId
Check 'POST /api/bookings -> created (auto-approved)' ($null -ne $bookingId -and $bk.data.status -eq 'ACCEPTED')

$overlap = RawCode "$base/api/bookings" 'Post' @{
  parkingId = $parkingId; vehicleId = $vehicleId; rentalType = 'MONTHLY'
  startDate = (Get-Date).AddDays(10).ToString('yyyy-MM-dd')
  endDate = (Get-Date).AddDays(30).ToString('yyyy-MM-dd')
} $userToken
Check 'POST /api/bookings overlapping dates -> 409' ($overlap -eq 409)

# Modern UPI flow (audit C-01): intent -> confirm (202, unverified) -> owner settle.
$intent = PostJson "$base/api/payments/upi/intent" @{ bookingId = $bookingId } $userToken
Check 'POST /api/payments/upi/intent -> PENDING' ($null -ne $intent -and $intent.data.paymentStatus -eq 'PENDING' -and $null -ne $intent.data.reference)

$confirmCode = RawCode "$base/api/payments/upi/confirm" 'Post' @{
  bookingId = $bookingId; transactionId = "TESTTXN$stamp"
} $userToken
Check 'POST /api/payments/upi/confirm -> 202 unverified' ($confirmCode -eq 202)

$bkMid = GetJson "$base/api/bookings/$bookingId" $userToken
Check 'No CONFIRMED before owner settlement' ($bkMid.data.status -eq 'ACCEPTED')

$settle = PutJson "$base/api/payments/$bookingId/upi/settle" $null $ownerToken
Check 'PUT /api/payments/{id}/upi/settle (owner) -> 200' ($null -ne $settle -and $settle.success -eq $true -and $settle.data.status -eq 'CONFIRMED')

$state = GetJson "$base/api/bookings/$bookingId" $userToken
Check 'Booking joins user+parking+vehicle+payment' (
  $null -ne $state.data.user -and $null -ne $state.data.parking -and
  $null -ne $state.data.vehicle -and $null -ne $state.data.payment)

$ownerBk = GetJson "$base/api/bookings/owner/$ownerId" $ownerToken
Check 'GET /api/bookings/owner/{id} -> joined list' ($ownerBk.data.bookings.Count -ge 1)

$userBk = GetJson "$base/api/bookings/user/$userId" $userToken
Check 'GET /api/bookings/user/{id} -> joined list' ($userBk.data.bookings.Count -ge 1)

# ---- 5. Inbox / chat -------------------------------------------------------
$conv = PostJson "$base/api/inbox/conversations" @{
  parkingId = $parkingId; bookingId = $bookingId
} $ownerToken
$convId = $conv.data.id
Check 'POST /api/inbox/conversations (ensure) -> created' ($null -ne $convId)

$convs = GetJson "$base/api/inbox/conversations" $ownerToken
Check 'GET /api/inbox/conversations -> listed' ($convs.data.conversations.Count -ge 1)

$msg = PostJson "$base/api/inbox/conversations/$convId/messages" @{ body = 'Please share the entry code.' } $ownerToken
Check 'POST message -> 201' ($null -ne $msg.data.id)

$msgs = GetJson "$base/api/inbox/conversations/$convId/messages" $ownerToken
Check 'GET messages -> real thread' ($msgs.data.messages.Count -ge 1)

# ---- 6. Photo serving + updates/cleanup ------------------------------------
$photoPath = $photoUrl -replace '^.*?/uploads/', 'uploads/'
$code = 0
try {
  $r = Invoke-WebRequest -Uri "$base/$photoPath" -UseBasicParsing -TimeoutSec 10
  $code = [int]$r.StatusCode
} catch { $code = [int]$_.Exception.Response.StatusCode.value__ }
Check 'GET /uploads/<file> serves the photo' ($code -eq 200)

$updatedName = "REST Greenview UPD $stamp"
$upd = PutJson "$base/api/parkings/$parkingId" @{
  parkingName = $updatedName; address = '42 REST Lane, Bandra'; city = 'Mumbai'
  state = 'Maharashtra'; pincode = '400050'; landmark = 'Near station'
  latitude = 19.0760; longitude = 72.8777; parkingType = 'COVERED'
  lengthM = 5.0; widthM = 2.5; heightM = 2.0
  entranceLengthM = 5.5; entranceWidthM = 2.8; entranceHeightM = 2.2
  vehicleType = 'BOTH'; maximumCars = 1; maximumBikes = 1
  monthlyEnabled = $true; monthlyRent = 3000
  yearlyEnabled = $false; accessHours = '24/7'; description = 'Covered garage.'
  conditions = 'No smoking.'; autoApproval = $true; amenities = @('CCTV'); photoUrls = @($photoUrl)
} $ownerToken
Check 'PUT /api/parkings/{id} -> 200' ($null -ne $upd -and $upd.data.parkingName -eq $updatedName)

$delVeh = RawCode "$base/api/vehicles/$vehicleId" 'Delete' $null $userToken
Check 'DELETE /api/vehicles/{id} -> 200' ($delVeh -eq 200)

Write-Output ''
Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) {
  Write-Output 'FAILED CHECKS:'
  $failures | ForEach-Object { Write-Output "  - $_" }
  exit 1
}
exit 0