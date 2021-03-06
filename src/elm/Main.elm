-- import ----------------------------------------------------------------------

--import Debug exposing (log)
import Html.Events as HEv
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as HAttr
import Svg exposing (Svg)
import Svg.Attributes as SAttr
import Svg.Lazy exposing (lazy)
import PageVisibility exposing (visibilityChanges, Visibility(Visible, Hidden))
import Window
import Task
import Process
import Time exposing (Time)
import Keyboard
import AnimationFrame
import BoxesAndBubbles.Bodies as Bodies
import Transition exposing (Transition)
import Phys
import KeysPressed exposing (KeysPressed)
import Target exposing (Target)
import Level exposing (Level)
import Cannon exposing (Cannon)
import Phase exposing (..)
import View exposing (..)
import Ease
import Layout exposing (Layout)
import Gfx
import Util

-- main ------------------------------------------------------------------------

main : Program Never Model Msg
main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- types/model -----------------------------------------------------------------

type alias Model =
  { playport : Layout -- like "viewport" into which we'll draw our game
  , phase : Phase -- ADT for starting, playing, transitioning, etc
  , keysPressed : KeysPressed -- knows which keys are currently pressed
  , ball : Maybe Phys.Obj -- is there a ball in play?
  , time : Time -- how old is the model?
  , remainingLevels : List Level -- levels yet to be completed
  , finishedLevels : List Level -- levels that have been finished
  , courseName : Maybe String -- name of course currently playing
  , resetCount : Int -- how many times user has pressed reset button
  }

init : (Model, Cmd Msg)
init =
  let
    playport = Layout.from (Window.Size 100 100)
    phase = Starting Phys.splashBouncers Cannon.practice
    keysPressed = KeysPressed.init
    ball = Nothing
    time = 0
    remainingLevels = []
    finishedLevels = []
    courseName = Nothing
    resetCount = 0
    -------------------------------
    model = Model
      playport
      phase
      keysPressed
      ball
      time
      remainingLevels
      finishedLevels
      courseName
      resetCount
    -------------------------------
    cmd = Task.perform Resize Window.size
  in
    (model, cmd)


-- update ----------------------------------------------------------------------

type Msg
  = Resize Window.Size
  | Viz Visibility
  | KeyDown Keyboard.KeyCode
  | KeyUp Keyboard.KeyCode
  | Frame Time
  | Start String

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Viz visibility -> viz visibility model
    Resize newViewport -> resize newViewport model
    Start courseName -> start courseName model
    KeyDown keyCode -> keyDown keyCode model
    KeyUp keyCode -> keyUp keyCode model
    Frame time -> frame time model

-- update main functions -------------------------------------------------------

viz : Visibility -> Model -> (Model, Cmd Msg)
viz visibility model =
  ({ model | keysPressed = KeysPressed.init }, Cmd.none)

resize : Window.Size -> Model -> (Model, Cmd Msg)
resize newViewport model =
  let
    newPlayport = Layout.from newViewport
    newModel = { model | playport = newPlayport }
  in
    (newModel, Cmd.none)

start : String -> Model -> (Model, Cmd Msg)
start courseName model =
  case Dict.get courseName Level.courses of
    Nothing -> -- this would be a bug
      (model, Cmd.none)
    Just levels ->
      case levels of
        [] -> -- this would be a bug
          (model, Cmd.none)
        level :: remainingLevels ->
          let
            newModel = { model
              | remainingLevels = remainingLevels
              , finishedLevels = []
              , phase = Playing level
              , ball = Nothing
              , courseName = Just courseName
              , resetCount = 0
              }
          in
            (newModel, Cmd.none)

keyDown : Int -> Model -> (Model, Cmd Msg)
keyDown keyCode model =
  let
    newKeysPressed = keysPressedOn keyCode model.time model.keysPressed
    keyedModel = { model | keysPressed = newKeysPressed }
  in
    (keyedModel, Cmd.none)

keyUp : Int -> Model -> (Model, Cmd Msg)
keyUp keyCode model =
  let
    newKeysPressed = keysPressedOff keyCode model.time model.keysPressed
    keyedModel = { model | keysPressed = newKeysPressed }
  in
    case keyCode of
      32 -> launchBall keyedModel -- spacebar launches ball
      85 -> reset keyedModel -- 'u' resets level/game
      _ -> (keyedModel, Cmd.none) -- ignore anything else

frame : Time -> Model -> (Model, Cmd Msg)
frame time model =
  let
    tickModel = { model | time = model.time + time }
  in
    case tickModel.phase of
      Starting splashBouncers cannon -> startingFrame splashBouncers cannon tickModel
      Playing level -> playingFrame level tickModel
      Transitioning trans -> transitioningFrame trans tickModel
      Ending splashBouncers -> endingFrame splashBouncers tickModel

-- update helper functions -----------------------------------------------------

launchBall : Model -> (Model, Cmd Msg)
launchBall model =
  case model.phase of
    Playing level ->
      case model.ball of
        Just ball ->
          (model, Cmd.none)
        Nothing ->
          let
            cannon = level.cannon
            adjustedPower = cannon.power / 10
            newBall = Just (Phys.ball cannon.pos cannon.angle adjustedPower)
            newCannon = { cannon | power = 0 }
            newLevel = { level | cannon = newCannon, score = level.score + 1 }
            modelInMotion = { model | ball = newBall, phase = Playing newLevel }
          in
            (modelInMotion, Cmd.none)
    _ ->
      (model, Cmd.none)

reset : Model -> (Model, Cmd Msg)
reset model =
  if model.keysPressed.shift == Nothing then
    (resetLevel model, Cmd.none)
  else
    (resetGame model, Cmd.none)

resetLevel : Model -> Model
resetLevel model =
  case model.courseName of
    Just name ->
      case Dict.get name Level.courses of
        Just redoCourses ->
          let
            idx = List.length model.finishedLevels
          in
            case Util.getByIndex idx redoCourses of
              Just redoLevel ->
                { model
                | phase = Playing redoLevel
                , ball = Nothing
                , resetCount = model.resetCount + 1
                }
              Nothing ->
                model
        Nothing ->
          model
    Nothing ->
      model

resetGame : Model -> Model
resetGame model =
  { model
  | phase = Starting Phys.splashBouncers Cannon.practice
  , ball = Nothing
  , courseName = Nothing
  , resetCount = 0
  }

startingFrame : List Phys.Obj -> Cannon -> Model -> (Model, Cmd Msg)
startingFrame splashBouncers cannon model =
  let
    newSplashBouncers = Phys.stepSplashBouncers splashBouncers
    newCannon = rotateTheCannon model.time model.keysPressed cannon
    newPhase = Starting newSplashBouncers newCannon
    newModel = { model | phase = newPhase }
  in
    (newModel, Cmd.none)

playingFrame : Level -> Model -> (Model, Cmd Msg)
playingFrame level model =
  let
    newModel = model
      |> rotateCannon level
      |> chargeCannon level
      |> advanceBall level
  in
    (newModel, Cmd.none)

transitioningFrame : Transition -> Model -> (Model, Cmd Msg)
transitioningFrame trans model =
  let
    newModel = advanceTransition trans model
  in
    (newModel, Cmd.none)

endingFrame : List Phys.Obj -> Model -> (Model, Cmd Msg)
endingFrame splashBouncers model =
  let
    newSplashBouncers = Phys.stepSplashBouncers splashBouncers
    newPhase = Ending newSplashBouncers
    newModel = { model | phase = newPhase }
  in
    (newModel, Cmd.none)

rotateCannon : Level -> Model -> Model
rotateCannon level model =
  let
    newCannon = rotateTheCannon model.time model.keysPressed level.cannon
    newLevel = { level | cannon = newCannon }
  in
    { model | phase = Playing newLevel }

chargeCannon : Level -> Model -> Model
chargeCannon level model =
  case model.ball of
    Just ball ->
      model
    Nothing ->
      case model.keysPressed.space of
        Just pressTime ->
          let
            pressDuration = model.time - pressTime
            cannon = level.cannon
            isFine = not (model.keysPressed.shift == Nothing)
            incr = pressDuration
              |> (\d -> (d / 100) + 1)
              |> logBase e
              |> (\p -> if isFine then p / 6 else p / 2)
            newPower = min 500 cannon.power + incr
            newCannon = { cannon | power = newPower }
            newLevel = { level | cannon = newCannon }
          in
            { model | phase = Playing newLevel }
        Nothing ->
          model

advanceBall : Level -> Model -> Model
advanceBall level model =
  case model.ball of
    Just ball ->
      let
        (isAtRest, isOOB, newBall, newBarriers) = Phys.step ball level.barriers level.fields
        newLevel = { level | barriers = newBarriers }
      in
        if isAtRest then
          evaluatePlay ball newLevel model
        else if isOOB then
          let
            endedLevel = { level | score = level.score + 5 }
            newFinishedLevels = endedLevel :: model.finishedLevels
            trans = Transition.unsuccessful "Tunneled Out! +6" ball.pos
            newPhase = Transitioning trans
          in
            { model | ball = Nothing, phase = newPhase, finishedLevels = newFinishedLevels }
        else
          { model | ball = Just newBall, phase = Playing newLevel }
    Nothing ->
      model

rotateTheCannon : Time -> KeysPressed -> Cannon -> Cannon
rotateTheCannon now keysPressed cannon =
  let
    isFine = not (keysPressed.shift == Nothing)
    isCoarse = not (keysPressed.alt == Nothing)
  in
    case (keysPressed.left, keysPressed.right) of
      (Just pressTime, Nothing) ->
        rotateCannonBy True isFine isCoarse (now - pressTime) cannon
      (Nothing, Just pressTime) ->
        rotateCannonBy False isFine isCoarse (now - pressTime) cannon
      _ -> cannon

rotateCannonBy : Bool -> Bool -> Bool -> Float -> Cannon -> Cannon
rotateCannonBy isLeft isFine isCoarse speed cannon =
  let
    incr = max 1.0 speed
      |> logBase e
      |> (\a -> a * 0.08)
      |> (\a -> if isFine then a / 6 else a)
      |> (\a -> if isCoarse then a * 4 else a)
      |> (\a -> if isLeft then 0 - a else a)
    incrAngle = cannon.angle - incr
    newAngle = if incrAngle < 0 then
      incrAngle + 360
    else if incrAngle >= 360 then
      incrAngle - 360
    else
      incrAngle
  in
    { cannon | angle = newAngle }

evaluatePlay : Phys.Obj -> Level -> Model -> Model
evaluatePlay ball level model =
  if ballIsInTarget ball level.target then
    let
      newFinishedLevels = level :: model.finishedLevels
      actionPoint = ball.pos
      parDiff = level.score - level.par
      message = if parDiff < 0 then toString parDiff
        else "+" ++ (toString parDiff)
      trans = Transition.successful message ball.pos
    in
      { model
      | ball = Nothing
      , finishedLevels = newFinishedLevels
      , phase = Transitioning trans
      }
  else
    let
      -- move and re-orient cannon
      cannon = level.cannon
      (x1, y1) = ball.pos
      (x2, y2) = level.target.pos
      fudge = toFloat (((round model.time) % 120) - 60)
      angle = (atan2 (y2 - y1) (x2 - x1)) * (360 / (pi * 2))
      newCannon = { cannon | pos = ball.pos, angle = angle + fudge }
      newLevel = { level | cannon = newCannon }
    in
      { model | ball = Nothing, phase = Playing newLevel }

ballIsInTarget : Phys.Obj -> Target -> Bool
ballIsInTarget ball target =
  case ball.shape of
    Bodies.Bubble radius ->
      let
        (tx, ty) = target.pos
        (bx, by) = ball.pos
        boundLeft = tx - target.size / 2
        boundRight = tx + target.size / 2
        boundHi = ty - target.size / 2
        boundLo = ty + target.size / 2
      in
        not (bx < boundLeft || bx > boundRight || by < boundHi || by > boundLo)
    Bodies.Box ext ->
      False

advanceTransition : Transition -> Model -> Model
advanceTransition transition model =
  case Transition.step transition of
    Just tr ->
      { model | phase = Transitioning tr }
    Nothing ->
      case model.remainingLevels of
        level :: newRemainingLevels ->
          { model | phase = Playing level, remainingLevels = newRemainingLevels }
        [] ->
          { model | phase = Ending Phys.splashBouncers }

delay : Time -> msg -> Cmd msg
delay time msg =
  Process.sleep time
    |> Task.andThen (always (Task.succeed msg))
    |> Task.perform identity

keysPressedOn : Int -> Time -> KeysPressed -> KeysPressed
keysPressedOn keyCode time keysPressed =
  updateKeysPressed keyCode True time keysPressed

keysPressedOff : Int -> Time -> KeysPressed -> KeysPressed
keysPressedOff keyCode time keysPressed =
  updateKeysPressed keyCode False time keysPressed

updateKeysPressed : Int -> Bool -> Time -> KeysPressed -> KeysPressed
updateKeysPressed keyCode isOn time keysPressed =
  case keyCode of
    16 -> { keysPressed | shift = updateKeyPressed isOn keysPressed.shift time }
    17 -> { keysPressed | ctrl =  updateKeyPressed isOn keysPressed.ctrl time  }
    18 -> { keysPressed | alt =   updateKeyPressed isOn keysPressed.alt time   }
    32 -> { keysPressed | space = updateKeyPressed isOn keysPressed.space time }
    37 -> { keysPressed | right = updateKeyPressed isOn keysPressed.right time }
    38 -> { keysPressed | up =    updateKeyPressed isOn keysPressed.up time    }
    39 -> { keysPressed | left =  updateKeyPressed isOn keysPressed.left time  }
    40 -> { keysPressed | down =  updateKeyPressed isOn keysPressed.down time  }
    91 -> { keysPressed | meta =  updateKeyPressed isOn keysPressed.meta time  }
    _ -> keysPressed

updateKeyPressed : Bool -> Maybe Time -> Time -> Maybe Time
updateKeyPressed isOn maybeExistingTime newTime =
  if not isOn then
    Nothing
  else
    case maybeExistingTime of
      Just existingTime -> maybeExistingTime
      Nothing -> Just newTime


-- subscriptions ---------------------------------------------------------------

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Keyboard.downs KeyDown
    , Keyboard.ups KeyUp
    , Window.resizes Resize
    , AnimationFrame.diffs Frame
    , visibilityChanges Viz
    ]


-- view ------------------------------------------------------------------------

view : Model -> Html Msg
view model =
  let
    attempts = case model.phase of
      Playing level -> level.score
      _ ->
        case model.finishedLevels of
          level :: others -> level.score
          [] -> -1
    finCount = List.length model.finishedLevels
    remCount = List.length model.remainingLevels
    levelCount = case model.phase of
      Playing level -> finCount + remCount + 1
      _ -> finCount + remCount
    currentLevel = case model.phase of
      Playing level -> finCount + 1
      _ -> finCount
    parSoFar = Level.tallyPar model.finishedLevels
    prevTotalScore = Level.tallyScore model.finishedLevels
    totalScore = case model.phase of
      Playing level -> prevTotalScore + level.score
      _ -> prevTotalScore
    parCompare = prevTotalScore - parSoFar
    totalPar = case model.phase of
      Playing level -> (Level.tallyPar model.finishedLevels) + (Level.tallyPar model.remainingLevels) + 1
      _ -> (Level.tallyPar model.finishedLevels) + (Level.tallyPar model.remainingLevels)
    levelPar = case model.phase of
      Playing level -> level.par
      _ ->
        case model.finishedLevels of
          level :: others -> level.par
          [] -> -1
  in
    Html.div
      [ HAttr.id "game-main"
      , HAttr.style
        [ ("left", (toString model.playport.left) ++ "px")
        , ("top", (toString model.playport.top) ++ "px")
        , ("width", (toString model.playport.width) ++ "px")
        , ("height", (toString model.playport.height) ++ "px")
        , ("font-size", (toString model.playport.fontSize) ++ "px")
        ]
      ]
      [ playingFieldWrapper model.playport
        [ boundary
        , drawFields model
        , drawTarget model
        , drawBarriers model
        , drawCannon model
        , drawBall model.ball
        , drawTransition model
        , drawSplashBouncers model
        ]
      , drawLevelMessage model
      , drawSplash model
      , drawEndSplash model (attempts, levelPar) (currentLevel, levelCount) (totalScore, totalPar, parCompare)
      , drawTallies model (attempts, levelPar) (currentLevel, levelCount) (totalScore, totalPar, parCompare)
      , help
      , copyright
      ]

drawLevelMessage : Model -> Html Msg
drawLevelMessage model =
  case model.phase of
    Playing level ->
      case level.message of
        Nothing ->
          Html.p [] []
        Just message ->
          let
            (x, y) = message.pos
            wPct = (toString ((message.width / 1000) * 100)) ++ "%"
            yPct = (toString ((y / 1000) * 100)) ++ "%"
            xPct = case message.xAnchor of
              Level.C ->
                (toString (((x - (message.width / 2)) / 1000) * 100)) ++ "%"
              _ ->
                (toString ((x / 1000) * 100)) ++ "%"
            xAnchor = case message.xAnchor of
              Level.L -> "left"
              Level.R -> "right"
              Level.C -> "left"
            yAnchor = case message.yAnchor of
              Level.T -> "top"
              Level.B -> "bottom"
          in
            Html.p
              [ HAttr.class "level-message", HAttr.style [(xAnchor, xPct), (yAnchor, yPct), ("max-width",wPct)] ]
              [ Html.text message.text ]
    _ ->
      Html.p [] []

drawFields : Model -> Svg Msg
drawFields model =
  case model.phase of
    Playing level ->
      group (List.map drawField level.fields)
    _ ->
      emptyGroup

drawField : Phys.Field -> Svg Msg
drawField field =
  let
    (x, y) = field.pos
    tPosX = x
    tPosY = y - (field.outerRadius - 50)
    charge = if field.strength < 0 then
      toString field.strength
    else
      "+" ++ (toString field.strength)
  in
    group
      [ drawCircExt "field-inner" field.pos field.innerRadius [SAttr.fill "url(#field-center-gradient)"]
      , drawCirc "field-outer" field.pos field.outerRadius
      , Svg.text_ [attrX tPosX, attrY tPosY, attrClass "field field-label"] [Svg.text ("charge: " ++ charge)]
      ]

copyright : Html Msg
copyright =
  Html.p [ HAttr.class "copyright" ]
    [ Html.text "Copyright (c) 2017 by Greg Reimer - All Rights Reserved"
    ]

boundary : Svg Msg
boundary =
  drawBox "boundary" (Phys.gutter, Phys.gutter) (Phys.playableWidth, Phys.playableHeight)

help : Html Msg
help =
  Html.div
    [ HAttr.id "help" ]
    [ labeledSlashVal "Aim" "L" "R"
    , labeledVal "Drive" "SPC -> Release"
    , labeledVal "Putt" "SHIFT + SPC"
    , labeledVal "Reset" "u/U"
    ]

drawTallies : Model -> (Int, Int) -> (Int, Int) -> (Int, Int, Int) -> Html Msg
drawTallies model (attempts, levelPar) (currentLevel, levelCount) (totalScore, totalPar, parCompare) =
  let
    cannon = case model.phase of
      Starting bouncers cannon -> cannon
      Playing level -> level.cannon
      _ ->
        case model.finishedLevels of
          level :: rest -> level.cannon
          [] -> Cannon (0, 0) 0 0
    angle = formatDeg cannon.angle
    power = formatJoules cannon.power
  in
    Html.div [ HAttr.id "tallies" ]
      [ labeledSlashVal "Cur"
          (if attempts >= 0 then toString attempts else "-")
          (if levelPar >= 0 then toString levelPar else "-")
      , labeledSlashVal "Lev"
          (toString currentLevel)
          (toString levelCount)
      , labeledSlashVal "Tot"
          (toString totalScore)
          (toString totalPar)
      , labeledVal "+/-"
          (if parCompare > 0 then ("+" ++ (toString parCompare)) else toString parCompare)
      , labeledVal "D"
          angle
      , labeledVal "J"
          power
      ]

formatJoules : Float -> String
formatJoules j =
  String.padLeft 3 '0' (toString (round j))

formatDeg : Float -> String
formatDeg az =
  let
    absAz = abs az
    firstPart = toString (truncate absAz)
    secondPart = toString (rem (truncate (absAz * 10)) 10)
    joined = (String.padLeft 3 '0' firstPart) ++ "." ++ secondPart
  in
    joined

drawSplashBouncers : Model -> Svg Msg
drawSplashBouncers model =
  let
    maybeBouncers = case model.phase of
      Starting bouncers cannon -> Just bouncers
      Ending bouncers -> Just bouncers
      _ -> Nothing
  in
    case maybeBouncers of
      Just bouncers ->
        let
          drawnBalls = bouncers
            |> List.map (\b -> Just b)
            |> List.map drawBall
        in
          group drawnBalls
      Nothing ->
        emptyGroup

drawSplash : Model -> Html Msg
drawSplash model =
  case model.phase of
    Starting bouncers cannon ->
      Html.div
        [ HAttr.id "splash"
        ]
        [ Html.div [HAttr.id "splash-inner"]
          [ Html.h1 [] [Html.text "~ Electron Golf ~"]
          , Html.p []
            [ Html.text "Fire your electron cannon at the captive proton, but beware of high-energy quantum tunneling effects!"
            ]
          , drawCourseOptions
          , Html.p []
            [ Html.strong [] [Html.text "Aim: "]
            , Html.text "LEFT/RIGHT (+SHIFT/ALT to modify)."
            ]
          , Html.p []
            [ Html.strong [] [Html.text "Shoot: "]
            , Html.text "SPACEBAR to charge. Release to fire."
            ]
          , Html.p []
            [ Html.strong [] [Html.text "Putt: "]
            , Html.text "SHIFT while pressing SPACEBAR."
            ]
          , Html.p []
            [ Html.strong [] [Html.text "Start: "]
            , Html.text "Press SPACEBAR."
            ]
          , Html.p []
            [ Html.strong [] [Html.text "Reset: u"]
            , Html.text " level / "
            , Html.strong [] [Html.text "U"]
            , Html.text " game."
            ]
          ]
        ]
    _ ->
      Html.div [] []

drawCourseOptions : Html Msg
drawCourseOptions =
  let
    keys = [ "Beginner", "Intermediate", "Advanced" ]
  in
    Html.div
      [ HAttr.id "course-options" ]
      ( List.map drawCourseOption keys )

drawCourseOption : String -> Html Msg
drawCourseOption key =
  Html.button
    [ HAttr.class "course-option"
    , HEv.onClick (Start key)
    ]
    [ Html.text key
    ]

drawEndSplash : Model -> (Int, Int) -> (Int, Int) -> (Int, Int, Int) -> Html Msg
drawEndSplash model (attempts, levelPar) (currentLevel, levelCount) (totalScore, totalPar, parCompare) =
  case model.phase of
    Ending bouncers ->
      let
        absParCompare = abs parCompare
        asterisk = if model.resetCount > 0 then "*" else ""
        message = if parCompare <= -3 then "Fantastic!"
          else if parCompare <= -2 then "Terrific!"
          else if parCompare <= -1 then "Nicely Done!"
          else if parCompare <= 0 then "Well Done"
          else "Game Over"
        parMessage = if parCompare < 0 then Html.span [] [ Html.text "You shot ", val absParCompare, Html.text " under par."]
          else if parCompare == 0 then Html.text "You got par."
          else Html.span [] [ Html.text "You shot ", val absParCompare, Html.text " over par."]
        parFollowup = if parCompare <= -4 then "I suspect you cheated but I can't prove it."
          else if parCompare == -3 then "Heisenberg was wrong, apparently."
          else if parCompare == -2 then "I stand in awe of your prowess."
          else if parCompare == -1 then "Hats off to you."
          else if parCompare == 0 then "Solid game."
          else if parCompare == 1 then "That seems respectable."
          else if parCompare <= 3 then "Not too bad for a beginner."
          else if parCompare <= 6 then "You need to work on your foo."
          else if parCompare <= 10 then "...and you call yourself a scientist."
          else "Hint: lower scores are better."
        resetMessage = if model.resetCount > 0 then "* We noticed you pushed the do-over button. ಠ_ಠ"
        else ""
      in
        Html.div
          [ HAttr.id "splash"
          , HAttr.class "end-splash"
          ]
          [ Html.div [HAttr.id "splash-inner"]
            [ Html.h1 [] [Html.text (message ++ asterisk)]
            , Html.p []
              [ Html.text "You cleared "
              , Html.strong [ HAttr.class "value" ] [ Html.text (toString levelCount) ]
              , Html.text " protons in "
              , Html.strong [ HAttr.class "value" ] [ Html.text (toString totalScore) ]
              , Html.text " moves."
              ]
            , Html.p []
              [ Html.text "Course par was "
              , Html.strong [ HAttr.class "value" ] [ Html.text (toString totalPar) ]
              , Html.text ". "
              , parMessage
              ]
            , Html.p []
              [ Html.text parFollowup
              ]
            , drawCourseOptions
            , blurb
            , Html.p [ HAttr.class "reset-count" ]
              [ Html.text resetMessage
              ]
            ]
          ]
    _ ->
      Html.div [] []

drawTransition : Model -> Svg Msg
drawTransition model =
  case model.phase of
    Transitioning trans ->
      let
        oldLevel = List.head model.finishedLevels
        newLevel = List.head model.remainingLevels
      in
        case oldLevel of
          Just oldLevel -> drawTheTransition trans oldLevel newLevel
          Nothing -> emptyGroup
    _ ->
      emptyGroup

drawTheTransition : Transition -> Level -> Maybe Level -> Svg Msg
drawTheTransition transition oldLevel maybeNewLevel =
  case transition.phase of
    Transition.Migrating step ->
      let end = oldLevel.target.pos
      in drawMigration oldLevel transition.actionPoint end step
    Transition.Absorbing step ->
      let point = oldLevel.target.pos
      in drawAbsorption oldLevel point step
    Transition.Exploding step ->
      let point = oldLevel.target.pos
      in drawExplosion oldLevel point step
    Transition.Messaging step ->
      drawMessage oldLevel transition.message step
    Transition.Moving step ->
      let
        oldCannon = oldLevel.cannon
        oldTarget = oldLevel.target
        (newCannon, newTarget) = case maybeNewLevel of
          Just newLevel -> (newLevel.cannon, newLevel.target)
          Nothing -> (Cannon.thrownCannon, Target.thrownTarget)
      in
        drawMoving oldCannon oldTarget newCannon newTarget step

drawMigration : Level -> (Float, Float) -> (Float, Float) -> Float -> Svg Msg
drawMigration level (x1, y1) (x2, y2) step =
  let
    progLin = Transition.migrateProgress step
    prog = Ease.inQuad progLin
    xTween = x1 + ((x2 - x1) * prog)
    yTween = y1 + ((y2 - y1) * prog)
  in
    group
      [ drawTheCannon level.cannon
      , drawTheTarget 1 level.target
      , Gfx.ball (xTween, yTween) 22
      ]

drawAbsorption : Level -> (Float, Float) -> Float -> Svg Msg
drawAbsorption level (cx, cy) step =
  let
    progLin = Transition.explodeProgress step
    prog = Ease.outQuint progLin
    r = 22 - (prog * 22)
  in
    group
      [ drawTheCannon level.cannon
      , drawTheTarget (1 - prog) level.target
      , Gfx.ball (cx, cy) r
      ]

drawExplosion : Level -> (Float, Float) -> Float -> Svg Msg
drawExplosion level pos step =
  let
    prog = Transition.explodeProgress step
    oProg = Ease.outQuint prog
    r = (prog) * 160
    opac = 1.0 - oProg
    style = "opacity:" ++ (toString opac)
  in
    group
      [ drawTheCannon level.cannon
      , drawTheTarget 0 level.target
      , drawCircExt "transition-explosion" pos r [SAttr.style style, SAttr.fill "url(#explosion-gradient)"]
      ]

drawMessage : Level -> String -> Float -> Svg Msg
drawMessage level message step =
  let
    progLin = Transition.messageProgress step
    prog = Ease.inExpo progLin
    offset = prog * 100
    opac = 1.0 - progLin
  in
    group
      [ drawTheCannon level.cannon
      , drawTheTarget 0 level.target
      , Svg.text_
        [ attrX 500
        , attrY (500 - offset)
        , attrClass "transition-message"
        , SAttr.style ("opacity:" ++ (toString opac))
        ]
        [ Svg.text message
        ]
      ]

drawMoving : Cannon -> Target -> Cannon -> Target -> Float -> Svg Msg
drawMoving oldCannon oldTarget newCannon newTarget step =
  let
    progLin = Transition.moveProgress step
    prog = Ease.inOutQuint progLin
    tweenCannon = Cannon.tweenCannon prog oldCannon newCannon
    tweenTarget = Target.tweenTarget prog oldTarget newTarget
  in
    group [ drawTheTarget prog tweenTarget, drawTheCannon tweenCannon ]

drawTarget : Model -> Svg Msg
drawTarget model =
  case model.phase of
    Playing level -> drawTheTarget 1 level.target
    _ -> emptyGroup

drawTheTarget : Float -> Target -> Svg Msg
drawTheTarget protonSize target =
  Gfx.target target.pos protonSize target.size

drawBall : Maybe Phys.Obj -> Svg Msg
drawBall ball =
  case ball of
    Just ball ->
      case ball.shape of
        Bodies.Bubble radius ->
          Gfx.ball ball.pos radius
        Bodies.Box vec ->
          emptyGroup
    Nothing ->
      emptyGroup

drawCannon : Model -> Svg Msg
drawCannon model =
  case model.phase of
    Starting bouncers cannon -> drawTheCannon cannon
    Playing level -> drawTheCannon level.cannon
    _ -> emptyGroup

drawTheCannon : Cannon -> Svg Msg
drawTheCannon cannon =
  Gfx.cannon cannon.pos cannon.power cannon.angle

drawBarriers : Model -> Svg Msg
drawBarriers model =
  case model.phase of
    Playing level -> lazy drawTheBarriers level.barriers
    _ -> emptyGroup

drawTheBarriers : List Phys.Obj -> Svg Msg
drawTheBarriers barriers =
  group (List.map drawBarrier barriers)

drawBarrier : Phys.Obj -> Svg Msg
drawBarrier barrier =
  case barrier.shape of
    Bodies.Bubble r ->
      let
        circ = drawCirc "barrier" barrier.pos r
      in
        if barrier.inverseMass /= 0 then
          group
            [ circ
            , drawCirc "barrier-inner" barrier.pos (r * 0.8)
            ]
        else
          circ
    Bodies.Box (halfWidth, halfHeight) ->
      let
        (cx, cy) = barrier.pos
        x = cx - halfWidth
        y = cy - halfHeight
        width = halfWidth * 2
        height = halfHeight * 2
      in
        drawBox "barrier" (x, y) (width, height)
