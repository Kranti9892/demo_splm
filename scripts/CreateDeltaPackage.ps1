$repositoryPath = "C:\my_repo\REPOS\demo_splm"
$branchName = "development"
$outputZipPath = "C:\Releasepackage\$branchName.zip"



try {
    # Navigate to the repository
    Set-Location -Path $repositoryPath
    Write-Output "Navigated to repository: $repositoryPath"

    # Checkout the current branch
    Write-Output "Checking out branch '$branchName'..."
    git checkout $branchName

    # Ensure the branch is up to date
    Write-Output "Updating branch '$branchName'..."
    git fetch
    git pull

    # Get the latest tag reachable from the current branch
    Write-Output "Retrieving the latest tag in branch '$branchName'..."
    $tagName = git tag --merged $branchName --sort=-creatordate | Select-Object -First 1
    Write-Output "Latest tag in branch '$branchName': $tagName"

    if (-not $tagName) {
        throw "No tags found on this branch."
    }

    # List commits on top of the tag and changed files
    Write-Output "Listing changed files since tag '$tagName'..."
    $changedFiles = git diff --name-only $tagName $branchName | Out-String
    $fileArray = $changedFiles -split "`r?`n" | Where-Object { $_ -ne "" }

    $importFiles = @()  # Array to store the paths of import.mf files

    if ($fileArray) {
        Write-Output "Files modified since tag '$tagName':"
        foreach ($file in $fileArray) {
            Write-Output "  $file"

            # Get the parent directory of the modified file
            $parentDir = Split-Path -Path $file -Parent

            # Traverse up to find the nearest import.mf
            while ($parentDir -and (Test-Path "$repositoryPath\$parentDir")) {
                $importFilePath = Join-Path -Path $parentDir -ChildPath "imports.mf"
                if (Test-Path "$repositoryPath\$importFilePath") {
                    Write-Output "Found import.mf in: $parentDir"
                    $importFiles += $importFilePath
                    break
                }
                $parentDir = Split-Path -Path $parentDir -Parent
            }
        }

        # Combine modified files and found import.mf files
        $allFilesToArchive = ($fileArray + $importFiles) | Select-Object -Unique

        # Create a temporary directory
        $tempDir = Join-Path $env:TEMP "git_repo_modified_files"
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        Write-Output "Created temporary directory: $tempDir"

        # Copy all selected files to the temp folder, preserving structure
        foreach ($file in $allFilesToArchive) {
            $sourcePath = Join-Path $repositoryPath $file
            $destPath = Join-Path $tempDir $file

            $destDir = Split-Path $destPath -Parent
            if (!(Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            } else {
                Write-Warning "File not found in repo: $sourcePath"
            }
        }

        # Create ZIP
        if (Test-Path $outputZipPath) { Remove-Item $outputZipPath -Force }
        Compress-Archive -Path "$tempDir\*" -DestinationPath $outputZipPath
        Write-Output "Packaged files into: $outputZipPath"
    } else {
        Write-Output "No files modified since tag '$tagName'."
    }

} catch {
    Write-Error "Error: $_"
} finally {
    git checkout $branchName
    Write-Output "Returned to branch '$branchName'."

    # Optional: Cleanup temp folder
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
        Write-Output "Cleaned up temporary folder: $tempDir"
    }
}
