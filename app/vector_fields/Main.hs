module Main where

import Control.Applicative (liftA2)
import Control.Monad (replicateM)
import Data.Foldable (for_)
import qualified Graphics.Rendering.Cairo as Cairo
import Numeric.Noise.Perlin
import System.Random.MWC

import Draw
import Geometry
import Geometry.Processes.DifferentialEquation
import Graphics.Rendering.Cairo (Render, liftIO)


picWidth, picHeight :: Int
picWidth = 2560
picHeight = 1440

noiseScale :: Double
noiseScale = 251

seed :: Int
seed = 123457

main :: IO ()
main = withSurface PNG "out.png" picWidth picHeight $ \surface -> Cairo.renderWith surface $ do
    restoreStateAfter $ do
        Cairo.setSourceRGB 1 1 1
        Cairo.rectangle 0 0 (fromIntegral picWidth) (fromIntegral picHeight)
        Cairo.fill
    let field = gradientField (perlin seed 1 (1/noiseScale) 0.5)
    don't $ drawVectorField field
    gen <- liftIO create
    ps <- uniformlyDistributedPoints gen 50000
    thicknesses <- liftIO $ replicateM 1000 (uniformR (0.1, 0.5) gen)
    for_ (zip ps (cycle thicknesses)) $ \(p, thickness) -> restoreStateAfter $ do
        Cairo.setLineWidth thickness
        drawFieldLine (take 10 (fieldLine field p))


uniformlyDistributedPoints :: GenIO -> Int -> Render [Vec2]
uniformlyDistributedPoints gen count = liftIO $ replicateM count randomPoint
  where
    randomPoint = liftA2 Vec2 (randomCoordinate picWidth) (randomCoordinate picHeight)
    randomCoordinate mx = fmap fromIntegral (uniformR (0, mx) gen :: IO Int)

drawVectorField :: (Vec2 -> Vec2) -> Render ()
drawVectorField f = restoreStateAfter $ do
    Cairo.setSourceRGB 0 0 0
    for_ [0,40..picWidth] $ \x -> for_ [0,40..picHeight] $ \y -> do
        let point = Vec2 (fromIntegral x) (fromIntegral y)
            end = point +. 20 *. f point
        arrowSketch (Line point end) def
        Cairo.stroke

drawFieldLine :: [Vec2] -> Render ()
drawFieldLine [] = pure ()
drawFieldLine ps = restoreStateAfter $ do
    bezierCurveSketch (bezierSmoothenOpen ps)
    Cairo.stroke

gradientField :: Perlin -> Vec2 -> Vec2
gradientField perturbation p@(Vec2 x y) =
    let perturbationStrength = 0.5 * (1 + tanh (4 * (x / fromIntegral picWidth - 0.6))) * exp (-3 * (y / fromIntegral picHeight - 0.5)^2)
        noise (Vec2 x' y') = noiseValue perturbation (x' + 49156616, 2 * y' + 46216981, 321685163213)
        grad f v = 100 *. Vec2 (f (v +. Vec2 0.01 0) - f v) (f (v +. Vec2 0 0.01) - f v)
        Vec2 dx dy = 0.6 * noiseScale * perturbationStrength *. grad noise p
    in  Vec2 1 0 +. Vec2 dy (-dx)

noise2d :: Perlin -> Vec2 -> Vec2
noise2d perturbation (Vec2 x y) = Vec2
    (noiseValue perturbation (x, y, 231356498))
    (noiseValue perturbation (x, y, 9872146164))

fieldLine :: (Vec2 -> Vec2) -> Vec2 -> [Vec2]
fieldLine f p =
    let f' _t y = f y
    in  snd <$> rungeKuttaConstantStep f' p 0 20

don't :: Applicative m => m a -> m ()
don't _ = pure ()
