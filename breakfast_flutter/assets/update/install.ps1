param([Parameter(Mandatory=$true)][string]$Config, [switch]$TestMode, [switch]$TestFailureAfterSwap)
$ErrorActionPreference='Stop'
$work=Split-Path -Parent ([IO.Path]::GetFullPath($Config))
$backup=$null
$installed=$false
$target=$null
try {
  $settings=Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
  $target=[IO.Path]::GetFullPath($settings.install).TrimEnd('\')
  $parent=Split-Path -Parent $target
  if (!$parent -or !(Test-Path -LiteralPath (Join-Path $target 'breakfast_orders.exe')) -or
      !(Test-Path -LiteralPath (Join-Path $target 'flutter_windows.dll'))) { throw 'Invalid application folder.' }
  if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked application folders are not supported.' }
  $profile=[IO.Path]::GetFullPath($settings.profile)
  if ($profile.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase) -or $profile -eq $target) { throw 'Move your profile outside the application folder before updating.' }
  if ((Get-FileHash -LiteralPath $settings.zip -Algorithm SHA256).Hash -ne $settings.sha256) { throw 'The update checksum is invalid.' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $expanded=Join-Path $work 'expanded'
  New-Item -ItemType Directory -Path $expanded | Out-Null
  $archive=[IO.Compression.ZipFile]::OpenRead($settings.zip)
  try {
    $total=0L
    foreach($entry in $archive.Entries) {
      $name=$entry.FullName.Replace('/','\')
      $destination=[IO.Path]::GetFullPath((Join-Path $expanded $name))
      if ($name.Contains(':') -or !$destination.StartsWith($expanded+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive path.' }
      $total += $entry.Length
      if ($total -gt 500000000) { throw 'The expanded update is too large.' }
    }
  } finally { $archive.Dispose() }
  [IO.Compression.ZipFile]::ExtractToDirectory($settings.zip,$expanded)
  $roots=@(Get-ChildItem -LiteralPath $expanded -Directory)
  if ($roots.Count -ne 1 -or @(Get-ChildItem -LiteralPath $expanded -File).Count -ne 0) { throw 'Unexpected update layout.' }
  $payload=$roots[0].FullName
  foreach($required in @('breakfast_orders.exe','flutter_windows.dll','data\flutter_assets')) {
    if (!(Test-Path -LiteralPath (Join-Path $payload $required))) { throw "Missing update file: $required" }
  }
  $smoke=Join-Path $work 'smoke.json'
  $probe=Start-Process -FilePath (Join-Path $payload 'breakfast_orders.exe') -ArgumentList ('"--smoke-test='+$smoke+'"') -WindowStyle Hidden -PassThru
  if (!$probe.WaitForExit(60000)) { $probe.Kill(); throw 'The new application did not pass its startup check.' }
  if ($probe.ExitCode -ne 0 -or !(Test-Path -LiteralPath $smoke) -or !(Get-Content -LiteralPath $smoke -Raw | ConvertFrom-Json).ok) { throw 'The new application failed its startup check.' }
  $stamp=[Guid]::NewGuid().ToString('N')
  $staging=Join-Path $parent ('.breakfast-update-'+$stamp)
  $backup=Join-Path $parent ('.breakfast-previous-'+$stamp)
  # Preserve unrelated files in a portable app folder; do not recursively delete it.
  if (Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked files in the application folder are not supported.' }
  New-Item -ItemType Directory -Path $staging | Out-Null
  Get-ChildItem -LiteralPath $target -Force | Copy-Item -Destination $staging -Recurse -Force
  Get-ChildItem -LiteralPath $payload -Force | Copy-Item -Destination $staging -Recurse -Force
  # Both sibling destinations are checked before moving either directory.
  foreach($path in @($staging,$backup)) {
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($path))) -ne $parent) { throw 'Unsafe update destination.' }
  }
  'ready' | Set-Content -LiteralPath (Join-Path $work 'ready')
  # Wait for the old process to release its executable. Never terminate user work.
  $old=Get-Process -Id $settings.pid -ErrorAction SilentlyContinue
  if ($old -and !$old.WaitForExit(60000)) { throw 'Close Breakfast Orders and try again.' }
  Move-Item -LiteralPath $target -Destination $backup
  try { Move-Item -LiteralPath $staging -Destination $target; $installed=$true }
  catch { Move-Item -LiteralPath $backup -Destination $target; throw }
  if ($TestMode -and $TestFailureAfterSwap) { throw 'Simulated restart failure.' }
  if (!$TestMode) { Start-Process -FilePath (Join-Path $target 'breakfast_orders.exe') -ArgumentList ('"--profile='+$profile+'"') -WorkingDirectory $target -WindowStyle Hidden | Out-Null }
  'Update installed. Previous application: '+$backup | Set-Content -LiteralPath (Join-Path $work 'result.txt')
} catch {
  $message=$_.Exception.Message
  if ($installed -and (Test-Path -LiteralPath $backup)) {
    $failed=Join-Path $parent ('.breakfast-failed-'+[Guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $target -Destination $failed
    Move-Item -LiteralPath $backup -Destination $target
  }
  $message | Set-Content -LiteralPath (Join-Path $work 'error.txt')
  if (!$TestMode) {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("The update could not be installed. Your order data is unchanged.`n`n$message`n`nDetails: $work",'Breakfast Orders update') | Out-Null
  }
  if (!$TestMode -and !(Get-Process -Id $settings.pid -ErrorAction SilentlyContinue) -and $target -and (Test-Path -LiteralPath (Join-Path $target 'breakfast_orders.exe'))) {
    Start-Process -FilePath (Join-Path $target 'breakfast_orders.exe') -ArgumentList ('"--profile='+$profile+'"') -WorkingDirectory $target -WindowStyle Hidden | Out-Null
  }
  exit 1
}
