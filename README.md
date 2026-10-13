# Bluetooth Battery Overlay

Небольшой оверлей для Windows 10/11: название подключённого Bluetooth-устройства, значок и процент заряда, если Windows предоставляет его. Оверлей можно перетаскивать, менять размер, прозрачность и цвет текста, а также выбирать отображаемые устройства. После запуска программа остаётся в области скрытых значков панели задач.

## Установка

1. Скачайте `BluetoothBatteryOverlay-Setup-1.0.0.exe` из [Releases](https://github.com/be0R1GINAL/bluetooth-battery-overlay/releases).
2. Запустите установщик. Права администратора не нужны.
3. В меню «Пуск» выберите **Bluetooth Battery Overlay**. В первый запуск откройте скрытые значки панели задач, если оверлей не виден.

Установщик добавляет программу в `%LOCALAPPDATA%\Programs\Bluetooth Battery Overlay` и создаёт ярлык в меню «Пуск». Удаление доступно через настройки приложений Windows. Пользовательские настройки находятся в `%APPDATA%\BluetoothBatteryOverlay\settings.json` и сохраняются после удаления программы.

## Управление

- Перетащите оверлей мышью, чтобы переместить.
- Щёлкните правой кнопкой для настроек: прозрачность, размер, цвет, список устройств.
- Дважды щёлкните значок в области уведомлений, чтобы скрыть или показать оверлей.
- В настройках выберите **RU** или **EN**. Выбор языка сохраняется.

Заряд показывается только для устройств, которые передают его в Windows. Программа читает данные Windows Bluetooth, включая доступный уровень гарнитур и стандартную BLE Battery Service. Если конкретное устройство не передаёт уровень заряда системе, оверлей не сможет его определить.

## Исходники и сборка

Приложение написано на Windows PowerShell 5.1 и WPF; файл `BluetoothBatteryOverlay.ps1` можно запустить напрямую через `Start Bluetooth Battery Overlay.cmd` без установки.

Установщик собирается [Inno Setup 6](https://jrsoftware.org/isdl.php):

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" .\BluetoothBatteryOverlay.iss
```

Для проверки обнаружения устройств:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\BluetoothBatteryOverlay.ps1 -SelfTest
```

## English

Bluetooth Battery Overlay shows connected Bluetooth devices with their names, icons, and battery percentages when Windows exposes the data. Drag the overlay to move it; right-click it for transparency, size, color, device visibility, and **RU / EN** language settings. The tray icon stays in the notification area. Double-click it to show or hide the overlay.

Download `BluetoothBatteryOverlay-Setup-1.0.0.exe` from [Releases](https://github.com/be0R1GINAL/bluetooth-battery-overlay/releases) and run it. No administrator rights are required. The installer adds a Start menu shortcut and an uninstaller. Device battery reporting depends on what Windows receives from each device.
