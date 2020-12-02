## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import base64, logging, parsetoml, sequtils, strutils
import conet_ctx

const PSK_KEYLEN_MAX* = 16

type
  PskKeyFormat* = enum
    FORMAT_BASE64
    FORMAT_HEX_DIGITS
    FORMAT_PLAINTEXT

  CotelConf* = ref object
    ## Configuration data for Cotel app. See src/cotel.conf for details.
    serverAddr*: string
    nosecPort*: int
    secPort*: int
    pskFormat*: PskKeyFormat
    pskKey*: seq[char]
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

  # psk_key is a char/byte array encoded as specified by psk_format.
  let formatStr = getStr(tSec["psk_format"])
  let keyStr = getStr(tsec["psk_key"])
  let keyLen = keyStr.len()
  case formatStr
  of "base64":
    result.pskFormat = FORMAT_BASE64
    result.pskKey = toSeq(decode(keyStr))

  of "hex":
    result.pskFormat = FORMAT_HEX_DIGITS
    if keyLen mod 2 != 0:
      raise newException(ValueError,
                         format("psk_key length $# not a multiple of two", $keyLen))
    let seqLen = (keyLen / 2).int
    if seqLen > PSK_KEYLEN_MAX:
      raise newException(ValueError,
                         format("psk_key length $# longer than 16", $keyLen))
    result.pskKey = newSeq[char](seqLen)
    for i in 0 ..< seqLen:
      result.pskKey[i] = cast[char](fromHex[int](keyStr.substr(i*2, i*2+1)))

  of "plain":
    result.pskFormat = FORMAT_PLAINTEXT
    if keyLen > PSK_KEYLEN_MAX:
      raise newException(ValueError,
                         format("psk_key length $# longer than 16", $keyLen))
    result.pskKey = cast[seq[char]](keyStr)
  else:
    raise newException(ValueError,
                       format("psk_format $# not understood", formatStr))

  # client_id is a text string. Client requests use the same PSK key as the
  # local server.
  result.pskClientId = getStr(tSec["client_id"])

  # GUI section
  let tGui = toml["GUI"]
  result.windowSize = tGui["window_size"].getElems().mapIt(it.getInt())

  oplog.log(lvlInfo, "Conf file read OK")
