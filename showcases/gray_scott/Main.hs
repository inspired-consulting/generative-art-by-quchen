{-# LANGUAGE RecordWildCards #-}
module Main where

import Text.Printf (printf)
import qualified Codec.Picture as P
import Data.Maybe (fromMaybe)
import qualified Data.Vector.Storable as V
import qualified Data.Vector.Unboxed as U
import Math.Noise

import Draw
import Geometry
import Plane

picWidth, picHeight :: Num a => a
picWidth = 960
picHeight = 540

main :: IO ()
main = do

    let step = 2
        diffusionRate = 0.1

        params = GS
            { feedRateU = 0.029
            , killRateV = 0.057
            , diffusionRateU = 2 * diffusionRate
            , diffusionRateV = diffusionRate
            , step = step
            , width = picWidth
            , height = picHeight }
        warmup = grayScott 200 params { step = 1 }
        initialState = warmup $ planeFromList
            [ row
            | y <- [0..picHeight - 1]
            , let row =
                    [ (u, v, 0, 0)
                    | x <- [0..picWidth - 1]
                    , let u = 1 - noise x y 0
                    , let v = noise x y 0
                    ]
            ]
        addNoise t = mapPlaneCoordinates (\x y (u, v, du, dv) -> (u + 0.02 * noise x y t, v, du, dv))

        frames = take 2000 (iterate (\(t, grid) -> (t + step, grayScott 5 params (addNoise t grid))) (0, initialState))

    for_ (zip [0 :: Int ..] frames) $ \(index, (_, grid)) -> do
        P.writePng (printf "out/gray_scott_%06i.png" index) (renderImageColor (colorFront +. colorTrail +. colorReaction) grid)
        P.writePng (printf "out/uv_gray_scott_%06i.png" index) (renderImageColor (\(u, v, _, _) -> (1-u-v, v, u)) grid)

noise :: Int -> Int -> Double -> Double
noise x y t = fromMaybe 0 $ getValue perlin { perlinFrequency = 0.1 } (fromIntegral x, fromIntegral y, 0.1 * t)

renderImageGrayscale :: Plane Double -> P.Image P.Pixel8
renderImageGrayscale grid = P.Image picWidth picHeight (V.convert (items (mapPlane renderPixel grid)))
  where renderPixel = round . max 0 . min 255 . (* 255)

renderImageColor :: ((Double, Double, Double, Double) -> (Double, Double, Double)) -> Grid -> P.Image P.PixelRGB8
renderImageColor f grid = P.Image picWidth picHeight (V.convert $ U.concatMap renderPixel (items grid))
  where
    renderPixel uv = let (r, g, b) = f uv in U.fromList [pixel8 r, pixel8 g, pixel8 b]
    pixel8 = round . clamp 0 255 . (* 255)

colorFront :: (Double, Double, Double, Double) -> (Double, Double, Double)
colorFront (_, _, _, dv)= tanh (400 * max 0 dv) *. (0.4, 0.1, 0)

colorTrail :: (Double, Double, Double, Double) -> (Double, Double, Double)
colorTrail (_, _, du, dv) = tanh (400 * max 0 du) *. (0, 0, 0.5) +. tanh (-400 * min 0 dv) *. (0.7, 0, -0.1)

colorReaction :: (Double, Double, Double, Double) -> (Double, Double, Double)
colorReaction (u, v, _, _) = case 25 * u * v * v of
    x | x < 0.5   -> interpolate (2*x) color1 color0
      | x < 1.0   -> interpolate (2*(x-0.5)) color2 color1
      | otherwise -> interpolate (x-1) color3 color2
  where
    color0, color1, color2, color3 :: (Double, Double, Double)
    color0 = (0, 0, 0.1)
    color1 = 0.7 *. (0.1, 0.25, 0.5)
    color2 = (0.1, 0.9, 0.1)
    color3 = (255, 0, 0)
    interpolate a c1 c2 = a *. c1 +. (1-a) *. c2

clamp :: (Ord a, Num a) => a -> a -> a -> a
clamp lower upper = max lower . min upper

type Grid = Plane (Double, Double, Double, Double)

data GrayScott = GS
    { feedRateU :: Double
    , killRateV :: Double
    , diffusionRateU :: Double
    , diffusionRateV :: Double
    , step :: Double
    , width :: Double
    , height :: Double
    }

grayScott :: Int -> GrayScott -> Grid -> Grid
grayScott steps GS{..} = repeatF steps (mapNeighbours grayScottStep)
  where
    grayScottStep (uv11, uv12, uv13, uv21, uv22, uv23, uv31, uv32, uv33) = (u0, v0, deltaU, deltaV) +. step *. (deltaU, deltaV, 0, 0)
      where
        (u0, v0, _, _) = uv22
        deltaU = diffusionRateU * laplaceU - u0 * v0^2 + feedRateU * (1 - u0)
        deltaV = diffusionRateV * laplaceV + u0 * v0^2 - (feedRateU + killRateV) * v0
        (laplaceU, laplaceV, _, _) = (uv11 +. 2*.uv12 +. uv13 +. 2*.uv21 -. 12*.uv22 +. 2*. uv23 +. uv31 +. 2*.uv32 +. uv33) /. 4

    repeatF :: Int -> (a -> a) -> a -> a
    repeatF 0 _ = id
    repeatF n f = f . repeatF (n-1) f