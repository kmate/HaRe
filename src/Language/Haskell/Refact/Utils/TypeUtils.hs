{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoMonomorphismRestriction #-}

--------------------------------------------------------------------------------
-- Module      : TypeUtils

-- Maintainer  : refactor-fp\@kent.ac.uk
-- |
--
-- This module contains a collection of program analysis and
-- transformation functions (the API) that work over the Type
-- Decorated AST. Most of the functions defined in the module are
-- taken directly from the API, but in some cases are modified to work
-- with the type decorated AST.
--
-- In particular some new functions have been added to make type
-- decorated AST traversals easier.
--
-- In HaRe, in order to preserve the comments and layout of refactored
-- programs, a refactoring modifies not only the AST but also the
-- token stream, and the program source after the refactoring is
-- extracted from the token stream rather than the AST, for the
-- comments and layout information is kept in the token steam instead
-- of the AST. As a consequence, a program transformation function
-- from this API modifies both the AST and the token stream (unless
-- explicitly stated). So when you build your own program
-- transformations, try to use the API to do the transformation, as
-- this can liberate you from caring about the token stream.
--
-- This type decorated API is still in development. Any suggestions
-- and comments are very much welcome.


--------------------------------------------------------------------------------
module Language.Haskell.Refact.Utils.TypeUtils
       (
 -- * Program Analysis
    -- ** Imports and exports
   inScopeInfo, isInScopeAndUnqualified, isInScopeAndUnqualifiedGhc -- , hsQualifier, {-This function should be removed-} rmPrelude 
   {-,exportInfo -}, isExported, isExplicitlyExported, modIsExported

    -- ** Variable analysis
    ,hsPNs -- ,hsPNTs,hsDataConstrs,hsTypeConstrsAndClasses, hsTypeVbls
    {- ,hsClassMembers -} , HsBinds(..)
    ,getDecls, getDeclsP -- , replaceDecls
    ,hsFreeAndDeclaredPNs, hsFreeAndDeclaredNames
    ,hsVisiblePNs, hsVisibleNames
    ,hsFDsFromInside, hsFDNamesFromInside

    -- ** Property checking
    {- ,isVarId,isConId,isOperator -},isTopLevelPN,isLocalPN -- ,isTopLevelPNT
    ,isQualifiedPN {- ,isFunPNT, isFunName, isPatName-}, isFunOrPatName {-,isTypeCon-} ,isTypeSig
    ,isFunBindP,isFunBindR,isPatBindP,isPatBindR,isSimplePatBind
    ,isComplexPatBind,isFunOrPatBindP,isFunOrPatBindR -- ,isClassDecl,isInstDecl -- ,isDirectRecursiveDef
    ,usedWithoutQual,usedWithoutQualR {- ,canBeQualified, hasFreeVars -},isUsedInRhs
    ,findPNT,findPN
    ,findPNs, findEntity, findEntity'
    ,sameOccurrence
    ,defines, definesP,definesTypeSig -- , isTypeSigOf
    -- ,HasModName(hasModName), HasNameSpace(hasNameSpace)
    ,sameBind
    ,usedByRhs,UsedByRhs(..)

    -- ** Modules and files
    -- ,clientModsAndFiles,serverModsAndFiles,isAnExistingMod
    -- ,fileNameToModName, strToModName, modNameToStr

    -- ** Locations
    ,defineLoc, useLoc,locToPNT {-,locToPN -},locToExp -- , getStartEndLoc
    ,locToName
    ,getName

 -- * Program transformation
    -- ** Adding
    ,addDecl {- ,addItemsToImport -}, addHiding --, rmItemsFromImport, addItemsToExport
    ,addParamsToDecls {- , addGuardsToRhs, addImportDecl-}, duplicateDecl, moveDecl
    -- ** Removing
    ,rmDecl, rmTypeSig -- , commentOutTypeSig, rmParams
    -- ,rmItemsFromExport, rmSubEntsFromExport, Delete(delete)
    -- ** Updating
    -- ,Update(update)
    {- ,qualifyPName-},rmQualifier,renamePN -- ,replaceNameInPN,autoRenameLocalVar

-- * Miscellous
    -- ** Parsing, writing and showing
   {- ,parseSourceFile,writeRefactoredFiles-}, showEntities,showPNwithLoc -- , newProj, addFile, chase
    -- ** Locations
   -- ,toRelativeLocs, rmLocs
    -- ** Default values
   ,defaultPN,defaultPNT {-,defaultModName-},defaultExp-- ,defaultPat, defaultExpUnTyped


    -- ** Identifiers, expressions, patterns and declarations
    ,pNTtoPN -- ,pNTtoName,pNtoName,nameToPNT, nameToPN,pNtoPNT
    ,ghcToPN,lghcToPN
    {- ,expToPNT, expToPN, nameToExp,pNtoExp -},patToPNT {- , patToPN --, nameToPat -},pNtoPat
    ,definingDecls, definedPNs
    ,definingDeclsNames, definingSigsNames
    , allNames
    -- ,simplifyDecl

    -- ** Others
    -- , applyRefac, applyRefacToClientMods
    , mkRdrName,mkNewName,mkNewToplevelName

    -- The following functions are not in the the API yet.
    ,getDeclToks, causeNameClashInExports {- , inRegion , unmodified -}, prettyprint
    ,getDeclAndToks,getSigAndToks -- ++AZ++ Zipper?

-- * Typed AST traversals (added by CMB)
    -- * Miscellous
    -- ,removeFromInts, getDataName, checkTypes, getPNs, getPN, getPNPats, mapASTOverTAST

-- * Debug stuff
  , allPNT
  , allPNTLens
  , newNameTok
 ) where

import Exception
-- import Control.Exception
import Control.Monad.State
import Data.List
import Data.Maybe
import Language.Haskell.Refact.Utils.GhcUtils
import Language.Haskell.Refact.Utils.LocUtils
import Language.Haskell.Refact.Utils.Monad
import Language.Haskell.Refact.Utils.TypeSyn
import System.IO.Unsafe

-- Modules from GHC
import qualified Bag           as GHC
import qualified BasicTypes    as GHC
import qualified Coercion      as GHC
import qualified Digraph       as GHC
import qualified DynFlags      as GHC
import qualified ErrUtils      as GHC
import qualified FastString    as GHC
import qualified ForeignCall   as GHC
import qualified GHC           as GHC
import qualified GHC.Paths     as GHC
import qualified HsDecls       as GHC
import qualified HsImpExp      as GHC
import qualified HsPat         as GHC
import qualified HsSyn         as GHC
import qualified InstEnv       as GHC
import qualified Lexer         as GHC
import qualified Module        as GHC
import qualified MonadUtils    as GHC
import qualified Name          as GHC
import qualified NameSet       as GHC
import qualified OccName       as GHC
import qualified Outputable    as GHC
import qualified RdrName       as GHC
import qualified SrcLoc        as GHC
import qualified TcEvidence    as GHC
import qualified TcType        as GHC
import qualified TypeRep       as GHC
import qualified Unique        as GHC
import qualified Var           as GHC

import qualified Data.Generics as SYB
import qualified GHC.SYB.Utils as SYB
import qualified Unsafe.Coerce as SYB

-- Lens
import Control.Applicative
import Control.Lens hiding (Rep)
import Control.Lens.Plated
import Control.Lens.Traversal
import Control.Lens.Traversal
import Data.Data.Lens hiding (tinplate)
import GHC.Generics hiding (from, to)
import GHC.Generics.Lens

-- ---------------------------------------------------------------------
-- |Process the inscope relation returned from the parsing and module
-- analysis pass, and return a list of four-element tuples. Each tuple
-- contains an identifier name, the identifier's namespace info, the
-- identifier's defining module name and its qualifier name.
--
-- The same identifier may have multiple entries in the result because
-- it may have different qualifiers. This makes it easier to decide
-- whether the identifier can be used unqualifiedly by just checking
-- whether there is an entry for it with the qualifier field being
-- Nothing.
--
inScopeInfo :: InScopes                                          -- ^ The inscope relation .
           ->[(String, GHC.NameSpace, GHC.ModuleName, Maybe GHC.ModuleName)] -- ^ The result
inScopeInfo names = nub $  map getEntInfo $ names
  where
     getEntInfo name
       =(GHC.showPpr name,
         GHC.occNameSpace $ GHC.nameOccName name,
         GHC.moduleName $ GHC.nameModule name,
         getQualMaybe $ GHC.nameRdrName name)

     getQualMaybe rdrName = case rdrName of
       GHC.Qual modName _occName -> Just modName
       _                         -> Nothing

     -- getEntInfo (qual, ent@(Ent modName ident _))
     --   =(identToName ident, hasNameSpace ent,  modName, getQualifier qual)

{-
-- | Process the export relation returned from the parsing and module analysis pass, and
--   return a list of trhee-element tuples. Each tuple contains an identifier name, the
--   identifier's namespace info, and the identifier's define module.
exportInfo::Exports                             -- ^ The export relation.
          -> [(String, NameSpace, ModuleName)]  -- ^ The result
exportInfo exports = nub $ map getEntInfo  exports
  where
    getEntInfo (_, ent@(Ent modName ident _))
      =(identToName ident, hasNameSpace ent,  modName)
-}

-- | Return True if the identifier is inscope and can be used without
-- a qualifier.
isInScopeAndUnqualified::String       -- ^ The identifier name.
                       ->InScopes     -- ^ The inscope relation
                       ->Bool         -- ^ The result.
isInScopeAndUnqualified n names
 = isJust $ find (\ (x, _,_, qual) -> x == n && isNothing qual ) $ inScopeInfo names

-- isInScopeAndUnqualified id inScopeRel
--  = isJust $ find (\ (x, _,_, qual) -> x == id && isNothing qual ) $ inScopeInfo inScopeRel

-- | Return True if the identifier is inscope and can be used without
-- a qualifier. The identifier name string may have a qualifier already
isInScopeAndUnqualifiedGhc :: String         -- ^ The identifier name.
                           -> RefactGhc Bool -- ^ The result.
isInScopeAndUnqualifiedGhc n = do
  names <- ghandle handler (GHC.parseName n)
  nameInfo <- mapM GHC.lookupName names
  let nameList = filter isId $ catMaybes nameInfo
  return $ nameList /= []

  where
    isId (GHC.AnId _) = True
    isId _            = False

    -- handler:: (Exception e,GHC.GhcMonad m) => e -> m [GHC.Name]
    handler:: (GHC.GhcMonad m) => SomeException -> m [GHC.Name]
    handler _ = return []

-- ---------------------------------------------------------------------

-- | Show a PName in a format like: 'pn'(at row:r, col: c).
showPNwithLoc::GHC.Located GHC.Name->String
showPNwithLoc pn@(GHC.L l n)
  = let (r,c) = getGhcLoc l
    -- in  " '"++pNtoName pn++"'" ++"(at row:"++show r ++ ",col:" ++ show c ++")"
    in  " '"++GHC.showPpr pn++"'" ++"(at row:"++show r ++ ",col:" ++ show c ++")"

-- ---------------------------------------------------------------------

-- | Default identifier in the PNT format.
-- defaultPNT:: GHC.GenLocated GHC.SrcSpan GHC.RdrName   -- GHC.RdrName
defaultPNT:: PNT
-- defaultPNT = PNT defaultPN Value (N Nothing) :: PNT
-- defaultPNT = GHC.mkRdrUnqual "nothing" :: PNT
-- defaultPNT = PNT (mkRdrName "nothing") (N Nothing) :: PNT
defaultPNT = PNT (GHC.L GHC.noSrcSpan (mkRdrName "nothing"))

defaultPN :: PName
defaultPN = PN (mkRdrName "nothing")

-- | Default expression.
defaultExp::HsExpP
-- defaultExp=Exp (HsId (HsVar defaultPNT))
defaultExp=GHC.HsVar $ mkRdrName "nothing"

mkRdrName s = GHC.mkVarUnqual (GHC.mkFastString s)

-- | Make a new GHC.Name, using the Unique Int sequence stored in the
-- RefactState
mkNewName :: String -> RefactGhc GHC.Name
mkNewName name = do
  s <- get
  u <- gets rsUniqState
  put s { rsUniqState = (u+1) }

  let un = GHC.mkUnique 'H' (u+1) -- H for HaRe :)
      -- n = GHC.mkSystemName un (GHC.mkVarOcc name)
      n = GHC.localiseName $ GHC.mkSystemName un (GHC.mkVarOcc name)

  return n

mkNewToplevelName :: GHC.Module -> String -> GHC.SrcSpan -> RefactGhc GHC.Name
mkNewToplevelName modid name defLoc = do
  s <- get
  u <- gets rsUniqState
  put s { rsUniqState = (u+1) }

  let un = GHC.mkUnique 'H' (u+1) -- H for HaRe :)
      -- n = GHC.mkSystemName un (GHC.mkVarOcc name)
      -- n = GHC.localiseName $ GHC.mkSystemName un (GHC.mkVarOcc name)

        -- mkExternalName :: Unique -> Module -> OccName -> SrcSpan -> Name
      n = GHC.mkExternalName un modid (GHC.mkVarOcc name) defLoc
  return n

-- ---------------------------------------------------------------------

-- | Return True if the current module is exported either by default
-- or by specifying the module name in the export.
modIsExported::HsModuleP   -- ^ The AST of the module
               -> Bool     -- ^ The result
modIsExported (GHC.L _ mod)
   = let exps    = GHC.hsmodExports mod
         modName = GHC.hsmodName mod

         matchModName :: GHC.Located (GHC.IE GHC.RdrName) -> Bool
         matchModName (GHC.L _ n@(GHC.IEVar _)) =
           case modName of
             Nothing -> False
             Just (GHC.L _ mn) -> (GHC.moduleNameString mn) == GHC.showRdrName (GHC.ieName n)
         matchModName (GHC.L _ (GHC.IEModuleContents mne)) =
           case modName of
             Nothing -> False
             Just (GHC.L _ mn) -> (GHC.moduleNameString mn) == (GHC.moduleNameString mne)
         matchModName _ = False

     in if isNothing exps
           then True
           else isJust $ find matchModName (gfromJust "modIsExported" exps)

{- ++AZ++ original
-- | Return True if the current module is exported either by default or by specifying the module name in the export.
modIsExported::HsModuleP  -- ^ The AST of the module
               ->Bool     -- ^ The result
modIsExported mod
   = let exps    = hsModExports mod
         modName = hsModName mod
     in if isNothing exps
           then True
           else isJust $ find (==(ModuleE modName)) (fromJust exps)
-}

-- ---------------------------------------------------------------------

isExported = error "isExported undefined"
{- ++AZ++ original
-- | Return True if the identifier is exported either implicitly or explicitly.
isExported::PNT         -- ^ The identifier.
           ->Exports    -- ^ The export relation.
           ->Bool       -- ^ The result.
isExported pnt@(PNT pn t1 _) exps
   = if isTopLevelPNT pnt
       then case hasModName pn of
               Just modName  -> isJust (find (\(name, nameSpace, modName1) -> name == pNtoName pn
                                         && modName == modName1 && hasNameSpace pnt == nameSpace) $ exportInfo exps)  
               Nothing       -> False
       else False
-}

-- ---------------------------------------------------------------------

-- | Return True if an identifier is explicitly exported by the module.
isExplicitlyExported::GHC.Name           -- ^ The identifier
                     ->GHC.RenamedSource -- ^ The AST of the module
                     ->Bool              -- ^ The result
isExplicitlyExported pn (_g,_imps,exps,_docs)
  = findEntity pn exps

-- ---------------------------------------------------------------------

-- | ++AZ++ What does this actually do?
causeNameClashInExports::GHC.Name      -- ^ The original name??
                        -- -> String      -- ^ The identifier name
                        -> GHC.ModuleName     -- ^ The identity of the module
                        -> GHC.RenamedSource  -- ^ The AST of the module
                        ->Bool       -- ^ The result

-- Note that in the abstract representation of exps, there is no qualified entities.
causeNameClashInExports  pn {- newName -} modName mod@(_g,imps,maybeExps,_doc) -- exps
  -- = error "causeNameClashInExports undefined"

  = let exps = fromMaybe [] maybeExps
        varExps = filter isImpVar exps
        modNames=nub (concatMap (\(GHC.L _ (GHC.IEVar x))->if GHC.showPpr x== GHC.showPpr pn
                                                        then [GHC.moduleName $ GHC.nameModule x]
                                                        else []) varExps)
    in (isExplicitlyExported pn mod) &&
        ( any (modIsUnQualifedImported mod) modNames
            || elem modName modNames)
 where
    isImpVar (GHC.L _ x) = case x of
      GHC.IEVar _ -> True
      _           -> False

    modIsUnQualifedImported mod modName
     =let -- imps =hsModImports mod
       -- imp@(GHC.L _ (GHC.ImportDecl (GHC.L _ modName) qualify _source _safe isQualified _isImplicit as h))
      in isJust $ find (\(GHC.L _ (GHC.ImportDecl (GHC.L _ modName1) qualify _source _safe isQualified _isImplicit as h)) 
                                -> modName1 == modName && (not isQualified)) imps
      -- in isJust $ find (\(HsImportDecl _ (SN modName1 _) qualify  _ h) -> modName == modName1 && (not qualify)) imps


{- ++AZ++ Original
causeNameClashInExports::String      -- ^ The identifier name
                        ->HsModuleP  -- ^ The AST of the module
                        ->Exports    -- ^ The export relation of the module
                        ->Bool       -- ^ The result


-- Note that in the abstract representation of exps, there is no qualified entities.
causeNameClashInExports  pn newName mod exps
  = let modNames=nub (concatMap (\(x, Ent modName _ _)->if show x==show newName
                                                        then [modName]
                                                        else []) exps)
    in (isExplicitlyExported pn mod) &&
        ( any (modIsUnQualifedImported mod) modNames
            || elem (let (SN modName1 _) =hsModName mod
                     in modName1)  modNames)
 where
    modIsUnQualifedImported mod modName
     =let imps =hsModImports mod
      in isJust $ find (\(HsImportDecl _ (SN modName1 _) qualify  _ h)->modName==modName1 && (not qualify)) imps

-}

-- ---------------------------------------------------------------------
-- | Collect the free and declared variables (in the GHC.Name format)
-- in a given syntax phrase t. In the result, the first list contains
-- the free variables, and the second list contains the declared
-- variables.
-- Expects RenamedSource

hsFreeAndDeclaredPNs:: (SYB.Data t) => t -> ([GHC.Name],[GHC.Name])
hsFreeAndDeclaredPNs t = (nub f, nub d)
   where
          (f,d) = hsFreeAndDeclared'

          hsFreeAndDeclared' :: ([GHC.Name],[GHC.Name])

          hsFreeAndDeclared' = SYB.everythingStaged SYB.Renamer
                             (\(f1,d1) (f2,d2) -> (f1++f2,d1++d2))
                             ([],[])
                             (([],[]) `SYB.mkQ` expr
                             `SYB.extQ` pattern
                             `SYB.extQ` match
                             `SYB.extQ` stmts) t


          -- TODO: ++AZ++ Note:After renaming, HsBindLR has field bind_fvs
          --       containing locally bound free vars

          -- expr --
          expr (GHC.HsVar n) = ([n],[])

          expr (GHC.OpApp e1 (GHC.L _ (GHC.HsVar n)) _ e2)
              = addFree n (hsFreeAndDeclaredPNs [e1,e2])

          expr ((GHC.HsLam (GHC.MatchGroup matches _)) :: GHC.HsExpr GHC.Name) =
             hsFreeAndDeclaredPNs matches

          expr ((GHC.HsLet decls e) :: GHC.HsExpr GHC.Name) =
            let
              (df,dd) = hsFreeAndDeclaredPNs decls
              (ef,_)  = hsFreeAndDeclaredPNs e
            in
              ((df `union` (ef \\ dd)),[])

          expr (GHC.RecordCon (GHC.L _ n) _ e) =
            addFree  n (hsFreeAndDeclaredPNs e)   --Need Testing

          expr (GHC.EAsPat (GHC.L _ n) e) =
            addFree  n (hsFreeAndDeclaredPNs e)

          expr _ = ([],[])

          -- pat --
          pattern (GHC.VarPat n) = ([],[n])
          -- It seems all the GHC pattern match syntax elements end up
          -- with GHC.VarPat

          pattern _ = ([],[])

          -- match and patBind, same type--
          match ((GHC.FunBind (GHC.L _ n) _ (GHC.MatchGroup matches _) _ _ _) :: GHC.HsBind GHC.Name) =
           let
             (pf,_pd) = hsFreeAndDeclaredPNs matches
           in
             -- ((pf `union` ((rf `union` df) \\ (dd `union` pd `union` [fun]))),[fun])
             (pf,[n])

          -- patBind --
          match (GHC.PatBind pat rhs _ _ _) =
            let
              (pf,pd)  = hsFreeAndDeclaredPNs pat
              (rf,_rd) = hsFreeAndDeclaredPNs rhs
            in
              (pf `union` (rf \\pd),pd)

          match _ = ([],[])


          -- stmts --
          stmts ((GHC.BindStmt pat expr bind fail) :: GHC.Stmt GHC.Name) =
            let
              (pf,pd) = hsFreeAndDeclaredPNs pat
              (ef,ed) = hsFreeAndDeclaredPNs expr
              (sf,sd) = hsFreeAndDeclaredPNs [bind,fail]
            in
              (pf `union` ef `union` (sf\\pd),[]) -- pd) -- Check this

          stmts ((GHC.LetStmt binds) :: GHC.Stmt GHC.Name) =
            hsFreeAndDeclaredPNs binds

          stmts _ = ([],[])

{-
          recDecl ((HsRecDecl _ _ _ _ is) :: HsConDeclI PNT (HsTypeI PNT) [HsTypeI PNT])
                =do let d=map pNTtoPN $ concatMap fst is
                    return ([],d)
          recDecl _ =mzero
-}

          addFree :: GHC.Name -> ([GHC.Name],[GHC.Name]) -> ([GHC.Name],[GHC.Name]) 
          addFree free (f,d) = ([free] `union` f, d)

{-
hsFreeAndDeclaredPNs:: (Term t, MonadPlus m)=> t-> m ([PName],[PName])
hsFreeAndDeclaredPNs t=do (f,d)<-hsFreeAndDeclared' t
                          return (nub f, nub d)
   where
          hsFreeAndDeclared'=applyTU (stop_tdTU (failTU  `adhocTU` exp
                                                         `adhocTU` pat
                                                         `adhocTU` match
                                                         `adhocTU` patBind
                                                         `adhocTU` alt
                                                         `adhocTU` decls
                                                         `adhocTU` stmts
                                                         `adhocTU` recDecl))

          exp (TiDecorate.Exp (HsId (HsVar (PNT pn _ _))))=return ([pn],[])
          exp (TiDecorate.Exp (HsId (HsCon (PNT pn _ _))))=return ([pn],[])
          exp (TiDecorate.Exp (HsInfixApp e1 (HsVar (PNT pn _ _)) e2))
              =addFree pn (hsFreeAndDeclaredPNs [e1,e2])
          exp (TiDecorate.Exp (HsLambda pats body))
              = do (pf,pd) <-hsFreeAndDeclaredPNs pats
                   (bf,_) <-hsFreeAndDeclaredPNs body
                   return ((bf `union` pf) \\ pd, [])
          exp (TiDecorate.Exp (HsLet decls exp))
              = do (df,dd)<- hsFreeAndDeclaredPNs decls
                   (ef,_)<- hsFreeAndDeclaredPNs exp
                   return ((df `union` (ef \\ dd)),[])
          exp (TiDecorate.Exp (HsRecConstr _  (PNT pn _ _) e))
               =addFree  pn  (hsFreeAndDeclaredPNs e)   --Need Testing
          exp (TiDecorate.Exp (HsAsPat (PNT pn _ _) e))
              =addFree  pn  (hsFreeAndDeclaredPNs e)
          exp _ = mzero


          pat (TiDecorate.Pat (HsPId (HsVar (PNT pn _ _))))=return ([],[pn])
          pat (TiDecorate.Pat (HsPInfixApp p1 (PNT pn _ _) p2))=addFree pn (hsFreeAndDeclaredPNs [p1,p2])
          pat (TiDecorate.Pat (HsPApp (PNT pn _ _) pats))=addFree pn (hsFreeAndDeclaredPNs pats)
          pat (TiDecorate.Pat (HsPRec (PNT pn _ _) fields))=addFree pn (hsFreeAndDeclaredPNs fields)
          pat _ =mzero


          match ((HsMatch _ (PNT fun _ _)  pats rhs  decls)::HsMatchP)
            = do (pf,pd) <- hsFreeAndDeclaredPNs pats
                 (rf,rd) <- hsFreeAndDeclaredPNs rhs
                 (df,dd) <- hsFreeAndDeclaredPNs decls
                 return ((pf `union` ((rf `union` df) \\ (dd `union` pd `union` [fun]))),[fun])

         -------Added by Huiqing Li-------------------------------------------------------------------

          patBind ((TiDecorate.Dec (HsPatBind _ pat (HsBody rhs) decls))::HsDeclP)
             =do (pf,pd) <- hsFreeAndDeclaredPNs pat
                 (rf,rd) <- hsFreeAndDeclaredPNs rhs
                 (df,dd) <- hsFreeAndDeclaredPNs decls
                 return (pf `union` ((rf `union` df) \\(dd `union` pd)),pd)
          patBind _=mzero
         ------------------------------------------------------------------------------------------- 

          alt ((HsAlt _ pat exp decls)::(HsAlt (HsExpP) (HsPatP) HsDeclsP))
             = do (pf,pd) <- hsFreeAndDeclaredPNs pat
                  (ef,ed) <- hsFreeAndDeclaredPNs exp
                  (df,dd) <- hsFreeAndDeclaredPNs decls
                  return (pf `union` (((ef \\ dd) `union` df) \\ pd),[])


          decls (ds :: [HsDeclP])
             =do (f,d) <-hsFreeAndDeclaredList ds
                 return (f\\d,d)

          stmts ((HsGenerator _ pat exp stmts) :: HsStmt (HsExpP) (HsPatP) HsDeclsP) -- Claus
             =do (pf,pd) <-hsFreeAndDeclaredPNs pat
                 (ef,ed) <-hsFreeAndDeclaredPNs exp
                 (sf,sd) <-hsFreeAndDeclaredPNs stmts
                 return (pf `union` ef `union` (sf\\pd),[]) -- pd) -- Check this 

          stmts ((HsLetStmt decls stmts) :: HsStmt (HsExpP) (HsPatP) HsDeclsP)
             =do (df,dd) <-hsFreeAndDeclaredPNs decls
                 (sf,sd) <-hsFreeAndDeclaredPNs stmts
                 return (df `union` (sf \\dd),[])
          stmts _ =mzero

          recDecl ((HsRecDecl _ _ _ _ is) :: HsConDeclI PNT (HsTypeI PNT) [HsTypeI PNT])
                =do let d=map pNTtoPN $ concatMap fst is
                    return ([],d)
          recDecl _ =mzero


          addFree free mfd=do (f,d)<-mfd
                              return ([free] `union` f, d)

          hsFreeAndDeclaredList l=do fds<-mapM hsFreeAndDeclaredPNs l
                                     return (foldr union [] (map fst fds),
                                             foldr union [] (map snd fds))
-}



-- |The same as `hsFreeAndDeclaredPNs` except that the returned
-- variables are in the String format.
hsFreeAndDeclaredNames::(SYB.Data t) => t -> ([String],[String])
hsFreeAndDeclaredNames t = ((nub.map GHC.showPpr) f1, (nub.map GHC.showPpr) d1)
  where
    (f1,d1) = hsFreeAndDeclaredPNs t

-- hsFreeAndDeclaredNames::(Term t, MonadPlus m)=> t->m([String],[String])
-- hsFreeAndDeclaredNames t =do (f1,d1)<-hsFreeAndDeclaredPNs t
--                              return ((nub.map pNtoName) f1, (nub.map pNtoName) d1)


--------------------------------------------------------------------------------
-- | Same as `hsVisiblePNs' except that the returned identifiers are
-- in String format.
hsVisibleNames:: (FindEntity t1, SYB.Data t1, SYB.Data t2) => t1 -> t2 -> [String]
hsVisibleNames e t = ((nub.map GHC.showPpr) d)
  where
    d = hsVisiblePNs e t

-- hsVisibleNames:: (Term t1, Term t2, FindEntity t1, MonadPlus m) => t1 -> t2 -> m [String]
-- hsVisibleNames e t =do d<-hsVisiblePNs e t
--                        return ((nub.map pNtoName) d)


-- | Given syntax phrases e and t, if e occurs in t, then return those
-- variables which are declared in t and accessible to e, otherwise
-- return [].
hsVisiblePNs :: (FindEntity e1, SYB.Data e1, SYB.Data t1) =>
   e1 -> t1 -> [GHC.Name]
hsVisiblePNs e t = nub $ SYB.everythingStaged SYB.Renamer (++) []
                  ([] `SYB.mkQ`  top
                      `SYB.extQ` expr
                      `SYB.extQ` decl
                      `SYB.extQ` match
                      `SYB.extQ` stmts) t

      where
          top ((groups,_,_,_) :: GHC.RenamedSource)
            -- | findEntity e groups = dd -- ++AZ++:TODO: Should be GHC.HsBinds GHC.Name, not groups
            | findEntity e (GHC.hs_valds groups) = dd -- ++AZ++:TODO: Should be GHC.HsBinds GHC.Name, not groups
           where
             (_df,dd) = hsFreeAndDeclaredPNs (GHC.hs_valds groups)
          top _ = []

          {- ++AZ++ included in (GHC.Match ...) below
          expr ((GHC.HsLam (GHC.MatchGroup matches _)) :: GHC.HsExpr GHC.Name)
            | findEntity e matches = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs matches
          ++AZ++ end -}

          expr ((GHC.HsLet decls e1) :: GHC.HsExpr GHC.Name)
             |findEntity e e1 || findEntity e decls = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs decls

          {- ++AZ++ included in (GHC.Match ...) below
          -- This is the equivalent of HsAlt
          expr ((GHC.HsCase _ (GHC.MatchGroup matches _)) :: GHC.HsExpr GHC.Name)
            | findEntity e matches = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs matches
          ++AZ++ end -}

          expr _ = []

          {- ++AZ++ included in (GHC.Match ...) below
          decl ((GHC.FunBind _ _ (GHC.MatchGroup matches _) _ _ _) :: GHC.HsBind GHC.Name) 
            | findEntity e matches = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs matches
          ++AZ++ end -}

          decl ((GHC.PatBind pat rhs _ _ _) :: GHC.HsBind GHC.Name)
            |findEntity e rhs = (pd `union` dd)
           where
             (_pf,pd) = hsFreeAndDeclaredPNs pat
             (_df,dd) = hsFreeAndDeclaredPNs rhs

          decl _ = []

          -- Pick up from HsAlt etc
          match ((GHC.Match pats _ rhs) :: GHC.Match GHC.Name)
            |findEntity e rhs = (pd `union` dd)
           where
             (_pf,pd) = hsFreeAndDeclaredPNs pats
             (_df,dd) = hsFreeAndDeclaredPNs rhs
          match _ = []

          stmts ((GHC.LetStmt binds) :: GHC.Stmt GHC.Name)
            | findEntity e binds = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs binds

          stmts ((GHC.BindStmt pat rhs _ _) :: GHC.Stmt GHC.Name)
            | findEntity e rhs = dd
           where
             (_df,dd) = hsFreeAndDeclaredPNs pat

          stmts _ = []

{- ++ original ++
-- | Given syntax phrases e and t, if e occurs in  t, then return those vairables
--  which are declared in t and accessible to e, otherwise return [].
hsVisiblePNs :: (Term t1, Term t2, FindEntity t1, MonadPlus m) => t1 -> t2 -> m [PName]
hsVisiblePNs e t =applyTU (full_tdTU (constTU [] `adhocTU` mod
                                                  `adhocTU` exp
                                                  `adhocTU` match
                                                  `adhocTU` patBind
                                                  `adhocTU` alt
                                                  `adhocTU` stmts)) t
      where
          mod ((HsModule loc modName exps imps decls)::HsModuleP)
            |findEntity e decls
           =do (df,dd)<-hsFreeAndDeclaredPNs decls
               return dd
          mod _=return []

          exp ((Exp (HsLambda pats body))::HsExpP)
            |findEntity e body
             = do (pf,pd) <-hsFreeAndDeclaredPNs pats
                  return pd

          exp (Exp (HsLet decls e1))
             |findEntity e e1 || findEntity e decls
             = do (df,dd)<- hsFreeAndDeclaredPNs decls
                  return dd
          exp _ =return []

          match (m@(HsMatch _ (PNT fun _ _)  pats rhs  decls)::HsMatchP)
            |findEntity e rhs || findEntity e decls
            = do (pf,pd) <- hsFreeAndDeclaredPNs pats
                 (df,dd) <- hsFreeAndDeclaredPNs decls
                 return  (pd `union` dd `union` [fun])
          match _=return []

          patBind (p@(Dec (HsPatBind _ pat rhs decls))::HsDeclP)
            |findEntity e rhs || findEntity e decls
             =do (pf,pd) <- hsFreeAndDeclaredPNs pat
                 (df,dd) <- hsFreeAndDeclaredPNs decls
                 return (pd `union` dd)
          patBind _=return []

          alt ((HsAlt _ pat exp decls)::HsAltP)
             |findEntity e exp || findEntity e decls
             = do (pf,pd) <- hsFreeAndDeclaredPNs pat
                  (df,dd) <- hsFreeAndDeclaredPNs decls
                  return (pd `union` dd)
          alt _=return []

          stmts ((HsGenerator _ pat exp stmts) :: HsStmtP)
            |findEntity e stmts
             =do (pf,pd) <-hsFreeAndDeclaredPNs pat
                 return pd

          stmts (HsLetStmt decls stmts)
            |findEntity e decls || findEntity e stmts
             =do (df,dd) <-hsFreeAndDeclaredPNs decls
                 return dd
          stmts _ =return []

-}

------------------------------------------------------------------------

-- | Return True if the identifier is unqualifiedly used in the given
-- syntax phrase.

usedWithoutQual :: GHC.Name -> GHC.RenamedSource -> RefactGhc Bool
usedWithoutQual name renamed = do
  case res of
     Just (GHC.L l _) -> do
       liftIO $ putStrLn ("usedWithoutQual") -- ++AZ++ debug
       toks <- fetchToks

       let (_,s) = ghead "usedWithoutQual"  $ getToks (getGhcLoc l, getGhcLocEnd l) toks
       return $ not $ elem '.' s
     Nothing -> return False
  where
     res = somethingStaged SYB.Renamer Nothing
            (Nothing `SYB.mkQ` worker
            `SYB.extQ` workerBind
            `SYB.extQ` workerExpr
            ) renamed

     worker  (pname :: GHC.Located GHC.Name) =
       checkName pname

     workerBind (GHC.L l (GHC.VarPat n) :: (GHC.Located (GHC.Pat GHC.Name))) =
       checkName (GHC.L l n)
     workerBind _ = Nothing

     workerExpr ((GHC.L l (GHC.HsVar n)) :: (GHC.Located (GHC.HsExpr GHC.Name)))
       = checkName (GHC.L l n)
     workerExpr _ = Nothing

     -- ----------------

     checkName (pname@(GHC.L _l pn)::GHC.Located GHC.Name)
        | ((GHC.nameUnique pn) == (GHC.nameUnique name)) &&
          isUsedInRhs pname renamed = Just pname
     checkName _ = Nothing

-- | Return True if the identifier is unqualifiedly used in the given
-- syntax phrase.
usedWithoutQualR :: GHC.Name -> GHC.ParsedSource -> Bool
usedWithoutQualR name parsed = fromMaybe False res
  where
     res = somethingStaged SYB.Parser Nothing
            (Nothing `SYB.mkQ` worker
            `SYB.extQ` workerBind
            `SYB.extQ` workerExpr
            ) parsed

     worker  (pname :: GHC.Located GHC.RdrName) =
       checkName pname

     workerBind (GHC.L l (GHC.VarPat n) :: (GHC.Located (GHC.Pat GHC.RdrName))) =
       checkName (GHC.L l n)
     workerBind _ = Nothing

     workerExpr ((GHC.L l (GHC.HsVar n)) :: (GHC.Located (GHC.HsExpr GHC.RdrName)))
       = checkName (GHC.L l n)
     workerExpr _ = Nothing

     -- ----------------

     checkName (pname@(GHC.L l pn)::GHC.Located GHC.RdrName)
        -- | ((GHC.nameUnique pn) == (GHC.nameUnique name)) &&
        | ((GHC.rdrNameOcc pn) == (GHC.nameOccName name)) &&
          -- isUsedInRhs pname parsed &&
          isUsedInRhs (GHC.L l name) parsed &&
          GHC.isUnqual pn     = Just True
     checkName _ = Nothing

   {-
   =(fromMaybe False) (applyTU (once_tdTU (failTU `adhocTU` worker)) t)
      where
         worker (pnt::PNT)
           |pNTtoName pnt ==name && isUsedInRhs pnt t && not (isQualifiedPN (pNTtoPN pnt)) 
          = Just True
         worker _ =Nothing
    -}

-- ---------------------------------------------------------------------


-- |`hsFDsFromInside` is different from `hsFreeAndDeclaredPNs` in
-- that: given an syntax phrase t, `hsFDsFromInside` returns not only
-- the declared variables that are visible from outside of t, but also
-- those declared variables that are visible to the main expression
-- inside t.
-- NOTE: Expects to be given RenamedSource

hsFDsFromInside:: (SYB.Data t) => t-> ([GHC.Name],[GHC.Name])
hsFDsFromInside t = (nub f, nub d)
   where
     (f,d) = hsFDsFromInside'
     {-
     hsFDsFromInside' = applyTU (once_tdTU (failTU  `adhocTU` mod
                                                    -- `adhocTU` decls
                                                     `adhocTU` decl
                                                     `adhocTU` match
                                                     `adhocTU` exp
                                                     `adhocTU` alt
                                                     `adhocTU` stmts ))
     -}
     hsFDsFromInside' :: ([GHC.Name],[GHC.Name])
     hsFDsFromInside' = SYB.everythingStaged SYB.Renamer
                  (\(f1,d1) (f2,d2) -> (f1++f2,d1++d2))
                  ([],[])
                  (([],[]) `SYB.mkQ` renamed
                           `SYB.extQ` match
                           `SYB.extQ` decl
                           `SYB.extQ` expr
                           `SYB.extQ` stmts) t

     renamed ((group,_,_,_)::GHC.RenamedSource)
        = hsFreeAndDeclaredPNs $ GHC.hs_valds group

 {-    decls (ds::[HsDeclP])                    --CHECK THIS.
       = hsFreeAndDeclaredPNs decls
-}
     -- Match [LPat id] (Maybe (LHsType id)) (GRHSs id)
     match ((GHC.Match pats _type rhs):: GHC.Match GHC.Name ) =
       let
         (pf, pd) = hsFreeAndDeclaredPNs pats
         (rf, rd) = hsFreeAndDeclaredPNs rhs
       in
         (nub (pf `union` (rf \\ pd)),
          nub (pd `union` rd))


     decl ((GHC.FunBind (GHC.L _ n) _ (GHC.MatchGroup matches _) _ _ _) :: GHC.HsBind GHC.Name) =
       let
         fds = map hsFDsFromInside matches
       in
         (nub (concatMap fst fds), nub(concatMap snd fds))

     decl ((GHC.PatBind p rhs _ _ _) :: GHC.HsBind GHC.Name) =
       let
         (pf, pd) = hsFreeAndDeclaredPNs p
         (rf, rd) = hsFreeAndDeclaredPNs rhs
       in
         (nub (pf `union` (rf \\ pd)),
          nub (pd `union` rd))

     decl ((GHC.VarBind p rhs _) :: GHC.HsBind GHC.Name) =
       let
         (pf, pd) = hsFreeAndDeclaredPNs p
         (rf, rd) = hsFreeAndDeclaredPNs rhs
       in
         (nub (pf `union` (rf \\ pd)),
          nub (pd `union` rd))

     expr ((GHC.HsLet decls e) :: GHC.HsExpr GHC.Name) =
       let
         (df,dd) = hsFreeAndDeclaredPNs decls
         (ef,_)  = hsFreeAndDeclaredPNs e
       in
         (nub (df `union` (ef \\ dd)), nub dd)

     expr ((GHC.HsLam (GHC.MatchGroup matches _)) :: GHC.HsExpr GHC.Name) =
       hsFreeAndDeclaredPNs matches

     expr ((GHC.HsCase e (GHC.MatchGroup matches _)) :: GHC.HsExpr GHC.Name) =
       let
         (ef,_)  = hsFreeAndDeclaredPNs e
         (df,dd) = hsFreeAndDeclaredPNs matches
       in
         (nub (df `union` (ef \\ dd)), nub dd)

     expr _ = ([],[])

     stmts ((GHC.BindStmt pat e1 e2 e3) :: GHC.Stmt GHC.Name) =
       let
         (pf,pd)  = hsFreeAndDeclaredPNs pat
         (ef,_ed) = hsFreeAndDeclaredPNs e1
         (df,dd)  = hsFreeAndDeclaredPNs [e2,e3]
       in
         (nub (pf `union` (((ef \\ dd) `union` df) \\ pd)), nub (pd `union` dd))

     stmts ((GHC.LetStmt binds) :: GHC.Stmt GHC.Name) =
       hsFreeAndDeclaredPNs binds

     stmts _ = ([],[])

-- -----

{-
hsFDsFromInside:: (Term t, MonadPlus m)=> t-> m ([PName],[PName])
hsFDsFromInside t = do (f,d)<-hsFDsFromInside' t
                       return (nub f, nub d)
   where
     hsFDsFromInside' = applyTU (once_tdTU (failTU  `adhocTU` mod
                                                    -- `adhocTU` decls
                                                     `adhocTU` decl
                                                     `adhocTU` match
                                                     `adhocTU` exp
                                                     `adhocTU` alt
                                                     `adhocTU` stmts ))


     mod ((HsModule loc modName exps imps ds)::HsModuleP)
        = hsFreeAndDeclaredPNs ds

 {-    decls (ds::[HsDeclP])                    --CHECK THIS.
       = hsFreeAndDeclaredPNs decls
-}
     match ((HsMatch loc1 (PNT fun _ _) pats rhs ds) ::HsMatchP)
       = do (pf, pd) <-hsFreeAndDeclaredPNs pats
            (rf, rd) <-hsFreeAndDeclaredPNs rhs
            (df, dd) <-hsFreeAndDeclaredPNs ds
            return (nub (pf `union` ((rf `union` df) \\ (dd `union` pd `union` [fun]))), 
                    nub (pd `union` rd `union` dd `union` [fun]))

     decl ((TiDecorate.Dec (HsPatBind loc p rhs ds))::HsDeclP)
      = do (pf, pd)<-hsFreeAndDeclaredPNs p
           (rf, rd)<-hsFreeAndDeclaredPNs rhs
           (df, dd)<-hsFreeAndDeclaredPNs ds
           return (nub (pf `union` ((rf `union` df) \\ (dd `union` pd))),
                   nub ((pd `union` rd `union` dd)))

     decl (TiDecorate.Dec (HsFunBind loc matches))
         =do fds <-mapM hsFDsFromInside matches
             return (nub (concatMap fst fds), nub(concatMap snd fds))

     decl _ = mzero

     exp ((TiDecorate.Exp (HsLet decls exp))::HsExpP)
          = do (df,dd)<- hsFreeAndDeclaredPNs decls
               (ef,_)<- hsFreeAndDeclaredPNs exp
               return (nub (df `union` (ef \\ dd)), nub dd)
     exp (TiDecorate.Exp (HsLambda pats body))
            = do (pf,pd) <-hsFreeAndDeclaredPNs pats
                 (bf,_) <-hsFreeAndDeclaredPNs body
                 return (nub ((bf `union` pf) \\ pd), nub pd)
     exp _ = mzero

     alt ((HsAlt _ pat exp decls)::HsAltP)
         = do (pf,pd) <- hsFreeAndDeclaredPNs pat
              (ef,ed) <- hsFreeAndDeclaredPNs exp
              (df,dd) <- hsFreeAndDeclaredPNs decls
              return (nub (pf `union` (((ef \\ dd) `union` df) \\ pd)), nub (pd `union` dd))      

     stmts ((HsLetStmt decls stmts)::HsStmtP)
          = do (df,dd) <-hsFreeAndDeclaredPNs decls
               (sf,sd) <-hsFreeAndDeclaredPNs stmts
               return (nub (df `union` (sf \\dd)),[]) -- dd)

     stmts (HsGenerator _ pat exp stmts)
          = do (pf,pd) <-hsFreeAndDeclaredPNs pat
               (ef,ed) <-hsFreeAndDeclaredPNs exp
               (sf,sd) <-hsFreeAndDeclaredPNs stmts
               return (nub (pf `union` ef `union` (sf\\pd)),[]) -- pd)

     stmts _ = mzero
-}


-- | The same as `hsFDsFromInside` except that the returned variables
-- are in the String format
hsFDNamesFromInside::(SYB.Data t) => t -> ([String],[String])
hsFDNamesFromInside t =
  let
    (f,d) = hsFDsFromInside t
  in
    ((nub.map GHC.showPpr) f, (nub.map GHC.showPpr) d)
-- hsFDNamesFromInside::(Term t, MonadPlus m)=>t->m ([String],[String])
-- hsFDNamesFromInside t =do (f,d)<-hsFDsFromInside t
--                           return ((nub.map pNtoName) f, (nub.map pNtoName) d)


-- ---------------------------------------------------------------------
-- | Collect the identifiers (in PName format) in a given syntax phrase.

hsPNs::(SYB.Data t)=> t -> [PName]
hsPNs t = (nub.ghead "hsPNs") res
  where
     res = SYB.everythingStaged SYB.Parser (++) [] ([] `SYB.mkQ` inPnt) t

     inPnt (pname :: GHC.RdrName) = return [(PN pname)]

-- ---------------------------------------------------------------------

hsNamess::(SYB.Data t)=> t -> [GHC.Name]
hsNamess t = (nub.ghead "hsNamess") res
  where
     res = SYB.everythingStaged SYB.Renamer (++) [] ([] `SYB.mkQ` inName) t

     inName (pname :: GHC.Name) = return [pname]



{-
-- | Collect the identifiers (in PNT format) in a given syntax phrase.
hsPNTs ::(Term t)=>t->[PNT]
hsPNTs =(nub.ghead "hsPNTs").applyTU (full_tdTU (constTU [] `adhocTU` inPnt))
   where
     inPnt pnt@(PNT _  _ _) = return [pnt]
-}

-----------------------------------------------------------------------------

-- |Return True if a PName is a toplevel PName.
isTopLevelPN::GHC.Name -> RefactGhc Bool
isTopLevelPN n = do
  typechecked <- getTypecheckedModule
  let maybeNames = GHC.modInfoTopLevelScope $ GHC.tm_checked_module_info typechecked
  let names = fromMaybe [] maybeNames
  return $ n `elem` names


-- |Return True if a PName is a local PName.
isLocalPN::GHC.Name -> Bool
isLocalPN = GHC.isInternalName
-- isLocalPN (PN i (UniqueNames.S _)) = True
-- isLocalPN _ = False

{-
-- |Return True if a PName is a qualified PName.
isQualifiedPN::PName->Bool
isQualifiedPN (PN (Qual mod id) _)=True
isQualifiedPN _ =False

-- |Return True if an PNT is a toplevel PNT.
isTopLevelPNT::PNT->Bool
isTopLevelPNT = isTopLevelPN.pNTtoPN
-}

-- |Return True if a PName is a function\/pattern name defined in t.
isFunOrPatName::(SYB.Data t) => GHC.Name -> t -> Bool
isFunOrPatName pn
   =isJust.somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker)
     where
        -- worker (decl::HsDeclP)
        worker (decl::GHC.LHsBind GHC.Name)
           | defines pn decl = Just True
        worker _ = Nothing

{-
-- |Return True if a PNT is a function name defined in t.
isFunPNT::(Term t)=>PNT -> t -> Bool
isFunPNT pnt t = isFunName (pNTtoPN pnt) t

isFunName::(Term t)=>PName->t->Bool
isFunName pn
   =isJust.(applyTU (once_tdTU (failTU `adhocTU` worker)))
     where
        worker (decl::HsDeclP)
           | isFunBind decl && defines pn decl =Just True
        worker _ =Nothing

-- |Return True if a PName is a pattern name defined in t.
isPatName::(Term t)=>PName->t->Bool
isPatName pn
   =isJust.(applyTU (once_tdTU (failTU `adhocTU` worker)))
     where
        worker (decl::HsDeclP)
           | isPatBind decl && defines pn decl =Just True
        worker _ =Nothing
-}
-------------------------------------------------------------------------------
-- |Return True if a PName is a qualified PName.
--  AZ:NOTE: this tests the use instance, the underlying name may be qualified.
--           e.g. used name is zip, GHC.List.zip
isQualifiedPN :: GHC.Name -> RefactGhc Bool
isQualifiedPN name = return $ GHC.isQual $ GHC.nameRdrName name
{-
  = case (GHC.nameModule_maybe name) of
      Just _ -> True
      _      -> False
-}

{-
-- | Return True if a PNT is a type constructor.
isTypeCon :: PNT -> Bool
isTypeCon (PNT pn (Type typeInfo) _) = defType typeInfo == Just TypedIds.Data
isTypeCon _ = False

-- | Return True if a declaration is a type signature declaration.
isTypeSig ::HsDeclP->Bool
isTypeSig (TiDecorate.Dec (HsTypeSig loc is c tp))=True
isTypeSig _=False
-}

-- | Return True if a declaration is a type signature declaration.
-- isTypeSig ::HsDeclP->Bool
-- isTypeSig (TiDecorate.Dec (HsTypeSig loc is c tp))=True
isTypeSig (GHC.L _ (GHC.TypeSig _ _)) = True
isTypeSig _ = False

-- | Return True if a declaration is a function definition.
isFunBindP::HsDeclP -> Bool
isFunBindP (GHC.L l (GHC.ValD (GHC.FunBind _ _ _ _ _ _))) = True
isFunBindP _ =False

isFunBindR::GHC.LHsBind t -> Bool
isFunBindR (GHC.L _l (GHC.FunBind _ _ _ _ _ _)) = True
isFunBindR _ =False

-- | Returns True if a declaration is a pattern binding.
isPatBindP::HsDeclP->Bool
isPatBindP (GHC.L _ (GHC.ValD (GHC.PatBind _ _ _ _ _))) = True
isPatBindP _=False

isPatBindR::GHC.LHsBind t -> Bool
isPatBindR (GHC.L _ (GHC.PatBind _ _ _ _ _)) = True
isPatBindR _=False


-- | Return True if a declaration is a pattern binding which only
-- defines a variable value.
isSimplePatBind :: (SYB.Data t) => GHC.LHsBind t-> Bool
isSimplePatBind decl = case decl of
     (GHC.L _l (GHC.PatBind p _rhs _ty _fvs _)) -> hsPNs p /= []
     _ -> False
-- isSimplePatBind :: HsDeclP -> Bool
-- isSimplePatBind decl = case decl of
--      (GHC.L l (GHC.ValD (GHC.PatBind p rhs ty fvs _))) -> hsPNs p /= []
--      _ -> False

-- | Return True if a declaration is a pattern binding but not a simple one.
isComplexPatBind::GHC.LHsBind GHC.Name -> Bool
isComplexPatBind decl = case decl of
     (GHC.L _l (GHC.PatBind p _rhs _ty _fvs _)) -> patToPNT p /= Nothing
     _ -> False

-- | Return True if a declaration is a function\/pattern definition.
isFunOrPatBindP::HsDeclP->Bool
isFunOrPatBindP decl = isFunBindP decl || isPatBindP decl

-- | Return True if a declaration is a function\/pattern definition.
isFunOrPatBindR::GHC.LHsBind t -> Bool
isFunOrPatBindR decl = isFunBindR decl || isPatBindR decl

{-
-- | Return True if a declaration is a Class declaration.
isClassDecl :: HsDeclP ->Bool
isClassDecl (TiDecorate.Dec (HsClassDecl _ _ _ _ _)) = True
isClassDecl _ = False

-- | Return True if a declaration is a Class instance declaration.
isInstDecl :: HsDeclP -> Bool
isInstDecl (TiDecorate.Dec (HsInstDecl _ _ _ _ _)) = True
isInstDecl _ = False
-}
{-
-- | Return True if a function is a directly recursive function.
isDirectRecursiveDef::HsDeclP->Bool
isDirectRecursiveDef (TiDecorate.Dec (HsFunBind loc ms))
   = any isUsedInDef ms
  where
   isUsedInDef (HsMatch loc1 fun pats rhs ds)
     = findEntity (pNTtoPN fun) rhs
isDirectRecursiveDef _ = False
-}
-------------------------------------------------------------------------------

{- ++AZ++ This class is being removed
{- | The HsDecls class -}
class (SYB.Data t) => HsDecls t where

    -- | Return the declarations that are directly enclosed in the
    -- given syntax phrase.
    hsDecls :: t -> [HsDeclP]

    -- | Replace the directly enclosed declaration list by the given
    --  declaration list. Note: This function does not modify the
    --  token stream.
    -- replaceDecls :: t -> HsDeclsP -> t -- ++AZ++ TODO: what are HsDeclsP?

    -- | Return True if the specified identifier is declared in the
    -- given syntax phrase.
    isDeclaredIn :: PName -> t -> Bool

instance HsDecls GHC.ParsedSource where
   hsDecls (GHC.L _ (GHC.HsModule _ _ _ ds _ _)) = ds

   isDeclaredIn pn (GHC.L _ (GHC.HsModule _ _ _ ds _ _))
     = length (definingDecls [pn] ds False False) /= 0
++AZ++ end -}

-- | Replace the directly enclosed declaration list by the given
--  declaration list. Note: This function does not modify the
--  token stream.
replaceDecls :: [GHC.LHsBind GHC.Name] -> [GHC.LHsBind GHC.Name] -> [GHC.LHsBind GHC.Name]
replaceDecls t decls = decls

-- getDecls :: GHC.RenamedSource -> GHC.LHsBinds GHC.Name
getDecls :: GHC.RenamedSource -> [GHC.LHsBind GHC.Name]
getDecls renamed@(group, _, _, _) = case (GHC.hs_valds group) of
   GHC.ValBindsIn   binds _sigs -> GHC.bagToList $ binds
   GHC.ValBindsOut rbinds _sigs -> GHC.bagToList $ GHC.unionManyBags $ map (\(_,b) -> b) rbinds

getDeclsP :: GHC.ParsedSource -> [HsDeclP]
getDeclsP parsed@(GHC.L _ hsMod) = GHC.hsmodDecls hsMod

getValBinds :: GHC.HsValBinds t -> [GHC.LHsBind t]
getValBinds binds = case binds of
    GHC.ValBindsIn   binds _sigs -> GHC.bagToList binds
    GHC.ValBindsOut rbinds _sigs -> GHC.bagToList $ GHC.unionManyBags $ map (\(_,b) -> b) rbinds

-- This class replaces the HsDecls one
class (SYB.Data t) => HsBinds t where

    -- | Return the binds that are directly enclosed in the
    -- given syntax phrase.
    hsBinds :: t -> [GHC.LHsBind GHC.Name]

    -- | Replace the directly enclosed bind list by the given
    --  bind list. Note: This function does not modify the
    --  token stream.
    replaceBinds :: t -> [GHC.LHsBind GHC.Name] -> t

    -- | Return True if the specified identifier is declared in the
    -- given syntax phrase.
    isDeclaredIn :: GHC.Name -> t -> Bool


instance HsBinds (GHC.RenamedSource) where
  hsBinds (grp,_,_,_) = getValBinds (GHC.hs_valds grp)

  replaceBinds (grp,imps,exps,docs) binds = (grp',imps,exps,docs)
    where
      vb = GHC.hs_valds grp
      vb' = case vb of
        GHC.ValBindsIn _oldbinds sigs -> GHC.ValBindsIn (GHC.listToBag binds) sigs
        -- ++AZ++ does it matter that we are throwing away the recursive flag?
        GHC.ValBindsOut _rbinds sigs  -> GHC.ValBindsIn (GHC.listToBag binds) sigs
      grp' = grp {GHC.hs_valds = vb'}

instance HsBinds (GHC.HsValBinds GHC.Name) where
  hsBinds vb = getValBinds vb
  replaceBinds = error "undefined replaceBinds (GHC.HsValBinds GHC.Name)"

instance HsBinds (GHC.HsGroup GHC.Name) where
  hsBinds grp = getValBinds (GHC.hs_valds grp)
  replaceBinds = error "undefined replaceBinds (GHC.HsGroup GHC.Name)"

instance HsBinds (GHC.HsLocalBinds GHC.Name) where
  hsBinds lb = case lb of
    GHC.HsValBinds b    -> getValBinds b
    GHC.HsIPBinds _     -> []
    GHC.EmptyLocalBinds -> []

  replaceBinds (GHC.HsValBinds b) new    = (GHC.HsValBinds (replaceBinds b new))
  -- replaceBinds (GHC.GRHSs rhss (GHC.HsIPBinds b)) new     = (GHC.GRHSs rhss (GHC.HsIPBinds (replaceBinds b new)))
  replaceBinds (GHC.HsIPBinds b) new     = error "undefined replaceBinds HsIPBinds"
  replaceBinds (GHC.EmptyLocalBinds) new = (GHC.HsValBinds (GHC.ValBindsIn (GHC.listToBag new) []))

instance HsBinds (GHC.GRHSs GHC.Name) where
  hsBinds (GHC.GRHSs _ lb) = hsBinds lb

  replaceBinds (GHC.GRHSs rhss b) new = (GHC.GRHSs rhss (replaceBinds b new))


-- ---------------------------------------------------------------------

instance HsBinds (GHC.MatchGroup GHC.Name) where
  hsBinds (GHC.MatchGroup matches _) = hsBinds matches

  replaceBinds (GHC.MatchGroup matches a) newBinds
               = (GHC.MatchGroup (replaceBinds matches newBinds) a)

-- ---------------------------------------------------------------------

instance HsBinds [GHC.LMatch GHC.Name] where
  hsBinds ms = concatMap (\m -> hsBinds $ GHC.unLoc m) ms

  replaceBinds [] _        = error "empty match list in replaceBinds [GHC.LMatch GHC.Name]"
  replaceBinds ms newBinds = (replaceBinds (head ms) newBinds):(tail ms)

-- ---------------------------------------------------------------------

instance HsBinds (GHC.LMatch GHC.Name) where
  hsBinds m = hsBinds $ GHC.unLoc m

  replaceBinds (GHC.L l m) newBinds = (GHC.L l (replaceBinds m newBinds))


-- ---------------------------------------------------------------------


instance HsBinds (GHC.Match GHC.Name) where
  hsBinds (GHC.Match _ _ grhs) = hsBinds grhs

  replaceBinds (GHC.Match p t (GHC.GRHSs rhs binds)) newBinds
    = (GHC.Match p t (GHC.GRHSs rhs binds'))
      where
        binds' = (GHC.HsValBinds (GHC.ValBindsIn (GHC.listToBag newBinds) []))


instance HsBinds (GHC.HsBind GHC.Name) where
  hsBinds (GHC.PatBind _p rhs _typ _fvs _) = hsBinds rhs

  replaceBinds (GHC.PatBind p (GHC.GRHSs rhs binds) typ fvs pt) newBinds
    = (GHC.PatBind p (GHC.GRHSs rhs binds') typ fvs pt)
      where
        binds' = (GHC.HsValBinds (GHC.ValBindsIn (GHC.listToBag newBinds) []))

instance HsBinds (GHC.HsExpr GHC.Name) where
  hsBinds (GHC.HsLet ds _) = hsBinds ds

instance HsBinds (GHC.Stmt GHC.Name) where
  hsBinds (GHC.LetStmt ds) = hsBinds ds
  replaceBinds = error "replaceBinds (GHC.Stmt GHC.Name) undefined"


-- ---------------------------------------------------------------------

instance HsBinds (GHC.LHsBinds GHC.Name) where
  hsBinds binds = hsBinds $ GHC.bagToList binds

-- ---------------------------------------------------------------------

instance HsBinds (GHC.LHsBind GHC.Name) where
  hsBinds (GHC.L _ (GHC.FunBind _ _ matches _ _ _)) = hsBinds matches
  hsBinds (GHC.L _ (GHC.PatBind _ rhs _ _ _))       = hsBinds rhs
  hsBinds (GHC.L _ (GHC.VarBind _ rhs _))           = hsBinds rhs
  hsBinds (GHC.L _ (GHC.AbsBinds _ _ _ _ binds))    = hsBinds binds


  replaceBinds (GHC.L l (GHC.FunBind a b matches c d e)) newBinds
               = (GHC.L l (GHC.FunBind a b (replaceBinds matches newBinds) c d e))
  replaceBinds (GHC.L l (GHC.PatBind a rhs b c d)) newBinds
               = (GHC.L l (GHC.PatBind a (replaceBinds rhs newBinds) b c d))
  replaceBinds (GHC.L l (GHC.VarBind a rhs b)) newBinds
               = (GHC.L l (GHC.VarBind a (replaceBinds rhs newBinds) b))
  replaceBinds (GHC.L l (GHC.AbsBinds a b c d binds)) newBinds
               = (GHC.L l (GHC.AbsBinds a b c d (replaceBinds binds newBinds)))

-- ---------------------------------------------------------------------

instance HsBinds ([GHC.LHsBind GHC.Name]) where
  -- hsBinds x = x
  hsBinds xs = concatMap hsBinds xs -- As in original

  replaceBinds _old new = new
  -- replaceBinds old new = error ("replaceBinds (old,new)=" ++ (GHC.showPpr (old,new)))

instance HsBinds (GHC.LHsExpr GHC.Name) where
  hsBinds (GHC.L _ (GHC.HsLet binds ex)) = hsBinds binds
  hsBinds _                              = []

-- ---------------------------------------------------------------------



{-
instance HsDecls HsMatchP where
    hsDecls (HsMatch loc1 fun pats rhs ds@(Decs x y))=x

    replaceDecls (HsMatch loc1 fun pats rhs ds) ds'
      =(HsMatch loc1 fun pats rhs ds')

    isDeclaredIn  pn match@(HsMatch loc1 (PNT fun _ _) pats rhs ds)
       =fromMaybe False ( do (_,d)<-hsFDsFromInside match
                             Just (elem pn (d \\ [fun])))
instance HsDecls HsDeclP where
    hsDecls (TiDecorate.Dec (HsPatBind loc p rhs ds@(Decs x y)))=x
    hsDecls (TiDecorate.Dec (HsFunBind loc matches))=concatMap hsDecls matches
    hsDecls _ =[]

    replaceDecls (TiDecorate.Dec (HsPatBind loc p rhs ds)) ds'
        =TiDecorate.Dec (HsPatBind loc p rhs ds')
    replaceDecls x ds' =x

    isDeclaredIn pn (TiDecorate.Dec (HsPatBind loc p rhs ds))
      = fromMaybe False (do (_, rd)<-hsFreeAndDeclaredPNs rhs
                            (_, dd)<-hsFreeAndDeclaredPNs ds
                            Just (elem pn (rd `union` dd)))
    isDeclaredIn pn _ =False

instance HsDecls HsDeclsP where
    hsDecls ds@(Decs x y) = concatMap hsDecls x
    replaceDecls ds _ = ds
    isDeclaredIn _ ds@(Decs x y) = False

instance HsDecls [HsDeclP] where
    hsDecls ds= concatMap hsDecls ds
    replaceDecls ds _ = ds             -- This should not happen.
    isDeclaredIn _ ds = False            -- This should not happen.

instance HsDecls HsModuleP where
    hsDecls (HsModule loc modName exps imps ds@(Decs x y))=x

    replaceDecls (HsModule loc modName exps imps ds) ds'
       = HsModule loc modName exps imps ds'

    isDeclaredIn pn (HsModule loc modName exps imps ds)
       =fromMaybe False  (do (rf,rd)<-hsFreeAndDeclaredPNs ds
                             Just (elem pn rd))

instance HsDecls RhsP where
    hsDecls rhs=fromMaybe [] (applyTU (stop_tdTU (failTU `adhocTU` inLet
                                                                        `adhocTU` inAlt
                                                                        `adhocTU` inStmt)) rhs) 
             where inLet ((TiDecorate.Exp (HsLet ds@(Decs x y) e)) ::HsExpP)=Just x
                   inLet _ =mzero

                   inAlt ((HsAlt _ p rhs ds@(Decs x y))::HsAlt HsExpP HsPatP HsDeclsP)=Just x

                   inStmt ((HsLetStmt ds@(Decs x y) _)::HsStmt HsExpP HsPatP HsDeclsP)=Just x
                   inStmt _=mzero

    replaceDecls rhs _ = rhs           -- This should not happen.
    isDeclaredIn _ _  = False            -- This should not happen.

instance HsDecls HsExpP where
    hsDecls rhs=fromMaybe [] (applyTU (stop_tdTU (failTU `adhocTU` inLet
                                                         `adhocTU` inAlt
                                                         `adhocTU` inStmt)) rhs)
             where inLet ((TiDecorate.Exp (HsLet ds@(Decs x y) e)) ::HsExpP)=Just x
                   inLet (TiDecorate.Exp (HsListComp (HsLetStmt ds@(Decs x y) stmts)))=Just x
                   inLet (TiDecorate.Exp (HsDo (HsLetStmt ds@(Decs x y) stmts)))=Just x
                   inLet _ =Nothing

                   inAlt ((HsAlt _ p rhs ds@(Decs x y))::HsAlt HsExpP HsPatP HsDeclsP)=Just x

                   inStmt ((HsLetStmt ds@(Decs x y) _)::HsStmt HsExpP HsPatP HsDeclsP)=Just x
                   inStmt _=Nothing

    replaceDecls (TiDecorate.Exp (HsLet ds e)) ds'
            =if ds'== Decs [] ([], [])
                then e
                else (TiDecorate.Exp (HsLet ds' e))

    replaceDecls (TiDecorate.Exp (HsListComp (HsLetStmt ds stmts))) ds'@(Decs x y)
            =if x==[] && isLast stmts
               then (TiDecorate.Exp (HsList [fromJust (expInLast stmts)]))
               else (TiDecorate.Exp (HsListComp (HsLetStmt ds' stmts)))
       where
         isLast (HsLast e)=True
         isLast _=False

         expInLast (HsLast e)=Just e
         expInLast _=Nothing

    replaceDecls (TiDecorate.Exp (HsDo (HsLetStmt ds stmts))) ds'@(Decs x y)
            =if x==[]
                then (TiDecorate.Exp (HsDo stmts))
                else (TiDecorate.Exp (HsDo (HsLetStmt ds' stmts)))
    replaceDecls x ds'=x


    isDeclaredIn pn (TiDecorate.Exp (HsLambda pats body))
            = fromMaybe False (do (pf,pd) <-hsFreeAndDeclaredPNs pats
                                  Just (elem pn  pd))

    isDeclaredIn pn (TiDecorate.Exp (HsLet decls e))
           =fromMaybe False (do (df,dd)<- hsFreeAndDeclaredPNs decls
                                Just (elem pn dd))

    isDeclaredIn pn _=False


instance HsDecls HsStmtP where
    hsDecls (HsLetStmt ds@(Decs x y) stmts)=x
    hsDecls  _ = []

    replaceDecls (HsLetStmt ds stmts) ds'@(Decs x y)
     = if x/=[] then  HsLetStmt ds' stmts
                  else stmts

    isDeclaredIn pn (HsGenerator _ pat exp stmts) -- Claus
        =fromMaybe False (do (pf,pd) <-hsFreeAndDeclaredPNs pat
                             Just (elem pn pd))

    isDeclaredIn pn (HsLetStmt decls stmts)
        =fromMaybe False (do (df,dd) <-hsFreeAndDeclaredPNs decls
                             Just (elem pn dd))

    isDeclaredIn pn _=False

instance HsDecls HsAltP where
    hsDecls (HsAlt _ p rhs ds@(Decs x y))=x

    replaceDecls (HsAlt loc p rhs ds) ds'=HsAlt loc p rhs ds'

    isDeclaredIn pn (HsAlt _ pat exp decls)
       =fromMaybe False ( do (pf,pd) <- hsFreeAndDeclaredPNs pat
                             (df,dd) <- hsFreeAndDeclaredPNs decls
                             Just (elem pn (pd `union` dd)))

-}

-- ---------------------------------------------------------------------

class (SYB.Data a, SYB.Typeable a) => FindEntity a where

  -- | Returns True is a syntax phrase, say a, is part of another
  -- syntax phrase, say b.
  findEntity:: (SYB.Data b, SYB.Typeable b) => a -> b -> Bool

-- ---------------------------------------------------------------------

instance FindEntity GHC.Name where

  findEntity n t = fromMaybe False res
   where
    res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker) t

    worker (name::GHC.Name)
      | n == name = Just True
    worker _ = Nothing

-- ---------------------------------------------------------------------

instance FindEntity (GHC.Located GHC.Name) where

  findEntity n t = fromMaybe False res
   where
    res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker) t

    worker (name::GHC.Located GHC.Name)
      | n == name = Just True
    worker _ = Nothing

-- ---------------------------------------------------------------------

instance FindEntity (GHC.Located (GHC.HsExpr GHC.Name)) where

  -- findEntity n t = error "findEntity (GHC.Located (GHC.HsExpr GHC.Name)) undefined"
  findEntity e t = fromMaybe False res
   where
    res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker) t

    worker (expr::GHC.Located (GHC.HsExpr GHC.Name))
      -- | e == expr = Just True
      | sameOccurrence e expr = Just True
    worker _ = Nothing

-- ---------------------------------------------------------------------

{-
-- | Returns True is a syntax phrase, say a, is part of another syntax
-- phrase, say b.
-- Expects to be at least Parser output
findEntity:: (SYB.Data a, SYB.Data b)=> a -> b -> Bool
findEntity a b = fromMaybe False res
  where
    res = somethingStaged SYB.Parser Nothing worker b

    worker :: (SYB.Typeable b, SYB.Data b) => b -> Maybe Bool
    worker b = if SYB.typeOf a == SYB.typeOf b
                 -- then Just (getStartEndLoc b == getStartEndLoc a)
                 then Just True -- ++AZ++ test for now
                 else Nothing
-}
findEntity':: (SYB.Data a, SYB.Data b)
              => a -> b -> Maybe (SimpPos,SimpPos)
findEntity' a b = res
  where
    -- ++AZ++ do a generic traversal, and see if it matches.
    res = somethingStaged SYB.Parser Nothing worker b

    worker :: (SYB.Typeable c,SYB.Data c)
           => c -> Maybe (SimpPos,SimpPos)
    worker x = if SYB.typeOf a == SYB.typeOf x
                 -- then Just (getStartEndLoc b == getStartEndLoc a)
                 then Just (getStartEndLoc x)
                 else Nothing

{-
    worker :: ( SYB.Typeable a{-, SYB.Typeable b-})
      => Maybe Bool
      -- -> (b -> r)
      -> a
      -> Maybe Bool
    worker a = case SYB.cast a of
               Just b -> Just True
               Nothing -> r
-}




-- ---------------------------------------------------------------------

-- |Find those declarations(function\/pattern binding and type
-- signature) which define the specified PNames. incTypeSig indicates
-- whether the corresponding type signature will be included.
definingDecls::[PName]  -- ^ The specified identifiers.
            ->[HsDeclP] -- ^ A collection of declarations.
            ->Bool      -- ^ True means to include the type signature.
            ->Bool      -- ^ True means to look at the local declarations as well. 
            ->[HsDeclP] -- ^ The result.
definingDecls pns ds incTypeSig recursive = concatMap defines ds
  where
   defines decl
     = if recursive -- TODO: original seems to stop on first match? Should continue
        -- then ghead "defines" $ applyTU (stop_tdTU (failTU `adhocTU` inDecl)) decl
        then SYB.everythingStaged SYB.Parser (++) [] ([] `SYB.mkQ` inDecl) decl
        else defines' decl
     where
      inDecl (d::GHC.LHsDecl GHC.RdrName {- HsDeclP -} )
        -- |defines' d /= [] =return $ defines' d
        -- | length (defines' d) /= 0 = defines' d -- TODO: horribly inefficient
        | True = defines' d -- TODO: horribly inefficient
      inDecl _ = []

      defines' :: HsDeclP -> [HsDeclP]

      -- ValD - binds
      defines' decl@(GHC.L l (GHC.ValD (GHC.FunBind (GHC.L _ pname) _ _ _ _ _)))
        |isJust (find (==(PN pname)) pns) = [decl]

      defines' decl@(GHC.L l (GHC.ValD (GHC.PatBind p rhs ty fvs _)))    ---CONSIDER AGAIN----
        |(hsPNs p) `intersect` pns /= [] = [decl]
      defines' decl@(GHC.L l (GHC.ValD _))                                    = []

      -- SigD - type signatures
      defines' decl@(GHC.L l (GHC.SigD (GHC.TypeSig is tp)))
        |(map lghcToPN is) `intersect` pns /=[]
        = if incTypeSig
           then [(GHC.L l (GHC.SigD (GHC.TypeSig (filter (\x->isJust (find (==lghcToPN x) pns)) is) tp)))]
           else []
      defines' decl@(GHC.L l (GHC.SigD        _ {- (GHC.Sig id) -}))          = []

      -- TyClD - Type definitions
      defines' decl@(GHC.L l (GHC.TyClD (GHC.TyData _ _ name _ _ _ cons _)))
       = if checkCons cons == True then [decl]
                                   else []

             where
               checkCons [] = False
               checkCons ((GHC.L _ (GHC.ConDecl (GHC.L _ pname) _ _ _ _ _ _ _)):ms)
                 | isJust (find (==(PN pname)) pns) = True
                 | otherwise = checkCons ms

      defines' decl@(GHC.L l (GHC.TyClD       _ {- (GHC.TyClDecl id) -}))     = []


      defines' decl@(GHC.L l (GHC.InstD       _ {- (GHC.InstDecl id) -}))     = []
      defines' decl@(GHC.L l (GHC.DerivD      _ {- (GHC.DerivDecl id) -}))    = []
      defines' decl@(GHC.L l (GHC.DefD        _ {- (GHC.DefaultDecl id) -}))  = []
      defines' decl@(GHC.L l (GHC.ForD        _ {- (GHC.ForeignDecl id) -}))  = []
      defines' decl@(GHC.L l (GHC.WarningD    _ {- (GHC.WarnDecl id) -}))     = []
      defines' decl@(GHC.L l (GHC.AnnD        _ {- (GHC.AnnDecl id) -}))      = []
      defines' decl@(GHC.L l (GHC.RuleD       _ {- (GHC.RuleDecl id) -}))     = []
      defines' decl@(GHC.L l (GHC.VectD       _ {- (GHC.VectDecl id) -}))     = []
      defines' decl@(GHC.L l (GHC.SpliceD     _ {- (GHC.SpliceDecl id) -}))   = []
      defines' decl@(GHC.L l (GHC.DocD        _ {- (GHC.DocDecl) -}))         = []
      defines' decl@(GHC.L l (GHC.QuasiQuoteD _ {- (GHC.HsQuasiQuote id) -})) = []

-- ---------------------------------------------------------------------

-- |Find those declarations(function\/pattern binding) which define
-- the specified GHC.Names. incTypeSig indicates whether the
-- corresponding type signature will be included.
definingDeclsNames:: -- (SYB.Data t) =>
            [GHC.Name] -- ^ The specified identifiers.
            -- ->t                -- ^ A collection of declarations.
            ->[GHC.LHsBind GHC.Name] -- ^ A collection of declarations.
            ->Bool       -- ^ True means to include the type signature.
            ->Bool       -- ^ True means to look at the local declarations as well. 
            ->[GHC.LHsBind GHC.Name]  -- ^ The result.
definingDeclsNames pns ds _incTypeSig recursive = concatMap defines ds
  where
   defines decl
     = if recursive
        then SYB.everythingStaged SYB.Renamer (++) [] ([]  `SYB.mkQ` inDecl) decl
        else defines' decl
     where
      inDecl :: (GHC.LHsBind GHC.Name) -> [GHC.LHsBind GHC.Name]
      inDecl (d::(GHC.LHsBind GHC.Name))
        | not $ emptyList (defines' d) = defines' d
      inDecl _ = []

      defines' :: (GHC.LHsBind GHC.Name) -> [GHC.LHsBind GHC.Name]
      defines' decl'@(GHC.L _ (GHC.FunBind (GHC.L _ pname) _ _ _ _ _))
        |isJust (find (==(pname)) pns) = [decl']

      defines' decl'@(GHC.L _l (GHC.PatBind p _rhs _ty _fvs _))
        |(hsNamess p) `intersect` pns /= [] = [decl']

      defines' _ = []

-- ---------------------------------------------------------------------

-- |Find those type signatures for the specified GHC.Names.
definingSigsNames :: (SYB.Data t) =>
            [GHC.Name] -- ^ The specified identifiers.
            ->t        -- ^ A collection of declarations.
            ->[GHC.LSig GHC.Name]  -- ^ The result.
definingSigsNames pns ds = def ds
  where
   def decl
     = SYB.everythingStaged SYB.Renamer (++) [] ([]  `SYB.mkQ` inSig) decl
     where
      inSig :: (GHC.LSig GHC.Name) -> [GHC.LSig GHC.Name]
      inSig (GHC.L l (GHC.TypeSig ns t))
       | defines' ns /= [] = [(GHC.L l (GHC.TypeSig (defines' ns) t))]
      inSig _ = []

      defines' (p::[GHC.Located GHC.Name])
        = filter (\(GHC.L _ n) -> n `elem` pns) p

-- ---------------------------------------------------------------------

{-

definingDecls::[PName]         -- ^ The specified identifiers.
            ->[HsDeclP]        -- ^ A collection of declarations.
            ->Bool             -- ^ True means to include the type signature.
            ->Bool             -- ^ True means to look at the local declarations as well. 
            ->[HsDeclP]        -- ^ The result.
definingDecls pns ds incTypeSig recursive=concatMap defines ds
  where
   defines decl
     =if recursive
        then ghead "defines" $ applyTU (stop_tdTU (failTU `adhocTU` inDecl)) decl
        else defines' decl
     where
      inDecl (d::HsDeclP)
        |defines' d /=[] =return $ defines' d
      inDecl _=mzero

      defines' decl@(TiDecorate.Dec (HsFunBind _ ((HsMatch _ (PNT pname _ _) _ _ _):ms))) 
        |isJust (find (==pname) pns) = [decl]
      defines' decl@(TiDecorate.Dec (HsPatBind loc p rhs ds))    ---CONSIDER AGAIN----
        |(hsPNs p) `intersect` pns /=[] = [decl]
      defines' decl@(TiDecorate.Dec (HsTypeSig loc is c tp))     --handle cases like  a,b::Int 
        |(map pNTtoPN is) `intersect` pns /=[]
        =if incTypeSig
           then [(TiDecorate.Dec (HsTypeSig loc (filter (\x->isJust (find (==pNTtoPN x) pns)) is) c tp))]
           else []
      defines' decl@(TiDecorate.Dec (HsDataDecl loc c tp cons i))
       = if checkCons cons == True then [decl]
                                   else []

             where
               checkCons [] = False
               checkCons ((HsConDecl loc i c (PNT pname _ _) t):ms)
                 | isJust (find (==pname) pns) = True
                 | otherwise = checkCons ms
      defines' _ =[]
-}

-- ---------------------------------------------------------------------

-- TODO: AZ: pretty sure this can be simplified, depends if we need to
--          manage transformed stuff too though.

-- | Return True if syntax phrases t1 and t2 refer to the same one.
sameOccurrence :: (GHC.Located t) -> (GHC.Located t) -> Bool
sameOccurrence (GHC.L l1 _) (GHC.L l2 _)
 = l1 == l2


-- ---------------------------------------------------------------------

-- | Return True if the function\/pattern binding defines the
-- specified identifier.
defines:: GHC.Name -> GHC.LHsBind GHC.Name -> Bool
defines n (GHC.L _ (GHC.FunBind (GHC.L _ pname) _ _ _ _ _))
 = pname == n
defines n (GHC.L _ (GHC.PatBind p _rhs _ty _fvs _))
 = elem n (hsNamess p)
defines _ _= False

definesP::PName->HsDeclP->Bool
definesP pn (GHC.L _ (GHC.ValD (GHC.FunBind (GHC.L _ pname) _ _ _ _ _)))
 = PN pname == pn
definesP pn (GHC.L _ (GHC.ValD (GHC.PatBind p _rhs _ty _fvs _)))
 = elem pn (hsPNs p)
definesP _ _= False

-- defines::PName->HsDeclP->Bool
-- defines pn (GHC.L l (GHC.ValD (GHC.FunBind (GHC.L _ pname) _ _ _ _ _)))
--  = PN pname == pn
-- defines pn (GHC.L l (GHC.ValD (GHC.PatBind p rhs ty fvs _)))
--  = elem pn (hsPNs p)
-- defines _ _= False


-- | Return True if the declaration defines the type signature of the
-- specified identifier.
definesTypeSig :: GHC.Name -> GHC.LSig GHC.Name -> Bool
definesTypeSig pn (GHC.L _ (GHC.TypeSig names _typ)) = elem pn $ map (\(GHC.L _ n)->n) names
definesTypeSig _  _ =False


{-
-- | Return True if the declaration defines the type signature of the specified identifier.
isTypeSigOf :: PNT -> HsDeclP -> Bool
isTypeSigOf pnt (TiDecorate.Dec (HsTypeSig loc is c tp))= elem pnt is
isTypeSigOf _  _ =False
-}

-- | Return the list of identifiers (in PName format) defined by a function\/pattern binding.
definedPNs::GHC.LHsBind GHC.Name -> [GHC.Name]
definedPNs (GHC.L _ (GHC.FunBind (GHC.L _ pname) _ _ _ _ _)) = [pname]
definedPNs (GHC.L _ (GHC.PatBind p _rhs _ty _fvs _)) = (hsNamess p)
definedPNs (GHC.L _ (GHC.VarBind pname _rhs _)) = [pname]
-- TODO: what about GHC.AbsBinds?
definedPNs  _ = []

{-
-- |Return True if the given syntax phrase contains any free variables.
hasFreeVars::(Term t)=>t->Bool
hasFreeVars t = fromMaybe False (do (f,_)<-hsFreeAndDeclaredPNs t
                                    if f/=[] then Just True
                                             else Nothing)
-}

--------------------------------------------------------------------------------

sameBind :: GHC.LHsBind GHC.Name -> GHC.LHsBind GHC.Name -> Bool
sameBind b1 b2 = (definedPNs b1) == (definedPNs b2)
{-
sameBind b1 b2 = (definesNames b1) == (definesNames b2)
  where
    definesNames (GHC.L _ (GHC.PatBind p _rhs _ _ _))             = hsNamess p
    definesNames (GHC.L _ (GHC.FunBind (GHC.L _ name) _ _ _ _ _)) = [name]
    definesNames (GHC.L _ (GHC.VarBind name _ _))                 = [name]
-}
-- ---------------------------------------------------------------------

class (SYB.Data t) => UsedByRhs t where

    -- | Return True if any of the GHC.Name's appear in the given
    -- syntax element
    usedByRhs:: t -> [GHC.Name] -> Bool

instance UsedByRhs GHC.RenamedSource where

   -- Defined like this in the original
   usedByRhs renamed pns = False


instance UsedByRhs [GHC.LHsBind GHC.Name] where
  usedByRhs binds pns = or $ map (\b -> usedByRhs b pns) binds

instance UsedByRhs (GHC.LHsBind GHC.Name) where
  usedByRhs (GHC.L _ (GHC.FunBind _ _ matches _ _ _)) pns = findPNs pns matches
  usedByRhs (GHC.L _ (GHC.PatBind _ rhs _ _ _))       pns = findPNs pns rhs
  usedByRhs (GHC.L _ (GHC.VarBind _ rhs _))           pns = findPNs pns rhs
  usedByRhs (GHC.L _ (GHC.AbsBinds _ _ _ _ _))        pns = False


{- ++ original
class (Term t) =>UsedByRhs t where

    usedByRhs:: t->[PName]->Bool

instance UsedByRhs HsExpP where
    usedByRhs (Exp (HsLet ds e)) pns = or $ map (flip findPN e) pns

instance UsedByRhs HsAltP where
    usedByRhs (HsAlt _ _ rhs _) pns  =or $ map (flip findPN rhs) pns

instance UsedByRhs HsStmtP where
    usedByRhs (HsLetStmt _ stmt) pns =or $ map (flip findPN stmt) pns

instance UsedByRhs HsMatchP where
    usedByRhs (HsMatch loc1 fun pats rhs ds) pns =or $ map (flip findPN rhs) pns

instance UsedByRhs  HsDeclP where
    usedByRhs (Dec (HsPatBind loc p rhs ds)) pns =or $ map (flip findPN rhs) pns
    usedByRhs _ pn=False

instance UsedByRhs HsModuleP where
    usedByRhs mod pns=False
-}

--------------------------------------------------------------------------------

-- |Find the identifier(in PNT format) whose start position is (row,col) in the
-- file specified by the fileName, and returns defaultPNT if such an identifier does not exist.

locToPNT::(SYB.Data t)=>GHC.FastString -- ^ The file name
                    ->SimpPos          -- ^ The row and column number
                    ->t                -- ^ The syntax phrase
                    ->PNT              -- ^ The result
-- TODO: return a Maybe, rather than encoding failure in defaultPNT
locToPNT  fileName (row,col) t
  = case res of
         Just x -> x
         Nothing -> defaultPNT
       where
        res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt@(GHC.L l _) :: (GHC.Located GHC.RdrName))
          | inScope l = Just (PNT pnt)
        worker _ = Nothing

        workerBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.RdrName)))
          | inScope l = Just (PNT (GHC.L l name))
        workerBind _ = Nothing

        workerExpr (pnt@(GHC.L l (GHC.HsVar name)) :: (GHC.Located (GHC.HsExpr GHC.RdrName)))
          | inScope l = Just (PNT (GHC.L l name))
        workerExpr _ = Nothing

        inScope :: GHC.SrcSpan -> Bool
        inScope l =
          case l of
            (GHC.UnhelpfulSpan _) -> False
            (GHC.RealSrcSpan ss)  ->
              (GHC.srcSpanFile ss == fileName) &&
              (GHC.srcSpanStartLine ss == row) &&
              (col >= (GHC.srcSpanStartCol ss)) &&
              (col <= (GHC.srcSpanEndCol ss))

------------------------------------------------------------------------------------

-- |Find the identifier(in PNT format) whose start position is (row,col) in the
-- file specified by the fileName, and returns defaultPNT if such an identifier does not exist.

allPNT::(SYB.Data t)=>GHC.FastString   -- ^ The file name
                    ->SimpPos          -- ^ The row and column number
                    ->t                -- ^ The syntax phrase
                    ->[PNT]            -- ^ The result
-- TODO: return a Maybe, rather than encoding failure in defaultPNT
allPNT  fileName (row,col) t
  = res
       where
        -- res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker) t
        res = SYB.everythingStaged SYB.Parser (++) []
            ([] `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt :: (GHC.Located GHC.RdrName))
          | True = [(PNT pnt)]
        worker _ = []

        workerBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.RdrName)))
          | True = [(PNT (GHC.L l name))]
        workerBind _ = []

        workerExpr (GHC.L l (GHC.HsVar name) :: (GHC.Located (GHC.HsExpr GHC.RdrName)))
          | True = [(PNT (GHC.L l name))]
        workerExpr _ = []


--------------------------------------------------------------------------------

-- |Find the identifier(in GHC.Name format) whose start position is
-- (row,col) in the file specified by the fileName, and returns
-- `Nothing` if such an identifier does not exist.

locToName::(SYB.Data t)=>GHC.FastString   -- ^ The file name
                    ->SimpPos          -- ^ The row and column number
                    ->t                -- ^ The syntax phrase
                    -> Maybe (GHC.Located GHC.Name)  -- ^ The result
locToName fileName (row,col) t
  = res
       where
        res = somethingStaged SYB.Renamer Nothing
            (Nothing `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt :: (GHC.Located GHC.Name))
          | inScope pnt = Just pnt
        worker _ = Nothing

        workerBind pnt@(GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.Name)))
          | inScope pnt = Just (GHC.L l name)
        workerBind _ = Nothing

        workerExpr (pnt@(GHC.L l (GHC.HsVar name)) :: (GHC.Located (GHC.HsExpr GHC.Name)))
          | inScope pnt = Just (GHC.L l name)
        workerExpr _ = Nothing

        inScope :: GHC.Located e -> Bool
        inScope (GHC.L l _) =
          case l of
            (GHC.UnhelpfulSpan _) -> False
            (GHC.RealSrcSpan ss)  ->
              (GHC.srcSpanFile ss == fileName) &&
              (GHC.srcSpanStartLine ss == row) &&
              (col >= (GHC.srcSpanStartCol ss)) &&
              (col <= (GHC.srcSpanEndCol ss))



--------------------------------------------------------------------------------

-- |Find all Located Names in the given Syntax phrase.
allNames::(SYB.Data t)
       =>t                      -- ^ The syntax phrase
       ->[GHC.Located GHC.Name] -- ^ The result
allNames t
  = res
       where
        res = SYB.everythingStaged SYB.Parser (++) []
            ([] `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt :: (GHC.Located GHC.Name))
          = [pnt]
        -- worker _ = []

        workerBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.Name)))
          = [(GHC.L l name)]
        workerBind _ = []

        workerExpr ((GHC.L l (GHC.HsVar name)) :: (GHC.Located (GHC.HsExpr GHC.Name)))
          = [(GHC.L l name)]
        workerExpr _ = []



--------------------------------------------------------------------------------

-- |Find the identifier with the given name. This looks through the
-- given syntax phrase for the first GHC.Name which matches. Because
-- it is Renamed source, the GHC.Name will include its defining
-- location. Returns Nothing if the name is not found.

getName::(SYB.Data t)=>
                      String           -- ^ The name to find
                    ->t                -- ^ The syntax phrase
                    ->Maybe GHC.Name   -- ^ The result
getName str t
  = res
       where
        res = somethingStaged SYB.Renamer Nothing
            (Nothing `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt@(GHC.L _ n) :: (GHC.Located GHC.Name))
          | GHC.showPpr n == str = Just n
        worker _ = Nothing

        workerBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.Name)))
          | GHC.showPpr name == str = Just name
        workerBind _ = Nothing


        workerExpr (pnt@(GHC.L l (GHC.HsVar name)) :: (GHC.Located (GHC.HsExpr GHC.Name)))
          | GHC.showPpr name == str = Just name
        workerExpr _ = Nothing



------------------------------------------------------------------------------------

-- |Find the identifier(in PNT format) whose start position is (row,col) in the
-- file specified by the fileName, and returns defaultPNT if such an identifier does not exist.
allPNTLens ::(SYB.Data t, SYB.Typeable t)=>GHC.FastString   -- ^ The file name
                    ->SimpPos          -- ^ The row and column number
                    ->t                -- ^ The syntax phrase
                    ->[PNT]            -- ^ The result

-- TODO: return a Maybe, rather than encoding failure in defaultPNT
allPNTLens fileName (row,col) t
  = res
       where
        -- res = []
        res = pnts t

        pnts :: (SYB.Data a, SYB.Typeable a) => a -> [PNT]
        -- pnts = foldMapOf ghcplate getPNT

        -- foldMapOf :: Monoid r => Simple Traversal a c -> (c -> r) -> a -> r
        pnts = foldMapOf mytraverse pntQ
        -- pnts = foldMapOf mytraverse getPNT
        -- pnts = foldMapOf ghcplate getPNT
        -- pnts = foldOf mytraverse
        -- pnts = foldMapOf ghcplate getPNTBind


mytraverse :: (SYB.Data a) => Simple Traversal a [PNT]
mytraverse = ghcplate


-- pntQ :: (SYB.Data a, SYB.Typeable a) => a -> [PNT]
pntQ = (          [] `SYB.mkQ` getPNT `SYB.extQ` getPNTBind)

getPNT pnt@(GHC.L l name) = [PNT pnt]

getPNTBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.RdrName)))
       = [(PNT (GHC.L l name))]
getPNTBind _ = []

-- getPNT

  {-
        -- res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker) t
        res = SYB.everythingStaged SYB.Parser (++) []
            ([] `SYB.mkQ` worker `SYB.extQ` workerBind `SYB.extQ` workerExpr) t

        worker (pnt :: (GHC.Located GHC.RdrName))
          -- | inScope pnt = [(PNT pnt)]
          | True = [(PNT pnt)]
        worker _ = []

        workerBind (GHC.L l (GHC.VarPat name) :: (GHC.Located (GHC.Pat GHC.RdrName)))
          -- | inScope pnt = [(PNT pnt)]
          | True = [(PNT (GHC.L l name))]
        workerBind _ = []

        workerExpr (pnt@(GHC.L l (GHC.HsVar name)) :: (GHC.Located (GHC.HsExpr GHC.RdrName)))
          -- | inScope pnt = [(PNT pnt)]
          | True = [(PNT (GHC.L l name))]
        workerExpr _ = []

        inScope :: GHC.Located e -> Bool
        inScope (GHC.L l _) =
          case l of
            (GHC.UnhelpfulSpan _) -> False
            (GHC.RealSrcSpan ss)  ->
              (GHC.srcSpanFile ss == fileName) &&
              (GHC.srcSpanStartLine ss == row) &&
              (col >= (GHC.srcSpanStartCol ss)) &&
              (col <= (GHC.srcSpanEndCol ss))
  -}

-- ---------------------------------------------------------------------

-- | Add identifiers to the export list of a module. If the second argument is like: Just p, then do the adding only if p occurs
-- in the export list, and the new identifiers are added right after p in the export list. Otherwise the new identifiers are add
-- to the beginning of the export list. In the case that the export list is emport, then if the third argument is True, then create
-- an explict export list to contain only the new identifiers, otherwise do nothing.
{-
addItemsToExport::( )
                 => HsModuleP                           -- The module AST.
                   -> Maybe PName                       -- The condtion identifier.
                   -> Bool                              -- Create an explicit list or not
                   -> Either [String] [HsExportEntP]    -- The identifiers to add in either String or HsExportEntP format.
                   -> m HsModuleP                       -- The result.
-}
{-
addItemsToExport::(MonadState (([PosToken],Bool), t1) m)
                 => HsModuleP                           -- The module AST.
                   -> Maybe PName                       -- The condtion identifier.
                   -> Bool                              -- Create an explicit list or not
                   -> Either [String] [HsExportEntP]    -- The identifiers to add in either String or HsExportEntP format.
                   -> m HsModuleP                       -- The result.


addItemsToExport mod _  _ (Left [])  = return mod
addItemsToExport mod _  _ (Right []) = return mod
addItemsToExport mod@(HsModule loc modName exps imps ds) (Just pn) _ ids
  =  case exps  of
       Just ents ->let (e1,e2) = break (findEntity pn) ents
                   in if e2 /=[]
                        then do ((toks,_),others)<-get
                                let e = (ghead "addVarItemInExport" e2)
                                    es = case ids of
                                          (Left is' ) ->map (\x-> (EntE (Var (nameToPNT x)))) is'
                                          (Right es') -> es'
                                let (_,endPos) = getStartEndLoc toks e
                                    (t, (_,s)) = ghead "addVarItemInExport" $ getToks (endPos,endPos) toks
                                    newToken = mkToken t endPos (s++","++ showEntities (render.ppi) es) 
                                    toks' = replaceToks toks endPos endPos [newToken]
                                put ((toks',modified),others)
                                return (HsModule loc modName (Just (e1++(e:es)++tail e2)) imps ds)
                        else return mod
       Nothing   -> return mod

addItemsToExport mod@(HsModule _ _ (Just ents) _ _) Nothing createExp ids
    = do ((toks,_),others)<-get
         let es = case ids of
                    (Left is' ) ->map (\x-> (EntE (Var (nameToPNT x)))) is'
                    (Right es') -> es'
             (t, (pos,s))=fromJust $ find isOpenBracket toks  -- s is the '('
             newToken = if ents /=[] then  (t, (pos,(s++showEntities (render.ppi) es++",")))
                                     else  (t, (pos,(s++showEntities (render.ppi) es)))
             pos'= simpPos pos
             toks' = replaceToks toks pos' pos' [newToken]
         put ((toks',modified),others)
         return mod {hsModExports=Just (es++ ents)}

addItemsToExport mod@(HsModule _  (SN modName (SrcLoc _ c row col))  Nothing _ _)  Nothing createExp ids
  =case createExp of
       True ->do ((toks,_),others)<-get
                 let es = case ids of
                               (Left is' ) ->map (\x-> (EntE (Var (nameToPNT x)))) is'
                               (Right es') -> es'
                     pos = (row,col)
                     newToken = mkToken Varid pos (modNameToStr modName++ "("
                                         ++ showEntities (render.ppi) es++")")
                     toks' = replaceToks toks pos pos [newToken]
                 put  ((toks', modified), others)
                 return mod {hsModExports=Just es}
       False ->return mod
-}

-- | Add identifiers (given by the third argument) to the explicit entity list in the declaration importing the
--   specified module name. The second argument serves as a condition: if it is like : Just p, then do the adding 
--   the if only 'p' occurs in the entity list; if it is Nothing, then do the adding as normal. This function
--   does nothing if the import declaration does not have an explicit entity list.
{-
addItemsToImport::( )
                 =>ModuleName                  -- ^ The imported module name.
                 ->Maybe PName                 -- ^ The condition identifier.
                 ->Either [String] [EntSpecP]  -- ^ The identifiers to add in either String or EntSpecP format.
                 ->t                           -- ^ The given syntax phrase.
                 ->m t                         -- ^ The result.
-}

{-
addItemsToImport::(Term t,MonadState (([PosToken],Bool),t1) m)
                 =>ModuleName                  -- ^ The imported module name.
                 ->Maybe PName                 -- ^ The condition identifier.
                 ->Either [String] [EntSpecP]  -- ^ The identifiers to add in either String or EntSpecP format.
                 ->t                           -- ^ The given syntax phrase.
                 ->m t                         -- ^ The result.

addItemsToImport serverModName pn (Left [])  t = return t
addItemsToImport serverModName pn (Right []) t = return t
addItemsToImport serverModName pn ids t
 =applyTP (full_buTP (idTP `adhocTP` inImport)) t
  where
    inImport (imp@(HsImportDecl loc m@(SN modName _) qual  as h):: HsImportDeclP)
      | serverModName == modName && (if isJust pn then findPN (fromJust pn) h else True)
       = case h of
           Nothing        -> return imp
           Just (b, ents) -> do let ents'=case ids of
                                          Left  is'  -> map (\x-> Var (nameToPNT x)) is'
                                          Right es   -> es
                                ((toks,_),others)<-get
                                let (_,endPos)=getStartEndLoc toks (glast "addItemsToImport" ents)
                                    (t,(_,s))=ghead "addItemsToImport" $ getToks (endPos,endPos) toks
                                    newToken = mkToken t endPos (s++","++showEntities (render.ppi) ents')
                                    toks'=replaceToks toks endPos endPos [newToken]
                                put ((toks',modified),others)
                                return (HsImportDecl loc m qual as (Just (b, ents++ents')))
    inImport imp = return imp
-}

-- ---------------------------------------------------------------------

-- | Adding a declaration to the declaration list of the given syntax
-- phrase(so far only adding function\/pattern binding has been
-- tested). If the second argument is Nothing, then the declaration
-- will be added to the beginning of the declaration list, but after
-- the data type declarations is there is any.
addDecl:: (SYB.Data t,HsBinds t)
        => t              -- ^ The AST.
        -> Maybe GHC.Name -- ^ If this is Just, then the declaration
                          -- will be added right after this
                          -- identifier's definition.
        -> (GHC.LHsBind GHC.Name, Maybe [PosToken])
             -- ^ The declaration to be added, in both AST and Token
             -- stream format (optional).
        -> Bool              -- ^ True means the declaration is a
                             -- toplevel declaration.
        -> RefactGhc t --[GHC.LHsBind GHC.Name]

addDecl parent pn (decl, declToks) topLevel
 = if isJust pn
     then appendDecl parent (fromJust pn) (decl, declToks)
     else if topLevel
            then addTopLevelDecl (decl, declToks) parent
            else addLocalDecl parent (decl,declToks)
 where

  -- Add a definition to the beginning of the definition declaration
  -- list, but after the data type declarations if there is any. The
  -- definition will be pretty-printed if its token stream is not
  -- provided.
  addTopLevelDecl :: (SYB.Data t, HsBinds t)
                  => (GHC.LHsBind GHC.Name, Maybe [PosToken]) -> t -> RefactGhc t
  addTopLevelDecl (decl, declToks) parent
    = do let decls = hsBinds parent
             (decls1,decls2) = break (\x->isFunOrPatBindR x {- || isTypeSig x -}) decls
         toks <- fetchToks
         let loc1 = if (not $ emptyList decls2)  -- there are function/pattern binding decls.
                    then let ((startRow,_),_) = startEndLocIncComments toks (ghead "addTopLevelDecl"  decls2)
                         in  (startRow, 1)
                    else simpPos0  -- no function/pattern binding decls in the module.
             (toks1, toks2) = if loc1==simpPos0  then (toks, [])
                                 else break (\t -> tokenPos t >= loc1) toks

             declStr = case declToks of
                        Just ts -> concatMap tokenCon ts
                        Nothing -> "\n"++(prettyprint decl)++"\n\n"
                        -- Nothing -> (prettyprint decl)++"\n\n"
             -- colOffset = if (emptyList decls) then 1 else getOffset toks $ fst (getStartEndLoc (head decls))
             colOffset = 0
         newToks <- liftIO $ tokenise (realSrcLocFromTok $ glast "addTopLevelDecl" toks1) colOffset True declStr
         let toks' = toks1 ++ newToks ++ toks2
     --    error $ show decl

         -- put ((toks',modified),((tokenRow (glast "addTopLevelDecl" newToks) -10), v2))
         putToks toks' modified
         (decl',_) <- addLocInfo (decl, newToks)
     --    error $ show decl
         -- return (replaceDecls parent (Decs (decls1++decl'++decls2) ([], [])))
         return (replaceBinds parent (decls1++[decl']++decls2))

  appendDecl :: (SYB.Data t, HsBinds t)
      => t        -- ^Original AST
      -> GHC.Name -- ^Name to add the declaration after
      -> (GHC.LHsBind GHC.Name, Maybe [PosToken]) -- ^declaration and maybe tokens
      -> RefactGhc t -- ^updated AST
  appendDecl parent pn (decl, declToks)
    = do toks <- fetchToks
         -- error ("appendDecl:(before,after)=" ++ (GHC.showPpr (before,after))) -- ++AZ++ 
         -- error (show parent ++ "----" ++ show pn ++ "-----" ++ show (decl, declToks))
         let (startPos,endPos) = startEndLocIncFowComment toks (ghead "appendDecl1" after)
             -- divide the toks into three parts.
             (toks1, toks2, toks3) = splitToks' (startPos, endPos) toks
              --get the toks defining pn
             defToks = dropWhile (\t->tokenPos t /=startPos) toks2
             offset = if topLevel
                        then 0
                        else getOffset toks $ fst (getStartEndLoc (ghead "appendDecl2" decls))

             declStr = case declToks of
                          Just ts -> concatMap tokenCon ts
                          Nothing -> prettyprint decl
             nlToken = newLnToken (glast "appendDecl3" toks2)
         -- error ("appendDecl: (offset,startEndLoc)=" ++ (show (offset, (getStartEndLoc (ghead "appendDecl2" decls))))) -- ++AZ++ debug
         newToks <- liftIO $ tokenise (realSrcLocFromTok nlToken) offset True declStr
         let --
             toks' = if  endsWithNewLn  (glast "appendDecl2" toks2)
                      then  toks1++ toks2 ++ (nlToken: newToks) ++ [nlToken]++ compressPreNewLns toks3
                      else  replaceToks toks startPos endPos (defToks++[nlToken,nlToken]++newToks)
    --     (decl',_) <- addLocInfo (decl, newToks)
         -- put ((toks',modified),((tokenRow (glast "appendDecl2" newToks) -10), v2))
         putToks toks' modified
         -- return (replaceDecls parent (Decs (before ++ [ghead "appendDecl14" after]++ decl++ tail after) ([], [])))
         return (replaceBinds parent ((before ++ [ghead "appendDecl14" after]++[decl]++ tail after) ))
      where
        decls = hsBinds parent
        (before,after) = break (defines pn) decls -- Need to handle the case that 'after' is empty?
        splitToks' (startPos, endPos) toks
           = let (ts1, ts2, ts3) = splitToks (startPos, endPos) toks
                 -- (ts11, ts12) = break hasNewLn (reverse ts1)
                 (ts11, ts12) = splitOnNewLn (reverse ts1)
             in (reverse ts12, reverse ts11++ts2, ts3)

  addLocalDecl :: (SYB.Data t, HsBinds t)
               => t -> (GHC.LHsBind GHC.Name, Maybe [PosToken])
               -> RefactGhc t
  addLocalDecl parent (newFun, newFunToks)
    =do
        toks <- fetchToks
        -- error ("addLocalDecl:(parent,localDecls)=" ++ (GHC.showPpr (parent,localDecls))) -- ++AZ++ debug
        let (startPos@(_,startCol),endPos'@(endRow',_))  --endPos' does not include the following newline or comment.
              =if (emptyList localDecls)
                   then startEndLocIncFowComment toks parent    --The 'where' clause is empty
                   else startEndLocIncFowComment toks localDecls
            -- toks1=gtail "addLocalDecl1"  $ dropWhile (\t->tokenPos t/=endPos') toks
            -- ++AZ++ toks1 : tokens after the insertion point
            --        ts1: toks1 with whitespace, comments etc removed.
            toks1=gtail "addLocalDecl1"  $ dropWhile (\t->tokenPos t<=endPos') toks
            ts1=takeWhile (\t->isWhite t && ((not.isMultiLineComment) t) && (not.hasNewLn) t)  toks1
            --nextTokPos is only used to test whether there is a 'In' or a nested comment. 
            nextTokPos= case (dropWhile (\t->isWhite t && ((not.isMultiLineComment) t) && (not.hasNewLn) t) toks1) of
                           [] -> simpPos0
                           l  -> (tokenPos.ghead "addLocalFunInToks") l
            needNewLn=if nextTokPos==simpPos0  --used to decide whether add a new line character before a introduced fun.
                      then if (emptyList toks1)
                              then True
                              else (not.endsWithNewLn) (glast "addLocalDecl" ts1)
                      else endRow'==fst nextTokPos
            --endPos@(endRow,_)=if ts1==[] then endPos'
            --                             else tokenPos (last ts1)
            -- ++AZ++ temp offset = if (emptyList localDecls) then getOffset toks startPos + 4 else getOffset toks startPos
            offset = if (emptyList localDecls)
                        then getOffset toks startPos + 4
                        else getOffset toks startPos
            nlToken = newLnToken (ghead "addLocalDecl2" toks1)

        -- error ("addLocalDecl: (head toks1) =" ++ (showToks $ [head toks1])) -- ++AZ++ debug
        -- error ("addLocalDecl: (needNewLn,nextTokPos) =" ++ (GHC.showPpr (needNewLn,nextTokPos))) -- ++AZ++ debug

        newToks <- liftIO $ tokenise (realSrcLocFromTok $ ghead "addLocalDecl3" toks1) offset True
        -- newToks <- liftIO $ tokenise (realSrcLocFromTok $ nlToken) offset True
                          -- $ if needNewLn then "\n"++newSource else newSource++"\n"
                          $ if needNewLn then newSource++"\n" else newSource++"\n"
        let nlToken2 = newLnToken (glast "addLocalDecl4" newToks)
        let oldToks'=getToks (startPos,endPos') toks
            toks'=replaceToks toks startPos endPos' (oldToks'++newToks++[nlToken2])
        (newFun',_) <- addLocInfo (newFun, newToks) -- This function calles problems because of the lexer.
        -- put ((toks',modified),((tokenRow (glast "appendDecl2" newToks) -10), v2))
        putToks toks' modified
        return (replaceBinds parent ((hsBinds parent ++ [newFun']) ))
    where
         localDecls = hsBinds parent

         newSource  = if (emptyList localDecls)
                       then "where\n"++ concatMap (\l-> "  "++l++"\n") (lines newFun')
                       else (" " ++ newFun'++"\n")
           where
            newFun' = case newFunToks of
                           Just ts -> concatMap tokenCon ts
                           Nothing -> prettyprint newFun



{- ++original++
-- | Adding a declaration to the declaration list of the given syntax phrase(so far only adding function\/pattern binding
--  has been tested).  If the second argument is Nothing, then the declaration will be added to the beginning of the
-- declaration list, but after the data type declarations is there is any.
{-addDecl::( ) =>t                -- ^ The AST.
   -> Maybe PName     -- ^ If this is Just, then the declaration will be added right after this identifier's definition.
   ->([HsDeclP], Maybe [PosToken])  -- ^ The declaration to be added, in both AST and Token stream format (optional).
   ->Bool               -- ^ True means the declaration is a toplevel declaration.
   ->m t
-}

addDecl::((MonadState (([PosToken],Bool),(Int,Int)) m), StartEndLoc t, HsDecls t, Printable t)
                    =>t-> Maybe PName
                    ->([HsDeclP], Maybe [PosToken])
                    ->Bool
                    ->m t

addDecl parent pn (decl, declToks) topLevel
 = if isJust pn
     then appendDecl parent (fromJust pn) (decl, declToks)
     else if topLevel
            then addTopLevelDecl (decl, declToks) parent
            else addLocalDecl parent (decl,declToks)
 where

  {- Add a definition to the beginning of the definition declaration list, but after the data type declarations
     if there is any. The definition will be pretty-printed if its token stream is not provided. -}
  addTopLevelDecl (decl, declToks) parent
    = do let decls = hsDecls parent
             (decls1,decls2)=break (\x->isFunOrPatBind x || isTypeSig x) decls
         ((toks,_),(v1, v2))<-get
         let loc1 = if decls2/=[]  -- there are function/pattern binding decls.
                    then let ((startRow,_),_) = startEndLocIncComments toks (ghead "addTopLevelDecl"  decls2)
                         in  (startRow, 1)
                    else simpPos0  -- no function/pattern binding decls in the module.
             (toks1, toks2) = if loc1==simpPos0  then (toks, [])
                                 else break (\t->tokenPos t==loc1) toks

             declStr = case declToks of
                        Just ts -> concatMap tokenCon ts
                        Nothing -> prettyprint decl++"\n\n"
             colOffset = if decls ==[] then 1 else getOffset toks $ fst (getStartEndLoc toks (head decls))
             newToks = tokenise (Pos 0 v1 1) colOffset True declStr
             toks' = toks1 ++ newToks ++ toks2
     --    error $ show decl

         put ((toks',modified),((tokenRow (glast "addTopLevelDecl" newToks) -10), v2))
         (decl',_) <- addLocInfo (decl, newToks)
     --    error $ show decl
         return (replaceDecls parent (Decs (decls1++decl'++decls2) ([], [])))

  appendDecl parent pn (decl, declToks)
    = do ((toks,_),(v1, v2))<-get
         -- error (show parent ++ "----" ++ show pn ++ "-----" ++ show (decl, declToks))
         let (startPos,endPos) = startEndLocIncFowComment toks (ghead "appendDecl1" after)
             -- divide the toks into three parts.
             (toks1, toks2, toks3) = splitToks' (startPos, endPos) toks
              --get the toks defining pn
             defToks = dropWhile (\t->tokenPos t /=startPos) toks2
             offset = getOffset toks $ fst (getStartEndLoc toks (ghead "appendDecl2" decls))
             declStr = case declToks of
                          Just ts -> concatMap tokenCon ts
                          Nothing -> prettyprint decl
             newToks = tokenise (Pos 0 v1 1) offset True declStr
             toks' = if  endsWithNewLn  (glast "appendDecl2" toks2)
                      then  toks1++ toks2 ++ (newLnToken: newToks) ++ [newLnToken]++ compressPreNewLns toks3
                      else  replaceToks toks startPos endPos (defToks++[newLnToken,newLnToken]++newToks)
    --     (decl',_) <- addLocInfo (decl, newToks)
         put ((toks',modified),((tokenRow (glast "appendDecl2" newToks) -10), v2))
         return (replaceDecls parent (Decs (before ++ [ghead "appendDecl14" after]++ decl++ tail after) ([], [])))
      where
        decls = hsDecls parent
        (before,after) = break (defines pn) decls -- Need to handle the case that 'after' is empty?
        splitToks' (startPos, endPos) toks
           = let (ts1, ts2, ts3) = splitToks ( startPos, endPos) toks
                 (ts11, ts12) = break hasNewLn (reverse ts1)
             in (reverse ts12, reverse ts11++ts2, ts3)

  -- This function need to be tested.
  addLocalDecl parent (newFun, newFunToks)
    =do
        ((toks,_), (v1, v2))<-get
        let (startPos@(_,startCol),endPos'@(endRow',_))  --endPos' does not include the following newline or comment.
              =if localDecls==[] then startEndLocIncFowComment toks parent    --The 'where' clause is empty
                                 else startEndLocIncFowComment toks localDecls
            toks1=gtail "addLocalDecl1"  $ dropWhile (\t->tokenPos t/=endPos') toks
            ts1=takeWhile (\t->isWhite t && ((not.isMultiLineComment) t) && (not.hasNewLn) t)  toks1
            --nextTokPos is only used to test whether there is a 'In' or a nested comment. 
            nextTokPos= case (dropWhile (\t->isWhite t && ((not.isMultiLineComment) t) && (not.hasNewLn) t) toks1) of
                           [] -> simpPos0
                           l  -> (tokenPos.ghead "addLocalFunInToks") l
            needNewLn=if nextTokPos==simpPos0  --used to decide whether add a new line character before a introduced fun.
                      then if toks1==[] then True
                                        else (not.endsWithNewLn) (last ts1)
                      else endRow'==fst nextTokPos
            --endPos@(endRow,_)=if ts1==[] then endPos'
            --                             else tokenPos (last ts1)
            offset = if localDecls == [] then getOffset toks startPos + 4 else getOffset toks startPos
            newToks = tokenise (Pos 0 v1 1) offset True
                          $ if needNewLn then "\n"++newSource else newSource++"\n"
            oldToks'=getToks (startPos,endPos') toks
            toks'=replaceToks toks startPos endPos' (oldToks'++newToks)
        (newFun',_) <- addLocInfo (newFun, newToks) -- This function calles problems because of the lexer.
        put ((toks',modified),((tokenRow (glast "appendDecl2" newToks) -10), v2))
        return (replaceDecls parent (Decs (hsDecls parent ++ newFun') ([], [])))
    where
         localDecls = hsDecls parent

         newSource  = if localDecls == []
                      then "where\n"++ concatMap (\l-> "  "++l++"\n") (lines newFun')
                      else newFun'
            where
            newFun' = case newFunToks of
                           Just ts -> concatMap tokenCon ts
                           Nothing -> prettyprint newFun

++original end++ -}
-- ---------------------------------------------------------------------

-- | add items to the hiding list of an import declaration which
-- imports the specified module.
addHiding::
    GHC.ModuleName       -- ^ The imported module name
  ->GHC.RenamedSource    -- ^ The current module
  ->[GHC.Name]           -- ^ The items to be added
  ->RefactGhc GHC.RenamedSource -- ^ The result (with token stream updated)
addHiding serverModName (g,imps,e,d) pns = do
    imps' <- mapM inImport imps
    return (g,imps',e,d)
  where
    inImport :: GHC.LImportDecl GHC.Name -> RefactGhc (GHC.LImportDecl GHC.Name)
    inImport imp@(GHC.L _ (GHC.ImportDecl (GHC.L _ modName) _qualify _source _safe isQualified _isImplicit as h))
      | serverModName == modName  && not isQualified
       = case h of
           Nothing -> do
             toks <- fetchToks
             let (startPos,endPos) = getStartEndLoc imp
                 ((GHC.L l t),s) = ghead "addHiding" $ reverse $ getToks (startPos,endPos) toks
                 start = getGhcLoc l
                 end   = getGhcLocEnd l
                 newToken = mkToken t start (s++" hiding ("++showEntities GHC.showPpr pns++")")
                 toks'= replaceToks toks start end [newToken]
             -- error ("addHiding: newToken=" ++ (showToks [newToken]) ++ " (start,end)=" ++ (show (start,end)) ++ "(startPos,endPos)=" ++ (show (startPos,endPos)) ++ " toks=" ++ (showToks toks)) -- ++AZ++ debug
             putToks toks' True
             return (replaceHiding imp (Just (True, map mkNewEnt pns )))
           Just (True, ents) -> do
             toks <- fetchToks
             let (startPos,endPos) = getStartEndLoc imp
                 ((GHC.L l t),s) = ghead "addHiding" $ reverse $ getToks (startPos,endPos) toks
                 start = getGhcLoc l
                 end   = getGhcLocEnd l
                 newToken=mkToken t start (","++showEntities GHC.showPpr pns ++s)
                 toks'=replaceToks toks start end [newToken]
             putToks toks' True
             return (replaceHiding imp  (Just (True, (map mkNewEnt  pns)++ents))) 
           Just (False, _ent)  -> return imp
    inImport x = return x

    mkNewEnt :: GHC.Name -> GHC.LIE GHC.Name
    mkNewEnt pn = (GHC.L l (GHC.IEVar pn))
      where
       filename = (GHC.mkFastString "f")
       l = GHC.mkSrcSpan (GHC.mkSrcLoc filename 1 1) (GHC.mkSrcLoc filename 1 1)

    replaceHiding (GHC.L l (GHC.ImportDecl mn q src safe isQ isImp as _h)) h1 =
         (GHC.L l (GHC.ImportDecl mn q src safe isQ isImp as h1))

{- ++AZ++ original
-- | add items to the hiding list of an import declaration which imports the specified module.
addHiding::(MonadState (([PosToken],Bool),t1) m)
            =>ModuleName           -- ^ The imported module name
            ->HsModuleP            -- ^ The current module
            ->[PName]              -- ^ The items to be added
            ->m HsModuleP          -- ^ The result
addHiding serverModName mod pns
   = applyTP (full_tdTP (idTP `adhocTP` inImport)) mod
  where
    inImport (imp@(HsImportDecl loc (SN modName _) qual  as h)::HsImportDeclP)
      | serverModName == modName  && not qual
       = case h of
           Nothing ->do ((toks,_),others)<-get
                        let (_,endPos)=getStartEndLoc toks imp
                            (t,(_,s)) = ghead "addHiding" $ getToks (endPos,endPos) toks 
                            newToken=mkToken t endPos (s++" hiding ("++showEntities pNtoName pns++")")
                            toks'=replaceToks toks endPos endPos [newToken]
                        put ((toks',modified),others)
                        return (replaceHiding imp (Just (True, map mkNewEnt pns )))
           Just (True, ents) ->do ((toks,_),others)<-get
                                  let (_,endPos)=getStartEndLoc toks imp
                                      (t, (_,s))=ghead "addHiding"  $ getToks (endPos,endPos) toks
                                      newToken=mkToken t endPos (","++showEntities pNtoName pns ++s)
                                      toks'=replaceToks toks endPos endPos [newToken]
                                  put ((toks',modified),others)
                                  return (replaceHiding imp  (Just (True, (map mkNewEnt  pns)++ents))) 
           Just (False, ent)  -> return imp
    inImport x = return x

    mkNewEnt pn = (Var (PNT pn Value (N (Just loc0))))
    replaceHiding (HsImportDecl loc modName qual as h) h1 = HsImportDecl loc modName qual as h1    
-}
-- ---------------------------------------------------------------------

addParamsToDecls::
        [GHC.LHsBind GHC.Name] -- ^ A declaration list where the function is defined and\/or used.
      ->GHC.Name    -- ^ The function name.
      ->[GHC.Name]  -- ^ The parameters to be added.
      ->Bool        -- ^ Modify the token stream or not.
      ->RefactGhc [GHC.LHsBind GHC.Name] -- ^ The result.

addParamsToDecls decls pn paramPNames modifyToks
   = if (paramPNames/=[])
        then mapM addParamToDecl decls
        else return decls
  where
   addParamToDecl :: GHC.LHsBind GHC.Name -> RefactGhc (GHC.LHsBind GHC.Name)
   -- addParamToDecl (TiDecorate.Dec (HsFunBind loc matches@((HsMatch _ fun pats rhs ds):ms)))
   addParamToDecl (GHC.L l1 (GHC.FunBind fun@(GHC.L l2 pname) i (GHC.MatchGroup matches ptt) co fvs t))
    | pname == pn
    = do matches' <-mapM addParamtoMatch matches
         -- return (TiDecorate.Dec (HsFunBind loc matches'))
         return (GHC.L l1 (GHC.FunBind (GHC.L l2 pname) i (GHC.MatchGroup matches' ptt) co fvs t))
      where
       -- addParamtoMatch (HsMatch loc fun pats rhs  decls)
       addParamtoMatch (GHC.L l (GHC.Match pats mtyp rhs))
        = do rhs' <- addActualParamsToRhs pn paramPNames rhs
             let pats' = map GHC.noLoc $ map pNtoPat paramPNames
             pats'' <- if modifyToks then do _ <- addFormalParams fun pats'
                                             return pats'
                                     else return pats'
             -- return (HsMatch loc  fun  (pats'++pats)  rhs' decls)
             return (GHC.L l (GHC.Match (pats'++pats) mtyp rhs'))

   -- addParamToDecl (TiDecorate.Dec (HsPatBind loc p rhs ds))
   addParamToDecl (GHC.L l1 (GHC.PatBind (GHC.L l2 pat@(GHC.VarPat p)) rhs ty fvs t))
     | p == pn
       = do rhs'<-addActualParamsToRhs pn paramPNames rhs
            let pats' = map GHC.noLoc $ map pNtoPat paramPNames
            pats'' <- if modifyToks  then do _ <- addFormalParams pat pats'
                                             return pats'
                                     else return pats'
            -- return (TiDecorate.Dec (HsFunBind loc [HsMatch loc (patToPNT p) pats' rhs ds]))
            return (GHC.L l1 (GHC.PatBind (GHC.L l2 pat) rhs ty fvs t))
   addParamToDecl x=return x

   addActualParamsToRhs :: (SYB.Typeable t, SYB.Data t) =>
                        GHC.Name -> [GHC.Name] -> t -> RefactGhc t
   addActualParamsToRhs pn paramPNames rhs = do
    r <- everywhereMStaged SYB.Renamer (SYB.mkM worker) rhs
    return r
    -- = applyTP (stop_tdTP (failTP `adhocTP` worker))
     where
       worker :: (GHC.Located (GHC.HsExpr GHC.Name)) -> RefactGhc (GHC.Located (GHC.HsExpr GHC.Name))
{-
       worker (GHC.L l1 (GHC.HsApp e1 e2))
        -- | pname == pn
        | True
         = do
              error ("got here:addActualParamsToRhs:" ++ (GHC.showPpr (e1,e2)))
-}
       worker (GHC.L l1 (GHC.HsApp (GHC.L l2 (GHC.HsVar pname)) e2))
        -- | pname == pn
        | True
         = do
              -- error "got here:addActualParamsToRhs"
              let newExp = (GHC.L l1 (GHC.HsApp (GHC.L l2 (GHC.HsVar pname)) (foldl addParamToExp e2 paramPNames)))
              if modifyToks then do _ <- updateToks e2 newExp prettyprint
                                    -- return newExp'
                                    return newExp
                            else return newExp
       -- worker x = do
       --    liftIO $ putStrLn ("addActualParamsToRhs:" ++ (GHC.showPpr x))
       --    return x
       worker x = return x

       addParamToExp :: (GHC.LHsExpr GHC.Name) -> GHC.Name -> (GHC.LHsExpr GHC.Name)
       -- addParamToExp  exp param=(TiDecorate.Exp (HsApp exp param))
       addParamToExp  exp param = GHC.noLoc (GHC.HsApp exp (GHC.noLoc (GHC.HsVar param)))



       {-
       worker exp@(GHC.HsVar pname)
        | pname==pn
         = do -- let newExp=TiDecorate.Exp (HsParen (foldl addParamToExp exp (map pNtoExp paramPNames)))
              let newExp=exp -- TiDecorate.Exp (HsParen (foldl addParamToExp exp (map pNtoExp paramPNames)))
              if modifyToks then do -- (newExp', _) <- updateToks exp newExp prettyprint
                                    -- return newExp'
                                    return newExp
                            else return newExp
       worker x = return x
       -}

{-
zz ab = 1 + toplevel ab

       (L {test/testdata/DupDef/Dd1.hs:34:1-23}
        (FunBind
         (L {test/testdata/DupDef/Dd1.hs:34:1-2} {Name: DupDef.Dd1.zz})
         (False)
         (MatchGroup
          [
           (L {test/testdata/DupDef/Dd1.hs:34:1-23}
            (Match
             [
              (L {test/testdata/DupDef/Dd1.hs:34:4-5}
               (VarPat {Name: ab}))]
             (Nothing)
             (GRHSs
              [
               (L {test/testdata/DupDef/Dd1.hs:34:9-23}
                (GRHS
                 []
                 (L {test/testdata/DupDef/Dd1.hs:34:9-23}
                  (OpApp
                   (L {test/testdata/DupDef/Dd1.hs:34:9}
                    (HsOverLit
                     (OverLit
                      (HsIntegral
                       (1))
                      (False)
                      (HsVar {Name: GHC.Num.fromInteger}) {!type placeholder here?!})))
                   (L {test/testdata/DupDef/Dd1.hs:34:11}
                    (HsVar {Name: GHC.Num.+})) {!fixity placeholder here?!}
                   (L {test/testdata/DupDef/Dd1.hs:34:13-23}
                    (HsApp
                     (L {test/testdata/DupDef/Dd1.hs:34:13-20}
                      (HsVar {Name: DupDef.Dd1.toplevel}))
                     (L {test/testdata/DupDef/Dd1.hs:34:22-23}
                      (HsVar {Name: ab}))))))))]
              (EmptyLocalBinds))))] {!type placeholder here?!})
         (WpHole) {!NameSet placeholder here!}
         (Nothing)))

----------

zz ab = toplevel ab

       (L {test/testdata/DupDef/Dd1.hs:34:1-19}
        (FunBind
         (L {test/testdata/DupDef/Dd1.hs:34:1-2} {Name: DupDef.Dd1.zz})
         (False)
         (MatchGroup
          [
           (L {test/testdata/DupDef/Dd1.hs:34:1-19}
            (Match
             [
              (L {test/testdata/DupDef/Dd1.hs:34:4-5}
               (VarPat {Name: ab}))]
             (Nothing)
             (GRHSs
              [
               (L {test/testdata/DupDef/Dd1.hs:34:9-19}
                (GRHS
                 []
                 (L {test/testdata/DupDef/Dd1.hs:34:9-19}
                  (HsApp
                   (L {test/testdata/DupDef/Dd1.hs:34:9-16}
                    (HsVar {Name: DupDef.Dd1.toplevel}))
                   (L {test/testdata/DupDef/Dd1.hs:34:18-19}
                    (HsVar {Name: ab}))))))]
              (EmptyLocalBinds))))] {!type placeholder here?!})
         (WpHole) {!NameSet placeholder here!}
         (Nothing)))

-}


{-
   addActualParamsToRhs pn paramPNames
    = applyTP (stop_tdTP (failTP `adhocTP` worker))
     where
       worker exp@(TiDecorate.Exp (HsId (HsVar (PNT pname ty loc))))
        | pname==pn
         = do let newExp=TiDecorate.Exp (HsParen (foldl addParamToExp exp (map pNtoExp paramPNames)))
              if modifyToks then do (newExp', _) <- updateToks exp newExp prettyprint
                                    return newExp'
                            else return newExp
       worker x =mzero

       addParamToExp  exp param=(TiDecorate.Exp (HsApp exp param))
-}


{- ++AZ++ original
{-
addParamsToDecls::(MonadPlus m)
               => [HsDeclP]   -- ^ A declaration list where the function is defined and\/or used.
                  ->PName     -- ^ The function name.
                  ->[PName]   -- ^ The parameters to be added.
                  ->Bool      -- ^ Modify the token stream or not.
                  ->m [HsDeclP] -- ^ The result.
-}

addParamsToDecls::(MonadPlus m, (MonadState (([PosToken], Bool), (Int,Int)) m))
               => [HsDeclP]   -- ^ A declaration list where the function is defined and\/or used.
                  ->PName     -- ^ The function name.
                  ->[PName]   -- ^ The parameters to be added.
                  ->Bool      -- ^ Modify the token stream or not.
                  ->m [HsDeclP] -- ^ The result.

addParamsToDecls decls pn paramPNames modifyToks
   = if (paramPNames/=[])
        then mapM addParamToDecl decls
        else return decls
  where
   addParamToDecl (TiDecorate.Dec (HsFunBind loc matches@((HsMatch _ fun pats rhs ds):ms)))
    | pNTtoPN fun == pn
    = do matches'<-mapM addParamtoMatch matches
         return (TiDecorate.Dec (HsFunBind loc matches'))
      where
       addParamtoMatch (HsMatch loc  fun  pats rhs  decls)
        = do rhs'<-addActualParamsToRhs pn paramPNames rhs
             let pats' = map pNtoPat paramPNames
             pats'' <- if modifyToks then do (p, _)<-addFormalParams fun pats'
                                             return p
                                     else return pats'
             return (HsMatch loc  fun  (pats'++pats)  rhs' decls)

   addParamToDecl (TiDecorate.Dec (HsPatBind loc p rhs ds))
     |patToPN p == pn
       = do rhs'<-addActualParamsToRhs pn paramPNames rhs
            let pats' = map pNtoPat paramPNames
            pats'' <- if modifyToks  then do (p, _) <-addFormalParams p pats'
                                             return p
                                     else return pats'
            return (TiDecorate.Dec (HsFunBind loc [HsMatch loc (patToPNT p) pats' rhs ds]))
   addParamToDecl x=return x

   addActualParamsToRhs pn paramPNames
    = applyTP (stop_tdTP (failTP `adhocTP` worker))
     where
       worker exp@(TiDecorate.Exp (HsId (HsVar (PNT pname ty loc))))
        | pname==pn
         = do let newExp=TiDecorate.Exp (HsParen (foldl addParamToExp exp (map pNtoExp paramPNames)))
              if modifyToks then do (newExp', _) <- updateToks exp newExp prettyprint
                                    return newExp'
                            else return newExp
       worker x =mzero

       addParamToExp  exp param=(TiDecorate.Exp (HsApp exp param))



-}




-- | Remove those specified items from the entity list in the import declaration.
{-
 rmItemsFromImport::( )
                   =>HsModuleP    -- ^ The module AST
                   ->[PName]      -- ^ The items to be removed
                   ->m HsModuleP  -- ^ The result
-}

{-
rmItemsFromImport::(MonadState (([PosToken],Bool),t1) m)
                   =>HsModuleP    -- ^ The module AST
                   ->[PName]      -- ^ The items to be removed
                   ->m HsModuleP  -- ^ The result


rmItemsFromImport mod pns
  = applyTP (full_buTP (idTP `adhocTP` inImport)) mod
   where
     inImport (imp@(HsImportDecl loc modName qual  as h)::HsImportDeclP)
      | any (flip findEntity imp) pns
       = case h of
           Just (b, ents) ->
             do let matchedEnts=findEnts pns ents
                if  matchedEnts==[]
                  then return imp
                  else if length matchedEnts == length ents
                         then do ((toks,_),others)<-get
                                 let (startPos,endPos)=getStartEndLoc toks ents
                                     toks'=deleteToks toks startPos endPos
                                 put ((toks',modified),others)
                                 return (HsImportDecl loc modName qual as (Just (b,[])))
                         else do ((toks,_),others)<-get
                                 let remainedEnts=concatMap (\pn->filter (not.match pn) ents) pns 
                                     toks'=foldl deleteEnt toks $ map (getStartEndLoc toks) matchedEnts
                                 put ((toks',modified),others)
                                 return (HsImportDecl loc modName qual as (Just (b, remainedEnts)))
           _ ->return imp
     inImport x = return x

     findEnts pns ents =nub $ concatMap (\pn->filter (match pn) ents) pns

     -- this function does not check this sub entities of the ListSubs. any problems?
     match::PName -> EntSpec PNT ->Bool
     match pn (Var pnt) = pNTtoPN pnt == pn
     match pn (Abs pnt) = pNTtoPN pnt == pn
     match pn (AllSubs pnt) = pNTtoPN pnt == pn
     match pn (ListSubs pnt _) = pNTtoPN pnt == pn
-}


{-
-- | Remove the sub entities of a type constructor or class from the export list.
rmSubEntsFromExport::(MonadState (([PosToken],Bool),(Int,Int)) m)
                     =>PName       -- ^ The type constructor or class name
                     ->HsModuleP   -- ^ The module AST
                     ->m HsModuleP -- ^ The result
rmSubEntsFromExport typeCon
  = applyTP (full_buTP (idTP `adhocTP` inEntSpec))
  where
   inEntSpec (ent@(AllSubs pnt)::EntSpec PNT)
     | pNTtoPN pnt == typeCon
      =do (ent', _)<-updateToks ent (Abs pnt) prettyprint
          return ent'
   inEntSpec (ent@(ListSubs pnt _))
     | pNTtoPN pnt == typeCon
     = do (ent', _) <- updateToks ent (Abs pnt) prettyprint
          return ent'
   inEntSpec ent = return ent
-}

---------------------------------------------------------------------------------------
-- | Remove the specified entities from the module's exports. The entities can be specified in either of two formats:
-- i.e. either specify the module names and identifier names to be removed, so just given the exact AST for these entities.
{-rmItemsFromExport::( )
                   =>HsModuleP                                      -- ^ The module AST.
                    ->Either ([ModuleName],[PName]) [HsExportEntP]  -- ^ The entities to remove. 
                    ->m HsModuleP                                   -- ^ The result.
-}
{-
rmItemsFromExport::(MonadState (([PosToken],Bool),t1) m)
                   =>HsModuleP                                      -- ^ The module AST.
                    ->Either ([ModuleName],[PName]) [HsExportEntP]  -- ^ The entities to remove.
                    ->m HsModuleP                                   -- ^ The result.

rmItemsFromExport mod@(HsModule loc modName exps imps ds)  (Left (modNames, pns))
  =if isNothing exps
     then return mod
     else do let ents =findEnts (modNames, pns) (fromJust exps)
             rmItemsFromExport mod (Right ents)
  where
    findEnts (modNames, pns) ents
      =let ms = concatMap (\m ->filter (\e -> case e of
                                         ModuleE (SN m' _) -> m==m'
                                         EntE e'    -> False) ents) modNames
           es =concatMap (\pn->filter (\e ->case e of
                                            ModuleE _ -> False
                                            EntE e'    -> match pn e') ents) pns
       in (ms++es)
    match::PName -> EntSpec PNT ->Bool
    match pn (Var pnt) = pNTtoPN pnt == pn
    match pn (Abs pnt) = pNTtoPN pnt == pn
    match pn (AllSubs pnt) = pNTtoPN pnt == pn
    match pn (ListSubs pnt _) = pNTtoPN pnt == pn

rmItemsFromExport mod@(HsModule loc modName exps@(Just es) imps ds) (Right ents)
  = do exps'<- if ents==[]
                  then return exps
                  else if length ents == length es
                         then do ((toks,_),others)<-get
                                 let (startPos,endPos) = getStartEndLoc toks ents
                                     toks'= deleteToks toks startPos endPos
                                 put ((toks',modified),others)
                                 return (Just [] )  -- should not remove the empty bracket!!!
                         else do ((toks,_),others)<-get
                                 let toks' = foldl deleteEnt toks $ map (getStartEndLoc toks) ents
                                 put ((toks',modified),others)
                                 return (Just (es \\ ents))
       return (HsModule loc modName exps' imps ds)
rmItemsFromExport mod _ = return mod
-}

{-
--This function is only used by this module, and should not be exported.
deleteEnt toks (startPos, endPos)
  = let (toks1,toks2)=break (\t->tokenPos t==startPos) toks
        previousTok=ghead "deleteEnt" $ dropWhile isWhiteSpace $ reverse toks1
        toks' = dropWhile isWhiteSpace $ gtail "deleteEnts" $ dropWhile (\t->tokenPos t/=endPos) toks2
        nextTok = ghead "deleteEnt" toks'
        startPos'=if isComma previousTok && (not (isComma nextTok)) then tokenPos previousTok else startPos
    in if isComma nextTok
         then let remainedToks = tail toks'
              in if remainedToks /= []
                   then let whites = takeWhile isWhiteSpace remainedToks
                        in if whites /= [] then deleteToks toks startPos' (tokenPos (last whites))
                                           else deleteToks toks startPos' (tokenPos nextTok)
                   else deleteToks toks startPos' (tokenPos nextTok)
         else deleteToks toks startPos' endPos
-}

-- ---------------------------------------------------------------------

-- | Duplicate a functon\/pattern binding declaration under a new name
-- right after the original one. Also updates the token stream.
duplicateDecl::(SYB.Data t) =>
  [GHC.LHsBind GHC.Name]  -- ^ The declaration list
  ->t                     -- ^ Any signatures are in here
  ->GHC.Name              -- ^ The identifier whose definition is to be duplicated
  ->GHC.Name              -- ^ The new name (possibly qualified)
  ->RefactGhc [GHC.LHsBind GHC.Name]  -- ^ The result
{- there maybe fun/simple pattern binding and type signature in the
duplicated decls function binding, and type signature are handled
differently here: the comment and layout in function binding are
preserved.The type signature is outputted by pretty printer, so the
comments and layout are NOT preserved.
 -}
duplicateDecl decls sigs n newFunName
 = do
      toks <- fetchToks
      let (startPos, endPos) = startEndLocIncComments toks funBinding
          {-take those tokens before (and include) the function
            binding and its following white tokens before the 'new line' token.
            (some times the function may be followed by comments) -}
          toks1 = ts1++[ghead "duplicateDecl" ts2]
                    where (ts1, ts2) = break (\t -> (tokenPos t) > endPos) toks
          -- take those token after (and include) the function binding
          toks2 = dropWhile (\t -> tokenPos t /= startPos {- || isNewLn t -}) toks

      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:toks1=" ++ (showToks toks1)) -- ++AZ++ debug
      putToks toks2 True

      --rename the function name to the new name, and update token
      --stream (toks2, just updated) as well, in the monad
      funBinding' <- renamePN n newFunName True funBinding
      --rename function name in type signature  without adjusting the token stream

      -- typeSig'  <- renamePN pn Nothing newFunName False typeSig
      typeSig'  <- renamePN n newFunName False typeSig

      -- Get the updated token stream
      toks3 <- fetchToks

      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:(fst (getStartEndLoc funBinding))=" ++ (show (fst $ getStartEndLoc funBinding))) -- ++AZ++ debug 12
      -- error ("TypeUtils.duplicateDecl:(funBinding)=" ++ (GHC.showPpr funBinding)) -- ++AZ++ debug 12
      -- error ("TypeUtils.duplicateDecl:(fst (getStartEndLoc funBinding))=" ++ (show (fst $ getStartEndLoc funBinding))) -- ++AZ++ debug 12

      let offset = getOffset toks (fst (getStartEndLoc funBinding))
          newLineTok = if ((not (emptyList toks1)) {-&& endsWithNewLn (glast "doDuplicating" toks1 -})
                         then [newLnToken (last toks1)]
                         else [newLnToken (last toks1), newLnToken (last toks1)]

          toks'= if (not $ emptyList typeSig)
                 then let offset = tokenCol ((ghead "doDuplicating 1") (dropWhile (\t->isWhite t) toks3))
                          -- (GHC.L l t,s) = glast "doDuplicating" toks1
                          (GHC.L lf t,_s) = ghead "doDuplicating 2" $ getToks (getStartEndLoc funBinding) toks
                          (GHC.L ll _,_) = head newLineTok
                          (_,col) = getGhcLoc lf
                          (line,_) = getGhcLoc ll
                          -- (_line,col) = (fst (getStartEndLoc funBinding))

                          -- newToken = mkToken t start (prettyprint $ ghead "duplicateDecl" typeSig')
                          newToken = mkToken t (line,col) (prettyprint $ ghead "duplicateDecl" typeSig')
                          newLineTokAfter = [newLnToken newToken]

                          -- sigSource = concatMap (\s->replicate (offset-1) ' '++s++"\n")((lines.render.ppi) typeSig')
                          -- t = mkToken Whitespace (0,0) sigSource
                      -- in  (toks1++newLineTok++[t]++(whiteSpacesToken (0,0) (snd startPos-1))++toks3)
                      -- in  (toks1++newLineTok++[newToken]++newLineTok++toks3)
                      in  (toks1++newLineTok++[newToken]++newLineTokAfter++toks3)
                 else  (toks1++newLineTok++toks3)

          {- toks'= if typeSig/=[]
                 then let offset = tokenCol ((ghead "doDuplicating") (dropWhile (\t->isWhite t) toks3))
                          sigSource = concatMap (\s->replicate (offset-1) ' '++s++"\n")((lines.render.ppi) typeSig')
                          t = mkToken Whitespace (0,0) sigSource
                      in  (toks1++newLineTok++[t]++(whiteSpacesToken (0,0) (snd startPos-1))++toks3)
                 else  (toks1++newLineTok++(whiteSpacesToken (0,0) (snd startPos-1))++toks3) 
          -}

      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:(offset)=" ++ (show offset)) -- ++AZ++ debug 12
      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:(fst (getStartEndLoc funBinding))=" ++ (show (fst $ getStartEndLoc funBinding))) -- ++AZ++ debug 12
      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:(last toks1)=" ++ (showToks [last toks1])) -- ++AZ++ debug 19
      -- liftIO $ putStrLn ("TypeUtils.duplicateDecl:newLineTok=" ++ (showToks newLineTok)) -- ++AZ++ debug
      putToks toks' True
      -- return (typeSig'++funBinding') -- ++AZ++ TODO: reinstate this
      return funBinding'
     where
       declsToDup = definingDeclsNames [n] decls True False -- ++AZ++ should recursive be set true?
       funBinding = filter isFunOrPatBindR declsToDup     --get the fun binding.
       typeSig = definingSigsNames [n] sigs


{- ++ original ++
{- ********* IMPORTANT : THIS FUNCTION SHOULD BE UPDATED TO THE NEW TOKEN STREAM METHOD ****** -}
-- | Duplicate a functon\/pattern binding declaration under a new name right after the original one.
duplicateDecl::(MonadState (([PosToken],Bool),t1) m)
                 =>[HsDeclP]            -- ^ The declaration list
                 ->PName                -- ^ The identifier whose definition is going to be duplicated
                 ->String               -- ^ The new name
                 ->m [HsDeclP]          -- ^ The result
{-there maybe fun/simple pattern binding and type signature in the duplicated decls
  function binding, and type signature are handled differently here: the comment and layout
  in function binding are preserved.The type signature is output ted by pretty printer, so
  the comments and layout are NOT preserved.
 -}
duplicateDecl decls pn newFunName
 = do ((toks,_), others)<-get
      let (startPos, endPos) =startEndLocIncComments toks funBinding
          {-take those tokens before (and include) the function binding and its following
            white tokens before the 'new line' token. (some times the function may be followed by 
            comments) -}
          toks1 = let (ts1, ts2) =break (\t->tokenPos t==endPos) toks in ts1++[ghead "duplicateDecl" ts2]
          --take those token after (and include) the function binding
          toks2 = dropWhile (\t->tokenPos t/=startPos || isNewLn t) toks
      put((toks2,modified), others)
      --rename the function name to the new name, and update token stream as well
      funBinding'<-renamePN pn Nothing newFunName True funBinding
      --rename function name in type signature  without adjusting the token stream
      typeSig'  <- renamePN pn Nothing newFunName False typeSig
      ((toks2,_), others)<-get
      let offset = getOffset toks (fst (startEndLoc toks funBinding))
          newLineTok = if toks1/=[] && endsWithNewLn (glast "doDuplicating" toks1)
                         then [newLnToken]
                         else [newLnToken,newLnToken]
          toks'= if typeSig/=[]
                 then let offset = tokenCol ((ghead "doDuplicating") (dropWhile (\t->isWhite t) toks2))
                          sigSource = concatMap (\s->replicate (offset-1) ' '++s++"\n")((lines.render.ppi) typeSig')
                          t = mkToken Whitespace (0,0) sigSource
                      in  (toks1++newLineTok++[t]++(whiteSpacesToken (0,0) (snd startPos-1))++toks2)
                 else (toks1++newLineTok++(whiteSpacesToken (0,0) (snd startPos-1))++toks2) 
      put ((toks',modified),others)
      return (typeSig'++funBinding')
     where
       declsToDup = definingDecls [pn] decls True False
       funBinding = filter isFunOrPatBind declsToDup     --get the fun binding.
       typeSig    = filter isTypeSig declsToDup      --get the type signature.


-}

-- ---------------------------------------------------------------------
--------------------------------TRY TO REMOVE THIS FUNCTION---------------------


moveDecl:: (HsBinds t)
     => [GHC.Name]     -- ^ The identifier(s) whose defining
                       -- declaration is to be moved. List is used to
                       -- handle pattern bindings where multiple
                       -- identifiers are defined.
     -> t              -- ^ The syntax phrase where the declaration is
                       -- going to be moved to.
     -> Bool           -- ^ True mean the function\/pattern binding
                       -- being moved is going to be at the same level
                       -- with t. Otherwise it will be a local
                       -- declaration of t.
     -- -> [HsDeclP]      -- ^ The declaration list where the
                       -- definition\/pattern binding originally
                       -- exists.
     -> [GHC.LHsBind GHC.Name]      -- ^ The declaration list where
                                    -- the definition\/pattern binding
                                    -- originally exists.
     -- -> t2             -- ^ The declaration list where the
                       -- definition\/pattern binding originally
                       -- exists.
     -> Bool           -- ^ True means the type signature will not be
                       -- discarded.
     -> RefactGhc t    -- ^ The result.

moveDecl pns dest sameLevel decls incSig
   -- = error "undefined moveDecl"
   {- ++AZ++ WIP, sort out getDeclToks first -}
   = do ts <- fetchToks
        let defToks' =(getDeclToks (ghead "moveDecl:0" pns) True decls ts)
            defToks  =whiteSpaceTokens (tokenRow (ghead "moveDecl" defToks'),0)
                                       -- do not use tokenCol here. should count the whilte spaces.
                                       (tokenCol (ghead "moveDecl2" defToks') -1) ++ defToks'
            movedDecls = definingDeclsNames pns decls True False
        decls'<-rmDecl (ghead "moveDecl3"  pns) False =<<foldM (flip rmTypeSig) decls pns
        addDecl dest Nothing (ghead "moveDecl" movedDecls, Just defToks) False
   {- ++WIP end++ -}

{- ++AZ++ original
{-
moveDecl::(CanHaveWhereClause t,DeclStartLoc t, Term t,Printable t,MonadPlus m,
           MonadState (([PosToken],Bool),(Int, Int)) m)
     => [PName]        -- ^ The identifier(s) whose defining declaration is to be moved. List is used to handle pattern bindings where multiple identifiers are defined.
     -> t              -- ^ The syntax phrase where the declaration is going to be moved to.
     -> Bool           -- ^ True mean the function\/pattern binding being moved is going to be at the same level with t. Otherwise it will be a local declaration of t.
     -> [HsDeclP]      -- ^ The declaration list where the definition\/pattern binding originally exists.
     -> Bool           -- ^ True means the type signature will not be discarded.
     -> m t            -- ^ The result.
-}
moveDecl pns dest sameLevel decls incSig
   = do ((ts,_),_)<-get
        let defToks' =(getDeclToks (ghead "moveDecl:0" pns) True decls ts)
            defToks  =whiteSpaceTokens (tokenRow (ghead "moveDecl" defToks'),0)
                                       -- do not use tokenCol here. should count the whilte spaces.
                                       (tokenCol (ghead "moveDecl2" defToks') -1) ++ defToks'
            movedDecls = definingDecls pns decls True False
        decls'<-rmDecl (ghead "moveDecl3"  pns) False =<<foldM (flip rmTypeSig) decls pns
        addDecl dest Nothing (movedDecls, Just defToks) False

-}

-- ---------------------------------------------------------------------

-- | Remove the declaration (and the type signature is the second
-- parameter is True) that defines the given identifier from the
-- declaration list.
rmDecl:: (SYB.Data t)
        =>GHC.Name     -- ^ The identifier whose definition is to be removed.
        ->Bool         -- ^ True means including the type signature.
        ->t            -- ^ The declaration list.
        -> RefactGhc t -- ^ The result.
rmDecl pn incSig t = do
  t'  <- everywhereMStaged SYB.Renamer (SYB.mkM inDecls) t
  t'' <- if incSig then rmTypeSig pn t'
                   else return t'
  return t''
  where
    inDecls (decls::[GHC.LHsBind GHC.Name])
      | not $ emptyList (snd (break (defines pn) decls)) -- /=[]
      = do let (_decls1, decls2) = break (defines pn) decls
               decl = ghead "rmDecl" decls2
           -- error $ (render.ppi) t -- ecl ++ (show decl)
           topLevel <- isTopLevelPN pn
           case topLevel of
                     True   -> rmTopLevelDecl decl decls
                     False  -> rmLocalDecl decl decls
    inDecls x = return x

    rmTopLevelDecl :: GHC.LHsBind GHC.Name -> [GHC.LHsBind GHC.Name]
                -> RefactGhc [GHC.LHsBind GHC.Name]
    rmTopLevelDecl decl decls
      =do toks <- fetchToks
          let (startLoc, endLoc)=startEndLocIncComments toks decl
              toks'= deleteToks toks startLoc endLoc
          putToks toks' modified
          let (decls1, decls2) = break (defines pn) decls
              decls2' = gtail "rmLocalDecl 1" decls2
          return $ (decls1 ++ decls2')
          -- return (decls \\ [decl])

  {- The difference between removing a top level declaration and a
     local declaration is: if the local declaration to be removed is
     the only declaration in current declaration list, then the 'where'/
     'let'/'in' enclosing this declaration should also be removed. Whereas,
     when a only top level decl is removed, the 'where' can not be removed.
  -}

    -- |Remove a location declaration that defines pn.
    rmLocalDecl :: GHC.LHsBind GHC.Name -> [GHC.LHsBind GHC.Name]
                -> RefactGhc [GHC.LHsBind GHC.Name]
    rmLocalDecl decl decls
     = do
         toks <- fetchToks
         let (startPos,endPos) = getStartEndLoc decl   --startEndLoc toks decl
             (startPos',endPos')=startEndLocIncComments toks decl
             --(startPos',endPos')=startEndLocIncFowComment toks decl
             toks'=if length decls==1  --only one decl, which means the accompaning 'where',
                                       --'let' or'in' should be removed too.
                   then let (toks1,toks2)=break (\t->tokenPos t==startPos) toks --devide the token stream.
                              --get the  'where' or 'let' token
                            rvToks1 = dropWhile (not.isWhereOrLet) (reverse toks1)
                            --There must be a 'where' or 'let', so rvToks1 can not be empty.
                            whereOrLet=ghead "rmLocalFunPatBind:whereOrLet" rvToks1
                            --drop the 'where' 'or 'let' token
                            toks1'=takeWhile (\t->tokenPos t/=tokenPos whereOrLet) toks1
                            --remove the declaration from the token stream.
                            toks2'=gtail "rmLocalDecl 2" $ dropWhile (\t->tokenPos t<endPos') toks2
                            --get the remained tokens after the removed declaration.
                            remainedToks=dropWhile isWhite toks2'
                        in if (emptyList remainedToks)
                             then --the removed declaration is the last decl in the file.
                                  (compressEndNewLns toks1'++ compressPreNewLns toks2')
                             else if --remainedToks/=[], so no problem with head.
                                    isIn (ghead "rmLocalDecl:isIn"  remainedToks)
                                         || isComma (ghead "rmLocalDecl:isComma" remainedToks)
                                        --There is a 'In' after the removed declaration.
                                   then if isWhere whereOrLet
                                           then deleteToks toks (tokenPos whereOrLet) endPos'
                                           else deleteToks toks (tokenPos whereOrLet)
                                                   $ tokenPos (ghead "rmLocalDecl:tokenPos" remainedToks)
                                        --delete the decl and adjust the layout
                                   else if isCloseSquareBracket (ghead "rmLocalDecl:isCloseSquareBracker" remainedToks) &&
                                           (isBar.(ghead "rmLocalDecl:isBar")) (dropWhile isWhite (tail rvToks1))
                                         then deleteToks toks (tokenPos((ghead "rmLocalDecl")
                                                        (dropWhile isWhite (tail rvToks1)))) endPos'
                                         else deleteToks toks (tokenPos whereOrLet) endPos'
                        --there are more than one decls
                   else  deleteToks toks startPos' endPos'
         putToks toks' modified --Change the above endPos' to endPos will not delete the following comments.
         -- return $ (decls \\ [decl])

         let (decls1, decls2) = break (defines pn) decls
             decls2' = gtail "rmLocalDecl 3" decls2
         return $ (decls1 ++ decls2')


{- ++ original ++

{-
rmDecl::(MonadState (([PosToken],Bool),t1) m)
        =>PName       -- ^ The identifier whose definition is to be removed.
        ->Bool        -- ^ True means including the type signature.
        ->[HsDeclP]   -- ^ The declaration list.
        -> m [HsDeclP]-- ^ The result.
-}
rmDecl pn incSig t = applyTP (once_tdTP (failTP `adhocTP` inDecls)) t
  where
    inDecls (decls::[HsDeclP])
      | snd (break (defines pn) decls) /=[]
      = do let (decls1, decls2) = break (defines pn) decls
               decl = ghead "rmDecl" decls2
           -- error $ (render.ppi) t -- ecl ++ (show decl)
           case isTopLevelPN  pn of
                     True   -> if incSig then rmTopLevelDecl decl =<< rmTypeSig pn decls
                                         else rmTopLevelDecl decl decls
                     False  -> if incSig then rmLocalDecl decl =<< rmTypeSig pn decls
                                         else rmLocalDecl decl decls
    inDecls x = mzero
    rmTopLevelDecl decl decls
      =do ((toks,_),others)<-get
          let (startLoc, endLoc)=startEndLocIncComments toks decl
              toks'=deleteToks toks startLoc endLoc
          put ((toks',modified),others)
          return (decls \\ [decl])

  {- The difference between removing a top level declaration and a local declaration is:
     if the local declaration to be removed is the only declaration in current declaration list,
     then the 'where'/ 'let'/'in' enclosing this declaration should also be removed.
     Whereas, when a only top level decl is removed, the 'where' can not be removed.
   -}
   -- |Remove a location declaration that defines pn.
    rmLocalDecl decl decls
     =do ((toks,_),others)<-get
         let (startPos,endPos)=getStartEndLoc toks decl   --startEndLoc toks decl
             (startPos',endPos')=startEndLocIncComments toks decl
             --(startPos',endPos')=startEndLocIncFowComment toks decl
             toks'=if length decls==1  --only one decl, which means the accompaning 'where',
                                       --'let' or'in' should be removed too.
                   then let (toks1,toks2)=break (\t->tokenPos t==startPos) toks --devide the token stream.
                              --get the  'where' or 'let' token
                            rvToks1=dropWhile (not.isWhereOrLet) (reverse toks1)
                            --There must be a 'where' or 'let', so rvToks1 can not be empty.
                            whereOrLet=ghead "rmLocalFunPatBind:whereOrLet" rvToks1
                            --drop the 'where' 'or 'let' token
                            toks1'=takeWhile (\t->tokenPos t/=tokenPos whereOrLet) toks1
                            --remove the declaration from the token stream.
                            toks2'=gtail "rmLocalDecl" $ dropWhile (\t->tokenPos t/=endPos') toks2
                            --get the remained tokens after the removed declaration.
                            remainedToks=dropWhile isWhite toks2'
                        in if remainedToks==[]
                             then --the removed declaration is the last decl in the file.
                                  (compressEndNewLns toks1'++ compressPreNewLns toks2')
                             else if --remainedToks/=[], so no problem with head.
                                    isIn (ghead "rmLocalDecl:isIn"  remainedToks)
                                         || isComma (ghead "rmLocalDecl:isComma" remainedToks)
                                        --There is a 'In' after the removed declaration.
                                   then if isWhere whereOrLet
                                           then deleteToks toks (tokenPos whereOrLet) endPos'
                                           else deleteToks toks (tokenPos whereOrLet)
                                                   $ tokenPos (ghead "rmLocalDecl:tokenPos" remainedToks)
                                        --delete the decl and adjust the layout
                                   else if isCloseSquareBracket (ghead "rmLocalDecl:isCloseSquareBracker" remainedToks) &&
                                           (isBar.(ghead "rmLocalDecl:isBar")) (dropWhile isWhite (tail rvToks1))
                                         then deleteToks toks (tokenPos((ghead "rmLocalDecl")
                                                        (dropWhile isWhite (tail rvToks1)))) endPos'
                                         else deleteToks toks (tokenPos whereOrLet) endPos'
                        --there are more than one decls
                   else  deleteToks toks startPos' endPos'
         put ((toks',modified),others)  --Change the above endPos' to endPos will not delete the following comments.
         return $ (decls \\ [decl])
-}

-- ---------------------------------------------------------------------


-- | Remove the type signature that defines the given identifier's
-- type from the declaration list.
rmTypeSig :: (SYB.Data t) =>
         GHC.Name    -- ^ The identifier whose type signature is to be removed.
      -> t           -- ^ The declarations
      -> RefactGhc t -- ^ The result
rmTypeSig pn t
  = everywhereMStaged SYB.Renamer (SYB.mkM inDecls) t
  where
   inDecls (sigs::[GHC.LSig GHC.Name])
      | not $ emptyList (snd (break (definesTypeSig pn) sigs)) -- /=[]
     = do toks <- fetchToks
          let (decls1,decls2)= break (definesTypeSig pn) sigs
              (toks',decls')=
               let sig@(GHC.L l (GHC.TypeSig names typ)) = ghead "rmTypeSig" decls2  -- as decls2/=[], no problem with head
                   (startPos,endPos) = getStartEndLoc sig
               in if length names > 1
                     then let newSig=(GHC.L l (GHC.TypeSig (filter (\(GHC.L _ x) -> x /= pn) names) typ))
                              pnt = ghead "rmTypeSig" (filter (\(GHC.L _ x) -> x == pn) names)
                              (startPos1, endPos1) = let (startPos1', endPos1') = getStartEndLoc pnt
                                                     in if fromJust (elemIndex pnt names) >0
                                                        then extendForwards  toks startPos1' endPos1' isComma
                                                        else extendBackwards toks startPos1' endPos1' isComma
                          in (deleteToks toks startPos1 endPos1,(decls1++[newSig]++tail decls2))
                     else  ((deleteToks toks startPos endPos),(decls1++tail decls2)) 
                     -- else  error $ "rmTypeSig:(startPos,endPos)=" ++ (show (startPos,endPos)) -- ++AZ++
          putToks toks' modified
          return decls'
   inDecls x = return x


{- ++ original ++

-- | Remove the type signature that defines the given identifier's type from the declaration list.
{-rmTypeSig::(MonadState (([PosToken],Bool),t1) m)
            => PName       -- ^ The identifier whose type signature is to be removed.
            ->[HsDeclP]    -- ^ The declaration list
            ->m [HsDeclP]  -- ^ The result -}

rmTypeSig pn  t = applyTP (full_tdTP (idTP `adhocTP` inDecls)) t
  where
   inDecls (decls::[HsDeclP])
      | snd (break (definesTypeSig pn) decls) /=[]
     = do ((toks,_), others) <- get
          let (decls1,decls2)= break  (definesTypeSig pn) decls
              (toks',decls')=
               let sig@(TiDecorate.Dec (HsTypeSig loc is c tp))=ghead "rmTypeSig" decls2  -- as decls2/=[], no problem with head
                   (startPos,endPos)=getStartEndLoc toks sig
               in if length is>1
                     then let newSig=(TiDecorate.Dec (HsTypeSig loc (filter (\x-> (pNTtoPN x)/=pn) is) c tp))
                              pnt = ghead "rmTypeSig" (filter (\x-> pNTtoPN x == pn) is)
                              (startPos1, endPos1) = let (startPos1', endPos1') = getStartEndLoc toks pnt
                                                     in if fromJust (elemIndex pnt is) >0
                                                        then extendForwards toks startPos1' endPos1' isComma
                                                        else extendBackwards toks startPos1' endPos1' isComma
                          in (deleteToks toks startPos1 endPos1,(decls1++[newSig]++tail decls2))
                     else  ((deleteToks toks startPos endPos),(decls1++tail decls2)) 
          put ((toks',modified),others)
          return decls'
   inDecls x = return x


++ original end ++ -}

-- ---------------------------------------------------------------------

{-
------------------------------------------------------------------------------------------ 
-- | Replace the name (and qualifier if specified) by a new name (and qualifier) in a PName.
--   The function does not modify the token stream.
replaceNameInPN::Maybe ModuleName    -- ^ The new qualifier
                 ->PName             -- ^ The old PName
                 ->String            -- ^ The new name
                 ->PName             -- ^ The result
replaceNameInPN qualifier (PN (UnQual s)(UniqueNames.S loc))  newName
  = if isJust qualifier then (PN (Qual (fromJust qualifier) newName) (UniqueNames.S loc))
                        else (PN (UnQual newName) (UniqueNames.S loc))
replaceNameInPN qualifier (PN (Qual modName  s)(UniqueNames.S loc))  newName
  = if isJust qualifier  then (PN (Qual (fromJust qualifier) newName)(UniqueNames.S loc))
                         else (PN (Qual modName newName) (UniqueNames.S loc))
replaceNameInPN qualifier (PN (UnQual s) (G modName s1 loc))  newName
  = if isJust qualifier then (PN (Qual (fromJust qualifier)  newName) (G modName newName loc))
                        else (PN (UnQual newName) (G modName newName loc))
replaceNameInPN qualifier (PN (Qual modName s) (G modName1 s1 loc))  newName
  =if isJust qualifier then (PN (Qual (fromJust qualifier) newName) (G modName1 newName loc)) 
                       else (PN (Qual modName newName) (G modName1 newName loc))
-}

-- ---------------------------------------------------------------------

------------------------------------------------------------------------------------------------

{-
-- | Add a qualifier to an identifier if it is not qualified.
qualifyPName::ModuleName  -- ^ The qualifier.
              ->PName     -- ^ The identifier.
              ->PName     -- ^ The result.
qualifyPName qual pn 
 = case pn of 
      PN (UnQual n) ty -> PN (Qual qual n ) ty
      _                -> pn
-}

-- ---------------------------------------------------------------------

-- | Remove the qualifier from the given identifiers in the given syntax phrase.
rmQualifier:: (SYB.Data t) 
             =>[GHC.Name]       -- ^ The identifiers.
               ->t           -- ^ The syntax phrase.
               ->RefactGhc t -- ^ The result.
rmQualifier pns t = 
  -- error "undefined rmQualifier"
  everywhereMStaged SYB.Renamer (SYB.mkM rename) t
    where
     rename (pnt@(GHC.L l pn)::GHC.Located GHC.Name)
       | elem pn pns
       = do do toks <- fetchToks
               -- let toks' = replaceToks toks (row,col) (row,col) [mkToken Varid (row,col) s]
               let s = GHC.showPpr pn -- ++TODO: replace this with the appropriate formulation
               let (row,col) = getGhcLoc l
               let toks' = replaceToks toks (row,col) (row,col) [mkToken (GHC.ITvarid (GHC.mkFastString s)) (row,col) s]
               putToks toks' modified
          
               return (GHC.L l (GHC.mkInternalName (GHC.nameUnique pn) (GHC.mkVarOcc s) l))
     rename x = return  x



{- ++ original ++
-- | Remove the qualifier from the given identifiers in the given syntax phrase.
rmQualifier::((MonadState (([PosToken], Bool), t1) m),Term t)
             =>[PName]  -- ^ The identifiers.
               ->t      -- ^ The syntax phrase.
               ->m t    -- ^ The result.
rmQualifier pns t 
  = applyTP (full_tdTP (adhocTP idTP rename )) t
   where 
     rename pnt@(PNT  pn@(PN (Qual modName  s) l) ty loc@(N (Just (SrcLoc fileName _ row col))))
       | elem pn pns
       = do do ((toks,_), others)<-get
               let toks' =replaceToks toks (row,col) (row,col) [mkToken Varid (row,col) s]
               put ((toks', modified), others)
               return (PNT (PN (UnQual s) l) ty loc)
     rename x = return  x
-}

-- ---------------------------------------------------------------------

-- | Rename each occurrences of the identifier in the given syntax
-- phrase with the new name. If the Bool parameter is True, then
-- modify both the AST and the token stream, otherwise only modify the
-- AST.
renamePN::(SYB.Data t)
   =>GHC.Name             -- ^ The identifier to be renamed.
   ->GHC.Name             -- ^ The new name, including possible qualifier
   ->Bool                 -- ^ True means modifying the token stream as well.
   ->t                    -- ^ The syntax phrase
   ->RefactGhc t
renamePN oldPN newName updateTokens t
  = everywhereMStaged SYB.Renamer (SYB.mkM rename) t
  where
    rename :: (GHC.Located GHC.Name) -> RefactGhc (GHC.Located GHC.Name)
    rename  pnt@(GHC.L l n)
     | (GHC.nameUnique n == GHC.nameUnique oldPN)
     = do if updateTokens
           then  do
                    toks <- fetchToks
                    let (row,col) = (getLocatedStart pnt)
                    let toks'= replaceToks toks (row,col) (row,col) [newNameTok l newName]
                    putToks toks' True
                    return (GHC.L l newName)
           else return (GHC.L l newName)
    rename x = return x

-- ---------------------------------------------------------------------

newNameTok l newName =
  ((GHC.L l (GHC.ITvarid (GHC.occNameFS $ GHC.getOccName newName))),
   (GHC.occNameString $ GHC.getOccName newName))

-- ---------------------------------------------------------------------

-- | Show a list of entities, the parameter f is a function that
-- specifies how to format an entity.
showEntities:: (t->String) -> [t] ->String
showEntities _ [] = ""
showEntities f [pn] = f pn
showEntities f (pn:pns) =f pn ++ "," ++ showEntities f pns


-- ---------------------------------------------------------------------
{-
-- | Return True if the identifier can become qualified.
canBeQualified::(Term t)=>PNT->t->Bool
canBeQualified pnt t
  = isTopLevelPNT pnt && isUsedInRhs pnt t && not (findPntInImp pnt t)
  where
    findPntInImp pnt
      = (fromMaybe False).(applyTU (once_tdTU (failTU `adhocTU` inImp)))
      where
       inImp ((HsImportDecl loc modName qual  as h)::HsImportDeclP)
        |findEntity pnt h = Just True
       inImp _ = Nothing
-}


-- ---------------------------------------------------------------------

-- | Return the identifier's defining location.
-- defineLoc::PNT->SrcLoc
defineLoc :: GHC.Located GHC.Name -> GHC.SrcLoc
defineLoc (GHC.L _ name) = GHC.nameSrcLoc name

-- | Return the identifier's source location.
-- useLoc::PNT->SrcLoc
useLoc:: (GHC.Located GHC.Name) -> GHC.SrcLoc
-- useLoc (GHC.L l _) = getGhcLoc l
useLoc (GHC.L l _) = GHC.srcSpanStart l

-- ---------------------------------------------------------------------

-- | Return True if the identifier is used in the RHS if a
-- function\/pattern binding.
isUsedInRhs::(SYB.Data t) => (GHC.Located GHC.Name) -> t -> Bool
isUsedInRhs pnt t = useLoc pnt /= defineLoc pnt  && not (notInLhs)
  where
    notInLhs = fromMaybe False $ somethingStaged SYB.Parser Nothing
            (Nothing `SYB.mkQ` inMatch `SYB.extQ` inDecl) t
     where
      inMatch ((GHC.FunBind name _ (GHC.MatchGroup matches _) _ _ _) :: GHC.HsBind t)
         | isJust (find (sameOccurrence pnt) [name]) = Just True
      inMatch _ = Nothing

      inDecl ((GHC.TypeSig is _) :: GHC.Sig t)
        |isJust (find (sameOccurrence pnt) is)   = Just True
      inDecl _ = Nothing

-- ---------------------------------------------------------------------

-- | Return True if the identifier occurs in the given syntax phrase.
findPNT::(SYB.Data t) => GHC.Located GHC.Name -> t -> Bool
findPNT (GHC.L _ pn)
   = isJust.somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker)
     where
        worker (n::GHC.Name)
           | GHC.nameUnique pn == GHC.nameUnique n = Just True
        worker _ = Nothing

-- | Return True if the identifier occurs in the given syntax phrase.
findPN::(SYB.Data t)=> GHC.Name -> t -> Bool
findPN pn
   = isJust.somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker)
     where
        worker (n::GHC.Name)
           | GHC.nameUnique pn == GHC.nameUnique n = Just True
        worker _ = Nothing

-- | Return True if any of the specified PNames ocuur in the given syntax phrase.
findPNs::(SYB.Data t)=> [GHC.Name] -> t -> Bool
findPNs pns
   = isJust.somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` worker)
     where
        uns = map GHC.nameUnique pns

        worker (n::GHC.Name)
           | elem (GHC.nameUnique n) uns = Just True
        worker _ = Nothing


{-

-- | Return True if any of the specified PNames ocuur in the given syntax phrase.
findPNs::(Term t)=>[PName]->t->Bool
findPNs pns
   =(fromMaybe False).(applyTU (once_tdTU (failTU `adhocTU` worker)))
     where
        worker (pn1::PName)
           |elem pn1 pns = Just True
        worker _ =Nothing

-}


-- ---------------------------------------------------------------------
-- | Given the syntax phrase (and the token stream), find the
-- largest-leftmost expression contained in the region specified by
-- the start and end position. If no expression can be found, then
-- return the defaultExp.
locToExp:: (SYB.Data t,SYB.Typeable n) =>
                   SimpPos    -- ^ The start position.
                -> SimpPos    -- ^ The end position.
                -> t          -- ^ The syntax phrase.
                -> Maybe (GHC.Located (GHC.HsExpr n)) -- ^ The result.
locToExp beginPos endPos t = res
  where
     res = somethingStaged SYB.Parser Nothing (Nothing `SYB.mkQ` expr) t

     expr :: GHC.Located (GHC.HsExpr n) -> (Maybe (GHC.Located (GHC.HsExpr n)))
     expr e
        |inScope e = Just e
     expr _ = Nothing

     inScope :: GHC.Located e -> Bool
     inScope (GHC.L l _) =
       let
         (startLoc,endLoc) = case l of
           (GHC.RealSrcSpan ss) ->
             ((GHC.srcSpanStartLine ss,GHC.srcSpanStartCol ss),
              (GHC.srcSpanEndLine ss,GHC.srcSpanEndCol ss))
           (GHC.UnhelpfulSpan _) -> ((0,0),(0,0))
       in
        (startLoc>=beginPos) && (startLoc<= endPos) && (endLoc>= beginPos) && (endLoc<=endPos)

--------------------------------------------------------------------------------
-- | From PNT to PName.
-- NOTE: the PNT holds the GHC.Name value, it must be converted to a GHC.RdrName
pNTtoPN :: PNT -> PName
pNTtoPN (PNT (GHC.L _ n)) = PN n

ghcToPN :: GHC.RdrName -> PName
ghcToPN rdr = PN rdr

lghcToPN :: GHC.Located GHC.RdrName -> PName
lghcToPN (GHC.L _ rdr) = PN rdr

-- | If a pattern consists of only one identifier then return this
-- identifier, otherwise return Nothing
patToPNT::GHC.LPat GHC.Name -> Maybe GHC.Name
patToPNT (GHC.L _ (GHC.VarPat n)) = Just n
patToPNT _ = Nothing

{-
-- | If a pattern consists of only one identifier then returns this identifier in the PName format,
--   otherwise returns the default PName.
patToPN::HsPatP->PName
patToPN=pNTtoPN.patToPNT
-}

-- | Compose a pattern from a pName.
pNtoPat :: GHC.Name -> GHC.Pat GHC.Name
pNtoPat pname = GHC.VarPat pname
    -- =let loc=srcLoc pname
    --  in (TiDecorate.Pat (HsPId (HsVar (PNT pname Value (N (Just loc))))))

{-
-- | Compose a pattern from a pName.
pNtoPat :: PName -> HsPatP
pNtoPat pname
    =let loc=srcLoc pname
     in (TiDecorate.Pat (HsPId (HsVar (PNT pname Value (N (Just loc))))))
-}

{- ++AZ++ this with deal with an actual GHC.Name
pNTtoPN (PNT pname) = case (GHC.nameModule_maybe pname) of
        Nothing -> PN (GHC.Unqual (GHC.nameOccName pname))
        (Just mod) -> PN (GHC.Qual (GHC.moduleName mod) (GHC.nameOccName pname))
++AZ++ end -}

{-
-- | From PName to Name. This function ignores the qualifier.
pNtoName::PName->String
pNtoName (PN (UnQual i) orig)=i
pNtoName (PN (Qual modName i) orig)=i
-}

{-
-- | From PNT to Name. This function ingnores the qualifier.
pNTtoName::PNT->String
pNTtoName=pNtoName.pNTtoPN
-}

-- ---------------------------------------------------------------------

{-
-- THIS FUNCTION SHOULD NOT BE IN THE API.
-- | Get the list of tokens which represent the declaration that defines pn.
getDeclToks :: PName           -- ^ The identifier.
              -> Bool          -- ^ True means type signature should be included.
              -> [HsDeclP]     -- ^ The declaration list in which the identifier is defined.
              -> [PosToken]    -- ^ The input token stream.
              -> [PosToken]    -- ^ The result.
-}
-- | Get the list of tokens which represent the declaration that defines pn.
getDeclToks :: GHC.Name        -- ^ The identifier.
              -> Bool          -- ^ True means type signature should be included.
              -> [GHC.LHsBind GHC.Name] -- ^ The declaration list in which the identifier is defined.
              -> [PosToken]    -- ^ The input token stream.
              -> [PosToken]    -- ^ The result.
---  IMPORTANT: GET RID OF THE -1111*****************
-- ++AZ++ TODO: the last two params are swapped in getDeclAndToks
getDeclToks pn incSig decls toks
  = let -- (decls1,decls2) = break (definesTypeSig pn) decls
        -- typeSig = if decls2==[] then Nothing else Just (ghead "getDeclToks1" decls2) --There may or may not type signature.
        (decls1', decls2') = break (defines pn) decls
        decl = if (emptyList decls2') then error "getDeclToks:: declaration does not exist"
                                else ghead "getDeclToks2" decls2'
        declToks = getToks' decl toks
        sigToks = [] -- ++AZ++
        {- ++AZ++ TODO: sort this out, sig not in decls
        sigToks
         = case typeSig of
            Nothing  -> []
            Just (sig@(TiDecorate.Dec (HsTypeSig _ [i] _ _)))-> getToks' sig toks
            Just (TiDecorate.Dec (HsTypeSig loc is c ty))-> let sig' =(TiDecorate.Dec (HsTypeSig loc0 [nameToPNT (pNtoName pn)] c ty))
                                                 in  tokenise (Pos 0 (-1111) 1) 0 True $ prettyprint sig'++"\n"   
        -}
    in if incSig then sigToks ++ declToks  else declToks
   where
    getToks' decl toks
      = let (startPos, endPos) = startEndLocIncComments toks decl
            (toks1, _) =let(ts1,(t:ts2'))= break (\t -> tokenPos t >= endPos) toks
                        in (ts1, ts2')
        in dropWhile (\t -> tokenPos t < startPos {- || isNewLn t -}) toks1


-- ---------------------------------------------------------------------

-- Get the toks for a declaration, and adjust its offset to 0.
getDeclAndToks :: (SYB.Data t)
     => GHC.Located GHC.Name -> Bool -> [PosToken] -> t
     -> ([GHC.LHsBind GHC.Name],[PosToken])
getDeclAndToks (GHC.L _ pn) incSig toks t
    -- = error "undefined getDeclAndToks"
    = ghead "getDeclAndToks" $ SYB.everythingStaged SYB.Renamer (++) []
        ([] `SYB.mkQ` inDecls) t
    -- = ghead "getDeclAndToks" $ applyTU (stop_tdTU (failTU `adhocTU` inDecls)) t
  where
    inDecls (decls::[GHC.LHsBind GHC.Name])
      |not $ emptyList (snd (break (defines pn) decls))
      = return $ getDeclAndToks' pn incSig decls toks
    inDecls x = []

    getDeclAndToks' pn incSig decls toks
     = let typeSig = Nothing
     {-
     = let typeSig = if (not incSig)
                      then Nothing
                      else let (decls1,decls2) =break (definesTypeSig pn) decls
                           in if decls2==[] then Nothing else Just (ghead "getDeclAndToks" decls2) 
     -}
           (decls1', decls2') = break (defines pn) decls
           decl = if (emptyList decls2') then error "getDeclAndToks:: declaration does not exisit"
                                         else ghead "getDeclAndToks2" decls2'
           -- offset = getOffset toks (fst (startEndLoc toks decl))
           offset   = getOffset toks (fst (getStartEndLoc decl))
           declToks = removeOffset offset $ getToks' decl toks
           sigToks = []
           {-
           sigToks = case typeSig of
                       Nothing  -> []
                       Just (sig@(TiDecorate.Dec (HsTypeSig _ [i] _ _)))-> removeOffset offset $ getToks' sig toks
                       Just (TiDecorate.Dec (HsTypeSig loc is c ty))-> let sig' =(TiDecorate.Dec (HsTypeSig loc0 [nameToPNT (pNtoName pn)] c ty))
                                                            in  tokenise (Pos 0 (-1111) 1) 0 True $ prettyprint sig'++"\n" 
           -}
       in  (if isJust typeSig then [fromJust typeSig, decl] else [decl], (sigToks ++ declToks))

    getToks' decl toks
      = let (startPos, endPos) = startEndLocIncComments toks decl
            (toks1, _) =let(ts1,(t:ts2'))= break (\t -> tokenPos t >= endPos) toks
                        in (ts1, ts2')
        in dropWhile (\t -> tokenPos t < startPos {- || isNewLn t -}) toks1

    removeOffset offset toks
     = let groupedToks = groupTokensByLine toks
       in  concatMap  (doRmWhites offset) groupedToks


{- ++AZ++ original
-- Get the toks for a declaration, and adjust its offset to 0.
getDeclAndToks pn incSig toks t
    = ghead "getDeclAndToks" $ applyTU (stop_tdTU (failTU `adhocTU` inDecls)) t
  where
    inDecls decls
      |snd (break (defines pn) decls) /=[]
      = return $ getDeclAndToks' pn incSig decls toks
    inDecls x = mzero

    getDeclAndToks' pn incSig decls toks
     = let typeSig = if (not incSig)
                      then Nothing
                      else let (decls1,decls2) =break (definesTypeSig pn) decls
                           in if decls2==[] then Nothing else Just (ghead "getDeclAndToks" decls2) 
           (decls1', decls2') = break (defines pn) decls
           decl = if decls2' == [] then error "getDeclAndToks:: declaration does not exisit"
                                   else ghead "getDeclAndToks2" decls2'
           offset = getOffset toks (fst (startEndLoc toks decl))
           declToks =removeOffset offset $ getToks' decl toks
           sigToks = case typeSig of
                       Nothing  -> []
                       Just (sig@(TiDecorate.Dec (HsTypeSig _ [i] _ _)))-> removeOffset offset $ getToks' sig toks
                       Just (TiDecorate.Dec (HsTypeSig loc is c ty))-> let sig' =(TiDecorate.Dec (HsTypeSig loc0 [nameToPNT (pNtoName pn)] c ty))
                                                            in  tokenise (Pos 0 (-1111) 1) 0 True $ prettyprint sig'++"\n" 
       in  (if isJust typeSig then [fromJust typeSig, decl] else [decl], (sigToks ++ declToks))

    getToks' decl toks
      = let (startPos, endPos) = startEndLocIncComments toks decl
            (toks1, _) =let(ts1, (t:ts2'))= break (\t -> tokenPos t == endPos) toks
                        in (ts1++[t], ts2')
        in dropWhile (\t -> tokenPos t /= startPos || isNewLn t) toks1

    removeOffset offset toks
     = let groupedToks = groupTokensByLine toks
       in  concatMap  (doRmWhites offset) groupedToks

-}

-- ---------------------------------------------------------------------

-- Get the toks for a declaration, and adjust its offset to 0.
getSigAndToks :: GHC.Located GHC.Name -> [PosToken] -> t
     -> (GHC.LSig GHC.Name,[PosToken])
getSigAndToks pn toks t
    = error "undefined getSigAndToks"

-- ---------------------------------------------------------------------
