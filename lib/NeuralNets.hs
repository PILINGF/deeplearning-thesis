{-# LANGUAGE CPP, BangPatterns, ViewPatterns #-}

module NeuralNets where

import Control.Monad(when, join)
import qualified Data.Tree.Game_tree.Negascout as GTreeAlgo
import Text.Printf
import Data.List.Split(splitPlaces)
import qualified Numeric.Container as NC
import qualified Data.Packed.Vector as Vector


import System.IO.Memoize (ioMemo')
import System.IO.Unsafe
import System.IO

import Board
import CommonDatatypes
import MinimalNN

type LastLayer = (Double,[Double])

data AgentNN = AgentNN { net :: TNetwork
                       , lastLayer :: LastLayer
                       , col :: Color
                       } deriving (Show, Ord, Eq)

data AgentNNSimple = AgentNNSimple { netS :: TNetwork
                                   , colS :: Color
                                   } deriving (Show, Ord, Eq)

data AgentNNSimpleLL = AgentNNSimpleLL { netSLL :: TNetwork
                                       , colSLL :: Color
                                       } deriving (Show, Ord, Eq)


instance Agent AgentNNSimple where
    mkAgent colo = do
      let (!neuralNetwork, sizes) = myUnsafeNet
      print ("Agent created","AgentNNSimple")
      return (AgentNNSimple neuralNetwork colo)
    makeMove ag@(AgentNNSimple neuralNetwork colo) brd = do
      let gst = GameState brd (\ g -> doubleToEvalInt $ evalBoardNetOnePassN 1 (gtColorNow g) (gtBoard g) neuralNetwork)
                          colo colo
          depth = 3
          (princ, score) = GTreeAlgo.negascout gst depth
      print ("AgentNNSimple", score, (take 3 $ evaluateBoard ag brd))
      return (gtBoard $ head $ tail $ princ)
    evaluateBoard (AgentNNSimple neuralNetwork colo) brd = 
        [("int" <> valInt)
        ,("bare" <> valDbl)
        ,("network",valNet)]
     where
       valInt = doubleToEvalInt $ valDbl
       valDbl = evalBoardNetOnePassN 1 colo brd neuralNetwork
       brdNeg = if colo == White then brd else negateBoard brd
       valNet = unwords $ map (printf "%0.2f") $ Vector.toList $ computeTNetworkSigmoidSteps 1 neuralNetwork (boardToSparseNN brdNeg)
       s <> v = (s, (show v))
                

instance Agent AgentNNSimpleLL where
    mkAgent colo = do
      let (!neuralNetwork, sizes) = myUnsafeNetLL
      return (AgentNNSimpleLL neuralNetwork colo)
    makeMove (AgentNNSimpleLL neuralNetwork colo) brd = do
      let gst = GameState brd (\ g -> doubleToEvalInt $ evalBoardNetOnePass (gtColorNow g) (gtBoard g) neuralNetwork)
                          colo colo
          depth = 3
          (princ, score) = GTreeAlgo.negascout gst depth
      print ("AgentNNSimpleLL", score)
      return (gtBoard $ head $ tail $ princ)

instance Agent AgentNN where
    mkAgent colo = do
      let (!neuralNetwork, sizes) = myUnsafeNet
          swapTuple (a,b) = (b,a)
          ll :: LastLayer
          -- ll = swapTuple ([0.8612870072635965,0.13556289898576446,0.23856740534874787,-0.9979329974235303,0.5214206483083219,0.5567218465572636,6.30721199599138e-2,-0.9964997583716422,0.6633215227291445,0.9727764072367318,-0.9977300656726051,-0.7137626797569403,0.599503073952065,0.21117238019021678,-0.8943134998344482,-0.8507363319229861,-0.5796927500773281,-0.5944415874686173,-0.15455666225322306,0.48421792303516864,7.27231106402837e-2,-0.9283644693418183,0.30689324517669125,-0.3539762275595806,-0.6070475938654247,0.569425951578671,-0.9770268090296865,-0.7042885676466255,0.829879962337911,-0.8374036555090278,0.4084455058795846,0.19033645119509512,0.5226687071932188,0.37593093252835463,0.8750966180591477,0.2783969819593024,0.21502082061293115,0.5328102176833449,-0.913095686465424,1.7834153344699955e-2,-0.21090731225389203,-0.7926096658144519,0.33027529205870665,-0.5950117361138936,-0.2322369595737246,0.8544967675730344,0.8832103002110319,-0.48539113861681993,-0.8998826600710117,-0.47158017053846035,0.706039676126762,-0.28561829110183434,0.9198783114683449,0.3895434736047527,-0.2832766779528131,-0.20329351024642128,4.417816111277628e-2,-0.19855374724845487,-8.127954092267964e-2,0.8928326986485555,-0.7989752224829971,-0.33452644307129176,-6.750250789346235e-2,-6.010680309923688e-2,0.4154639143443546,0.9648585837921593,0.9480414301364253,-0.6649152911500036,0.6882932372250472,0.7699115131259664,0.3884008422743015,0.6881782900708593,-5.634221277961582e-2,-0.715489425131538,-0.8616836802575512,0.6833222561027494,0.31588681243071215,-0.38215905000508044,0.43148713223178947,-0.4126939727483758,-0.8082677460400503,0.9729490146612128,0.6163305835165447,-0.3789216454834452,-0.6158593001591457,5.109623424964349e-3,-4.076986403769234e-2,-0.2314156693706757,0.7605746771119992,-0.7303217846056131,0.5799821294014398,0.74224702249001,0.31361764991484775,-0.9989099173730651,0.3990524857254252,-0.32232293073842144,-0.9131409321750923,0.15206208775660257,0.6079320679483644,0.5941176532464534],0.0)

          ll = swapTuple ([3.53296028268415e-2,0.41258374770284667,0.9716251999924068,0.6461093501300319,0.36858339919815974,0.43597026853704457,-0.7073701587551537,0.3868414005608092,0.723148315109319,-0.8972674945694721,0.4420997713223065,0.9067931993487799,0.41409923013543826,-8.068197395783439e-2,0.8862581687622735,0.4852201054061276,0.2335516086598728,-8.258575847493566e-3,0.5770323197228124,-0.6179587062604741,0.6029908134272255,-0.6954166844743483,-2.3268075345892703e-2,0.6522853800020074,0.7885808604107984,-0.18162417186351187,-0.8635969389240092,0.2358592185988495,-2.0870501136375674e-2,3.855954827335473e-2,0.8608507813245156,0.44788651292603876,-0.8370198497154122,-0.7138133129169086,-0.50701765631321,6.979141541207334e-2,0.5645833216601714,0.6436395529316379,0.4098369764352412,-0.21073449671562128,-0.5188514945612208,0.8162304576671524,-0.8001330029844371,0.289086789351497,0.7966122309981232,-9.673884916038822e-2,-0.3636773604589607,5.590794289129719e-2,0.6438126153232913,-0.44717179090697257,0.8080652151392604,-0.34206643739057685,-0.523904582284483,0.8533622218496901,-0.15254434747163947,-0.8245801770682546,-4.804120692148639e-2,-8.414065431599993e-2,-0.23766827394696688,0.6674629696916956,-0.6089329548506883,0.3518428432447622,0.19794358456829086,-0.5987647581755235,0.982028878142186,0.4293737527949182,0.9381724793099544,0.948671638031868,-0.9184082825482405,0.3319881138357139,-0.8840105263038633,-0.8857892884216636,0.7642278263217748,-0.9859743558076388,0.4267285483093619,0.4768625051016475,-0.5687649917542832,0.8383303386549874,0.7062552988634827,0.5309687713312312,-0.3985756486458969,-0.11372085506377672,0.5258725723356228,0.5847200106534876,-0.32585509409660296,-0.9875019163049588,0.5886022298450573,-0.453834024215104,-0.20890574739471224,-0.4829861061320282,-0.6273434043457027,-0.10322518477237597,0.7042790125049632,-0.10219172591915826,-0.12199168164155139,-0.5768319785659191,0.6257375493124433,0.47341737012022533,0.10637748322659779,0.32836732190719675,0.45890359606432907,-0.8375868044838486,9.987190051198369e-2,-0.44782931049879404,-0.11087351365969522,2.757090085425884e-2,-4.1446131521124085e-2,0.5937040707990835,-0.2618395095647157,0.874687216657114,0.6804757705000999,-0.8140214915474251,0.1303321507459041,0.5256003071555118,-0.29024916843887527,3.419757965565284e-2,-0.4517019858419673,-0.2438149012739761,-0.20329832095183797,-0.7655872110659623,0.593519546851532,-0.318945183405569,-0.4640775697189492,-0.52324701717546,0.16556341659168594,9.13246870529203e-2,0.7954894760959699,6.790746398605196e-2,0.479076946345282,0.43248452847878993,0.21358928986839154,5.439637954929988e-2,-0.9713933087290714,0.14208328233221423,5.8398554678791514e-2,-0.17820576073679661,0.5820892720840563,-4.170165215183763e-3,0.3054782922179611,0.1057137156470549,-5.283254772958057e-2,-0.3733012021459514,-7.445501831295176e-2,-0.19333998022633803,-0.7568969064605653,-0.13019735131864185,-0.1764696828388661,-0.5171407674598518,0.9094401333425084,-0.17306928987114056,0.13614496975318935,0.508675945394202,-0.9428455945463383,5.064099213548956e-2,0.2402007553606118,-0.5557788842765989,-0.45616461023034227,0.5925060213736468,0.8110931793490825,-0.17635303405022218,-0.5911394629504712,-0.7394648043677756,0.5180989098584903,3.1990567697212535e-2,-0.16443580389307466,-2.569838489035603e-2,-0.8295134218583102,0.6040972854268947,-0.12067428930828084,-9.85072125624753e-3,0.9284144022008871,0.8220739766829268,0.9168169127757311,0.48046837842754564,0.5772995236979648,-0.4902180404075762,0.30592908809775365,0.34494316033351224,7.4300223077157e-2,-7.388228158674681e-2,-0.9721542072231288,0.2740715342713329,0.5827872648080052,0.2856753036428332,-0.9921924599341236,-0.8380414316118843,-0.5002939098360948,-0.21431214129683362,-0.7199577501645849,-0.3412520239990122,0.3518228545623143,-0.7001025562825689,-0.8923686169664855,-0.6354758553341708,-0.17367701155333148,-0.47572942567941756,0.11846069119354063,-0.3421570248590291,0.4331170027563378,0.8612580319162977,-0.23431034051329314,-9.719509457233122e-2,0.5519351741482839,-0.28854396308459873,0.32594813300849057,-0.18280587822382066,0.2928120721556262,0.14751370934705643,-0.24905841487203007,0.12118808512919288,-4.633644580538454e-2,0.21139532095441793,0.1664317154522068,0.7408132366637636,0.18976529720157065,-0.9029710029015716,-0.12473002830094049,-0.5666186326793781,0.6384096644457726,0.4971824933491835,0.698150226663534,-0.2142267067473005,0.5807893754256417,0.7699334796170649,0.9315144659197341,0.32182861091100556,0.8554315691971957,0.5541016549061266,-0.5596744877875663,-0.31224635296492154,-0.6855424614854091,-0.14970114557820824,-0.7385867084520996,0.896756089622359,0.25686113562880863,5.062828908173844e-2,-0.10103707837898379,0.9574380055211227,0.7834925647022264,0.27523767520562514,0.35598674965644794,4.677762624695636e-2,0.4246221382726725,-0.6620745578261114,-0.7743019654712298,-0.13132400435666258,-0.3558058267168087,-0.3130531243486725,-0.7579454404267543,-0.6795798066804715,-0.76815992593943,0.66049001078303,0.9233825384951844,-0.5595948006234901,0.377206269141072,-0.2587864770009578,0.37610477690608124,-0.4506913051437509,-0.5499284711717489,-7.841739666974101e-3,-0.707730359971398,0.167604035100682,-0.1032801656140927,0.7123450791256964,0.37617235451438646,-0.5406569786292208,0.26047297819070026,-0.6985896058501704,-0.46939503266269855,-0.8877406219445942,-0.3112571101221364,0.9909344790768884,0.882134962731487,0.3826334373339628,-0.5439794729505179,7.191970831758421e-2,0.8601086477758486,0.6738674678388199,-0.16326047267035837,-0.8052072198666715,-0.27070006435279415,-0.7193870305981804,0.9950481055095632,-0.7466048526123219,0.3376510291100978,-5.439271087810371e-2,0.5420615469100569,-0.2055574086609624,0.441013516906019,-0.47415337937325863,-1.6391744401644148e-2,0.2526682122039421,-0.930951010045953,-0.4644631155986485,0.68887489046998,-0.302219341237705,0.54328253063499,-0.7155980054234246,-0.8569300109093627,0.8595472607050068,0.8981348256065702,-0.3214519597512593,-0.5426712170267909,-0.922054252571922,0.49804490627652576,-0.7789684357963964,-0.4014244529974127,-0.5051395810707995,-0.7648195114959637,0.19366660207491848,-0.4538412829297622,-0.6487700773620413,7.145142579759356e-2,0.8270678458025362,-0.1886536429771788,-0.8734059215749743,0.19541122990673077,-0.7660610177600382,0.8469877340255205,-0.7976407173979687,-0.3721979380504499,-0.8184022901641212,-0.6225231180551278,-0.8955875230343724,-0.10245687437640005,0.7866460872307932,0.6246212713029344,-0.506137007847715,0.9130100959971192,0.10655304394956988,0.2566651789161265,-0.3036247150151452,-0.390879799062015,-0.5045170045531349,0.27734701410185925,0.8526601020219491,0.3831435079558523,-0.13395928877426333,3.8725333865275546e-2,0.49278949086095136,-0.8105771776503568,0.42443153577553505,0.3723725242797904,0.15397978745227126,-0.44750273875164903,0.9838427509007859,-0.1634934687867624,-0.7087351444216325,-0.702260564724724,-0.20637701135238395,0.8356141638203145,0.10323733992324624,9.339138375714584e-2,0.7877221166787696,4.5146291657066184e-2,0.3158215534126405,-0.3926837250419941,-0.8396917963228165,-0.9447812071772341,0.9563269104008418,-5.257160821771012e-2,0.9386726315974123,0.1982600718193288,0.5150779064567963,-0.1966419020316097,0.2965357940800739,-0.3419755231805939,0.6098326793584812,0.2731829425700696,0.4142366218375655,-0.3814255110320708,-0.5255598046988552,0.730414488455086,-0.9337733651676683,0.6548105775948205,0.5214435583704933,0.9062971117278595,-0.8949465612587268,-0.40863278234606715,0.8406142134020629,-0.11756336663461364,-0.45245008632925576,-1.1178417345955038e-2,0.9947560456551041,0.46160199911859023,0.47080111918537715,0.927474944525007,-0.7958373387051527,0.10080267886367911,-0.4956291193152016,-0.8678168797458363,-0.5815079244913577,-0.5814604753895318,5.275465506299981e-2,0.7245744122073792,0.4854446457843935,0.7271870573714094,-0.923361989928656,0.13133340045766428,0.9987250309398858,-0.12793332355050713,0.8279639172701063,0.7572170089309835,0.583639121492882,0.1897931921039253,-7.49227850545553e-2,0.7636329437656559,0.7097380203089563,-0.4183078129891935,0.28554894273410514,0.517597188196403,0.4570425467303749,-0.2490067792261741,-0.8425714561635618,7.288172954618366e-3,-0.5475124399265201,-0.13486172328903057,0.7413110123979789,0.9896726602443968,0.2581292144728622,0.22531536985213818,-0.9387407841414432,0.1202970607396201,0.1164176315450478,-2.1886506704056563e-2,-0.9127704142669126,-0.6945450009294818,-0.5191030932824259,-0.3715542055485812,-0.6928314056821907,0.7789028505996936,-0.8689780992013809,-0.1709225112879953,0.38989266463548433,0.795323963343854,-0.9997266866006098,-0.9450867773507248,0.49388553354577724,0.2893491395257921,0.922521179086701,-1.7127654770268785e-2,0.3786648706302367,0.36427006473793155,0.8054486259454994,-9.847597677118558e-2,0.5773704818608942,0.8770080251316903,4.571976383687781e-3,0.15460891845323466,-0.7981957997833502,-0.25054504040127923,-0.9959997225954764,-0.7695046681014233,-4.9848181229548816e-2,5.543555278178625e-3,-0.8940782457610534,0.38403328070350784,2.8676832792348117e-2,0.9668127253758214,0.7857401064853098,0.6019608746272256,-1.8098298866809914e-2,-0.6724725495372017,-0.4294452122594212,-0.574671417803607,-0.38353934808148993,-0.9245114893348523,0.16831517325483714,-0.5363335569502674,-0.4363606979886183,-1.7169543491863726e-2,-0.6172873681627535,0.19640316186888085,-0.21884751230762167,-0.9175298420035822,-0.7913429616201146,0.7826644996590659,1.5577005141663713e-2,-0.9015580041578783,0.6736095480614057,0.7301326538361523,0.5861536003517795,-4.7198324939927705e-3,-0.7659574634485546,0.44853303942807465,0.15000419401639742,0.44916095928235067,-0.8094141357823521,0.5629755314811129,0.41136753108884183,0.306604734849133,-0.6037213165964792,0.7402791592791205,0.4820588650833775,-0.21940421799073895,-0.9564820119814781,0.10055166673032034,0.5797970914664503,-0.434923155417265,-0.2653753752108028],0.0)

--          [ll] = lastLayerTN $ fst myUnsafeNetLL
--          ll' = (0, replicate (last sizes) 1)

      return (AgentNN neuralNetwork ll colo)
    makeMove agent brd = do
      let gst = GameState brd (\ g -> doubleToEvalInt $ evalBoardNet (gtColorNow g) (gtBoard g) (net agent) (lastLayer agent)) 
                              (col agent) (col agent)
          depth = 1
          (princ, score) = GTreeAlgo.negascout gst depth

          pr = "http://localhost:3000/board/" ++ (reprToRow $ boardToDense $ gtBoard $ last $ princ)
      print ("AgentNN-score",score)
      -- hPutStrLn stderr ("AgentNN-score " ++ show score ++ " " ++ pr)
      return (gtBoard $ head $ tail $ princ)

printE :: (Show a) => a -> IO ()
printE p = do
  hPutStr stderr (show p)
  hPutStr stderr "\n"

doubleToEvalInt :: Double -> Int
doubleToEvalInt d = round (d * (fromIntegral ((maxBound :: Int) `div`10)))

sparse = True
nn'filename = (if sparse then "/home/tener/abalone-nn/nn_183.txt-500" else "/home/tener/abalone-nn/nn_61.txt-100")

parseNetFromFile'' fp = ioMemo' (parseNetFromFile `fmap` readFile fp)
parseNetFromFile' = join $ parseNetFromFile'' (nn'filename) -- "/home/tener/abalone-nn/nn_183.txt-500"
parseNetFromFile'LL = join $ parseNetFromFile'' "nn_ll.txt"

{-# NOINLINE myUnsafeNet #-}
myUnsafeNet = unsafePerformIO parseNetFromFile'

{-# NOINLINE myUnsafeNetLL #-}
myUnsafeNetLL = unsafePerformIO parseNetFromFile'LL

parseNetFromFile :: String -> (TNetwork, [Int])
parseNetFromFile input = asserts $ (result, sizes) -- (length weights, length weights'split, length biases, neuronCount, layerCount, sizes)
  where input'lines@(sizes'row : rest'rows) = lines input
        sizes = readIntsRow sizes'row -- sizes in first line

        neuronCount = sum sizes
        layerCount = length sizes

        rest'double'rows :: [[Double]]
        rest'double'rows = map readDoublesRow rest'rows

        weights, biases :: [[Double]]
        (biases,moar) = splitAt layerCount rest'double'rows -- biases in next layerCount lines -- in each appropriate number of biases
        (weights,garbage) = splitAt neuronCount $ moar -- weights in next neuronCount lines
        weights'split = splitPlaces sizes weights

        --- weights, biases, neuronCount, layerCount, sizes
        -- biases'neg = (map (map negate) biases)  -- must negate biases -- different from matlab -- not any more

        result = network
        network = mkTNetwork weights'split biases

        asserts r | garbage /= [] = error (printf "parseNetFromFile: garbage not empty: %d elements" (length garbage))
                  | length weights /= neuronCount = error (printf "parseNetFromFile: too little weights: %d (should be %d)" (length weights) neuronCount)
                  | length weights'split /= layerCount = error "parseNetFromFile: not enough weights?"
                  | otherwise = r -- r for result


readDoublesRow :: String -> [Double]
readDoublesRow row = map read (words row)

readIntsRow :: String -> [Int]
readIntsRow row = map read (words row)

evalBoardNet :: Color -> Board -> TNetwork -> LastLayer -> Double
evalBoardNet col brd net (ll'b, ll'w) = result
    where
      brdEval = if col == White then brd else negateBoard brd
      values = boardToSparseNN brdEval

      net'll :: TNetwork
      net'll = mkTNetwork [[ll'w]] [[ll'b]]

      result'p1 = computeTNetworkSigmoid net values
      result'p2 = computeTNetworkSigmoid net'll result'p1

      combine = NC.sumElements
      result = combine result'p2

evalBoardNetOnePass :: Color -> Board -> TNetwork -> Double
evalBoardNetOnePass col brd net = result
    where
      brdEval = if col == White then brd else negateBoard brd
      values = boardToSparseNN brdEval
      result = NC.sumElements $ computeTNetworkSigmoid net values

evalBoardNetOnePassN :: Int -> Color -> Board -> TNetwork -> Double
evalBoardNetOnePassN steps col brd net = result
    where
      brdEval = if col == White then brd else negateBoard brd
      values = boardToSparseNN brdEval
      result = NC.sumElements $ computeTNetworkSigmoidSteps steps net values
     
g0 :: (Num a) => [a]
g0 = [1,0,1,0,0,0,0,0,1,1,1,1,0,1,1,0,1,1,1,0,1,1,1,0,1,0,0,1,0,1,1,1,1,1,0,1,0,0,1,0,0,1,0,1,1,1,0,0,1,1,0,1,0,0,1,0,1,1,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,1,0,0,0,1,0,0,0,0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,0,0,1,0,1,0,0,0,0,0,0,0,1,0,1,1,0,0,0,0,1,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0,0,0,0,1,0,1,0,0,1,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,1,0,0,0,0,0]

