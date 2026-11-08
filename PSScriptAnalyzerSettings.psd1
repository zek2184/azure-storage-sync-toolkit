@{
    Severity = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        # The project intentionally supports Windows PowerShell 5.1.
        'PSUseCompatibleSyntax'
    )
    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @()
        }
    }
}

