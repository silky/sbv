-----------------------------------------------------------------------------
-- |
-- Module      :  Main
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- SBV library unit-test program
-----------------------------------------------------------------------------

module Main(main) where

import Control.Monad        (unless, when)
import Data.Maybe           (isJust)
import Data.List            (isInfixOf)
import System.Directory     (doesDirectoryExist)
import System.Environment   (getArgs)
import System.Exit          (exitWith, exitSuccess, ExitCode(..))
import System.FilePath      ((</>))
import Test.HUnit           (Test(..), Counts(..), runTestTT)

import Data.Version         (showVersion)
import SBVTest              (SBVTestSuite(..), generateGoldCheck)
import Paths_sbv            (getDataDir, version)

import SBVTestCollection    (allTestCases)

main :: IO ()
main = do putStrLn $ "*** SBVUnitTester, version: " ++ showVersion version
          tgts <- getArgs
          case tgts of
            [x] | x `elem` ["-h", "--help", "-?"]
                   -> do putStrLn "Usage: SBVUnitTests [-c] [-l] [-s] [targets]" -- Not quite right, but sufficient
                         putStrLn "  -l: List all tests"
                         putStrLn "  -s: Skip constant-folding tests"
                         putStrLn "  -c: Create gold-files"
                         putStrLn "  -m: Do a wild-card match on targets"
                         putStrLn "  -i: Do an inverse wild-card match on targets"
                         putStrLn "If targets are given, run those groups; except with the -m flag which matches test names."
            ["-l"] -> showTargets
            -- undocumented really
            ("-c":ts) -> run (Nothing,     ts)   False True ["SBVUnitTest/GoldFiles"]
            ("-s":ts) -> run (Nothing,     ts)   True  False []
            ("-m":ts) -> run (Just False,  ts)   False False []
            ("-i":ts) -> run (Just True,   ts)   False False []
            _         -> run (Nothing,   tgts) False False []

checkGoldDir :: FilePath -> IO ()
checkGoldDir gd = do e <- doesDirectoryExist gd
                     unless e $ do putStrLn "*** Cannot locate gold file repository!"
                                   putStrLn "*** Please call with one argument, the directory name of the gold files."
                                   putStrLn "*** Cannot run test cases, exiting."
                                   exitWith $ ExitFailure 1

allTargets :: [String]
allTargets = [s | (s, _, _) <- allTestCases]

showTargets :: IO ()
showTargets = do putStrLn "Known test targets are:"
                 mapM_ (putStrLn . ("\t" ++))  allTargets

run :: (Maybe Bool, [String]) -> Bool -> Bool -> [String] -> IO ()
run (mbWCMatch, targets) skipCF shouldCreate [gd] =
        do mapM_ checkTgt targets
           putStrLn $ "*** Starting SBV unit tests..\n*** Gold files at: " ++ show gd
           checkGoldDir gd
           cts <- runTestTT $ TestList $ concatMap mkTst [c | (tc, needsSolver, c) <- allTestCases, select needsSolver tc]
           decide shouldCreate cts
  where mkTst (SBVTestSuite f) = pick $ f (generateGoldCheck gd shouldCreate)
          where pick :: Test -> [Test]
                pick tst = case mbWCMatch of
                             Nothing       -> [tst]
                             Just inverted -> collect tst
                              where collect (TestCase _)    = []
                                    collect (TestList ts)   = concatMap collect ts
                                    collect t@(TestLabel s _)
                                       | all (`isInfixOf` s) targets = [t | not inverted]
                                       | True                        = [t |     inverted]
        wcMode = isJust mbWCMatch
        select needsSolver tc
           | not included = False
           | shouldCreate = True
           | needsSolver  = True
           | True         = not skipCF
          where included | wcMode = True
                         | True   = null targets || tc `elem` targets
        checkTgt t | wcMode              = return ()
                   | t `elem` allTargets = return ()
                   | True                = do putStrLn $ "*** Unknown test target: " ++ show t
                                              exitWith $ ExitFailure 1
run targets skipCF shouldCreate [] = getDataDir >>= \d -> run targets skipCF shouldCreate [d </> "SBVUnitTest" </> "GoldFiles"]
run _       _      _            _  = error "SBVUnitTests.run: impossible happened!"

decide :: Bool -> Counts -> IO ()
decide shouldCreate (Counts c t e f) = do
        when (c /= t) $ putStrLn $ "*** Not all test cases were tried. (Only tested " ++ show t ++ " of " ++ show c ++ ")"
        when (e /= 0) $ putStrLn $ "*** " ++ show e ++ " (of " ++ show c ++ ") test cases in error."
        when (f /= 0) $ putStrLn $ "*** " ++ show f ++ " (of " ++ show c ++ ") test cases failed."
        if c == t && e == 0 && f == 0
           then do putStrLn $ "All " ++ show c ++ " test cases "
                            ++ (if shouldCreate
                                then " executed in gold-file generation mode."
                                else " successfully passed.")
                   exitSuccess
           else exitWith $ ExitFailure 2
