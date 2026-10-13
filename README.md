# Bluetooth Battery Overlay

Небольшой оверлей для Windows 10/11: название подключённого Bluetooth-устройства, значок и процент заряда, если Windows предоставляет его. Оверлей можно перетаскивать, менять размер, прозрачность и цвет текста, а также выбирать отображаемые устройства. После запуска программа остаётся в области скрытых значков панели задач.

## Запуск без установки

1. Скачайте `BluetoothBatteryOverlay-Portable-1.1.1.exe` из [Releases](https://github.com/be0R1GINAL/bluetooth-battery-overlay/releases).
2. Сохраните EXE в папку, доступную для записи, и запустите его двойным щелчком.

Установка и права администратора не нужны. Настройки хранятся в `settings.json` рядом с программой. Если запуск завершится ошибкой, появится сообщение, а подробности сохранятся в `BluetoothBatteryOverlay-error.log`. Подробнее: [PORTABLE.md](PORTABLE.md).

## Управление

- Перетащите оверлей мышью, чтобы переместить.
- Щёлкните правой кнопкой для настроек: прозрачность, размер, цвет, список устройств.
- Дважды щёлкните значок в области уведомлений, чтобы скрыть или показать оверлей.
- В настройках выберите **RU** или **EN**. Выбор языка сохраняется.

Заряд показывается только для устройств, которые передают его в Windows. Программа читает данные Windows Bluetooth, включая доступный уровень гарнитур и стандартную BLE Battery Service. Если конкретное устройство не передаёт уровень заряда системе, оверлей не сможет его определить.

Для каждого подключённого устройства программа проверяет четыре доступных пути: свойство Windows `System.Devices.BatteryLife`, свойство батареи Bluetooth PnP, Hands-Free Profile и BLE Battery Service. Допустимые показания сверяются, затем отображается одно из реально полученных значений. Записи одного физического устройства объединяются по Windows Container ID; одинаковые названия разных устройств не объединяются.

## Исходники и сборка

Приложение написано на Windows PowerShell 5.1 и WPF. `Build-Portable.ps1` собирает один EXE со встроенным скриптом; требуется штатный Windows PowerShell 5.1 и .NET Framework 4.x.

Для проверки обнаружения устройств:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\BluetoothBatteryOverlay.ps1 -SelfTest
```

## English

Bluetooth Battery Overlay shows connected Bluetooth devices with their names, icons, and battery percentages when Windows exposes the data. Drag the overlay to move it; right-click it for transparency, size, color, device visibility, and **RU / EN** language settings. The tray icon stays in the notification area. Double-click it to show or hide the overlay.

Download `BluetoothBatteryOverlay-Portable-1.1.1.exe` from [Releases](https://github.com/be0R1GINAL/bluetooth-battery-overlay/releases), save it in a writable folder, and double-click it. No installation or administrator rights are required. Settings stay in `settings.json` beside the app. Startup errors appear in a dialog and in `BluetoothBatteryOverlay-error.log`. Device battery reporting depends on what Windows receives from each device.

The app checks Windows device battery, Bluetooth PnP, Hands-Free Profile, and BLE Battery Service where available. It reconciles valid readings and shows one entry per Windows device container.
