Set-StrictMode -Version Latest

class SVTResourceResolver: AzSKRoot
{
    [string[]] $ResourceNames = @();
    [string] $ResourceType = "";
    [ResourceTypeName] $ResourceTypeName = [ResourceTypeName]::All;
	[Hashtable] $Tag = $null;
    [string] $TagName = "";
    [string[]] $TagValue = "";
	hidden [string[]] $ResourceGroups = @();
	[ResourceTypeName] $ExcludeResourceTypeName = [ResourceTypeName]::All;
	[string[]] $ExcludeResourceNames=@();
	[SVTResource[]] $ExcludedResources=@();
	[string] $ExcludeResourceWarningMessage=[string]::Empty
	[string[]] $ExcludeResourceGroupNames=@();
	[string[]] $ExcludedResourceGroupNames=@();
	[string] $ExcludeResourceGroupWarningMessage=[string]::Empty
	[SVTResource[]] $SVTResources = @();
    [int] $SVTResourcesFoundCount=0;
    
    [string] $ResourcePath;
    [string] $organizationName
    hidden [string[]] $ProjectNames = @();
    hidden [string[]] $BuildNames = @();
    hidden [string[]] $ReleaseNames = @();
    hidden [string[]] $AgentPools = @();
    SVTResourceResolver([string]$organizationName,$ProjectNames,$BuildNames,$ReleaseNames,$AgentPools,$ScanAllArtifacts,$PATToken,$ResourceTypeName): Base($organizationName,$PATToken)
	{
        $this.organizationName = $organizationName
        $this.ResourceTypeName = $ResourceTypeName
        

        if(-not [string]::IsNullOrEmpty($ProjectNames))
        {
			$this.ProjectNames += $this.ConvertToStringArray($ProjectNames);

			if ($this.ProjectNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ProjectNames' does not contain any string."
			}
        }	

        if(-not [string]::IsNullOrEmpty($BuildNames))
        {
			$this.BuildNames += $this.ConvertToStringArray($BuildNames);
			if ($this.BuildNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'BuildNames' does not contain any string."
			}
        }

        if(-not [string]::IsNullOrEmpty($ReleaseNames))
        {
			$this.ReleaseNames += $this.ConvertToStringArray($ReleaseNames);
			if ($this.ReleaseNames.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'ReleaseNames' does not contain any string."
			}
        }

        if(-not [string]::IsNullOrEmpty($AgentPools))
        {
			$this.AgentPools += $this.ConvertToStringArray($AgentPools);
			if ($this.AgentPools.Count -eq 0)
			{
				throw [SuppressedException] "The parameter 'AgentPools' does not contain any string."
			}
        }

        if($ScanAllArtifacts)
        {
            $this.ProjectNames = "*"
            $this.BuildNames = "*"
            $this.ReleaseNames = "*"
            $this.AgentPools = "*"
        }        
    }

    [void] LoadAzureResources()
	{
        
        #Call APIS for Organization,User/Builds/Releases/ServiceConnections 
        if($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::Organization)
        {
            #Select Org/User by default...
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.organizationName;
            $svtResource.ResourceType = "AzureDevOps.Organization";
            $svtResource.ResourceId = "Organization/$($this.organizationName)/"
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                            Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                            Select-Object -First 1)
            $this.SVTResources +=$svtResource
        }
        

        if($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::User)
        {
            $svtResource = [SVTResource]::new();
            $svtResource.ResourceName = $this.organizationName;
            $svtResource.ResourceType = "AzureDevOps.User";
            $svtResource.ResourceId = "Organization/$($this.organizationName)/User"
            $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                            Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                            Select-Object -First 1)
            $this.SVTResources +=$svtResource
        }

        #Get project resources
        if($this.ProjectNames.Count -gt 0)
        {
            $this.PublishCustomMessage("Querying api for resources to be scanned. This may take a while...");

            $this.PublishCustomMessage("Getting project configurations...");

            $apiURL = "https://dev.azure.com/{0}/_apis/projects?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName);
            $responseObj = [WebRequestHelper]::InvokeGetWebRequest($apiURL) ;

            $responseObj  | Where-Object {  (($this.ProjectNames -contains $_.name) -or ($this.ProjectNames -eq "*"))  } | ForEach-Object {
                $projectName = $_.name

            if($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::Project)
            {
                $svtResource = [SVTResource]::new();
                $svtResource.ResourceName = $_.name;
                $svtResource.ResourceGroupName = $this.organizationName
                $svtResource.ResourceType = "AzureDevOps.Project";
                $svtResource.ResourceId = $_.url
                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                Select-Object -First 1)
                
                $this.SVTResources +=$svtResource
            }


            if($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::ServiceConnection)
            {
                if($this.ProjectNames -ne "*")
                {
                    $this.PublishCustomMessage("Getting service endpoint configurations...");
                }
                
                $serviceEndpointURL = "https://dev.azure.com/{0}/{1}/_apis/serviceendpoint/endpoints?api-version=4.1-preview.1" -f $($this.organizationName),$($projectName);
                $serviceEndpointObj = [WebRequestHelper]::InvokeGetWebRequest($serviceEndpointURL)
                
                if(([Helpers]::CheckMember($serviceEndpointObj,"count") -and $serviceEndpointObj[0].count -gt 0) -or  (($serviceEndpointObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($serviceEndpointObj[0],"name")))
                {
                    # Currently get only Azure Connections as all controls are applicable for same
                    #TODO: temp added git in the where
                    $azureConnections = $serviceEndpointObj | Where-Object { $_.type -eq "azurerm" -or $_.type -eq "azure" -or $_.type -eq "git" -or $_.type -eq "github"} #-or $_.type -eq "git" -or $_.type -eq "git"

                    $azureConnections | ForEach-Object {
                        $connectionObject = $_
                        $svtResource = [SVTResource]::new();
                        $svtResource.ResourceName = $connectionObject.Name;
                        $svtResource.ResourceGroupName = $projectName;
                        $svtResource.ResourceType = "AzureDevOps.ServiceConnection";
                        $svtResource.ResourceId = "Organization/$($this.organizationName)/Project/$projectName/$($connectionObject.Name)"
                        $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                        Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                        Select-Object -First 1)
                        $svtResource.ResourceDetails = $connectionObject
                        $this.SVTResources +=$svtResource
                    }
                }
            }

                if($this.BuildNames.Count -gt 0  -and ($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::Build))
                {
                    if($this.ProjectNames -ne "*")
                    {
                        $this.PublishCustomMessage("Getting build configurations...");
                    }

                    if($this.BuildNames -eq "*")
                    {
                        $buildDefnURL = "https://dev.azure.com/{0}/{1}/_apis/build/definitions?api-version=4.1" -f $($this.SubscriptionContext.SubscriptionName), $_.name;
                        $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                        if(([Helpers]::CheckMember($buildDefnsObj,"count") -and $buildDefnsObj[0].count -gt 0) -or  (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0],"name")))
                        {
                            $buildDefnsObj  | ForEach-Object {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $_.name;
                                $svtResource.ResourceGroupName =$_.project.name;
                                $svtResource.ResourceType = "AzureDevOps.Build";
                                $svtResource.ResourceId = $_.url
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                Select-Object -First 1)
                                $svtResource.ResourceDetails = $_
                                $this.SVTResources +=$svtResource
                            }
                        }
                    }
                    else
                    {
                        $this.BuildNames | ForEach-Object {
                            $buildName = $_
                            $buildDefnURL = "https://{0}.visualstudio.com/{1}/_apis/build/definitions?name={2}&api-version=5.1-preview.7" -f $($this.SubscriptionContext.SubscriptionName),$projectName, $buildName;
                            $buildDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($buildDefnURL) 
                            if(([Helpers]::CheckMember($buildDefnsObj,"count") -and $buildDefnsObj[0].count -gt 0) -or  (($buildDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($buildDefnsObj[0],"name")))
                            {
                                $buildDefnsObj  | ForEach-Object {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $_.name;
                                    $svtResource.ResourceGroupName =$_.project.name;
                                    $svtResource.ResourceType = "AzureDevOps.Build";
                                    $svtResource.ResourceId = $_.url
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                    Select-Object -First 1)
                                    $this.SVTResources +=$svtResource
                                }
                            }
                        }
                    }
                           
                }

                if($this.ReleaseNames.Count -gt 0 -and ($this.ResourceTypeName -eq [ResourceTypeName]::All -or $this.ResourceTypeName -eq [ResourceTypeName]::Release))
                {
                    if($this.ProjectNames -ne "*")
                    {
                        $this.PublishCustomMessage("Getting release configurations...");
                    }
                    if($this.ReleaseNames -eq "*")
                    {
                        $releaseDefnURL = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions?api-version=4.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                        $releaseDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($releaseDefnURL);
                        if(([Helpers]::CheckMember($releaseDefnsObj,"count") -and $releaseDefnsObj[0].count -gt 0) -or  (($releaseDefnsObj | Measure-Object).Count -gt 0 -and [Helpers]::CheckMember($releaseDefnsObj[0],"name")))
                        {
                            $releaseDefnsObj  | ForEach-Object {
                                $svtResource = [SVTResource]::new();
                                $svtResource.ResourceName = $_.name;
                                $svtResource.ResourceGroupName =$projectName;
                                $svtResource.ResourceType = "AzureDevOps.Release";
                                $svtResource.ResourceId = $_.url
                                $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                Select-Object -First 1)
                                $this.SVTResources +=$svtResource
                            }
                        }
                    }
                    else
                    {
                        try {
                            #TODO: temporary added
                           # $releaseDefnURL2 = "https://vsrm.dev.azure.com/{0}/{1}/_apis/release/definitions?api-version=4.1-preview.3" -f $($this.SubscriptionContext.SubscriptionName), $projectName;
                           # $releaseDefnsObj2 = [WebRequestHelper]::InvokeGetWebRequest($releaseDefnURL);

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
                            
                            $releaseDefnsObj = [WebRequestHelper]::InvokePostWebRequest($releaseDefnURL,$inputbody);
                            if(([Helpers]::CheckMember($releaseDefnsObj,"dataProviders") -and $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider") -and [Helpers]::CheckMember($releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider","releaseDefinitions") )
                            {
                                $releaseDefnsObj.dataProviders."ms.vss-releaseManagement-web.search-definitions-data-provider".releaseDefinitions  | ForEach-Object {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $_.name;
                                    $svtResource.ResourceGroupName =$projectName;
                                    $svtResource.ResourceType = "AzureDevOps.Release";
                                    $svtResource.ResourceId = $_.url
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                    Select-Object -First 1)
                                    $this.SVTResources +=$svtResource
                                }
                        }

                        }
                    }
                    catch {
                        Write-Error $_.Exception.Message;
                        Write-Error 'Insufficient Privileges. You do not have the level of access necessary to perform the scan.'
                    }
                    }
                }
                
                if($this.AgentPools.Count -gt 0)
                {
                    if($this.AgentPools -ne "*")
                    {
                        $this.PublishCustomMessage("Getting agent pools configurations...");
                    }
                    if($this.AgentPools -eq "*")
                    {
                        $agentPoolsDefnURL = "https://{0}.visualstudio.com/{1}/_settings/agentqueues?__rt=fps&__ver=2" -f $($this.SubscriptionContext.SubscriptionName),$projectName;
                        #TODO: comment above line added below line for testing. previously above commented line was in use, below line is also working fine.
                        #$agentPoolsDefnURL = "https://dev.azure.com/{0}/{1}/_settings/agentqueues?__rt=fps&__ver=2 " -f $($this.SubscriptionContext.SubscriptionName),$projectName;
                        
                        try {
                      
                                $agentPoolsDefnsObj = [WebRequestHelper]::InvokeGetWebRequest($agentPoolsDefnURL);
                           
                        
                             if(([Helpers]::CheckMember($agentPoolsDefnsObj,"fps.dataProviders.data") ) -and  (($agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider") -and $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues))
                            {
                                $agentPoolsDefnsObj.fps.dataProviders.data."ms.vss-build-web.agent-queues-data-provider".taskAgentQueues  | ForEach-Object {
                                    $svtResource = [SVTResource]::new();
                                    $svtResource.ResourceName = $_.name;
                                    $svtResource.ResourceGroupName =$projectName;
                                    $svtResource.ResourceType = "AzureDevOps.AgentPool";
                                    $svtResource.ResourceId = "https://{0}.visualstudio.com/_apis/securityroles/scopes/distributedtask.agentqueuerole/roleassignments/resources/{1}_{2}" -f $($this.SubscriptionContext.SubscriptionName),$($_.projectId), $_.id
                                    $svtResource.ResourceTypeMapping = ([SVTMapping]::AzSKDevOpsResourceMapping |
                                                                    Where-Object { $_.ResourceType -eq $svtResource.ResourceType } |
                                                                    Select-Object -First 1)
                                    $this.SVTResources +=$svtResource
                                }
                            }
                        }
                        catch {
                           #Write-Warning "Insufficient Privileges. You do not have the level of access necessary to perform the scan.";
                           #Write-Error -Exception ([System.UnauthorizedAccessException]::new("Insufficient Privileges. You do not have the level of access necessary to perform the scan."));
                           Write-Error $_.Exception.Message;
                        }              
                    }
                }

            }

         
        }

        
        $this.SVTResourcesFoundCount = $this.SVTResources.Count
    
    }
}