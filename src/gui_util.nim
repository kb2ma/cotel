## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import parsecfg, std/strutils

type
  CotelConf* = object
    serverPort*: int

proc readConfFile*(confName: string): CotelConf =
  if confName == "":
    return CotelConf(serverPort: 5683)

  var dict = loadConfig(confName)
  result = CotelConf()
  let portStr = dict.getSectionValue("Server", "port")
  try:
    result.serverPort = parseInt(portStr)
  except ValueError:
    if portStr != "":
      echo("Error reading Server port; using default")
    result.serverPort = 5683
