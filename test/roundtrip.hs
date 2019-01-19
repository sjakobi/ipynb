{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

import Data.Ipynb
import Data.Aeson (Value(..), eitherDecode, encode, decode)
import Data.Aeson.Diff
import System.Environment
import System.FilePath
import qualified Data.ByteString.Lazy as BL
import Test.Tasty
import Test.Tasty.HUnit
import System.Directory
import Data.Char (isSpace)
import Data.Text.IO as T
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Lens.Micro
import Lens.Micro.Aeson
import qualified Data.HashMap.Strict as HM
import qualified Data.ByteString.Base64 as Base64

main :: IO ()
main = do
  let rtdir = "test" </> "rt-files"
  createDirectoryIfMissing False rtdir
  fs <- map (rtdir </>) . filter isIpynb <$> getDirectoryContents rtdir
  defaultMain $ testGroup "round-trip tests" $ map rtTest fs

isIpynb :: FilePath -> Bool
isIpynb fp = takeExtension fp == ".ipynb"

-- We don't want tests failing because of inconsequential
-- differences in formatting of base64 data, like line breaks.
normalizeBase64 :: Value -> Value
normalizeBase64 bs =
  bs & key "cells" . values . key "outputs" . values . key "data"
       . _Object %~ HM.mapWithKey (\k v ->
                       if k == "application/json" ||
                          "text/" `T.isPrefixOf` k ||
                          "+json" `T.isSuffixOf` k
                          then v
                          else go v)
  where
     go (String t) =
       case Base64.decode (TE.encodeUtf8 (T.filter (not . isSpace) t)) of
            Left _  -> String t  -- textual
            Right b -> String $
              TE.decodeUtf8 . Base64.joinWith "\n" 76 . Base64.encode .
              TE.encodeUtf8 . T.replace "\n" "" $ t
     go v = v

rtTest :: FilePath -> TestTree
rtTest fp = testCase fp $ do
  inRaw <- BL.readFile fp
  let format = inRaw ^? key "nbformat"._Number
  case format of
    Just 4 -> rtTest4 inRaw
    _      -> rtTest3 inRaw

rtTest3 :: BL.ByteString -> IO ()
rtTest3 inRaw = do
  (inJSON :: Value) <- either error return $ eitherDecode inRaw
  (nb :: Notebook NbV3) <- either error return $ eitherDecode inRaw
  let outRaw = encode nb
  (nb' :: Notebook NbV3) <- either error return $ eitherDecode outRaw
  (outJSON :: Value) <- either error return $ eitherDecode outRaw
  -- test that (read . write) == id
  let patch = diff (normalizeBase64 inJSON) (normalizeBase64 outJSON)
  assertBool (show patch) (patch == Patch [])
  -- now test that (write . read) == id
  assertEqual "write . read != read" nb nb'

rtTest4 :: BL.ByteString -> IO ()
rtTest4 inRaw = do
  (inJSON :: Value) <- either error return $ eitherDecode inRaw
  (nb :: Notebook NbV4) <- either error return $ eitherDecode inRaw
  let outRaw = encode nb
  (nb' :: Notebook NbV4) <- either error return $ eitherDecode outRaw
  (outJSON :: Value) <- either error return $ eitherDecode outRaw
  -- test that (read . write) == id
  let patch = diff (normalizeBase64 inJSON) (normalizeBase64 outJSON)
  assertBool (show patch) (patch == Patch [])
  -- now test that (write . read) == id
  assertEqual "write . read != read" nb nb'

