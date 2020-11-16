## Provides a module for common conet context data for an application that uses
## its CoAP networking.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0
import logging

type
  CoMsg* = object
    ## A REST-like message for use in a channel with the enclosing context
    req*: string
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
