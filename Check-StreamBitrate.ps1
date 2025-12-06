# Config
$inputFile    = "C:\Users\Vincent\OneDrive\Documents\GitHub\myTV\live.m3u"
$outputFile   = "C:\Users\Vincent\OneDrive\Documents\GitHub\myTV\stable-live.m3u"
$testSeconds  = 1
$minMbps      = 0.01
$gitRepoPath  = "C:\Users\Vincent\OneDrive\Documents\GitHub\myTV"
$gitBranch    = "main"  # change to your branch if needed
$gitExe = "C:\Program Files\Git\cmd\git.exe"

# Function to remove non-ASCII characters
function Remove-SpecialChars($text) {
    return ($text -replace '[^\x20-\x7E]', '')  # Keep only ASCII 32-126
}

# Write header without BOM
[System.IO.File]::WriteAllText($outputFile, "#EXTM3U`r`n", [System.Text.Encoding]::UTF8)

# Read input lines
$lines = Get-Content $inputFile

$currentBlock = @()
$kodipropBuffer = @()  # Temp storage for #KODIPROP lines

foreach ($line in $lines) {

    $trimLine = $line.Trim()

    if ($trimLine -eq "") { continue }  # Skip empty lines

    if ($trimLine.StartsWith("#EXTINF")) {
        # Flush previous block if it exists
        if ($currentBlock.Count -gt 0) {
															
            $currentBlock += $kodipropBuffer
            $kodipropBuffer = @()
        }

		# Clean special characters in #EXTINF line
        $cleanLine = Remove-SpecialChars $trimLine
        $currentBlock = @($cleanLine)
        continue
    }

	# Collect #KODIPROP lines in buffer
	if ($trimLine -match "KODIPROP") {
		$kodipropBuffer += $trimLine
		continue
	}

    # URL line
    if ($trimLine.ToLower().StartsWith("http")) {

        # Finalize block: append buffered KODIPROP before URL
        $currentBlock += $kodipropBuffer
        $kodipropBuffer = @()
        $currentBlock += $trimLine

        $url = $trimLine
        Write-Host "`nTesting: $url"

        # Remove old temp file
        $tempFile = "temp_stream.bin"
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }

        # Start curl download
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.FileName = "curl.exe"
        $process.StartInfo.Arguments = "-L `"$url`" --silent --output $tempFile"
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.UseShellExecute = $false
        $process.Start() | Out-Null

        # Wait N seconds
        Start-Sleep -Seconds $testSeconds

        # Kill curl if still running
        if (!$process.HasExited) { $process.Kill() }

        # File size
        $sizeBytes = 0
        if (Test-Path $tempFile) {
            $sizeBytes = (Get-Item $tempFile).Length
        }

        # Convert to Mbps
        $mbps = [math]::Round((($sizeBytes * 8) / 1000000), 2)
        Write-Host "Bitrate: $mbps Mbps"

        if ($mbps -ge $minMbps) {
            Write-Host " => STABLE, writing block to output"

            # Append block to M3U
            foreach ($bLine in $currentBlock) {
                [System.IO.File]::AppendAllText($outputFile, $bLine + "`r`n", [System.Text.Encoding]::UTF8)
            }

            # Optional blank line
            [System.IO.File]::AppendAllText($outputFile, "`r`n", [System.Text.Encoding]::UTF8)

        }
        else {
            Write-Host " => UNSTABLE, skipping"
        }

        # Reset block after processing
        $currentBlock = @()
        continue
    }

	# -------------------------------
	# Auto commit this iteration to GitHub
	# -------------------------------
	try {
		Set-Location $gitRepoPath

		$outputName = Split-Path $outputFile -Leaf
		Write-Host "Preparing Git commit for: $outputName"

		# Stage file
		& $gitExe add $outputName

		# Check if any changes exist
		$status = & $gitExe status --porcelain

		if ([string]::IsNullOrWhiteSpace($status)) {
			Write-Host "No changes detected. Skipping Git commit."
		}
		else {
			$commitMessage = "Updated stable stream list for $url at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
			Write-Host "Changes detected. Committing with message: $commitMessage"

			& $gitExe commit -m "$commitMessage"

			Write-Host "Commit created. Attempting to push to branch '$gitBranch'."
			& $gitExe push origin $gitBranch

			Write-Host "Git push completed successfully."
		}
	}
	catch {
		Write-Host "Git encountered an error:"
		Write-Host $_.Exception.Message
	}
}

Write-Host "`nDONE. Channels saved to $outputFile"
