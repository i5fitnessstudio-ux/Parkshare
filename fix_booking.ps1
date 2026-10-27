$f = "C:\Parkshare_new\lib\shared\models\booking.dart"
$c = Get-Content $f -Raw
$old = @'
      upiTransactionId:
          (json['upiTransactionId']?.toString() ?? '').trim().isEmpty
              ? null
              : json['upiTransactionId'].toString().trim(),
'@
$new = @'
      razorpayPaymentId: null,
      upiTransactionId:
          (json['upiTransactionId']?.toString() ?? '').trim().isEmpty
              ? null
              : json['upiTransactionId'].toString().trim(),
'@
if ($c.Contains($old)) {
  $c2 = $c.Replace($old, $new)
  Set-Content $f -Value $c2 -NoNewline
  Write-Host "ok"
} else {
  Write-Host "no"
}
