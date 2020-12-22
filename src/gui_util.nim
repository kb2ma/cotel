## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import base64, logging, parsetoml, sequtils, strutils
import imgui
import conet_ctx

const PSK_KEYLEN_MAX* = 16

type
  PskKeyFormat* = enum
    FORMAT_HEX_DIGITS
    FORMAT_PLAINTEXT
    FORMAT_BASE64

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

proc igComboString*(label: string, currentIndex: var int,
                   strList: openArray[string]): bool =
  ## Combo box to display a list of strings.
  result = false
  if igBeginCombo(label, strList[currentIndex]):
    for i in 0 ..< len(strList):
      var isSelected = (i == currentIndex)
      if igSelectable(strList[i], isSelected.addr):
        currentIndex = i
      if isSelected:
        igSetItemDefaultFocus()
        result = true
    igEndCombo()

proc igInputTextCap*(label: string, text: var string, cap: int,
                     size: ImVec2 = ImVec2(x: 0, y: 0),
                     flags: ImGuiInputTextFlags = 0.ImGuiInputTextFlags,
                     callback: ImGuiInputTextCallback = nil): bool =
  ## Synchronizes the length property of the input Nim string with its component
  ## cstring, as it is edited by the ImGui library.
  var isEmpty = false
  
  if len(text) == 0:
    # Temporarily set Nim string length > 0 for adaptation to C library. If
    # length is 0, Nim passes a NULL char* as the cstring text buffer, which
    # causes a segmentation fault in ImGui.
    text.setLen(1)
    isEmpty = true
  if igInputTextEx(label, nil, text, cap.int32, size, flags, callback):
    text.setLen(len(text.cstring))
    return true
  elif isEmpty:
    text.setLen(0)
  return false

proc isEnterPressed*():bool =
  ## Returns true if the enter key has been pressed
  return igIsWindowFocused(ImGuiFocusedFlags.RootWindow) and
         igIsKeyReleased(igGetKeyIndex(ImGuiKey.Enter))
