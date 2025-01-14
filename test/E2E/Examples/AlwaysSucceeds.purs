module Test.Ctl.E2E.Examples.AlwaysSucceeds (runExample) where

import Prelude

import Contract.Test.E2E
  ( SomeWallet(SomeWallet)
  , TestOptions
  , WalletPassword
  )
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Test.Ctl.E2E.Helpers
  ( delaySec
  , runE2ETest
  )
import Test.Ctl.TestM (TestPlanM)

runExample
  :: SomeWallet -> WalletPassword -> TestOptions -> TestPlanM (Aff Unit) Unit
runExample (SomeWallet { id, wallet, confirmAccess, sign }) password options =
  runE2ETest "AlwaysSucceeds" options wallet $ \example ->
    do
      confirmAccess id example
      sign id password example
      liftEffect $ log $
        " ...waiting before trying to spend script output (this will take a minute)"
      delaySec 60.0
      sign id password example
