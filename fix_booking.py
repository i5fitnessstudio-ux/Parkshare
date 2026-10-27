path = r'C:\Parkshare_new\lib\shared\models\booking.dart'
s = open(path, encoding='utf-8').read()
old = "      paymentReference:\n          (json['paymentReference']?.toString() ?? '').trim().isEmpty\n              ? null\n              : json['paymentReference'].toString().trim(),\n      upiTransactionId:"
new = "      paymentReference:\n          (json['paymentReference']?.toString() ?? '').trim().isEmpty\n              ? null\n              : json['paymentReference'].toString().trim(),\n      razorpayPaymentId: _cleanText(json['razorpayPaymentId']),\n      upiTransactionId:"
print(old in s)
if old in s:
    open(path, 'w', encoding='utf-8').write(s.replace(old, new))
    print('done')
else:
    print('nope')
