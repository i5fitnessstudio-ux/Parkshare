# OCR each emulator screenshot with the Windows 10+ OCR engine so we can
# caption them accurately (this model cannot view images directly).
param(
  [string]$Dir = "C:\Parkshare_new\docs\e2e_shots"
)

Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]

function Await($WinRtTask, $ResultType) {
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  $netTask = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) {
  Write-Output 'OCR engine unavailable'
  exit 1
}

Get-ChildItem -Path $Dir -Filter '*.png' | Sort-Object Name | ForEach-Object {
  $path = $_.FullName
  try {
    $sf = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
    $stream = Await ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $text = ($result.Lines | ForEach-Object { $_.Text }) -join ' | '
    Write-Output ("=== {0} ===" -f $_.Name)
    Write-Output $text
  } catch {
    Write-Output ("=== {0} === OCR FAILED: {1}" -f $_.Name, $_.Exception.Message)
  }
}