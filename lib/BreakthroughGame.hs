{-# LANGUAGE ViewPatterns, TypeFamilies, DefaultSignatures, FlexibleContexts, FlexibleInstances #-} 

module BreakthroughGame where

import GenericGame
import Utils

import qualified Data.HashMap as HashMap
import qualified Data.HashSet as HashSet
import Data.HashMap (Map)
import Data.HashSet (Set)
import Data.Monoid (mempty, mappend)
import Data.Maybe

type Position = (Int,Int) -- ^ (x,y), x=column goes from 0 to width-1, y=row goes from 0 to height-1
type BoardMap = Map Position Player2

data Breakthrough = Breakthrough { board :: BoardMap -- ^ map from position to P1 or P2 piece.
                                 , boardSize :: (Int,Int) -- ^ width, height. height >= 4, width >= 2. each player will be given exactly 2*width pieces. there are 'width' many columns and 'height' many rows.
                                 , winningP1 :: Set Position -- ^ fixed set of winning positions for P1
                                 , winningP2 :: Set Position -- ^ fixed set of winning positions for P2
                                 , countP1 :: !Int -- ^ how many pieces P1 have
                                 , countP2 :: !Int -- ^ how many pieces P2 have
                                 } deriving (Show, Eq, Read, Ord)

instance GameTxtRender Breakthrough where
    prettyPrintGame g = let -- ll = "---------------------------" 
                            rl = fst (boardSize g)
                            charPos pos = case HashMap.lookup pos (board g) of
                                            Nothing -> '☐'
                                            Just P1 -> '♙' 
                                            Just P2 -> '♟'
                            pprow n = "| " ++ map charPos (row n rl) ++ " |"

                            bareBoard = map pprow [0..(snd (boardSize g))-1]
                        in
                          unlines bareBoard
                          
--                         unlines ( 
--                         [ll
--                         ,show g
--                         ,ll] ++
--                         bareBoard
--                         ++ [ll])


class (Game2 a) => Game2Features a where
    type Feature a :: *
    type FeatureRepr a :: *

    encodeAllFeatures :: a -> (FeatureRepr a)
    default encodeAllFeatures :: (Enum (Feature a), Bounded (Feature a), (FeatureRepr a) ~ [b]) => a -> (FeatureRepr a)
    encodeAllFeatures g = concatMap (encodeFeature g) [minBound..maxBound]

    encodeFeature :: a -> (Feature a) -> (FeatureRepr a)
    countFeatures :: a -> Int
    default countFeatures :: ((FeatureRepr a) ~ [b]) => a -> Int
    countFeatures g = length $ encodeAllFeatures g

data BrFeature = MaxPos
               | MinPos
               | Centroid
               | Count
                deriving (Eq, Ord, Read, Show, Enum, Bounded)

instance Game2Features Breakthrough where
    type Feature Breakthrough = BrFeature
    type FeatureRepr Breakthrough = [Double] -- GameRepr Breakthrough

    encodeFeature _ _ = []
    encodeFeature g feat = map fixNaN $  
        case feat of
          MaxPos -> map (scaleX . fromIntegral) [maximum (allFst P1), minimum (allFst P2)]
          MinPos -> map (scaleX . fromIntegral) [minimum (allFst P1), maximum (allFst P2)]
          Centroid -> concatMap (pairToLst . scaleXY . centroid) [P1,P2]
          Count -> map scaleCnt [countP1 g, countP2 g]
        where
          pairToLst (x,y) = [x,y]
          brd = board g 
          allFst p = case map fst (getAll p brd) of
                       [] -> [0] -- FIXME: what to do in case there is no sensible value for a feature?
                       xs -> xs

          centroid :: Player2 -> (Double,Double)
          centroid pl = let els = getAll pl brd
                            els'1 = fromIntegral $ sum $ map fst els
                            els'2 = fromIntegral $ sum $ map snd els
                            cnt = fromIntegral $ length els
                        in (els'1/cnt, els'2/cnt)
          
          scale :: Double -> Double -> Double
          scale factor arg = arg / factor
          scaleI f = scale (fromIntegral f)
          scaleX = scaleI (fst (boardSize g))
          scaleY = scaleI (snd (boardSize g))
          scaleXY (x,y) = ((scaleX x), (scaleY y))
          scaleCnt v = scaleI (2 * (snd (boardSize g))) (fromIntegral v)

instance Game2 Breakthrough where
    type MoveDesc Breakthrough = (Position,Position) -- first position, second position
    type GameRepr Breakthrough = [Double] -- sparse field repr.
    type GameParams Breakthrough = (Int,Int) -- board size

    freshGameDefaultParams = freshGame (8,8)

    gameName g = "Breakthrough size=" ++ show (boardSize g)

    freshGame bsize@(sw,sh) = Breakthrough { board = HashMap.fromList [ (pos,P1) | pos <- row 0 sw ] `mappend`
                                                     HashMap.fromList [ (pos,P1) | pos <- row 1 sw ] `mappend`
                                                     HashMap.fromList [ (pos,P2) | pos <- row (sh-2) sw ] `mappend`
                                                     HashMap.fromList [ (pos,P2) | pos <- row (sh-1) sw ]
--                                             HashMap.fromList [ (pos,pl) | (pl,rows) <- [(P1,[0,1]), (P2, [(sh-1,sh-2)])]
--                                                                           , row'num <- rows
--                                                                           , pos <- row row'num sw ]
                                           , boardSize = bsize
                                           , winningP1 = HashSet.fromList (row (sh-1) sw)
                                           , winningP2 = HashSet.fromList (row 0 sw)
                                           , countP1 = 2 * sw
                                           , countP2 = 2 * sw
                                           }
    
    winner g | countP1 g == 0 = return P2
             | countP2 g == 0 = return P1
             | (getAllSet P1 (board g) `HashSet.intersection` winningP1 g) /= mempty = return P1
             | (getAllSet P2 (board g) `HashSet.intersection` winningP2 g) /= mempty = return P2
             | otherwise = fail "no winners"

    movesDesc g p = let dirs = case p of
                                  P1 -> [(1,1),(0,1),(-1,1)] -- move upward
                                  P2 -> [(1,-1),(0,-1),(-1,-1)] -- move downward
                        brd = board g
                        applyDir (x,y) (dx,dy) = (x+dx, y+dy)
                        movesPos = [ (pos1, applyDir pos1 dir) | pos1 <- getAll p brd, dir <- dirs]
                        boardsPos = map (applyMove g) movesPos

                        uplift :: (a, Maybe b) -> Maybe (a,b)
                        uplift (x,my) = do
                           y <- my
                           return (x,y)
                    in
                        catMaybes $ map uplift $ zip movesPos boardsPos

    -- uses default implementation for 'moves':
    -- moves g p = map snd $ movesDesc g p 

    applyMove g (p1,p2)
       | p1 `illegalPos` g = Nothing
       | p2 `illegalPos` g = Nothing
       | otherwise = let b0 = board g
                         b1 = HashMap.alter (const $ valPos1) p2 b0
                         b2 = HashMap.delete p1 b1
                         valPos1 = HashMap.lookup p1 b0
                         valPos2 = HashMap.lookup p2 b0

                         -- board after move
                         brdOK = g { board = b2 }

                         -- move removing P1 piece
                         brdOK'P2P1 = brdOK { countP1 = (countP1 g) - 1 }

                         -- move removing P2 piece
                         brdOK'P1P2 = brdOK { countP2 = (countP2 g) - 1 }

                         isDiagonalMove = (fst p1 - fst p2) /= 0

                     in
                       case (valPos1, valPos2) of
                         (Just P1,Just P2) | isDiagonalMove -> return brdOK'P1P2
                                           | otherwise -> Nothing -- we can only kill moving diagonally
                         (Just P2,Just P1) | isDiagonalMove -> return brdOK'P2P1
                                           | otherwise -> Nothing -- we can only kill moving diagonally
                         (Just _,Nothing) -> return brdOK
                         (Nothing,_) -> Nothing -- we cannot move non-existing piece
                         (Just P1,Just P1) -> Nothing -- we cannot kill our own pieces
                         (Just P2,Just P2) -> Nothing -- we cannot kill our own pieces

    toRepr g = let 
        pos = allPos (boardSize g)
        look c p = if HashMap.lookup p (board g) == c then one else zero
        repr = [ look c p | c <- [Nothing, Just P1, Just P2], p <- pos]
     in encodeAllFeatures g ++ repr
    {-# INLINE toRepr #-}

    fromRepr params repr'with'features = let
        repr = drop (countFeatures g0) repr'with'features

        g0 :: Breakthrough
        g0 = freshGame params
        pos :: (Maybe Player2) -> [((Maybe Player2),Position)]
        pos c = zip (cycle [c]) (allPos (boardSize g0))
        cs :: [Maybe Player2]
        cs = [Nothing, Just P1, Just P2]

        pos3 :: [((Maybe Player2),Position)]
        pos3 = concatMap pos cs

        b0 = board g0 
        b1 = foldl update b0 (zip pos3 repr) 
            where update b ((c,po),val) | val == zero = b
                                        | val == one = HashMap.alter (const c) po b
                                        | otherwise = error "fromRepr: bad val"

        g1 = g0 { board = b1
                , countP1 = count P1 b1
                , countP2 = count P2 b1
                }
     in g1

    invertGame br = br { countP1 = (countP2 br)
                       , countP2 = (countP1 br)
                       , board = (HashMap.fromList . map swapSides . HashMap.toList . board $ br)
                       }
        where
          h = snd (boardSize br)
          invertPos (x,y) = (x,h-y)
          swapSides (pos, pl) = (invertPos pos, nextPlayer pl)

illegalPos :: Position -> Breakthrough -> Bool
illegalPos _pos@(x,y) g 
    | y < 0 = True
    | y >= (snd (boardSize g)) = True
    | x < 0 = True
    | x >= (fst (boardSize g)) = True
    | otherwise = False

legalPos :: Position -> Breakthrough -> Bool
legalPos pos brd = not (illegalPos pos brd)

-- | get all positions within a specified row. 
row :: Int -> Int -> [Position]
row rowNum rowLength = [(column',rowNum) | column' <- [0..rowLength-1]]
{-# INLINE row #-}

-- | get all positions within a specified column. 
column :: Int -> Int -> [Position]
column colNum colLength = [(colNum,row') | row' <- [0..colLength-1]]
{-# INLINE column #-}

-- | get all possible positions
allPos :: (Int,Int) -> [Position]
allPos (rowLength,colLength) = [(column',row') | row' <- [0..colLength-1], column' <- [0..rowLength-1]]
{-# INLINE allPos #-}

-- | get all positions of pieces of specified player on board (as a set)
getAllSet :: Player2 -> BoardMap -> Set Position
getAllSet el hm = HashSet.fromList $ HashMap.keys $ HashMap.filter (==el) hm

-- | get all positions of pieces of specified player on board (as a list)
getAll :: Player2 -> BoardMap -> [Position]
getAll el hm = HashMap.keys $ HashMap.filter (==el) hm

-- | count number of pieces of specified player on board
count :: Player2 -> BoardMap -> Int
count p hm = length $ filter (==p) $ map snd $ HashMap.toList hm

-- -- debugging utils 
-- pp g = putStrLn . prettyPrintGame $ g
--  
-- g0 :: Breakthrough
-- g0 = freshGame (6,6)

