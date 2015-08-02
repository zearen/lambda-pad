{-# LANGUAGE RecordWildCards #-}
module Game.LambdaPad.Internal where

import Control.Applicative ( (<$>), (<*>), optional )
import Control.Monad ( when )
import Data.Maybe ( fromMaybe, listToMaybe )
import Data.Monoid ( mempty, mconcat, (<>) )
import System.Directory ( doesFileExist, createDirectoryIfMissing )
import System.FilePath ( dropFileName )
import System.IO ( IOMode(WriteMode), withFile, hPutStrLn, )

import qualified Config.Dyre as Dyre
import qualified Config.Dyre.Options as Dyre
import qualified Config.Dyre.Paths as Dyre
import qualified Options.Applicative as Opt

import Game.LambdaPad.Core.Run
    ( stop, padConfigByName, padConfigByDefault )
import Game.LambdaPad.GameConfig
    ( PackagedGameConfig, unpackage, packageName )
import Game.LambdaPad.PadConfig
    ( PadConfig, padShortName )
import Game.LambdaPad.Pads ( allKnownPads )

data LambdaPadConfig = LambdaPadConfig
    { gameConfigs :: [PackagedGameConfig]
    , padConfigs :: [PadConfig]
    , defaultGame :: Maybe PackagedGameConfig
    , defaultPad :: Maybe PadConfig
    , defaultSpeed :: Float
    , errorMsg :: Maybe String
    }

defaultLambdaPadConfig :: LambdaPadConfig
defaultLambdaPadConfig = LambdaPadConfig
    { gameConfigs = []
    , padConfigs = allKnownPads
    , defaultGame = Nothing
    , defaultPad = Nothing
    , defaultSpeed = 60
    , errorMsg = Nothing
    }

data LambdaPadFlags = LambdaPadFlags
    { lpfPad :: Maybe PadConfig
    , lpfDefaultPad :: Maybe PadConfig
    , lpfGame :: PackagedGameConfig
    , lpfSpeed :: Float
    , lpfJoyIndex :: Int
    }

lambdaPadFlags :: LambdaPadConfig -> Opt.Parser LambdaPadFlags
lambdaPadFlags (LambdaPadConfig{..}) = LambdaPadFlags
    <$> (optional $ Opt.option padChooser $ mconcat
        [ Opt.long "pad"
        , Opt.short 'p'
        ])
    <*> case defaultPad of
          Nothing -> optional $ Opt.option padChooser $ mconcat
              [ Opt.long "default-pad"
              ]
          Just actualDefaultPad -> fmap Just $ Opt.option padChooser $ mconcat
              [ Opt.long "default-pad"
              , Opt.value actualDefaultPad
              ]
    <*> (Opt.option gameChooser $ mconcat
        [ Opt.long "game"
        , Opt.short 'g'
        , maybe mempty Opt.value defaultGame
        ])
    <*> (Opt.option Opt.auto $ mconcat
        [ Opt.long "speed"
        , Opt.short 's'
        , Opt.value defaultSpeed
        ])
    <*> (Opt.option Opt.auto $ mconcat
        [ Opt.long "joystick"
        , Opt.short 'j'
        , Opt.value 0
        ])
  where chooser :: (String -> String) -> (a -> String) -> [a] -> Opt.ReadM a
        chooser formatError getName as = Opt.eitherReader $ \name ->
            maybe (Left $ formatError name) Right $ listToMaybe $
                filter ((==name) . getName) as
        padChooser = chooser (("Unrecognized pad " ++) . show)
            padShortName padConfigs
        gameChooser = chooser (("Unrecognized game " ++) . show)
            packageName gameConfigs

realLambdaPad :: LambdaPadConfig -> IO ()
realLambdaPad lambdaPadConfig = do
    maybe (return ()) fail $ errorMsg lambdaPadConfig
    (LambdaPadFlags{..}) <- Opt.execParser $ 
        Opt.info (Opt.helper <*> lambdaPadFlags lambdaPadConfig) $ mconcat
            [ Opt.fullDesc
            , Opt.header "lambda-pad - Control things with your gamepad !"
            ]
    let padConfigSelector = flip fromMaybe ( padConfigByDefault <$> lpfPad) $
          (padConfigByName (padConfigs lambdaPadConfig) <>) $
              maybe mempty padConfigByDefault lpfDefaultPad
    lpStop <- unpackage lpfGame padConfigSelector lpfJoyIndex lpfSpeed
    _ <- getLine
    stop lpStop

showError :: LambdaPadConfig -> String -> LambdaPadConfig
showError cfg msg = cfg { errorMsg = Just msg }

lambdaPad :: LambdaPadConfig -> IO ()
lambdaPad lambdaPadConfig = do
  (_, _, configFilePath, _, _) <- Dyre.getPaths dyreParams
  configExists <- doesFileExist configFilePath
  when (not configExists) $ do
      putStrLn $ "Config missing, writing empty config to " ++
          show configFilePath
      createDirectoryIfMissing True $ dropFileName configFilePath
      withFile configFilePath WriteMode $
          flip mapM_ defaultConfigFile . hPutStrLn
  Dyre.wrapMain dyreParams lambdaPadConfig
  where dyreParams = Dyre.defaultParams
            { Dyre.projectName = "lambda-pad"
            , Dyre.realMain = Dyre.withDyreOptions dyreParams . realLambdaPad
            , Dyre.showError = showError
            , Dyre.ghcOpts = [ "-threaded", "-funbox-strict-fields" ]
            }

defaultConfigFile :: [String]
defaultConfigFile = 
    [ "import Game.LambdaPad"
    , ""
    , "main :: IO ()"
    , "main = lambdaPad defaultLambdaPadConfig"
    , "    { gameConfigs = [ ]"
    , "    }"
    ]