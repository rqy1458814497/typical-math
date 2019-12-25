module Knowledge where

import           ABT
import           Control.Applicative (Applicative (..))
import           Control.Monad       (ap, liftM, join, mapM_, mapM)
import           Match               (match, unify)
import           Utilities

-- This module defines the necessary data structures for Bidirectional.hs

-- TODO refactor the system so that it is more easily extensible

-- The idea is that knowledge of the assignment of meta-variables,
-- and, by the way, the uuid stuff is carried through the derivation
-- process, and thus has a monadic feature. So we can easily add a log
-- function to that. More boldly, we can even make it an IO monad!
type LogDoc = String

data Knowledge = Knows
    { assignment :: Assignment
    , gensym     :: Int
    , logstring  :: LogDoc  -- This should always end with a newline!
    } deriving (Show)

--instance Show Knowledge where
--  show (Knows ass gen log) = "(Knows : " ++ (show ass) ++ " Currenc gensym: " ++ (show gen) ++ ")"

ignorance = Knows [] 0 "Starting from ignorance;\n"

data State a =  State { getState :: Knowledge -> (Maybe a, Knowledge) }

instance Functor State where
  fmap = liftM

instance Applicative State where
  pure = return
  (<*>) = ap

instance Monad State where
  return x = State (\s -> (Just x, s))

  (State p) >>= f = State (\x -> let (d, state) = p x in
    case d of
      Just d' -> runState (f d') state
      Nothing -> (Nothing, state)
    )

-- Several utilities for the state monad.

runState :: State a -> Knowledge -> (Maybe a, Knowledge)
runState (State f) i = f i

get :: State Knowledge
get = State (\s -> (Just s, s))

set :: Knowledge -> State ()
set k = State (\s -> (Just (), k))

mergeState :: Knowledge -> State ()
mergeState (Knows ass gen log) = State f 
  where f :: Knowledge -> (Maybe (), Knowledge)
        f (Knows ass' gen' log') = case (mergeAssoc ass ass') of
          Just m -> (Just (), (Knows m (max gen gen') (log ++ log')))
          Nothing -> (Nothing, (Knows [] (max gen gen') (log ++ log' ++ "Merge failed!\n")))

withState :: a -> Knowledge -> State a
d `withState` s = State (\s -> (Just d, s))

getAssignment :: State Assignment
getAssignment = do
  k <- get
  return (assignment k)

setAssignment :: Assignment -> State ()
setAssignment ass = do
  k <- get
  set (k{assignment = ass})

getGensym :: State Int
getGensym = do
  k <- get
  return (gensym k)

setGensym :: Int -> State ()
setGensym n = do
  k <- get
  set (k{gensym = n})

incGensym :: State ()
incGensym = do
  n <- getGensym
  setGensym (n+1)

writeLog :: LogDoc -> State ()
writeLog log = do
  state <- get
  set (state {logstring = (logstring state ++ log)})

panic :: LogDoc -> State a
panic d = State (\s -> (Nothing, s {logstring = logstring s ++ d}))

mergeMatch :: Maybe Assignment -> State ()
mergeMatch Nothing = panic "Match Failed\n"
mergeMatch (Just ass) = do
  k <- get
  case (mergeAssoc ass (assignment k)) of
    Just assignment -> do
      set (k{assignment = assignment})
    Nothing -> do
      panic "Match success but merge failed\n"

metaSubstituteFromState :: ABT -> State ABT
metaSubstituteFromState expr = do
  knowledge <- get
  return (expr `metaSubstitute` (assignment knowledge))

-- A judgment susceptible for bidirectional type-checking
-- consists of two parts: one named `input`, and another
-- named `output`. However, These two parts are usually
-- both bound by the context (in the input).
-- In a inference rule, it is required that all the meta-
-- variables in the input part of the premise is obtained
-- by pattern matching with the input of the conclusion.
-- Also, the output of the conclusion is completely obtained
-- by pattern matching with the output of the premise.

-- We try out a more elegant approach, where the judgments are
-- syntactically seperable to input and output parts, but not
-- explicitly marked out. We use a basic form of unification,
-- where meta-variables with closures are always treated as 
-- rigid. If the arrangements of the judgments are correct, the
-- information will propogate through the derivation tree, as if
-- the input/output parts were correcly marked. In this way, a
-- judgment is no different from a ordinary syntactic node:

type Judgment = ABT

-- If this does not work, we will fall back to the traditional
-- bidirectional method instead.

data InferenceRule 
  = Rule 
      { premises   :: [Judgment {- with meta-variable -}]
      , conclusion ::  Judgment {- with meta-variable -}
      } deriving (Show)  -- TODO Pretty printing

freeMetaVarInf r = freeMetaVar (conclusion r) ++ concatMap freeMetaVar (premises r)
metaSubstituteInf r subs = Rule (map (`metaSubstitute` subs) (premises r))
  ((conclusion r) `metaSubstitute` subs)

metaSubstituteInfFromState :: InferenceRule -> State InferenceRule
metaSubstituteInfFromState expr = do
  knowledge <- get
  return (expr `metaSubstituteInf` (assignment knowledge))

data Derivation
  = Derivation
      { rule          :: InferenceRule
      , derivePremise :: [Derivation {- without meta-variable -}]
      , judgment      :: Judgment    {- without meta-variable -}
      } deriving (Show)

metaSubstituteDer :: Derivation -> Assignment -> Derivation
metaSubstituteDer (Derivation r ds j) subs =
  Derivation r (map (`metaSubstituteDer` subs) ds) (j `metaSubstitute` subs)

metaSubstituteDerFromState :: Derivation -> State Derivation
metaSubstituteDerFromState d = do
  knowledge <- get
  return (d `metaSubstituteDer` (assignment knowledge))

getFresh :: InferenceRule -> State InferenceRule
getFresh inf = do
  incGensym
  g <- getGensym
  return $ refresh g inf

refresh :: Int -> InferenceRule -> InferenceRule
refresh gen inf = inf `metaSubstituteInf`
  map (\(MetaVar (Meta n i) _) -> ((Meta n i), MetaVar (Meta n gen) (Shift 0)))
    (freeMetaVarInf inf)

-- Actually there is no backtracking happening here
-- We store all the failures with a Nothing

data StateBacktrack a =  StateBacktrack { getStateBacktrack :: Knowledge -> [(Maybe a, Knowledge)] }

instance Functor StateBacktrack where
  fmap = liftM

instance Applicative StateBacktrack where
  pure = return
  (<*>) = ap

instance Monad StateBacktrack where
  return x = StateBacktrack (\s -> [(Just x, s)])

  (StateBacktrack p) >>= f = StateBacktrack (\s ->
      [ b | a <- p s, b <- case fst a of
          Nothing -> [(Nothing, snd a)]
          Just ar -> getStateBacktrack (f $ ar) (snd a)
        ]
    )

runStateBacktrack :: StateBacktrack a -> Knowledge -> [(Maybe a, Knowledge)]
runStateBacktrack (StateBacktrack f) s = f s

liftBacktrack :: State a -> StateBacktrack a
liftBacktrack (State f) = StateBacktrack (\s -> [f s])

caseSplit :: [a] -> StateBacktrack a
caseSplit cases = StateBacktrack (\s -> [(Just c, s) | c <- cases])