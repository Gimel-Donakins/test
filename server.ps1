# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:8080/")

# Create images directory with absolute path - using multiple fallback options
$scriptPath = $null
if ($PSScriptRoot) {
    $scriptPath = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $scriptPath = (Get-Location).Path
}

$imageDir = Join-Path -Path $scriptPath -ChildPath "images"
Write-Host "Images will be saved to: $imageDir"

# Ensure images directory exists
if (-not (Test-Path -Path $imageDir)) {
    New-Item -ItemType Directory -Force -Path $imageDir | Out-Null
}

Write-Host "Server listening on port 8080..."

$listener.Start()

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        switch ($request.HttpMethod + " " + $request.Url.LocalPath) {
            "GET /" {
                # Serve viewer.html
                $viewerPath = Join-Path $scriptPath "viewer.html"
                if (Test-Path $viewerPath) {
                    $content = Get-Content $viewerPath -Raw
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.ContentType = "text/html"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                else {
                    $response.StatusCode = 404
                }
            }
            
            "GET /images" {
                # Return list of images
                $files = Get-ChildItem -Path $imageDir -Filter "*.jpg" | Select-Object -ExpandProperty Name
                $json = $files | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            
            {$_ -match "GET /images/.*"} {
                # Serve image files
                $imageName = $request.Url.LocalPath -replace '^/images/'
                $imagePath = Join-Path $imageDir $imageName
                if (Test-Path $imagePath) {
                    $imageBytes = [System.IO.File]::ReadAllBytes($imagePath)
                    $response.ContentType = "image/jpeg"
                    $response.ContentLength64 = $imageBytes.Length
                    $response.OutputStream.Write($imageBytes, 0, $imageBytes.Length)
                }
                else {
                    $response.StatusCode = 404
                }
            }
            
            "POST /upload" {
                # Ensure directory still exists
                if (-not (Test-Path $imageDir)) {
                    New-Item -ItemType Directory -Force -Path $imageDir | Out-Null
                }

                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $filename = Join-Path $imageDir "screenshot-$timestamp.jpg"
                
                # Read the entire request body
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $content = $reader.ReadToEnd()
                
                # Extract base64 content from multipart form data
                $base64Data = $content -replace '(?ms).*Content-Type: image/jpeg\r\n\r\n(.*?)\r\n--.*', '$1'
                
                try {
                    $imageBytes = [Convert]::FromBase64String($base64Data)
                    [System.IO.File]::WriteAllBytes($filename, $imageBytes)
                    Write-Host "Saved screenshot to: $filename"
                    $response.StatusCode = 200
                }
                catch {
                    Write-Error "Failed to process image data: $_"
                    $response.StatusCode = 400
                }
            }

            "GET /client.ps1" {
                # Serve capture-client.ps1
                $clientPath = Join-Path $scriptPath "capture-client.ps1"
                if (Test-Path $clientPath) {
                    $content = Get-Content $clientPath -Raw
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.ContentType = "text/plain"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                else {
                    $response.StatusCode = 404
                }
            }
            
            default {
                $response.StatusCode = 404
            }
        }
        
        $response.Close()
    }
    catch {
        Write-Error "Request processing error: $_"
    }
}

$listener.Stop()
