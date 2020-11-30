## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import base64, logging, parsetoml, sequtils
import conet_ctx

type
  CotelConf* = ref object
    ## Configuration data for Cotel app. See src/cotel.conf for details.
    serverAddr*: string
    nosecPort*: int
    secPort*: int
    pskKey*: seq[int]
      ## uses int rather than char for JSON compatibility
    pskClientId*: string
    windowSize*: seq[int]

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
  result.nosecPort = getInt(tServ["nosecPort"])
  result.secPort = getInt(tServ["secPort"])

  # Security section
  let tSec = toml["Security"]

  # psk_key is a base64 encoded char/byte array
  result.pskKey = cast[seq[int]](decode(getStr(tsec["psk_key"])))

  # client_id is a text string. Client requests use the same PSK key as the
  # local server.
  result.pskClientId = getStr(tSec["client_id"])

  # GUI section
  let tGui = toml["GUI"]
  result.windowSize = tGui["window_size"].getElems().mapIt(it.getInt())

  oplog.log(lvlInfo, "Conf file read OK")
