function New-IdleADPassword {
    <#
    .SYNOPSIS
    Generates a policy-compliant Active Directory password.

    .DESCRIPTION
    Generates a password that satisfies Active Directory domain password policy requirements.
    First attempts to read the domain password policy using Get-ADDefaultDomainPasswordPolicy.
    If policy reading fails, falls back to provider-specified configuration.

    The generated password will meet:
    - Minimum length (from policy or fallback configuration)
    - Complexity requirements (uppercase, lowercase, digits, special characters)

    .PARAMETER Credential
    Optional PSCredential for accessing Active Directory. If not provided, uses integrated auth.

    .PARAMETER FallbackMinLength
    Fallback minimum password length if domain policy cannot be read. Default is 24.

    .PARAMETER FallbackRequireUpper
    Fallback requirement for uppercase characters. Default is $true.

    .PARAMETER FallbackRequireLower
    Fallback requirement for lowercase characters. Default is $true.

    .PARAMETER FallbackRequireDigit
    Fallback requirement for digit characters. Default is $true.

    .PARAMETER FallbackRequireSpecial
    Fallback requirement for special characters. Default is $true.

    .PARAMETER FallbackSpecialCharSet
    Set of special characters to use when generating passwords. Default is '!@#$%&*+-_=?'.

    .OUTPUTS
    PSCustomObject with properties:
    - PlainText: The generated password as a plain string
    - SecureString: The generated password as a SecureString
    - ProtectedString: The generated password as a ProtectedString (DPAPI-scoped)
    - UsedPolicy: Information about which policy was used (domain or fallback)

    .EXAMPLE
    $result = New-IdleADPassword
    # Uses domain policy if available, otherwise uses default fallback configuration

    .EXAMPLE
    $result = New-IdleADPassword -FallbackMinLength 32 -FallbackRequireSpecial $true
    # Uses custom fallback configuration if domain policy cannot be read
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'This function generates passwords and must convert the generated plaintext to SecureString')]
    param(
        [Parameter()]
        [AllowNull()]
        [PSCredential] $Credential,

        [Parameter()]
        [int] $FallbackMinLength = 24,

        [Parameter()]
        [bool] $FallbackRequireUpper = $true,

        [Parameter()]
        [bool] $FallbackRequireLower = $true,

        [Parameter()]
        [bool] $FallbackRequireDigit = $true,

        [Parameter()]
        [bool] $FallbackRequireSpecial = $true,

        [Parameter()]
        [string] $FallbackSpecialCharSet = '!@#$%&*+-_=?'
    )

    # Character sets for password generation
    $upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lowerChars = 'abcdefghijklmnopqrstuvwxyz'
    $digitChars = '0123456789'

    # Try to read domain password policy
    $policySource = 'Fallback'
    $minLength = $FallbackMinLength
    $requireUpper = $FallbackRequireUpper
    $requireLower = $FallbackRequireLower
    $requireDigit = $FallbackRequireDigit
    $requireSpecial = $FallbackRequireSpecial
    $specialCharSet = $FallbackSpecialCharSet

    # Validate special character set if special characters are required
    if ($requireSpecial -and ([string]::IsNullOrEmpty($specialCharSet) -or $specialCharSet.Length -eq 0)) {
        # Fall back to a safe default character set if none provided
        $specialCharSet = '!@#$%&*+-_=?'
        Write-Verbose "AD Password Generation: Special characters required but FallbackSpecialCharSet is empty. Using default: '$specialCharSet'"
    }

    try {
        $params = @{
            ErrorAction = 'Stop'
        }
        if ($null -ne $Credential) {
            $params['Credential'] = $Credential
        }

        $domainPolicy = Get-ADDefaultDomainPasswordPolicy @params

        if ($null -ne $domainPolicy) {
            $policySource = 'DomainPolicy'
            
            # Use domain policy minimum length, but enforce fallback as minimum baseline
            # This ensures generated passwords meet at least the provider's configured minimum,
            # even if domain policy allows shorter passwords (defense in depth)
            if ($domainPolicy.MinPasswordLength -gt 0) {
                $minLength = [Math]::Max($domainPolicy.MinPasswordLength, $FallbackMinLength)
            }

            # If complexity is enabled, require all character classes
            if ($domainPolicy.ComplexityEnabled) {
                $requireUpper = $true
                $requireLower = $true
                $requireDigit = $true
                $requireSpecial = $true
            }

            Write-Verbose "AD Password Generation: Using domain policy (MinLength=$minLength, ComplexityEnabled=$($domainPolicy.ComplexityEnabled))"
        }
    }
    catch {
        Write-Verbose "AD Password Generation: Failed to read domain policy, using fallback configuration: $_"
    }

    # Ensure minimum length is at least 8 (AD minimum)
    if ($minLength -lt 8) {
        $minLength = 8
        Write-Verbose "AD Password Generation: Adjusted minimum length to 8 (AD minimum)"
    }

    # Build character pool based on requirements
    $charPool = ''
    $requiredChars = @()

    if ($requireUpper) {
        $charPool += $upperChars
        # Pick one random uppercase character to guarantee requirement
        $requiredChars += $upperChars[(Get-Random -Minimum 0 -Maximum $upperChars.Length)]
    }

    if ($requireLower) {
        $charPool += $lowerChars
        # Pick one random lowercase character to guarantee requirement
        $requiredChars += $lowerChars[(Get-Random -Minimum 0 -Maximum $lowerChars.Length)]
    }

    if ($requireDigit) {
        $charPool += $digitChars
        # Pick one random digit to guarantee requirement
        $requiredChars += $digitChars[(Get-Random -Minimum 0 -Maximum $digitChars.Length)]
    }

    if ($requireSpecial) {
        $charPool += $specialCharSet
        # Pick one random special character to guarantee requirement
        $requiredChars += $specialCharSet[(Get-Random -Minimum 0 -Maximum $specialCharSet.Length)]
    }

    # If no requirements specified, use all character types
    if ($charPool.Length -eq 0) {
        $charPool = $upperChars + $lowerChars + $digitChars + $specialCharSet
    }

    # Calculate remaining length after required characters
    $remainingLength = $minLength - $requiredChars.Count

    # Generate remaining random characters using a cryptographically secure RNG
    $randomChars = @()
    for ($i = 0; $i -lt $remainingLength; $i++) {
        $index = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $charPool.Length)
        $randomChars += $charPool[$index]
    }

    # Combine required and random characters
    $allChars = $requiredChars + $randomChars

    # Shuffle the characters to randomize position of required characters (Fisher–Yates, CSPRNG-driven)
    for ($i = $allChars.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $i + 1)
        $temp = $allChars[$i]
        $allChars[$i] = $allChars[$j]
        $allChars[$j] = $temp
    }
    $shuffledChars = $allChars

    # Join to create the password
    $plainTextPassword = -join $shuffledChars

    # Convert to SecureString
    $securePassword = ConvertTo-SecureString -String $plainTextPassword -AsPlainText -Force

    # Convert to ProtectedString (DPAPI-scoped)
    $protectedPassword = ConvertFrom-SecureString -SecureString $securePassword

    return [pscustomobject]@{
        PSTypeName       = 'IdLE.ADPassword'
        PlainText        = $plainTextPassword
        SecureString     = $securePassword
        ProtectedString  = $protectedPassword
        UsedPolicy       = $policySource
        MinLength        = $minLength
        RequiredUpper    = $requireUpper
        RequiredLower    = $requireLower
        RequiredDigit    = $requireDigit
        RequiredSpecial  = $requireSpecial
    }
}
