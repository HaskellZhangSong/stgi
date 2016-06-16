{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Prelude.List (tests) where



import qualified Data.List   as L
import           Data.Monoid
import           Data.Text   (Text)

import           Stg.Language
import           Stg.Machine.Types
import           Stg.Marshal
import           Stg.Parser.QuasiQuoter
import qualified Stg.Prelude            as Stg

import Test.Machine.Evaluate.TestTemplates.MarshalledValue
import Test.Orphans                                        ()
import Test.QuickCheck.Modifiers
import Test.Tasty



tests :: TestTree
tests = testGroup "List"
    [ testConcat2
    , testReverse
    , testLength
    , testCycle
    , testIterate
    , testRepeat
    , testReplicate
    , testGroup "Sort"
        [ testSort
        , testNaiveSort ]
    , testFilter
    , testMap
    , testZip
    , testZipWith
    , testGroup "Folds"
        [ testFoldr
        , testFoldl
        , testFoldl' ]
    ]

testFilter :: TestTree
testFilter = marshalledValueTest defSpec
    { testName = "filter"
    , expectedValue = \(xs, threshold) -> filter (> threshold) xs
    , source = \(xs, threshold :: Integer) -> mconcat
        [ toStg "inputList" xs
        , toStg "threshold" threshold
        , Stg.gt_Int
        , Stg.force
        , Stg.filter
        , [stg|
        main = \ =>
            letrec
                positive = \x -> gt_Int x threshold;
                filtered = \(positive) => filter positive inputList
            in force filtered
        |] ]}

testSort :: TestTree
testSort = marshalledValueTest defSpec
    { testName = "sort (Haskell/base version)"
    , failWithInfo = True
    , expectedValue = \xs -> L.sort xs
    , source = \(xs :: [Integer]) -> mconcat
        [ toStg "inputList" xs
        , Stg.sort
        , Stg.force
        , [stg|
        main = \ =>
            let sorted = \ => sort inputList
            in force sorted
        |] ]}

testNaiveSort :: TestTree
testNaiveSort = marshalledValueTest defSpec
    { testName = "sort (naive version)"
    , expectedValue = \xs -> L.sort xs
    , source = \(xs :: [Integer]) -> mconcat
        [ toStg "inputList" xs
        , Stg.naiveSort
        , Stg.force
        , [stg|

        main = \ =>
            let sorted = \ => naiveSort inputList
            in force sorted
        |] ]}

testMap :: TestTree
testMap = marshalledValueTest defSpec
    { testName = "map"
    , expectedValue = \(xs, offset) -> map (+offset) xs
    , source = \(xs, offset :: Integer) -> mconcat
        [ Stg.add
        , Stg.map
        , Stg.force
        , toStg "offset" offset
        , toStg "inputList" xs
        , [stg|
        main = \ =>
            letrec
                plusOffset = \n -> add n offset;
                result = \(plusOffset) => map plusOffset inputList
            in force result
        |] ]}

testZip :: TestTree
testZip = marshalledValueTest defSpec
    { testName = "zip, map"
    , expectedValue = \(list1, list2) -> zipWith (+) list1 list2
    , source = \(list1, list2 :: [Integer]) -> mconcat
        [ toStg "list1" list1
        , toStg "list2" list2
        , Stg.add
        , Stg.map
        , Stg.uncurry
        , Stg.zip
        , Stg.force
        , [stg|

        main = \ =>
            letrec
                zipped   = \ -> zip list1 list2;
                addTuple = \ -> uncurry add;
                summed   = \(addTuple zipped) => map addTuple zipped
            in force summed
        |] ]}

testZipWith :: TestTree
testZipWith = marshalledValueTest defSpec
    { testName = "zipWith (+)"
    , expectedValue = \(list1, list2) -> zipWith (+) list1 list2
    , source = \(list1, list2 :: [Integer]) -> mconcat
        [ toStg "list1" list1
        , toStg "list2" list2
        , Stg.add
        , Stg.zipWith
        , Stg.force
        , [stg|
        main = \ =>
            let zipped = \ => zipWith add list1 list2
            in force zipped
        |] ]}


testFoldr, testFoldl, testFoldl' :: TestTree
testFoldr  = foldSumTemplate
    "foldr"
    foldr
    (Stg.foldr <> [stg| fold = \ -> foldr |])
    (const False)
testFoldl  = foldSumTemplate
    "foldl"
    foldl
    (Stg.foldl <> [stg| fold = \ -> foldl |])
    (const False)
testFoldl' = foldSumTemplate
    "foldl'"
    L.foldl'
    (Stg.foldl' <> [stg| fold = \ -> foldl' |])
    (\stgState -> length (stgStack stgState) >= 8) -- Stack should stay small!

foldSumTemplate
    :: Text
        -- ^ Fold function name

    -> (forall a. (a -> a -> a) -> a -> [a] -> a)
        -- ^ Haskell reference fold function

    -> Program
        -- ^ STG Program with binding associating "fold" with the desired fold
        -- function, e.g. foldr

    -> (StgState -> Bool)
        -- ^ Failure predicate; useful in foldl' to check bounded stack size

    -> TestTree
foldSumTemplate foldName foldF foldStg failP
  = marshalledValueTest defSpec
    { testName = foldName
    , maxSteps = 1024
    , failPredicate = failP
    , expectedValue = \(z, xs) -> foldF (+) z xs
    , source = \(z :: Integer, xs) -> mconcat
        [ foldStg
        , Stg.add
        , Stg.force
        , toStg "z" z
        , toStg "input" xs
        , [stg|
        main = \ =>
            let result = \ => fold add z input
            in force result
        |] ]}

testConcat2 :: TestTree
testConcat2 = marshalledValueTest defSpec
    { testName = "(++)"
    , expectedValue = \(list1, list2) -> list1 ++ list2
    , source = \(list1, list2 :: [Integer]) -> mconcat
        [ toStg "list1" list1
        , toStg "list2" list2
        , Stg.concat2
        , Stg.force
        , [stg|
        main = \ =>
            let concatenated = \ => concat2 list1 list2
            in force concatenated
        |] ]}

testReverse :: TestTree
testReverse = marshalledValueTest defSpec
    { testName = "reverse"
    , maxSteps = 1024
    , expectedValue = \xs -> reverse xs
    , source = \(xs :: [Integer]) -> mconcat
        [ toStg "input" xs
        , Stg.reverse
        , Stg.force
        , [stg|
        main = \ =>
            let reversed = \ => reverse input
            in force reversed
        |] ]}

testCycle :: TestTree
testCycle = marshalledValueTest defSpec
    { testName = "cycle (+take)"
    , expectedValue = \(NonEmpty (list :: [Integer]), NonNegative n)
        -> take n (cycle list)
    , source = \(NonEmpty (list :: [Integer]), NonNegative n) -> mconcat
        [ toStg "n" n
        , toStg "list" list
        , Stg.take
        , Stg.cycle
        , Stg.force
        , [stg|
        main = \ =>
            letrec
                cycled = \ -> cycle list;
                takeCycled = \(cycled) => take n cycled
            in force takeCycled
        |] ]}

testRepeat :: TestTree
testRepeat = marshalledValueTest defSpec
    { testName = "repeat (+take)"
    , expectedValue = \(item, NonNegative n) -> replicate n item
    , source = \(item :: Integer, NonNegative n) -> mconcat
        [ toStg "n" n
        , toStg "item" item
        , Stg.take
        , Stg.repeat
        , Stg.force
        , [stg|
        main = \ =>
            letrec
                repeated = \ -> repeat item;
                takeRepeated = \(repeated) => take n repeated
            in force takeRepeated
        |] ]}

testReplicate :: TestTree
testReplicate = marshalledValueTest defSpec
    { testName = "replicate"
    , failWithInfo = True
    , maxSteps = 1024
    , failPredicate = \stgState -> case stgCode stgState of
        Eval AppP {} _ -> True
        _ -> False
    , expectedValue = \(item, n) -> replicate n item
    , source = \(item :: Integer, n) -> mconcat
        [ toStg "n" n
        , toStg "item" item
        , Stg.replicate
        , Stg.force
        , [stg|
        main = \ =>
            let replicated = \ => replicate n item
            in force replicated
        |] ]}

testIterate :: TestTree
testIterate = marshalledValueTest defSpec
    { testName = "iterate (+take)"
    , expectedValue = \(seed, offset, NonNegative n)
        -> take n (iterate (+offset) seed)
    , source = \(seed, offset :: Integer, NonNegative n) -> mconcat
        [ toStg "n" n
        , toStg "offset" offset
        , toStg "seed" seed
        , Stg.add
        , Stg.take
        , Stg.iterate
        , Stg.force
        , [stg|
        main = \ =>
            letrec
                addOffset = \ -> add offset;
                iterated = \(addOffset) -> iterate addOffset seed;
                takeIterated = \(iterated) => take n iterated
            in force takeIterated
        |] ]}


testLength :: TestTree
testLength = marshalledValueTest defSpec
    { testName = "length"
    , expectedValue = \xs -> fromIntegral (length xs) :: Integer
    , source = \(xs :: [Integer]) -> mconcat
        [ toStg "input" xs
        , Stg.length
        , Stg.force
        , [stg|
        main = \ =>
            let len = \ => length input
            in force len
        |] ]}
