$l=Get-Content "C:\Parkshare_new\lib\shared\models\booking.dart"
for ($i=525; $i -le 540; $i++) { Write-Host "$i`: $($l[$i])" }
