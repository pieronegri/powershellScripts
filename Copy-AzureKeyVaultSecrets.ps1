<# comment on the 2025-12-05
modifica da dev VA
nuova modifica
.SYNOPSIS
This script copies secrets from one Azure Key Vault to another. Credits to pages /individuals mentioned in the Link section

.DESCRIPTION
The script connects to Azure and retrieves the secrets from the source Key Vault. 
It then copies these secrets to the destination Key Vault. 
You can specify a subset of secrets to copy using the -SecretArrayInput parameter, 
or copy all secrets using the -AllKeyVaultSecrets switch.

.PARAMETER SourceSubscriptionName
The name of the source subscription.

.PARAMETER SourceResourceGroupName
The name of the resource group of the source Key Vault.

.PARAMETER SourceKeyVaultName
The name of the source Key Vault.

.PARAMETER DestSubscriptionName
The name of the destination subscription. If not set or blank then same subscription is assumed.

.PARAMETER DestResourceGroupName
The name of the resource group of the destination Key Vault. If not set or blank then same resource group is assumed.

.PARAMETER DestKeyVaultName
The name of the destination Key Vault. If not set or blank then same subscription is assumed.

.PARAMETER SecretArrayInput
An array of secret names to copy. Cannot be used with -AllKeyVaultSecrets.

.PARAMETER AllKeyVaultSecrets
If this switch is present, all secrets will be copied. Cannot be used with -SecretArrayInput.

.PARAMETER NameOnly
If this switch is present, the secret value will be set to the value present in DefaultSecretValue parameter. sourceSecretVersionMigrated will be assigned value "N/A"

.PARAMETER DefaultSecretValue
The default value for secrets when NameOnly is present. Defaults to 'Needs Configuration' if not provided.

.PARAMETER DoNotEnhanceSecretTag
If this switch is NOT present, to the source secret tag will be added the following tags: -Migrated='true' -SourceVault=SourceKeyVaultName -sourceSecretVersionMigrated=secret.Version or "N/A" if NameOnly is present -ValueMigrated to 'true' if NameOnly is not present and to 'false' viceversa.

.PARAMETER Force
If this switch is present, secrets in SourceKeyVaultName will override those in DestKeyVaultName with the same name.

.EXAMPLE
PS> .\CopyKeyVaultSecrets.ps1 -SourceSubscriptionName 'source-suscriptionName' -SourceResourceGroupName 'source-groupName' -SourceKeyVaultName 'source-vault' -DestKeyVaultName 'dest-vault' -SecretArrayInput 'secret1', 'secret2'

This command copies the secrets named 'secret1' and 'secret2' from 'source-vault' to 'dest-vault'.

.LINK
https://stackoverflow.com/a/55618194/8394315
https://nicholasrogoff.com/2021/08/09/azure-key-vault-script-for-copying-secrets-from-one-to-another/
#>

Param(
    [Parameter(Mandatory = $true, HelpMessage = "This is the Source Subscription Name")]
    [string] $SourceSubscriptionName,
    [Parameter(Mandatory = $true, HelpMessage = "This is the Source Resource Group Name")]
    [string] $SourceResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "This is the Source Key Vault Name")]
    [string] $SourceKeyVaultName,
    [Parameter(Mandatory = $false, HelpMessage = "This is the Destination Subscription Name. If not set or blank then same subscription is assumed")]
    [string] $DestSubscriptionName,
    [Parameter(Mandatory = $false, HelpMessage = "This is the Destination Resource Group Name. If not set or blank then same resource group is assumed")]
    [string] $DestResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "This is the Destination Key Vault Name")]
    [string] $DestKeyVaultName,
    [Parameter(Mandatory=$false, HelpMessage = "An array of secret names to copy. Cannot be used with -AllKeyVaultSecrets")]
    [string[]] $SecretArrayInput,
    [Parameter(Mandatory=$false, HelpMessage = "If this switch is present, all secrets will be copied. Cannot be used with -SecretArrayInput")]
    [switch] $AllKeyVaultSecrets,
    [Parameter(Mandatory=$false, HelpMessage = "If this switch is present, the secret value will be set to the value present in DefaultSecretValue parameter")]
    [switch] $NameOnly,
    [Parameter(Mandatory=$false, HelpMessage = "The default value for secrets when NameOnly is present. Defaults to 'Needs Configuration' if not provided")]
    [string] $DefaultSecretValue = 'Needs Configuration',
    [Parameter(Mandatory=$false, HelpMessage = "If this switch is present, to the source secret tag will be added the following tags: -Migrated='true' -SourceVault=SourceKeyVaultName and -ValueMigrated to 'true' if NameOnly is not present and to 'false' viceversa")]
    [switch] $DoNotEnhanceSecretTag,
    [Parameter(Mandatory=$false, HelpMessage = "If this switch is present, further tags will not be added")]
    [switch] $Force
)


#---------------------------------------------------------[Initialisations]--------------------------------------------------------

$ForegroundColor="Yellow"
if (! $DestSubscriptionName) {
  $DestSubscriptionName = $SourceSubscriptionName
}

Write-Host ("{0} Source Subscription {1} Dest Subscription {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), `
                                                                    $SourceSubscriptionName, `
                                                                    $DestSubscriptionName `
                                                                   ) `
                                                                 -ForegroundColor $ForegroundColor

if (! $DestResourceGroupName) {
  $DestResourceGroupName=$SourceResourceGroupName
}

Write-Host ("Source ResourceGroup {0} Dest ResourceGroup {1}" -f $SourceResourceGroupName, $DestResourceGroupName) -ForegroundColor Yellow


Write-Host ("Source KeyVault {0} Dest KeyVault {1}... " -f $SourceKeyVaultName, `
                                                           $DestKeyVaultName) `
                                                           -ForegroundColor $ForegroundColor


# Set Error Action to Silently Continue
$ErrorActionPreference = 'Continue'

$success = 0
$failed = 0



#---------------------------------------------------------[Parameter Validations]--------------------------------------------------------


if ($AllKeyVaultSecrets.IsPresent -and $SecretArrayInput) {
    Write-Error "Parameters AllKeyVaultSecrets and SecretArrayInput cannot be specified at the same time."
    return
} elseif (-not $AllKeyVaultSecrets.IsPresent -and -not $SecretArrayInput) {
    Write-Error "Either AllKeyVaultSecrets or SecretArrayInput must be specified."
    return
}

if ($DefaultSecretValue -ne 'Needs Configuration' -and !$NameOnly.IsPresent) {
    Write-Error "Parameter DefaultSecretValue can only be specified if NameOnly is present."
    return
}

if ($SourceKeyVaultName -eq $DestKeyVaultName) {
    Write-Error "SourceKeyVaultName and DestKeyVaultName must be different!"
    return
}


$context = Get-AzContext

if ($context -eq $null) {
    # Not connected, so connect
    Connect-AzAccount
}

#---------------------------------------------------------[Parameter Validations After Connection]--------------------------------------------------------

# ensure source subscription is selected
Select-AzSubscription -Subscription $SourceSubscriptionName

#is Source Key Vault Existing?

if ($(Get-AzKeyVault -ResourceGroupName $SourceResourceGroupName -VaultName $SourceKeyVaultName) -eq $null) {
    Write-Error "Key Vault $SourceKeyVaultName does not exist."
    return
} 

#---------------------------------------------------------[sourceSecrets Initialization]--------------------------------------------------------

$sourceSecrets = Get-AzKeyVaultSecret -VaultName $SourceKeyVaultName


Select-AzSubscription -Subscription $DestSubscriptionName

if (! $DestResourceGroupName) {
  $DestResourceGroupName=$SourceResourceGroupName
}

#is Dest Key Vault Existing?
if ($(Get-AzKeyVault  -ResourceGroupName $DestResourceGroupName -VaultName $SourceKeyVaultName) -eq $null) {
    Write-Error "Key Vault $SourceKeyVaultName does not exist."
    return
} 

if(! $Force.isPresent){
    $destSecrets = Get-AzKeyVaultSecret -VaultName $DestKeyVaultName
    Write-Host "Filter out the secrets that are in destSecrets"
    # Filter out the secrets that are already in destSecrets
    $sourceSecrets = $sourceSecrets | Where-Object { $destSecrets.Name -notcontains $_.Name }
}
else{
    Write-Host "secrets in destSecrets with the same name than those in source secrets will be overwritten"
}


if (! $AllKeyVaultSecrets.IsPresent) {
    $sourceSecrets = $sourceSecrets | Where-Object { $SecretArrayInput -contains $_.Name }
}

#---------------------------------------------------------[DO]---------------------------------------------------------
ForEach ($sourceSecret in $sourceSecrets) {
  $Error.clear()

  $name = $sourceSecret.Name
  $tags = $sourceSecret.Tags

  Write-Host ("Adding SecretName: {0} ..." -f $sourceSecret.Name) -ForegroundColor $ForegroundColor
  
  
  if ($NameOnly.IsPresent) {
    $value = ConvertTo-SecureString $DefaultSecretValue -AsPlainText -Force
    $sourceSecretVersionMigrated="N/A"
    Write-Host "Adding $DefaultSecretValue as secret value and $sourceSecretVersionMigrated as secretVersion" -ForegroundColor $ForegroundColor
  }
  else {
    Write-Host "Adding secret value from the source key vault" -ForegroundColor $ForegroundColor
    Write-Host "Fetching the secret from the KeyVault for further info"  -ForegroundColor $ForegroundColor    
    $secretFetchedAgain=Get-AzKeyVaultSecret -VaultName $SourceKeyVaultName -Name $sourceSecret.Name
    $value = $secretFetchedAgain.SecretValue
    $sourceSecretVersionMigrated=$secretFetchedAgain.Version
  }

  if(! $DoNotEnhanceSecretTag.IsPresent){
      Write-Host "Adding Enhanced Tags  to existing ones" -ForegroundColor $ForegroundColor
      $tags.Migrated='true';
      $tags.SourceVault=$SourceKeyVaultName
      $tags.ValueMigrated=(!$NameOnly.IsPresent).ToString()
      $tags.SourceSecretVersionMigrated=$sourceSecretVersionMigrated
      
  }
  
  
  $secret = Set-AzKeyVaultSecret -VaultName $DestKeyVaultName `
                                 -Name $sourceSecret.Name `
                                 -SecretValue $value `
                                 -ContentType $sourceSecret.ContentType `
                                 -Expires $sourceSecret.Expires `
                                 -NotBefore $sourceSecret.NotBefore `
                                 -Tags $tags 
  
  if (!$Error[0]) {
    $message="Success to copy secret {0}" -f $sourceSecret.Name 
    $success += 1
  }
  else {
    $failed += 1
    $message= "!! Failed to copy secret {0}" -f $sourceSecret.Name
  }
  Write-Host $message -ForegroundColor $ForegroundColor
}

Write-Output "================================="
Write-Output "Completed Key Vault Secrets Copy"
Write-Output "Succeeded: $success"
Write-Output "Failed: $failed"
Write-Output "================================="
