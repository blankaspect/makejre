#===============================================================================
#
# Generates a Java runtime environment that may include JavaFX modules
# Requires PowerShell 7 or later
#
# Parameters:
#
#   output-kind
#     The kind of archive that will be generated: one of { tar.gz, zip }.
#
#   output-directory
#     The location of the directory to which the JRE will be written.  The
#     pathname must include a parent directory.
#       Two JRE archives will be created from the output directory in the parent
#     directory of the output directory.  If <output-directory-name> is the name
#     of the output directory, the filenames of the two archives will be:
#         <output-directory-name>-windows.<output-kind>
#         <output-directory-name>-windows-src.<output-kind>
#     The output directory will be deleted after the two JRE archives are
#     successfully created.
#
#   jdk-archive
#     The location of the .zip archive of the JDK that will provide modules, the
#     linker and the source archive.
#
#   javafx-jmods-archive | 'null'
#     The location of the .zip archive of the JavaFX JMOD files.  If this
#     argument has the value 'null', it will be ignored.
#
#   module-list-file
#     The location of the text file in which each non-empty line is the name of
#     a module that will be included in the JRE.
#
#   copy-list-file (optional)
#     The location of the text file in which each line specifies a file that
#     will be copied to a directory in the JRE.  A line must have the form:
#         <source-file>;<destination-directory>
#     The destination directory must be relative to the output directory (see
#     above).  Any whitespace before or after the ';' separator will be ignored.
#
#===============================================================================

# Function: create a pathname from its components
function _path([string[]]$components)
{
    return [string]::Join([IO.Path]::DirectorySeparatorChar, $components)
}

#-------------------------------------------------------------------------------

# Output kind
if ([string]::IsNullOrEmpty($args[0]))
{
    Write-Host "ERROR: no output kind was specified." -ForegroundColor Yellow
    exit 1
}
if ("tar.gz", "zip" -cnotcontains $args[0])
{
    Write-Host "ERROR: the output kind must be one of { tar.gz, zip }." -ForegroundColor Yellow
    exit 1
}
[string]$outKind = $args[0]

# Output directory
if ([string]::IsNullOrEmpty($args[1]))
{
    Write-Host "ERROR: no output directory was specified." -ForegroundColor Yellow
    exit 1
}
[string]$outDir = $args[1]

# Parent of output directory
$outParentDir = Split-Path -Path $outDir -Parent
if ([string]::IsNullOrEmpty($outParentDir))
{
    Write-Host "ERROR: the pathname of the output directory must include a parent." -ForegroundColor Yellow
    exit 1
}

# Name of output directory
$outDirName = Split-Path -Path $outDir -Leaf

# JDK archive
if ([string]::IsNullOrEmpty($args[2]))
{
    Write-Host "ERROR: no JDK archive was specified." -ForegroundColor Yellow
    exit 1
}
[string]$jdkArchive = $args[2]
if (-not (Test-Path -Path $jdkArchive -PathType Leaf))
{
    Write-Host "ERROR: no JDK archive was found at $jdkArchive" -ForegroundColor Yellow
    exit 1
}

# JavaFX JMODs archive
if ([string]::IsNullOrEmpty($args[3]))
{
    Write-Host "ERROR: no JavaFX JMODs archive was specified." -ForegroundColor Yellow
    exit 1
}
if ($args[3] -cne "null")
{
    [string]$jfxJmodsArchive = $args[3]
    if (-not (Test-Path -Path $jfxJmodsArchive -PathType Leaf))
    {
        Write-Host "ERROR: no JavaFX JMODs archive was found at $jfxJmodsArchive" -ForegroundColor Yellow
        exit 1
    }
}

# Module-list file
if ([string]::IsNullOrEmpty($args[4]))
{
    Write-Host "ERROR: no module-list file was specified." -ForegroundColor Yellow
    exit 1
}
[string]$moduleList = $args[4]
if (-not (Test-Path -Path $moduleList -PathType Leaf))
{
    Write-Host "ERROR: no module-list file was found at $moduleList" -ForegroundColor Yellow
    exit 1
}

# Copy-list file
if (-not ([string]::IsNullOrEmpty($args[5])))
{
    $copyList = $args[5]
    if (-not (Test-Path -Path $copyList -PathType Leaf))
    {
        Write-Host "ERROR: no copy-list file was found at $copyList" -ForegroundColor Yellow
        exit 1
    }
}

# Create comma-separated list of modules from lines of module-list file
$modules = ""
Write-Host "Reading module list: $moduleList"
foreach ($line in Get-Content -Path $moduleList)
{
    if (-not ([string]::IsNullOrWhiteSpace($line)))
    {
        if ($modules -ne "")
        {
            $modules += ","
        }
        $modules += $line
    }
}

# Create first temporary directory
$temp1Dir = _path($outParentDir, '$temp-jdk$')
if (Test-Path -Path $temp1Dir -PathType Container)
{
    Remove-Item -Recurse -Force $temp1Dir
}
Write-Host "Creating temporary directory: $temp1Dir"
New-Item -Path $temp1Dir -ItemType "directory" > $null

# Extract JDK
Write-Host "Extracting JDK from $jdkArchive to $temp1Dir"
Expand-Archive -Path $jdkArchive -Destination $temp1Dir

# JDK directory
$jdkDir = _path($temp1Dir, (Get-ChildItem -Path $temp1Dir -Directory -Name | Select-Object -First 1))

# Module path
$modulePath = _path($jdkDir, "jmods")

# Extract JavaFX JMODs
if (-not ([string]::IsNullOrEmpty($jfxJmodsArchive)))
{
    # Create second temporary directory
    $temp2Dir = _path($outParentDir, '$temp-jfx$')
    if (Test-Path -Path $temp2Dir -PathType Container)
    {
        Remove-Item -Recurse -Force $temp2Dir
    }
    Write-Host "Creating temporary directory: $temp2Dir"
    New-Item -Path $temp2Dir -ItemType "directory" > $null

    # Extract JavaFX JMODs
    Write-Host "Extracting JavaFX JMODs from $jfxJmodsArchive to $temp2Dir"
    Expand-Archive -Path $jfxJmodsArchive -Destination $temp2Dir

    # JavaFX JMODs directory
    $jfxJmodsDir = _path($temp2Dir, (Get-ChildItem -Path $temp2Dir -Directory -Name | Select-Object -First 1))

    # Append to module path
    $modulePath += ";$jfxJmodsDir"
}

# Location of jlink tool
$linker = _path($jdkDir, "bin", "jlink.exe")

# Delete output directory
if (Test-Path -Path $outDir -PathType Container)
{
    Remove-Item -Recurse -Force $outDir
}

# Generate JRE
Write-Host "Writing JRE to $outDir"
$command = "$linker"
$argList = `
    "--output ""$outDir""",
    "--module-path ""$modulePath""",
    "--add-modules $modules"
$process = Start-Process $command -ArgumentList $argList -PassThru -NoNewWindow -Wait
if ($process.ExitCode -ne 0)
{
    exit 1
}

# Copy files to JRE
if (-not ([string]::IsNullOrEmpty($copyList)))
{
    foreach ($line in Get-Content -Path $copyList)
    {
        $strs = $line.Split(";", 2, [StringSplitOptions].None)
        if ($strs.Length -lt 2)
        {
            Write-Host "ERROR: malformed line in copy list: $line" -ForegroundColor Yellow
            exit 1
        }
        $source = $strs[0].Trim()
        $dest = _path($outDir, $strs[1].Trim())
        Write-Host "Copying $source to $dest"
        Copy-Item -Path $source -Destination $dest
    }
}

# Delete archive, no source
$archiveName = "$outDirName-windows.$outKind"
$archive = _path($outParentDir, $archiveName)
if (Test-Path -Path $archive -PathType Leaf)
{
    Remove-Item -Force $archive
}

# Create archive, no source
Write-Host "Creating JRE archive: $archive"
if ($outKind -ceq "tar.gz")
{
    tar -c -C "$outParentDir" -f "$archive" -z "$outDirName"
}
else
{
    Compress-Archive -Path "$outDir" -DestinationPath "$archive" -CompressionLevel Optimal
}

# Copy source archive to JRE
Copy-Item -Path (_path($jdkDir, "lib", "src.zip")) -Destination (_path($outDir, "lib"))

# Delete archive, source
$archiveName = "$outDirName-windows-src.$outKind"
$archive = _path($outParentDir, $archiveName)
if (Test-Path -Path $archive -PathType Leaf)
{
    Remove-Item -Force $archive
}

# Create archive, source
Write-Host "Creating JRE archive: $archive"
if ($outKind -ceq "tar.gz")
{
    tar -c -C "$outParentDir" -f "$archive" -z "$outDirName"
}
else
{
    Compress-Archive -Path "$outDir" -DestinationPath "$archive" -CompressionLevel Optimal
}

# Delete temporary directories and output directory
Write-Host "Deleting temporary directory: $temp1Dir"
Remove-Item -Recurse -Force $temp1Dir
if ($temp2Dir -and (Test-Path -Path $temp2Dir -PathType Container))
{
    Write-Host "Deleting temporary directory: $temp2Dir"
    Remove-Item -Recurse -Force $temp2Dir
}
Write-Host "Deleting output directory: $outDir"
Remove-Item -Recurse -Force $outDir

#-------------------------------------------------------------------------------
