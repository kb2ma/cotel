## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import parsetoml

const
  SERVER_PORT_DEFAULT = 5683

type
  CotelConf* = object
    serverPort*: int

proc readConfFile*(confName: string): CotelConf =
  ## Raises IOError if can't read file

  # Build default config, and replace with values from conf file
  result = CotelConf(serverPort: SERVER_PORT_DEFAULT)
  if confName == "":
    return result

  let toml = parseFile(confName)

  let tServer = toml.getOrDefault("Server")
  if tServer != nil:
    result.serverPort = getInt(tServer.getOrDefault("port"), SERVER_PORT_DEFAULT)
