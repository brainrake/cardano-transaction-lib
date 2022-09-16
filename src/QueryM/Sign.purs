module QueryM.Sign
  ( signTransaction
  ) where

import Prelude

import Cardano.Types.Transaction (UtxoMap, _witnessSet, _body, _inputs)
import Cardano.Types.Transaction as Transaction
import Data.Array (elem, fromFoldable)
import Data.Lens ((<>~))
import Data.Lens.Getter ((^.))
import Data.Map as Map
import Data.Maybe (Maybe(Just), fromMaybe)
import Data.Newtype (unwrap, wrap)
import Data.Traversable (traverse)
import Data.Tuple.Nested ((/\))
import Effect.Aff (delay, error)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (throw)
import Helpers (liftedM)
import QueryM (QueryM, callCip30Wallet, getWalletAddresses, withMWallet)
import QueryM.Utxos (getUtxo, getWalletUtxos)
import Types.Transaction (TransactionInput)
import Wallet (Wallet(KeyWallet, Lode, Eternl, Flint, Gero, Nami))

signTransaction
  :: Transaction.Transaction -> QueryM (Maybe Transaction.Transaction)
signTransaction tx = withMWallet case _ of
  Nami nami -> liftAff $ callCip30Wallet nami \nw -> flip nw.signTx tx
  Gero gero -> liftAff $ callCip30Wallet gero \nw -> flip nw.signTx tx
  Flint flint -> liftAff $ callCip30Wallet flint \nw -> flip nw.signTx tx
  Eternl eternl -> do
    let
      txInputs :: Array TransactionInput
      txInputs = fromFoldable $ tx ^. _body <<< _inputs

    ownAddrs <- liftedM (error "Could not get addresses") getWalletAddresses
    ownInputUtxos <- txInputs #
      traverse
        ( \txInput -> do
            utxo <- liftedM (error "Could not get utxo") $ getUtxo txInput
            pure (txInput /\ utxo)
        ) >>> map
        ( Map.fromFoldable >>> Map.filter
            ( flip elem ownAddrs
                <<< _.address
                <<< unwrap
            )
        )
    delayUntilUtxosSynchronized ownInputUtxos
    liftAff $ callCip30Wallet eternl \nw -> flip nw.signTx tx
  Lode lode -> liftAff $ callCip30Wallet lode \nw -> flip nw.signTx tx
  KeyWallet kw -> liftAff do
    witnessSet <- (unwrap kw).signTx tx
    pure $ Just (tx # _witnessSet <>~ witnessSet)

-- | Waits till all UTxOs in a given map appear in the UTxOs provided by wallet.
-- | This is a hacky solution to the problem of Eternl not seeing UTxOs that
-- | hasn't been fully confirmed at the moment of a `sign()` call.
-- | Since it can't detect their origin, it can't know which of the private keys
-- | to use for signing. As a result, we get `MissingVKeyWitnesses`.
delayUntilUtxosSynchronized :: UtxoMap -> QueryM Unit
delayUntilUtxosSynchronized ownInputUtxos =
  -- As clarified in Eternl discord, they synchronize with the server every 2
  -- minutes, so 150 seconds would probably be enough to also account for
  -- possible network latency.
  go 150
  where
  go attempts = do
    walletUtxos <- getWalletUtxos <#> fromMaybe Map.empty

    liftEffect <<< log $ "wallet utxos:" <> show walletUtxos
    liftEffect <<< log $ "ownInputsUtxo" <> show ownInputUtxos

    unless (ownInputUtxos `Map.isSubmap` walletUtxos) do
      liftAff $ delay $ wrap $ 1000.0
      when (attempts == 0) do
        liftEffect $ throw $
          "delayUntilUtxosSynchronized: timeout while waiting for wallet"
            <> " UTxO set and CTL query layer UTxO set to synchronize. UTxOs"
            <> " from Ogmios: "
            <> show ownInputUtxos
            <> ", UTxOs from wallet: "
            <> show walletUtxos
            <> ", UTxOs that didn't appear in the wallet: "
            <>
              show (Map.difference ownInputUtxos walletUtxos)
      go (attempts - 1)
