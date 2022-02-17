module Deserialization.FromBytes
  ( class FromBytes
  , fromBytes
  , fromBytesEffect
  ) where

import Prelude

import Data.Maybe (Maybe(Just, Nothing))
import Effect (Effect)
import Effect.Exception (throw)
import FfiHelpers (MaybeFfiHelper, maybeFfiHelper)
import Serialization.Types (Address, DataHash, Ed25519KeyHash, PlutusData, ScriptHash, TransactionHash, TransactionUnspentOutput, TransactionWitnessSet)
import Types.ByteArray (ByteArray)

-- | Calls `from_bytes` method for the appropriate type
class FromBytes a where
  fromBytes :: ByteArray -> Maybe a

instance FromBytes Address where
  fromBytes = _fromBytesAddress maybeFfiHelper

instance FromBytes ScriptHash where
  fromBytes = _fromBytesScriptHash maybeFfiHelper

instance FromBytes DataHash where
  fromBytes = _fromBytesDataHash maybeFfiHelper

instance FromBytes Ed25519KeyHash where
  fromBytes = _fromBytesEd25519KeyHash maybeFfiHelper

instance FromBytes TransactionHash where
  fromBytes = _fromBytesTransactionHash maybeFfiHelper

instance FromBytes PlutusData where
  fromBytes = _fromBytesPlutusData maybeFfiHelper

instance FromBytes TransactionUnspentOutput where
  fromBytes = _fromBytesTransactionUnspentOutput maybeFfiHelper

instance FromBytes TransactionWitnessSet where
  fromBytes = _fromBytesTransactionWitnessSet maybeFfiHelper

fromBytesEffect :: forall a. FromBytes a => ByteArray -> Effect a
fromBytesEffect bytes =
  case fromBytes bytes of
    Nothing -> throw "from_bytes() call failed"
    Just a -> pure a

foreign import _fromBytesAddress :: MaybeFfiHelper -> ByteArray -> Maybe Address
foreign import _fromBytesScriptHash :: MaybeFfiHelper -> ByteArray -> Maybe ScriptHash
foreign import _fromBytesDataHash :: MaybeFfiHelper -> ByteArray -> Maybe DataHash
foreign import _fromBytesEd25519KeyHash :: MaybeFfiHelper -> ByteArray -> Maybe Ed25519KeyHash
foreign import _fromBytesTransactionHash :: MaybeFfiHelper -> ByteArray -> Maybe TransactionHash
foreign import _fromBytesPlutusData :: MaybeFfiHelper -> ByteArray -> Maybe PlutusData
foreign import _fromBytesTransactionUnspentOutput :: MaybeFfiHelper -> ByteArray -> Maybe TransactionUnspentOutput
foreign import _fromBytesTransactionWitnessSet :: MaybeFfiHelper -> ByteArray -> Maybe TransactionWitnessSet