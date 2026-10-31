@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.IdLE.Step.Emit'; With = @{ Message = 'Step 1' } }
    @{ Name = 'Step2'; Type = 'Test.IdLE.Step.Emit'; With = @{ Message = 'Step 2' } }
  )
}
