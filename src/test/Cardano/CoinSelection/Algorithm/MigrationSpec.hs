{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.CoinSelection.Algorithm.MigrationSpec
    ( spec
    ) where

import Prelude

import Cardano.CoinSelection
    ( CoinMap (..)
    , CoinMapEntry (..)
    , CoinSelection (..)
    , coinMapToList
    , coinMapValue
    , sumChange
    , sumInputs
    )
import Cardano.CoinSelection.Algorithm.Migration
    ( BatchSize (..), idealBatchSize, selectCoins )
import Cardano.CoinSelection.Fee
    ( DustThreshold (..)
    , Fee (..)
    , FeeBalancingPolicy (..)
    , FeeEstimator (..)
    , FeeOptions (..)
    )
import Cardano.CoinSelection.FeeSpec ( FeeParameters, stableEstimator )
import Cardano.CoinSelectionSpec
    ()
import Cardano.Test.Utilities
    ( InputId
    , OutputId
    , genInputId
    , mkInputId
    , unsafeCoin
    , unsafeDustThreshold
    , unsafeFee
    )
import Data.Function ( (&) )
import Internal.Coin ( Coin, coinToIntegral )
import Numeric.Natural ( Natural )
import Test.Hspec ( Spec, SpecWith, describe, it, shouldSatisfy )
import Test.QuickCheck
    ( Arbitrary (..)
    , Gen
    , Property
    , arbitrarySizedIntegral
    , choose
    , conjoin
    , counterexample
    , frequency
    , label
    , property
    , vectorOf
    , withMaxSuccess
    , (===)
    )
import Test.QuickCheck.Monadic ( monadicIO, monitor, pick )

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Internal.Coin as C

spec :: Spec
spec = do
    describe "idealBatchSize" $ do
        it "Eventually converge for decreasing functions" $ do
            property $ \coinselOpts -> do
                let batchSize = idealBatchSize coinselOpts
                label (show batchSize) True

    describe "accuracy of selectCoins" $ do
        let testAccuracy :: Double -> SpecWith ()
            testAccuracy r = it title $ withMaxSuccess 1000 $ monadicIO $ do
                let dust = unsafeCoin @Int 100
                utxo <- pick (genUTxO r dust)
                batchSize <- pick genBatchSize
                feeOpts <- pick (genFeeOptions dust)
                let selections = selectCoins feeOpts batchSize utxo
                monitor $ label $ accuracy dust
                    (coinToIntegral $ coinMapValue utxo)
                    (sum $ coinToIntegral . sumInputs <$> selections)
              where
                title :: String
                title = "dust=" <> show (round (100 * r) :: Int) <> "%"

                accuracy :: Coin -> Natural -> Natural -> String
                accuracy dust sup real
                    | a >= 1.0 =
                        "PERFECT  (== 100%)"
                    | a > 0.99 || (sup - real) < coinToIntegral dust =
                        "OKAY     (>   99%)"
                    | otherwise =
                        "MEDIOCRE (<=  99%)"
                  where
                    a = double real / double sup
                    double = fromRational @Double . fromIntegral

        mapM_ testAccuracy [ 0.01 , 0.05 , 0.10 , 0.25 , 0.50 ]

    describe "selectCoins properties" $ do
        it "No coin selection has outputs" $
            property $ withMaxSuccess 10_000 $ prop_onlyChangeOutputs
                @(Wrapped InputId) @OutputId

        it "Every coin in the selection change > dust threshold" $
            property $ withMaxSuccess 10_000 $ prop_allAboveThreshold
                @(Wrapped InputId) @OutputId

        it "Total input UTxO value >= sum of selection change coins" $
            property $ withMaxSuccess 10_000 $ prop_inputsGreaterThanOutputs
                @(Wrapped InputId) @OutputId

        it "Every selection input is unique" $
            property $ withMaxSuccess 10_000 $ prop_inputsAreUnique
                @(Wrapped InputId) @OutputId

        it "Every selection input is a member of the UTxO" $
            property $ withMaxSuccess 10_000 $ prop_inputsStillInUTxO
                @(Wrapped InputId) @OutputId

        it "Every coin selection is well-balanced" $
            property $ withMaxSuccess 10_000 $ prop_wellBalanced
                @(Wrapped InputId) @OutputId

    describe "selectCoins regressions" $ do
        it "regression #1" $ do
            let feeOpts = FeeOptions
                    { dustThreshold = unsafeDustThreshold @Int 9
                    , feeEstimator = FeeEstimator $ \s -> unsafeFee @Int
                        $ fromIntegral
                        $ 5 * (length (inputs s) + length (outputs s))
                    , feeBalancingPolicy = RequireBalancedFee
                    }
            let batchSize = BatchSize 1
            let utxo = CoinMap $ Map.fromList
                    [ ( mkInputId "|\243^\SUBg\242\231\&1\213\203"
                      , unsafeCoin @Int 2
                      )
                    ]
            property $ prop_inputsGreaterThanOutputs
                @InputId @OutputId feeOpts batchSize utxo

--------------------------------------------------------------------------------
-- Properties
--------------------------------------------------------------------------------

-- | No coin selection has outputs
prop_onlyChangeOutputs
    :: forall i o . (Ord i, Ord o, Show o)
    => FeeOptions i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_onlyChangeOutputs feeOpts batchSize utxo = do
    let allOutputs =
            coinMapToList . outputs =<< selectCoins feeOpts batchSize utxo
    property (allOutputs `shouldSatisfy` null)

-- | Every coin in the selection change > dust threshold
prop_allAboveThreshold
    :: forall i o . (Ord i, Ord o)
    => FeeOptions i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_allAboveThreshold feeOpts batchSize utxo = do
    let allChange = change
            =<< selectCoins feeOpts batchSize utxo
    let undersizedCoins =
            filter (<= threshold) allChange
    property (undersizedCoins `shouldSatisfy` null)
  where
    threshold = unDustThreshold $ dustThreshold feeOpts

-- | Total input UTxO value >= sum of selection change coins
prop_inputsGreaterThanOutputs
    :: forall i o . (Ord i, Ord o, Show i, Show o)
    => FeeOptions i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_inputsGreaterThanOutputs feeOpts batchSize utxo = do
    let selections  = selectCoins feeOpts batchSize utxo
    let totalChange = mconcat (sumChange <$> selections)
    let balanceUTxO = coinMapValue utxo
    property (balanceUTxO >= totalChange)
        & counterexample ("Total change balance: " <> show totalChange)
        & counterexample ("Total UTxO balance: " <> show balanceUTxO)
        & counterexample ("Selections: " <> show selections)

-- | Every selected input is unique, i.e. selected only once
prop_inputsAreUnique
    :: forall i o . (Ord i, Ord o)
    => FeeOptions i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_inputsAreUnique feeOpts batchSize utxo = do
    let selectionInputList =
            coinMapToList . inputs =<< selectCoins feeOpts batchSize utxo
    let selectionInputSet =
            Set.fromList selectionInputList
    Set.size selectionInputSet === length selectionInputSet

-- | Every selection input is still a member of the UTxO" $
prop_inputsStillInUTxO
    :: forall i o . (Ord i, Ord o)
    => FeeOptions i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_inputsStillInUTxO feeOpts batchSize utxo = do
    let selectionInputSet = Set.fromList $
            coinMapToList . inputs =<< selectCoins feeOpts batchSize utxo
    let utxoSet = Set.fromList $
            fmap (uncurry CoinMapEntry) $ Map.toList $ unCoinMap utxo
    property (selectionInputSet `Set.isSubsetOf` utxoSet)

-- | Every coin selection is well-balanced (i.e. actual fees are exactly the
-- expected fees)
prop_wellBalanced
    :: forall i o . (Ord i, Ord o, Show i, Show o)
    => FeeParameters i o
    -> BatchSize
    -> CoinMap i
    -> Property
prop_wellBalanced feeParams batchSize utxo = do
    let feeOpts = FeeOptions
            { dustThreshold = DustThreshold mempty
            , feeEstimator = stableEstimator feeParams
            , feeBalancingPolicy = RequireBalancedFee
            }
    let selections = selectCoins feeOpts batchSize utxo
    conjoin
        [ counterexample example (actualFee === expectedFee)
        | s <- selections
        , let actualFee
                = coinToIntegral (sumInputs s)
                - coinToIntegral (sumChange s)
        , let expectedFee
                = coinToIntegral @Integer
                $ unFee $ estimateFee (feeEstimator feeOpts) s
        , let example = unlines
                [ "Coin Selection: " <> show s
                , "Actual fee: " <> show actualFee
                , "Expected fee: " <> show expectedFee
                ]
        ]

--------------------------------------------------------------------------------
-- Arbitrary Instances
--------------------------------------------------------------------------------

-- A wrapper to avoid overlapping instances imported from other modules.
newtype Wrapped a = Wrapped { unwrap :: a }
    deriving (Eq, Ord, Show)

-- TODO: Move similar Arbitrary instances to a shared module for better reuse.
instance Arbitrary (Wrapped InputId) where
    arbitrary = Wrapped <$> genInputId 8

instance Arbitrary BatchSize where
    arbitrary = BatchSize <$> arbitrarySizedIntegral
    shrink (BatchSize s) = BatchSize <$> shrink s

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

genBatchSize :: Gen BatchSize
genBatchSize = BatchSize <$> choose (50, 150)

genFeeOptions :: Coin -> Gen (FeeOptions InputId OutputId)
genFeeOptions dust = do
    pure $ FeeOptions
        { feeEstimator = FeeEstimator $ \s ->
            let x = fromIntegral @_ @Integer
                    (length (inputs s) + length (outputs s))
            in unsafeFee $
                  (C.coinToIntegral dust `div` 100) * x + C.coinToIntegral dust
        , dustThreshold = DustThreshold dust
        , feeBalancingPolicy = RequireBalancedFee
        }

-- | Generate a given UTxO with a particular percentage of dust
genUTxO :: Double -> Coin -> Gen (CoinMap InputId)
genUTxO r dust = do
    n <- choose (10, 1000)
    inps <- vectorOf n (genInputId 8)
    coins <- vectorOf n genCoin
    pure $ CoinMap $ Map.fromList $ zip inps coins
  where
    genCoin :: Gen Coin
    genCoin = unsafeCoin @Int <$> frequency
        [ (round (100*r), choose (1, integralDust))
        , (round (100*(1-r)), choose (integralDust, 1000 * integralDust))
        ]
      where
        integralDust = C.coinToIntegral dust

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------
