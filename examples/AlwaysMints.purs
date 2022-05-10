-- | This module demonstrates how the `Contract` interface can be used to build,
-- | balance, and submit a smart-contract transaction. It creates a transaction
-- | that mints a value using the `AlwaysSucceeds` policy
-- |
-- | * Prerequisites
-- |   - A Chromium-based browser (for Nami compatibility)
--
-- |   - A Nami wallet funded with test Ada ("tAda") and collateral set, If you need
-- |     tAda, visit https://testnets.cardano.org/en/testnets/cardano/tools/faucet/
--
-- | * How to run
--
-- |   The `Contract` interface requires several external services to be running.
-- |   From the repository root, run `nix run .#ctl-runtime` to launch all
-- |   required services
--
-- |   Once all of the services are *fully synced*, run:
--
-- |   - `make run-dev` and visit `localhost:4008`. You may be prompted to enable
-- |     access to your wallet if you have not run this example before. You will
-- |     also be prompted to sign the transaction using your Nami password

module Examples.AlwaysMints (main) where

import Contract.Prelude

import Contract.Monad
  ( ContractConfig(ContractConfig)
  , launchAff_
  , liftContractM
  , liftedE
  , liftedM
  , logInfo'
  , runContract_
  , traceContractConfig
  )
import Contract.Prim.ByteArray (byteArrayFromAscii)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (MintingPolicy)
import Contract.Transaction
  ( BalancedSignedTransaction(BalancedSignedTransaction)
  , balanceAndSignTx
  , submit
  )
import Contract.TxConstraints as Constraints
import Contract.Value as Value
import Contract.Wallet (mkNamiWalletAff)
import Data.Argonaut (decodeJson, fromString)
import Data.BigInt as BigInt

main :: Effect Unit
main = launchAff_ $ do
  wallet <- Just <$> mkNamiWalletAff
  cfg <- over ContractConfig _ { wallet = wallet } <$> traceContractConfig
  runContract_ cfg $ do
    mp <- liftContractM "Invalid script JSON" $ alwaysMintsPolicy
    cs <- liftedM "Cannot get cs" $ Value.scriptCurrencySymbol mp
    tn <- liftContractM "Cannot make token name"
      $ Value.mkTokenName
      =<< byteArrayFromAscii "TheToken"

    let
      -- Note that CTL does not have explicit equivalents of Plutus'
      -- `mustPayToTheScript` or `mustPayToOtherScript`, as we have no notion
      -- of a "current" script. Thus, we have the single constraint
      -- `mustPayToScript`, and all scripts must be explicitly provided to build
      -- the transaction (see the value for `lookups` below as well)
      constraints :: Constraints.TxConstraints Void Void
      constraints = Constraints.mustMintValue
        $ Value.singleton cs tn
        $ BigInt.fromInt 100

      lookups :: Lookups.ScriptLookups Void
      lookups = Lookups.mintingPolicy mp

    ubTx <- liftedE $ Lookups.mkUnbalancedTx lookups constraints
    BalancedSignedTransaction bsTx <-
      liftedM "Failed to balance/sign tx" $ balanceAndSignTx ubTx
    txId <- submit bsTx.signedTxCbor
    logInfo' $ "Tx ID: " <> show txId

alwaysMintsPolicy :: Maybe MintingPolicy
alwaysMintsPolicy = hush $ decodeJson $ fromString
  "59094c0100003232323322332233322232333222333222333333332222222233223333322222\
  \3333222233322233223322332233322233223322332233223322323232323232323232323232\
  \3232323232323232323232323233500101122031122223005330033004002300600125335302\
  \c001104d13501835304c33573892010250640004d4988c8c8c8c8c8c8cccd5cd19b8735573aa\
  \00a90001280112803a4c26603ca002a0042600c6ae8540084c050d5d09aba25001135573ca00\
  \226ea80084d405d262323232323232323232323232323232323232323232323333573466e1cd\
  \55cea80aa40004a0044a02e9309999999999817a800a8012801a8022802a8032803a8042804a\
  \805099a81080b1aba15012133502001635742a0202666aa032eb94060d5d0a8070999aa80c3a\
  \e501735742a018266a03a0426ae8540284cd4070cd54078085d69aba15008133501675a6ae85\
  \40184cd4069d71aba150041335019335501b75c0346ae8540084c080d5d09aba25001135744a\
  \00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba2500113557\
  \3ca00226ea80084d40592623232323232323333573466e1cd55cea802a40004a0044a00e9309\
  \98102800a8010980b9aba1500213005357426ae8940044d55cf280089baa0021350154988c8c\
  \8c8c8c8c8c8c8cccd5cd19b8735573aa00e90001280112804a4c2666046a002a004a00626010\
  \6ae8540104ccd54029d728049aba15002133500775c6ae84d5d1280089aba25001135573ca00\
  \226ea80084d40512623232323232323333573466e1cd55cea802a40004a0044a00e930998112\
  \800a8010980a1aba150021335005012357426ae8940044d55cf280089baa002135013498488c\
  \8c8c8c8c8c8cccd5cd19b87500448000940089401126135025500113006357426aae79400c4c\
  \ccd5cd19b875001480089408c9401126135573aa00226ea80084d404d261335500175ceb4448\
  \88c8c8c004dd58019a80090008918009aa82591191919191919191999aab9f0085504c253002\
  \12001051350022200135001220023555505212223300321300a357440124266a09ea00aa6006\
  \24002266aa09ea002a004260106aae7540084c018d55cf280089aba100112232323232323233\
  \33573466e1cd55cea802a40004a0044a00e93099a8122800a801099a8038031aba1500213350\
  \07005357426ae8940044d55cf280089baa002135010498488c8c8c8c8c8c8cccd5cd19b87355\
  \73aa00a90001280112803a4c266a04ea002a004266a01000c6ae8540084c020d5d09aba25001\
  \135573ca00226ea80084d403d261223232323232323333573466e1cd55cea802a40004a0044a\
  \00e93099a8122800a801099a8038031aba1500213007357426ae8940044d55cf280089baa002\
  \13500e498488c8c8c8c8c8c8c8cccd5cd19b87500548010940b4940092613333573466e1d401\
  \1200225002250044984d40b140044c018d5d09aab9e500313333573466e1d400520002502a25\
  \0044984d55cea80089baa00213500d4988c8c8c8cccd5cd19b87500248008809494009261333\
  \3573466e1d400520002023250034984d55ce9baa00213500b498488c8c8c004dd60019a80090\
  \008918009aa822111999aab9f00125042233504130063574200460066ae8800810c800444888\
  \c8c8c8c8c8c8cccd5cd19b8735573aa00a90001280112803a4c266aa08ca002a0042600e6ae8\
  \540084c014d5d09aba25001135573ca00226ea80084d40292623232323232323232323232323\
  \2323333573466e1d4029200625002250044984c0cd40044c038d5d09aab9e500b13333573466\
  \e1d401d200425002250044984c0b940044c030d5d09aab9e500813333573466e1d4011200225\
  \002250044984c0a940044c02cd5d09aab9e500513333573466e1d4005200025003250064984d\
  \55cea80189814280089bae357426aae7940044dd500109a803a4c46464646464646464646464\
  \64646464646464646464646464646666ae68cdc3a80aa4018408a4a0049309999ab9a3370ea0\
  \28900510229280124c26666ae68cdc3a809a40104a0044a00c9309981fa800a80109bae35742\
  \a00426eb4d5d09aba25001135573ca02426666ae68cdc3a8072400c4a0044a00c9309981da80\
  \0a80109bae35742a00426eb8d5d09aba25001135573ca01a26666ae68cdc3a804a40084a0044\
  \a00c9309981d2800a801098069aba150021375c6ae84d5d1280089aab9e500813333573466e1\
  \d4011200225002250044984c0d940044c020d5d09aab9e500513333573466e1d400520002500\
  \3250064984d55cea801898182800898021aba135573ca00226ea80084d401926232323232323\
  \23232323232323333573466e1d4021200225002250084984ccc0ed40054009400c4dd69aba15\
  \0041375a6ae8540084dd69aba135744a00226ae8940044d55cf280289999ab9a3370ea002900\
  \0128019280324c26aae75400c4c0d140044c010d5d09aab9e50011375400426a00a931191919\
  \19191919191999ab9a3370ea0089001128011280224c26072a00226eb8d5d09aab9e50051333\
  \3573466e1d4005200025003250064984d55cea8018981b280089bae357426aae7940044dd500\
  \109a80224c46464646464646666ae68cdc39aab9d500548000940089401d2613302950015002\
  \1300635742a00426eb4d5d09aba25001135573ca00226ea80084d400d2623232323333573466\
  \e1cd55cea801240004a0044a0089309bae357426aae7940044dd500109a80124c24c44246600\
  \20060044002444444444424666666666600201601401201000e00c00a0080060044002442466\
  \0020060044002444246660020080060044002442466002006004400224244600400622440022\
  \4002244246600200600424002244246600200600424002244246600200600424002244004244\
  \00240022424446006008224440042244400224002424444600800a424444600600a424444600\
  \400a424444600200a40024424660020060044002424444444600e01044244444446600c01201\
  \0424444444600a01024444444008244444440064424444444660040120104424444444660020\
  \1201040024244600400644424466600200a008006400242446004006424460020064002224a0\
  \0822440042442446600200800624002240024002224424660020060042240022246460020024\
  \46600660040040022222466a0044246600246a00644600400646a00644600200600224646460\
  \020024466006600400400244246a6008246a60080066a006002003"
