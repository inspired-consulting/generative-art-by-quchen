module Test.Triangulate (tests) where



import           Data.Foldable
import qualified Data.Set                 as S
import           Graphics.Rendering.Cairo hiding (x, y)

import Draw
import Geometry
import Geometry.Shapes

import Test.Common
import Test.Tasty
import Test.Tasty.HUnit



tests :: TestTree
tests = testGroup "Polygon triangulation"
    [ testSquare
    , testRegular9gon
    , testHaskellLogo
    , testSpiral
    ]

testSquare :: TestTree
testSquare = testCase "Square" test
  where
    triangulation = triangulate (Polygon [Vec2 0 0, Vec2 100 0, Vec2 100 100, Vec2 0 100])
    test = renderAllFormats 120 120 "test/out/triangulation/1_square" $ do
        translate 10 10
        paintTriangulation triangulation

testRegular9gon :: TestTree
testRegular9gon = testCase "Regular 9-gon" test
  where
    triangulation = triangulate (Polygon [ Geometry.transform (rotate' (deg (fromIntegral d))) (Vec2 0 50) | d <- [0::Int, 360 `div` 9 .. 360-1] ])
    test = renderAllFormats 120 120 "test/out/triangulation/2_heptagon" $ do
        translate 60 60
        paintTriangulation triangulation

testHaskellLogo :: TestTree
testHaskellLogo = testCase "Haskell logo" test
  where
    triangulation = map triangulate wonkyHaskellLogo
    test = renderAllFormats 510 360 "test/out/triangulation/3_haskell_logo" $ do
        translate 10 10
        for_ triangulation (restoreStateAfter . paintTriangulation)

testSpiral :: TestTree
testSpiral = localOption (mkTimeout (10^6)) $ testCase "Spiral" test
  where
    triangulation = triangulate (spiralPolygon 8 20)
    test = renderAllFormats 300 300 "test/out/triangulation/4_spiral" $ do
        translate 110 110
        paintTriangulation triangulation

nubLines :: [Line] -> [Line]
nubLines = S.toList . S.fromList . map normalize
  where
    normalize (Line v1 v2) = Line (min v1 v2) (max v1 v2)

paintTriangulation :: [Polygon] -> Render ()
paintTriangulation triangulation = do
    let setColors = map (\c -> mmaColor c) [0..]
    for_ (zip3 [1::Int ..] setColors triangulation) $ \(i, setColor, polygon) -> do
        restoreStateAfter $ do
            polygonSketch polygon
            setColor 0.5
            fill
        restoreStateAfter $ do
            moveToVec (polygonAverage polygon)
            hsva 0 0 0 1
            showTextAligned HCenter VCenter (show i)
    restoreStateAfter $ do
        setLineWidth 0.5
        hsva 0 0 0 1
        let allEdges = polygonEdges =<< triangulation
            uniqueEdges = nubLines allEdges
        for_ uniqueEdges $ \edge -> do
            lineSketch edge
            stroke
