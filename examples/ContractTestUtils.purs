-- | This module demonstrates how various assertions from `Contract.Test.Utils`
-- | can be used to test `Contract`s. It creates a transaction with metadata 
-- | that performs three actions: (1) sends some amount of Ada to the receiver's 
-- | address, (2) mints the specified non-Ada value (3) then sends it to the 
-- | owner's address with a datum attached. 
module Ctl.Examples.ContractTestUtils
  ( ContractParams(ContractParams)
  , contract
  ) where

import Contract.Prelude

import Contract.Address
  ( Address
  , PaymentPubKeyHash
  , StakePubKeyHash
  , getNetworkId
  , getWalletAddress
  , ownPaymentPubKeyHash
  , ownStakePubKeyHash
  , payPubKeyHashBaseAddress
  , payPubKeyHashEnterpriseAddress
  )
import Contract.AuxiliaryData (setTxMetadata)
import Contract.Hashing (datumHash)
import Contract.Log (logInfo')
import Contract.Monad (Contract, liftContractM, liftedE, liftedM)
import Contract.PlutusData (Datum, OutputDatum(OutputDatumHash))
import Contract.ScriptLookups as Lookups
import Contract.Scripts (MintingPolicy)
import Contract.Test.Utils
  ( ContractBasicAssertion
  , ContractWrapAssertion
  , label
  )
import Contract.Test.Utils as TestUtils
import Contract.Transaction
  ( ScriptRef(PlutusScriptRef)
  , TransactionHash
  , TransactionOutputWithRefScript
  , awaitTxConfirmed
  , balanceAndSignTxE
  , getTxFinalFee
  , lookupTxHash
  , submit
  )
import Contract.TxConstraints (DatumPresence(DatumWitness))
import Contract.TxConstraints as Constraints
import Contract.Utxos (utxosAt)
import Contract.Value (CurrencySymbol, TokenName, Value)
import Contract.Value (lovelaceValueOf, singleton) as Value
import Ctl.Examples.Helpers (mustPayToPubKeyStakeAddress) as Helpers
-- TODO Re-export into Contract or drop the usage
-- https://github.com/Plutonomicon/cardano-transaction-lib/issues/1042
import Ctl.Internal.Metadata.Cip25.V2 (Cip25Metadata)
import Ctl.Internal.Plutus.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  , _output
  )
import Data.BigInt (BigInt)
import Data.Lens (view)
import Data.Map (empty) as Map

newtype ContractParams = ContractParams
  { receiverPkh :: PaymentPubKeyHash
  , receiverSkh :: Maybe StakePubKeyHash
  , adaToSend :: BigInt
  , mintingPolicy :: MintingPolicy
  , tokensToMint :: Tuple3 CurrencySymbol TokenName BigInt
  , datumToAttach :: Datum
  , txMetadata :: Cip25Metadata
  }

derive instance Newtype ContractParams _

type ContractResult =
  { txHash :: TransactionHash
  , txFinalFee :: BigInt
  , txOutputUnderTest :: TransactionOutputWithRefScript
  }

mkAssertions
  :: ContractParams
  -> Contract ()
       ( Array (ContractWrapAssertion () ContractResult)
           /\ Array (ContractBasicAssertion () ContractResult Unit)
       )
mkAssertions params@(ContractParams p) = do
  senderAddress <-
    liftedM "Failed to get sender address" getWalletAddress
  receiverAddress <-
    liftedM "Failed to get receiver address" (getReceiverAddress params)
  dhash <- liftContractM "Failed to hash datum" $ datumHash $ p.datumToAttach
  pure
    $
      [ TestUtils.assertGainAtAddress' (label receiverAddress "Receiver")
          p.adaToSend

      , TestUtils.assertLossAtAddress (label senderAddress "Sender")
          \{ txFinalFee } -> pure (p.adaToSend + txFinalFee)

      , TestUtils.assertTokenGainAtAddress' (label senderAddress "Sender")
          ( uncurry3 (\cs tn amount -> cs /\ tn /\ amount)
              p.tokensToMint
          )
      ]
    /\
      [ \{ txOutputUnderTest } ->
          TestUtils.assertOutputHasDatum (OutputDatumHash dhash)
            (label txOutputUnderTest "Sender's output with datum hash")

      , \{ txOutputUnderTest } ->
          TestUtils.assertOutputHasRefScript
            (PlutusScriptRef $ unwrap p.mintingPolicy)
            (label txOutputUnderTest "Sender's output with reference script")

      , \{ txHash } ->
          TestUtils.assertTxHasMetadata "CIP25 Metadata" txHash p.txMetadata
      ]

contract :: ContractParams -> Contract () Unit
contract params@(ContractParams p) = do
  logInfo' "Running Examples.ContractTestUtils"
  ownPkh <- liftedM "Failed to get own PKH" ownPaymentPubKeyHash
  ownSkh <- ownStakePubKeyHash
  let
    mustPayToPubKeyStakeAddressWithDatumAndScriptRef =
      ownSkh # maybe Constraints.mustPayToPubKeyWithDatumAndScriptRef
        \skh pkh ->
          Constraints.mustPayToPubKeyAddressWithDatumAndScriptRef pkh skh

    adaValue :: Value
    adaValue = Value.lovelaceValueOf p.adaToSend

    nonAdaValue :: Value
    nonAdaValue = uncurry3 Value.singleton p.tokensToMint

    constraints :: Constraints.TxConstraints Void Void
    constraints = mconcat
      [ Helpers.mustPayToPubKeyStakeAddress p.receiverPkh p.receiverSkh adaValue

      , Constraints.mustMintValue nonAdaValue

      , mustPayToPubKeyStakeAddressWithDatumAndScriptRef ownPkh p.datumToAttach
          DatumWitness
          (PlutusScriptRef $ unwrap p.mintingPolicy)
          nonAdaValue
      ]

    lookups :: Lookups.ScriptLookups Void
    lookups = Lookups.mintingPolicy p.mintingPolicy

  assertions <- mkAssertions params
  void $ TestUtils.withAssertions assertions do
    unbalancedTx <- liftedE $ Lookups.mkUnbalancedTx lookups constraints
    unbalancedTxWithMetadata <- setTxMetadata unbalancedTx p.txMetadata
    balancedSignedTx <- liftedE $ balanceAndSignTxE unbalancedTxWithMetadata

    txId <- submit balancedSignedTx
    logInfo' $ "Tx ID: " <> show txId

    awaitTxConfirmed txId
    logInfo' "Tx submitted successfully!"

    senderAddress <- liftedM "Failed to get sender address" getWalletAddress
    utxos <- fromMaybe Map.empty <$> utxosAt senderAddress

    txOutputUnderTest <-
      view _output <$>
        liftContractM "Could not find required unspent output with datum hash"
          (find hasDatumHash $ lookupTxHash txId utxos)

    pure
      { txHash: txId
      , txFinalFee: getTxFinalFee balancedSignedTx
      , txOutputUnderTest
      }
  where
  hasDatumHash :: TransactionUnspentOutput -> Boolean
  hasDatumHash = view _output >>> unwrap >>> _.output >>> unwrap >>> _.datum >>>
    case _ of
      OutputDatumHash _ -> true
      _ -> false

getReceiverAddress :: ContractParams -> Contract () (Maybe Address)
getReceiverAddress (ContractParams { receiverPkh, receiverSkh }) =
  getNetworkId <#> \networkId ->
    case receiverSkh of
      Just skh ->
        payPubKeyHashBaseAddress networkId receiverPkh skh
      Nothing ->
        payPubKeyHashEnterpriseAddress networkId receiverPkh
