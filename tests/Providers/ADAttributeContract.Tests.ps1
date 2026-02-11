Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'AD Provider Attribute Contract' {
    BeforeAll {
        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $adProviderPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.AD\IdLE.Provider.AD.psd1'
        
        if (Test-Path -LiteralPath $adProviderPath -PathType Leaf) {
            Import-Module $adProviderPath -Force
        }
    }

    Context 'Get-IdleADAttributeContract' {
        It 'Returns contract for CreateIdentity operation' {
            $contract = Get-IdleADAttributeContract -Operation 'CreateIdentity'
            
            $contract | Should -Not -BeNullOrEmpty
            $contract | Should -BeOfType [hashtable]
            $contract.Keys | Should -Contain 'GivenName'
            $contract.Keys | Should -Contain 'Surname'
            $contract.Keys | Should -Contain 'OtherAttributes'
        }

        It 'Returns contract for EnsureAttribute operation' {
            $contract = Get-IdleADAttributeContract -Operation 'EnsureAttribute'
            
            $contract | Should -Not -BeNullOrEmpty
            $contract | Should -BeOfType [hashtable]
            $contract.Keys | Should -Contain 'GivenName'
            $contract.Keys | Should -Contain 'Surname'
        }

        It 'CreateIdentity contract includes all expected attributes' {
            $contract = Get-IdleADAttributeContract -Operation 'CreateIdentity'
            
            # Identity attributes
            $contract.Keys | Should -Contain 'SamAccountName'
            $contract.Keys | Should -Contain 'UserPrincipalName'
            $contract.Keys | Should -Contain 'Path'
            
            # Name attributes
            $contract.Keys | Should -Contain 'Name'
            $contract.Keys | Should -Contain 'GivenName'
            $contract.Keys | Should -Contain 'Surname'
            $contract.Keys | Should -Contain 'DisplayName'
            
            # Organizational attributes
            $contract.Keys | Should -Contain 'Description'
            $contract.Keys | Should -Contain 'Department'
            $contract.Keys | Should -Contain 'Title'
            
            # Contact attributes
            $contract.Keys | Should -Contain 'EmailAddress'
            
            # Relationship attributes
            $contract.Keys | Should -Contain 'Manager'
            
            # Password attributes
            $contract.Keys | Should -Contain 'AccountPassword'
            $contract.Keys | Should -Contain 'AccountPasswordAsPlainText'
            
            # State attributes
            $contract.Keys | Should -Contain 'Enabled'
            
            # Extension container
            $contract.Keys | Should -Contain 'OtherAttributes'
        }

        It 'EnsureAttribute contract excludes password and OtherAttributes' {
            $contract = Get-IdleADAttributeContract -Operation 'EnsureAttribute'
            
            $contract.Keys | Should -Not -Contain 'AccountPassword'
            $contract.Keys | Should -Not -Contain 'AccountPasswordAsPlainText'
            $contract.Keys | Should -Not -Contain 'OtherAttributes'
            $contract.Keys | Should -Not -Contain 'Path'
            $contract.Keys | Should -Not -Contain 'Name'
            $contract.Keys | Should -Not -Contain 'Enabled'
        }

        It 'EnsureAttribute contract includes modifiable attributes' {
            $contract = Get-IdleADAttributeContract -Operation 'EnsureAttribute'
            
            # Name attributes
            $contract.Keys | Should -Contain 'GivenName'
            $contract.Keys | Should -Contain 'Surname'
            $contract.Keys | Should -Contain 'DisplayName'
            
            # Organizational attributes
            $contract.Keys | Should -Contain 'Description'
            $contract.Keys | Should -Contain 'Department'
            $contract.Keys | Should -Contain 'Title'
            
            # Contact attributes
            $contract.Keys | Should -Contain 'EmailAddress'
            
            # Identity attributes
            $contract.Keys | Should -Contain 'UserPrincipalName'
            
            # Relationship attributes
            $contract.Keys | Should -Contain 'Manager'
        }
    }

    Context 'Test-IdleADAttributeContract - CreateIdentity' {
        It 'Validates supported attributes without error' {
            $attrs = @{
                GivenName   = 'John'
                Surname     = 'Doe'
                DisplayName = 'John Doe'
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | Should -Not -Throw
        }

        It 'Returns correct validation result for supported attributes' {
            $attrs = @{
                GivenName   = 'John'
                Surname     = 'Doe'
                DisplayName = 'John Doe'
            }

            $result = Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity'
            
            $result.Requested | Should -HaveCount 3
            $result.Supported | Should -HaveCount 3
            $result.Unsupported | Should -HaveCount 0
        }

        It 'Throws on unsupported attribute' {
            $attrs = @{
                GivenName       = 'John'
                InvalidAttribute = 'Value'
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | 
                Should -Throw -ExpectedMessage '*Unsupported attributes*'
        }

        It 'Error message lists unsupported attributes' {
            $attrs = @{
                InvalidAttr1 = 'Value1'
                InvalidAttr2 = 'Value2'
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | 
                Should -Throw -ExpectedMessage '*InvalidAttr1*InvalidAttr2*'
        }

        It 'Error message provides guidance on supported attributes' {
            $attrs = @{
                InvalidAttribute = 'Value'
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | 
                Should -Throw -ExpectedMessage '*Supported attributes for CreateIdentity*'
        }

        It 'Accepts OtherAttributes as hashtable' {
            $attrs = @{
                GivenName       = 'John'
                OtherAttributes = @{
                    extensionAttribute1 = 'X'
                    employeeType        = 'Contractor'
                }
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | Should -Not -Throw
        }

        It 'Throws if OtherAttributes is not a hashtable' {
            $attrs = @{
                GivenName       = 'John'
                OtherAttributes = 'NotAHashtable'
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | 
                Should -Throw -ExpectedMessage '*OtherAttributes*must be a hashtable*'
        }

        It 'Handles empty attributes hashtable' {
            $attrs = @{}

            $result = Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity'
            
            $result.Requested | Should -HaveCount 0
            $result.Supported | Should -HaveCount 0
            $result.Unsupported | Should -HaveCount 0
        }

        It 'Handles null attributes hashtable' {
            $result = Test-IdleADAttributeContract -Attributes $null -Operation 'CreateIdentity'
            
            $result.Requested | Should -HaveCount 0
            $result.Supported | Should -HaveCount 0
            $result.Unsupported | Should -HaveCount 0
        }

        It 'Validates all supported CreateIdentity attributes' {
            $attrs = @{
                SamAccountName             = 'jdoe'
                UserPrincipalName          = 'jdoe@example.com'
                Path                       = 'OU=Users,DC=example,DC=com'
                Name                       = 'John Doe'
                GivenName                  = 'John'
                Surname                    = 'Doe'
                DisplayName                = 'John Doe'
                Description                = 'Test User'
                Department                 = 'IT'
                Title                      = 'Engineer'
                EmailAddress               = 'john.doe@example.com'
                Manager                    = 'CN=Manager,OU=Users,DC=example,DC=com'
                Enabled                    = $true
            }

            { Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity' } | Should -Not -Throw
            
            $result = Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity'
            $result.Unsupported | Should -HaveCount 0
        }
    }

    Context 'Test-IdleADAttributeContract - EnsureAttribute' {
        It 'Validates supported attribute without error' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'GivenName' } | Should -Not -Throw
        }

        It 'Returns correct validation result for supported attribute' {
            $result = Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'GivenName'
            
            $result.Requested | Should -HaveCount 1
            $result.Requested[0] | Should -Be 'GivenName'
            $result.Supported | Should -HaveCount 1
            $result.Supported[0] | Should -Be 'GivenName'
            $result.Unsupported | Should -HaveCount 0
        }

        It 'Throws on unsupported attribute' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'InvalidAttribute' } | 
                Should -Throw -ExpectedMessage '*Unsupported attribute*'
        }

        It 'Error message lists the unsupported attribute' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'InvalidAttr' } | 
                Should -Throw -ExpectedMessage '*InvalidAttr*'
        }

        It 'Error message provides guidance on supported attributes' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'InvalidAttr' } | 
                Should -Throw -ExpectedMessage '*Supported attributes for EnsureAttribute*'
        }

        It 'Throws if AttributeName is empty' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName '' } | 
                Should -Throw -ExpectedMessage '*AttributeName is required*'
        }

        It 'Throws if AttributeName is null' {
            { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName $null } | 
                Should -Throw -ExpectedMessage '*AttributeName is required*'
        }

        It 'Validates all supported EnsureAttribute attributes' {
            $supportedAttrs = @(
                'GivenName', 'Surname', 'DisplayName',
                'Description', 'Department', 'Title',
                'EmailAddress', 'UserPrincipalName', 'Manager'
            )

            foreach ($attr in $supportedAttrs) {
                { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName $attr } | Should -Not -Throw
            }
        }

        It 'Rejects CreateIdentity-only attributes in EnsureAttribute' {
            $createOnlyAttrs = @(
                'AccountPassword', 'AccountPasswordAsPlainText',
                'Path', 'Name', 'Enabled', 'OtherAttributes'
            )

            foreach ($attr in $createOnlyAttrs) {
                { Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName $attr } | 
                    Should -Throw -ExpectedMessage '*Unsupported attribute*'
            }
        }
    }
}
