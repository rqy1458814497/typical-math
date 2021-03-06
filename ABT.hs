module ABT
  ( VarName
  , MetaName(..)
  , NodeType
  , ABT(..)
  , Substitution(..)
  , compose
  , substitute
  , beta
  , metaSubstitute
  , freeMetaVar
  , Assignment
  , nubMetaVar
  ) where

import           Data.List           (intercalate, groupBy, minimumBy)

type VarName = Int
type NodeType = String
type Assignment = [(MetaName, ABT)]

data MetaName = Meta String Int deriving (Eq)

instance Show MetaName where
  show (Meta s i) = s ++ "_{" ++ show i ++ "}"

data ABT
  = Var VarName
  | Node NodeType [ABT]
  | Bind ABT
  | MetaVar MetaName Substitution
  deriving (Eq)

-- Uses De Bruijn Indices starting from zero; therefore we can just derive the Eq class
-- TODO See if the String param in Node should be replaced with a record type of Node types
-- TODO Also we can implement the 'sort' of nodes.
-- TODO Pretty print
instance Show ABT where
  show (Var n)          = "\\mathtt{v}_{" ++ show n ++ "}"
  show (Node name [])   = '\\' : name
  show (Node name abts) = '\\' : name ++ concatMap (('{' :) . (++ "}") . show) abts
  show (Bind e)         = '.' : show e
  show (MetaVar s (Shift 0)) = '?' : (show s)
  show (MetaVar s c)         = '?' : (show s) ++ "\\left[" ++ show c ++ "\\right]"

data Substitution
  = Shift Int
  | Dot ABT Substitution
  deriving (Eq)

instance Show Substitution where
  show (Shift k) = "\\uparrow^{" ++ show k ++ "}"
  show (Dot e s) = show e ++ " . " ++ show s

compose :: Substitution -> Substitution -> Substitution
compose s (Shift 0)         = s
compose (Dot _ s) (Shift k) = compose s (Shift (k - 1))
compose (Shift m) (Shift n) = Shift (m + n)
compose s (Dot e t)         = Dot (substitute e s) (compose s t)

substitute :: ABT -> Substitution -> ABT
substitute (Var m) (Shift k) = Var (k + m)
substitute (Var 0) (Dot e _) = e
substitute (Var k) (Dot _ s) = substitute (Var (k - 1)) s
substitute (Bind e) s = Bind (substitute e (Dot (Var 0) (compose (Shift 1) s)))
substitute (Node name abts) s = Node name (map (`substitute` s) abts)
substitute (MetaVar n c) s = MetaVar n (compose s c)

-- We seriously need to check if there is any bug
beta :: ABT -> ABT -> ABT
-- aux function for Bind's beta reduction
beta (Bind e1) e2 = substitute e1 (Dot e2 (Shift 0))
beta x         y  = error $ "beta is for Bind only." ++ show x ++ show y

metaSubstitute :: ABT -> Assignment -> ABT
metaSubstitute p [] = p
metaSubstitute m@(MetaVar n s) msubs = case lookup n msubs of
  Just e  -> substitute e (msc s msubs) -- This is supposed to be simultaneous..?
  Nothing -> MetaVar n (msc s msubs)
  where msc :: Substitution -> Assignment -> Substitution
        msc (Shift n) _   = Shift n
        msc (Dot e t) ass = Dot (metaSubstitute e ass) (msc t ass)
metaSubstitute v@(Var _)      _     = v
metaSubstitute (Node nt abts) msubs = Node nt (map (`metaSubstitute` msubs) abts)
metaSubstitute (Bind abt)     msubs = Bind (metaSubstitute abt msubs)

nubMetaVar :: [ABT] -> [ABT]
nubMetaVar = map (minimumBy helperOrder) . groupBy nameEq
  where nameEq :: ABT -> ABT -> Bool
        nameEq (MetaVar n _) (MetaVar m _) = n == m
        nameEq _ _ = error "Panic! Non-meta-vars appeared at strange places!"
        helperOrder :: ABT -> ABT -> Ordering
        helperOrder (MetaVar _ (Shift 0)) (MetaVar _ (Shift 0)) = EQ
        helperOrder (MetaVar _ _) (MetaVar _ (Shift 0)) = LT
        helperOrder (MetaVar _ (Shift 0)) (MetaVar _ _) = GT
        helperOrder e f | e == f = EQ
                        | otherwise = error $ "Panic! Meta-vars with closures clashed, giving up on:\n    "
                          ++ show e ++ "\n  and\n    " ++ show f

freeMetaVar :: ABT -> [ABT]
freeMetaVar (Var _) = []
freeMetaVar (Node _ abts) = nubMetaVar $ concatMap freeMetaVar abts
freeMetaVar (Bind abt) = freeMetaVar abt
freeMetaVar m@(MetaVar _ _) = [m]
