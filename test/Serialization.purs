module Test.Ctl.Serialization (suite) where

import Prelude

import Ctl.Internal.Cardano.Types.Transaction (Transaction)
import Ctl.Internal.Deserialization.FromBytes (fromBytes, fromBytesEffect)
import Ctl.Internal.Deserialization.Transaction (convertTransaction) as TD
import Ctl.Internal.Serialization (convertTransaction) as TS
import Ctl.Internal.Serialization (convertTxOutput, toBytes)
import Ctl.Internal.Serialization.PlutusData (convertPlutusData)
import Ctl.Internal.Serialization.Types (TransactionHash)
import Ctl.Internal.Types.ByteArray (byteArrayToHex, hexToByteArrayUnsafe)
import Ctl.Internal.Types.PlutusData as PD
import Data.BigInt as BigInt
import Data.Either (hush)
import Data.Maybe (isJust)
import Data.Tuple.Nested ((/\))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Mote (group, test)
import Test.Ctl.Fixtures
  ( txBinaryFixture1
  , txBinaryFixture2
  , txBinaryFixture3
  , txBinaryFixture4
  , txBinaryFixture5
  , txBinaryFixture6
  , txFixture1
  , txFixture2
  , txFixture3
  , txFixture4
  , txFixture5
  , txFixture6
  , txOutputBinaryFixture1
  , txOutputFixture1
  )
import Test.Ctl.TestM (TestPlanM)
import Test.Ctl.Utils (errMaybe)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Untagged.Union (asOneOf)

suite :: TestPlanM (Aff Unit) Unit
suite = do
  group "cardano-serialization-lib bindings" $ do
    group "conversion between types" $ do
      test "newTransactionHash" do
        let
          txString =
            "5d677265fa5bb21ce6d8c7502aca70b9316d10e958611f3c6b758f65ad959996"
          txBytes = hexToByteArrayUnsafe txString
        _txHash :: TransactionHash <- liftEffect $ fromBytesEffect txBytes
        pure unit
      test "PlutusData #1 - Constr" $ do
        let
          datum = PD.Constr (BigInt.fromInt 1)
            [ PD.Integer (BigInt.fromInt 1)
            , PD.Integer (BigInt.fromInt 2)
            ]
        (convertPlutusData datum $> unit) `shouldSatisfy` isJust
      test "PlutusData #2 - Map" $ do
        let
          datum =
            PD.Map
              [ PD.Integer (BigInt.fromInt 1) /\ PD.Integer (BigInt.fromInt 2)
              , PD.Integer (BigInt.fromInt 3) /\ PD.Integer (BigInt.fromInt 4)
              ]
        (convertPlutusData datum $> unit) `shouldSatisfy` isJust
      test "PlutusData #3 - List" $ do
        let
          datum = PD.List
            [ PD.Integer (BigInt.fromInt 1), PD.Integer (BigInt.fromInt 2) ]
        (convertPlutusData datum $> unit) `shouldSatisfy` isJust
      test "PlutusData #4 - List" $ do
        let
          datum = PD.List
            [ PD.Integer (BigInt.fromInt 1), PD.Integer (BigInt.fromInt 2) ]
        (convertPlutusData datum $> unit) `shouldSatisfy` isJust
      test "PlutusData #5 - Bytes" $ do
        let datum = PD.Bytes $ hexToByteArrayUnsafe "00ff"
        (convertPlutusData datum $> unit) `shouldSatisfy` isJust
      test
        "PlutusData #6 - Integer 0 (regression to https://github.com/Plutonomicon/cardano-transaction-lib/issues/488 ?)"
        $ do
            let
              datum = PD.Integer (BigInt.fromInt 0)
            datum' <- errMaybe "Cannot convertPlutusData" $ convertPlutusData
              datum
            let bytes = toBytes (asOneOf datum')
            byteArrayToHex bytes `shouldEqual` "00"
      test "TransactionOutput serialization" $ liftEffect do
        txo <- convertTxOutput txOutputFixture1
        let bytes = toBytes (asOneOf txo)
        byteArrayToHex bytes `shouldEqual` txOutputBinaryFixture1
      test "Transaction serialization #1" $
        serializeTX txFixture1 txBinaryFixture1
      test "Transaction serialization #2 - tokens" $
        serializeTX txFixture2 txBinaryFixture2
      test "Transaction serialization #3 - ada" $
        serializeTX txFixture3 txBinaryFixture3
      test "Transaction serialization #4 - ada + mint + certificates" $
        serializeTX txFixture4 txBinaryFixture4
      test "Transaction serialization #5 - plutus script" $
        serializeTX txFixture5 txBinaryFixture5
      test "Transaction serialization #6 - metadata" $
        serializeTX txFixture6 txBinaryFixture6
    group "Transaction Roundtrips" $ do
      test "Deserialization is inverse to serialization #1" $
        txSerializedRoundtrip txFixture1
      test "Deserialization is inverse to serialization #2" $
        txSerializedRoundtrip txFixture2
      test "Deserialization is inverse to serialization #3" $
        txSerializedRoundtrip txFixture3
      test "Deserialization is inverse to serialization #4" $
        txSerializedRoundtrip txFixture4
      test "Deserialization is inverse to serialization #5" $
        txSerializedRoundtrip txFixture5
      test "Deserialization is inverse to serialization #6" $
        txSerializedRoundtrip txFixture6

serializeTX :: Transaction -> String -> Aff Unit
serializeTX tx fixture =
  liftEffect $ do
    cslTX <- TS.convertTransaction $ tx
    let bytes = toBytes (asOneOf cslTX)
    byteArrayToHex bytes `shouldEqual` fixture

txSerializedRoundtrip :: Transaction -> Aff Unit
txSerializedRoundtrip tx = do
  cslTX <- liftEffect $ TS.convertTransaction tx
  let serialized = toBytes (asOneOf cslTX)
  deserialized <- errMaybe "Cannot deserialize bytes" $ fromBytes
    serialized
  expected <- errMaybe "Cannot convert TX from CSL to CTL" $ hush $
    TD.convertTransaction deserialized
  tx `shouldEqual` expected
