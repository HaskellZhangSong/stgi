{-# LANGUAGE NumDecimals       #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Machine.Evaluate (tests) where

-- TODO: Important tests to add:
--   - Only case does evaluation
--   - Don't forget to add the variables closed over in let(rec)



import           Test.Tasty

import qualified Test.Machine.Evaluate.Programs as Programs
import qualified Test.Machine.Evaluate.Rules    as Rules



tests :: TestTree
tests = testGroup "Evaluate"
    [ Rules.tests
    , Programs.tests ]
