#Script that will parse the Chrome ADMX files from your domains sysvol folder, and give you the OMA URI values.
#Script found on Reddit by https://www.reddit.com/user/ginolard/

$Domain = (Get-WmiObject Win32_ComputerSystem).Domain
Write-Host "Searching for Chrome policy files in $domain"

$PolSource = "filesystem::\\$domain\sysvol\$domain\Policies\"
$ChromeADMX = Get-ChildItem -Path $PolSource -Filter "chrome.admx" -Recurse
$ChromeADML = Get-ChildItem -Path $PolSource -Filter "chrome.adml" -Recurse

$results = @()

If ($ChromeADMX -and $ChromeADML) {
    #Read ADMX into an XML object
    Write-Host "Parsing $ChromeADMX"
    [xml]$admx_xmlContent = Get-Content "filesystem::$($ChromeADMX.FullName)"
    [System.Xml.XmlElement] $admx_xmlroot = $admx_xmlContent.get_DocumentElement()
    
    #Read ADML into an XML object
    Write-Host "Parsing $ChromeADML"
    [xml]$adml_xmlContent = Get-Content "filesystem::$($ChromeADML.FullName)"
    [System.Xml.XmlElement] $adml_xmlroot = $adml_xmlContent.get_DocumentElement()
    $StringHashTable = $adml_xmlroot.resources.stringTable.string |group-object id -AsHashTable

    #Set some top-level variables we'll need throughout
    $GPOname = $ChromeADMX.BaseName
    $CategoryHashTable = $admx_xmlroot.categories.category|Group-Object name -AsHashTable
    $Policies = $admx_xmlroot.policies.policy
    
    #Loop through every Policy element in the the ADMX and try to get the setting
    Write-Host "Extracting policy settings" 
    ForEach ($p in $policies) {
        
        Switch ($p.class) {
            Machine {$PolicyClass = "Computer Configuration"}
            User {$PolicyClass = "User Configuration"}
            Both {$PolicyClass = "Both Configurations"}
        }

        #Try to determine the data type of the setting (this may not be 100% accurate!)
        Switch ($false) {
            $([string]::IsNullOrEmpty($p.enabledValue.decimal)) {$ValueType = 'Boolean'}
            $([string]::IsNullOrEmpty($p.elements.boolean)) {$ValueType = 'Boolean'}
            $([string]::IsNullOrEmpty($p.elements.decimal)) {$ValueType = 'Decimal'}
            $([string]::IsNullOrEmpty($p.elements.enum)) {$ValueType = 'Decimal'}
            $([string]::IsNullOrEmpty($p.elements.text)) {$ValueType = 'String'}
            $([string]::IsNullOrEmpty($p.elements.list)) {$ValueType = 'String'}
            $([string]::IsNullOrEmpty($p.elements.multiText)) {$ValueType = 'String'}
            default {$ValueType = $p.elements}
        
        }
        $PolicyParent = $p.parentcategory.ref
        $PolicySetting = $p.Name
        $GPOSettingText = $StringHashTable.Get_Item($PolicySetting).InnerXML
        
        $PolicyParentCategory = $CategoryHashTable.Get_Item($PolicyParent)
        $PolicyParentCategoryName = $PolicyParentCategory.Name
        $PolicyParentCategoryDisplayName = $PolicyParentCategory.displayName.Substring(9).Replace(')','')
        $GPOSection = $StringHashTable.Get_Item($PolicyParentCategoryDisplayName).InnerXML

        #Create OMA-URI and equivalent GPO Path variables
        If ($GPOSection -eq "Google Chrome") {
            $GPOPath = "$PolicyClass/$GPOSection/$GPOSettingText"
        } Else {
            $GPOPath = "$PolicyClass/Google Chrome/$GPOSection/$GPOSettingText"
        }

        If ($PolicyParentCategoryName -eq 'googlechrome') {
            $OMAURIPrefix = "./Device/Vendor/MSFT/Policy/Config/$GPOName~Policy~$PolicyParentCategoryName/$PolicySetting"
        } Else {
            $OMAURIPrefix = "./Device/Vendor/MSFT/Policy/Config/$GPOName~Policy~googlechrome~$PolicyParentCategoryName/$PolicySetting"
        }

        #Add entry to results
        $results += [pscustomobject] @{
            'GPO Setting' = $GPOPath
            'OMA-URI' = $OMAURIPrefix   
            'Value Type' = $ValueType
        }
    }
    Write-Host "Displaying results"
    $results|Out-GridView

} Else {
    Write-Error "Could not find one of $ADMXFile or $ADMLFile"
}
