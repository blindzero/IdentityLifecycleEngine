function Normalize-IdleExchangeOnlineAutoReplyMessage {
    <#
    .SYNOPSIS
    Normalizes Exchange Online auto-reply messages for stable idempotency comparison.

    .DESCRIPTION
    Exchange Online may introduce server-side canonicalization when storing automatic reply messages,
    such as adding HTML/body wrappers, normalizing line endings, or adjusting whitespace.

    This helper performs minimal, deterministic normalization to ensure that functionally equivalent
    messages are recognized as identical during idempotency checks.

    Normalization operations:
    - Normalize line endings (CRLF to LF)
    - Remove common HTML wrappers added by Exchange (<html>, <head>, <body>)
    - Trim leading/trailing whitespace
    - Normalize consecutive whitespace sequences in HTML (multiple spaces/tabs to single space)

    This function does NOT sanitize or validate HTML. It only normalizes structural differences
    introduced by server-side canonicalization.

    .PARAMETER Message
    The auto-reply message string to normalize (plain text or HTML).

    .OUTPUTS
    System.String - The normalized message string.

    .EXAMPLE
    $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $currentMessage
    if ($normalized -eq (Normalize-IdleExchangeOnlineAutoReplyMessage -Message $desiredMessage)) {
        # Messages are functionally equivalent
    }

    .NOTES
    This is a private helper function used by the ExchangeOnline provider for idempotency checks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Message
    )

    if ([string]::IsNullOrEmpty($Message)) {
        return ''
    }

    # Start with the original message
    $normalized = $Message

    # 1. Normalize line endings: CRLF -> LF
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"

    # 2. Remove common HTML wrappers that Exchange may add
    # Remove <!DOCTYPE ...> declarations
    $normalized = $normalized -replace '(?i)<!DOCTYPE[^>]*>', ''

    # Remove <html> opening and closing tags (with optional attributes)
    $normalized = $normalized -replace '(?i)<html[^>]*>', ''
    $normalized = $normalized -replace '(?i)</html>', ''

    # Remove <head> wrapper tags while preserving their inner content
    $normalized = $normalized -replace '(?is)<head[^>]*>\s*(.*?)\s*</head>', '$1'

    # Remove <body> opening and closing tags (with optional attributes)
    $normalized = $normalized -replace '(?i)<body[^>]*>', ''
    $normalized = $normalized -replace '(?i)</body>', ''

    # 3. Trim leading/trailing whitespace (including newlines)
    $normalized = $normalized.Trim()

    # 4. Normalize whitespace conservatively
    # Only collapse truly excessive whitespace that Exchange commonly adds
    # This is conservative to avoid making intentionally different messages compare equal
    # NOTE: This normalization is ONLY used for idempotency comparison, not for modifying
    # the actual message sent to Exchange. The original message formatting is preserved.
    
    # Normalize 3+ consecutive spaces/tabs to 2 (preserves intentional double-spacing)
    # This handles Exchange adding extra whitespace without collapsing intentional formatting
    $normalized = $normalized -replace '[ \t]{3,}', '  '
    
    # 5. Normalize excessive empty lines (4+ consecutive newlines to 3)
    # This is very conservative - only removes truly excessive blank lines
    # Preserves intentional spacing while handling Exchange-added excessive gaps
    $normalized = $normalized -replace '\n{4,}', "`n`n`n"

    # 6. Final trim to remove any whitespace introduced by previous operations
    $normalized = $normalized.Trim()

    return $normalized
}
