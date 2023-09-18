<#
Purpose: Setup my AD structure.
Switches
    -Action Create : Creation of OU/Groups/Users defined in ./data/model.json.
    -Action Delete : Delete recursivly everything that is unprotected in the RootOUName
    -Action Reset  : Delete then Create.
#>

# PARAMETERS
Param(
    [ValidateSet('Create','Delete','Reset')]$Action,
    [switch]$help
)
# VARS
## Static
$HelpTxt = @'
Purpose     : Setup my AD structure.
Switches    :
    -Action Create : Creation of OU/Groups/Users defined in ./data/model.json.
    -Action Delete : Delete recursivly everything that is unprotected in the RootOUName
    -Action Reset  : Delete then Create.
'@
if ($help){
    Write-Host $HelpTxt
}


## External content
$modelPath = "./data/model.json"
$model = Get-Content $modelPath | ConvertFrom-Json
$Tnames = [System.Collections.ArrayList](Get-Content "./data/1000simpleNames.csv" | ConvertFrom-Csv -Delimiter ";")

## Output files
$outPath = "./data/out/"
$logName = "outputfile.txt"
if ((Test-Path $outPath) -eq $false){
    New-Item $outPath -ItemType Directory
}
$logs = $outPath + $logName

# FUNCTIONS

function Get-CharsList (){
    $list = @('.',',','-','_','(',')','[',']','!',"'") # self-defined
    $alphaNumIds = (48..57),(65..90),(97..122) # (numerics),(uppercase letters),(lowercase letters) ASCII ids

    foreach ($subList in $alphaNumIds){
        foreach ($id in $subList){
            $list += [char]$id
        }
    }
    return $list
}

Function Get-NewPassword([int32]$Nbr,[array]$AllowedChars){
    $DefinitelyNotAPassword = ""
    Get-Random -InputObject $AllowedChars -Count $Nbr | ForEach-Object {$DefinitelyNotAPassword += $_.ToString()}
    $sPsw = ConvertTo-SecureString $DefinitelyNotAPassword -AsPlainText -Force

    return $sPsw,$DefinitelyNotAPassword
}

# Return Distinguished name for domain and ROOT ou
function get-DomainNRoot($domain,$RootOUName){
    $domainDistName = ""
    foreach ($i in $domain.Split('.')){
        $sSub = "DC=$i,"
        $domainDistName += $sSub
    }
    $domainDistName = $domainDistName.Substring(0,$domainDistName.Length-1)
    $RootDistName = "OU=$RootOUName,$domainDistName"

    return $domainDistName, $RootDistName
}

# Set-OUs -OUPaths $model.CustomOUs -DC $domainDistName -RootOUName $model.RootOUName -Delete
Function Set-OUs([array]$OUPaths,[string]$DC,[string]$RootOUName,[switch]$delete){
    $OUs = @("$RootOUName/$DC")
    $OUIdentities = @()
    # Building OUs array ("OUName"/"OUPath")
    foreach ($ou in $OUPaths){
        $splitted = $ou.Split('/')
        $ouname = $splitted[$splitted.Length-1]
        $oupath = $DC

        if ($splitted.Length -gt 1){
            for($i=0; $i -lt ($splitted.Length -1); $i++){
                $oupath = "OU=" + $splitted[$i] + "," + $oupath
            }
        }
        $OUs += "$ouname/$oupath"
    }
    # OU creation or deletion
    if(!$Delete){
        foreach($ou in $OUs){
            $ouname,$oupath = $ou.Split('/')[0],$ou.Split('/')[1]
            $ouIdentity = "OU=$ouname,$oupath"
            try {
                Write-Host "    [+] Creating OU=$ouname,$oupath"
                New-ADOrganizationalUnit -Name "$ouname" -Path "$oupath" -ProtectedFromAccidentalDeletion $false
                $OUIdentities += $ouIdentity
            }
            catch {
                $msg = $_
                Write-Host "    [!] Error creating $ouIdentity" -ForegroundColor Red
                Write-Host $msg -ForegroundColor Red
            } 
        }  
        # SHOULN'T BE HERE ??    
        return $OUIdentities
    }
    else {
        [array]::Reverse($OUs)
        foreach($ou in $OUs){
            $ouname,$oupath = $ou.Split('/')[0],$ou.Split('/')[1]
            $ouIdentity = "OU=$ouname,$oupath"
            try {
                Write-Host "[-] Deleting $ouIdentity"
                Remove-ADOrganizationalUnit -Identity $ouIdentity -Recursive -Confirm:$false
            }
            catch {
                $msg = $_
                Write-Host "[!] Error deleting $ouIdentity" -ForegroundColor Red
                Write-Host $msg -ForegroundColor Red
            }   
        }
    }
    return $OUIdentities
}

function set-ADGroups ([array]$groupNames,[string]$userGroupsOU){
    foreach ($group in $groupNames){
        try {
            Write-Host "    [+] Creating $group"
            New-ADGroup -Name $group -GroupCategory Security -GroupScope DomainLocal -Path $userGroupsOU
        }
        catch{
            $msg= $_
            Write-Host "    [!] Error creating $group" -ForegroundColor Red
            Write-Host $msg -ForegroundColor Red
        }
    }
    
}

# To use with the model.json.userExpirations, return a hashtable with "ExpirationType":"ExpirationTypeDate"
function Get-Times($userExpirations) {
    $Now = Get-Date
    $retVal = @{}
    foreach($item in $userExpirations.PSObject.Properties){
        $userTypeName, $userTypeExpDate = $item.Name, $item.Value
        $targetDate = $Now

        if ($userTypeExpDate -ne '$false'){
            foreach ($splitVal in $userTypeExpDate.Split(',')){
                $iValue, $sDateUnit = $splitVal.Split('-')[0],$splitVal.Split('-')[1]
                if ($sDateUnit -eq "Day"){
                    $targetDate = $targetDate.AddDays($iValue)
                }
                elseif ($sDateUnit -eq "Month"){
                    $targetDate = $targetDate.AddMonths($iValue)
                }
                elseif ($sDateUnit -eq "Year"){
                    $targetDate = $targetDate.AddYears($iValue)
                }
                else {
                    Write-Host "[!] $sDateUnit : not detected by the script - only ('Day','Month','Year') singular, not case sensitive" -ForegroundColor Red
                }
            }
            $targetDate = Get-Date -Year $targetDate.Year -Month $targetDate.Month -Day $targetDate.Day -Hour 0 -Minute 0 -Second 0
        }
        else {
            $targetDate = $false
        }
        $retVal.Add("$userTypeName","$targetDate")
        # Write-Host "[i] $userTypeName users will have an expiration date set to:$targetDate"
    }
    return $retVal
}

# Active or Expired user creation, return SAM
function set-NewADUser($domain, $destOU, $expDate, [switch]$expired) {    
    # Get a random name from .csv and remove it from the list
    $userNames = Get-Random -InputObject $Tnames
    $Tnames.Remove($userNames)
    # Get a random set of groups (between 1 and 3)
    $groups = @((Get-Random -InputObject $model.userGroupNames -Count (Get-Random -InputObject (1..3) -Count 1)))
    # Get a random description
    $AddDesc = Get-Random -InputObject $model.AdditionalDesc
    # Get departement
    foreach($outDept in $model.Depts){
        if ($destOU -like "*$outDept*"){
            $Dept = $outDept
        }
    }
    # Build full desc
    $fDesc = "[$Dept] $AddDesc"
    # Get user psw 
    $sPsw, $psw = Get-NewPassword -Nbr 12 -AllowedChars $charlist
    # define default values // Sanitize those values in a PROD env.
    $displayName = $userNames.firstName + " " + $userNames.lastName
    $SAM = ($userNames.firstName + "." + $userNames.lastName).toLower()
    $UPN = $SAM + "@" + $domain
    # Active user
    if (!$expired){
        # Expiration date is well defined
        if($expDate -ne $false){
            try {
                New-ADUser -Path $destOU -Name $displayName -DisplayName $displayName -GivenName $userNames.firstName -Surname $userNames.lastName -SamAccountName $SAM -UserPrincipalName $UPN -EmailAddress $UPN -AccountPassword $sPsw -AccountExpirationDate $expDate -ChangePasswordAtLogon $true -Enabled $true -Description $fDesc
                Write-Host "   [+] Creating user :$UPN - $expDate // $fDesc" -ForegroundColor Blue
            }
            catch {
                $msg = $_
                Write-Host "[!] Error creating Active User (expDate defined): $SAM " -ForegroundColor Red
                Write-Host $msg -ForegroundColor Red
            }
        }
        # Expiration date set to $false
        else{
            try {
                New-ADUser -Path $destOU -Name $displayName -DisplayName $displayName -GivenName $userNames.firstName -Surname $userNames.lastName -SamAccountName $SAM -UserPrincipalName $UPN -EmailAddress $UPN -AccountPassword $sPsw -ChangePasswordAtLogon $true -Enabled $true -Description $fDesc
                Write-Host "   [+] Creating user :$UPN - $expDate // $fDesc" -ForegroundColor Blue
            }
            catch {
                $msg = $_
                Write-Host "[!] Error creating Active User (expDate not defined): $SAM" -ForegroundColor Red
                Write-Host $msg -ForegroundColor Red
            }
        }

    }
    # Expired user (not disabled as AD doesn't disabled an expired user)
    else{
        try {
            New-ADUser -Path $destOU -Name $displayName -DisplayName $displayName -GivenName $userNames.firstName -Surname $userNames.lastName -SamAccountName $SAM -UserPrincipalName $UPN -EmailAddress $UPN -AccountPassword $sPsw -AccountExpirationDate (Get-Date) -Enabled $true -Description $fDesc
            Write-Host "   [+] Creating DISABLED user :$UPN // $fDesc" -ForegroundColor Cyan
        }
        catch {
            $msg = $_
            Write-Host "[!] Error creating Expired User: $SAM" -ForegroundColor Red
            Write-Host $msg -ForegroundColor Red
        }

    }
    # Add user to his groups
    foreach($group in $groups){
        try {
             # Add-ADGroupMember -Identity $group -Members $SAM
             Write-Host "       [+] Adding user :$UPN to $group"
        }
        catch {
            $msg = $_
            Write-Host "[!] Error setting $SAM in $group :" -ForegroundColor Red
            Write-Host $msg -ForegroundColor Red
        }
    }
    return $SAM, $psw

}

function set-Manager ($userOUs) {
    $managerOUs = @()
    $managedOUs = @()
    foreach ($ou in $userOUs){
        if($ou -like "*manager*"){
            $managerOUs += $ou
            $managedOUs += $ou
            $managedOUs += $ou.Replace("$($ou.Split(',')[0]),","") # adding parent ou to managed ous
        }
    }
}

# ---------------------
# Zhu-li, do the thing:
# ---------------------

# Define default values
$userOUs = @()
$charlist = Get-CharsList
$domainDistName, $RootDistName = get-DomainNRoot -domain $model.domain -RootOUName $model.RootOUName
$expDefinitions = Get-Times($model.userExpirationTypes)

# Check AD

# -Create, -Delete or -Reset ?
if ($Action -eq 'Create'){
    Write-Host "[+] Creating AD Structure following $modelPath" -ForegroundColor Green
    # OUs
    Write-Host "[+] OUs:" -ForegroundColor Green
    $allOUs = Set-OUs -OUPaths $model.CustomOUs -RootOUName $model.RootOUName -DC $domainDistName
    foreach($ou in $allOUs){
        if ($ou -like "*user*" -and $ou -notlike "*Security groups*" -and $ou -notlike "*WAITING*" -and $ou -notlike "*DISABLED*"){
            $userOUs += $ou
        }
    }
    # Security Groups 
    Write-Host "[+] Security groups:" -ForegroundColor Green
    set-ADGroups -groupNames $model.userGroupNames -userGroupsOU $model.userGroupsOU
    # Users
    Write-Host "[+] Users:" -ForegroundColor Green
    foreach($expType in $expDefinitions.Keys){
        Write-Host "[i] Processing $expType, expiration date is: $($expDefinitions.$expType)" -ForegroundColor Yellow
        foreach ($userOU in $userOUs){
            if ($userOU -like "*$expType*"){
                Write-Host "    [+] Creating users in $userOU" -ForegroundColor Yellow
                # Create n Active users with the definied expiration date
                for($i=0; $i -lt $model.activeUsersPerOU; $i++){
                    ## Create user
                    $SAM,$psw = set-NewADUser -domain $model.domain -destOU $userOU -expDate $($expDefinitions.$expType)
                    ## Append new user:psw to logfile
                    Out-File -FilePath $logs -InputObject ($SAM + ":" + $psw) -Append
                }
                # Create n Expired users with an expiration date as of now.
                for($i=0; $i -lt $model.expiredUsersPerOU; $i++){
                    ## Create user
                    $SAM,$psw = set-NewADUser -domain $model.domain -destOU $userOU -expired
                    ## Append new user:psw to logfile
                    Out-File -FilePath $logs -InputObject ($SAM + ":" + $psw) -Append
                       
                }
            }
        }
    }
    Out-File -FilePath $logs -InputObject "#----------------------------------#" -Append
}

elseif ($Action -eq 'Delete') {
    # Recursive delete _ROOT OU (everything unprotected from accidental deletion)
    Write-Host "[-] Deleting $($model.RootOUName) recursively" -ForegroundColor Blue
    $allOUs = Set-OUs -OUPaths $model.CustomOUs -RootOUName $model.RootOUName -DC $domainDistName -delete
}

elseif ($Action -eq 'Reset') {
    Write-Host "[..] Resetting AD Structure following ./data/model.json" -ForegroundColor Yellow
    # 1. Delete
    ## Recusrive OU deletion
    Write-Host "[-] Deleting _ROOT OU recursively" -ForegroundColor Blue
    $allOUs = Set-OUs -OUPaths $model.CustomOUs -RootOUName $model.RootOUName -DC $domainDistName -delete

    # 2. Create
    Write-Host "[+] Creating AD Structure following $modelPath" -ForegroundColor Green
    # OUs
    Write-Host "[+] OUs:" -ForegroundColor Green
    $allOUs = Set-OUs -OUPaths $model.CustomOUs -RootOUName $model.RootOUName -DC $domainDistName
    foreach($ou in $allOUs){
        if ($ou -like "*user*" -and $ou -notlike "*Security groups*" -and $ou -notlike "*WAITING*" -and $ou -notlike "*DISABLED*"){
            $userOUs += $ou
        }
    }
    # Security Groups 
    Write-Host "[+] Security groups" -ForegroundColor Green
    set-ADGroups -groupNames $model.userGroupNames -userGroupsOU $model.userGroupsOU
    # Users
    Write-Host "[+] Users:" -ForegroundColor Green
    foreach($expType in $expDefinitions.Keys){
        Write-Host "[i] Processing $expType, expiration date is: $($expDefinitions.$expType)" -ForegroundColor Yellow
        foreach ($userOU in $userOUs){
            if ($userOU -like "*$expType*"){
                Write-Host "    [+] Creating users in $userOU" -ForegroundColor Yellow
                # Create n Active users with the definied expiration date
                for($i=0; $i -lt $model.activeUsersPerOU; $i++){
                    ## Create user
                    $SAM,$psw = set-NewADUser -domain $model.domain -destOU $userOU -expDate $($expDefinitions.$expType)
                    ## Append new user:psw to logfile
                    Out-File -FilePath $logs -InputObject ($SAM + ":" + $psw) -Append
            
                }
                # Create n Expired users with an expiration date as of now.
                for($i=0; $i -lt $model.expiredUsersPerOU; $i++){
                    ## Create user
                    $SAM,$psw = set-NewADUser -domain $model.domain -destOU $userOU -expired
                    ## Append new user:psw to logfile
                    Out-File -FilePath $logs -InputObject ($SAM + ":" + $psw) -Append
                       
                }
            }
        }
    }
    Out-File -FilePath $logs -InputObject "#----------------------------------#" -Append
}

else{
    Write-Host "[!] No parameter: see -help"
}



