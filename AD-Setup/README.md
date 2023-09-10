# About

Files to setup/reset my AD environment for testing.

# AD Structure

Defining the AD structure of my testing environment.

## Active Users

About: Root OU where all users are. Has a set of sub OUs  
Action: Detect all expired users, move them to waiting OU without disabling it and apply small changes (reset password, description modification,...)  
OUs: ...

### Users 

5 active users in root OU and each sub OU.  
2 expired users in root OU and each sub OU.

## Waiting Users

About: OU where expired users will be moved for a period of time to allow processing/synchro with whatever systems (Azure/ERP/...) before going to the disabled OU. This OU can also be used by AD operators to disable users with minimal actions (move to OU + reset password), it should reduce the user error when disabling a user.  
Actions: Detect waiting users in this OU for the defined period of time. Move them to disabled OU an apply all necessary disabeling changes (Department, Description, Groups, ...)  
OU: ...

### Users

2 freshly moved in users.  
2 users that exceed the period of time defined.

## Disabled Users

About: OU where disabled users where put for a period of time. Depending of the retention policy. Some companies will prefer to directly delete disabled users, while other prefer to have retention over who came by.   
Actions: Delete users that are in this OU for the defined period of time.  
OU: ...

### Users

2 freshly moved in users.  
2 users that exceed the period of time defined.


