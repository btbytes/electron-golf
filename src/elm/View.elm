
-- module ----------------------------------------------------------------------

module View exposing (..)

-- import ----------------------------------------------------------------------

import Html exposing (Html)
import Html.Attributes as HAttr
--import Html.Events as HEv
import Svg exposing (Svg)
import Svg.Attributes as SAttr
import Phys exposing (areaWidth, areaHeight)
import Layout exposing (Layout)

-- functions -------------------------------------------------------------------

playingFieldWrapper : Layout -> List (Svg msg) -> Svg msg
playingFieldWrapper playport children =
  Svg.svg
    [ viewBox
    , attrWidth playport.width
    , attrHeight playport.height
    ]
    children

val : a -> Html msg
val a =
  Html.strong [ HAttr.class "value" ] [ Html.text (toString a) ]

drawLine : String -> (Float, Float) -> (Float, Float) -> Svg msg
drawLine cls (x1, y1) (x2, y2) =
  Svg.line
    [ attrX1 x1
    , attrX2 x2
    , attrY1 y1
    , attrY2 y2
    , attrClass cls
    ] []

drawLinePlain : (Float, Float) -> (Float, Float) -> Svg msg
drawLinePlain (x1, y1) (x2, y2) =
  Svg.line
    [ attrX1 x1
    , attrX2 x2
    , attrY1 y1
    , attrY2 y2
    ] []

drawLineVert : String -> (Float, Float) -> Float -> Svg msg
drawLineVert cls (x, y) height =
  Svg.line
    [ attrX1 x
    , attrX2 x
    , attrY1 y
    , attrY2 (y + height)
    , attrClass cls
    ] []

drawLineHoriz : String -> (Float, Float) -> Float -> Svg msg
drawLineHoriz cls (x, y) width =
  Svg.line
    [ attrX1 x
    , attrX2 (x + width)
    , attrY1 y
    , attrY2 y
    , attrClass cls
    ] []

drawBox : String -> (Float, Float) -> (Float, Float) -> Svg msg
drawBox cls (x, y) (width, height) =
  Svg.rect
    [ attrX x
    , attrY y
    , attrWidth width
    , attrHeight height
    , attrClass cls
    ] []

drawCirc : String -> (Float, Float) -> Float -> Svg msg
drawCirc cls (cx, cy) radius =
  Svg.circle
    [ attrCX cx
    , attrCY cy
    , attrR radius
    , attrClass cls
    ] []

drawCircPlain : (Float, Float) -> Float -> Svg msg
drawCircPlain (cx, cy) radius =
  Svg.circle
    [ attrCX cx
    , attrCY cy
    , attrR radius
    ] []

drawCircExt : String -> (Float, Float) -> Float -> List (Svg.Attribute msg) -> Svg msg
drawCircExt cls (cx, cy) radius attrs =
  let
    clsa = attrClass cls
    cxa = attrCX cx
    cya = attrCY cy
    ra = attrR radius
    allAttrs = clsa :: (cxa :: (cya :: (ra :: attrs)))
  in
    Svg.circle allAttrs []

group : List (Svg msg) -> Svg msg
group children =
  Svg.g [] children

emptyGroup : Svg msg
emptyGroup = group []

labeledVal : String -> String -> Html msg
labeledVal label val =
  Html.span [ HAttr.class "section" ]
    [ Html.span [ HAttr.class "label" ] [ Html.text (label ++ ": ") ]
    , Html.span [ HAttr.class "value" ] [ Html.text val ]
    ]

labeledSlashVal : String -> String -> String -> Html msg
labeledSlashVal label val1 val2 =
  Html.span [ HAttr.class "section" ]
    [ Html.span [ HAttr.class "label" ] [ Html.text (label ++ ": ") ]
    , Html.span [ HAttr.class "value" ]
      [ Html.text val1
      , Html.span [ HAttr.class "slash" ] [ Html.text "/" ]
      , Html.text val2
      ]
    ]

-- helpers ---------------------------------------------------------------------

viewBox : Svg.Attribute msg
viewBox = attrViewBox 0 0 areaWidth areaHeight

attrX : number -> Svg.Attribute msg
attrX x = SAttr.x (toString x)

attrY : number -> Svg.Attribute msg
attrY y = SAttr.y (toString y)

attrWidth : number -> Svg.Attribute msg
attrWidth width = SAttr.width (toString width)

attrHeight : number -> Svg.Attribute msg
attrHeight height = SAttr.height (toString height)

attrCX : number -> Svg.Attribute msg
attrCX cx = SAttr.cx (toString cx)

attrCY : number -> Svg.Attribute msg
attrCY cy = SAttr.cy (toString cy)

attrX1 : number -> Svg.Attribute msg
attrX1 x1 = SAttr.x1 (toString x1)

attrY1 : number -> Svg.Attribute msg
attrY1 y1 = SAttr.y1 (toString y1)

attrX2 : number -> Svg.Attribute msg
attrX2 x2 = SAttr.x2 (toString x2)

attrY2 : number -> Svg.Attribute msg
attrY2 y2 = SAttr.y2 (toString y2)

attrR : number -> Svg.Attribute msg
attrR r = SAttr.r (toString r)

attrClass : String -> Svg.Attribute msg
attrClass cls = SAttr.class cls

attrViewBox : number -> number -> number -> number -> Svg.Attribute msg
attrViewBox x y w h =
  SAttr.viewBox ((toString x) ++ " " ++ (toString y) ++ " " ++ (toString w) ++ " " ++ (toString h))
