module Pages.Home_ exposing (Model, Msg, page)

import Base64
import Bytes exposing (Bytes)
import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Common.Alert exposing (viewAlertError)
import Dict exposing (Dict)
import File.Download as Download
import Gen.Route
import Html exposing (Html, a, button, div, hr, i, img, input, label, li, nav, ol, option, section, select, span, table, tbody, td, text, th, thead, tr, ul)
import Html.Attributes as Attr
import Html.Events exposing (onClick)
import List exposing (head)
import List.Extra as LE exposing (uniqueBy)
import Page
import Request exposing (Request)
import S3
import S3.Types exposing (Error, KeyList, QueryElement(..))
import Shared exposing (KeyInfoDecrypted, KeyListDecrypted, KeyListDescriptionMessage, decryptFile, decryptKeyList, FileDescriptionMessage)
import Storage
import Task
import View exposing (View)


page : Shared.Model -> Request -> Page.With Model Msg
page shared req =
    Page.element
        { init = init shared
        , update = update shared req
        , view = view shared
        , subscriptions = subscriptions
        }

type alias Model =
    { display: String
    , keyList: Maybe KeyListDecrypted
    , currentDir: String
    , folderList: List(KeyInfoDecrypted)
    , selectedList: List(KeyInfoDecrypted)
    , expandedItem: String
    , key: String
    , text: String
    , headers : List ( String, String )
    }

init : Shared.Model -> (Model, Cmd Msg)
init shared =
    (Model "" Nothing "" [] [] "" "" "" []
    , case shared.storage.account of
        Just account ->
            listBucket account
        Nothing ->
            Cmd.none
    )

-- Update

type Msg
    = ReceiveListBucket (Result Error KeyList)
    | ReceiveDeleteObject (Result Error String)
    | ReceiveGetObjectBytes (Result Error ( Bytes ))
    | ListBucket
    | ClickedFolder String
    | ClickedBack
    | ClickedLogout
    | ClickedSelected KeyInfoDecrypted
    | ClickedFilePath String
    | ClickedDropdown String
    | ClickedDownload KeyInfoDecrypted
    | ClickedRename String
    | ClickedDelete String
    | ClickedCopyLink String
    | ReceivedDecryptedKeyList KeyListDecrypted
    | ReceivedDecryptedFile String

listBucket : S3.Types.Account -> Cmd Msg
listBucket account =
    let
        bucket = (case (head account.buckets) of
            Just b -> b
            Nothing -> ""
            )
    in
    S3.listKeys bucket
        |> S3.addQuery [ MaxKeys 100 ]
        |> S3.send account
        |> Task.attempt ReceiveListBucket

deleteObject : S3.Types.Account -> String -> Cmd Msg
deleteObject account key =
    let
        bucket = (case (head account.buckets) of
            Just b -> b
            Nothing -> ""
            )
    in
    S3.deleteObject bucket key
        |> S3.send account
        |> Task.attempt ReceiveDeleteObject

getBytesObject : S3.Types.Account -> String -> Cmd Msg
getBytesObject account key  =
    let
        bucket = (case (head account.buckets) of
            Just b -> b
            Nothing -> ""
            )
    in
    S3.getBytesObject bucket key
        |> S3.sendBytes account
        |> Task.attempt ReceiveGetObjectBytes

removeFiles: KeyInfoDecrypted ->  KeyInfoDecrypted
removeFiles key =
    let
        file = String.split "/" key.keyDecrypted
    in
    case List.head (List.reverse file) of
        Just element ->
            if element == "" then -- already a folder, do nothing
                key
            else
                let
                    tempName = List.drop 1 (List.reverse file) -- drop file name
                    fixedName = List.map (\m -> m ++ "/") tempName
                in
                { key | keyDecrypted = String.concat fixedName}
        Nothing ->
            key


isFolder: KeyInfoDecrypted -> Bool
isFolder key =
    let
        file = String.split "/" key.keyDecrypted
    in
    if (List.length file) >= 2 then
        True
    else
        False


bytesToList : Bytes -> List Int
bytesToList bytes =
    let
        listDecode =
            bytesListDecode Decode.unsignedInt8 (Bytes.width bytes)
    in
    Maybe.withDefault [] (Decode.decode listDecode bytes)

bytesListDecode : Decode.Decoder a -> Int -> Decode.Decoder (List a)
bytesListDecode decoder len =
    Decode.loop ( len, [] ) (listStep decoder)

listStep : Decode.Decoder a -> ( Int, List a ) -> Decode.Decoder (Decode.Step ( Int, List a ) (List a))
listStep decoder ( n, xs ) =
    if n <= 0 then
        Decode.succeed (Decode.Done xs)

    else
        Decode.map (\x -> Decode.Loop ( n - 1, x :: xs )) decoder


update: Shared.Model -> Request -> Msg -> Model -> (Model, Cmd Msg)
update shared req msg model =
    case msg of

        ListBucket ->
            case shared.storage.account of
                Just acc ->
                    ( { model | display = "Getting bucket listing..." }
                    , listBucket acc
                    )
                Nothing -> (model, Cmd.none)

        ReceiveListBucket result ->
            case result of
                Err err ->
                    ( { model | display = Debug.toString err }
                    , Cmd.none
                    )

                Ok keys ->
                    ( model, decryptKeyList (KeyListDescriptionMessage keys shared.storage.encryptionKey shared.storage.salt))

        ClickedFolder folder ->
            ( { model | currentDir = folder, expandedItem = "" }, Cmd.none)


        ClickedBack ->
            let
                tempList = List.reverse (List.drop 2 (List.reverse (String.split "/" model.currentDir)))
                newDirList =  List.map (\m -> m ++ "/") tempList
            in
            ( { model | currentDir = String.concat newDirList }, Cmd.none)

        ClickedLogout ->
            ( model, Cmd.batch [ Storage.signOut shared.storage
                               , Request.replaceRoute Gen.Route.Login req
                               ]
            )

        ClickedFilePath dir ->
            ( model, Cmd.none )

        ReceivedDecryptedKeyList keyList ->
            let
                reducedFolder = List.map removeFiles keyList.keys
                folders = List.filter isFolder reducedFolder
            in
            ( { model
                | display = "Bucket listing received."
                , keyList = Just keyList
                , folderList = uniqueBy (\k -> k.keyDecrypted) folders
              }
            , Cmd.none
            )

        ClickedSelected keyInfo ->
            if List.member keyInfo model.selectedList then
                ( { model | selectedList = (List.filter (\x -> x /= keyInfo) model.selectedList) }, Cmd.none ) -- Remove item from list
            else
                ( { model | selectedList = (List.append [keyInfo] model.selectedList) }, Cmd.none ) -- Add item to list

        ClickedDropdown item ->
            if model.expandedItem == item then
                ( { model | expandedItem = "" }, Cmd.none)
            else
                ( { model | expandedItem = item }, Cmd.none )

        ClickedDownload key ->
            case shared.storage.account of
                Just acc ->
                    ( { model | expandedItem = "", key = key.keyDecrypted }
                    , getBytesObject acc key.keyEncrypted
                    )
                Nothing -> (model, Cmd.none)

        ClickedRename key ->
            case shared.storage.account of
                Just acc ->
                    ( { model | expandedItem = "" }
                    , Cmd.none
                    )
                Nothing -> (model, Cmd.none)

        ClickedDelete key ->
            case shared.storage.account of
                Just acc ->
                    ( { model | expandedItem = "" }
                    , deleteObject acc key
                    )
                Nothing -> (model, Cmd.none)


        ClickedCopyLink key ->
            case shared.storage.account of
                Just acc ->
                    ( { model | expandedItem = "" }
                    , Cmd.none
                    )
                Nothing -> (model, Cmd.none)

        ReceiveDeleteObject result ->
            case result of
                Err err ->
                    ( { model | display = Debug.toString err }
                    , Cmd.none
                    )

                Ok res ->
                    case shared.storage.account of
                        Just acc ->
                            ( { model | display = res, expandedItem = "" }
                            , listBucket acc -- Should simply update keyList instead, but used for debugging because delete not working
                            )
                        Nothing -> (model, Cmd.none)

        ReceivedDecryptedFile decryptedFile ->
            ( model
            , Download.string model.key "text" decryptedFile
            )

        ReceiveGetObjectBytes result ->
            case result of
                Err err ->
                    ( { model | display = Debug.toString err }
                    , Cmd.none
                    )

                Ok ( res ) ->
                    case Base64.fromBytes res of
                        Just s ->
                            ( model, decryptFile (FileDescriptionMessage s shared.storage.encryptionKey shared.storage.salt))
                        Nothing ->
                            ( model, Cmd.none) -- TODO show error message

-- Listen for shared model changes

subscriptions: Model -> Sub Msg
subscriptions model =
    Sub.batch [subscriptionFile model , subscriptionKeyList model]

subscriptionFile: Model -> Sub Msg
subscriptionFile _ =
    Shared.decryptedFile ReceivedDecryptedFile

subscriptionKeyList : Model -> Sub Msg
subscriptionKeyList _ =
    Shared.decryptedKeyList ReceivedDecryptedKeyList


-- View

view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "File Manager"
    , body = [ viewMain model shared.storage.account
             ]
    }

viewMain: Model -> Maybe S3.Types.Account-> Html Msg
viewMain model account =
    div
        [ Attr.id "wrapper"
        ]
        [ div
            [ Attr.id "inner"
            ]
            [ div
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.id "dropzone"
                , Attr.class "container"
                ]
                [ div
                    [ Attr.attribute "data-v-07f55d0a" ""
                    , Attr.attribute "data-v-081c0a81" ""
                    ]
                    []
                , div
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.class "container"
                    ]
                    [ nav
                        [ Attr.attribute "data-v-cd57c856" ""
                        , Attr.attribute "data-v-081c0a81" ""
                        , Attr.attribute "role" "navigation"
                        , Attr.attribute "aria-label" "main navigation"
                        , Attr.class "navbar"
                        ]
                        [ div
                            [ Attr.attribute "data-v-cd57c856" ""
                            , Attr.class "navbar-brand"
                            ]
                            [ a
                                [ Attr.attribute "data-v-cd57c856" ""
                                , Attr.class "navbar-item logo"
                                ]
                                [ img
                                    [ Attr.attribute "data-v-cd57c856" ""
                                    , Attr.src "/img/logo.png"
                                    ]
                                    []
                                ]
                            , a
                                [ Attr.attribute "data-v-cd57c856" ""
                                , Attr.attribute "role" "button"
                                , Attr.attribute "aria-label" "menu"
                                , Attr.attribute "aria-expanded" "false"
                                , Attr.class "navbar-burger burger"
                                ]
                                [ span
                                    [ Attr.attribute "data-v-cd57c856" ""
                                    , Attr.attribute "aria-hidden" "true"
                                    ]
                                    []
                                , span
                                    [ Attr.attribute "data-v-cd57c856" ""
                                    , Attr.attribute "aria-hidden" "true"
                                    ]
                                    []
                                , span
                                    [ Attr.attribute "data-v-cd57c856" ""
                                    , Attr.attribute "aria-hidden" "true"
                                    ]
                                    []
                                ]
                            ]
                        , div
                            [ Attr.attribute "data-v-cd57c856" ""
                            , Attr.class "navbar-menu"
                            ]
                            [ div
                                [ Attr.attribute "data-v-cd57c856" ""
                                , Attr.class "navbar-end"
                                ]
                                [ a
                                    [ Attr.attribute "data-v-cd57c856" ""
                                    , Attr.style "color" "#253b6e"
                                    , Attr.style "font-weight" "600"
                                    , Attr.class "navbar-item logout"
                                    ]
                                    [ text "Log out" ]
                                ]
                            ]
                        ]
                    , div
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.id "browser"
                        ]
                        [ div
                            [ Attr.attribute "data-v-081c0a81" ""
                            , Attr.class "is-flex is-justify-between"
                            ]
                            [ div
                                [ Attr.attribute "data-v-081c0a81" ""
                                , Attr.attribute "aria-label" "breadcrumbs"
                                , Attr.class "breadcrumb"
                                , Attr.style "background-color" "white"
                                , Attr.style "padding-left" "0"
                                ]
                                [ ul
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    ]
                                    ( case account of
                                        Just a ->
                                            ( List.append [viewFilePath
                                                (case (List.head a.buckets) of
                                                    Just bucket ->
                                                        bucket
                                                    Nothing ->
                                                        ""
                                                )
                                                ]
                                              (List.map viewFilePath (String.split "/" model.currentDir))
                                            )
                                        Nothing ->
                                            (List.map viewFilePath (String.split "/" model.currentDir))
                                    )
                                ]
                            , div
                                [ Attr.attribute "data-v-081c0a81" ""
                                ]
                                [ a
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    , Attr.id "search"
                                    , Attr.class "search-btn"
                                    , Attr.href "#"
                                    ]
                                    [ span
                                        [ Attr.attribute "data-v-081c0a81" ""
                                        , Attr.class "icon is-small"
                                        ]
                                        [ i
                                            [ Attr.class "fas fa-search"
                                            ]
                                            []
                                        ]
                                    ]
                                ]
                            ]
                        , section
                            [ Attr.attribute "data-v-081c0a81" ""
                            , Attr.id "multi-actions"
                            , Attr.class "is-flex is-justify-between"
                            ]
                            [ div
                                [ Attr.attribute "data-v-081c0a81" ""
                                ]
                                [ div
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    , Attr.class "field file is-inline-block"
                                    ]
                                    [ label
                                        [ Attr.attribute "data-v-081c0a81" ""
                                        , Attr.class "upload control"
                                        ]
                                        [ a
                                            [ Attr.attribute "data-v-081c0a81" ""
                                            , Attr.class "is-inline-block"
                                            ]
                                            [ span
                                                [ Attr.attribute "data-v-081c0a81" ""
                                                , Attr.class "icon is-small"
                                                ]
                                                [ i
                                                    [ Attr.class "fas fa-upload"
                                                    ]
                                                    []
                                                ]
                                            , text " Upload file" ]
                                        , input
                                            [ Attr.type_ "file"
                                            , Attr.multiple True
                                            , Attr.class ""
                                            ]
                                            []
                                        ]
                                    ]
                                , a
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    , Attr.class "add-new is-inline-block"
                                    , Attr.href "#"
                                    ]
                                    [ div
                                        [ Attr.attribute "data-v-081c0a81" ""
                                        , Attr.class "dropdown is-mobile-modal"
                                        ]
                                        [ div
                                            [ Attr.attribute "role" "button"
                                            , Attr.attribute "aria-haspopup" "true"
                                            , Attr.class "dropdown-trigger"
                                            ]
                                            [ span
                                                [ Attr.attribute "data-v-081c0a81" ""
                                                ]
                                                [ span
                                                    [ Attr.attribute "data-v-081c0a81" ""
                                                    , Attr.class "icon is-small"
                                                    ]
                                                    [ i
                                                        [ Attr.class "fas fa-plus"
                                                        ]
                                                        []
                                                    ]
                                                , text " New" ]
                                            ]
                                        , div
                                            [ Attr.attribute "aria-hidden" "true"
                                            , Attr.class "background"
                                            , Attr.style "display" "none"
                                            ]
                                            []
                                        , div
                                            [ Attr.attribute "aria-hidden" "true"
                                            , Attr.class "dropdown-menu"
                                            , Attr.style "display" "none"
                                            ]
                                            [ div
                                                [ Attr.attribute "role" "list"
                                                , Attr.class "dropdown-content"
                                                ]
                                                [ a
                                                    [ Attr.attribute "data-v-081c0a81" ""
                                                    , Attr.attribute "role" "listitem"
                                                    , Attr.tabindex 0
                                                    , Attr.class "dropdown-item"
                                                    ]
                                                    [ span
                                                        [ Attr.attribute "data-v-081c0a81" ""
                                                        , Attr.class "icon is-small"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-folder"
                                                            ]
                                                            []
                                                        ]
                                                    , text "Folder" ]
                                                , a
                                                    [ Attr.attribute "data-v-081c0a81" ""
                                                    , Attr.attribute "role" "listitem"
                                                    , Attr.tabindex 0
                                                    , Attr.class "dropdown-item"
                                                    ]
                                                    [ span
                                                        [ Attr.attribute "data-v-081c0a81" ""
                                                        , Attr.class "icon is-small"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-file"
                                                            ]
                                                            []
                                                        ]
                                                    , text "File" ]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            , div
                                [ Attr.attribute "data-v-081c0a81" ""
                                , Attr.id "pagination"
                                ]
                                [ div
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    ]
                                    [ div
                                        [ Attr.class "control"
                                        ]
                                        [ span
                                            [ Attr.class "select is-small"
                                            ]
                                            [ select []
                                                [ option
                                                    [ Attr.value ""
                                                    ]
                                                    [ text "No pagination" ]
                                                , option
                                                    [ Attr.value "5"
                                                    ]
                                                    [ text "5 Per Page" ]
                                                , option
                                                    [ Attr.value "10"
                                                    ]
                                                    [ text "10 Per Page" ]
                                                , option
                                                    [ Attr.value "15"
                                                    ]
                                                    [ text "15 Per Page" ]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        , div
                            [ Attr.attribute "data-v-081c0a81" ""
                            , Attr.class "b-table"
                            ]
                            [ div
                                [ Attr.class "field table-mobile-sort"
                                ]
                                [ div
                                    [ Attr.class "field has-addons"
                                    ]
                                    [ div
                                        [ Attr.class "control is-expanded"
                                        ]
                                        [ span
                                            [ Attr.class "select is-fullwidth"
                                            ]
                                            [ select []
                                                [ option
                                                    [ Attr.value "[object Object]"
                                                    ]
                                                    [ text "Name" ]
                                                , option
                                                    [ Attr.value "[object Object]"
                                                    ]
                                                    [ text "Size" ]
                                                , option
                                                    [ Attr.value "[object Object]"
                                                    ]
                                                    [ text "Time" ]
                                                ]
                                            ]
                                        ]
                                    , div
                                        [ Attr.class "control"
                                        ]
                                        [ button
                                            [ Attr.class "button is-primary"
                                            ]
                                            [ span
                                                [ Attr.class "icon is-small"
                                                ]
                                                [ i
                                                    [ Attr.class "fas fa-arrow-up"
                                                    ]
                                                    []
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            , div
                                [ Attr.class "table-wrapper"
                                ]
                                [ table
                                    [ Attr.class "table has-mobile-cards is-hoverable"
                                    ]
                                    [ thead []
                                        [ tr []
                                            [ th
                                                [ Attr.class "checkbox-cell"
                                                ]
                                                [ label
                                                    [ Attr.class "b-checkbox checkbox"
                                                    ]
                                                    [ input
                                                        [ Attr.type_ "checkbox"
                                                        , Attr.attribute "true-value" "true"
                                                        , Attr.value "false"
                                                        ]
                                                        []
                                                    , span
                                                        [ Attr.class "check"
                                                        ]
                                                        []
                                                    , span
                                                        [ Attr.class "control-label"
                                                        ]
                                                        []
                                                    ]
                                                ]
                                            , th
                                                [ Attr.class "is-current-sort is-sortable"
                                                ]
                                                [ div
                                                    [ Attr.class "th-wrap"
                                                    ]
                                                    [ text "Name", span
                                                        [ Attr.class "icon is-small"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-arrow-up"
                                                            ]
                                                            []
                                                        ]
                                                    ]
                                                ]
                                            , th
                                                [ Attr.class "is-sortable"
                                                , Attr.style "width" "150px"
                                                ]
                                                [ div
                                                    [ Attr.class "th-wrap is-numeric"
                                                    ]
                                                    [ text "Size", span
                                                        [ Attr.class "icon is-small"
                                                        , Attr.style "display" "none"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-arrow-up"
                                                            ]
                                                            []
                                                        ]
                                                    ]
                                                ]
                                            , th
                                                [ Attr.class "is-sortable"
                                                , Attr.style "width" "200px"
                                                ]
                                                [ div
                                                    [ Attr.class "th-wrap is-numeric"
                                                    ]
                                                    [ text "Time", span
                                                        [ Attr.class "icon is-small"
                                                        , Attr.style "display" "none"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-arrow-up"
                                                            ]
                                                            []
                                                        ]
                                                    ]
                                                ]
                                            , th
                                                [ Attr.class ""
                                                , Attr.style "width" "51px"
                                                ]
                                                [ div
                                                    [ Attr.class "th-wrap"
                                                    ]
                                                    [ span
                                                        [ Attr.class "icon is-small"
                                                        , Attr.style "display" "none"
                                                        ]
                                                        [ i
                                                            [ Attr.class "fas fa-arrow-up"
                                                            ]
                                                            []
                                                        ]
                                                    ]
                                                ]
                                            ]
                                        ]
                                    , tbody []
                                        (case model.keyList of
                                            Just keyList ->
                                                if List.length keyList.keys /= 0 then
                                                    (List.append
                                                        (List.append (viewBack model) (List.map (viewFolderItem model) model.folderList))
                                                        (List.map (viewFileItem model) keyList.keys)
                                                    )
                                                else
                                                    [viewAlertError "No files to show"]
                                            Nothing -> []
                                        )
                                    ]
                                ]
                            ]
                        , section
                            [ Attr.attribute "data-v-081c0a81" ""
                            , Attr.id "bottom-info"
                            , Attr.class "is-flex is-justify-between"
                            ]
                            [ div
                                [ Attr.attribute "data-v-081c0a81" ""
                                ]
                                [ span
                                    [ Attr.attribute "data-v-081c0a81" ""
                                    ]
                                    [ text ("Selected: " ++ (String.fromInt (List.length model.selectedList))) ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

viewFilePath: String -> Html Msg
viewFilePath dir =
    li
    [ Attr.attribute "data-v-081c0a81" ""
    ]
    [ a
        [ Attr.attribute "data-v-081c0a81" ""
        , Attr.href "#"
        , onClick (ClickedFilePath dir)
        ]
        [ text dir ]
    ]


viewFileItem: Model -> KeyInfoDecrypted -> Html Msg
viewFileItem model key =
    if String.contains model.currentDir key.keyDecrypted then
        let
            name = String.replace model.currentDir "" key.keyDecrypted
            file = String.split "/" name
        in
        if name /= "" && (List.length file) == 1 then
            viewFile model key
        else
            div [] []
    else
        div [] []

viewFile: Model -> KeyInfoDecrypted -> Html Msg
viewFile model key =
    let
        name = String.replace model.currentDir "" key.keyDecrypted
    in
    tr
        [ Attr.draggable "false"
        , Attr.class "file-row type-file"
        ]
        [ td
            [ Attr.class "checkbox-cell"
            ]
            [ label
                [ Attr.class "b-checkbox checkbox"
                ]
                [ input
                    [ Attr.type_ "checkbox"
                    , Attr.attribute "true-value" "true"
                    , Attr.value "false"
                    , onClick (ClickedSelected key)
                    ]
                    []
                , span
                    [ Attr.class "check"
                    ]
                    []
                , span
                    [ Attr.class "control-label"
                    ]
                    []
                ]
            ]
        , td
            [ Attr.attribute "data-v-081c0a81" ""
            , Attr.attribute "data-label" "Name"
            , Attr.class ""
            ]
            [ span []
                [ a
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.class "is-block name"
                    , Attr.href "#"
                    ]
                    [ text name ]
                ]
            ]
        , td
            [ Attr.attribute "data-v-081c0a81" ""
            , Attr.attribute "data-label" "Size"
            , Attr.class "has-text-right"
            ]
            [ span []
                [ text (String.fromInt key.size ++ " Bytes") ]
            ]
        , td
            [ Attr.attribute "data-v-081c0a81" ""
            , Attr.attribute "data-label" "Time"
            , Attr.class "has-text-right"
            ]
            [ span []
                [ text key.lastModified ]
            ]
        , td
            [ Attr.attribute "data-v-081c0a81" ""
            , Attr.class ""
            , Attr.id "single-actions"
            ]
            [ span []
                (viewDropdown model key)
            ]
        ]

viewDropdown: Model -> KeyInfoDecrypted -> List (Html Msg)
viewDropdown model key =
    [ div
        [ Attr.attribute "data-v-081c0a81" ""
        , if key.keyDecrypted == model.expandedItem then
            Attr.class "dropdown is-bottom-left is-active is-mobile-modal"
         else
            Attr.class "dropdown is-bottom-left is-mobile-modal"
        ]
        [ div
            [ Attr.attribute "role" "button"
            , Attr.attribute "aria-haspopup" "true"
            , Attr.class "dropdown-trigger"
            ]
            [ button
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.class "button is-small"
                , onClick (ClickedDropdown key.keyDecrypted)
                ]
                [ span
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.class "icon is-small"
                    ]
                    [ i
                        [ Attr.class "fas fa-ellipsis-h"
                        ]
                        []
                    ]
                ]
            ]
        , div
            [ Attr.attribute "aria-hidden" "true"
            , Attr.class "background"
            , Attr.style "display" "none"
            ]
            []
        , div
            [ Attr.attribute "aria-hidden" "true"
            , Attr.class "dropdown-menu"
            , if key.keyDecrypted == model.expandedItem then
                Attr.style "" ""
              else
               Attr.style "display" "none"
            ]
            [ div
                [ Attr.attribute "role" "list"
                , Attr.class "dropdown-content"
                ]
                [ a
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.attribute "role" "listitem"
                    , Attr.tabindex 0
                    , Attr.class "dropdown-item"
                    , Attr.href "#"
                    , onClick (ClickedDownload key)
                    ]
                    [ span
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.class "icon is-small"
                        ]
                        [ i
                            [ Attr.class "fas fa-download"
                            ]
                            []
                        ]
                    , text " Download" ]
                , a
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.attribute "role" "listitem"
                    , Attr.tabindex 0
                    , Attr.class "dropdown-item"
                    , Attr.href "#"
                    ]
                    [ span
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.class "icon is-small"
                        ]
                        [ i
                            [ Attr.class "fas fa-file-signature"
                            ]
                            []
                        ]
                    , text " Rename" ]
                , a
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.attribute "role" "listitem"
                    , Attr.tabindex 0
                    , Attr.class "dropdown-item"
                    , Attr.href "#"
                    , onClick (ClickedDelete key.keyEncrypted)
                    ]
                    [ span
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.class "icon is-small"
                        ]
                        [ i
                            [ Attr.class "fas fa-trash-alt"
                            ]
                            []
                        ]
                    , text " Delete" ]
                , a
                    [ Attr.attribute "data-v-081c0a81" ""
                    , Attr.attribute "role" "listitem"
                    , Attr.tabindex 0
                    , Attr.class "dropdown-item"
                    , Attr.href "#"
                    ]
                    [ span
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.class "icon is-small"
                        ]
                        [ i
                            [ Attr.class "fas fa-clipboard"
                            ]
                            []
                        ]
                    , text " Copy link" ]
                ]
            ]
        ]
    ]

viewFolderItem: Model -> KeyInfoDecrypted -> Html Msg
viewFolderItem model key =
    if String.contains model.currentDir key.keyDecrypted then
        let
            tempFolder = String.replace model.currentDir "" key.keyDecrypted
        in

        if model.currentDir /= key.keyDecrypted && (List.length (String.split "/" tempFolder)) == 2 then
            viewFolder model key
        else
            div [] []
    else
        div [] []

viewFolder: Model -> KeyInfoDecrypted -> Html Msg
viewFolder model key =
    let
        name = String.replace model.currentDir "" key.keyDecrypted
    in
    tr
    [ Attr.draggable "false"
    , Attr.class "file-row type-dir"
    ]
    [ td
        [ Attr.class "checkbox-cell"
        ]
        [ label
            [ Attr.class "b-checkbox checkbox"
            ]
            [ input
                [ Attr.type_ "checkbox"
                , Attr.attribute "true-value" "true"
                , Attr.value "false"
                ]
                []
            , span
                [ Attr.class "check"
                ]
                []
            , span
                [ Attr.class "control-label"
                ]
                []
            ]
        ]
    , td
        [ Attr.attribute "data-v-081c0a81" ""
        , Attr.attribute "data-label" "Name"
        , Attr.class ""
        ]
        [ span []
            [ a
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.class "is-block name"
                , Attr.href "#"
                , onClick (ClickedFolder key.keyDecrypted)
                ]
                [ text (String.left ((String.length name) - 1) name) ]
            ]
        ]
    , td
        [ Attr.attribute "data-v-081c0a81" ""
        , Attr.attribute "data-label" "Size"
        , Attr.class "has-text-right"
        ]
        [ span []
            [ text "Folder" ]
        ]
    , td
        [ Attr.attribute "data-v-081c0a81" ""
        , Attr.attribute "data-label" "Time"
        , Attr.class "has-text-right"
        ]
        [ span []
            [ text key.lastModified ]
        ]
    , td
        [ Attr.attribute "data-v-081c0a81" ""
        , Attr.class ""
        , Attr.id "single-actions"
        ]
        [ span []
            (viewDropdown model key)
        ]
    ]

viewBack: Model -> List (Html Msg)
viewBack model =
    if model.currentDir == "" then
        []
    else
        [ tr
            [ Attr.draggable "false"
            , Attr.class "file-row type-back"
            ]
            [ td
                [ Attr.class "checkbox-cell"
                ]
                [ label
                    [ Attr.class "b-checkbox checkbox is-disabled"
                    , Attr.disabled True
                    ]
                    [ input
                        [ Attr.type_ "checkbox"
                        , Attr.attribute "true-value" "true"
                        , Attr.value "false"
                        , Attr.disabled True
                        ]
                        []
                    , span
                        [ Attr.class "check"
                        ]
                        []
                    , span
                        [ Attr.class "control-label"
                        ]
                        []
                    ]
                ]
            , td
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.attribute "data-label" "Name"
                , Attr.class ""
                , onClick ClickedBack
                ]
                [ span []
                    [ a
                        [ Attr.attribute "data-v-081c0a81" ""
                        , Attr.class "is-block name"
                        , Attr.href "#"
                        ]
                        [ text ".." ]
                    ]
                ]
            , td
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.attribute "data-label" "Size"
                , Attr.class "has-text-right"
                ]
                [ span []
                    [ text "Folder" ]
                ]
            , td
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.attribute "data-label" "Time"
                , Attr.class "has-text-right"
                ]
                [ span []
                    []
                ]
            , td
                [ Attr.attribute "data-v-081c0a81" ""
                , Attr.class ""
                , Attr.id "single-actions"
                ]
                [ span []
                    []
                ]
            ]
        ]