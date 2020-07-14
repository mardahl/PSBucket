#Requires -Version 5.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
This script will add an AAD user to the local Administrators group.
.DESCRIPTION
The script will look for predefined groups is Azure AD, and add the members to the local Administrators group.
Logic can be applied for different scenarios, by customizing this script.
.EXAMPLE
Just run this script without any parameters in the system user context (for example, as an Intune Extensions Powershell script)
.NOTES
NAME: aad_controlled_localadmins.ps1
VERSION: 1b
PREREQ: You need to have registered an App in Azure AD with the required permissions to have this script work with the Microsoft Graph API.
        For this script the following permissions must be assigned to the application: Directory.Read.All
.COPYRIGHT
@michael_mardahl / https://www.iphase.dk
Some parts of the authentication functions have been heavily modified from their original state, initially provided by Microsoft as samples of Accessing AAD.
Licensed under the MIT license.
Please credit me if you fint this script useful and do some cool things with it.
#>

####################################################
#
# CONFIG
#
####################################################

    #Required credentials - Get the client_id and client_secret from the app when creating it i Azure AD
    $client_id = "4j4nf78dj-9d87-mrj6-0000-hjf7dnsy5ef2" #App ID
    $client_secret = "j6lflsj9untUQi94Q0000ghMALYrn0000/sOy00D8rs=" #API Access Key Password

    #tenant_id can be read from the azure portal of your tenant (check the properties blade on your azure active directory)
    $tenant_id = "0000054-c700-400e-9004-1000009c3700" #Directory ID

    #Object ID of the group that holds users, whom need to be local admin on AAD joined Intune Devices
    $localAdminGroupID = "00098b5a-0000-4a53-0000-3bd1d69f604e"

    #Special params for some advanced modification
    $global:graphApiVersion = "v1.0" #should be "v1.0"
    

####################################################
#
# FUNCTIONS
#
####################################################

Function Get-AuthToken {
    
    <#
    .SYNOPSIS
    This function is used to get an auth_token for the Microsoft Graph API
    .DESCRIPTION
    The function authenticates with the Graph API Interface with client credentials to get an access_token for working with the REST API
    .EXAMPLE
    Get-AuthToken -TenantID "0000-0000-0000" -ClientID "0000-0000-0000" -ClientSecret "sw4t3ajHTwaregfasdgAWREGawrgfasdgAWREGw4t24r"
    Authenticates you with the Graph API interface and creates the AuthHeader to use when invoking REST Requests
    .NOTES
    NAME: Get-AuthToken
    #>

    param
    (
        [Parameter(Mandatory=$true)]
        $TenantID,
        [Parameter(Mandatory=$true)]
        $ClientID,
        [Parameter(Mandatory=$true)]
        $ClientSecret
    )
    
    try{
        # Define parameters for Microsoft Graph access token retrieval
        $resource = "https://graph.microsoft.com"
        $authority = "https://login.microsoftonline.com/$TenantID"
        $tokenEndpointUri = "$authority/oauth2/token"
  
        # Get the access token using grant type client_credentials for Application Permissions
        $content = "grant_type=client_credentials&client_id=$ClientID&client_secret=$ClientSecret&resource=$resource"

        $response = Invoke-RestMethod -Uri $tokenEndpointUri -Body $content -Method Post -UseBasicParsing

        Write-Host "Got new Access Token!" -ForegroundColor Green
        Write-Host

        # If the accesstoken is valid then create the authentication header
        if($response.access_token){
    
        # Creating header for Authorization token
    
        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $response.access_token
            'ExpiresOn'=$response.expires_on
            }
    
        return $authHeader
    
        }
    
        else{
    
        Write-Error "Authorization Access Token is null, check that the client_id and client_secret is correct..."
        break
    
        }

    }
    catch{
    
        FatalWebError -Exeption $_.Exception -Function "Get-AuthToken"
   
    }

}

####################################################

Function Get-ValidToken {

    <#
    .SYNOPSIS
    This function is used to identify a possible existing Auth Token, and renew it using Get-AuthToken, if it's expired
    .DESCRIPTION
    Retreives any existing Auth Token in the session, and checks for expiration. If Expired, it will run the Get-AuthToken Fucntion to retreive a new valid Auth Token.
    .EXAMPLE
    Get-ValidToken
    Authenticates you with the Graph API interface by reusing a valid token if available - else a new one is requested using Get-AuthToken
    .NOTES
    NAME: Get-ValidToken
    #>

    #Fixing client_secret illegal char (+), which do't go well with web requests
    $client_secret = $($client_secret).Replace("+","%2B")
    
    # Checking if authToken exists before running authentication
    if($global:authToken){
    
        # Get current time in (UTC) UNIX format (and ditch the milliseconds)
        $CurrentTimeUnix = $((get-date ([DateTime]::UtcNow) -UFormat +%s)).split((Get-Culture).NumberFormat.NumberDecimalSeparator)[0]
                
        # If the authToken exists checking when it expires (converted to minutes for readability in output)
        $TokenExpires = [MATH]::floor(([int]$authToken.ExpiresOn - [int]$CurrentTimeUnix) / 60)
    
            if($TokenExpires -le 0){
    
                Write-Host "Authentication Token expired" $TokenExpires "minutes ago! - Requesting new one..." -ForegroundColor Green
                $global:authToken = Get-AuthToken -TenantID $tenant_id -ClientID $client_id -ClientSecret $client_secret
    
            }
            else{

                Write-Host "Using valid Authentication Token that expires in" $TokenExpires "minutes..." -ForegroundColor Green
                Write-Host

            }

    }
    
    # Authentication doesn't exist, calling Get-AuthToken function
    
    else {
       
        # Getting the authorization token
        $global:authToken = Get-AuthToken -TenantID $tenant_id -ClientID $client_id -ClientSecret $client_secret
    
    }
    
}
    
####################################################

Function FatalWebError {

    <#
    .SYNOPSIS
    This function will output mostly readable error information for web request related errors.
    .DESCRIPTION
    Unwraps most of the exeptions details and gets the response codes from the web request, afterwards it stops script execution.
    .EXAMPLE
    FatalWebError -Exception $_.Exception -Function "myFunctionName"
    Shows the error message and the name of the function calling it.
    .NOTES
    NAME: FatalWebError
    #>

    param
    (
        [Parameter(Mandatory=$true)]
        $Exeption, # Should be the execption trace, you might try $_.Exception
        [Parameter(Mandatory=$true)]
        $Function # Name of the function that calls this function (for readability)
    )

#Handles errors for all my Try/Catch'es

        $errorResponse = $Exeption.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Failed to execute Function : $Function" -f Red
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Host "Request to $Uri failed with HTTP Status $($Exeption.Response.StatusCode) $($Exeption.Response.StatusDescription)" -f Red
        write-host
        break

}

####################################################

Function Get-AADGroupMembers(){
    
    <#
    .SYNOPSIS
    This function is used to get all the members of a groups in Azure AD, using the Graph API REST interface
    .DESCRIPTION
    The function connects to the Graph API Interface and gets all members of a group, by identifying it via and Object ID.
    The ID was choosen for stability, as it will allow the group to be renamed without breaking the script.
    .EXAMPLE
    Get-AADGroupMembers -objectID hr7rhrnt-7dht-8dhf-00ok-nt7fhd5shn44
    .NOTES
    NAME: Get-AADGroupMembers
    PREREQUISITES: Requires a global authToken (properly formattet hashtable header) to be set as $authToken and the FatalWebError Function to be in the script.
    #>
       
    param
    (
        [Parameter(Mandatory=$true)]
        $objectID
    )

    #$Resource = "myorganization/groups"
    $Resource = "/groups/$objectID/members"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"

    try {

        Return (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

    }
    
    catch {
    
        FatalWebError -Exeption $_.Exception -Function "Get-AADGroupMembers"
    
    }

    
}


####################################################

Function Add-localAdmin(){
    
    <#
    .SYNOPSIS
    This function is used to add a specified UPN to the built-in Administrators group
    .DESCRIPTION
    The function connects generates the required commandline required in order to add an Azure AD account to a local group, and handle any errors.
    IF all goes well, the user is added to the group.
    The fucntion will also validate agains existing members, to avoid generating errors.
    .EXAMPLE
    Get-AADGroupMembers -UPN user@domain.tld -Name "Display Name"
    .NOTES
    NAME: Add-LocalAdmin
    PREREQUISITES: Requires elevation
    #>
       
    param
    (
        [Parameter(Mandatory=$true)]
        $UPN,
        [Parameter(Mandatory=$true)]
        $Name
    )

    try {
        
        #Validating agains existing members
        
        #Formatting the correct commandline, and executing it.        
        $commandline = 'net localgroup administrators'
        $currentMembers = & cmd.exe /c "$commandline"
        #Special way of catching an error in the cmd and turning it into a terminating error.
        if ($LASTEXITCODE -ne 0) { throw }
        #Removing spaces from the users display name, and comparing agains current members.
        $noSpaceName = $Name -replace '\s',''
        $found = $currentMembers | select-string -Pattern $noSpaceName
        if ($found.count -gt 0) {
            Write-Host "Found $found, in the built-in Administrators group. Skipping..." -ForegroundColor Yellow
            continue
        }

        #Adding users, since validation seems to have passed

        Write-Host "Adding $Name <$UPN> to the built-in Administrators group." -ForegroundColor Yellow
        
        #Formatting the correct commandline, and executing it.        
        $commandline = 'net localgroup administrators /add "AzureAD\{0}"' -f $UPN
        & cmd.exe /c "$commandline"
        #Special way of catching an error in the cmd and turning it into a terminating error.
        if ($LASTEXITCODE -ne 0) { throw }

    }
    
    catch {
    
        Write-Host "Failed adding $userUPN to the built-in Administrators group." -ForegroundColor Red
        continue
    
    }

}

####################################################

Function Delete-localAADAdmins(){
    
    <#
    .SYNOPSIS
    This function is used to remove all the AAD users from the built-in Administrators group
    .DESCRIPTION
    The function generates the commandline required in order to remove an Azure AD account from the local administrators group, and handle any errors.
    IF all goes well, there will be no AAD accounts left in the built-in Administrators group.
    .EXAMPLE
    Delete-localAADAdmins
    .NOTES
    NAME: Delete-localAADAdmins
    PREREQUISITES: Requires elevation
        Be cautious when using this function, and make sure you dont cripple your access to the device.
    #>
       
    try {

        #Cleaning out users that are not members of the AAD group
        
        #Getting current members that are from AzureAD
        #Formatting the correct commandline, and executing it.        
        $commandline = 'net localgroup administrators'
        $currentMembers = & cmd.exe /c "$commandline"
        #Special way of catching an error in the cmd and turning it into a terminating error.
        if ($LASTEXITCODE -ne 0) { throw }
        #Getting a list of AAD accounts currently in the local Administrators group.
        $AADAccounts = $currentMembers | select-string -Pattern "AzureAD\\"
        if ($AADAccounts.count -gt 0) {

            Write-Host "Removing users from Administrators group..." -ForegroundColor Yellow

                foreach ($account in $AADAccounts) {
                    
                    try {

                        #Removing accounts one at a time
                        Write-Host "Now removing $account" -ForegroundColor Yellow
                        #Formatting the correct commandline, and executing it.        
                        $commandline = 'net localgroup administrators {0} /DELETE' -f $account
                        $currentMembers = & cmd.exe /c "$commandline"
                        #Special way of catching an error in the cmd and turning it into a terminating error.
                        if ($LASTEXITCODE -ne 0) { throw }

                    } 
                    catch {
                        
                        Write-Host "ERROR: Could not remove $account from built-in Administrators group." -ForegroundColor Red
                        continue

                    }

                }
            
        } 
        
        else {

             Write-Host "Found no AzureAD accounts, in the built-in Administrators group. Skipping..." -ForegroundColor Yellow

        }

    }
    catch {

        Write-Host "There was an error getting the current members of the built-in Administrators group." -ForegroundColor Yellow

    }

}

####################################################
#
# EXECUTION
#
####################################################

Write-Host "Adding required members to the built-in Administrators group." -ForegroundColor Magenta
Write-Host

#Calling Microsoft to see if they will give us access with the parameters defined in the config section of this script.
Get-ValidToken

#Getting the members of the predefined groups (see config section)
$localAdmins = Get-AADGroupMembers -objectID $localAdminGroupID

#EXPERIMENTAL: Deletes all AAD accounts before adding them back again, in order to cleanup users that have left the group.
#Only enable this command if you fully understand the flow of this script, and the potentioal consequences.
#Delete-localAADAdmins

foreach ($user in $localAdmins) {
    
    Add-localAdmin -UPN $user.userPrincipalName -Name $user.displayName

}

Write-Host
Write-Host "Completed script execution."
