param([string]$Version='2.0.32-expressive-preview')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$workspace=Split-Path -Parent $project
$release=Join-Path $project 'build/windows/x64/runner/Release'
if (!(Test-Path -LiteralPath (Join-Path $release 'breakfast_orders.exe'))) { throw 'Build the Windows release first.' }
$output=Join-Path $workspace 'release'
$bundle=Join-Path $output "Breakfast-Orders-Flutter-$Version-Windows"
New-Item -ItemType Directory -Force $bundle | Out-Null
Copy-Item -Path "$release/*" -Destination $bundle -Recurse -Force
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio=(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
$redistRoot=Join-Path $visualStudio 'VC/Redist/MSVC'
$redistVersion=Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object Name -Match '^\d' | Sort-Object Name -Descending | Select-Object -First 1
$crt=Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName 'x64') -Directory | Where-Object Name -Match '\.CRT$' | Select-Object -First 1
foreach($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) { Copy-Item -LiteralPath (Join-Path $crt.FullName $name) -Destination $bundle -Force }
$licenses=Join-Path $bundle 'licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $visualStudio 'Licenses/1033/Redist.txt') -Destination (Join-Path $licenses 'Microsoft-Redist.txt') -Force
$thirdParty=Get-ChildItem -LiteralPath (Join-Path $visualStudio 'Licenses') -Recurse -File -Filter ThirdPartyNotices.txt | Select-Object -First 1
if ($thirdParty) { Copy-Item -LiteralPath $thirdParty.FullName -Destination (Join-Path $licenses 'Microsoft-ThirdPartyNotices.txt') -Force }
$cache=if($env:PUB_CACHE){$env:PUB_CACHE}else{Join-Path $workspace '.tools/pub-cache'}
$mailSource=Join-Path $cache 'hosted/pub.dev/enough_mail-2.1.7'
Copy-Item -LiteralPath (Join-Path $mailSource 'LICENSE') -Destination (Join-Path $licenses 'enough_mail-MPL-2.0.txt') -Force
Compress-Archive -Path "$mailSource/lib", "$mailSource/LICENSE", "$mailSource/pubspec.yaml", "$mailSource/README.md", "$mailSource/CHANGELOG.md" -DestinationPath (Join-Path $licenses 'enough_mail-2.1.7-source.zip') -Force
Copy-Item -LiteralPath (Join-Path $project 'docs/START-HERE.txt') -Destination $bundle -Force
Copy-Item -LiteralPath (Join-Path $project 'docs/THIRD-PARTY-NOTICES.txt') -Destination $bundle -Force
$zip=Join-Path $output "Breakfast-Orders-Flutter-$Version-Windows.zip"
Compress-Archive -LiteralPath $bundle -DestinationPath $zip -CompressionLevel Optimal -Force
$size=(Get-ChildItem -LiteralPath $bundle -Recurse -File | Measure-Object Length -Sum).Sum
$report=[ordered]@{version=$Version;zipBytes=(Get-Item -LiteralPath $zip).Length;installedBytes=$size;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;files=(Get-ChildItem -LiteralPath $bundle -Recurse -File).Count}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'package-size.json')
$report | ConvertTo-Json









