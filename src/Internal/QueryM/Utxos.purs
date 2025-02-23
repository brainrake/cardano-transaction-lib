-- | A module for `QueryM` queries related to utxos.
module Ctl.Internal.QueryM.Utxos
  ( filterLockedUtxos
  , getUtxo
  , getWalletBalance
  , utxosAt
  , getWalletCollateral
  , getWalletUtxos
  ) where

import Prelude

import Control.Monad.Reader (withReaderT)
import Control.Monad.Reader.Trans (ReaderT, asks)
import Ctl.Internal.Address (addressToOgmiosAddress)
import Ctl.Internal.Cardano.Types.Transaction (TransactionOutput, UtxoMap)
import Ctl.Internal.Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  )
import Ctl.Internal.Cardano.Types.Value (Value)
import Ctl.Internal.Helpers as Helpers
import Ctl.Internal.QueryM
  ( QueryM
  , callCip30Wallet
  , getWalletAddresses
  , mkOgmiosRequest
  )
import Ctl.Internal.QueryM.Ogmios as Ogmios
import Ctl.Internal.Serialization.Address (Address)
import Ctl.Internal.TxOutput
  ( ogmiosTxOutToTransactionOutput
  , txOutRefToTransactionInput
  )
import Ctl.Internal.Types.Transaction (TransactionInput)
import Ctl.Internal.Types.UsedTxOuts (UsedTxOuts, isTxOutRefUsed)
import Ctl.Internal.Wallet (Wallet(Gero, Nami, Flint, Lode, Eternl, KeyWallet))
import Data.Array (head)
import Data.Array as Array
import Data.Bifunctor (bimap)
import Data.Bitraversable (bisequence)
import Data.Foldable (fold, foldr)
import Data.Map as Map
import Data.Maybe (Maybe(Nothing), fromMaybe, maybe)
import Data.Newtype (unwrap, wrap)
import Data.Traversable (for, for_, sequence, traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Data.UInt as UInt
import Effect.Aff (Aff)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)

--------------------------------------------------------------------------------
-- UtxosAt
--------------------------------------------------------------------------------

-- If required, we can change to Either with more granular error handling.
-- | Gets utxos at an (internal) `Address` in terms of (internal) `Cardano.Transaction.Types`.
-- | Results may vary depending on `Wallet` type.
utxosAt
  :: Address
  -> QueryM (Maybe UtxoMap)
utxosAt address =
  mkUtxoQuery
    <<< mkOgmiosRequest Ogmios.queryUtxosAtCall _.utxosAt
    $ addressToOgmiosAddress address

-- | Queries for UTxO given a transaction input filtering out collaterals.
getUtxo
  :: TransactionInput -> QueryM (Maybe TransactionOutput)
getUtxo ref = do
  res <- mkOgmiosRequest Ogmios.queryUtxoCall _.utxo ref
  pure $ convertUtxos res >>= Map.lookup ref

  where
  convertUtxos :: Ogmios.UtxoQR -> Maybe UtxoMap
  convertUtxos (Ogmios.UtxoQR utxoQueryResult) =
    let
      out'
        :: Array
             ( Maybe TransactionInput /\ Maybe
                 TransactionOutput
             )
      out' = Map.toUnfoldable utxoQueryResult
        <#> bimap
          txOutRefToTransactionInput
          ogmiosTxOutToTransactionOutput

      out
        :: Maybe
             ( Array
                 ( TransactionInput /\
                     TransactionOutput
                 )
             )
      out = out' <#> bisequence # sequence
    in
      Map.fromFoldable <$> out

mkUtxoQuery :: QueryM Ogmios.UtxoQR -> QueryM (Maybe UtxoMap)
mkUtxoQuery query = asks (_.runtime >>> _.wallet) >>= maybe allUtxosAt
  utxosAtByWallet
  where
  -- Add more wallet types here:
  utxosAtByWallet :: Wallet -> QueryM (Maybe UtxoMap)
  utxosAtByWallet = case _ of
    Nami _ -> cip30UtxosAt
    Gero _ -> cip30UtxosAt
    Flint _ -> cip30UtxosAt
    Eternl _ -> cip30UtxosAt
    Lode _ -> cip30UtxosAt
    KeyWallet _ -> allUtxosAt

  -- Gets all utxos at an (internal) Address in terms of (internal)
  -- Cardano.Transaction.Types.
  allUtxosAt :: QueryM (Maybe UtxoMap)
  allUtxosAt = convertUtxos <$> query
    where
    convertUtxos :: Ogmios.UtxoQR -> Maybe UtxoMap
    convertUtxos (Ogmios.UtxoQR utxoQueryResult) =
      let
        out'
          :: Array
               ( Maybe TransactionInput /\ Maybe
                   TransactionOutput
               )
        out' = Map.toUnfoldable utxoQueryResult
          <#> bimap
            txOutRefToTransactionInput
            ogmiosTxOutToTransactionOutput

        out
          :: Maybe
               ( Array
                   ( TransactionInput /\
                       TransactionOutput
                   )
               )
        out = out' <#> bisequence # sequence
      in
        Map.fromFoldable <$> out

  cip30UtxosAt :: QueryM (Maybe UtxoMap)
  cip30UtxosAt = getWalletCollateral >>= maybe
    (liftEffect $ throw "CIP-30 wallet missing collateral")
    \collateralUtxos ->
      allUtxosAt <#> \utxos' ->
        foldr
          ( \collateralUtxo utxoAcc ->
              (Map.delete (unwrap collateralUtxo).input) <$> utxoAcc
          )
          utxos'
          collateralUtxos

--------------------------------------------------------------------------------
-- Used Utxos helpers
--------------------------------------------------------------------------------

filterLockedUtxos :: UtxoMap -> QueryM UtxoMap
filterLockedUtxos utxos =
  withTxRefsCache $
    flip Helpers.filterMapWithKeyM utxos
      (\k _ -> not <$> isTxOutRefUsed (unwrap k))

withTxRefsCache
  :: forall (m :: Type -> Type) (a :: Type)
   . ReaderT UsedTxOuts Aff a
  -> QueryM a
withTxRefsCache = wrap <<< withReaderT (_.runtime >>> _.usedTxOuts)

getWalletBalance
  :: QueryM (Maybe Value)
getWalletBalance = do
  asks (_.runtime >>> _.wallet) >>= map join <<< traverse case _ of
    Nami wallet -> liftAff $ wallet.getBalance wallet.connection
    Gero wallet -> liftAff $ wallet.getBalance wallet.connection
    Eternl wallet -> liftAff $ wallet.getBalance wallet.connection
    Flint wallet -> liftAff $ wallet.getBalance wallet.connection
    Lode wallet -> liftAff $ wallet.getBalance wallet.connection
    KeyWallet _ -> do
      -- Implement via `utxosAt`
      mbAddresses <- getWalletAddresses

      map join $ for mbAddresses \addresses ->
        (map fold <<< sequence) <$> for addresses \address ->
          utxosAt address <#> map
            -- Combine `Value`s
            (fold <<< map _.amount <<< map unwrap <<< Map.values)

getWalletUtxos :: QueryM (Maybe UtxoMap)
getWalletUtxos = do
  asks (_.runtime >>> _.wallet) >>= map join <<< traverse case _ of
    Nami wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    Gero wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    Flint wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map
      toUtxoMap
    Eternl wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map
      toUtxoMap
    Lode wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    KeyWallet _ -> do
      mbAddress <- getWalletAddresses <#> (_ >>= head)
      map join $ for mbAddress utxosAt
  where
  toUtxoMap :: Array TransactionUnspentOutput -> UtxoMap
  toUtxoMap = Map.fromFoldable <<< map
    (unwrap >>> \({ input, output }) -> input /\ output)

getWalletCollateral :: QueryM (Maybe (Array TransactionUnspentOutput))
getWalletCollateral = do
  mbCollateralUTxOs <- asks (_.runtime >>> _.wallet) >>= maybe (pure Nothing)
    case _ of
      Nami wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Gero wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Flint wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Lode wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Eternl wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      KeyWallet kw -> do
        networkId <- asks $ _.config >>> _.networkId
        addr <- liftAff $ (unwrap kw).address networkId
        utxos <- utxosAt addr <#> fromMaybe Map.empty
          >>= filterLockedUtxos
        pparams <- asks $ _.runtime >>> _.pparams <#> unwrap
        let
          coinsPerUtxoUnit = pparams.coinsPerUtxoUnit
          maxCollateralInputs = UInt.toInt $
            pparams.maxCollateralInputs
        liftEffect $ (unwrap kw).selectCollateral coinsPerUtxoUnit
          maxCollateralInputs
          utxos
  for_ mbCollateralUTxOs \collateralUTxOs -> do
    pparams <- asks $ _.runtime >>> _.pparams
    let
      tooManyCollateralUTxOs =
        UInt.fromInt (Array.length collateralUTxOs) >
          (unwrap pparams).maxCollateralInputs
    when tooManyCollateralUTxOs do
      liftEffect $ throw tooManyCollateralUTxOsError
  pure mbCollateralUTxOs
  where
  tooManyCollateralUTxOsError =
    "Wallet returned too many UTxOs as collateral. This is likely a bug in \
    \the wallet."
