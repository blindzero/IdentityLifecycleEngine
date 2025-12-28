BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\IdLE\IdLE.psd1'
    Import-Module $modulePath -Force
}

Describe 'New-IdleLifecycleRequest' {
    It 'creates a request object with the expected type' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $req | Should -Not -BeNullOrEmpty
        $req.GetType().Name | Should -Be 'IdleLifecycleRequest'
    }

    It 'generates CorrelationId when missing' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $req.CorrelationId | Should -Not -BeNullOrEmpty
        { [guid]::Parse($req.CorrelationId) } | Should -Not -Throw
    }

    It 'preserves CorrelationId when provided' {
        $cid = ([guid]::NewGuid()).Guid
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -CorrelationId $cid
        $req.CorrelationId | Should -Be $cid
    }

    It 'defaults IdentityKeys and DesiredState to empty hashtables when omitted' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $req.IdentityKeys | Should -BeOfType 'hashtable'
        $req.DesiredState | Should -BeOfType 'hashtable'
        $req.IdentityKeys.Count | Should -Be 0
        $req.DesiredState.Count | Should -Be 0
    }

    It 'leaves Changes as null when omitted' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Mover'
        $req.Changes | Should -BeNullOrEmpty
    }

    It 'accepts Changes when provided' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Mover' -Changes @{
            Attributes = @{
                Department = @{
                    From = 'Sales'
                    To   = 'IT'
                }
            }
        }

        $req.Changes | Should -BeOfType 'hashtable'
        $req.Changes.Attributes.Department.From | Should -Be 'Sales'
        $req.Changes.Attributes.Department.To   | Should -Be 'IT'
    }

    It 'treats Actor as optional (null when omitted)' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $req.Actor | Should -BeNullOrEmpty
    }

    It 'accepts Actor when provided' {
        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'alice@contoso.com'
        $req.Actor | Should -Be 'alice@contoso.com'
    }
}
