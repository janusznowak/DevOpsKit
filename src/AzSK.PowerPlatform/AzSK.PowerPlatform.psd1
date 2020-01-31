﻿#
# Module manifest for module 'AzSK.PowerPlatform'
#
# Generated by: Microsoft AzSK Team
#
# Generated on: 2020-Jan-01
#

@{

    # Script module or binary module file associated with this manifest.
    RootModule             = '.\AzSK.PowerPlatform.psm1'

    # Version number of this module. (Placeholder, updated from release pipeline.)
    ModuleVersion          = '1.0.0.0'

    # ID used to uniquely identify this module
    GUID                   = '11299a7c-4c12-4b8b-9f9b-a72cded3f582'

    # Author of this module
    Author                 = 'AzSK Team'

    # Company or vendor of this module
    CompanyName            = 'Microsoft Corporation'

    # Copyright statement for this module
    Copyright              = '(c) 2020 Microsoft Corporation. All rights reserved.'

    # Description of the functionality provided by this module
    Description            = 'Security Scanner for Power Platform - Preview'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion      = '5.0'

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module
    DotNetFrameworkVersion = '4.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion             = '4.0'

    # Processor architecture (None, X86, Amd64) required by this module
    ProcessorArchitecture  = 'None'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules        = @('Microsoft.PowerApps.Administration.PowerShell','Microsoft.PowerApps.PowerShell')

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @('.\Lib\Newtonsoft.Json.dll','.\Lib\Microsoft.ApplicationInsights.dll','.\Lib\Microsoft.IdentityModel.Clients.ActiveDirectory.dll')

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess       = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules          = @()
  
    # Functions to export from this module
    FunctionsToExport      = @(
        'Get-AzSKPowerPlatformSecurityStatus',
        'Set-AzSKPowerPlatformPolicySettings'
    )

    # Cmdlets to export from this module
    CmdletsToExport        = @()

    # Variables to export from this module
    VariablesToExport      = '*'

    # Aliases to export from this module
    # AliasesToExport      = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData            = @{
        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = 'PowerPlatform', 'AzSK', 'PowerApps', 'Flow', 'PowerAutomate','Automate'

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/azsk/azsk-docs/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/azsk/azsk-docs'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = '
		* Security scanner for Microsoft Power Platform artifacts such as:
            * PowerPlatform Tenant
            * PowerApps
            * Flows
            * Connectors
            * Connections
            * Etc. '

        }
    } # End of PSData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    DefaultCommandPrefix   = ''
	
}
