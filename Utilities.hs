module Utilities
  ( mergeAssoc
  , mergeAssocs
  , substituteEqs
  , freeMetaVarEqs
  , justMetaVar
  ) where

import           Control.Monad (foldM, join, liftM2, mapM, liftM)
import           ABT (MetaName(..), ABT(..), Substitution(..), metaSubstitute, freeMetaVar)

-- utilities
mergeAssoc :: [(MetaName, ABT)] -> [(MetaName, ABT)] -> Maybe [(MetaName, ABT)]
mergeAssoc [] assoc = Just assoc
mergeAssoc ((k, v):as) assoc =
  (append (k, v) assoc) >>= (\assoc' -> mergeAssoc as assoc')
  where
    append :: (MetaName, ABT) -> [(MetaName, ABT)] -> Maybe [(MetaName, ABT)]
    append (k, v) assoc
      | k `elem` (map fst assoc) =
        case v == snd (head (filter ((== k) . fst) assoc)) of
          True  -> Just assoc
          False -> Nothing
      | otherwise = Just ((k, v) : assoc `substituteSubs` [(k, v)])

mergeAssocs :: [[(MetaName, ABT)]] -> Maybe [(MetaName, ABT)]
mergeAssocs asss = join $ foldM (liftM2 mergeAssoc) (Just []) (map Just asss)

substituteEqs :: [(ABT, ABT)] -> [(MetaName, ABT)] -> [(ABT, ABT)]
substituteEqs eqs subs =
  map (\(e1, e2) -> (metaSubstitute e1 subs, metaSubstitute e2 subs)) eqs

substituteSubs :: [(MetaName, ABT)] -> [(MetaName, ABT)] -> [(MetaName, ABT)]
substituteSubs s subs =
  map (\(m, e2) -> (m, metaSubstitute e2 subs)) s

metaSubstituteCompose = flip substituteSubs

freeMetaVarEqs :: [(ABT, ABT)] -> [ABT]
freeMetaVarEqs = concatMap helper
  where helper :: (ABT, ABT) -> [ABT]
        helper (e1, e2) = (freeMetaVar e1) ++ (freeMetaVar e2)

justMetaVar :: String -> ABT
justMetaVar s = MetaVar (Meta s 0) (Shift 0)
