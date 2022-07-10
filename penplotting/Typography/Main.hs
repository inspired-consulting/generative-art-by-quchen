module Main where



import Data.List.Extended (nubOrd)
import qualified Data.Vector.Unboxed as V
import qualified Graphics.Rendering.Cairo as C
import qualified Graphics.Text.TrueType as TT

import Draw
import Geometry



main :: IO ()
main = do
    Right iosevka <- TT.loadFontFile "/home/fthoma/.nix-profile/share/fonts/truetype/iosevka-custom-regular.ttf"
    render "out/typography.png" 200 200 $ do
        C.translate (-10) 158
        cairoScope (setColor white >> C.paint)
        let [f] = glyph iosevka 200 'f'
        sketch f
        C.stroke
        C.translate 100 0
        let fHatched = hatch f (deg 45) 5 ++ hatch f (deg (-45)) 5
        --for_ fHatched sketch
        C.stroke

        for_ (glyphOutline iosevka 200 'ɇ') $ \(Polygon ps, _) -> sketch (Polygon ps)
        C.stroke

glyph :: TT.Font -> Double -> Char -> [Polygon]
glyph font size c = fmap (Polygon . fmap toVec2 . nubOrd . V.toList) polys
  where
    dpi = 96
    pt = TT.pixelSizeInPointAtDpi (realToFrac size) dpi
    toVec2 (x, y) = Vec2 (realToFrac x) (realToFrac y)
    [polys] = TT.getGlyphForStrings dpi [(font, pt, [c])]

str :: TT.Font -> Double -> String -> [[Polygon]]
str font size t = fmap (fmap (Polygon . fmap toVec2 . nubOrd . V.toList)) glyphs
  where
    dpi = 96
    pt = TT.pixelSizeInPointAtDpi (realToFrac size) dpi
    toVec2 (x, y) = Vec2 (realToFrac x) (realToFrac y)
    glyphs = TT.getStringCurveAtPoint dpi (0, 0) [(font, pt, t)]

hatchedGlyph
    :: TT.Font
    -> Double -- ^ Font size
    -> Char -- ^ Glyph
    -> Angle -- ^ Direction in which the lines will point. @'deg' 0@ is parallel to the x axis.
    -> Double -- ^ Distance between shading lines
    -> [Line]
hatchedGlyph font size c angle hatchInterval = do
    let polygons = glyph font size c
    let polygonsAligned = transform (rotate (negateV angle)) polygons
    horizontalScissors <- do
        let BoundingBox (Vec2 xLo yLo) (Vec2 xHi yHi) = boundingBox polygonsAligned
        y <- takeWhile (< yHi) (tail (iterate (+ hatchInterval) yLo))
        pure (Line (Vec2 xLo y) (Vec2 xHi y))
    horizontalHatches <-
        [ line
        | polygonAligned <- polygonsAligned
        , (line, LineInsidePolygon) <- clipPolygonWithLine polygonAligned horizontalScissors
        ]
    pure (transform (rotate angle) horizontalHatches)

glyphOutline :: TT.Font -> Double -> Char -> [(Polygon, IslandOrHole)]
glyphOutline font size c = foldl' combinePolygons [p] ps
  where
    rawPolygons = glyph font size c
    classify poly = case polygonOrientation poly of
        PolygonPositive -> (poly, Island)
        PolygonNegative -> (poly, Hole)
    p:ps = classify <$> rawPolygons
    combinePolygons :: [(Polygon, IslandOrHole)] -> (Polygon, IslandOrHole) -> [(Polygon, IslandOrHole)]
    combinePolygons ps (p, ioh) = case ioh of
        Island -> unionsPP ps p
        Hole   -> differencesPP ps p

unionsPP :: [(Polygon, IslandOrHole)] -> Polygon -> [(Polygon, IslandOrHole)]
unionsPP [] p = [(p, Island)]
unionsPP ps p =
    [ q'
    | (q, ioh) <- ps
    , q' <- case ioh of
        Island -> unionPP q p
        Hole   -> differencePP q p >>= \case
            (x, Island) -> [(x, Hole)]
            (x, Hole)   -> [(x, Island)]
    ]

differencesPP :: [(Polygon, IslandOrHole)] -> Polygon -> [(Polygon, IslandOrHole)]
differencesPP [] _ = []
differencesPP ps p =
    [ q'
    | (q, ioh) <- ps
    , q' <- case ioh of
        Island -> differencePP q p
        Hole   -> unionPP q p >>= \case
            (x, Island) -> [(x, Hole)]
            (x, Hole)   -> [(x, Island)]
    ]
