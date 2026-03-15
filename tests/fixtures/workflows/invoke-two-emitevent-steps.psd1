@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Step 1' } }
    @{ Name = 'Step2'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Step 2' } }
  )
}
