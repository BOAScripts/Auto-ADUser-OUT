# About

Files to setup/reset my AD environment for testing.

# AD Structure

Defining the AD structure of my testing environment.

# Usage

On a management workstation of a remote DC:

`git clone https://github.com/BOAScripts/Auto-ADUser-OUT.git`

Review `./AD-Setup/data/`

- domain: domain simple name.
- RootOUName: The custom OU where all the custom OUs will be populated.
- CustomOUs: All OUs to create in a readable path format 
- userGroupOU: Distinguished name of the `user security groups`
- userGroupNames: List of groups to create in userGroupOU and randomly assign to users
- activeUsersPerOU: Integer for the number of active users to create in each user OU
- expiredUsersPerOU: Integer for the number of expired users to create in each user OU
- userExpirationTypes: `"Key":"Value"` of a set of users and what expiration date to assign. Assign the expiration date to all users that are in a OU with the Key in his distinguished name. Accepted values for dates are "$false" or "integer-(Year/Month/Day),integer-(Year/Month/Day),..." (eg:"External":"1-Year,2-Month,3-Day").
- thresholds: "Key":"Value" of time that users will be in the WAITING and DISABLED OU. The accepted values are the same as above.


-> Setup a PS-Session to your DC, and copy the content to a writable folder.
```powershell
$cred = get-credential
$Sess = New-PSSession -ComputerName $DC -Credential $Cred
Copy-item "./*.*" -Destination "C:/Windows/Tasks/" -ToSession $Sess # ???
Enter-PSSession $Sess
```

`./AD-Setup/AD-Setup.ps1 -Action Create`

-> Verify execution with the script output and AD GUI.

# Limitations

- There is only 1000 user names in the .csv, so `($model.activeUsersPerOU + $model.expiredUsersPerOU) * $userOUs.Length` cannot be more than 1000 => $userOUs are OUs where there is "user" in the distinguished name but not "security groups","WAITING","DISABLED".

# Issues

- users in Internal & External OU precisely doesn't have a department in their description.

# Copy below in project readme, not in AD-Setup

# Users

## Active Users

About: Root **user** OU where all users are. Has a set of sub OUs  
Action: Detect all expired users, move them to waiting OU without disabling it and apply small changes (reset password, description modification,...)  
OUs: ...

5 freshly created users in each user OUs.  
2 expired users in each user OUs.

## Waiting Users

About: OU where expired users will be moved for a period of time to allow processing/synchro with whatever systems (Azure/ERP/...) before going to the disabled OU. This OU can also be used by AD operators to disable users with minimal actions (move to OU + reset password), it should reduce the user error when disabling a user.  
Actions: Detect waiting users in this OU for the defined period of time. Move them to disabled OU an apply all necessary disabling changes (Department, Description, Groups, ...)  
OU: ...

5 freshly moved in users.  
2 users that exceed the period of time defined.

## Disabled Users

About: OU where disabled users where put for a period of time. Depending of the retention policy. Some companies will prefer to directly delete disabled users, while other prefer to have retention over who came by.   
Actions: Delete users that are in this OU for the defined period of time.  
OU: ...

5 freshly moved in users.  
2 users that exceed the period of time defined.


