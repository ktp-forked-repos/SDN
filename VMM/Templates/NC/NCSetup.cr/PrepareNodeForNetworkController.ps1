﻿Param($mgmtDomainAccountUserName, $SSLCertificatePassword)

. ./Helpers.ps1

# Stops script execution on first error
$ErrorActionPreference = "stop"

# Exit Codes
$ErrorCode_Success = 0
$ErrorCode_Failed = 1

try 
{
    #------------------------------------------
    # Disable IPv6, as it is not supported by NC for TP4
    #------------------------------------------
    Log "Disabling IPv6 on network adapter.."
    $nicName = $(Get-NetAdapter).Name
    Disable-NetAdapterBinding -Name $nicName -ComponentID "ms_tcpip6"
    New-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\" -Name "DisabledComponents" -Value 0xffffffff -PropertyType "DWord" -Force
    ipconfig /registerdns
    
    #------------------------------------------
    # Install windows features + cmdlet module
    #------------------------------------------        
    Log "Installing NetworkController Role.."
    Add-WindowsFeature -Name NetworkController -IncludeManagementTools
    
    #------------------------------------------
    # Add the domain account as local admin on this machine
    #------------------------------------------
    Log "Adding $mgmtDomainAccountUserName to local admin group.."
    AddToAdministrators $mgmtDomainAccountUserName
    
    Log "Adding trusted hosts"
    Set-Item wsman:\localhost\Client\TrustedHosts -value * -Force
    
    #------------------------------------------
    # Find and install SSL Certificate
    #------------------------------------------
    $sslCertPath = "C:\NCInstall\certificate-ssl\"
    Log "Finding certificate file in script directory. '$sslCertPath'"
    $sslCertFile = Get-ChildItem $sslCertPath -Recurse -Exclude @("SCVMMCRTag.cr")
    
    if($sslCertFile -ne $null)
    {
        Log "Found certificate at path: $($sslCertFile.FullName)"
        Log "Adding certificate to personal store.."
        AddCertToLocalMachineStore $sslCertFile.FullName "My" $SSLCertificatePassword $true
        
        $sslThumbprint = GetSSLCertificateThumbprint
        $installedSSLCert = Get-Item Cert:\LocalMachine\My | Get-ChildItem | where {$_.Thumbprint -eq $sslThumbprint}
        if($installedSSLCert.Issuer -eq $installedSSLCert.Subject)
        {
            Log "SSL Cert is self-signed."
            Log "Adding certificate to root store.."
            AddCertToLocalMachineStore $sslCertFile.FullName "Root" $SSLCertificatePassword
        }
        
        Log "Adding read permission to NetworkService account"
        GivePermissionToNetworkService $installedSSLCert
    }
    else 
    {
        Log "Error: Did not find an SSL certificate file deployed to VM."
        Log "    Please create a valid certificate and include in the SSL certificate.cr custom resource folder."
        Exit $ErrorCode_Failed 
    }
    
    #------------------------------------------
    # Find and install trusted root certificate
    #------------------------------------------
    $rootCertPath = "C:\NCInstall\certificate-root\"
    Log "Finding certificate file in script directory. '$rootCertPath'"
    $rootCertFile = Get-ChildItem $rootCertPath -Recurse -Exclude @("SCVMMCRTag.cr")
    
    if($rootCertFile -ne $null)
    {
        Log "Found certificate at path: $($rootCertFile.FullName)"
        Log "Adding certificate to root store.."
        AddCertToLocalMachineStore $rootCertFile.FullName "Root"
    }
    else 
    {
        Log "Did not find any root certificates. Skipping import."
    }
}
catch 
{
    Log "Caught an exception:"
    Log "    Exception Type: $($_.Exception.GetType().FullName)"
    Log "    Exception Message: $($_.Exception.Message)"
    Log "    Exception HResult: $($_.Exception.HResult)"
    Exit $($_.Exception.HResult)
}  

Log "Completed execution of script."
Exit $ErrorCode_Success 