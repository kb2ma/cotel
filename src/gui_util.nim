## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import base64, logging, parsetoml
import conet_ctx

type
  SecurityMode* = enum
    SECURITY_MODE_NOSEC,
    SECURITY_MODE_PSK

  CotelConf* = ref object
    serverPort*: int
    securityMode*: SecurityMode
    pskKey*: seq[char]


proc readConfFile*(confName: string): CotelConf =
  ## confName must not be empty!
  ## Raises IOError if can't read file.
  ## Raises ValueError if can't read a section/key.

  # Build conf object with values from conf file, or defaults.
  result = CotelConf()

  let toml = parseFile(confName)

  # Server section
  result.serverPort = getInt(toml["Server"]["port"])

  # Security section
  let tSec = toml["Security"]

  let secMode = getStr(tsec["security_mode"])
  case secMode
  of "NoSec":
    result.securityMode = SECURITY_MODE_NOSEC
  of "PSK":
    result.securityMode = SECURITY_MODE_PSK
  else:
    raise newException(ValueError, "security_mode not understood: " & secMode)

  result.pskKey = cast[seq[char]](decode(getStr(tsec["psk_key"])))

  oplog.log(lvlInfo, "Conf file read OK")
