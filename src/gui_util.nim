## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import base64, logging, parsetoml
import conet_ctx

type
  CotelConf* = ref object
    ## Configuration data for Cotel app
    serverAddr*: string
    serverPort*: int
    securityMode*: SecurityMode
    pskKey*: seq[char]
    pskClientId*: string

proc readConfFile*(confName: string): CotelConf =
  ## Builds configuration object from entries in configuration file.
  ## *confName* must not be empty!
  ## Raises IOError if can't read file.
  ## Raises ValueError if can't read a section/key.

  # Build conf object with values from conf file, or defaults.
  result = CotelConf()

  let toml = parseFile(confName)

  # Server section
  let tServ = toml["Server"]
  
  result.serverAddr = getStr(tServ["listen_addr"])
  result.serverPort = getInt(tServ["port"])

  # Security section
  let tSec = toml["Security"]

  let secMode = getStr(tsec["mode"])
  case secMode
  of "NoSec":
    result.securityMode = SECURITY_MODE_NOSEC
  of "PSK":
    result.securityMode = SECURITY_MODE_PSK
  else:
    raise newException(ValueError, "security_mode not understood: " & secMode)

  # psk_key is a base64 encoded char/byte array
  result.pskKey = cast[seq[char]](decode(getStr(tsec["psk_key"])))

  # client_id is a text string. Client requests use the same PSK key as the
  # local server.
  result.pskClientId = getStr(tSec["client_id"])

  oplog.log(lvlInfo, "Conf file read OK")
