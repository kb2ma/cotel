## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import logging, parsetoml, sequtils, strutils
import imgui
import conet_ctx

const
  PSK_KEYLEN_MAX* = 16
  headingColor* = ImVec4(x: 154f/256f, y: 152f/256f, z: 80f/256f, w: 230f/256f)
    ## dull gold color

type
  CotelConf* = ref object
    ## Configuration data for Cotel app. See src/cotel.conf for details.
    serverAddr*: string
    nosecPort*: int
    secPort*: int
    pskKey*: seq[char]
    pskClientId*: string
    tokenLen*: int
    windowSize*: seq[int]

  CotelData* = ref object
    ## Runtime data for Cotel app.
    isChanged*: bool
      ## Indicates this object has been updated, and needs to be persisted.
    windowSize*: seq[int]
      ## Size of top level window, in pixels

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
  let keyStr = getStr(tsec["psk_key"])
  let keyLen = keyStr.len()

  if keyLen > PSK_KEYLEN_MAX:
    raise newException(ValueError,
                       format("psk_key length $# longer than 16", $keyLen))
  result.pskKey = cast[seq[char]](keyStr)

  # client_id is a text string. Client requests use the same PSK key as the
  # local server.
  result.pskClientId = getStr(tSec["client_id"])

  # Client section
  let tClient = toml["Client"]
  result.tokenLen = getInt(tClient["token_length"])
  oplog.log(lvlInfo, "Conf file read OK")

proc readDataFile*(pathName: string): CotelData =
  ## Builds runtime data object from entries in file, or from defaults
  ## *pathName* must not be empty!
  result = CotelData()
  result.isChanged = false
  try:
    let toml = parseFile(pathName)
    # GUI section
    let tGui = toml["GUI"]
    result.windowSize = tGui["window_size"].getElems().mapIt(it.getInt())
  except:
    oplog.log(lvlInfo, format("Can't read data file $#; using defaults", pathName))
    result.windowSize = @[ 800, 600 ]

proc saveDataFile*(pathName: string, data: CotelData) =
  ## Persists data to the provided file. Logs any exception without re-raising.
  let dataTable = newTTable()
  dataTable.add("GUI", ?[("window_size", ?data.windowSize)])
  try:
    writeFile(pathName, toTomlString(dataTable))
    data.isChanged = false
  except:
    oplog.log(lvlError, format("Can't write data file $#\n$#", pathName,
                               getCurrentExceptionMsg()))

proc igComboString*(label: string, currentIndex: var int,
                   strList: openArray[string]): bool =
  ## Combo box to display a list of strings.
  result = false
  if igBeginCombo(label, strList[currentIndex]):
    for i in 0 ..< len(strList):
      var isSelected = (i == currentIndex)
      if igSelectable(strList[i], isSelected.addr):
        currentIndex = i
        result = true
      if isSelected:
        igSetItemDefaultFocus()
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

proc isEnterPressed*(): bool =
  ## Returns true if the Enter key has been pressed
  return igIsWindowFocused(ImGuiFocusedFlags.RootWindow) and
         igIsKeyReleased(igGetKeyIndex(ImGuiKey.Enter))
