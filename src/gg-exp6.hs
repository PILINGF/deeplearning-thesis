{-# LANGUAGE Rank2Types, OverloadedStrings #-}

module Main where

import Prelude hiding (putStr, putStrLn)

import ConstraintsGA
import ConstraintsGeneric
import GenericGameExperiments
import Matlab
import GraphNN
import MinimalNN
import NeuralNets
import ThreadLocal

import Control.Applicative
import Control.Concurrent
import Control.Concurrent.Async
import Control.Monad
import Control.DeepSeq
import Control.Parallel.Strategies
import Data.Default
import Data.IORef
import Data.Timeout
import System.FilePath

-- gameplayConstraints'3 = concatMap (\ (x,y) -> [x,y]) $ zip gameplayConstraints'1 gameplayConstraints'0

useCachedDBN = False
searchTimeout = 3 # Minute
searchTimeoutMulti = 30 # Second
dbnGameCount = 250000
dbnGameProb = 0.7
dbnMatlabOpts = Just (def {dbnSizes = [500, 500, 500], numEpochs = 5, implementation = Matlab})
constraintSource = CS_Gameplay playerUseCoinstraints gameplayConstraints'0
playerUseCoinstraints = 5000
constraintsStage2Count = 1000
allowedBad = 3000 -- round $ 0.10 * fromIntegral workSetSize
workSetSize = 300
singleNeuronTarget = 0.9
localSearch = 0.003
attemptsCount = 4

mkLayer :: [SingleNeuron] -> [[Int]] -> GNetwork
mkLayer neurons refs = let ws = [map ((\ [[w]] -> w ) . fst) neurons]
                           bs = [map ((\ [[b]] -> b ) . snd) neurons]
                       in mkGNetwork ws bs refs

getNeuronSize :: SingleNeuron -> Int
getNeuronSize ([[w]],_) = length w

main :: IO ()
main = runThrLocMainIO $ do
  printTL "DBN read/train"
  fn <- getDBNCachedOrNew useCachedDBN dbnGameCount dbnGameProb dbnMatlabOpts
  -- let fn = "tmp-data/iybjioktvbdgmjocdtow/dbn.txt"
  -- let fn = "tmp-data/iwssqgpqsryvajvoerqi/dbn.txt"
  printTL ("DBN FN=",fn)
  let fixLastLayerRefs (GNetwork bs ws refs) = let newRefs = [0 .. ((length bs)-2)]
                                                   refs' = (init refs) ++ [last refs ++ newRefs]
                                               in (GNetwork bs ws refs')
  dbn <- (fixLastLayerRefs . fromTNetwork) <$> getDBNFile fn

  printTL "Constraint generation"
  constraints <- getConstraints constraintSource
  let constraintsPacked = map (packConstraint dbn) $ concatMap (uncurry generateConstraintsSimpleAll) constraints
  printTL ("Total coinstraint count", length constraintsPacked)
  printTL "Evaluating packed constraints..."
  print $ head constraintsPacked
  (constraintsPacked `using` parList rdeepseq) `deepseq` printTL "Done."
  printTL "Perform multiNeuronMinimalGAReprSearch"
  threads <- getNumCapabilities
  scoredNeurons <- multiNeuronMinimalGAReprSearch threads allowedBad workSetSize searchTimeoutMulti singleNeuronTarget constraintsPacked
  let neurons = map fst scoredNeurons

  printTL "Do few times: train last layer network & evaluate"
  forM_ [1..attemptsCount] $ \ attempt -> do
    let newLayer = mkLayer neurons [[0]] -- (neurons ++ mkBypass (getNeuronSize (head neurons)))
        dbnBigger = appendGNetwork dbn newLayer
        constraintsPackedBigger = take constraintsStage2Count $ 
                                  map (packConstraint dbnBigger) $
                                  concatMap (uncurry generateConstraintsSimpleAll) constraints

    printTL ("dbnBigger", dbnBigger)
    printTL ("newLayer", newLayer, length neurons)

    bestRef <- newIORef (undefined, neginf)
    let wt thr'act = waitAnyCancel =<< withTimeout bestRef searchTimeout (mapM thr'act [1..threads])
    (_, _bestGA) <- wt (\ thr -> async (singleNeuronMinimalGAReprSearch (searchCB bestRef) thr 1 constraintsPackedBigger Nothing))
    (_, bestFinal) <- wt (\ thr -> async (singleNeuronLocalReprSearch (searchCB bestRef) bestRef localSearch 1 thr constraintsPackedBigger))

    let finalNetwork = appendGNetwork dbnBigger (fromTNetwork (uncurry mkTNetwork (fst bestFinal)))
        baseDir = takeDirectory fn

    rndStr <- getRandomFileName
    writeFile (baseDir </> "dbn-final-data-ggexp6-"++rndStr++".txt") $ show $ finalNetwork
    wins <- evaluateLL finalNetwork (snd bestFinal)
    writeFile (baseDir </> "dbn-final-info-ggexp6-"++rndStr++".txt") $ showExperimentConfig wins bestFinal

showExperimentConfig wins bestFinal = unlines $
        ["wins                 " ++ (show wins                 )
        ,"bestFinal            " ++ (show bestFinal            )
        ,"useCachedDBN         " ++ (show useCachedDBN         ) 
        ,"searchTimeout        " ++ (show searchTimeout        ) 
        ,"searchTimeoutMulti   " ++ (show searchTimeoutMulti   ) 
        ,"dbnGameCount         " ++ (show dbnGameCount         ) 
        ,"dbnGameProb          " ++ (show dbnGameProb          ) 
        ,"dbnMatlabOpts        " ++ (show dbnMatlabOpts        ) 
        ,"constraintSource     " ++ (show constraintSource     ) 
        ,"playerUseCoinstraints" ++ (show playerUseCoinstraints) 
        ,"allowedBad           " ++ (show allowedBad           ) 
        ,"workSetSize          " ++ (show workSetSize          ) 
        ,"singleNeuronTarget   " ++ (show singleNeuronTarget   ) 
        ,"localSearch          " ++ (show localSearch          ) 
        ]
