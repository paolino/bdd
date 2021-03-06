{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import           Control.Concurrent.MVar
import           Control.Exception
import           Test.BDD.LanguageFree
import qualified Test.HUnit              as H
import           Test.Tasty
import           Test.Tasty.Bdd
import           Test.Tasty.HUnit        hiding ((@?=))
import Test.Tasty.ExpectedFailure

main :: IO ()
main = defaultMain $ testGroup
    "All"
    [ testCase
            "givens and givenandafter order is respected, constructors language"
        $ do
              let
                  t write =
                      defaultMain
                          $ testBehavior "Test sequence"
                          $ Given (write "First effect")
                          $ Given (write "Another effect")
                          $ GivenAndAfter
                                (  write "Aquiring resource"
                                >> return "Resource 1"
                                )
                                (write . ("Release " ++))
                          $ GivenAndAfter
                                (  write "Aquiring resource"
                                >> return "Resource 2"
                                )
                                (write . ("Release " ++))
                          $ When (write "Action returning")
                          $ Then (\_ -> return ()) End
              testTest
                  t
                  [ "First effect"
                  , "Another effect"
                  , "Aquiring resource"
                  , "Aquiring resource"
                  , "Action returning"
                  , "Release Resource 2"
                  , "Release Resource 1"
                  ]
    , testCase "3 givens and givenandafter order is respected, free language"
        $ do
              let
                  t write = defaultMain $ testBehaviorF id "test free" $ do
                      q <- given $ do
                          write "First effect"
                          return (1 :: Int)
                      given $ write "Another effect"
                      q' <-
                          givenAndAfter
                              (  write "Aquiring resource"
                              >> return (q + 1, "Resource " <> show q)
                              )
                          $ write
                          . ("Release " ++)
                      givenAndAfter_
                              (  write "Aquiring resource"
                              >> return ("Resource " <> show q')
                              )
                          $ write
                          . ("Release " ++)
                      when_ (write "Action returning" >> return (q' + q)) $ do
                          then_ (@?= 7)
                          then_ (assertBool "less then" . (< 4))
                      {-when_ (write "Action returning2" >> return "different type") $ do
                          then_  (@?= ("different typ" :: String))-}
              testTest
                  t
                  [ "First effect"
                  , "Another effect"
                  , "Aquiring resource"
                  , "Aquiring resource"
                  , "Action returning"
                  -- , "Action returning2"
                  , "Release Resource 2"
                  , "Release Resource 1"
                  ]
    , testCase
            "3 givens and givenandafter order is respected, free language, with exceptions"
        $ do
              let
                  t write = defaultMain $ testBehaviorF id "test free" $ do
                      q <- given $ do
                          write "First effect"
                          return (1 :: Int)
                      given $ write "Another effect"
                      q' <-
                          givenAndAfter
                              (  write "Aquiring resource"
                              >> return (q + 1, "Resource " <> show q)
                              )
                          $ write
                          . ("Release " ++)
                      givenAndAfter_
                              (  write "Aquiring resource"
                              >> return ("Resource " <> show q')
                              )
                          $ write
                          . ("Release " ++)
                      when_ ((1 :: Int) @?= 2 >> return (q' + q))
                          $ then_ (@?= 3)
              testTest
                  t
                  [ "First effect"
                  , "Another effect"
                  , "Aquiring resource"
                  , "Aquiring resource"
                  , "Release Resource 2"
                  , "Release Resource 1"
                  ]
    , testCase "recursive before decorations are honored" $ do
        let t write = defaultMain $ beforeEach (write 0) $ testGroup
                "g1"
                [ testCase "t1" $ write 1
                , testCase "t2" $ write 2
                , testGroup "g2" [testCase "t3" $ write 3]
                , testCase "t4" $ write 4
                ]
        testTest t ([0, 1, 0, 2, 0, 3, 0, 4] :: [Int])
    , testCase "recursive after decorations are honored" $ do
        let t write = defaultMain $ afterEach (write 0) $ testGroup
                "g1"
                [ testCase "t1" $ write 1
                , testCase "t2" $ write 2
                , testGroup "g2" [testCase "t3" $ write 3]
                , testCase "t4" $ write 4
                ]
        testTest t ([1, 0, 2, 0, 3, 0, 4, 0] :: [Int])
    , expectFail $ testBehaviorF runCase "didn't break tasty" $ do
        when_ (pure 42 :: IO Int) $ then_ $ \x -> x @?= 43

    ]


testTest :: (Show a, Eq a) => ((a -> IO ()) -> IO ()) -> [a] -> IO ()
testTest t r' = do
    l <- newMVar []
    let write x = modifyMVar_ l (return . (x :))
    _ <- handle (\(_ :: SomeException) -> return "")
        $ captureStdout "tasty-bdd-test-suite"
        $ t write
    r <- readMVar l
    r H.@?= reverse r'
