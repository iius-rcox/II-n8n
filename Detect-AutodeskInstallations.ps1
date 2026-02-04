<#
.SYNOPSIS
    Detects Autodesk software installations for compliance auditing.
    
.DESCRIPTION
    Scans for Autodesk product installations, specifically:
    - AutoCAD (all versions, flagging 2017)
    - Navisworks Simulate (all versions, flagging 2016)
    - Serial number 666-69696969
    
    Hardened for RMM deployment:
    - No Win32_Product (avoids MSI self-repair storms)
    - Loads actual user registry hives when running as SYSTEM
    - Explicit error collection (no silent failures)
    - Retry logic for Azure upload
    
.NOTES
    Author: I&I IT Department
    Date: February 4, 2026
    Version: 2.0 (Hardened)
    Purpose: Autodesk License Compliance Audit
#>

#Requires -Version 5.1

# Don't hide errors globally - we'll handle them explicitly
$ErrorActionPreference = "Continue"
$OutputEncoding = [System.Text.Encoding]::UTF8

#region Azure Blob Configuration
$BlobBaseUrl = "https://aboraboranditscans.blob.core.windows.net/autodesk-compliance-scans"
$SasToken = "se=2026-02-15T23%3A59%3A59Z&sp=cw&sv=2022-11-02&sr=c&sig=vXyMs2Y0n76Podr2ib0UEuHVCZ8EqSRgOIOgiUjXfSY%3D"
$LocalFallbackPath = "$env:ProgramData\AutodeskComplianceScans"  # More persistent than TEMP
$MaxUploadRetries = 3
#endregion

# Initialize results object
$Results = [PSCustomObject]@{
    ComputerName     = $env:COMPUTERNAME
    ScanDate         = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    ScanDateUTC      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Domain           = $env:USERDOMAIN
    RunningAs        = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    IsSystem         = ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)
    AllUsers         = @()
    UsersScanned     = 0
    UsersFailed      = 0
    ScanComplete     = $false
    AutodeskFound    = $false
    Products         = @()
    FlaggedProducts  = @()
    RegistrySerials  = @()
    AlertLevel       = "None"
    Summary          = ""
    UploadStatus     = "Pending"
    Errors           = @()
    Warnings         = @()
}

# Products of interest
$TargetProducts = @(
    @{ Name = "AutoCAD"; Version = "2017"; Priority = "High" }
    @{ Name = "Navisworks Simulate"; Version = "2016"; Priority = "High" }
    @{ Name = "Navisworks"; Version = "*"; Priority = "Medium" }
    @{ Name = "AutoCAD"; Version = "*"; Priority = "Medium" }
)

$FlaggedSerial = "666-69696969"
$FlaggedSerialDigits = ($FlaggedSerial -replace '\D', '')
$PlaceholderSerialDigits = @(
    "00000000000"
)

# Track which user hives we loaded (so we can unload them)
$Script:LoadedHives = @()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Autodesk Compliance Detection Script v2" -ForegroundColor Cyan
Write-Host "Scan Started: $($Results.ScanDate)" -ForegroundColor Cyan
Write-Host "Computer: $($Results.ComputerName)" -ForegroundColor Cyan
Write-Host "Running As: $($Results.RunningAs)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#region Functions

function Add-ScanError {
    param([string]$Context, [string]$Message)
    $Script:Results.Errors += [PSCustomObject]@{
        Timestamp = (Get-Date -Format "HH:mm:ss")
        Context   = $Context
        Message   = $Message
    }
    Write-Host "    [ERROR] $Context : $Message" -ForegroundColor Red
}

function Add-ScanWarning {
    param([string]$Context, [string]$Message)
    $Script:Results.Warnings += [PSCustomObject]@{
        Timestamp = (Get-Date -Format "HH:mm:ss")
        Context   = $Context
        Message   = $Message
    }
    Write-Host "    [WARN] $Context : $Message" -ForegroundColor Yellow
}

function Get-AllLocalUsers {
    <#
    .SYNOPSIS
        Gets all users who have logged into this machine
    #>
    
    $Users = @()
    
    try {
        $ProfileList = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" -ErrorAction Stop
        
        foreach ($Profile in $ProfileList) {
            if ($Profile.ProfileImagePath -and $Profile.ProfileImagePath -notmatch "systemprofile|LocalService|NetworkService") {
                $SID = Split-Path $Profile.PSPath -Leaf
                $Username = "Unknown"
                
                try {
                    $UserObj = New-Object System.Security.Principal.SecurityIdentifier($SID)
                    $Username = $UserObj.Translate([System.Security.Principal.NTAccount]).Value
                }
                catch {
                    $Username = Split-Path $Profile.ProfileImagePath -Leaf
                }
                
                # Skip system/default accounts
                if ($Username -match "^(Default|Public|All Users)$") {
                    continue
                }
                
                # FILTER: Only include INSULATIONSINC domain users
                if ($Username -notmatch "^INSULATIONSINC\\") {
                    Write-Host "    Skipping non-domain user: $Username" -ForegroundColor DarkGray
                    continue
                }
                
                $LastUse = "Unknown"
                if ($Profile.LocalProfileLoadTimeHigh -and $Profile.LocalProfileLoadTimeLow) {
                    try {
                        $ft = ([Int64]$Profile.LocalProfileLoadTimeHigh -shl 32) -bor [UInt32]$Profile.LocalProfileLoadTimeLow
                        $LastUse = [DateTime]::FromFileTime($ft).ToString("yyyy-MM-dd HH:mm:ss")
                    } catch { }
                }
                
                $Users += [PSCustomObject]@{
                    Username    = $Username
                    SID         = $SID
                    ProfilePath = $Profile.ProfileImagePath
                    LastUseTime = $LastUse
                    NTUserPath  = Join-Path $Profile.ProfileImagePath "NTUSER.DAT"
                }
            }
        }
    }
    catch {
        Add-ScanError -Context "Get-AllLocalUsers" -Message $_.Exception.Message
    }
    
    return $Users
}

function Mount-UserHive {
    <#
    .SYNOPSIS
        Loads a user's NTUSER.DAT into HKU for scanning
    #>
    param(
        [string]$SID,
        [string]$NTUserPath
    )
    
    # Check if already loaded (user is logged in)
    if (Test-Path "Registry::HKU\$SID") {
        return @{ Success = $true; AlreadyLoaded = $true }
    }
    
    if (-not (Test-Path $NTUserPath)) {
        return @{ Success = $false; Message = "NTUSER.DAT not found" }
    }
    
    try {
        $Result = & reg.exe load "HKU\$SID" $NTUserPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            $Script:LoadedHives += $SID
            return @{ Success = $true; AlreadyLoaded = $false }
        }
        else {
            return @{ Success = $false; Message = "reg load failed: $Result" }
        }
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Dismount-UserHive {
    param([string]$SID)
    
    try {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        $null = & reg.exe unload "HKU\$SID" 2>&1
    }
    catch { }
}

function Get-InstalledAutodeskFromRegistry {
    <#
    .SYNOPSIS
        Searches registry for installed Autodesk products (HKLM + all user hives)
    #>
    
    $AutodeskProducts = @()
    
    # HKLM paths (machine-wide installs)
    $HKLMPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($Path in $HKLMPaths) {
        try {
            $Items = Get-ItemProperty -Path $Path -ErrorAction Stop
            foreach ($Item in $Items) {
                if ($Item.DisplayName -match "Autodesk|AutoCAD|Navisworks|Revit|3ds Max|Maya|Inventor|Civil 3D|Fusion") {
                    $AutodeskProducts += [PSCustomObject]@{
                        Name            = $Item.DisplayName
                        Version         = $Item.DisplayVersion
                        Publisher       = $Item.Publisher
                        InstallDate     = $Item.InstallDate
                        InstallLocation = $Item.InstallLocation
                        UninstallString = $Item.UninstallString
                        Source          = "Registry-HKLM"
                        UserContext     = "Machine"
                    }
                }
            }
        }
        catch {
            Add-ScanError -Context "Registry-HKLM" -Message "Failed to read $Path : $($_.Exception.Message)"
        }
    }
    
    # Scan each user's hive
    foreach ($User in @($Script:Results.AllUsers)) {
        $HiveMount = Mount-UserHive -SID $User.SID -NTUserPath $User.NTUserPath
        
        if ($HiveMount.Success) {
            $Script:Results.UsersScanned++
            $UserPath = "Registry::HKU\$($User.SID)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            
            try {
                $Items = Get-ItemProperty -Path $UserPath -ErrorAction SilentlyContinue
                foreach ($Item in $Items) {
                    if ($Item.DisplayName -match "Autodesk|AutoCAD|Navisworks|Revit|3ds Max|Maya|Inventor|Civil 3D|Fusion") {
                        $AutodeskProducts += [PSCustomObject]@{
                            Name            = $Item.DisplayName
                            Version         = $Item.DisplayVersion
                            Publisher       = $Item.Publisher
                            InstallDate     = $Item.InstallDate
                            InstallLocation = $Item.InstallLocation
                            UninstallString = $Item.UninstallString
                            Source          = "Registry-HKU"
                            UserContext     = $User.Username
                        }
                    }
                }
            }
            catch {
                Add-ScanWarning -Context "Registry-HKU" -Message "Failed to read hive for $($User.Username)"
            }
        }
        else {
            if ($HiveMount.AlreadyLoaded) {
                # User is logged in, hive accessible - counts as scanned
                $Script:Results.UsersScanned++
            }
            else {
                $Script:Results.UsersFailed++
                Add-ScanWarning -Context "Mount-UserHive" -Message "$($User.Username): $($HiveMount.Message)"
            }
        }
    }
    
    return $AutodeskProducts
}

function Get-AutodeskSerialNumbers {
    <#
    .SYNOPSIS
        Searches for Autodesk serial numbers in registry and license files
    #>
    $Serials = New-Object System.Collections.Generic.List[object]
    $SerialIndex = @{}
    $SerialPattern = '\b\d{3}-\d{8}\b|\b\d{11}\b'
    $SerialPropertyPattern = 'SerialNumber|Serial|ProductKey|ProductCode|SN|CDKey'

    function Normalize-SerialValue {
        param([string]$Value)
        if (-not $Value) { return $Value }
        $digits = ($Value -replace '\D', '')
        if ($digits.Length -eq 11) {
            return ($digits.Substring(0,3) + '-' + $digits.Substring(3))
        }
        return $Value
    }

    function Add-Serial {
        param(
            [string]$Path,
            [string]$Property,
            [string]$Value,
            [string]$Context,
            [bool]$ForceFlagged = $false
        )
        if (-not $Value) { return }
        $Normalized = Normalize-SerialValue $Value
        $digits = ($Normalized -replace '\D', '')
        if ($digits.Length -ne 11) { return }
        $Key = "$Context|$Path|$Property|$Normalized"
        if ($SerialIndex.ContainsKey($Key)) { return }
        $SerialIndex[$Key] = $true
        $IsFlagged = $ForceFlagged -or ($Normalized -eq $FlaggedSerial)
        $IsPlaceholder = ($digits -match '^(\d)\1{10}$') -or ($PlaceholderSerialDigits -contains $digits)
        $Serials.Add([PSCustomObject]@{
            Path     = $Path
            Property = $Property
            Value    = $Normalized
            Flagged  = $IsFlagged
            Placeholder = $IsPlaceholder
            Context  = $Context
        })
    }

    function Scan-RegistryPath {
        param(
            [string]$BasePath,
            [string]$Context
        )
        if (-not (Test-Path $BasePath)) { return }
        try {
            Get-ChildItem -Path $BasePath -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $Properties = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    foreach ($Prop in $Properties.PSObject.Properties) {
                        if ($Prop.Value -isnot [string]) { continue }
                        $Name = $Prop.Name
                        $Val = [string]$Prop.Value
                        if ($Name -match $SerialPropertyPattern -or $Val -match $SerialPattern) {
                            $Matches = [regex]::Matches($Val, $SerialPattern)
                            if ($Matches.Count -gt 0) {
                                foreach ($Match in $Matches) {
                                    Add-Serial -Path $_.PSPath -Property $Name -Value $Match.Value -Context $Context
                                }
                            }
                            else {
                                Add-Serial -Path $_.PSPath -Property $Name -Value $Val -Context $Context
                            }
                        }
                    }
                }
                catch { }
            }
        }
        catch {
            Add-ScanWarning -Context "SerialScan-Registry" -Message "Failed to scan $BasePath"
        }
    }

    # Machine-level registry paths
    $LicenseRegPaths = @(
        "HKLM:\SOFTWARE\Autodesk",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk",
        "HKLM:\SOFTWARE\Autodesk\Licensing",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\Licensing",
        "HKLM:\SOFTWARE\Autodesk\CLM",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\CLM",
        "HKLM:\SOFTWARE\Autodesk\AdskLicensingService",
        "HKLM:\SOFTWARE\WOW6432Node\Autodesk\AdskLicensingService",
        "HKLM:\SOFTWARE\FLEXlm License Manager",
        "HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager"
    )

    foreach ($BasePath in $LicenseRegPaths) {
        Scan-RegistryPath -BasePath $BasePath -Context "Machine"
    }

    # Scan each user's registry (Autodesk + FLEXlm)
    foreach ($User in @($Script:Results.AllUsers)) {
        $UserRegPaths = @(
            "Registry::HKU\$($User.SID)\SOFTWARE\Autodesk",
            "Registry::HKU\$($User.SID)\SOFTWARE\FLEXlm License Manager"
        )
        foreach ($BasePath in $UserRegPaths) {
            Scan-RegistryPath -BasePath $BasePath -Context $User.Username
        }
    }

    # License files (targeted search, not recursive everything)
    $LicenseFilePaths = @(
        "$env:ProgramData\Autodesk\AdskLicensingService",
        "$env:ProgramData\Autodesk\AdskLicensingService\Licenses",
        "$env:ProgramData\Autodesk\AdskLicensingService\LicenseStorage",
        "$env:ProgramData\Autodesk\CLM\LGS",
        "$env:ProgramData\FLEXlm",
        "$env:ProgramData\Autodesk\Network License Manager",
        "$env:ProgramFiles\Autodesk\Network License Manager",
        "${env:ProgramFiles(x86)}\Autodesk\Network License Manager"
    )

    foreach ($LicPath in $LicenseFilePaths) {
        if (Test-Path $LicPath) {
            try {
                Get-ChildItem -Path $LicPath -Recurse -Include "*.lic", "*.dat", "*.data" -ErrorAction SilentlyContinue |
                Select-Object -First 200 |
                ForEach-Object {
                    try {
                        $Content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                        if (-not $Content) { return }
                        $Matches = [regex]::Matches($Content, $SerialPattern)
                        if ($Matches.Count -gt 0) {
                            foreach ($Match in $Matches) {
                                $IsFlagged = ($Match.Value -replace '\D', '') -eq $FlaggedSerialDigits
                                Add-Serial -Path $_.FullName -Property "FileContent" -Value $Match.Value -Context "LicenseFile" -ForceFlagged:$IsFlagged
                            }
                        }
                        elseif ($Content -match $FlaggedSerialDigits) {
                            Add-Serial -Path $_.FullName -Property "FileContent" -Value $FlaggedSerialDigits -Context "LicenseFile" -ForceFlagged:$true
                        }
                    }
                    catch { }
                }
            }
            catch {
                Add-ScanWarning -Context "SerialScan-Files" -Message "Failed to scan $LicPath"
            }
        }
    }

    return $Serials.ToArray()
}

function Get-AutodeskFromFileSystem {
    <#
    .SYNOPSIS
        Searches file system for Autodesk executables (limited depth)
    #>
    
    $FileSystemProducts = @()
    
    $SearchPaths = @(
        "$env:ProgramFiles\Autodesk",
        "${env:ProgramFiles(x86)}\Autodesk"
    )
    
    $TargetExecutables = @(
        @{ Exe = "acad.exe"; Product = "AutoCAD" }
        @{ Exe = "roamer.exe"; Product = "Navisworks" }
    )
    
    foreach ($BasePath in $SearchPaths) {
        if (Test-Path $BasePath) {
            foreach ($Target in $TargetExecutables) {
                try {
                    # Limit depth to 4 levels to prevent slow scans
                    Get-ChildItem -Path $BasePath -Filter $Target.Exe -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $FileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($_.FullName)
                            $FileSystemProducts += [PSCustomObject]@{
                                Name            = if ($FileVersion.ProductName) { $FileVersion.ProductName } else { $Target.Product }
                                Version         = $FileVersion.ProductVersion
                                FileVersion     = $FileVersion.FileVersion
                                InstallLocation = $_.DirectoryName
                                ExecutablePath  = $_.FullName
                                Source          = "FileSystem"
                                UserContext     = "Machine"
                            }
                        }
                        catch {
                            Add-ScanWarning -Context "FileSystem" -Message "Could not read version from $($_.FullName)"
                        }
                    }
                }
                catch {
                    Add-ScanWarning -Context "FileSystem" -Message "Access denied or error scanning $BasePath for $($Target.Exe)"
                }
            }
        }
    }
    
    return $FileSystemProducts
}

function Test-ProductMatch {
    param([PSCustomObject]$Product)
    
    foreach ($Target in $TargetProducts) {
        $NameMatch = $Product.Name -match [regex]::Escape($Target.Name)
        
        # More precise version matching
        $VersionMatch = $false
        if ($Target.Version -eq "*") {
            $VersionMatch = $false  # Wildcard doesn't count as exact
        }
        elseif ($Product.Version) {
            # Match year at word boundary: "2017" but not "20170" or "12017"
            $VersionMatch = $Product.Version -match "\b$([regex]::Escape($Target.Version))\b"
        }
        # Also check if year is in product name
        if (-not $VersionMatch -and $Product.Name -match "\b$([regex]::Escape($Target.Version))\b") {
            $VersionMatch = $true
        }
        
        if ($NameMatch) {
            return [PSCustomObject]@{
                Matched           = $true
                Target            = $Target.Name
                Version           = $Target.Version
                Priority          = $Target.Priority
                ExactVersionMatch = $VersionMatch
            }
        }
    }
    
    return [PSCustomObject]@{ Matched = $false }
}

function Get-ProductKey {
    <#
    .SYNOPSIS
        Creates a unique key for deduplication (includes user context)
    #>
    param([PSCustomObject]$Product)
    
    $Name = if ($Product.Name) { $Product.Name.Trim() } else { "Unknown" }
    $Version = if ($Product.Version) { $Product.Version.Trim() } else { "Unknown" }
    $Location = if ($Product.InstallLocation) { $Product.InstallLocation.Trim().ToLower() } else { "" }
    $User = if ($Product.UserContext) { $Product.UserContext } else { "Machine" }
    
    return "$Name|$Version|$Location|$User"
}

function Send-ToAzureBlob {
    param(
        [string]$JsonContent,
        [string]$Filename
    )
    
    $UploadUrl = "$BlobBaseUrl/$Filename`?$SasToken"
    
    for ($Attempt = 1; $Attempt -le $MaxUploadRetries; $Attempt++) {
        try {
            $Headers = @{
                "x-ms-blob-type" = "BlockBlob"
                "Content-Type"   = "application/json; charset=utf-8"
            }
            
            # Use TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            $null = Invoke-RestMethod -Uri $UploadUrl -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($JsonContent)) -Headers $Headers -TimeoutSec 30 -ErrorAction Stop
            return @{ Success = $true; Attempts = $Attempt }
        }
        catch {
            $LastError = $_.Exception.Message
            if ($Attempt -lt $MaxUploadRetries) {
                Start-Sleep -Seconds (2 * $Attempt)  # Exponential backoff
            }
        }
    }
    
    return @{ Success = $false; Message = $LastError; Attempts = $MaxUploadRetries }
}

function Save-LocalFallback {
    param(
        [string]$JsonContent,
        [string]$Filename
    )
    
    try {
        if (-not (Test-Path $LocalFallbackPath)) {
            New-Item -ItemType Directory -Path $LocalFallbackPath -Force | Out-Null
        }
        
        $FilePath = Join-Path $LocalFallbackPath $Filename
        [System.IO.File]::WriteAllText($FilePath, $JsonContent, [System.Text.Encoding]::UTF8)
        return @{ Success = $true; Path = $FilePath }
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

#endregion Functions

#region Main Detection Logic

try {
    Write-Host "`nScanning for Autodesk installations..." -ForegroundColor Yellow

    Write-Host "  [1/4] Collecting User Profiles..." -ForegroundColor Gray
    $Results.AllUsers = @($(Get-AllLocalUsers))
    Write-Host "        Found $(@($Results.AllUsers).Count) user profiles" -ForegroundColor Gray

    Write-Host "  [2/4] Checking Registry (HKLM + User Hives)..." -ForegroundColor Gray
    $RegistryProducts = Get-InstalledAutodeskFromRegistry

    Write-Host "  [3/4] Checking File System..." -ForegroundColor Gray
    $FileSystemProducts = Get-AutodeskFromFileSystem

    Write-Host "  [4/4] Searching for Serial Numbers..." -ForegroundColor Gray
    $SerialNumbers = @(Get-AutodeskSerialNumbers)

    # Combine and deduplicate using composite key
    $AllProducts = @()
    $AllProducts += $RegistryProducts
    $AllProducts += $FileSystemProducts

    $SeenKeys = @{}
    $UniqueProducts = @()

    foreach ($Product in $AllProducts) {
        $Key = Get-ProductKey -Product $Product
        if (-not $SeenKeys.ContainsKey($Key)) {
            $SeenKeys[$Key] = $true
            $UniqueProducts += $Product
        }
    }

    $Results.ScanComplete = $true
}
finally {
    # Always cleanup: Unload any user hives we loaded
    foreach ($SID in $Script:LoadedHives) {
        Dismount-UserHive -SID $SID
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DETECTION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Display users
Write-Host "`nUsers who have logged into this machine:" -ForegroundColor Yellow
foreach ($User in @($Results.AllUsers)) {
    Write-Host "  - $($User.Username) (Last: $($User.LastUseTime))" -ForegroundColor Gray
}

if ($UniqueProducts.Count -gt 0) {
    $Results.AutodeskFound = $true
    Write-Host "`nAutodesk products found: $($UniqueProducts.Count)" -ForegroundColor Yellow
    
    foreach ($Product in $UniqueProducts) {
        $Match = Test-ProductMatch -Product $Product
        
        $ProductRecord = [PSCustomObject]@{
            Name            = $Product.Name
            Version         = $Product.Version
            InstallLocation = $Product.InstallLocation
            Source          = $Product.Source
            UserContext     = $Product.UserContext
            IsFlagged       = $false
            FlagReason      = ""
            Priority        = "Low"
        }
        
        if ($Match.Matched) {
            $ProductRecord.Priority = $Match.Priority
            
            if ($Match.ExactVersionMatch) {
                $ProductRecord.IsFlagged = $true
                $ProductRecord.FlagReason = "Matches compliance target: $($Match.Target) $($Match.Version)"
                $Results.FlaggedProducts += $ProductRecord
                
                Write-Host "`n  [CRITICAL] $($Product.Name)" -ForegroundColor Red
                Write-Host "    Version: $($Product.Version)" -ForegroundColor Red
                Write-Host "    Location: $($Product.InstallLocation)" -ForegroundColor Red
                Write-Host "    User Context: $($Product.UserContext)" -ForegroundColor Red
            }
            else {
                Write-Host "`n  [WARNING] $($Product.Name)" -ForegroundColor Yellow
                Write-Host "    Version: $($Product.Version)" -ForegroundColor Yellow
                Write-Host "    User Context: $($Product.UserContext)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n  [INFO] $($Product.Name)" -ForegroundColor White
            Write-Host "    Version: $($Product.Version)" -ForegroundColor Gray
        }
        
        $Results.Products += $ProductRecord
    }
}
else {
    Write-Host "`nNo Autodesk products detected." -ForegroundColor Green
}

# Serial numbers
Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "SERIAL NUMBER ANALYSIS" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Cyan

$FlaggedSerials = $SerialNumbers | Where-Object { $_.Flagged -eq $true }

if ($FlaggedSerials.Count -gt 0) {
    Write-Host "`n[CRITICAL] Flagged serial number detected!" -ForegroundColor Red
    foreach ($Serial in $FlaggedSerials) {
        Write-Host "  Value: $($Serial.Value)" -ForegroundColor Red
        Write-Host "  Location: $($Serial.Path)" -ForegroundColor Red
        Write-Host "  Context: $($Serial.Context)" -ForegroundColor Red
    }
    $Results.AlertLevel = "Critical"
}
else {
    Write-Host "`nNo flagged serial numbers found." -ForegroundColor Green
}

$Results.RegistrySerials = @($SerialNumbers)

# Determine alert level
if ($Results.AlertLevel -ne "Critical") {
    if ($Results.FlaggedProducts.Count -gt 0) {
        $Results.AlertLevel = "Critical"
    }
    elseif ($Results.AutodeskFound) {
        $Results.AlertLevel = "Warning"
    }
}

# Generate summary
$SummaryParts = @()
$SummaryParts += "Users: $($Results.UsersScanned)/$(@($Results.AllUsers).Count) scanned"
if ($Results.UsersFailed -gt 0) {
    $SummaryParts += "INCOMPLETE: $($Results.UsersFailed) users not scanned"
}
if ($Results.FlaggedProducts.Count -gt 0) {
    $SummaryParts += "FLAGGED: $($Results.FlaggedProducts.Count) compliance targets"
}
if ($FlaggedSerials.Count -gt 0) {
    $SummaryParts += "FLAGGED SERIAL FOUND"
}
if ($Results.AutodeskFound -and $Results.FlaggedProducts.Count -eq 0) {
    $SummaryParts += "Autodesk products: $($Results.Products.Count)"
}
if (-not $Results.AutodeskFound) {
    $SummaryParts += "No Autodesk software"
}
if ($Results.Errors.Count -gt 0) {
    $SummaryParts += "Errors: $($Results.Errors.Count)"
}

$Results.Summary = $SummaryParts -join " | "

# Adjust alert level if user scan was incomplete
if ($Results.UsersFailed -gt 0 -and $Results.AlertLevel -eq "None") {
    $Results.AlertLevel = "Warning"
}

#endregion Main Detection Logic

#region Upload Results

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "UPLOADING RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$Filename = "$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$JsonOutput = $Results | ConvertTo-Json -Depth 10 -Compress

Write-Host "`nUploading to Azure Blob Storage..." -ForegroundColor Yellow
$UploadResult = Send-ToAzureBlob -JsonContent $JsonOutput -Filename $Filename

if ($UploadResult.Success) {
    Write-Host "  [SUCCESS] Uploaded (attempt $($UploadResult.Attempts))" -ForegroundColor Green
    Write-Host "  Filename: $Filename" -ForegroundColor Gray
    $Results.UploadStatus = "Uploaded"
}
else {
    Write-Host "  [FAILED] $($UploadResult.Message)" -ForegroundColor Red
    Write-Host "  Saving to local fallback..." -ForegroundColor Yellow
    
    $LocalResult = Save-LocalFallback -JsonContent $JsonOutput -Filename $Filename
    
    if ($LocalResult.Success) {
        Write-Host "  [SAVED] $($LocalResult.Path)" -ForegroundColor Yellow
        $Results.UploadStatus = "LocalFallback: $($LocalResult.Path)"
    }
    else {
        Write-Host "  [ERROR] Local save failed: $($LocalResult.Message)" -ForegroundColor Red
        $Results.UploadStatus = "FAILED: $($UploadResult.Message)"
    }
}

#endregion Upload Results

#region Final Output

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$AlertColor = switch ($Results.AlertLevel) {
    "Critical" { "Red" }
    "Warning"  { "Yellow" }
    default    { "Green" }
}

Write-Host "`nAlert Level: $($Results.AlertLevel)" -ForegroundColor $AlertColor
Write-Host "Summary: $($Results.Summary)" -ForegroundColor White
Write-Host "Upload Status: $($Results.UploadStatus)" -ForegroundColor Gray

if ($Results.Errors.Count -gt 0) {
    Write-Host "`nErrors encountered:" -ForegroundColor Red
    foreach ($Err in $Results.Errors) {
        Write-Host "  - [$($Err.Context)] $($Err.Message)" -ForegroundColor Red
    }
}

# Compact stdout for RMM - full data is in blob
Write-Host "`n### SCAN_RESULT ###" -ForegroundColor DarkGray
$StdoutSummary = [PSCustomObject]@{
    ComputerName    = $Results.ComputerName
    ScanDate        = $Results.ScanDate
    AlertLevel      = $Results.AlertLevel
    Summary         = $Results.Summary
    UsersScanned    = $Results.UsersScanned
    UsersFailed     = $Results.UsersFailed
    ProductsFound   = $Results.Products.Count
    FlaggedCount    = $Results.FlaggedProducts.Count
    UploadStatus    = $Results.UploadStatus
    ScanComplete    = $Results.ScanComplete
    ErrorCount      = $Results.Errors.Count
}
$StdoutSummary | ConvertTo-Json -Compress
Write-Host "### END_RESULT ###" -ForegroundColor DarkGray

#endregion Final Output

# Exit 0 always for RMM compatibility - alert level is in the JSON
exit 0
