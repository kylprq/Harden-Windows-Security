Function Update-Self {
    <#
    .SYNOPSIS
        Make sure the latest version of the module is installed and if not, automatically update it, clean up any old versions
    .PARAMETER InvocationStatement
        The command that was used to invoke the main function/cmdlet that invoked the Update-Self function, this is used to re-run the command after the module has been updated.
        It checks to make sure the Update-Self function was called by an authorized command, that is one of the main cmdlets of the WDACConfig module, otherwise it will throw an error.
        The parameter also shouldn't contain any backtick or semicolon characters used to chain commands together.
    .NOTES
        Even if the main cmdlets of the module are called with semicolons like this: Get-Date;New-WDACConfig -GetDriverBlockRules -Verbose -Deploy;Get-Host
        Since the Update-Self function only receives the invocation statement from the main cmdlet/function, anything before or after the semicolons are automatically dropped and will not run after the module is auto updated.
        So from the example above, only this part gets executed after auto update: New-WDACConfig -GetDriverBlockRules -Verbose -Deploy
        The ValidatePattern attribute is just an extra layer of security.
    .INPUTS
        System.String
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidatePattern('^(Confirm-WDACConfig|Deploy-SignedWDACConfig|Edit-SignedWDACConfig|Edit-WDACConfig|Invoke-WDACSimulation|New-DenyWDACConfig|New-KernelModeWDACConfig|New-SupplementalWDACConfig|New-WDACConfig|Remove-WDACConfig|Assert-WDACConfigIntegrity|Build-WDACCertificate|Get-CiFileHashes|ConvertTo-WDACPolicy)(?!.*[;`]).*$', ErrorMessage = 'Either Update-Self function was called with an unauthorized command or it contains semicolon and/or backtick')]
        [System.String]$InvocationStatement
    )
    . "$ModuleRootPath\CoreExt\PSDefaultParameterValues.ps1"

    try {
        # Get the last update check time
        Write-Verbose -Message 'Getting the last update check time'
        [System.DateTime]$UserConfigDate = Get-CommonWDACConfig -LastUpdateCheck
    }
    catch {
        # If the User Config file doesn't exist then set this flag to perform online update check
        Write-Verbose -Message 'No LastUpdateCheck was found in the user configurations, will perform online update check'
        [System.Boolean]$PerformOnlineUpdateCheck = $true
    }

    # Ensure these are run only if the User Config file exists and contains a date for last update check
    if (!$PerformOnlineUpdateCheck) {
        # Get the current time
        [System.DateTime]$CurrentDateTime = Get-Date
        # Calculate the minutes elapsed since the last online update check
        [System.Int64]$TimeDiff = ($CurrentDateTime - $UserConfigDate).TotalMinutes
    }

    # Only check for updates if the last attempt occurred more than 10 minutes ago or the User Config file for last update check doesn't exist
    # This prevents the module from constantly doing an update check by fetching the version file from GitHub
    if (($TimeDiff -gt 10) -or $PerformOnlineUpdateCheck) {

        Write-Verbose -Message "Performing online update check because the last update check was performed $($TimeDiff ?? [System.Char]::ConvertFromUtf32(8734)) minutes ago"

        [System.Version]$CurrentVersion = (Test-ModuleManifest -Path "$ModuleRootPath\WDACConfig.psd1").Version.ToString()
        try {
            # First try the GitHub source
            [System.Version]$LatestVersion = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/HotCakeX/Harden-Windows-Security/main/WDACConfig/version.txt' -ProgressAction SilentlyContinue
        }
        catch {
            try {
                # If GitHub source is unavailable, use the Azure DevOps source
                [System.Version]$LatestVersion = Invoke-RestMethod -Uri 'https://dev.azure.com/SpyNetGirl/011c178a-7b92-462b-bd23-2c014528a67e/_apis/git/repositories/5304fef0-07c0-4821-a613-79c01fb75657/items?path=/WDACConfig/version.txt' -ProgressAction SilentlyContinue
            }
            catch {
                Throw [System.Security.VerificationException] 'Could not verify if the latest version of the module is installed, please check your Internet connection. You can optionally bypass the online check by using -SkipVersionCheck parameter.'
            }
        }

        # Reset the last update timer to the current time
        Write-Verbose -Message 'Resetting the last update timer to the current time'
        Set-CommonWDACConfig -LastUpdateCheck $(Get-Date) | Out-Null

        if ($CurrentVersion -lt $LatestVersion) {

            Write-Output -InputObject "$($PSStyle.Foreground.FromRGB(255,0,230))The currently installed module's version is $CurrentVersion while the latest version is $LatestVersion - Auto Updating the module...$($PSStyle.Reset)"

            # Remove the old module version from the current session
            Remove-Module -Name 'WDACConfig' -Force

            # Do this if the module was installed properly using Install-module cmdlet
            try {
                Uninstall-Module -Name 'WDACConfig' -AllVersions -Force -ErrorAction Stop
                Install-Module -Name 'WDACConfig' -RequiredVersion $LatestVersion -Scope AllUsers -Force
                # Will not import the new module version in the current session because of the constant variables. New version is automatically imported when the main cmdlet is run in a new session.
            }
            # Do this if module files/folder was just copied to Documents folder and not properly installed - Should rarely happen
            catch {
                Install-Module -Name 'WDACConfig' -RequiredVersion $LatestVersion -Scope AllUsers -Force
                # Will not import the new module version in the current session because of the constant variables. New version is automatically imported when the main cmdlet is run in a new session.
            }
            # Make sure the old version isn't run after update
            Write-Output -InputObject "$($PSStyle.Foreground.FromRGB(152,255,152))Update has been successful, running your command now$($PSStyle.Reset)"

            try {
                # Try to re-run the command that invoked the Update-Self function in a new session after the module is updated.
                pwsh.exe -NoLogo -NoExit -command $InvocationStatement
            }
            catch {
                Throw 'Could not relaunch PowerShell after update. Please close and reopen PowerShell to run your command again.'
            }
        }
    }
    else {
        Write-Verbose -Message "Skipping online update check because the last update check was performed $TimeDiff minutes ago"
    }
}
Export-ModuleMember -Function 'Update-Self'

# SIG # Begin signature block
# MIILkgYJKoZIhvcNAQcCoIILgzCCC38CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAh3DXuGdyMpjKW
# YlosHiFXyXBgrtC0NyjhDlUiJ0tEw6CCB9AwggfMMIIFtKADAgECAhMeAAAABI80
# LDQz/68TAAAAAAAEMA0GCSqGSIb3DQEBDQUAME8xEzARBgoJkiaJk/IsZAEZFgNj
# b20xIjAgBgoJkiaJk/IsZAEZFhJIT1RDQUtFWC1DQS1Eb21haW4xFDASBgNVBAMT
# C0hPVENBS0VYLUNBMCAXDTIzMTIyNzExMjkyOVoYDzIyMDgxMTEyMTEyOTI5WjB5
# MQswCQYDVQQGEwJVSzEeMBwGA1UEAxMVSG90Q2FrZVggQ29kZSBTaWduaW5nMSMw
# IQYJKoZIhvcNAQkBFhRob3RjYWtleEBvdXRsb29rLmNvbTElMCMGCSqGSIb3DQEJ
# ARYWU3B5bmV0Z2lybEBvdXRsb29rLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAKb1BJzTrpu1ERiwr7ivp0UuJ1GmNmmZ65eckLpGSF+2r22+7Tgm
# pEifj9NhPw0X60F9HhdSM+2XeuikmaNMvq8XRDUFoenv9P1ZU1wli5WTKHJ5ayDW
# k2NP22G9IPRnIpizkHkQnCwctx0AFJx1qvvd+EFlG6ihM0fKGG+DwMaFqsKCGh+M
# rb1bKKtY7UEnEVAsVi7KYGkkH+ukhyFUAdUbh/3ZjO0xWPYpkf/1ldvGes6pjK6P
# US2PHbe6ukiupqYYG3I5Ad0e20uQfZbz9vMSTiwslLhmsST0XAesEvi+SJYz2xAQ
# x2O4n/PxMRxZ3m5Q0WQxLTGFGjB2Bl+B+QPBzbpwb9JC77zgA8J2ncP2biEguSRJ
# e56Ezx6YpSoRv4d1jS3tpRL+ZFm8yv6We+hodE++0tLsfpUq42Guy3MrGQ2kTIRo
# 7TGLOLpayR8tYmnF0XEHaBiVl7u/Szr7kmOe/CfRG8IZl6UX+/66OqZeyJ12Q3m2
# fe7ZWnpWT5sVp2sJmiuGb3atFXBWKcwNumNuy4JecjQE+7NF8rfIv94NxbBV/WSM
# pKf6Yv9OgzkjY1nRdIS1FBHa88RR55+7Ikh4FIGPBTAibiCEJMc79+b8cdsQGOo4
# ymgbKjGeoRNjtegZ7XE/3TUywBBFMf8NfcjF8REs/HIl7u2RHwRaUTJdAgMBAAGj
# ggJzMIICbzA8BgkrBgEEAYI3FQcELzAtBiUrBgEEAYI3FQiG7sUghM++I4HxhQSF
# hqV1htyhDXuG5sF2wOlDAgFkAgEIMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1Ud
# DwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFOlnnQDHNUpYoPqECFP6JAqGDFM6MB8GA1UdIwQYMBaA
# FICT0Mhz5MfqMIi7Xax90DRKYJLSMIHUBgNVHR8EgcwwgckwgcaggcOggcCGgb1s
# ZGFwOi8vL0NOPUhPVENBS0VYLUNBLENOPUhvdENha2VYLENOPUNEUCxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPU5vbkV4aXN0ZW50RG9tYWluLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwgccG
# CCsGAQUFBwEBBIG6MIG3MIG0BggrBgEFBQcwAoaBp2xkYXA6Ly8vQ049SE9UQ0FL
# RVgtQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZp
# Y2VzLENOPUNvbmZpZ3VyYXRpb24sREM9Tm9uRXhpc3RlbnREb21haW4sREM9Y29t
# P2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5MA0GCSqGSIb3DQEBDQUAA4ICAQA7JI76Ixy113wNjiJmJmPKfnn7brVI
# IyA3ZudXCheqWTYPyYnwzhCSzKJLejGNAsMlXwoYgXQBBmMiSI4Zv4UhTNc4Umqx
# pZSpqV+3FRFQHOG/X6NMHuFa2z7T2pdj+QJuH5TgPayKAJc+Kbg4C7edL6YoePRu
# HoEhoRffiabEP/yDtZWMa6WFqBsfgiLMlo7DfuhRJ0eRqvJ6+czOVU2bxvESMQVo
# bvFTNDlEcUzBM7QxbnsDyGpoJZTx6M3cUkEazuliPAw3IW1vJn8SR1jFBukKcjWn
# aau+/BE9w77GFz1RbIfH3hJ/CUA0wCavxWcbAHz1YoPTAz6EKjIc5PcHpDO+n8Fh
# t3ULwVjWPMoZzU589IXi+2Ol0IUWAdoQJr/Llhub3SNKZ3LlMUPNt+tXAs/vcUl0
# 7+Dp5FpUARE2gMYA/XxfU9T6Q3pX3/NRP/ojO9m0JrKv/KMc9sCGmV9sDygCOosU
# 5yGS4Ze/DJw6QR7xT9lMiWsfgL96Qcw4lfu1+5iLr0dnDFsGowGTKPGI0EvzK7H+
# DuFRg+Fyhn40dOUl8fVDqYHuZJRoWJxCsyobVkrX4rA6xUTswl7xYPYWz88WZDoY
# gI8AwuRkzJyUEA07IYtsbFCYrcUzIHME4uf8jsJhCmb0va1G2WrWuyasv3K/G8Nn
# f60MsDbDH1mLtzGCAxgwggMUAgEBMGYwTzETMBEGCgmSJomT8ixkARkWA2NvbTEi
# MCAGCgmSJomT8ixkARkWEkhPVENBS0VYLUNBLURvbWFpbjEUMBIGA1UEAxMLSE9U
# Q0FLRVgtQ0ECEx4AAAAEjzQsNDP/rxMAAAAAAAQwDQYJYIZIAWUDBAIBBQCggYQw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQx
# IgQgPsr7mha1uvo8aMFJiwvG1SgrN65IJiwMMA/d4bdFgyMwDQYJKoZIhvcNAQEB
# BQAEggIAVq0i/NE7AxL11WwN3+A6m5eqRrbqGjf6Tk6pFC+Xi+6PGlPOaAZOUGaI
# GgRBr6L0EEHirYUkkovYL9u3nwIEVe+4s1+L436SzSj9ufaMR+Uj4K8tBrKBgYVO
# EESvkc/2MzbCmqrw9R/BAZw0NP8DK1GNWGOYyV7WkzklUiHApHxrJc0W8MY7/uKa
# 9ETwbu7fKDsbTzIZSDys6Ep6wPe4Gsgg3m5QIQ6BTJ0D5NQLWAieHaGoVeEHM2ct
# mDxaKXk5JlRBzXyTWgOfGBFcGoFI66qtU85G8tXfhLAh7So8ybTgh+wTQzNx2m/S
# L46OzXvUYWSNAbDPSIRV7FkrLKYgueEC9nsGAt8bh57pv1B38eV2qbP4/RCOg6u7
# m41/lAQYmp63J6nYua/0vGsFM4S3FhNZqsEIZvg3in69/6T3WwF5e3pPCU2UtIBa
# MnMB42A9F3xEHQob5+nsv3TgP3rAIdtws36OOACEDaoqenhyKyy8sQL9hArBdn7c
# Ay8zjYIIjIx4yt4hHHHqlaVlQnNmCItrtFETxsI/Qy64KQpD2aqy57rXAsldIf7k
# ESbB9h+me34YYliJjJl3QG6qcBQvn+1gsSYX0iRjL3b+iHJAAWdBF7jITkjZ+mFG
# DD7aUj2U6aXHNyw4SDwFsGKdB28ZINdAOTwW2iNSvPVUJyeqE68=
# SIG # End signature block
