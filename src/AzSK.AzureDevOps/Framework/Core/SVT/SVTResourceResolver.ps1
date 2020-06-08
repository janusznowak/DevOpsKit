Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot {
    [string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
    [Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string[]] $TagValue = "";
    hidden [string[]] $ResourceGroups = @();
    [ResourceTypeName] $ExcludeResourceTypeName = [ResourceTypeName]::All;
    [string[]] $ExcludeResourceNames = @();
    [SVTResource[]] $ExcludedResources = @();
    [int] $MaxObjectsToScan;
    [string] $ExcludeResourceWarningMessage = [string]::Empty
    [string[]] $ExcludeResourceGroupNames = @();
    [string[]] $ExcludedResourceGroupNames = @();
    [string] $ExcludeResourceGroupWarningMessage = [string]::Empty
    [SVTResource[]] $SVTResources = @();
    [int] $SVTResourcesFoundCount = 0;
    
    [string] $ResourcePath;
    [string] $organizationName
    hidden [string[]] $ProjectNames = @();
    hidden [string[]] $BuildNames = @();
    hidden [string[]] $ReleaseNames = @();
    hidden [string[]] $AgentPools = @();
    hidden [string[]] $ServiceConnections = @();
    SVTResourceResolver([string]$organizationName, $ProjectNames, $BuildNames, $ReleaseNames, $AgentPools, $ScanAllArtifacts, $PATToken, $ResourceTypeName): Base($organizationName, $PATToken) {
        $this.SetallTheParamValues($organizationName, $ProjectNames, $BuildNames, $ReleaseNames, $AgentPools, $ScanAllArtifacts, $PATToken, $ResourceTypeName);
    }

    SVTResourceResolver([string]$organizationName, $ProjectNames, $BuildNames, $ReleaseNames, $AgentPools, $ServiceConnectionNames, $MaxObj, $ScanAllArtifacts, $PATToken, $ResourceTypeName): Base($organizationName, $PATToken) {
        $this.MaxObjectsToScan = $MaxObj #default = 0 => scan all if "*" specified...

        if (-not [string]::IsNullOrEmpty($ServiceConnectionNames)) {
            $this.ServiceConnections += $this.ConvertToStringArray($ServiceConnectionNames);

            if ($this.ServiceConnections.Count -eq 0) {
                throw [SuppressedException] "The parameter 'ServiceConnectionNames' does not contain any string."
            }
        }	

        if ($ScanAllArtifacts -or ([string]::IsNullOrEmpty($ServiceConnectionNames) -and $ResourceTypeName -eq [ResourceTypeName]::ServiceConnection )) {
            $this.ServiceConnections = "*"
        }

        $this.SetallTheParamValues($organizationName, $ProjectNames, $BuildNames, $ReleaseNames, $AgentPools, $ScanAllArtifacts, $PATToken, $ResourceTypeName);
                
    }

    [void] SetallTheParamValues([string]$organizationName, $ProjectNames, $BuildNames, $ReleaseNames, $AgentPools, $ScanAllArtifacts, $PATToken, $ResourceTypeName) { 
        $this.organizationName = $organizationName
        $this.ResourceTypeName = $ResourceTypeName

        if (-not [string]::IsNullOrEmpty($ProjectNames)) {
            $this.ProjectNames += $this.ConvertToStringArray($ProjectNames);

            if ($this.ProjectNames.Count -eq 0) {
                throw [SuppressedException] "The parameter 'ProjectNames' does not contain any string."
            }
        }
        elseif ($ResourceTypeName -eq [ResourceTypeName]::Project) {
            $this.ProjectNames = "*"
        }	

        if (-not [string]::IsNullOrEmpty($BuildNames)) {
            $this.BuildNames += $this.ConvertToStringArray($BuildNames);
            if ($this.BuildNames.Count -eq 0) {
                throw [SuppressedException] "The parameter 'BuildNames' does not contain any string."
            }
        }
        elseif ($ResourceTypeName -eq [ResourceTypeName]::Build -or $ResourceTypeName -eq [ResourceTypeName]::Build_Release) {
            $this.BuildNames = "*"
        }

        if (-not [string]::IsNullOrEmpty($ReleaseNames)) {
            $this.ReleaseNames += $this.ConvertToStringArray($ReleaseNames);
            if ($this.ReleaseNames.Count -eq 0) {
                throw [SuppressedException] "The parameter 'ReleaseNames' does not contain any string."
            }
        }
        elseif ($ResourceTypeName -eq [ResourceTypeName]::Release -or $ResourceTypeName -eq [ResourceTypeName]::Build_Release) {
            $this.ReleaseNames = "*"
        }

        if (-not [string]::IsNullOrEmpty($AgentPools)) {
            $this.AgentPools += $this.ConvertToStringArray($AgentPools);
            if ($this.AgentPools.Count -eq 0) {
                throw [SuppressedException] "The parameter 'AgentPools' does not contain any string."
            }
        }
        elseif ($ResourceTypeName -eq [ResourceTypeName]::AgentPool) {
            $this.AgentPools = "*"
        }

        if ($ScanAllArtifacts) {
            $this.ProjectNames = "*"
            $this.BuildNames = "*"
            $this.ReleaseNames = "*"
            $this.AgentPools = "*"
        }  

        if ($this.ProjectNames -eq "*" -or $this.BuildNames -eq "*" -or $this.ReleaseNames -eq "*" -or $this.ServiceConnections -eq "*" -or $this.AgentPools -eq "*") {
            $message = "";
            if($this.ProjectNames -eq "*") 
            {
                $message = "projects";
            }
            if($this.BuildNames -eq "*") 
            {
                if($message -ne ""){
                  $message += " ,builds";
                }
                else {
                    $message += "builds";
                }
            }
            if($this.ReleaseNames -eq "*") 
            {
                if($message -ne ""){
                 $message += " ,releases";
                }
                else {
                    $message += "releases"; 
                }
            }
            if($this.ServiceConnections -eq "*") 
            {
                if($message -ne ""){
                 $message += " ,service connections";
                }
                else {
                    $message += "service connections";
                }
            }
            if($this.AgentPools -eq "*") 
            {
                $message += " ,agent pools";
            }
            $this.PublishCustomMessage("Using '*' can take a long time for the scan to complete in larger projects. You may want to provide a comma-separated list of $($message).");
        }
    }

    [void] LoadResourcesForScan() {
        
        #Call APIS for Organization,User/Builds/Releases/ServiceConnections 
        if ($this.ResourceTypeName -in ([ResourceTypeName]::Organization, [ResourceTypeName]::All, [ResourceTypeName]::Org_Project_User)) {
            #Checking if org name is correct 
            $apiURL = "https://dev.azure.com/{0}/_apis/Contribution/HierarchyQuery?api-version=5.0-preview.1" -f $($this.organizationName);

            $inputbody = "{'contributionIds':['ms.vss-features.my-organizations-data-provider'],'dataProviderContext':{'properties':{'sourcePage':{'url':'https://dev.azure.com/$($this.organizationName)','routeId':'ms.vss-tfs-web.suite-me-page-route','routeValues':{'view':'projects','controller':'ContributedPage','action':'Execute'}}}}}" | ConvertFrom-Json
            try {
                $responseObj = [WebRequestHelper]::InvokePostWebRequest($apiURL, $inputbody);
                $inputbody = $null;
                Remove-Variable inputbody;
            }
            catch {
                Write-Host 'Organization not found: Incorrect organization name or you do not have neccessary permission to access the organization.' -ForegroundColor Red
                throw;
            }
           
            #Select Org/User by default...
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.organizationName;
            $svtResource.ResourceType = "AzureDevOps.Organization";
            $svtResource.ResourceId = "Organization/$($this.organizationName)/"
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                Select-Object -First 1)

            $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = $svtResource.ResourceId.Replace('Organization', 'https://dev.azure.com') + "_settings/"; }
            $this.SVTResources += $svtResource
            
        }

        if ($this.ResourceTypeName -in ([ResourceTypeName]::User, [ResourceTypeName]::All, [ResourceTypeName]::Org_Project_User, [ResourceTypeName]::Build_Release_SvcConn_AgentPool_User)) {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.organizationName;
            $svtResource.ResourceType = "AzureDevOps.User";
            $svtResource.ResourceId = "Organization/$($this.organizationName)/User"
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                Select-Object -First 1)
           
            $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = "https://dev.azure.com/$($this.organizationName)/_settings/users" }
            $this.SVTResources += $svtResource
        }

        #Get project resources
        if ($this.ProjectNames.Count -gt 0) {
            $this.PublishCustomMessage("Querying api for resources to be scanned. This may take a while...");

            $this.PublishCustomMessage("Getting project configurations...");

            $apiURL = "https://dev.azure.com/{0}/_apis/projects?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = "";
            try { 
                $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL) ;
            }
            catch {
                Write-Host 'Project not found: Incorrect organization or project name or you do not have neccessary permission to access the organization.' -ForegroundColor Red
                throw;
            }
            if($this.ProjectNames -eq "*")
            {
                $projects = $responseObj
            }
            else {
                $projects = $responseObj | Where-Object { $this.ProjectNames -contains $_.name } 
            }
            
            $responseObj = $null;  
            Remove-Variable responseObj;
            
            $nProj = $this.MaxObjectsToScan;
            if (!$projects) {
                Write-Host 'No project found to perform the scan.' -ForegroundColor Red
            }
            foreach ($thisProj in $projects) 
            {
                $projectName = $thisProj.name
                if ($this.ResourceTypeName -in ([ResourceTypeName]::Project, [ResourceTypeName]::All, [ResourceTypeName]::Org_Project_User)) {
                    $svtResource = [SVTResource]::new();
                    $svtResource.ResourceName = $thisProj.name;
                    $svtResource.ResourceGroupName = $this.organizationName
                    $svtResource.ResourceType = "AzureDevOps.Project";
                    $svtResource.ResourceId = $thisProj.url
                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                        Select-Object -First 1)
                
               
                    $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = ($svtResource.ResourceId.Replace('/_apis/projects', '') + '/_settings/') }
                    $this.SVTResources += $svtResource
                }

                if ($this.BuildNames.Count -gt 0 -and ($this.ResourceTypeName -in ([ResourceTypeName]::Build, [ResourceTypeName]::All, [ResourceTypeName]::Build_Release, [ResourceTypeName]::Build_Release_SvcConn_AgentPool_User))) {
                    if ($this.ProjectNames -ne "*") {
                        $this.PublishCustomMessage("Getting build configurations...");
                    }

                    if ($this.BuildNames -eq "*") {
                        $buildDefnURL = "https://dev.azure.com/{0}/{1}/_apis/build/definitions?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName), $thisProj.name;
                        $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                        if (([Helpers]::CheckMember($buildDefnsObj, "count") -and $buildDefnsObj[0].count -gt 0) -or (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0], "name"))) {
                            $nObj = $this.MaxObjectsToScan
                            foreach ($bldDef in $buildDefnsObj) {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $bldDef.name;
                                $svtResource.ResourceGroupName = $bldDef.project.name;
                                $svtResource.ResourceType = "AzureDevOps.Build";
                                $svtResource.ResourceId = $bldDef.url.split('?')[0];
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                    Select-Object -First 1)
                                $svtResource.ResourceDetails = $bldDef
                                $link = $svtResource.ResourceId.replace('_apis/build/Definitions/', '_build?definitionId=');
                                $svtResource.ResourceDetails | Add-Member -Name 'ResourceLink' -Type NoteProperty -Value $link;
                                $this.SVTResources += $svtResource

                                if (--$nObj -eq 0) { break; } 
                            }
                            $buildDefnsObj = $null;
                            Remove-Variable buildDefnsObj;
                        }
                    }
                    else {
                        $this.BuildNames | ForEach-Object {
                            $buildName = $_
                            $buildDefnURL = "https://{0}.visualstudio.com/{1}/_apis/build/definitions?name={2}&api-version=5.1-preview.7" -f $($this.SubscriptionContext.SubscriptionName), $projectName, $buildName;
                            $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                            if (([Helpers]::CheckMember($buildDefnsObj, "count") -and $buildDefnsObj[0].count -gt 0) -or (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0], "name"))) {
                                foreach ($bldDef in $buildDefnsObj) {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $bldDef.name;
                                    $svtResource.ResourceGroupName = $bldDef.project.name;
                                    $svtResource.ResourceType = "AzureDevOps.Build";
                                    $svtResource.ResourceId = $bldDef.url.split('?')[0];
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                        Select-Object -First 1)
      
                                    $link = $svtResource.ResourceId.replace('_apis/build/Definitions/', '_build?definitionId=');
                                    $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = $link }
                                                                                                     
                                    $this.SVTResources += $svtResource
                                }
                                $buildDefnsObj = $null;
                                Remove-Variable buildDefnsObj;
                            }
                        }
                    }          
                }

                if ($this.ReleaseNames.Count -gt 0 -and ($this.ResourceTypeName -in ([ResourceTypeName]::Release, [ResourceTypeName]::All, [ResourceTypeName]::Build_Release, [ResourceTypeName]::Build_Release_SvcConn_AgentPool_User)))
                {
                    if ($this.ProjectNames -ne "*") {
                        $this.PublishCustomMessage("Getting release configurations...");
                    }
                    if ($this.ReleaseNames -eq "*") 
                    {
                        $releaseDefnURL = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions?api-version=4.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                        $releaseDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($releaseDefnURL);
                        if (([Helpers]::CheckMember($releaseDefnsObj, "count") -and $releaseDefnsObj[0].count -gt 0) -or (($releaseDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($releaseDefnsObj[0], "name"))) {
                            $nObj = $this.MaxObjectsToScan
                            foreach ($relDef in $releaseDefnsObj) {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $relDef.name;
                                $svtResource.ResourceGroupName = $projectName;
                                $svtResource.ResourceType = "AzureDevOps.Release";
                                $svtResource.ResourceId = $relDef.url
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                    Select-Object -First 1)

                                $link = "https://dev.azure.com/{0}/{1}/_release?_a=releases&view=mine&definitionId={2}" -f $this.SubscriptionContext.SubscriptionName, $projectName, $svtResource.ResourceId.split('/')[-1];
                                $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = $link }
                                                                
                                $this.SVTResources += $svtResource

                                if (--$nObj -eq 0) { break; } 
                            }
                            $releaseDefnsObj = $null;
                        }
                    }
                    else {
                        try {
                            $this.ReleaseNames | ForEach-Object {
                                $resleaseName = $_
                                $releaseDefnURL = "https://{0}.vsrm.visualstudio.com/_apis/Contribution/HierarchyQuery/project/{1}?api-version=5.0-preview.1" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                                $inputbody = "{
                                'contributionIds': [
                                    'ms.vss-releaseManagement-web.search-definitions-data-provider'
                                ],
                                'dataProviderContext': {
                                    'properties': {
                                        'searchText': '$resleaseName',
                                        'sourcePage': {
                                            'routeValues': {
                                                'project': '$projectName'
                                            }
                                        }
                                    }
                                }
                            }" | ConvertFrom-Json
                            
                                $releaseDefnsObj = [WebRequestHelper]::InvokePostWebRequest($releaseDefnURL, $inputbody);
                                if (([Helpers]::CheckMember($releaseDefnsObj, "dataProviders") -and $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider") -and [Helpers]::CheckMember($releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider", "releaseDefinitions") ) {
                                    $releaseDefinitions = $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider".releaseDefinitions  
                                    foreach ($relDef in $releaseDefinitions) {
                                        $svtResource = [SVTResource]::new();
                                        $svtResource.ResourceName = $relDef.name;
                                        $svtResource.ResourceGroupName = $projectName;
                                        $svtResource.ResourceType = "AzureDevOps.Release";
                                        $svtResource.ResourceId = $relDef.url
                                        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                            Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                            Select-Object -First 1)

                                        $link = "https://dev.azure.com/{0}/{1}/_release?_a=releases&view=mine&definitionId={2}" -f $this.SubscriptionContext.SubscriptionName, $projectName, $svtResource.ResourceId.split('/')[-1];
                                        $svtResource.ResourceDetails = New-Object -TypeName psobject -Property @{ ResourceLink = $link }
                                                                    
                                        $this.SVTResources += $svtResource
                                    }
                                    $releaseDefinitions = $null;
                                }

                            }
                        }
                        catch {
                            Write-Error $_.Exception.Message;
                            Write-Error 'Insufficient Privileges. You do not have the level of access necessary to perform the scan.'
                        }
                    }
                }

                if ($this.ServiceConnections.Count -gt 0 -and ($this.ResourceTypeName -in ([ResourceTypeName]::ServiceConnection, [ResourceTypeName]::All, [ResourceTypeName]::Build_Release_SvcConn_AgentPool_User)))
                {
                    if ($this.ProjectNames -ne "*") {
                        $this.PublishCustomMessage("Getting service endpoint configurations...");
                    }
                
                    $serviceEndpointURL = "https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" -f $($this.organizationName), $($projectName);
                    $serviceEndpointObj = [WebRequestHelper]::InvokeGetWebRequest($serviceEndpointURL)
                
                    if (($serviceEndpointObj | Measure-Object).Count -gt 0) {
                        # Currently get only Azure Connections as all controls are applicable for same
                   
                        $Connections = $null;
                        if ($this.ServiceConnections -eq "*") {
                            $Connections = $serviceEndpointObj | Where-Object { ($_.type -eq "azurerm" -or $_.type -eq "azure" -or $_.type -eq "git" -or $_.type -eq "github") } 
                        }
                        else {
                            $Connections = $serviceEndpointObj | Where-Object { ($_.type -eq "azurerm" -or $_.type -eq "azure" -or $_.type -eq "git" -or $_.type -eq "github") -and ($this.ServiceConnections -eq $_.name) } #-or $_.type -eq "git" -or $_.type -eq "git"  
                        }

                        $serviceEndpointObj = $null;
                        Remove-Variable  serviceEndpointObj;
                        $nObj = $this.MaxObjectsToScan
                        foreach ($connectionObject in $Connections) {
                            $svtResource = [SVTResource]::new();
                            $svtResource.ResourceName = $connectionObject.Name;
                            $svtResource.ResourceGroupName = $projectName;
                            $svtResource.ResourceType = "AzureDevOps.ServiceConnection";
                            $svtResource.ResourceId = "Organization/$($this.organizationName)/Project/$projectName/$($connectionObject.Name)"
                            $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                Select-Object -First 1)
                        
                            $svtResource.ResourceDetails = $connectionObject
                            $link = $svtResource.ResourceId.Replace('Organization', 'https://dev.azure.com').Replace('Project/', '').Replace( $connectionObject.Name, "_settings/adminservices?resourceId=$($svtResource.ResourceDetails.id)") ;
                            $svtResource.ResourceDetails | Add-Member -Name 'ResourceLink' -Type NoteProperty -Value $link;
                            $this.SVTResources += $svtResource

                            if (--$nObj -eq 0) { break; }
                        }
                    }
                }
                
                if ($this.AgentPools.Count -gt 0 -and ($this.ResourceTypeName -in ([ResourceTypeName]::AgentPool, [ResourceTypeName]::All, [ResourceTypeName]::Build_Release_SvcConn_AgentPool_User))) {
                    if ($this.ProjectNames -ne "*") {
                        $this.PublishCustomMessage("Getting agent pools configurations...");
                    }

                    $agentPoolsDefnURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                    try {
                      
                        $agentPoolsDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsDefnURL);
                                                   
                        if (([Helpers]::CheckMember($agentPoolsDefnsObj, "fps.dataProviders.data") ) -and (($agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider") -and $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues)) {
                            $nObj = $this.MaxObjectsToScan
                            $taskAgentQueues = $null;
                            if ($this.AgentPools -eq "*") {
                                $taskAgentQueues = $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues;
                            }
                            else {
                                $taskAgentQueues = $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues | Where-Object { ($this.AgentPools -contains $_.name) } 
                            }
                            
                            foreach ($taq in $taskAgentQueues) {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $taq.name;
                                $svtResource.ResourceGroupName = $projectName;
                                $svtResource.ResourceType = "AzureDevOps.AgentPool";
                                $svtResource.ResourceId = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.agentqueuerole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName), $($taq.projectId), $taq.id   
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                    Select-Object -First 1)
                                $this.SVTResources += $svtResource

                                if (--$nObj -eq 0) { break; }
                            }
                            $taskAgentQueues = $null;
                            Remove-Variable taskAgentQueues;
                        }
                    }
                    catch {
                        Write-Warning "Insufficient Privileges. You do not have the level of access to perform the scan.";
                        Write-Error $_.Exception.Message;
                    }              
                }
                if (--$nProj -eq 0) { break; } #nProj is set to MaxObj before loop.
                
            }
        }
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    }
}