param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$settingsPath = Join-Path $env:APPDATA 'BluetoothBatteryOverlay\settings.json'
$defaultLanguage = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' }
$settings = @{ Left = $null; Top = $null; Width = 215; Opacity = 0.85; Color = '#FFFFFF'; Language = $defaultLanguage; HiddenDevices = @(); KnownDevices = @() }
if (Test-Path $settingsPath) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        foreach ($key in @('Left', 'Top', 'Width', 'Opacity', 'Color', 'Language', 'HiddenDevices', 'KnownDevices')) {
            if ($null -ne $saved.$key) { $settings[$key] = $saved.$key }
        }
    } catch { Write-Warning "Settings could not be loaded: $_" }
}
$settings.HiddenDevices = @($settings.HiddenDevices | Where-Object { $_ -is [string] -and $_ })
$settings.KnownDevices = @($settings.KnownDevices | Where-Object { $_ -is [string] -and $_ })
if ($settings.Language -notin @('ru', 'en')) { $settings.Language = $defaultLanguage }
$script:translations = @{
    ru = @{ ReadError = 'Ошибка чтения устройств'; AllHidden = 'Все устройства скрыты'; NoDevices = 'Нет подключённых устройств'; SettingsTitle = 'Настройки'; OpacityLabel = 'Прозрачность фона'; SizeLabel = 'Размер окна'; ColorLabel = 'Цвет значков и текста'; OpenPaletteLabel = 'Открыть палитру цветов'; PaletteTitle = 'Выберите цвет'; Done = 'Готово'; ChooseDevices = 'Выбрать устройства'; DevicesTitle = 'Показывать в оверлее'; ExitApp = 'Выход'; DragHint = 'Перетащите оверлей мышью'; NoKnownDevices = 'Устройства пока не обнаружены'; LanguageLabel = 'Язык' }
    en = @{ ReadError = 'Could not read devices'; AllHidden = 'All devices are hidden'; NoDevices = 'No connected devices'; SettingsTitle = 'Settings'; OpacityLabel = 'Background transparency'; SizeLabel = 'Window size'; ColorLabel = 'Icon and text color'; OpenPaletteLabel = 'Open color palette'; PaletteTitle = 'Choose a color'; Done = 'Done'; ChooseDevices = 'Choose devices'; DevicesTitle = 'Show in overlay'; ExitApp = 'Exit'; DragHint = 'Drag the overlay to move it'; NoKnownDevices = 'No devices found yet'; LanguageLabel = 'Language' }
}
function Get-UiText([string]$key) { $script:translations[$settings.Language][$key] }

function Save-Settings {
    $directory = Split-Path -Parent $settingsPath
    [void][System.IO.Directory]::CreateDirectory($directory)
    $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

$script:bluetoothContainers = @{}
$script:handsFreeContainers = @{}
function Await-WinRT($operation, [type]$resultType) {
    $task = $script:asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    if (-not $task.Wait(3000)) { throw 'Bluetooth battery read timed out.' }
    $task.Result
}
function Get-BleBattery([UInt64]$address) {
    try {
        if (-not $script:bleReady) {
            Add-Type -AssemblyName System.Runtime.WindowsRuntime
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("905a0fef-bc53-11df-8c49-001e4fc686da"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IBufferByteAccess { void Buffer(out IntPtr value); }
public static class BtOverlayBufferReader {
    public static byte First(object buffer) {
        IntPtr unknown = Marshal.GetIUnknownForObject(buffer);
        try {
            Guid iid = typeof(IBufferByteAccess).GUID;
            IntPtr pointer;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, ref iid, out pointer));
            try {
                var access = (IBufferByteAccess)Marshal.GetTypedObjectForIUnknown(pointer, typeof(IBufferByteAccess));
                IntPtr data;
                access.Buffer(out data);
                return Marshal.ReadByte(data);
            } finally { Marshal.Release(pointer); }
        } finally { Marshal.Release(unknown); }
    }
}
'@
            $script:bleType = [Windows.Devices.Bluetooth.BluetoothLEDevice,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
            $script:servicesType = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
            $script:characteristicsType = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
            $script:readType = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattReadResult,Windows.Devices.Bluetooth,ContentType=WindowsRuntime]
            $script:asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
                $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            } | Select-Object -First 1
            $script:bleReady = $true
        }
        $device = Await-WinRT ($script:bleType::FromBluetoothAddressAsync($address)) $script:bleType
        if (-not $device -or $device.ConnectionStatus -ne 'Connected') { return $null }
        try {
            $services = Await-WinRT ($device.GetGattServicesForUuidAsync([guid]'0000180f-0000-1000-8000-00805f9b34fb')) $script:servicesType
            if ($services.Status -ne 'Success') { return $null }
            foreach ($service in $services.Services) {
                try {
                    $characteristics = Await-WinRT ($service.GetCharacteristicsForUuidAsync([guid]'00002a19-0000-1000-8000-00805f9b34fb')) $script:characteristicsType
                    if ($characteristics.Status -ne 'Success') { continue }
                    foreach ($characteristic in $characteristics.Characteristics) {
                        $read = Await-WinRT ($characteristic.ReadValueAsync()) $script:readType
                        if ($read.Status -eq 'Success' -and $read.Value.Length -gt 0) { return [int][BtOverlayBufferReader]::First($read.Value) }
                    }
                } finally { $service.Dispose() }
            }
        } finally { $device.Dispose() }
    } catch { return $null }
    $null
}
function Get-DeviceIcon([string]$description) {
    switch -Regex ($description) {
        '(?i)mouse|мыш' { 'mouse'; break }
        '(?i)keyboard|клавиат' { 'keyboard'; break }
        '(?i)headphone|headset|\bear\b|earbud|buds|науш|гарнит' { 'headphones'; break }
        '(?i)controller|gamepad|игров|геймпад' { 'controller'; break }
        '(?i)watch|часы' { 'watch'; break }
        '(?i)speaker|колонк|динамик' { 'speaker'; break }
        default { 'bluetooth' }
    }
}
function Get-BluetoothDevices {
    $ids = @{}
    $bleAddresses = @{}
    $handsFreeNodes = @{}
    Get-PnpDevice -Class Bluetooth -ErrorAction Stop |
        Where-Object { $_.InstanceId -match '^(BTHENUM|BTHLE)\\DEV_' } |
        ForEach-Object {
            if (-not $script:bluetoothContainers.ContainsKey($_.InstanceId)) {
                $container = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_ContainerId' -ErrorAction SilentlyContinue
                if ($container -and $container.Data) { $script:bluetoothContainers[$_.InstanceId] = [string]$container.Data }
            }
            if ($script:bluetoothContainers.ContainsKey($_.InstanceId)) {
                $containerId = $script:bluetoothContainers[$_.InstanceId]
                $ids[$containerId] = $true
                if ($_.InstanceId -match '^BTHLE\\DEV_([0-9A-Fa-f]{12})') {
                    $bleAddresses[$containerId] = [Convert]::ToUInt64($Matches[1], 16)
                }
            }
        }
    Get-PnpDevice -Class System -ErrorAction Stop |
        Where-Object { $_.InstanceId -match '^BTHENUM\\\{0000111E-0000-1000-8000-00805F9B34FB\}' } |
        ForEach-Object {
            if (-not $script:handsFreeContainers.ContainsKey($_.InstanceId)) {
                $container = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_ContainerId' -ErrorAction SilentlyContinue
                if ($container -and $container.Data) { $script:handsFreeContainers[$_.InstanceId] = [string]$container.Data }
            }
            if ($script:handsFreeContainers.ContainsKey($_.InstanceId)) {
                $handsFreeNodes[$script:handsFreeContainers[$_.InstanceId]] = $_.InstanceId
            }
        }

    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace('shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}')
    if (-not $folder) { throw 'Windows Devices and Printers folder is unavailable.' }
    foreach ($item in $folder.Items()) {
        $containerId = [string]$item.ExtendedProperty('System.Devices.ContainerId')
        if (-not $ids.ContainsKey($containerId) -or
            $item.ExtendedProperty('System.Devices.Connected') -ne $true) { continue }
        $battery = $item.ExtendedProperty('System.Devices.BatteryLife')
        $batteryPercent = 0
        $hasBattery = [int]::TryParse([string]$battery, [ref]$batteryPercent) -and $batteryPercent -ge 0 -and $batteryPercent -le 100
        if (-not $hasBattery -and $handsFreeNodes.ContainsKey($containerId)) {
            $level = Get-PnpDeviceProperty -InstanceId $handsFreeNodes[$containerId] -KeyName '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2' -ErrorAction SilentlyContinue
            if ($level) { $battery = $level.Data }
            $hasBattery = [int]::TryParse([string]$battery, [ref]$batteryPercent) -and $batteryPercent -ge 0 -and $batteryPercent -le 100
        }
        if (-not $hasBattery -and $bleAddresses.ContainsKey($containerId)) {
            $battery = Get-BleBattery $bleAddresses[$containerId]
            $hasBattery = [int]::TryParse([string]$battery, [ref]$batteryPercent) -and $batteryPercent -ge 0 -and $batteryPercent -le 100
        }
        $icon = Get-DeviceIcon ([string]$item.Name)
        if ($icon -eq 'bluetooth') { $icon = Get-DeviceIcon ((@($item.ExtendedProperty('System.Devices.Category')) -join ' ')) }
        [pscustomobject]@{
            Name = [string]$item.Name
            Battery = if ($hasBattery) { $batteryPercent } else { $null }
            Icon = $icon
        }
    }
}

if ($SelfTest) {
    if ((Get-DeviceIcon 'Беспроводная мышь') -ne 'mouse' -or
        (Get-DeviceIcon 'Nothing Headphone (1)') -ne 'headphones' -or
        (Get-DeviceIcon 'Wireless Controller') -ne 'controller' -or
        (Get-DeviceIcon 'Keyboard') -ne 'keyboard' -or
        (Get-DeviceIcon 'CMF Watch 3 Pro') -ne 'watch' -or
        (Get-DeviceIcon 'Bluetooth Speaker') -ne 'speaker') { throw 'Device icon mapping failed.' }
    @(Get-BluetoothDevices) | Format-Table -AutoSize
    return
}
$created = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\BluetoothBatteryOverlay', [ref]$created)
if (-not $created) { $mutex.Dispose(); return }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Bluetooth Battery Overlay" Width="215" MinWidth="94" MaxWidth="215" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
  <Border Name="Panel" Background="#DD18212D" CornerRadius="14" Padding="10,8" Cursor="SizeAll">
    <StackPanel Name="Devices"/>
  </Border>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$panel = $window.FindName('Panel')
$list = $window.FindName('Devices')
$window.Width = [Math]::Max(94, [Math]::Min(215, [double]$settings.Width))
$settings.Opacity = [Math]::Max(0.0, [Math]::Min(1.0, [double]$settings.Opacity))
try { $script:brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$settings.Color) }
catch { $script:brush = [System.Windows.Media.Brushes]::White; $settings.Color = '#FFFFFF' }
$iconGeometry = @{
    headphones = 'M 3,13 L 3,10 C 3,5 7,2 12,2 C 17,2 21,5 21,10 L 21,13 M 3,13 L 7,13 L 7,20 L 3,20 Z M 21,13 L 17,13 L 17,20 L 21,20 Z'
    mouse = 'M 12,2 C 7,2 4,5 4,10 L 4,15 C 4,20 7,22 12,22 C 17,22 20,20 20,15 L 20,10 C 20,5 17,2 12,2 Z M 12,2 L 12,10'
    keyboard = 'M 3,6 L 21,6 L 21,18 L 3,18 Z M 5,9 L 7,9 M 9,9 L 11,9 M 13,9 L 15,9 M 17,9 L 19,9 M 6,13 L 18,13'
    controller = 'M 7,8 L 17,8 C 20,8 21,10 22,14 L 22,17 C 22,20 20,21 18,19 L 16,17 L 8,17 L 6,19 C 4,21 2,20 2,17 L 2,14 C 2,10 4,8 7,8 Z M 7,11 L 7,16 M 4.5,13.5 L 9.5,13.5 M 16,12 L 16.1,12 M 19,14 L 19.1,14'
    watch = 'M 8,2 L 16,2 L 16,6 L 8,6 Z M 6,6 L 18,6 L 18,18 L 6,18 Z M 8,18 L 16,18 L 16,22 L 8,22 Z M 12,9 L 12,12 L 15,14'
    speaker = 'M 6,2 L 18,2 L 18,22 L 6,22 Z M 12,7 L 12.1,7 M 12,13 C 9,13 8,15 8,17 C 8,19 10,20 12,20 C 14,20 16,19 16,17 C 16,15 15,13 12,13 Z'
    bluetooth = 'M 9,2 L 17,9 L 9,16 L 9,2 M 4,6 L 17,18 L 9,22 L 9,8 M 4,18 L 17,6'
}
function Set-PanelOpacity {
    # Layered WPF windows need a nonzero alpha to receive mouse input.
    $alpha = [byte][Math]::Max(1, [Math]::Round(255 * [double]$settings.Opacity))
    $panel.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb($alpha, 24, 33, 45))
}
Set-PanelOpacity

function Render-Devices {
    $list.Children.Clear()
    $compact = $window.Width -le 170
    $panel.Padding = if ($compact) { '8,5' } else { '10,8' }
    $visibleDevices = @($script:devices | Where-Object { $null -ne $_ -and $settings.HiddenDevices -notcontains $_.Name })
    if ($visibleDevices.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = if ($compact) { '—' } elseif ($script:readError) { Get-UiText 'ReadError' } elseif ($script:devices.Count -gt 0) { Get-UiText 'AllHidden' } else { Get-UiText 'NoDevices' }
        $empty.Foreground = $brush
        [void]$list.Children.Add($empty)
        return
    }
    foreach ($device in $visibleDevices) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,2,0,2'
        $row.ToolTip = $device.Name
        $percent = New-Object System.Windows.Controls.TextBlock
        $percent.Text = if ($null -ne $device.Battery) { "$($device.Battery)%" } else { '—' }
        $percent.Foreground = $brush
        $percent.FontSize = 14
        $percent.FontWeight = 'Bold'
        $percent.VerticalAlignment = 'Center'
        $percent.Margin = if ($compact) { '5,0,0,0' } else { '10,0,0,0' }
        [System.Windows.Controls.DockPanel]::SetDock($percent, 'Right')
        [void]$row.Children.Add($percent)
        $icon = New-Object System.Windows.Shapes.Path
        $icon.Data = [System.Windows.Media.Geometry]::Parse($iconGeometry[$device.Icon])
        $icon.Stroke = $brush
        $icon.StrokeThickness = 2
        $icon.StrokeStartLineCap = 'Round'
        $icon.StrokeEndLineCap = 'Round'
        $icon.StrokeLineJoin = 'Round'
        $icon.Stretch = 'Uniform'
        $icon.Width = 21
        $icon.Height = 21
        $icon.Margin = if ($compact) { '0,0,2,0' } else { '0,0,7,0' }
        [System.Windows.Controls.DockPanel]::SetDock($icon, 'Left')
        [void]$row.Children.Add($icon)
        if (-not $compact) {
            $name = New-Object System.Windows.Controls.TextBlock
            $name.Text = $device.Name
            $name.Foreground = $brush
            $name.TextTrimming = 'CharacterEllipsis'
            $name.VerticalAlignment = 'Center'
            [void]$row.Children.Add($name)
        }
        [void]$list.Children.Add($row)
    }
}

function Refresh-Devices {
    try { $script:devices = @(Get-BluetoothDevices | Sort-Object Name -Unique); $script:readError = $false }
    catch { $script:devices = @(); $script:readError = $true }
    $newDevice = $false
    foreach ($device in $script:devices) {
        if ($settings.KnownDevices -notcontains $device.Name) { $settings.KnownDevices += $device.Name; $newDevice = $true }
    }
    if ($newDevice) { Save-Settings }
    Update-DeviceChoices
    Render-Devices
}

[xml]$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="330" Height="405" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
  <Window.Resources>
    <Style TargetType="Slider">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Track Name="PART_Track" Height="18" VerticalAlignment="Center">
              <Track.DecreaseRepeatButton>
                <RepeatButton Command="Slider.DecreaseLarge" Focusable="False">
                  <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="#55E6BE" Height="5" CornerRadius="3"/></ControlTemplate></RepeatButton.Template>
                </RepeatButton>
              </Track.DecreaseRepeatButton>
              <Track.Thumb>
                <Thumb Width="17" Height="17">
                  <Thumb.Template><ControlTemplate TargetType="Thumb"><Ellipse Fill="#E8FFF8" Stroke="#55E6BE" StrokeThickness="2"/></ControlTemplate></Thumb.Template>
                </Thumb>
              </Track.Thumb>
              <Track.IncreaseRepeatButton>
                <RepeatButton Command="Slider.IncreaseLarge" Focusable="False">
                  <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="#385365" Height="5" CornerRadius="3"/></ControlTemplate></RepeatButton.Template>
                </RepeatButton>
              </Track.IncreaseRepeatButton>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#F1F7FF"/>
      <Setter Property="Background" Value="#263949"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="ButtonFace" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonFace" Property="Opacity" Value="0.75"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Name="SettingsPanel" Background="#F41A2532" BorderBrush="#637D91" BorderThickness="1"
          CornerRadius="18" Padding="20">
    <Border.Effect><DropShadowEffect Color="Black" BlurRadius="20" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
    <StackPanel>
      <DockPanel Margin="0,0,0,20">
        <Button Name="CloseSettings" Content="✕" DockPanel.Dock="Right" Width="30" Height="30" Padding="0" Background="#314657"/>
        <TextBlock Name="SettingsTitle" Text="Настройки" Foreground="#F1F7FF" FontSize="18" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </DockPanel>
      <DockPanel Margin="0,0,0,16">
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <Button Name="RussianLanguage" Content="RU" Width="43" Margin="0,0,5,0"/>
          <Button Name="EnglishLanguage" Content="EN" Width="43"/>
        </StackPanel>
        <TextBlock Name="LanguageLabel" Text="Язык" Foreground="#D7E4EF" VerticalAlignment="Center"/>
      </DockPanel>
      <DockPanel Margin="0,0,0,5">
        <TextBlock Name="OpacityValue" DockPanel.Dock="Right" Foreground="#57E6BE" FontWeight="Bold"/>
        <TextBlock Name="OpacityLabel" Text="Прозрачность фона" Foreground="#D7E4EF"/>
      </DockPanel>
      <Slider Name="OpacitySlider" Minimum="0" Maximum="100" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,0,0,17"/>
      <DockPanel Margin="0,0,0,5">
        <TextBlock Name="SizeValue" DockPanel.Dock="Right" Foreground="#57E6BE" FontWeight="Bold"/>
        <TextBlock Name="SizeLabel" Text="Размер окна" Foreground="#D7E4EF"/>
      </DockPanel>
      <Slider Name="SizeSlider" Minimum="94" Maximum="215" TickFrequency="1" IsSnapToTickEnabled="True" Margin="0,0,0,18"/>
      <TextBlock Name="ColorLabel" Text="Цвет значков и текста" Foreground="#D7E4EF" Margin="0,0,0,10"/>
      <Button Name="OpenPalette" Background="#263949" Margin="0,0,0,17">
        <StackPanel Orientation="Horizontal">
          <Border Name="CurrentColor" Width="18" Height="18" CornerRadius="9" Background="White" Margin="0,0,10,0"/>
          <TextBlock Name="OpenPaletteLabel" Text="Открыть палитру цветов" VerticalAlignment="Center"/>
        </StackPanel>
      </Button>
      <Popup Name="ColorPopup" PlacementTarget="{Binding ElementName=OpenPalette}" Placement="Bottom"
             StaysOpen="True" AllowsTransparency="True" PopupAnimation="Fade">
        <Border Background="#F41A2532" BorderBrush="#637D91" BorderThickness="1" CornerRadius="16" Padding="16" Width="286">
          <Border.Effect><DropShadowEffect Color="Black" BlurRadius="18" ShadowDepth="4" Opacity="0.55"/></Border.Effect>
          <StackPanel>
            <TextBlock Name="PaletteTitle" Text="Выберите цвет" Foreground="#F1F7FF" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
            <Border Name="PaletteSquare" Width="252" Height="155" Background="Red" Cursor="Cross" CornerRadius="7" ClipToBounds="True">
              <Grid Name="PaletteSurface" Background="Transparent">
                <Rectangle IsHitTestVisible="False">
                  <Rectangle.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="White" Offset="0"/><GradientStop Color="#00FFFFFF" Offset="1"/></LinearGradientBrush></Rectangle.Fill>
                </Rectangle>
                <Rectangle IsHitTestVisible="False">
                  <Rectangle.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#00000000" Offset="0"/><GradientStop Color="Black" Offset="1"/></LinearGradientBrush></Rectangle.Fill>
                </Rectangle>
                <Ellipse Name="PaletteCursor" Width="14" Height="14" Stroke="White" StrokeThickness="2" HorizontalAlignment="Left" VerticalAlignment="Top" IsHitTestVisible="False">
                  <Ellipse.Effect><DropShadowEffect Color="Black" BlurRadius="2" ShadowDepth="0" Opacity="0.9"/></Ellipse.Effect>
                </Ellipse>
              </Grid>
            </Border>
            <Border Name="HueStrip" Height="16" Margin="0,14,0,14" CornerRadius="5" Cursor="Hand">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="Red" Offset="0"/><GradientStop Color="Yellow" Offset="0.1667"/><GradientStop Color="Lime" Offset="0.3333"/><GradientStop Color="Cyan" Offset="0.5"/><GradientStop Color="Blue" Offset="0.6667"/><GradientStop Color="Magenta" Offset="0.8333"/><GradientStop Color="Red" Offset="1"/></LinearGradientBrush></Border.Background>
            </Border>
            <DockPanel>
              <Button Name="PaletteDone" Content="Готово" DockPanel.Dock="Right" Background="#176F61"/>
              <Border Name="PalettePreview" Width="33" Height="33" CornerRadius="9" Background="White" HorizontalAlignment="Left"/>
            </DockPanel>
          </StackPanel>
        </Border>
      </Popup>
      <Button Name="ChooseDevices" Content="Выбрать устройства" Background="#263949" Margin="0,0,0,17"/>
      <Popup Name="DevicesPopup" PlacementTarget="{Binding ElementName=ChooseDevices}" Placement="Bottom"
             StaysOpen="True" AllowsTransparency="True" PopupAnimation="Fade">
        <Border Background="#F41A2532" BorderBrush="#637D91" BorderThickness="1" CornerRadius="16" Padding="16" Width="286">
          <Border.Effect><DropShadowEffect Color="Black" BlurRadius="18" ShadowDepth="4" Opacity="0.55"/></Border.Effect>
          <StackPanel>
            <TextBlock Name="DevicesTitle" Text="Показывать в оверлее" Foreground="#F1F7FF" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
            <ScrollViewer MaxHeight="220" VerticalScrollBarVisibility="Auto">
              <StackPanel Name="DeviceChoices"/>
            </ScrollViewer>
            <Button Name="DevicesDone" Content="Готово" Background="#176F61" HorizontalAlignment="Right" Margin="0,12,0,0"/>
          </StackPanel>
        </Border>
      </Popup>
      <DockPanel>
        <Button Name="ExitApp" Content="Выход" DockPanel.Dock="Right" Background="#4A303C"/>
        <TextBlock Name="DragHint" Text="Перетащите оверлей мышью" Foreground="#90A6B8" FontSize="11" VerticalAlignment="Center"/>
      </DockPanel>
    </StackPanel>
  </Border>
</Window>
'@
$settingsWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $settingsXaml))
$settingsPanel = $settingsWindow.FindName('SettingsPanel')
$opacitySlider = $settingsWindow.FindName('OpacitySlider')
$sizeSlider = $settingsWindow.FindName('SizeSlider')
$opacityValue = $settingsWindow.FindName('OpacityValue')
$sizeValue = $settingsWindow.FindName('SizeValue')
$colorPopup = $settingsWindow.FindName('ColorPopup')
$paletteSquare = $settingsWindow.FindName('PaletteSquare')
$paletteSurface = $settingsWindow.FindName('PaletteSurface')
$hueStrip = $settingsWindow.FindName('HueStrip')
$paletteCursor = $settingsWindow.FindName('PaletteCursor')
$currentColor = $settingsWindow.FindName('CurrentColor')
$palettePreview = $settingsWindow.FindName('PalettePreview')
$devicesPopup = $settingsWindow.FindName('DevicesPopup')
$deviceChoices = $settingsWindow.FindName('DeviceChoices')
$opacitySlider.Value = [Math]::Round((1 - [double]$settings.Opacity) * 100)
$sizeSlider.Value = $window.Width
$opacityValue.Text = "$([int]$opacitySlider.Value)%"
$sizeValue.Text = "$([int]$sizeSlider.Value) px"
function Set-Language([string]$language) {
    $settings.Language = $language
    foreach ($key in @('SettingsTitle','LanguageLabel','OpacityLabel','SizeLabel','ColorLabel','OpenPaletteLabel','PaletteTitle','DevicesTitle','DragHint')) {
        $settingsWindow.FindName($key).Text = Get-UiText $key
    }
    $settingsWindow.FindName('PaletteDone').Content = Get-UiText 'Done'
    $settingsWindow.FindName('DevicesDone').Content = Get-UiText 'Done'
    $settingsWindow.FindName('ChooseDevices').Content = Get-UiText 'ChooseDevices'
    $settingsWindow.FindName('ExitApp').Content = Get-UiText 'ExitApp'
    $settingsWindow.FindName('RussianLanguage').Background = if ($language -eq 'ru') { '#176F61' } else { '#263949' }
    $settingsWindow.FindName('EnglishLanguage').Background = if ($language -eq 'en') { '#176F61' } else { '#263949' }
    Update-DeviceChoices
    Render-Devices
    Save-Settings
}
$settingsWindow.FindName('RussianLanguage').Add_Click({ Set-Language 'ru' })
$settingsWindow.FindName('EnglishLanguage').Add_Click({ Set-Language 'en' })

function Set-TextColor([string]$value) {
    $value = $value.Trim().ToUpperInvariant()
    if ($value -notmatch '^#[0-9A-F]{6}$') { return }
    if ($settings.Color -eq $value) { return }
    $settings.Color = $value
    $script:brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($value)
    $currentColor.Background = $script:brush
    $palettePreview.Background = $script:brush
    Render-Devices
    Save-Settings
}

function Convert-HsvColor([double]$h, [double]$s, [double]$v) {
    $h = ($h % 360) / 60
    $c = $v * $s
    $x = $c * (1 - [Math]::Abs(($h % 2) - 1))
    $m = $v - $c
    $rgb = switch ([int][Math]::Floor($h)) {
        0 { @($c,$x,0); break }
        1 { @($x,$c,0); break }
        2 { @(0,$c,$x); break }
        3 { @(0,$x,$c); break }
        4 { @($x,0,$c); break }
        default { @($c,0,$x) }
    }
    '#{0:X2}{1:X2}{2:X2}' -f [int][Math]::Round(($rgb[0]+$m)*255), [int][Math]::Round(($rgb[1]+$m)*255), [int][Math]::Round(($rgb[2]+$m)*255)
}
function Update-Palette([switch]$Apply) {
    $hueColor = Convert-HsvColor $script:hue 1 1
    $paletteSquare.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($hueColor)
    $cursorX = [Math]::Max(0.0, [Math]::Min($paletteSquare.Width - 14, $script:saturation * $paletteSquare.Width - 7))
    $cursorY = [Math]::Max(0.0, [Math]::Min($paletteSquare.Height - 14, (1 - $script:brightness) * $paletteSquare.Height - 7))
    $paletteCursor.Margin = "$cursorX,$cursorY,0,0"
    if ($Apply) { Set-TextColor (Convert-HsvColor $script:hue $script:saturation $script:brightness) }
}
function Sync-Palette {
    $color = ([System.Windows.Media.SolidColorBrush]$script:brush).Color
    $r = $color.R / 255; $g = $color.G / 255; $b = $color.B / 255
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $delta = $max - $min
    $script:brightness = $max
    $script:saturation = if ($max -eq 0) { 0 } else { $delta / $max }
    $script:hue = if ($delta -eq 0) { 0 } elseif ($max -eq $r) { (60 * (($g - $b) / $delta) + 360) % 360 } elseif ($max -eq $g) { 60 * (($b - $r) / $delta + 2) } else { 60 * (($r - $g) / $delta + 4) }
    Update-Palette
}
$currentColor.Background = $script:brush
$palettePreview.Background = $script:brush
Sync-Palette
$settingsWindow.FindName('OpenPalette').Add_Click({ $devicesPopup.IsOpen = $false; Sync-Palette; $colorPopup.IsOpen = -not $colorPopup.IsOpen })
$settingsWindow.FindName('PaletteDone').Add_Click({ $colorPopup.IsOpen = $false })
function Set-DeviceChoiceStyle($button) {
    $selected = $settings.HiddenDevices -notcontains [string]$button.Tag
    $button.Content = if ($selected) { "✓  $($button.Tag)" } else { "○  $($button.Tag)" }
    $button.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($selected) { '#176F61' } else { '#263949' }))
}
function Update-DeviceChoices {
    $deviceChoices.Children.Clear()
    if ($settings.KnownDevices.Count -eq 0) {
        $message = New-Object System.Windows.Controls.TextBlock
        $message.Text = Get-UiText 'NoKnownDevices'
        $message.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#90A6B8')
        [void]$deviceChoices.Children.Add($message)
        return
    }
    foreach ($name in ($settings.KnownDevices | Sort-Object -Unique)) {
        $button = New-Object System.Windows.Controls.Button
        $button.Tag = $name
        $button.Margin = '0,0,0,6'
        $button.ToolTip = $name
        Set-DeviceChoiceStyle $button
        $button.Add_Click({
            $name = [string]$this.Tag
            if ($settings.HiddenDevices -contains $name) { $settings.HiddenDevices = @($settings.HiddenDevices | Where-Object { $_ -ne $name }) }
            else { $settings.HiddenDevices += $name }
            Set-DeviceChoiceStyle $this
            Save-Settings
            Render-Devices
        })
        [void]$deviceChoices.Children.Add($button)
    }
}
Set-Language $settings.Language
$settingsWindow.FindName('ChooseDevices').Add_Click({ $colorPopup.IsOpen = $false; Update-DeviceChoices; $devicesPopup.IsOpen = -not $devicesPopup.IsOpen })
$settingsWindow.FindName('DevicesDone').Add_Click({ $devicesPopup.IsOpen = $false })
function Set-HueAt($point) {
    $script:hue = [Math]::Max(0.0, [Math]::Min(359.99, $point.X / $hueStrip.ActualWidth * 360))
    Update-Palette -Apply
}
function Set-PaletteAt($point) {
    $script:saturation = [Math]::Max(0.0, [Math]::Min(1.0, $point.X / $paletteSurface.ActualWidth))
    $script:brightness = [Math]::Max(0.0, [Math]::Min(1.0, 1 - $point.Y / $paletteSurface.ActualHeight))
    Update-Palette -Apply
}
$hueStrip.Add_MouseLeftButtonDown({ Set-HueAt ($_.GetPosition($hueStrip)) })
$hueStrip.Add_MouseMove({ if ($_.LeftButton -eq 'Pressed') { Set-HueAt ($_.GetPosition($hueStrip)) } })
$paletteSurface.Add_MouseLeftButtonDown({ Set-PaletteAt ($_.GetPosition($paletteSurface)) })
$paletteSurface.Add_MouseMove({ if ($_.LeftButton -eq 'Pressed') { Set-PaletteAt ($_.GetPosition($paletteSurface)) } })
$opacitySlider.Add_ValueChanged({
    $settings.Opacity = 1 - $opacitySlider.Value / 100
    $opacityValue.Text = "$([int]$opacitySlider.Value)%"
    Set-PanelOpacity
    Save-Settings
})
$sizeSlider.Add_ValueChanged({
    $window.Width = $sizeSlider.Value
    $settings.Width = $window.Width
    $sizeValue.Text = "$([int]$sizeSlider.Value) px"
    Render-Devices
    Save-Settings
})
$settingsWindow.FindName('CloseSettings').Add_Click({ $colorPopup.IsOpen = $false; $devicesPopup.IsOpen = $false; $settingsWindow.Hide() })
$settingsWindow.FindName('ExitApp').Add_Click({ $window.Close() })
$settingsPanel.Add_MouseLeftButtonDown({ if ($_.OriginalSource -eq $settingsPanel) { $settingsWindow.DragMove() } })
$settingsWindow.Add_Closing({ if (-not $script:closingApp) { $_.Cancel = $true; $settingsWindow.Hide() } })
function Show-Settings {
    if ($settingsWindow.IsVisible) { $colorPopup.IsOpen = $false; $devicesPopup.IsOpen = $false; $settingsWindow.Hide(); return }
    $area = [System.Windows.SystemParameters]::WorkArea
    $settingsWindow.Left = [Math]::Max($area.Left, [Math]::Min($area.Right - $settingsWindow.Width, $window.Left + $window.Width + 12))
    $settingsWindow.Top = [Math]::Max($area.Top, [Math]::Min($area.Bottom - $settingsWindow.Height, $window.Top))
    $settingsWindow.Show()
    [void]$settingsWindow.Activate()
}
$panel.Add_MouseRightButtonUp({ Show-Settings })

$panel.Add_MouseLeftButtonDown({
    if ($_.ButtonState -eq 'Pressed') {
        $window.DragMove()
        $settings.Left = $window.Left
        $settings.Top = $window.Top
        Save-Settings
    }
})
$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = if ($null -ne $settings.Left -and [double]$settings.Left -ge $area.Left -and [double]$settings.Left -le $area.Right - 40) { [double]$settings.Left } else { $area.Right - $window.Width - 20 }
$window.Top = if ($null -ne $settings.Top -and [double]$settings.Top -ge $area.Top -and [double]$settings.Top -le $area.Bottom - 40) { [double]$settings.Top } else { $area.Top + 20 }
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NativeIcon { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle); }'
$bitmap = New-Object System.Drawing.Bitmap(32, 32)
$drawing = [System.Drawing.Graphics]::FromImage($bitmap)
$drawing.SmoothingMode = 'AntiAlias'
$accent = [System.Drawing.Color]::FromArgb(50, 230, 184)
$pen = New-Object System.Drawing.Pen($accent, 4)
$fill = New-Object System.Drawing.SolidBrush($accent)
$drawing.DrawArc($pen, 5, 4, 22, 23, 180, 180)
$drawing.FillEllipse($fill, 3, 17, 8, 11)
$drawing.FillEllipse($fill, 21, 17, 8, 11)
$drawing.Dispose(); $pen.Dispose(); $fill.Dispose()
$iconHandle = $bitmap.GetHicon()
$trayIcon = [System.Drawing.Icon]::FromHandle($iconHandle).Clone()
[void][NativeIcon]::DestroyIcon($iconHandle)
$bitmap.Dispose()
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $trayIcon
$tray.Text = 'Bluetooth Battery Overlay'
$tray.Add_MouseClick({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $window.Dispatcher.Invoke([action]{ Show-Settings }) } })
$tray.Add_DoubleClick({
    if ($window.IsVisible) { $window.Hide() }
    else { $window.Show(); [void]$window.Activate() }
})
$tray.Visible = $true
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ Refresh-Devices })
$window.Add_Loaded({ Refresh-Devices; $timer.Start() })
$window.Add_Closed({ $script:closingApp = $true; $settingsWindow.Close(); $timer.Stop(); $tray.Visible = $false; $tray.Dispose(); $trayIcon.Dispose() })
$app = New-Object System.Windows.Application
try { [void]$app.Run($window) }
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
