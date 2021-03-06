{-# LANGUAGE
  NoImplicitPrelude
  #-}

module Hakflow.Abstraction.Map
    ( MapCfg (..)
    , map 
    ) where

import Hakflow.Makeflow
import Hakflow.Monad
import Hakflow.Util
import Hakflow.Magma
import Hakflow.Instances.Vector
import Hakflow.Commands.Cat
import Hakflow.Commands.Rm


import Data.Default
import Data.Vector (Vector)
import qualified Data.Vector as V
import Prelude.Plus hiding (group, map)
import qualified Prelude.Plus as P (map)
import Data.Maybe
import qualified Data.Set as S

import Control.Monad.ST
import Data.STRef



chunk :: Foldable f => Int -> f Rule -> Vector (Vector Rule)
chunk limit xs = foldl' pick empty xs
    where
      pick rs r
          | V.length rs == 0             = pure . pure $ r
          | V.length (V.last rs) < limit = V.init rs <|> pure (V.last rs `V.snoc` r)
          | otherwise                    = rs `V.snoc` pure r
{-# INLINE chunk #-}


data MapCfg = Map { chunksize    :: Int
                  , groupsize    :: Int
                  , outputPrefix :: String
                  }

instance Default MapCfg where def = Map {chunksize = 1, groupsize = 16, outputPrefix = "map"}

map :: (Traversable t, Traversable t') => MapCfg -> Command -> t (t' Parameter) -> Hak File
map cfg c ps = do
  rules <- mapM (addRule c) ps

  rules' <- if chunksize cfg > 1
            then let chunks = chunk (chunksize cfg) rules in mapM mcat chunks
            else return $ foldr' V.cons empty rules

  addFlow rules'

  groups <- group rules' (groupsize cfg)
  addFlow groups

  res    <- withPrefix' (outputPrefix cfg) (clean groups)
  addFlow $ pure res

  return . fromJust $ mainOut res

group :: Flow -> Int -> Hak Flow
group rules size = do
  let chunks = chunk size rules
  rules' <- mapM clean chunks
  return rules'


clean :: Vector Rule -> Hak Rule
clean rs = do
  let mains = V.map fromJust . V.filter isJust . V.map mainOut $ rs
  [rCat, rRm] <- mapM (\cmd -> cmd (V.map (param . FileInArg) mains) >>= eval) [cat def, rm def]
  return Rule { outputs = S.empty
              , inputs = S.fromList . V.toList $ mains
              , mainOut = mainOut rCat
              , commands = commands rCat V.++ commands rRm
              , local = True
              }
{-# INLINE clean #-}



newRule :: Command -> Parameter -> Command
newRule c p = c {params = params c `V.snoc` p}


addRule :: Traversable t => Command -> t Parameter -> Hak Rule
addRule c ps = eval $ foldl' newRule c ps
