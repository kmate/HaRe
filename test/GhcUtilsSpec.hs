{-# LANGUAGE ScopedTypeVariables #-}
module GhcUtilsSpec (main, spec) where

import           Test.Hspec

import           TestUtils

import qualified GHC     as GHC

import qualified Data.Generics as SYB
import qualified GHC.SYB.Utils as SYB

import Language.Haskell.GHC.ExactPrint.Utils

import Language.Haskell.Refact.Utils.Binds
import Language.Haskell.Refact.Utils.GhcUtils
import Language.Haskell.Refact.Utils.GhcVersionSpecific
import Language.Haskell.Refact.Utils.Monad
import Language.Haskell.Refact.Utils.MonadFunctions
import Language.Haskell.Refact.Utils.TypeUtils
import Language.Haskell.Refact.Utils.Utils
import Language.Haskell.Refact.Utils.Variables

-- import TestUtils

-- ---------------------------------------------------------------------

main :: IO ()
main = do
  hspec spec

spec :: Spec
spec = do

  describe "onelayerStaged" $ do
    it "only descends one layer into a structure" $ do
      let s' = (2,[3,4],5) :: (Int,[Int],Int)
      let
          worker' (i::Int) = [i]

      let g = onelayerStaged SYB.Renamer [] ([] `SYB.mkQ` worker') s'
      let g1 = SYB.gmapQ ([] `SYB.mkQ` worker') s'
      let g2 = SYB.gmapQl (++) [] ([] `SYB.mkQ` worker') s'

      (show g) `shouldBe` "[[2],[],[5]]"
      (show g1) `shouldBe` "[[2],[],[5]]"
      (show g2) `shouldBe` "[2,5]"

    -- ---------------------------------

    it "Finds a GHC.Name at top level only" $ do
      let
        comp = do
         parseSourceFileGhc "./DupDef/Dd1.hs"
         renamed <- getRefactRenamed

         let mn = locToName (4,1) renamed
         let (Just (ln@(GHC.L _ n))) = mn

         let mx = locToName (4,10) renamed
         let (Just (lx@(GHC.L _ x))) = mx

         let declsr = hsBinds renamed
             duplicatedDecls = definingDeclsNames [n] declsr True False

             res = findEntity ln duplicatedDecls
             res2 = findEntity n duplicatedDecls

             resx = findEntity lx duplicatedDecls
             resx2 = findEntity x duplicatedDecls


             worker (nn::GHC.Name) = [showGhc nn]
             g = onelayerStaged SYB.Renamer ["-1"] (["-10"] `SYB.mkQ` worker) duplicatedDecls

             worker2 ((GHC.L _ (GHC.FunBind (GHC.L _ n') _ _ _ _ _))::GHC.Located (GHC.HsBind GHC.Name))
               | n == n' = ["found"]
             worker2 _ = []
             g2 = onelayerStaged SYB.Renamer ["-1"] (["-10"] `SYB.mkQ` worker2) duplicatedDecls

         return (res,res2,resx,resx2,duplicatedDecls,g,g2,ln,lx)
      ((r,r2,rx,rx2,d,gg,gg2,_l,_x),_s) <- ct $ runRefactGhc comp initialState testOptions
      -- (SYB.showData SYB.Renamer 0 d) `shouldBe` ""

      (showGhcQual d) `shouldBe` "[DupDef.Dd1.toplevel x = DupDef.Dd1.c GHC.Num.* x]"
      (showGhcQual _l) `shouldBe` "DupDef.Dd1.toplevel"
      (showGhc _x) `shouldBe` "x"
      (show gg) `shouldBe` "[[\"-10\"],[\"-10\"]]"
      (show gg2) `shouldBe` "[[\"found\"],[\"-10\"]]"
      r `shouldBe` True
      r2 `shouldBe` True
      rx `shouldBe` False
      rx2 `shouldBe` True

-- ---------------------------------------------------------------------
