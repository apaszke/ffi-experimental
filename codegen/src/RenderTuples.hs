{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}
module RenderTuples where

import Data.Yaml (ParseException)
import qualified Data.Yaml as Y
import Text.Shakespeare.Text (st)
import Data.Text (Text)
import qualified Data.Text.IO as T
import qualified Data.Text as T
import System.Directory (createDirectoryIfMissing)

import qualified ParseTuples as PT
import ParseFunctionSig as P
import RenderCommon


renderImport :: Bool -> Text
renderImport is_managed =  if is_managed then  [st|
import Foreign.C.String
import Foreign.C.Types
import Foreign hiding (newForeignPtr)
import Foreign.Concurrent
import Aten.Type
import Aten.Class
import Aten.Cast

import qualified Aten.Unmanaged.Type.Tuple as Unmanaged
import Aten.Unmanaged.Type.Generator
import Aten.Unmanaged.Type.IntArray
import Aten.Unmanaged.Type.Scalar
import Aten.Unmanaged.Type.SparseTensorRef
import Aten.Unmanaged.Type.Storage
import Aten.Unmanaged.Type.Tensor
import Aten.Unmanaged.Type.TensorList
import Aten.Unmanaged.Type.TensorOptions
import Aten.Unmanaged.Type.Tuple
|] else [st|
import Foreign.C.String
import Foreign.C.Types
import Foreign hiding (newForeignPtr)
import Foreign.Concurrent
import Aten.Type
import Aten.Class

import qualified Language.C.Inline.Cpp as C
import qualified Language.C.Inline.Cpp.Exceptions as C
import qualified Language.C.Inline.Context as C
import qualified Language.C.Types as C
import qualified Data.Map as Map

C.context $ C.cppCtx <> mempty { C.ctxTypesTable = typeTable }

C.include "<ATen/ATen.h>"
|]

tupleToCpp :: PT.Tuple -> Text
tupleToCpp (PT.Tuple parsables) = [st|std::tuple<#{T.intercalate "," (map parsableToCppType parsables)}>|]

tupleToHs :: PT.Tuple -> Text
tupleToHs (PT.Tuple parsables) = [st|(#{T.intercalate "," (map parsableToHsType parsables)})|]

tupleToHs' :: PT.Tuple -> Text
tupleToHs' (PT.Tuple parsables) = [st|#{T.intercalate "" (map parsableToHsType parsables)}|]

toHs :: P.Parsable -> Text
toHs typ_ =
  if isCType typ_
  then [st|#{parsableToHsType typ_}|]
  else [st|Ptr #{parsableToHsType typ_}|]

toManagedHs :: P.Parsable -> Text
toManagedHs typ_ =
  if isCType typ_
  then [st|#{parsableToHsType typ_}|]
  else [st|ForeignPtr #{parsableToHsType typ_}|]


toCpp :: P.Parsable -> Text
toCpp typ_ =
  if isCType typ_
  then [st|#{parsableToCppType typ_}|]
  else [st|#{parsableToCppType typ_}*|]

toCpp' :: P.Parsable -> Text
toCpp' typ_ =
  if isCType typ_
  then [st||]
  else [st|new #{parsableToCppType typ_}|]

renderCppObject :: PT.Tuple -> Text
renderCppObject typ_ = [st|

-----------------#{tupleToHs typ_}---------------------

delete#{tupleToHs' typ_} :: Ptr #{tupleToHs typ_} -> IO ()
delete#{tupleToHs' typ_} ptr = #{bra}C.throwBlock| void { delete $(#{tupleToCpp typ_}* ptr); return; }|#{cket}

instance CppObject #{tupleToHs typ_} where
  fromPtr ptr = newForeignPtr ptr (delete#{tupleToHs' typ_} ptr)
|]

renderCppTuple2 :: PT.Tuple -> Text
renderCppTuple2 typ_@(PT.Tuple (a:b:_)) = [st|
instance CppTuple2 (Ptr #{tupleToHs typ_}) where
  type A (Ptr #{tupleToHs typ_}) = #{toHs a}
  type B (Ptr #{tupleToHs typ_}) = #{toHs b}
  get0 v = #{bra}C.throwBlock| #{toCpp a} { return #{toCpp' a}(std::get<0>(*$(#{tupleToCpp typ_}* v)));}|#{cket}
  get1 v = #{bra}C.throwBlock| #{toCpp b} { return #{toCpp' b}(std::get<1>(*$(#{tupleToCpp typ_}* v)));}|#{cket}
|]
renderCppTuple2 _ = ""

renderCppTuple3 :: PT.Tuple -> Text
renderCppTuple3 typ_@(PT.Tuple (_:_:c:_)) = [st|
instance CppTuple3 (Ptr #{tupleToHs typ_}) where
  type C (Ptr #{tupleToHs typ_}) = #{toHs c}
  get2 v = #{bra}C.throwBlock| #{toCpp c} { return #{toCpp' c}(std::get<2>(*$(#{tupleToCpp typ_}* v)));}|#{cket}
|]
renderCppTuple3 _ = ""

renderCppTuple4 :: PT.Tuple -> Text
renderCppTuple4 typ_@(PT.Tuple (_:_:_:d:_)) = [st|
instance CppTuple4 (Ptr #{tupleToHs typ_}) where
  type D (Ptr #{tupleToHs typ_}) = #{toHs d}
  get3 v = #{bra}C.throwBlock| #{toCpp d} { return #{toCpp' d}(std::get<3>(*$(#{tupleToCpp typ_}* v)));}|#{cket}
|]
renderCppTuple4 _ = ""


renderCppTuple5 :: PT.Tuple -> Text
renderCppTuple5 typ_@(PT.Tuple (_:_:_:_:e:_)) = [st|
instance CppTuple5 (Ptr #{tupleToHs typ_}) where
  type E (Ptr #{tupleToHs typ_}) = #{toHs e}
  get4 v = #{bra}C.throwBlock| #{toCpp e} { return #{toCpp' e}(std::get<4>(*$(#{tupleToCpp typ_}* v)));}|#{cket}
|]
renderCppTuple5 _ = ""

renderManagedCppTuple2 :: PT.Tuple -> Text
renderManagedCppTuple2 typ_@(PT.Tuple (a:b:_)) = [st|
instance CppTuple2 (ForeignPtr #{tupleToHs typ_}) where
  type A (ForeignPtr #{tupleToHs typ_}) = #{toManagedHs a}
  type B (ForeignPtr #{tupleToHs typ_}) = #{toManagedHs b}
  get0 v = cast1 (get0 :: Ptr #{tupleToHs typ_} -> IO (#{toHs a})) v
  get1 v = cast1 (get1 :: Ptr #{tupleToHs typ_} -> IO (#{toHs b})) v
|]
renderManagedCppTuple2 _ = ""

renderManagedCppTuple3 :: PT.Tuple -> Text
renderManagedCppTuple3 typ_@(PT.Tuple (_:_:c:_)) = [st|
instance CppTuple3 (ForeignPtr #{tupleToHs typ_}) where
  type C (ForeignPtr #{tupleToHs typ_}) = #{toManagedHs c}
  get2 v = cast1 (get2 :: Ptr #{tupleToHs typ_} -> IO (#{toHs c})) v
|]
renderManagedCppTuple3 _ = ""

renderManagedCppTuple4 :: PT.Tuple -> Text
renderManagedCppTuple4 typ_@(PT.Tuple (_:_:_:d:_)) = [st|
instance CppTuple4 (ForeignPtr #{tupleToHs typ_}) where
  type D (ForeignPtr #{tupleToHs typ_}) = #{toManagedHs d}
  get3 v = cast1 (get3 :: Ptr #{tupleToHs typ_} -> IO (#{toHs d})) v
|]
renderManagedCppTuple4 _ = ""


renderManagedCppTuple5 :: PT.Tuple -> Text
renderManagedCppTuple5 typ_@(PT.Tuple (_:_:_:_:e:_)) = [st|
instance CppTuple5 (ForeignPtr #{tupleToHs typ_}) where
  type E (ForeignPtr #{tupleToHs typ_}) = #{toManagedHs e}
  get4 v = cast1 (get4 :: Ptr #{tupleToHs typ_} -> IO (#{toHs e})) v
|]
renderManagedCppTuple5 _ = ""



renderTuples :: Bool -> [PT.Tuple] -> Text
renderTuples True [] = ""
renderTuples True (x:xs) =
  renderManagedCppTuple2 x <>
  renderManagedCppTuple3 x <>
  renderManagedCppTuple4 x <>
  renderManagedCppTuple5 x <>
  renderTuples True xs
renderTuples False [] = ""
renderTuples False (x:xs) =
  renderCppObject x <>
  renderCppTuple2 x <>
  renderCppTuple3 x <>
  renderCppTuple4 x <>
  renderCppTuple5 x <>
  renderTuples False xs


decodeAndCodeGen :: String -> String -> IO ()
decodeAndCodeGen basedir fileName = do
  funcs <- Y.decodeFileEither fileName :: IO (Either ParseException [PT.Tuple])
  case funcs of
    Left err' -> print err'
    Right fns -> do
      createDirectoryIfMissing True (basedir <> "/Aten/Unmanaged/Type")
      T.writeFile (basedir <> "/Aten/Unmanaged/Type/Tuple.hs") $
        template False "Aten.Unmanaged.Type.Tuple" fns
      createDirectoryIfMissing True (basedir <> "/Aten/Managed/Type")
      T.writeFile (basedir <> "/Aten/Managed/Type/Tuple.hs") $
        template True "Aten.Managed.Type.Tuple" fns


template :: Bool -> Text -> [PT.Tuple] -> Text
template is_managed module_name types = [st|
-- generated by using spec/tuples.yaml

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}

module #{module_name} where

#{renderImport is_managed}

#{renderTuples is_managed types}
|]

