{-# LANGUAGE ImplicitParams, Rank2Types, BangPatterns #-}

module ThreadLocal where

import Control.Concurrent
import Text.Printf
import System.IO

import Data.Time.LocalTime
import Data.Time.Format
import System.Locale

type ThrLocIO a = (?thrLoc :: ThreadLocal) => IO a
data ThreadLocal = ThreadLocal { tl_stdout :: MVar Handle
                               , tl_ident :: String
                               }

runThrLocMainIO :: (ThrLocIO a) -> IO a
runThrLocMainIO main = do
  hSetBuffering stdout NoBuffering
  var <- newMVar stdout
  runThrLocIO (ThreadLocal var "MAIN") main

runThrLocIO :: ThreadLocal -> ThrLocIO a -> IO a
runThrLocIO tl ma = let ?thrLoc = tl in ma

fmtTimeNow :: IO String
fmtTimeNow = formatTime defaultTimeLocale "%F %T" `fmap` getZonedTime

putStrLnTL :: String -> ThrLocIO ()
putStrLnTL val = do
  now <- fmtTimeNow
  let msg = (printf "[%s] [THR=%s] %s" now (tl_ident ?thrLoc) (val :: String)) :: String
  msg `seq` modifyMVar_ (tl_stdout ?thrLoc) (\ handle -> do
                                               hPutStrLn handle msg
                                               return handle)

printTL :: (Show a) => a -> ThrLocIO ()
printTL val = putStrLnTL (show val)
