[Setup]
AppId=BluetoothBatteryOverlay.be0R1GINAL
AppName=Bluetooth Battery Overlay
AppVersion=1.0.0
AppPublisher=be0R1GINAL
DefaultDirName={localappdata}\Programs\Bluetooth Battery Overlay
DefaultGroupName=Bluetooth Battery Overlay
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
WizardStyle=modern
MinVersion=10.0
OutputDir=.
OutputBaseFilename=BluetoothBatteryOverlay-Setup-1.0.0
SetupIconFile=BluetoothBatteryOverlay.ico
UninstallDisplayIcon={app}\BluetoothBatteryOverlay.ico
Compression=lzma
SolidCompression=yes
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[CustomMessages]
english.LaunchOverlay=Launch Bluetooth Battery Overlay
russian.LaunchOverlay=Запустить Bluetooth Battery Overlay

[Files]
Source: "BluetoothBatteryOverlay.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Start Bluetooth Battery Overlay.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "BluetoothBatteryOverlay.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Bluetooth Battery Overlay"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\BluetoothBatteryOverlay.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\BluetoothBatteryOverlay.ico"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\BluetoothBatteryOverlay.ps1"""; Description: "{cm:LaunchOverlay}"; Flags: nowait postinstall skipifsilent
