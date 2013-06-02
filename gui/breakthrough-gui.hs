{-# LANGUAGE ParallelListComp #-}

module Main where

import Graphics.Blank
import Control.Concurrent
import Control.Monad
import Data.Array
import Data.Maybe
import Data.Tuple
import System.Environment

import BreakthroughGame
import GenericGame
import qualified Data.HashMap as HashMap


data Fill = FillEmpty | FillP1 | FillP2
data BG = BGLight | BGDark | BGSelected | BGPossible deriving (Eq,Read,Show,Ord)
data DrawingBoard = DrawingBoard { getArrDB :: (Array (Int,Int) Field) }

data Field = Field { fFill :: Fill
                   , fBG :: BG
                   , fSuperBG :: Maybe BG
                   }

-- | enable feedback on moving mouse. works poorly with big latency links.
enableMouseMoveFeedback :: Bool
enableMouseMoveFeedback = False

drawPointEv :: Event -> Canvas ()
drawPointEv e = do
  case e of
    Event _ (Just (x,y)) -> drawPoint x y
    _ -> return ()

drawPoint :: Int -> Int -> Canvas ()
drawPoint x y = do
  font "bold 20pt Mono"
  textBaseline "middle"
  textAlign "center"
  strokeStyle "rgb(240, 124, 50)"
  strokeText ("+",fromIntegral x, fromIntegral y)
  return ()

bgToStyle BGLight = "rgb(218, 208, 199)"
bgToStyle BGDark = "rgb(134, 113, 92)"
bgToStyle BGSelected = "rgb(102,153,0)"
bgToStyle BGPossible = "rgb(153,204,0)"

drawField :: (Float,Float) -> Bool -> Field -> Canvas ()
drawField baseXY@(x,y) highlight field = do
  let s2 = side/2
      s4 = side/4
  -- background
  let actualBG = fromMaybe (fBG field) (fSuperBG field)
  fillStyle (bgToStyle actualBG)
  fillRect (x,y,side,side)
  -- border
  strokeStyle "rgb(10,10,10)"
  strokeRect (x,y,side,side)
  -- fill
  let drawFill style = do
        save ()
        beginPath ()
        -- lineWidth 4
        arc ((x+s2), (y+s2), s4, 0, (2*pi), False)
        fillStyle style
        fill ()
        restore ()
  case (fFill field) of
    FillEmpty -> return ()
    FillP1 -> drawFill "rgb(250,250,250)"
    FillP2 -> drawFill "rgb(50,50,50)"

  -- highlight
  when highlight $ do
     strokeStyle "rgb(120, 210, 30)"
     strokeRect (x+side*0.1,y+side*0.1,side*0.8,side*0.8)
    
  return ()

positionToIndex :: (Int,Int) -> Maybe (Int,Int)
positionToIndex (px,py) = do
  cx <- toCoord px
  cy <- toCoord py
  return (cx, cy)
      where
        toCoord val = case (val-offset) `div` side of
                        x | x < 0 -> Nothing
                          | x >= maxTiles -> Nothing
                          | otherwise -> Just x

maxTiles, offset, side :: (Num a) => a
side = 50
maxTiles = 8
offset = 50
      

drawFills :: [Fill] -> Canvas ()
drawFills boardFills = do
  let pos = zip (zip boardFills (cycle [True,False,False]))
            [ (((offset + x*side),(offset + y*side)),bg) 
                  | y <- [0..maxTiles-1], x <- [0..maxTiles-1] | bg <- boardBackgrounds ]

  mapM_ (\ ((f,hl),((x,y),bg)) -> drawField (fromIntegral x, fromIntegral y) hl (Field f bg Nothing)) pos
         

boardBackgrounds = let xs = (take maxTiles $ cycle [BGLight, BGDark]) in cycle (xs ++ reverse xs)
ixToBackground (x,y) = if ((x-y) `mod` 2) == 0 then BGLight else BGDark

newDemoBoard = DrawingBoard $ array ((0,0), ((maxTiles-1),(maxTiles-1))) 
                              [ ((x,y),(Field f bg Nothing)) | y <- [0..maxTiles-1], x <- [0..maxTiles-1] 
                                             | bg <- boardBackgrounds
                                             | f <- cycle [FillEmpty, FillP1, FillP2, FillP2, FillP1]
                              ]


drawBoard maybeHighlightPos (DrawingBoard arr) = mapM_ (\ (pos,field) -> drawField (fi pos) (hl pos) field) (assocs arr) 
    where
      hl p = Just p == maybeHighlightPos 
      fi (x,y) = (offset+side*(fromIntegral x), offset+side*(fromIntegral y))

drawBreakthroughGame :: Breakthrough -> DrawingBoard
drawBreakthroughGame br = let (w,h) = boardSize br
                              toFill Nothing = FillEmpty
                              toFill (Just P1) = FillP1
                              toFill (Just P2) = FillP2
                              getFill pos = toFill $ HashMap.lookup pos (board br)
                              arr = array ((0,0), (w-1,h-1))
                                    [ ((x,y),(Field (getFill (x,y)) (ixToBackground (x,y)) Nothing)) | y <- [0..w-1], x <- [0..h-1]]
                              result = DrawingBoard arr
                          in result
                              

data CanvasGameState = CanvasGameState { boardDrawn :: DrawingBoard
                                       , lastHighlight :: (Maybe Position)
                                       , boardState :: Breakthrough
                                       , playerNow :: Player2
                                       , allFinished :: Bool
                                       }

makeCGS b p = CanvasGameState (drawBreakthroughGame b) Nothing b p False
drawUpdateCGS ctx cgs = send ctx $ do
   drawBoard (lastHighlight cgs) (boardDrawn cgs)
   drawCurrentPlayer (playerNow cgs)
   let win = winner (boardState cgs)
   case win of
     Nothing -> return ()
     Just w -> drawWinner w
   return (cgs { allFinished = (win /= Nothing) })

p2Txt P1 = "Player 1"
p2Txt P2 = "Player 2"

drawWinner w = do
  let txt = p2Txt w ++ " wins the game!"
      tpx = offset + (maxTiles * side / 2)
      tpy = offset + (maxTiles * side / 2)
      
      rpx = offset
      rpy = offset
      rdimx = maxTiles * side
      rdimy = maxTiles * side

  globalAlpha 0.75
  fillStyle "gray"
  fillRect (rpx,rpy,rdimx,rdimy)
  globalAlpha 1
  textBaseline "middle"
  textAlign "center"
  font "bold 20pt Sans"
  strokeStyle (if w == P1 then "darkred" else "darkgreen")
  strokeText (txt, tpx, tpy)
  
drawCurrentPlayer pl = do
  -- put text
  let txt = "Current move: " ++ p2Txt pl
  font "15pt Sans"
  clearRect (0,0,500,offset*0.9) -- fix for damaging board border
  fillStyle "black"
  fillText (txt, offset, offset/2)
  -- put symbol on the left side
  clearRect (0,0,offset*0.9,500)
  let px = offset/2
      py = offset + (side * pside)
      pside = 0.5 + if pl == P1 then 0 else (maxTiles-1) 
  save ()
  font "bold 20pt Mono"
  textBaseline "middle"
  textAlign "center"
  strokeStyle "rgb(240, 124, 50)"
  strokeText ("+",px,py)
  restore ()
  

main :: IO ()
main = do
  args <- getArgs
  let port = case args of
               [x] -> read x
               _ -> 3000
  let bC act = blankCanvasParams port act "." False
  bC $ \ context -> do
         let initial = makeCGS br P1
             br = freshGame (maxTiles,maxTiles) :: Breakthrough
             drawCGS' cgs = drawUpdateCGS context cgs
         var <- newMVar =<< drawCGS' initial

         let drawMove mPos = modifyMVar_ var $ \ cgs -> if allFinished cgs then return cgs else do
               let prevPos = lastHighlight cgs
               when (mPos /= prevPos) (send context (drawBoard mPos (boardDrawn cgs)))
               return (cgs { lastHighlight = mPos })

             clearSuperBG (Field f bg _) = (Field f bg Nothing)
             lastSelect cgs = case filter (\ (pos,(Field _ _ sup)) -> sup == Just BGSelected) (assocs (getArrDB $ boardDrawn cgs)) of
                                [(pos,_)] -> Just pos
                                _ -> Nothing -- no matches or more than one match

             clickSelect ix cgs = do
               let DrawingBoard brd = boardDrawn cgs
                   brdClean = fmap clearSuperBG brd
                   brd' = accum (\ (Field f bg _) sup -> (Field f bg sup)) brdClean [(ix,(Just BGSelected))] 
               send context (drawBoard (Just ix) (DrawingBoard brd'))
               return (cgs { boardDrawn = DrawingBoard brd' })

             clickClear cgs = do
               let DrawingBoard brd = boardDrawn cgs
                   brd' = fmap clearSuperBG brd
               send context (drawBoard (lastHighlight cgs) (DrawingBoard brd'))
               return (cgs { boardDrawn = DrawingBoard brd' })

             drawClick Nothing = return ()
             drawClick mPos@(Just sndPos@(x,y)) = modifyMVar_ var $ \ cgs -> if allFinished cgs then return cgs else do
               let valid state = state `elem` moves (boardState cgs) (playerNow cgs)
               case lastSelect cgs of
                 Nothing -> clickSelect sndPos cgs 
                 Just fstPos | fstPos == sndPos -> clickClear cgs
                             | otherwise -> case applyMove (boardState cgs) (fstPos,sndPos) of
                                             Nothing -> clickSelect sndPos cgs
                                             Just newState | valid newState -> drawCGS' (makeCGS newState (nextPlayer (playerNow cgs)))
                                                           | otherwise -> clickSelect sndPos cgs


         when enableMouseMoveFeedback $ do
           moveQ <- events context MouseMove
           void $ forkIO $ forever $ do
             evnt <- readEventQueue moveQ
             case jsMouse evnt of
               Nothing -> return ()
               Just xy -> drawMove (positionToIndex xy)

         downQ <- events context MouseDown
         forkIO $ forever $ do
           evnt <- readEventQueue downQ
           case jsMouse evnt of
             Nothing -> return ()
             Just xy -> drawClick (positionToIndex xy)

         return ()
