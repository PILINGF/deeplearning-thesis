{-# LANGUAGE TypeFamilies, FlexibleContexts #-}

-- minimal, efficient, incremental implementation of GA

module MinimalGA where

import System.Random.MWC
import Data.Default
import Data.Array.IArray
import Control.Monad
import Control.Applicative
import Data.List (sort, sortBy, group)
import Data.Ord (comparing)
import Control.Arrow ((&&&))
import ThreadLocal
import Utils

class MinimalGA ent where
    -- | scoring datatype, lower means better
    type Score ent :: * 
    -- | for scoring entity
    type ScoreDataset ent :: * 
    -- | parameters for entity creation
    type EntityParams ent :: * 
    -- | parameters for all operations
    type WorkParams ent :: * 

    newEntity :: (WorkParams ent) -> (EntityParams ent) -> ThrLocIO ent
    crossover :: (WorkParams ent) -> ent -> ent -> ThrLocIO ent
    mutation :: (WorkParams ent) -> Double -> ent -> ThrLocIO ent
    -- | score entity using provided dataset; lower means better. consider using 'negate' if your original score doesn't work this way.    
    scoreEntity :: ScoreDataset ent -> ent -> ThrLocIO (Score ent)
    -- | score population. default implementation simply calls score entity for each element. advanced uses may use others members of population for scoring.
    scorePopulation :: ScoreDataset ent -> [ent] -> ThrLocIO [((Score ent), ent)]
    scorePopulation dataset pop = mapM (\p -> (\ s -> (s,p)) <$> scoreEntity dataset p) pop

-- | encapsulates all evolution-related parameters supplied by caller
data EvolveConfig ent = EvolveConfig { ecPopulationSize :: Int -- ^ population size
                                     , ecKillCount :: Int -- ^ number of worst entities to drop from population
                                     , ecArchiveSize :: Int -- ^ archive (a list of best entities ever) size
                                     , ecMaxGenerations :: Int -- ^ maximum number of generations to create
                                     , ecMutatedRatio :: Double -- ^ percentage of entites bred by mutation (best works < 0.2)
                                     , ecCrossoveredRatio :: Double -- ^ percentage of entites bred by mutation (best works > 0.8)
                                     , ecMutationParam :: Double -- ^ parameter passed to mutation (mutation strength)
                                     , ecCallbackNewStep :: EvolveStepParams ent -> ThrLocIO Bool -- ^ callback called after each evolution step, returned False means "stop evolution"
                                     }

type AlmostEvolveConfig ent = (EvolveStepParams ent -> ThrLocIO Bool) -> EvolveConfig ent

instance Default (EvolveConfig ent) where
    def = EvolveConfig { ecPopulationSize = 300
                       , ecKillCount = 0
                       , ecArchiveSize = 50
                       , ecMaxGenerations = 100
                       , ecMutatedRatio = 0.2
                       , ecCrossoveredRatio = 0.8
                       , ecMutationParam = 0.2
                       , ecCallbackNewStep = (\ _ -> return True)
                       }

-- | encapsulates working parameters of evolveStep
data EvolveStepParams ent = EvolveStepParams { esConfig :: (EvolveConfig ent) -- ^ config used
                                             , esWorkParams :: WorkParams ent -- ^ working params for MinimalGA operations (e.g. random number gen etc.)
                                             , esEntityParams :: EntityParams ent -- ^ entity params for creating new entities (e.g. size of entity, pool of items etc.)
                                             , esDataset :: ScoreDataset ent -- ^ dataset used for scoring
                                             , esArchive :: [(Score ent, ent)] -- ^ archive of best entites so far
                                             , esPopulation :: [(Score ent, ent)] -- ^ working population
                                             , esBest :: (Score ent, ent) -- ^ best entity so far (== head esArchive)
                                             , esGens :: Int -- ^ remaining generations (steps to go)
                                             , esRndGen :: GenIO -- ^ local PRNG
                                             }

ofTypeArr :: Array i e -> Array i e
ofTypeArr = id

evolveStep :: (Show (Score ent), Ord ent, Ord (Score ent), (MinimalGA ent)) => (EvolveStepParams ent) -> ThrLocIO (EvolveStepParams ent)
evolveStep esParams = do
  let conf = esConfig esParams
      oldArchive = esArchive esParams
      combined = oldArchive ++ esPopulation esParams
      
      combined'arr = ofTypeArr (listArray (0, (length combined-1)) (map snd combined))
      
      pick1Elem = (combined'arr !) `fmap` uniformR (bounds combined'arr) (esRndGen esParams)
      pick2Elems = liftM2 (,) pick1Elem pick1Elem

      crossCnt = round $ ecCrossoveredRatio conf * (fromIntegral (ecPopulationSize conf)) 
      mutatCnt = round $ ecMutatedRatio conf     * (fromIntegral (ecPopulationSize conf))

  crossedEnt <- mapM (\ (ent1, ent2) -> crossover (esWorkParams esParams) ent1 ent2) =<< (replicateM crossCnt pick2Elems)
  mutatedEnt <- mapM (mutation (esWorkParams esParams) (ecMutationParam conf)) =<< (replicateM mutatCnt pick1Elem)

  newPop' <- scorePopulation (esDataset esParams) $ (mutatedEnt ++ crossedEnt)
  let newBigPop = nubSort (oldArchive ++ newPop')
      newArch = take (ecArchiveSize conf) $ newBigPop
      newBest = head newBigPop
      newPop = reverse . drop (ecKillCount conf) . reverse $ newBigPop

  newPop `seq` newArch `seq` newBest `seq` return ()

  printTL ("evolveStep", (fst newBest), (esGens esParams))

  return esParams { esGens = (esGens esParams - 1)
                  , esArchive = newArch
                  , esBest = newBest
                  , esPopulation = newPop
                  }

evolve :: (MinimalGA ent, Show (Score ent), Ord (Score ent), Ord ent) => (EvolveConfig ent) -> (EntityParams ent) -> (WorkParams ent) -> (ScoreDataset ent) -> ThrLocIO [((Score ent), ent)]
evolve ec entPar workPar dataset = do
  initialPop <- replicateM (ecPopulationSize ec) (newEntity workPar entPar)
  rgen <- mkGenIO
  initialPopScored <- scorePopulation dataset initialPop
  let bestEnt = head $ sortBy (comparing fst) initialPopScored
      esPar = EvolveStepParams { esConfig = ec 
                               , esWorkParams = workPar
                               , esEntityParams = entPar
                               , esDataset = dataset
                               , esArchive = [bestEnt] 
                               , esPopulation = initialPopScored
                               , esBest = bestEnt
                               , esGens = (ecMaxGenerations ec)
                               , esRndGen = rgen
                               }

  chainEvolveSteps esPar
  
chainEvolveSteps :: (Show (Score ent), Ord ent, Ord (Score ent), (MinimalGA ent)) => EvolveStepParams ent -> ThrLocIO [(Score ent, ent)]
chainEvolveSteps initialParams = do
  let evoFinished pars = esGens pars <= 0
      loop pars = do
        newPars <- evolveStep pars
        continue <- (ecCallbackNewStep (esConfig newPars)) newPars
        when (evoFinished newPars) (printTL ("chainEvolveSteps, evoFinished"))
        when (not continue) (printTL ("chainEvolveSteps, callbackContinue = False", continue))
        if (evoFinished newPars) || not continue then return (esArchive newPars) else loop newPars

  loop initialParams
