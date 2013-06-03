module Main where

import ThreadLocal
import GenericGameExperiments
import AgentGeneric
import GenericGame
import MinimalNN
import MCTS

import Control.Applicative
import Control.Monad (void)
import System.Environment

main :: IO ()
main = mapM_ evaluateDBN =<< getArgs

evaluateDBN :: FilePath -> IO ()
evaluateDBN fn = runThrLocMainIO $ do
  dbn <- read <$> readFile fn
  agSmpl <- mkTimed "simple" (dbn :: TNetwork) :: IO (AgentTrace AgentSimple)
  agTree <- mkTimed "tree" (dbn, 3) :: IO (AgentTrace AgentGameTree)
  agMCT <- mkTimed "mcts" 50 :: IO (AgentTrace AgentMCTS)
  agMCTNet <- mkTimed "mctNet" (2, 5, dbn) :: IO (AgentTrace (AgentParMCTS AgentSimple))
  agMCTS'Tree <- mkTimed "mcts'Tree" (2, 5, dbn) :: IO (AgentTrace (AgentProperMCTS'Tree AgentSimple))

  putStrLnTL "======================================================================================"
  w0 <- reportWin agSmpl agMCT P1
  w1 <- reportWin agTree agMCT P1
  w2 <- reportWin agMCTNet agMCT P1
  w3 <- reportWin agMCTS'Tree agMCT P1
  putStrLnTL "======================================================================================"
  print [w0,w1,w2,w3]
  putStrLnTL "======================================================================================"
