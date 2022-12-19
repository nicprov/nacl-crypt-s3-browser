module Pages.Login exposing (Model, Msg, page)

import Common.Alert exposing (viewAlertError)
import Gen.Route
import Html exposing (Html, a, br, button, div, form, h1, hr, i, img, input, label, li, main_, ol, option, p, select, small, span, text)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onInput)
import S3.Types
import List exposing (head)
import Page
import Request exposing (Request)
import Shared
import Storage exposing (signIn)
import View exposing (View)


page : Shared.Model -> Request -> Page.With Model Msg
page shared req =
    Page.element
        { init = init
        , update = update shared req
        , view = view shared
        , subscriptions = \_ -> Sub.none
        }

type Status
    = Error String
    | None

type alias Model =
    { account: S3.Types.Account
    , status: Status
    , encryptionKey: String
    , salt: String
    }

init : (Model, Cmd Msg)
init =
    (Model (S3.Types.Account "S3" (Just "") False "" "" []) None "" "", Cmd.none)

-- Update

type Msg
    = ChangeRegion String
    | ChangeIsDigitalOcean String
    | ChangeAccessKey String
    | ChangeSecretKey String
    | ChangeBucket String
    | ChangeEncryptionKey String
    | ChangedSalt String
    | ClickedSignIn

stringFromBool : Bool -> String
stringFromBool value =
  if value then
    "True"
  else
    "False"

boolFromString : String -> Bool
boolFromString value =
  if value == "True" then
    True
  else
    False


update: Shared.Model -> Request -> Msg -> Model -> (Model, Cmd Msg)
update shared req msg model =
    case msg of
        ChangeRegion region ->
            let
                oldAccount = model.account
                newAccount = { oldAccount | region = Just region }
            in
            ( { model | account = newAccount }, Cmd.none)

        ChangeIsDigitalOcean isDigitalOcean ->
            let
                oldAccount = model.account
                newAccount = { oldAccount | isDigitalOcean = (boolFromString isDigitalOcean) }
            in
            ( { model | account = newAccount }, Cmd.none)

        ChangeAccessKey accessKey ->
            let
                oldAccount = model.account
                newAccount = { oldAccount | accessKey = accessKey }
            in
            ( { model | account = newAccount }, Cmd.none)


        ChangeBucket bucket ->
            let
                oldAccount = model.account
                newAccount = { oldAccount | buckets = [bucket] }
            in
            ( { model | account = newAccount }, Cmd.none)

        ChangeSecretKey secretKey ->
            let
                oldAccount = model.account
                newAccount = { oldAccount | secretKey = secretKey }
            in
            ( { model | account = newAccount }, Cmd.none)


        ChangeEncryptionKey encryptionKey ->
            ( { model | encryptionKey = encryptionKey }, Cmd.none)


        ChangedSalt salt ->
            ( { model | salt = salt }, Cmd.none)

        ClickedSignIn ->
            if model.account.accessKey == "" then
                ( { model | status = Error "Access Key cannot be empty"}, Cmd.none)
            else if model.account.secretKey == "" then
                ( { model | status = Error "Endpoint cannot be empty"}, Cmd.none)
            else if model.account.buckets == [] then
                ( { model | status = Error "Bucket cannot be empty"}, Cmd.none)
            else if model.encryptionKey == "" then
                ( { model | status = Error "Encryption key cannot be empty"}, Cmd.none)
            else
                (model, Cmd.batch [ Storage.signIn model.account model.encryptionKey model.salt shared.storage
                                  , Request.replaceRoute Gen.Route.Home_ req
                                  ]
                )

-- View

view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Login"
    , body = [ viewMain model
             ]
    }

viewMain: Model -> Html Msg
viewMain model =
    div
        [ Attr.id "wrapper"
        ]
        [ div
            [ Attr.attribute "data-v" ""
            ]
            [
            div
                [ Attr.attribute "data-v" ""
                , Attr.id "login"
                , Attr.class "columns is-centered"
                ]
                [ div
                    [ Attr.attribute "data-v" ""
                    , Attr.class "column is-narrow"
                    ]
                    [ div
                        [ Attr.attribute "data-v" ""
                        , Attr.attribute "data-bitwarden-watching" "1"
                        ]
                        [ div
                            [ Attr.attribute "data-v" ""
                            , Attr.class "box"
                            ]
                            [ div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "has-text-centered"
                                ]
                                [ img
                                    [ Attr.attribute "data-v" ""
                                    , Attr.src "/img/logo.png"
                                    , Attr.class "logo"
                                    ]
                                    []
                                ]
                            , br
                                [ Attr.attribute "data-v" ""
                                ]
                                []
                            , (case model.status of
                                    Error msg -> viewAlertError msg
                                    None -> div [] []
                                )
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Region" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right"
                                    ]
                                    [ input
                                        [ Attr.type_ "text"
                                        , Attr.class "input"
                                        , Attr.value ( case model.account.region of
                                                     Just region -> region
                                                     Nothing -> ""
                                                 )
                                             , onInput ChangeRegion
                                        ]
                                        []
                                    , small
                                        [ Attr.class "form-text text-muted"
                                        ]
                                        [ text "S3 region used (ie. us-west-1 for AWS, or nyc3 for Digital Ocean)" ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Is Digital Ocean" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right"
                                    ]
                                    [ select
                                        [ Attr.class "form-control"
                                        , Attr.id "exampleFormControlSelect1"
                                        , Attr.value (stringFromBool model.account.isDigitalOcean)
                                        , onInput ChangeIsDigitalOcean
                                        ]
                                        [ option []
                                            [ text "False" ]
                                        , option []
                                            [ text "True" ]
                                        ]
                                    , small
                                        [ Attr.class "form-text text-muted"
                                        ]
                                        [ text "Indicate whether the bucket is hosted on AWS or Digital Ocean" ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Bucket Name" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right"
                                    ]
                                    [ input
                                        [ Attr.type_ "text"
                                        , Attr.class "input"
                                        , Attr.value (case (head model.account.buckets) of
                                            Just item -> item
                                            Nothing -> ""
                                            )
                                        , onInput ChangeBucket
                                        ]
                                        []
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Access Key" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right"
                                    ]
                                    [ input
                                        [ Attr.type_ "text"
                                        , Attr.class "input"
                                        , Attr.value model.account.accessKey
                                        , onInput ChangeAccessKey
                                        ]
                                        []
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Secret Key" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right is-clearfix"
                                    ]
                                    [ input
                                        [ Attr.type_ "password"
                                        , Attr.class "input"
                                        , Attr.value model.account.secretKey
                                        , onInput ChangeSecretKey
                                        ]
                                        []
                                    ,
                                    span
                                        [ Attr.class "icon is-right has-text-primary is-clickable"
                                        ]
                                        [ i
                                            [ Attr.class "fas fa-eye fa-lg"
                                            ]
                                            []
                                        ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Encryption Key" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right is-clearfix"
                                    ]
                                    [ input
                                        [ Attr.type_ "password"
                                        , Attr.class "input"
                                        , Attr.value model.encryptionKey
                                        , onInput ChangeEncryptionKey
                                        ]
                                        []
                                    , small
                                        [ Attr.class "form-text text-muted"
                                        ]
                                        [ text "Must be the encryption key found in the rclone config file because it is padded" ]
                                    , span
                                        [ Attr.class "icon is-right has-text-primary is-clickable"
                                        ]
                                        [ i
                                            [ Attr.class "fas fa-eye fa-lg"
                                            ]
                                            []
                                        ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "field"
                                ]
                                [ label
                                    [ Attr.class "label"
                                    ]
                                    [ text "Salt" ]
                                , div
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "control has-icons-right is-clearfix"
                                    ]
                                    [ input
                                        [ Attr.type_ "password"
                                        , Attr.class "input"
                                        , Attr.value model.salt
                                        , onInput ChangedSalt
                                        ]
                                        []
                                    , small
                                        [ Attr.class "form-text text-muted"
                                        ]
                                        [ text "Optional (leave blank for empty), but must be the salt found in the rclone config file (named Password2) because it is padded" ]
                                    , span
                                        [ Attr.class "icon is-right has-text-primary is-clickable"
                                        ]
                                        [ i
                                            [ Attr.class "fas fa-eye fa-lg"
                                            ]
                                            []
                                        ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v" ""
                                , Attr.class "is-flex is-justify-end"
                                ]
                                [ button
                                    [ Attr.attribute "data-v" ""
                                    , Attr.class "button is-primary"
                                    , onClick ClickedSignIn
                                    ]
                                    [ text "Log in" ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]