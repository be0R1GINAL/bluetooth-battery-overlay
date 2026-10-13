$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $compiler)) { throw 'The .NET Framework C# compiler is unavailable.' }
$automation = Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
if (-not (Test-Path $automation)) { throw 'Windows PowerShell 5.1 is unavailable.' }
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:$automation /reference:System.Windows.Forms.dll /reference:System.Core.dll /win32icon:BluetoothBatteryOverlay.ico /resource:BluetoothBatteryOverlay.ps1,BluetoothBatteryOverlay.ps1 /out:BluetoothBatteryOverlay-Portable-1.1.1.exe PortableHost.cs
if ($LASTEXITCODE -ne 0) { throw "C# compiler exited with $LASTEXITCODE." }
