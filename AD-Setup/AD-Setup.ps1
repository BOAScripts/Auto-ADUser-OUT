<#
Purpose: Setup my AD structure.
Switches
    -Create : Creation of OU/Groups/Users definied in ./data/* files.
    -Delete : Purge the AD of created entries (OU/Groups/Users)
    -Reset  : -Purge then -Create.
#>

# VARS
## Static

## External content
$OUsList = Get-Content "./data/OU-Definition.txt"
$model = Get-Content "./data/model.json" | ConvertFrom-Json
$allNames = Get-Content "./data/1000names.csv" | ConvertFrom-Csv

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

# ---------------------
# Zhu-li, do the thing:
# ---------------------

# Check AD
## Making sure the user / computers are created in the correct default/custom location
redircmp $model.ComputersOU
redirusr $model.UsersOU

# -Create, -Purge or -Reset ?

# OU

# Security Groups 

# Users

