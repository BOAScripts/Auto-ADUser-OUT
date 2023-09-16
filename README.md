# About

Set of tools to reduce the human actions in AD when an AD-User come to the end of his lifecycle.
And also remediate the design of not disabling an AD-user although his expiration date is in the past.

- Set-Config : Tool to create a config file. It defines the variables of your environment and the actions to take on the different thresholds. 
- Auto-AD_User-Out : Script to use on a regular basis (Task Scheduler or other) to process the AD Users. It uses the config file previously created.

