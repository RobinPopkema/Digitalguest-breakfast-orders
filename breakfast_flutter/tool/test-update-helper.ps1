$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$workspace=Split-Path -Parent $project
$root=Join-Path $workspace ('.update-helper-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$release=Join-Path $project 'build/windows/x64/runner/Release'
$payload=Join-Path $root 'payload'
New-Item -ItemType Directory -Path $payload | Out-Null
Get-ChildItem -LiteralPath $release | Copy-Item -Destination $payload -Recurse
'new' | Set-Content -LiteralPath (Join-Path $payload 'update-marker.txt')
$zip=Join-Path $root 'release.zip'
Compress-Archive -LiteralPath $payload -DestinationPath $zip
foreach($scenario in @('success','checksum','rollback','traversal')) {
  $case=Join-Path $root $scenario
  $target=Join-Path $case 'app'
  $profile=Join-Path $case 'profile'
  New-Item -ItemType Directory -Path $target,$profile | Out-Null
  Get-ChildItem -LiteralPath $release | Copy-Item -Destination $target -Recurse
  'old' | Set-Content -LiteralPath (Join-Path $target 'update-marker.txt')
  'orders-stay-here' | Set-Content -LiteralPath (Join-Path $profile 'orders.txt')
  $archive=$zip
  if ($scenario -eq 'traversal') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=Join-Path $case 'malicious.zip'
    $z=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    $e=$z.CreateEntry('../escape.txt'); $stream=$e.Open(); $stream.WriteByte(65); $stream.Dispose(); $z.Dispose()
  }
  $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
  if ($scenario -eq 'checksum') { $hash='0'*64 }
  $config=Join-Path $case 'update.json'
  @{pid=2147483647;install=$target;profile=$profile;zip=$archive;sha256=$hash} | ConvertTo-Json | Set-Content -LiteralPath $config
  $extra=@()
  if ($scenario -eq 'rollback') { $extra=@('-TestFailureAfterSwap') }
  $helper=Join-Path $project 'assets/update/install.ps1'
  $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -Config "'+$config+'" -TestMode '+($extra -join ' ')
  $process=Start-Process powershell.exe -ArgumentList $arguments -WorkingDirectory $target -WindowStyle Hidden -Wait -PassThru
  $global:LASTEXITCODE=$process.ExitCode
  $expected=if($scenario -eq 'success'){'new'}else{'old'}
  if ((Get-Content -LiteralPath (Join-Path $target 'update-marker.txt')) -ne $expected) { throw "Unexpected files after $scenario" }
  if ((Get-Content -LiteralPath (Join-Path $profile 'orders.txt')) -ne 'orders-stay-here') { throw 'Profile changed.' }
  if ($scenario -eq 'success' -and $LASTEXITCODE -ne 0) { throw (Get-Content -LiteralPath (Join-Path $case 'error.txt')) }
  if ($scenario -ne 'success' -and $LASTEXITCODE -eq 0) { throw "Expected failure: $scenario" }
  if (Test-Path -LiteralPath (Join-Path $case 'escape.txt')) { throw 'Archive escaped staging.' }
  Write-Output "$scenario passed"
}
$global:LASTEXITCODE=0
