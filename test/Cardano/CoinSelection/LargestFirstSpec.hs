{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.CoinSelection.LargestFirstSpec
    ( spec
    ) where

import Prelude

import Cardano.CoinSelection
    ( CoinSelection (..), CoinSelectionOptions (..), ErrCoinSelection (..) )
import Cardano.CoinSelection.LargestFirst
    ( largestFirst )
import Cardano.CoinSelectionSpec
    ( CoinSelProp (..)
    , CoinSelectionFixture (..)
    , CoinSelectionResult (..)
    , ErrValidation (..)
    , alwaysFail
    , coinSelectionUnitTest
    , noValidation
    )
import Cardano.Types
    ( Coin (..), TxOut (..), UTxO (..), excluding )
import Control.Monad
    ( unless )
import Control.Monad.Trans.Except
    ( runExceptT )
import Data.Either
    ( isRight )
import Data.Functor.Identity
    ( Identity (runIdentity) )
import Data.List.NonEmpty
    ( NonEmpty (..) )
import Test.Hspec
    ( Spec, describe, it, shouldSatisfy )
import Test.QuickCheck
    ( Property, property, (===), (==>) )

import qualified Data.List as L
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

spec :: Spec
spec = do
    describe "Coin selection : LargestFirst algorithm unit tests" $ do
        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionResult
                { rsInputs = [17]
                , rsChange = []
                , rsOutputs = [17]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [10,10,17]
                , txOutputs = 17 :| []
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionResult
                { rsInputs = [17]
                , rsChange = [16]
                , rsOutputs = [1]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,10,17]
                , txOutputs = 1 :| []
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionResult
                { rsInputs = [12, 17]
                , rsChange = [11]
                , rsOutputs = [18]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,10,17]
                , txOutputs = 18 :| []
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionResult
                { rsInputs = [10, 12, 17]
                , rsChange = [9]
                , rsOutputs = [30]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,10,17]
                , txOutputs = 30 :| []
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionResult
                { rsInputs = [6,10,5]
                , rsChange = [5,4]
                , rsOutputs = [11,1]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 3
                , validateSelection = noValidation
                , utxoInputs = [1,2,10,6,5]
                , txOutputs = 11 :| [1]
                })

        coinSelectionUnitTest largestFirst "not enough coins"
            (Left $ ErrNotEnoughMoney 39 40)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,10,17]
                , txOutputs = 40 :| []
                })

        coinSelectionUnitTest largestFirst "not enough coin & not fragmented enough"
            (Left $ ErrNotEnoughMoney 39 43)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,10,17]
                , txOutputs = 40 :| [1,1,1]
                })

        coinSelectionUnitTest largestFirst "enough coins, but not fragmented enough"
            (Left $ ErrUtxoNotEnoughFragmented 3 4)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,20,17]
                , txOutputs = 40 :| [1,1,1]
                })

        coinSelectionUnitTest largestFirst
            "enough coins, fragmented enough, but one output depletes all inputs"
            (Left ErrInputsDepleted)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [12,20,17]
                , txOutputs = 40 :| [1]
                })

        coinSelectionUnitTest
            largestFirst
            "enough coins, fragmented enough, but the input needed to stay for the next output is depleted"
            (Left ErrInputsDepleted)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = noValidation
                , utxoInputs = [20,20,10,5]
                , txOutputs = 41 :| [6]
                })

        coinSelectionUnitTest largestFirst "each output needs <maxNumOfInputs"
            (Left $ ErrMaximumInputsReached 9)
            (CoinSelectionFixture
                { maxNumOfInputs = 9
                , validateSelection = noValidation
                , utxoInputs = replicate 100 1
                , txOutputs = NE.fromList (replicate 100 1)
                })

        coinSelectionUnitTest largestFirst "each output needs >maxNumInputs"
            (Left $ ErrMaximumInputsReached 9)
            (CoinSelectionFixture
                { maxNumOfInputs = 9
                , validateSelection = noValidation
                , utxoInputs = replicate 100 1
                , txOutputs = NE.fromList (replicate 10 10)
                })

        coinSelectionUnitTest largestFirst
            "enough coins but, strict maximumNumberOfInputs"
            (Left $ ErrMaximumInputsReached 2)
            (CoinSelectionFixture
                { maxNumOfInputs = 2
                , validateSelection = noValidation
                , utxoInputs = [1,2,10,6,5]
                , txOutputs = 11 :| [1]
                })

        coinSelectionUnitTest largestFirst "custom validation"
            (Left $ ErrInvalidSelection ErrValidation)
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , validateSelection = alwaysFail
                , utxoInputs = [1,1]
                , txOutputs = 2 :| []
                })

    describe "Coin selection properties : LargestFirst algorithm" $ do
        it "forall (UTxO, NonEmpty TxOut), running algorithm twice yields \
            \exactly the same result"
            (property propDeterministic)
        it "forall (UTxO, NonEmpty TxOut), there's at least as many selected \
            \inputs as there are requested outputs"
            (property propAtLeast)
        it "forall (UTxO, NonEmpty TxOut), for all selected input, there's no \
            \bigger input in the UTxO that is not already in the selected inputs"
            (property propInputDecreasingOrder)

{-------------------------------------------------------------------------------
                                  Properties
-------------------------------------------------------------------------------}

propDeterministic
    :: CoinSelProp
    -> Property
propDeterministic (CoinSelProp utxo txOuts) = do
    let opts = CoinSelectionOptions (const 100) noValidation
    let resultOne = runIdentity $ runExceptT $ largestFirst opts txOuts utxo
    let resultTwo = runIdentity $ runExceptT $ largestFirst opts txOuts utxo
    resultOne === resultTwo

propAtLeast
    :: CoinSelProp
    -> Property
propAtLeast (CoinSelProp utxo txOuts) =
    isRight selection ==> let Right (s,_) = selection in prop s
  where
    prop (CoinSelection inps _ _) =
        L.length inps `shouldSatisfy` (>= NE.length txOuts)
    selection = runIdentity $ runExceptT $
        largestFirst (CoinSelectionOptions (const 100) noValidation) txOuts utxo

propInputDecreasingOrder
    :: CoinSelProp
    -> Property
propInputDecreasingOrder (CoinSelProp utxo txOuts) =
    isRight selection ==> let Right (s,_) = selection in prop s
  where
    prop (CoinSelection inps _ _) =
        let
            utxo' = (Map.toList . getUTxO) $
                utxo `excluding` (Set.fromList . map fst $ inps)
        in unless (L.null utxo') $
            (getExtremumValue L.minimum inps)
            `shouldSatisfy`
            (>= (getExtremumValue L.maximum utxo'))
    getExtremumValue f = f . map (getCoin . coin . snd)
    selection = runIdentity $ runExceptT $
        largestFirst (CoinSelectionOptions (const 100) noValidation) txOuts utxo
