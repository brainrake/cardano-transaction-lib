module Test.Ctl.Unit (main, testPlan) where

import Prelude

import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Mote.Monad (mapTest)
import Test.Ctl.Base64 as Base64
import Test.Ctl.ByteArray as ByteArray
import Test.Ctl.Data as Data
import Test.Ctl.Deserialization as Deserialization
import Test.Ctl.Hashing as Hashing
import Test.Ctl.Internal.Plutus.Conversion.Address as Plutus.Conversion.Address
import Test.Ctl.Internal.Plutus.Conversion.Value as Plutus.Conversion.Value
import Test.Ctl.Internal.Plutus.Time as Plutus.Time
import Test.Ctl.Metadata.Cip25 as Cip25
import Test.Ctl.NativeScript as NativeScript
import Test.Ctl.Ogmios.Address as Ogmios.Address
import Test.Ctl.Ogmios.Aeson as Ogmios.Aeson
import Test.Ctl.Ogmios.EvaluateTx as Ogmios.EvaluateTx
import Test.Ctl.OgmiosDatumCache as OgmiosDatumCache
import Test.Ctl.Parser as Parser
import Test.Ctl.ProtocolParams as ProtocolParams
import Test.Ctl.Serialization as Serialization
import Test.Ctl.Serialization.Address as Serialization.Address
import Test.Ctl.Serialization.Hash as Serialization.Hash
import Test.Ctl.TestM (TestPlanM)
import Test.Ctl.Transaction as Transaction
import Test.Ctl.TxOutput as TxOutput
import Test.Ctl.Types.Interval as Types.Interval
import Test.Ctl.Types.TokenName as Types.TokenName
import Test.Ctl.UsedTxOuts as UsedTxOuts
import Test.Ctl.Utils as Utils

-- Run with `spago test --main Test.Ctl.Unit`
main :: Effect Unit
main = launchAff_ do
  Utils.interpret testPlan

testPlan :: TestPlanM (Aff Unit) Unit
testPlan = do
  NativeScript.suite
  Base64.suite
  ByteArray.suite
  Cip25.suite
  Data.suite
  Deserialization.suite
  Hashing.suite
  Parser.suite
  Plutus.Conversion.Address.suite
  Plutus.Conversion.Value.suite
  Plutus.Time.suite
  Serialization.suite
  Serialization.Address.suite
  Serialization.Hash.suite
  Transaction.suite
  TxOutput.suite
  UsedTxOuts.suite
  OgmiosDatumCache.suite
  Ogmios.Address.suite
  Ogmios.Aeson.suite
  Ogmios.EvaluateTx.suite
  ProtocolParams.suite
  Types.TokenName.suite
  flip mapTest Types.Interval.suite \f -> liftEffect $ join $
    f <$> Types.Interval.eraSummariesFixture
      <*> Types.Interval.systemStartFixture
