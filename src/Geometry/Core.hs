{-# LANGUAGE BangPatterns #-}

module Geometry.Core (
    -- * Primitives
    -- ** Vector spaces
      VectorSpace(..)

    -- ** 2D Vectors
    , Vec2(..)
    , dotProduct
    , norm
    , normSquare
    , polar

    -- ** Lines
    , Line(..)
    , angleOfLine
    , angleBetween
    , angledLine
    , lineLength
    , resizeLine
    , resizeLineSymmetric
    , centerLine
    , normalizeLine
    , lineReverse
    , perpendicularBisector
    , perpendicularLineThrough
    , distanceFromLine
    , LLIntersection(..)
    , intersectionLL

    -- ** Polygons
    , Polygon(..)
    , normalizePolygon
    , PolygonError(..)
    , validatePolygon
    , pointInPolygon
    , countEdgeTraversals
    , polygonAverage
    , polygonCircumference
    , polygonArea
    , signedPolygonArea
    , polygonEdges
    , polygonAngles
    , isConvex
    , convexHull
    , PolygonOrientation(..)
    , polygonOrientation

    -- ** Bezier curves
    , Bezier(..)

    -- ** Angles
    , Angle(..)
    , deg
    , getDeg
    , rad

    -- ** Safety newtypes
    , Distance(..)
    , Area(..)

    -- * Transformations
    , Transformation(..)
    , identityTransformation
    , transformationProduct
    , inverse
    , Transform(..)
    , translate
    , rotate
    , rotateAround
    , scale
    , scaleAround
    , mirror
    , mirrorX
    , mirrorY

    -- * Bounding Box
    , HasBoundingBox(..)
    , BoundingBox(..)
    , transformBoundingBox
    , AspectRatioBehavior(..)

    -- * Processes
    , reflection
    , billardProcess

    -- * Useful stuff
    , vectorOf
    , det
    , direction
    , bugError
) where



import Control.Monad
import Data.Fixed
import Data.List
import Data.Maybe
import Text.Printf

import Util



data Vec2 = Vec2 !Double !Double deriving (Eq, Ord, Show)

-- | Polygon, defined by its corners.
--
-- Many algorithms assume certain invariants about polygons, see
-- 'validatePolygon' for details.
newtype Polygon = Polygon [Vec2]

-- | List-rotate the polygon’s corners until the minimum is the first entry in
-- the corner list.
normalizePolygon :: Polygon -> Polygon
normalizePolygon (Polygon corners) = Polygon (rotateUntil (== minimum corners) corners)

instance Eq Polygon where
    p1 == p2
      = let Polygon p1Edges@(edge1:_) = p1
            Polygon p2Edges = p2
            p2Edges' = rotateUntil (== edge1) p2Edges
        in p1Edges == p2Edges'

instance Ord Polygon where
    compare p1 p2
      = let Polygon p1Edges = normalizePolygon p1
            Polygon p2Edges = normalizePolygon p2
        in compare p1Edges p2Edges

instance Show Polygon where
    show poly = let Polygon corners = normalizePolygon poly
                in "Polygon " ++ show corners

-- | Line, defined by beginning and end.
data Line = Line Vec2 Vec2 deriving (Eq, Ord, Show)


-- | Cubic Bezier curve, defined by start, first/second control points, and end.
data Bezier vec = Bezier vec vec vec vec deriving (Eq, Ord, Show)


-- | Affine transformation,
--
-- > transformation a b c
-- >                d e f
-- > ==>
-- > / a b \ + / c \
-- > \ d e /   \ f /
--
-- Transformations can be chained using '<>', but in general it’s often more
-- convenient to use the predefined functions such as 'rotateT with '.' as composition.
data Transformation = Transformation Double Double Double
                                     Double Double Double
                                     deriving (Eq, Ord, Show)

identityTransformation :: Transformation
identityTransformation = Transformation
    1 0 0
    0 1 0

transformationProduct :: Transformation -> Transformation -> Transformation
transformationProduct (Transformation a1 b1 c1
                                      d1 e1 f1)
                      (Transformation a2 b2 c2
                                      d2 e2 f2)
                    =  Transformation (a1*a2 + b1*d2) (a1*b2 + b1*e2) (a1*c2 + b1*f2 + c1)
                                      (d1*a2 + e1*d2) (d1*b2 + e1*e2) (d1*c2 + e1*f2 + f1)

inverse :: Transformation -> Transformation
inverse (Transformation a b c
                        d e f)
    = let x = 1 / (a*e - b*d)
      in Transformation (x*e) (x*(-b)) (x*(-e*c + b*f))
                        (x*(-d)) (x*a) (x*(d*c - a*f))

-- | The order transformations are applied in function order:
--
-- @
-- transform (scale a b <> translate p)
-- ==
-- transform (scale a b) . translate p
-- @
--
-- In other words, this translates first, and then scales.
--
-- Note that Cairo does its Canvas transformations just the other way round. You
-- can use 'inverse' to translate between the two directions.
instance Semigroup Transformation where
    (<>) = transformationProduct

instance Monoid Transformation where
    mempty = identityTransformation

class Transform geo where
    transform :: Transformation -> geo -> geo

instance Transform Vec2 where
    transform (Transformation a b c
                              d e f)
              (Vec2 x y)
            = Vec2 (a*x + b*y + c) (d*x + e*y + f)

instance Transform Line where
    transform t (Line start end) = Line (transform t start) (transform t end)

instance Transform Polygon where
    transform t (Polygon ps) = Polygon (transform t ps)

instance Transform vec => Transform (Bezier vec) where
    transform t (Bezier a b c d) = Bezier
        (transform t a)
        (transform t b)
        (transform t c)
        (transform t d)

instance Transform Transformation where
    transform = transformationProduct
    -- ^ Right argument will be applied first, so that
    --
    --
    -- > rotate `transform` translate
    --
    -- will translate before rotating.

instance Transform a => Transform [a] where
    transform t = map (transform t)

instance (Transform a, Transform b) => Transform (a,b) where
    transform t (a,b) = (transform t a, transform t b)

instance (Transform a, Transform b, Transform c) => Transform (a,b,c) where
    transform t (a,b,c) = (transform t a, transform t b, transform t c)

instance (Transform a, Transform b, Transform c, Transform d) => Transform (a,b,c,d) where
    transform t (a,b,c,d) = (transform t a, transform t b, transform t c, transform t d)

instance (Transform a, Transform b, Transform c, Transform d, Transform e) => Transform (a,b,c,d,e) where
    transform t (a,b,c,d,e) = (transform t a, transform t b, transform t c, transform t d, transform t e)

translate :: Vec2 -> Transformation
translate (Vec2 dx dy) = Transformation
    1 0 dx
    0 1 dy

rotate :: Angle -> Transformation
rotate (Angle a) = Transformation
    (cos a) (-sin a) 0
    (sin a) ( cos a) 0

rotateAround :: Vec2 -> Angle -> Transformation
rotateAround pivot angle = translate pivot <> rotate angle <> inverse (translate pivot)

scale :: Double -> Double -> Transformation
scale x y = Transformation
    x 0 0
    0 y 0

scaleAround :: Vec2 -> Double -> Double -> Transformation
scaleAround pivot x y = translate pivot <> scale x y <> inverse (translate pivot)

mirror :: Line -> Transformation
mirror line@(Line p _) = translate p <> rotate angle <> mirrorY <> inverse (rotate angle) <> inverse (translate p)
  where
    angle = angleOfLine line

mirrorX :: Transformation
mirrorX = scale (-1) 1

mirrorY :: Transformation
mirrorY = scale 1 (-1)




-- | The bounding box, with the minimum and maximum vectors.
--
-- In geometrical terms, the bounding box is a rectangle spanned by the top-left
-- (minimum) and bottom-right (maximum) points, so that everything is inside the
-- rectangle.
--
-- Make sure the first argument is smaller than the second when using the
-- constructor directly! Or better yet, don’t use the constructor and create
-- bounding boxes via the provided instances.
data BoundingBox = BoundingBox !Vec2 !Vec2
    deriving (Eq, Ord)

instance Show BoundingBox where
    show (BoundingBox vMin vMax) = "Min: " ++ show vMin ++ " max: " ++ show vMax

instance Semigroup BoundingBox where
    BoundingBox (Vec2 xMin1 yMin1) (Vec2 xMax1 yMax1) <> BoundingBox (Vec2 xMin2 yMin2) (Vec2 xMax2 yMax2)
      = BoundingBox (Vec2 (min xMin1 xMin2) (min yMin1 yMin2))
                    (Vec2 (max xMax1 xMax2) (max yMax1 yMax2))

-- | A bounding box with the minimum at (plus!) infinity and maximum at (minus!)
-- infinity acts as a neutral element. This is mostly useful so we can make
-- potentiallly empty data structures such as @[a]@ and @'Maybe' a@ instances too.
instance Monoid BoundingBox where
    mempty = BoundingBox (Vec2 inf inf) (Vec2 (-inf) (-inf))
      where inf = 1/0

-- | Anything we can paint has a bounding box. Knowing it is useful to e.g. rescale
-- the geometry to fit into the canvas or for collision detection.
class HasBoundingBox a where
    boundingBox :: a -> BoundingBox

instance HasBoundingBox BoundingBox where
    boundingBox = id

instance HasBoundingBox Vec2 where
    boundingBox v = BoundingBox v v

instance (HasBoundingBox a, HasBoundingBox b) => HasBoundingBox (a,b) where
    boundingBox (a,b) = boundingBox a <> boundingBox b

instance (HasBoundingBox a, HasBoundingBox b, HasBoundingBox c) => HasBoundingBox (a,b,c) where
    boundingBox (a,b,c) = boundingBox (a,b) <> boundingBox c

instance (HasBoundingBox a, HasBoundingBox b, HasBoundingBox c, HasBoundingBox d) => HasBoundingBox (a,b,c,d) where
    boundingBox (a,b,c,d) = boundingBox (a,b) <> boundingBox (c,d)

instance (HasBoundingBox a, HasBoundingBox b, HasBoundingBox c, HasBoundingBox d, HasBoundingBox e) => HasBoundingBox (a,b,c,d,e) where
    boundingBox (a,b,c,d,e) = boundingBox (a,b) <> boundingBox (c,d,e)

instance HasBoundingBox a => HasBoundingBox (Maybe a) where
    boundingBox = foldMap boundingBox

instance HasBoundingBox a => HasBoundingBox [a] where
    boundingBox = foldMap boundingBox

instance HasBoundingBox Line where
    boundingBox (Line start end) = boundingBox (start, end)

instance HasBoundingBox Polygon where
    boundingBox (Polygon ps) = boundingBox ps

instance HasBoundingBox vec => HasBoundingBox (Bezier vec) where
    boundingBox (Bezier a b c d) = boundingBox (a,b,c,d)

data AspectRatioBehavior
    = MaintainAspectRatio -- ^ Maintain aspect ratio, possibly leaving some margin for one of the dimensions
    | IgnoreAspectRatio -- ^ Fit the target, possibly stretching the source unequally in x/y directions
    deriving (Eq, Ord, Show)

-- | Generate a transformation that transforms the bounding box of one object to
-- match the other’s. Canonical use case: transform any part of your graphic to
-- fill the Cairo canvas.
transformBoundingBox
    :: (HasBoundingBox source, HasBoundingBox target)
    => source              -- ^ e.g. drawing coordinate system
    -> target              -- ^ e.g. Cairo canvas
    -> AspectRatioBehavior -- ^ Maintain or ignore aspect ratio
    -> Transformation
transformBoundingBox source target aspectRatioBehavior
  = let bbSource = boundingBox source
        bbTarget = boundingBox target

        sourceCenter = boundingBoxCenter bbSource
        targetCenter = boundingBoxCenter bbTarget

        boundingBoxCenter :: BoundingBox -> Vec2
        boundingBoxCenter (BoundingBox lo hi) = (hi +. lo) /. 2
        translateToMatchCenter = translate (targetCenter -. sourceCenter)

        -- | The size of the bounding box. Toy example: calculate the area of it.
        -- Note that the values can be negative if orientations differ.
        boundingBoxDimension :: BoundingBox -> (Double, Double)
        boundingBoxDimension (BoundingBox lo hi) = let Vec2 xSize ySize = hi-.lo in (xSize, ySize)

        (sourceWidth, sourceHeight) = boundingBoxDimension bbSource
        (targetWidth, targetHeight) = boundingBoxDimension bbTarget
        xScaleFactor = targetWidth / sourceWidth
        yScaleFactor = targetHeight / sourceHeight
        scaleAroundT pivot x y = translate pivot <> scale x y <> inverse (translate pivot)

        scaleToMatchSize = case aspectRatioBehavior of
            MaintainAspectRatio ->
                let scaleFactor = min xScaleFactor yScaleFactor
                in scaleAroundT targetCenter scaleFactor scaleFactor
            IgnoreAspectRatio -> scaleAroundT targetCenter xScaleFactor yScaleFactor

    in  scaleToMatchSize <> translateToMatchCenter


-- | A generic vector space. Not only classic vectors like 'Vec2' form a vector
-- space, but also concepts like 'Angle's or 'Distance's – anything that can be
-- added, inverted, and multiplied with a scalar.
--
-- Vector space laws:
--
--     (1) Associativity of addition: @a +. (b +. c) = (a +. b) +. c@
--     (2) Neutral ('zero'): @a +. 'zero' = a = 'zero' +. a@
--     (3) Inverse ('negateV'): @a +. 'negateV' a = 'zero' = 'negateV' a +. a@. '(-.)' is a shorthand for the inverse: @a -. b = a +. negate b@.
--     (4) Commutativity of addition: @a +. b = b +. a@
--     (5) Distributivity of scalar multiplication 1: @a *. (b +. c) = a *. b +. a *. c@
--     (6) Distributivity of scalar multiplication 2: @(a + b) *. c = a *. c +. b *. c@
--     (7) Compatibility of scalar multiplication: @(a * b) *. c = a *. (b *. c)@
--     (8) Scalar identity: @1 *. a = a@
class VectorSpace v where
    {-# MINIMAL (+.), (*.), ((-.) | negateV) #-}
    -- | Vector addition
    (+.) :: v -> v -> v

    -- | Vector subtraction
    (-.) :: v -> v -> v
    a -. b = a +. negateV b

    -- | Multiplication with a scalar
    (*.) :: Double -> v -> v

    -- | Division by a scalar
    (/.) :: v -> Double -> v
    v /. a = (1/a) *. v

    -- | Inverse element
    negateV :: v -> v
    negateV a = (-1) *. a

infixl 6 +., -.
infixl 7 *., /.


instance VectorSpace Vec2 where
    Vec2 x1 y1 +. Vec2 x2 y2 = Vec2 (x1+x2) (y1+y2)
    a *. Vec2 x y = Vec2 (a*x) (a*y)
    negateV (Vec2 x y) = Vec2 (-x) (-y)

instance (VectorSpace v1, VectorSpace v2) => VectorSpace (v1, v2) where
    (u1, v1) +. (u2, v2) = (u1+.u2, v1+.v2)
    (u1, v1) -. (u2, v2) = (u1-.u2, v1-.v2)
    a *. (u1, v1) = (a*.u1, a*.v1)

instance VectorSpace Double where
    a +. b = a+b
    a *. b = a*b
    a -. b = a-b

instance VectorSpace b => VectorSpace (a -> b) where
    (f +. g) a = f a +. g a
    (c *. f) a = c *. f a
    (f -. g) a = f a -. g a

dotProduct :: Vec2 -> Vec2 -> Double
dotProduct (Vec2 x1 y1) (Vec2 x2 y2) = x1*x2 + y1*y2

-- | Euclidean norm.
norm :: Vec2 -> Distance
norm = Distance . sqrt . normSquare

-- | Squared Euclidean norm. Does not require a square root, and is thus
-- suitable for sorting points by distance without excluding certain kinds of
-- numbers such as rationals.
normSquare :: Vec2 -> Double
normSquare v = dotProduct v v

-- | Construct a 'Vec2' from polar coordinates
polar :: Angle -> Distance -> Vec2
polar (Angle a) (Distance d) = Vec2 (d * cos a) (d * sin a)

-- | Newtype safety wrapper.
newtype Angle = Angle { getRad :: Double } deriving (Eq, Ord)

instance Show Angle where
    show (Angle a) = printf "deg %2.8f" (a / pi * 180)

instance VectorSpace Angle where
    Angle a +. Angle b = rad (a + b)
    Angle a -. Angle b = rad (a - b)
    a *. Angle b = rad (a * b)
    negateV (Angle a) = rad (-a)

-- | Degrees-based 'Angle' smart constructor.
deg :: Double -> Angle
deg degrees = rad (degrees / 360 * 2 * pi)

-- | Radians-based 'Angle' smart constructor.
rad :: Double -> Angle
rad r = Angle (r `mod'` (2*pi))

getDeg :: Angle -> Double
getDeg (Angle a) = a / pi * 180

-- | Newtype safety wrapper.
newtype Distance = Distance Double deriving (Eq, Ord, Show)

instance VectorSpace Distance where
    Distance a +. Distance b = Distance (a + b)
    Distance a -. Distance b = Distance (a - b)
    a *. Distance b = Distance (a * b)
    negateV (Distance a) = Distance (-a)

-- | Newtype safety wrapper.
newtype Area = Area Double deriving (Eq, Ord, Show)

-- | Directional vector of a line, i.e. the vector pointing from start to end.
-- The norm of the vector is the length of the line. Use 'normalizeLine' to make
-- it unit length.
vectorOf :: Line -> Vec2
vectorOf (Line start end) = end -. start

-- | Angle of a single line, relative to the x axis.
angleOfLine :: Line -> Angle
angleOfLine (Line (Vec2 x1 y1) (Vec2 x2 y2)) = rad (atan2 (y2-y1) (x2-x1))

angleBetween :: Line -> Line -> Angle
angleBetween line1 line2
  = let Angle a1 = angleOfLine line1
        Angle a2 = angleOfLine line2
    in rad (a2 - a1)

angledLine :: Vec2 -> Angle -> Distance -> Line
angledLine start angle (Distance len) = Line start end
  where
    end = transform (rotateAround start angle) (start +. Vec2 len 0)

lineLength :: Line -> Distance
lineLength = norm . vectorOf

-- | Resize a line, keeping the starting point.
resizeLine :: (Distance -> Distance) -> Line -> Line
resizeLine f line@(Line start _end)
  = let v = vectorOf line
        len@(Distance d) = norm v
        Distance d' = f len
        v' = (d'/d) *. v
        end' = start +. v'
    in Line start end'

-- | Resize a line, keeping the middle point.
resizeLineSymmetric :: (Distance -> Distance) -> Line -> Line
resizeLineSymmetric f line@(Line start end) = (centerLine . resizeLine f . transform (translate delta)) line
  where
    middle = 0.5 *. (start +. end)
    delta = middle -. start

-- | Move the line so that its center is where the start used to be.
--
-- Useful for painting lines going through a point symmetrically.
centerLine :: Line -> Line
centerLine line@(Line start end) = transform (translate delta) line
  where
    middle = 0.5 *. (start +. end)
    delta = start -. middle

-- | Move the end point of the line so that it has length 1.
normalizeLine :: Line -> Line
normalizeLine = resizeLine (const (Distance 1))

-- | Distance of a point from a line.
distanceFromLine :: Vec2 -> Line -> Distance
distanceFromLine (Vec2 ux uy) (Line p1@(Vec2 x1 y1) p2@(Vec2 x2 y2))
  = let Distance l = norm (p2 -. p1)
    in Distance (abs ((x2-x1)*(y1-uy) - (x1-ux) * (y2-y1)) / l)

-- | Direction vector of a line.
direction :: Line -> Vec2
direction = vectorOf . normalizeLine

-- | Switch defining points of a line.
lineReverse :: Line -> Line
lineReverse (Line start end) = Line end start

bugError :: String -> a
bugError msg = errorWithoutStackTrace (msg ++ "\nThis should never happen! Please report it as a bug.")

data LLIntersection
    = IntersectionReal
        -- ^ Two lines intersect fully.

    | IntersectionVirtualInsideL
        -- ^ The intersection is in the left argument (of 'intersectionLL')
        -- only, and only on the infinite continuation of the right argument.

    | IntersectionVirtualInsideR
        -- ^ dito, but the other way round.

    | IntersectionVirtual
        -- ^ The intersection lies in the infinite continuations of both lines.

    deriving (Eq, Ord, Show)

-- | Calculate the intersection of two lines.
--
-- Returns the point of the intersection, and whether it is inside both, one, or
-- none of the provided finite line segments.
intersectionLL :: Line -> Line -> Maybe (Vec2, LLIntersection)
intersectionLL lineL lineR
    | discriminant == 0 = Nothing -- parallel or collinear lines
    | otherwise         = Just (intersectionPoint, intersectionType)
  where
    intersectionType = case (intersectionInsideL, intersectionInsideR) of
        (True,  True)  -> IntersectionReal
        (True,  False) -> IntersectionVirtualInsideL
        (False, True)  -> IntersectionVirtualInsideR
        (False, False) -> IntersectionVirtual

    -- Calculation copied straight off of Wikipedia, then converted Latex to
    -- Haskell using bulk editing.
    --
    -- https://en.wikipedia.org/wiki/Line%E2%80%93line_intersection

    Line v1@(Vec2 x1 y1) v2@(Vec2 x2 y2) = lineL
    Line v3@(Vec2 x3 y3) v4@(Vec2 x4 y4) = lineR

    discriminant = det (v1 -. v2) (v3 -. v4)

    intersectionPoint = Vec2
        ( (det v1 v2 * (x3-x4) - (x1-x2) * det v3 v4) / discriminant )
        ( (det v1 v2 * (y3-y4) - (y1-y2) * det v3 v4) / discriminant )

    t = det (v1 -. v3) (v3 -. v4) / det (v1 -. v2) (v3 -. v4)
    intersectionInsideL = t >= 0 && t <= 1

    u = - det (v1 -. v2) (v1 -. v3) / det (v1 -. v2) (v3 -. v4)
    intersectionInsideR = u >= 0 && u <= 1

polygonEdges :: Polygon -> [Line]
polygonEdges (Polygon ps) = zipWith Line ps (tail (cycle ps))

polygonAngles :: Polygon -> [Angle]
polygonAngles polygon@(Polygon corners)
  = let orient = case polygonOrientation polygon of
            PolygonNegative -> flip
            PolygonPositive -> id
        angle p x q = orient angleBetween (Line x q) (Line x p)
        _ : corners1 : corners2 : _ = iterate tail (cycle corners)
    in zipWith3 angle corners corners1 corners2

-- | The smallest convex polygon that contains all points.
--
-- The result is oriented in mathematically positive direction. (Note that Cairo
-- uses a left-handed coordinate system, so mathematically positive is drawn as
-- clockwise.)
convexHull :: [Vec2] -> Polygon
-- Andrew’s algorithm
convexHull points
  = let pointsSorted = sort points
        angleSign a b c = signum (det (b -. a) (c -. b))
        go :: (Double -> Double -> Bool) -> [Vec2] -> [Vec2] -> [Vec2]
        go cmp [] (p:ps) = go cmp [p] ps
        go cmp [s] (p:ps) = go cmp [p,s] ps
        go cmp (s:t:ack) (p:ps)
            | angleSign t s p `cmp` 0 = go cmp (p:s:t:ack) ps
            | otherwise = go cmp (t:ack) (p:ps)
        go _ stack [] = stack

    in Polygon (drop 1 (go (<=) [] pointsSorted) ++ drop 1 (reverse (go (>=) [] pointsSorted)))

-- | Orientation of a polygon
data PolygonOrientation = PolygonPositive | PolygonNegative
    deriving (Eq, Ord, Show)

polygonOrientation :: Polygon -> PolygonOrientation
polygonOrientation polygon
    | signedPolygonArea polygon >= Area 0 = PolygonPositive
    | otherwise                           = PolygonNegative

-- | Ray-casting algorithm. Counts how many times a ray coming from infinity
-- intersects the edges of an object.
--
-- The most basic use case is 'pointInPolygon', but it can also be used to find
-- out whether something is inside more complicated objects, such as nested
-- polygons (e.g. polygons with holes).
countEdgeTraversals
    :: Vec2   -- ^ Point to check
    -> [Line] -- ^ Geometry
    -> Int    -- ^ Number of edges crossed
countEdgeTraversals p edges = length intersections
  where
    -- The test ray comes from outside the polygon, and ends at the point to be
    -- tested.
    --
    -- This ray is numerically sensitive, because exactly crossing a corner of
    -- the polygon counts as two traversals (with each adjacent edge), when it
    -- should only be one.  For this reason, we subtract 1 from the y coordinate
    -- as well to get a bit of an odd angle, greatly reducing the chance of
    -- exactly hitting a corner on the way.
    testRay = Line (Vec2 (leftmostPolyX - 1) (pointY - 1)) p
      where
        leftmostPolyX = minimum (edges >>= \(Line (Vec2 x1 _) (Vec2 x2 _)) -> [x1,x2])
        Vec2 _ pointY = p

    intersections = filter (\edge ->
        case intersectionLL testRay edge of
            Just (_, IntersectionReal) -> True
            _other -> False)
        edges

pointInPolygon :: Vec2 -> Polygon -> Bool
pointInPolygon p poly = odd (countEdgeTraversals p (polygonEdges poly))

data PolygonError
    = NotEnoughCorners Int
    | IdenticalPoints [Vec2]
    | SelfIntersections [(Line, Line)]
    deriving (Eq, Ord, Show)

-- | Check whether the polygon satisfies the invariants assumed by many
-- algorithms,
--
--   * At least three corners
--   * No identical points
--   * No self-intersections
--
-- Returns the provided polygon on success.
validatePolygon :: Polygon -> Either PolygonError Polygon
validatePolygon = \polygon -> do
    threeCorners polygon
    noIdenticalPoints polygon
    noSelfIntersections polygon
    pure polygon
  where
    threeCorners (Polygon ps) = case ps of
        (_1:_2:_3:_) -> pure ()
        _other       -> Left (NotEnoughCorners (length ps))

    noIdenticalPoints (Polygon corners) = case nub' corners of
        uniques | uniques == corners -> pure ()
                | otherwise -> Left (IdenticalPoints (corners \\ uniques))

    noSelfIntersections polygon = case selfIntersectionPairs polygon of
        [] -> pure ()
        intersections -> Left (SelfIntersections intersections)

    selfIntersectionPairs :: Polygon -> [(Line, Line)]
    selfIntersectionPairs poly
      = [ (edge1, edge2) | _:edge1:_:restEdges <- tails (polygonEdges poly)
                         , edge2 <- restEdges
                         -- Skip neighbouring edge because neighbours always intersect
                         -- , let Line e11 _e12 = edge1
                         -- , let Line _e21 e22 = edge2
                         -- -- , e12 /= e21
                         -- , e11 /= e22
                         , Just (_, IntersectionReal) <- [intersectionLL edge1 edge2]
                         ]

-- | Average of polygon vertices
polygonAverage :: Polygon -> Vec2
polygonAverage (Polygon corners)
  = let (num, total) = foldl' (\(!n, !vec) corner -> (n+1, vec +. corner)) (0, Vec2 0 0) corners
    in (1/num) *. total

polygonCircumference :: Polygon -> Distance
polygonCircumference poly = foldl'
    (\(Distance acc) edge -> let Distance d = lineLength edge in Distance (acc + d))
    (Distance 0)
    (polygonEdges poly)

-- | Determinant of the matrix
--
-- > / x1 x2 \
-- > \ y1 y2 /
--
-- This is useful to calculate the (signed) area of the parallelogram spanned by
-- two vectors.
det :: Vec2 -> Vec2 -> Double
det (Vec2 x1 y1) (Vec2 x2 y2) = x1*y2 - y1*x2

-- UNTESTED
--
-- http://mathworld.wolfram.com/PolygonArea.html
polygonArea :: Polygon -> Area
polygonArea (Polygon ps)
  = let determinants = zipWith det ps (tail (cycle ps))
    in Area (abs (sum determinants / 2))

signedPolygonArea :: Polygon -> Area
signedPolygonArea (Polygon ps)
  = let determinants = zipWith det ps (tail (cycle ps))
    in Area (sum determinants / 2)

isConvex :: Polygon -> Bool
isConvex (Polygon ps)
    -- The idea is that a polygon is convex iff all internal angles are in the
    -- same direction. The direction of an angle defined by two vectors shares
    -- its sign with the signed area spanned by those vectors, and the latter is
    -- easy to calculate via a determinant.
  = let angleDotProducts = zipWith3
            (\p q r ->
                let lineBeforeAngle = Line p q
                    lineAfterAngle  = Line q r
                in det (vectorOf lineBeforeAngle) (vectorOf lineAfterAngle) )
            ps
            (tail (cycle ps))
            (tail (tail (cycle ps)))

        allSameSign :: [Double] -> Bool
        -- NB: head is safe here, since all short-circuits for empty xs
        allSameSign xs = all (\p -> signum p == signum (head xs)) xs
    in allSameSign angleDotProducts

-- | The result has the same length as the input, point in its center, and
-- points to the left (90° turned CCW) relative to the input.
perpendicularBisector :: Line -> Line
perpendicularBisector line@(Line start end) = perpendicularLineThrough middle line
  where
    middle = 0.5 *. (start +. end)

-- | Line perpendicular to a given line through a point.
--
-- The result has the same length as the input, point in its center, and points
-- to the left (90° turned CCW) relative to the input.
perpendicularLineThrough :: Vec2 -> Line -> Line
perpendicularLineThrough p line@(Line start _) = centerLine line'
  where
    -- Move line so it starts at the origin
    Line start0 end0 = transform (translate (negateV start)) line
    -- Rotate end point 90° CCW
    end0' = let Vec2 x y  = end0
            in Vec2 (-y) x
    -- Construct rotated line
    lineAt0' = Line start0 end0'
    -- Move line back so it goes through the point
    line' = transform (translate p) lineAt0'

-- | Optical reflection of a ray on a mirror. Note that the outgoing line has
-- reversed direction like light rays would. The second result element is the
-- point of intersection with the mirror, which is not necessarily on the line,
-- and thus returned separately.
reflection
    :: Line -- ^ Light ray
    -> Line -- ^ Mirror
    -> Maybe (Line, Vec2, LLIntersection)
            -- ^ Reflected ray; point of incidence; type of intersection of the
            -- ray with the mirror. The reflected ray is symmetric with respect
            -- to the incoming ray (in terms of length, distance from mirror,
            -- etc.), but has reversed direction (like real light).
reflection ray mirrorSurface = case intersectionLL ray mirrorSurface of
    Nothing -> Nothing
    Just (iPoint, iType) -> Just (lineReverse ray', iPoint, iType)
      where
        mirrorAxis = perpendicularLineThrough iPoint mirrorSurface
        ray' = transform (mirror mirrorAxis) ray

-- | Shoot a billard ball, and record its trajectory as it is reflected off the
-- edges of a provided geometry.
billardProcess
    :: [Line] -- ^ Geometry; typically involves the edges of a bounding polygon.
    -> Line   -- ^ Initial velocity vector of the ball. Only start and direction,
              --   not length, are relevant for the algorithm.
    -> [Vec2] -- ^ List of collision points. Finite iff the ball escapes the
              --   geometry.
billardProcess edges = go (const True)
  where
    -- The predicate is used to exclude the line just mirrored off of, otherwise
    -- we get rays stuck in a single line due to numerical shenanigans. Note
    -- that this is a valid use case for equality of Double (contained in
    -- Line/Vec2). :-)
    go :: (Line -> Bool) -> Line -> [Vec2]
    go considerEdge ballVec@(Line ballStart _)
      = let reflectionRays :: [(Line, Line)]
            reflectionRays = do
                edge <- edges
                (Line _ reflectionEnd, incidentPoint, ty) <- maybeToList (reflection ballVec edge)
                guard $ case ty of
                    IntersectionReal           -> True
                    IntersectionVirtualInsideR -> True
                    _otherwise                 -> False
                guard (incidentPoint `liesAheadOf` ballVec)
                guard (considerEdge edge)
                pure (edge, Line incidentPoint reflectionEnd)

        in case reflectionRays of
            [] -> let Line _ end = ballVec in [end]
            _  ->
                let (edgeReflectedOn, reflectionRay@(Line reflectionStart _))
                      = minimumBy
                          (\(_, Line p _) (_, Line q _) -> distanceFrom ballStart p q)
                          reflectionRays
                in reflectionStart : go (/= edgeReflectedOn) reflectionRay

    liesAheadOf :: Vec2 -> Line -> Bool
    liesAheadOf point (Line rayStart rayEnd)
      = dotProduct (point -. rayStart) (rayEnd -. rayStart) > 0

    distanceFrom :: Vec2 -> Vec2 -> Vec2 -> Ordering
    distanceFrom start p q
      = let Distance pDistance = lineLength (Line start p)
            Distance qDistance = lineLength (Line start q)
        in compare pDistance qDistance
