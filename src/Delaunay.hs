{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
module Delaunay (
  DelaunayTriangulation()
, getPolygons
, bowyerWatson
, bowyerWatsonStep

, toVoronoi
) where

import Data.List (foldl', intersect, sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (maybeToList, catMaybes, fromJust)
import qualified Data.Set as S

import Geometry
import Voronoi



data DelaunayTriangulation = Delaunay
    { triangulation :: S.Set (Triangle, Circle)
    , bounds :: BoundingBox
    }

data Triangle = Triangle Vec2 Vec2 Vec2 deriving (Eq, Ord, Show)
data Circle = Circle { center :: Vec2, radius :: Distance } deriving (Eq, Ord, Show)

-- | Smart constructor for triangles.
--
-- Invariant: Orientation is always positive
triangle :: Vec2 -> Vec2 -> Vec2 -> Triangle
triangle p1 p2 p3 = case polygonOrientation (Polygon [p1, p2, p3]) of
    PolygonPositive -> Triangle p1 p2 p3
    PolygonNegative -> Triangle p1 p3 p2

toPolygon :: Triangle -> Polygon
toPolygon (Triangle p1 p2 p3) = Polygon [p1, p2, p3]

edges :: Triangle -> [Line]
edges (Triangle p1 p2 p3) = [Line p1 p2, Line p2 p3, Line p3 p1]

getPolygons :: DelaunayTriangulation -> [Polygon]
getPolygons Delaunay{..} = deleteBoundingBox $ toPolygon . fst <$> S.toList triangulation
  where
    deleteBoundingBox = filter (not . hasCommonCorner (boundingBoxPolygon bounds))
    hasCommonCorner (Polygon ps) (Polygon qs) = not . null $ ps `intersect` qs

bowyerWatson :: BoundingBox -> [Vec2] -> DelaunayTriangulation
bowyerWatson bounds = foldl' bowyerWatsonStep initialDelaunay
  where
    initialTriangles = [triangle (Vec2 x1 y1) (Vec2 x1 y2) (Vec2 x2 y1), triangle (Vec2 x2 y2) (Vec2 x1 y2) (Vec2 x2 y1)]
    BoundingBox (Vec2 x1 y1) (Vec2 x2 y2) = bounds
    initialDelaunay = Delaunay
        { triangulation = S.fromList (zip initialTriangles (fromJust . circumcircle <$> initialTriangles))
        , ..  }

bowyerWatsonStep :: DelaunayTriangulation -> Vec2 -> DelaunayTriangulation
bowyerWatsonStep delaunay@Delaunay{..} newPoint = delaunay { triangulation = goodTriangles <> newTriangles }
  where
    validNewPoint = if newPoint `insideBoundingBox` bounds
        then newPoint
        else error "User error: Tried to add a point outside the bounding box"
    (badTriangles, goodTriangles) = S.partition ((validNewPoint `inside`) . snd) triangulation
    outerPolygon = collectPolygon $ go (edges . fst =<< S.toList badTriangles) M.empty
      where
        go [] result = result
        go (Line p q : es) result
            -- Shared edges always have opposite direction, so they eliminate each other
            | maybe False (p `S.member`) (result M.!? q) = go es (M.adjust (S.delete p) q result)
            | otherwise = go es $ M.alter (\case
                Just qs -> Just (S.insert q qs)
                Nothing -> Just (S.singleton q))
                p result
    collectPolygon edgeGraph = let (p, _) = M.findMin edgeGraph in Polygon (go p edgeGraph)
      where
        go p remainingGraph
            | M.null remainingGraph = []
            | otherwise =
                let qs = remainingGraph M.! p
                    [q] = S.toList qs
                in p : go q (M.delete p remainingGraph)
    newTriangles = S.fromList
        [ (t, c)
        | Line p q <- polygonEdges outerPolygon
        , let t = triangle newPoint p q
        , c <- maybeToList (circumcircle t) ]

circumcircle :: Triangle -> Maybe Circle
circumcircle (Triangle p1 p2 p3) = case maybeCenter of
    Just center -> Just Circle { radius = norm (center -. p1), .. }
    Nothing -> bugError ("Circumcircle of triangle: Bad intersection " ++ show intersectionOfBisectors)
  where
    intersectionOfBisectors = intersectionLL (perpendicularBisector (Line p1 p2)) (perpendicularBisector (Line p1 p3))
    maybeCenter = intersectionPoint intersectionOfBisectors

inside :: Vec2 -> Circle -> Bool
point `inside` Circle {..} = norm (center -. point) <= radius

toVoronoi :: DelaunayTriangulation -> Voronoi'
toVoronoi delaunay@Delaunay{..} = Voronoi {..}
  where
    cells =
        [ cell
        | (p, rays) <- M.toList (vertexGraph delaunay)
        , cell <- maybeToList (voronoiCell bounds p rays)
        ]

vertexGraph :: DelaunayTriangulation -> M.Map Vec2 (S.Set Vec2)
vertexGraph Delaunay{..} = go (fst <$> S.toList triangulation) M.empty
  where
    go [] = id
    go (Triangle a b c : rest) = go rest
        . M.alter (insertOrUpdate b) a
        . M.alter (insertOrUpdate c) a
        . M.alter (insertOrUpdate a) b
        . M.alter (insertOrUpdate c) b
        . M.alter (insertOrUpdate a) c
        . M.alter (insertOrUpdate b) c
    insertOrUpdate p Nothing = Just (S.singleton p)
    insertOrUpdate p (Just ps) = Just (S.insert p ps)

voronoiCell :: BoundingBox -> Vec2 -> S.Set Vec2 -> Maybe (VoronoiCell ())
voronoiCell bb p qs
    | p `elem` bbCorners = Nothing
    | otherwise          = Just Cell { region = polygonRestrictedToBounds, seed = p, props = () }
  where
    sortedRays = sortOn angleOfLine (Line p <$> S.toList qs)
    voronoiVertex l1 l2
        | Line _ q1 <- l1, Line _ q2 <- l2, q1 `elem` bbCorners, q2 `elem` bbCorners
          = intersectionPoint (intersectionLL (transform (rotateAround q1 (deg 90)) l1) (transform (rotateAround q2 (deg 90)) l2))
        | Line _ q <- l1, q `elem` bbCorners
          = intersectionPoint (intersectionLL (transform (rotateAround q (deg 90)) l1) (perpendicularBisector l2))
        | Line _ q <- l2, q `elem` bbCorners
          = intersectionPoint (intersectionLL (perpendicularBisector l1) (transform (rotateAround q (deg 90)) l2))
        | otherwise
          = intersectionPoint (intersectionLL (perpendicularBisector l1) (perpendicularBisector l2))
    rawPolygon = Polygon $ catMaybes (uncurry voronoiVertex <$> zip sortedRays (tail (cycle sortedRays)))
    polygonRestrictedToBounds = go (polygonEdges bbPoly) rawPolygon
      where
        go [] poly = poly
        go (l:ls) poly = let [clipped] = filter (p `pointInPolygon`) (cutPolygon l poly) in go ls clipped

    bbPoly@(Polygon bbCorners) = boundingBoxPolygon bb
