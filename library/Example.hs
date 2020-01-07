{-# LANGUAGE TemplateHaskell, QuasiQuotes, ScopedTypeVariables, FlexibleInstances, TypeFamilies, Rank2Types #-}

-- | An example module.
module Example (main) where

import Language.Haskell.Exts.Pretty ( prettyPrint )
import Language.Haskell.Exts.Syntax ( Exp(ExpTypeSig), Type(TyFun, TyCon, TyApp, TyVar), Name(Ident), QName(UnQual) ) -- , SpecialCon(ExprHole)
import Language.Haskell.Exts.Parser ( ParseResult, parse, fromParseResult )
import Language.Haskell.Exts.SrcLoc ( SrcSpan(..), SrcSpanInfo(..), srcInfoSpan, srcInfoPoints )
-- import Test.QuickCheck ( Gen, arbitrary, sample, sample', variant, generate )
-- TODO: pre-compile for performance, see https://github.com/haskell-hint/hint/issues/37
import Language.Haskell.Interpreter (Interpreter, InterpreterError(..), GhcError(..), interpret, as, typeOf, runInterpreter, lift, liftIO, setImports) -- , MonadInterpreter, infer, eval, kindOf, typeChecks
import Data.List (intercalate, nub, replicate)
import System.Random (randomRIO)

errorString :: InterpreterError -> String
errorString (WontCompile es) = intercalate "\n" (header : map unbox es)
  where
    header = "ERROR: Won't compile:"
    unbox (GhcError e) = e
errorString e = show e

-- | An example function.
main :: IO ()
main = do
    r <- runInterpreter testHint
    case r of
        Left err -> putStrLn $ errorString err
        Right () -> return ()

say :: String -> Interpreter ()
say = liftIO . putStrLn

testHint :: Interpreter ()
testHint = do
    let modules = ["Prelude", "Data.List", "Test.QuickCheck"]
    setImports modules

    -- alternative to ScopedTypeVariables: https://stackoverflow.com/q/14540704/1502035
    -- let src = "\\b -> let _b = (b :: Bool) in not b"
    let src = "id"

    (hole_expr, triplets) <- fromFn src
    say $ src
    say $ prettyPrint hole_expr
    -- say $ io_pairs
    -- do (in_tp_str, out_tp_str, io_pairs) <- triplets
    --     say (in_tp_str, out_tp_str)
    --     say io_pairs
    --     return ()
    -- do trplt <- triplets
    --     say trplt
    --     return ()
    mapM_ (say . show) triplets
    return ()

data Item a = One [a] | Many [Item a]

flatten :: Item a -> [a]
flatten (One x) = x
flatten (Many x) = concatMap flatten x

-- TODO: this isn't right, I shouldn't replace each type variable instance, but find the type variables and their occurrences, then for each one (e.g. a) instantiate types and substitute all occurrences for these.
instantiateType :: (Type SrcSpanInfo) -> IO (Item (Type SrcSpanInfo))
instantiateType tp = case tp of
                        TyCon _l qname -> return $ One $ [TyCon _l qname]
                        TyVar _l _name -> (Many . fmap (One . pure)) <$> (mapM id $ replicate maxInstances $ randomType nestLimit)
                        -- checking if the input type *is* a type variable -- what about nested occurrences?
                        -- TyApp _l a b -> Many [instantiateType ?]
                        x -> fail $ "unexpected " ++ show x
                      where
                          maxInstances = 5  -- may get less after nub filters out duplicate type instances
                          nestLimit = 2

-- TODO: do sample generation not for each function level but for each function type?
fromFn :: String -> Interpreter (Exp SrcSpanInfo, [] (String, String, String))
fromFn fn_str = do
    fn_tp_str <- typeOf fn_str
    let hole_expr = skeleton fn_tp_str
    in_tp <- fnInTp fn_tp_str
    nested_types <- lift $ instantiateType in_tp
    let in_types = nub $ flatten nested_types
    triplets :: [] (String, String, String) <- mapM (handleInTp fn_str fn_tp_str) in_types
    return (hole_expr, triplets)

handleInTp :: String -> String -> (Type SrcSpanInfo) -> Interpreter (String, String, String)
handleInTp fn_str fn_tp_str in_type = do
    let in_tp_str = prettyPrint in_type
    let cmd :: String = "do \n\
    \    let seed = 0 -- somehow this won't make it deterministic? \n\
    \    let n = 10 \n\
    \    ins <- nub <$> sample' (resize n $ variant seed arbitrary :: Gen (" ++ in_tp_str ++ ")) \n\
    \    let outs = (" ++ fn_str ++ ") <$> ins \n\
    \    return $ show $ zip ins outs \n\
    \    "
    io <- interpret cmd (as :: IO String)
    io_pairs <- lift io
    out_tp_str <- returnType fn_tp_str in_tp_str
    return (in_tp_str, out_tp_str, io_pairs)

-- -- Bool/Int types are bs substitutes for a/b to statically test if this compiles for above
-- genIO :: (Bool -> Int) -> IO String
-- genIO fn = do
--     let seed = 0 -- somehow this won't make it deterministic?
--     let n = 10
--     ins <- nub <$> sample' (resize n $ variant seed arbitrary :: (Gen Bool))
--     let outs = (fn) <$> ins
--     return $ show $ zip ins outs

-- str = show $ funResultTy (typeOf (reverse :: [Char] -> [Char])) $ typeOf "abc"
returnType :: String -> String -> Interpreter String
returnType fn_tp_str par_tp_str = typeOf $ "(undefined :: " ++ fn_tp_str ++ ") (undefined :: " ++ par_tp_str ++ ")"

fnInTp :: String -> Interpreter (Type SrcSpanInfo)
fnInTp fn_tp_str = do
    let tp_ast = fromParseResult (parse ("_ :: " ++ fn_tp_str) :: ParseResult (Exp SrcSpanInfo))
    tp_fn <- case tp_ast of
                ExpTypeSig _mdl _exp tp -> return tp
                x -> fail $ "expected ExpTypeSig, not" ++ show x
    in_tp <- case tp_fn of
                TyFun _mdl i _o -> return i
                x -> fail $ "expected TyFun, not " ++ show x
    say $ prettyPrint in_tp
    return in_tp
 
pick :: [a] -> IO a
pick xs = fmap (xs !!) $ randomRIO (0, length xs - 1)

randomType :: Int -> IO (Type SrcSpanInfo)
randomType nestLimit = do
    io <- pick $ case nestLimit of
            0 -> simples
            _ -> simples ++ monos
    io
    where
        simples = [ simple "Bool"
                  , simple "Int"
                  ]
        monos = [ mono "[]"
                ]
        simple = return . typeNode
        mono str = do
            tp <- randomType (nestLimit - 1)
            return $ polyTypeNode str tp

l :: SrcSpanInfo
l = SrcSpanInfo {srcInfoSpan = spn, srcInfoPoints = []}
    where
        spn = SrcSpan "<unknown>.hs" 1 1 1 1

typeNode :: String -> (Type SrcSpanInfo)
typeNode str = TyCon l $ UnQual l $ Ident l str

polyTypeNode :: String -> (Type SrcSpanInfo) -> (Type SrcSpanInfo)
polyTypeNode str tp = TyApp l (typeNode str) tp

-- -- can't get TypeRep for polymorphic types
-- skeleton :: TypeRep -> Exp SrcSpanInfo
-- skeleton rep = expr
--     where
--         io = typeRepArgs rep
--         hole = Var l $ Special l $ ExprHole l
--         i = typeNode . show $ head io
--         o = typeNode . show $ last io
--         tp_fn = TyFun l i o
--         expr = ExpTypeSig l hole tp_fn

skeleton :: String -> Exp SrcSpanInfo
skeleton fn_tp_str = expr
    where
        src = "_ :: " ++ fn_tp_str
        expr = fromParseResult (parse src :: ParseResult (Exp SrcSpanInfo))
