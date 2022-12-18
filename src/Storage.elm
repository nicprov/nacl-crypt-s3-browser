port module Storage exposing
    ( Storage
    , storageToJson
    , storageFromJson
    , storageDecoder
    , init
    , onChange
    , signIn
    , signOut
    )

import Json.Decode as Decode exposing (Decoder, decodeValue, field, int, map, map2, nullable, string)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Encode exposing (Value, encode, list, string)
import S3 as S3
import S3.Types
import List exposing (concatMap)


-- Model

type alias Storage =
    { account: Maybe S3.Types.Account
    , encryptionKey: String
    , salt: String
    }

-- Ports

port save: Decode.Value -> Cmd msg
port load: (Decode.Value -> msg) -> Sub msg


-- Convert to JSON

storageToJson: Storage -> Decode.Value
storageToJson storage =
    case storage.account of
        Just account ->
            Encode.object
                [ ("account", S3.encodeAccount account)
                , ("encryptionKey", Encode.string storage.encryptionKey)
                , ("salt", Encode.string storage.salt)
                ]
        Nothing ->
            Encode.object []

-- Convert from JSON

storageFromJson: Decode.Value -> Storage
storageFromJson json =
    json
        |> Decode.decodeValue storageDecoder
        |> Result.withDefault init


-- Decoders

storageDecoder: Decoder Storage
storageDecoder =
    Decode.succeed Storage
        |> required "account" (nullable S3.accountDecoder)
        |> required "encryptionKey" Decode.string
        |> required "salt" Decode.string

-- Auth

signIn: S3.Types.Account -> String -> String -> Storage -> Cmd msg
signIn account key salt storage =
    { storage | account = Just account, encryptionKey = key, salt = salt }
        |> storageToJson
        |> save

signOut: Storage -> Cmd msg
signOut storage =
    { storage | account = Nothing, encryptionKey = "", salt = ""}
        |> storageToJson
        |> save


-- Init

init: Storage
init =
    { account = Nothing
    , encryptionKey = ""
    , salt = ""
    }

-- Listen for storage updates

onChange : (Storage -> msg) -> Sub msg
onChange fromStorage =
    load (\json -> storageFromJson json |> fromStorage)