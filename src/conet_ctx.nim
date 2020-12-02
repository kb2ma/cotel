## Provides common data and utilities for an application context to use Conet
## networking.
##
## Includes ability to convert a char to/from JSON, as required by the
## ServerConfig type for use in a CoMsg.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0
import json, logging, std/jsonutils

type
  CoMsg* = object
    ## A REST-like message for use in a channel with the enclosing context
    subject*: string
    token*: string
        ## A response to this message must include this token. Provides a
        ## flexible way to connect messages into a conversation.
    payload*: string

  SecurityMode* = enum
    SECURITY_MODE_NOSEC,
    SECURITY_MODE_PSK

var
  netChan*: Channel[CoMsg]
    ## Communication channel from conet to enclosing context
  ctxChan*: Channel[CoMsg]
    ## Communication channel from enclosing context to conet
  oplog* {.threadvar.}: FileLogger
    ## Logging, which may be initialized on a per-thread basis


proc toJsonHook*(c: char): JsonNode =
  # Marshalls a char to a JSON object
  return toJson(cast[int](c))

proc fromJsonHook*(a: var char, b: JsonNode) =
  # Unmarshalls a JSON object to a char
  a = cast[char](getInt(b))
