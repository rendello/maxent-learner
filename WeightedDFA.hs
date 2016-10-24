{-# LANGUAGE ScopedTypeVariables, ExplicitForAll #-}

module WeightedDFA where

import Control.Monad
import Control.Monad.ST
import Control.Monad.State
import Data.Array.IArray
import Data.Array.MArray
import Data.Array.ST
import Data.Array.Unboxed ()
import Data.Ix
import Data.Tuple
import Data.Bits
import Ring




data WDFA l sigma w = WDFA (Array (l,sigma) (l,w)) deriving Show

labelBounds :: (Ix l, Ix sigma) => WDFA l sigma w -> (l,l)
labelBounds (WDFA arr) = let ((a,_), (b,_)) = bounds arr in (a,b)

segBounds :: (Ix l, Ix sigma) => WDFA l sigma w -> (sigma,sigma)
segBounds (WDFA arr) = let ((_,a), (_,b)) = bounds arr in (a,b)

transition :: (Ix l, Ix sigma) => WDFA l sigma w -> l -> sigma -> (l,w)
transition (WDFA arr) s c = arr!(s,c)

advanceState :: (Ix l, Ix sigma) => WDFA l sigma w -> l -> sigma -> l
advanceState (WDFA arr) s c = fst (arr!(s,c))

mapweights :: (Ix l, Ix sigma) => (w1 -> w2) -> WDFA l sigma w1 -> WDFA l sigma w2
mapweights f (WDFA arr) = WDFA (fmap (fmap f) arr)

pruneUnreachable :: forall l sigma w . (Ix l, Ix sigma) => WDFA l sigma w -> WDFA Int sigma w
pruneUnreachable dfa = WDFA (array arrbound (fmap newdfa (range arrbound)))
    where
        lbound = labelBounds dfa
        cbound = segBounds dfa
        reachable = runSTUArray $ do
            reached :: STUArray s l Bool <- newArray lbound False
            let dfs :: l -> ST s ()
                dfs n = do
                writeArray reached n True
                forM_ (range cbound) $ \c -> do
                    let n' = advanceState dfa n c
                    seen <- readArray reached n'
                    when (not seen) (dfs n')
                return ()
            dfs (fst lbound)
            return reached
        keepstates :: [l] = filter (reachable!) (range lbound)
        nbound = (1,length keepstates)
        oldlabels :: Array Int l = listArray nbound keepstates 
        newlabels :: Array l Int = array lbound (zip keepstates (range nbound))
        arrbound = timesbound nbound cbound
        newdfa (s,c) = let (t,w) = transition dfa (oldlabels!s) c in ((s,c), (newlabels!t, w))

timesbound :: (a,a) -> (b,b) -> ((a,b), (a,b))
timesbound (w,x) (y,z) = ((w,y), (x,z))

-- raw product construction
rawIntersection :: (Ix l1, Ix l2, Ix sigma) => (w1 -> w2 -> w3) -> WDFA l1 sigma w1 -> WDFA l2 sigma w2 -> WDFA (l1,l2) sigma w3
rawIntersection f dfa1 dfa2 = if cbound == cbound2 then WDFA (array arrbound (fmap newdfa (range arrbound)))
                                                   else error "Segment ranges must match"
    where
        lbound1 = labelBounds dfa1
        lbound2 = labelBounds dfa2
        cbound = segBounds dfa1
        cbound2 = segBounds dfa2
        nbound = timesbound lbound1 lbound2
        arrbound = timesbound nbound cbound
        newdfa ((s1,s2),c) = let (t1,w1) = transition dfa1 s1 c
                                 (t2,w2) = transition dfa2 s2 c
                             in (((s1,s2),c), ((t1,t2), f w1 w2))

-- use this one in peactice to omit unreachable states
intersection :: (Ix l1, Ix l2, Ix sigma) => (w1 -> w2 -> w3) -> WDFA l1 sigma w1 -> WDFA l2 sigma w2 -> WDFA Int sigma w3
intersection f dfa1 dfa2 = pruneUnreachable (rawIntersection f dfa1 dfa2)


transduce :: (Ix l, Ix sigma, Monoid w) => WDFA l sigma w -> [sigma] -> w
transduce dfa@(WDFA arr) cs = mconcat $ evalState (mapM trans cs) (fst (labelBounds dfa))
    where
        trans = state . tf
        tf c s = swap (arr!(s,c))

transduceR :: (Ix l, Ix sigma, Semiring w) => WDFA l sigma w -> [sigma] -> w
transduceR dfa@(WDFA arr) cs = foldl (<.>) one $ evalState (mapM trans cs) (fst (labelBounds dfa))
    where
        trans = state . tf
        tf c s = swap (arr!(s,c))

-- counts class-based n-grams. takes in a sequences of character classes to match and counts the number of occurrences. 
countngrams :: forall sigma . (Ix sigma) => (sigma, sigma) -> [[sigma]] -> WDFA Int sigma Int
countngrams sbound classes = pruneUnreachable (WDFA arr)
    where
        n = length classes
        cls :: Array Int [sigma]
        cls = listArray (1,n) classes
        states = range (0, 2^(n-1) - 1)
        unBinary [] = 0
        unBinary (True:x) = 1 + 2 * (unBinary x)
        unBinary (False:x) = 2 * (unBinary x)
        arr :: Array (Int, sigma) (Int, Int)
        arr = array ((0, fst sbound), (2^(n-1) - 1, snd sbound)) $ do
            s <- states
            c <- range sbound
            let ns = sum $ do
                    b <- range (1, n-1)
                    guard (b == 1 || testBit s (b-2))
                    guard (c `elem` (cls!(b)))
                    return (2^(b-1))
                isfinal = (testBit s (n-2)) && (c `elem` (cls!(n)))
                w = if isfinal then 1 else 0
            return ((s,c),(ns,w))

