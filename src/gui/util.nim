## Utilities for Cotel UI
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import logging, parsetoml, sequtils, strutils
import imgui
import conet_ctx

const
  PSK_KEYLEN_MAX* = 64
  headingColor* = ImVec4(x: 154f/256f, y: 152f/256f, z: 80f/256f, w: 230f/256f)
    ## dull gold color

type
  CotelConf* = ref object
    ## Configuration data for Cotel app. See resources/cotel.conf for details.
    serverAddr*: string
    nosecPort*: int
    secPort*: int
    pskKey*: seq[char]
    pskClientId*: string
    tokenLen*: int
    # Saved separately in cotel.dat when user changes window size.
    windowSize*: seq[int]

  CotelData* = ref object
    ## Runtime data for Cotel app.
    isChanged*: bool
      ## Indicates this object has been updated, and needs to be persisted.
    windowSize*: seq[int]
      ## Size of top level window, in pixels

var childBgColor*: ptr ImVec4
  ## Cache color for use by dependents; initialized below in init()

proc init*() =
  ## Initialization triggered by app after ImGui initialized
  childBgColor = igGetStyleColorVec4(ImGuiCol.ChildBg)

proc createDefaultConfFile*(): CotelConf =
  ## Creates a default application configuration file.
  result = CotelConf()
  # result.pskKey nil
  result.pskClientId = "cotel"
  result.tokenLen = 2
  result.serverAddr = "::"
  result.nosecPort = 5683
  result.secPort = 5684

proc readConfFile*(confName: string): CotelConf =
  ## Builds configuration object from entries in configuration file.
  ## *confName* must not be empty!
  ## Raises IOError if can't read file.
  ## Raises ValueError if can't read a section/key.

  # Build conf object with values from conf file, or defaults.
  result = CotelConf()

  let toml = parseFile(confName)

  # Security section
  let tSec = toml["Security"]

  # psk_key is a char/byte array encoded as specified by psk_format.
  let keyStr = getStr(tsec["psk_key"])
  let keyLen = keyStr.len()

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

  # client_id is a text string. Client requests use the same PSK key as the
  # local server.
  result.pskClientId = getStr(tSec["client_id"])

  # Client section
  let tClient = toml["Client"]
  result.tokenLen = getInt(tClient["token_length"])
  oplog.log(lvlInfo, "Conf file read OK")

  # Server section
  let tServ = toml["Server"]
  
  result.serverAddr = getStr(tServ["listen_addr"])
  result.nosecPort = getInt(tServ["nosecPort"])
  result.secPort = getInt(tServ["secPort"])

proc saveConfFile*(pathName: string, conf: CotelConf): bool =
  ## Persists configuration to the provided file. Logs any exception without
  ## re-raising, but return value indicates success/failure.
  let confTable = newTTable()
  var pskKey: string
  for c in conf.pskKey:
    pskKey.add(toHex(cast[int](c), 2))
  
  confTable.add("Security", ?[("psk_key", ?pskKey), ("client_id", ?conf.pskClientId)])
  confTable.add("Client", ?[("token_length", ?conf.tokenLen)])
  confTable.add("Server", ?[("listen_addr", ?conf.serverAddr), ("nosecPort", ?conf.nosecPort), ("secPort", ?conf.secPort)])
  try:
    writeFile(pathName, toTomlString(confTable))
  except:
    oplog.log(lvlError, format("Can't write conf file $#\n$#", pathName,
                               getCurrentExceptionMsg()))
    return false
  return true

proc readDataFile*(pathName: string): CotelData =
  ## Builds runtime data object from entries in file, or from defaults.
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
  ## 'text' must have a buffer at least one byte longer than 'cap' to
  ## accommodate the trailing 0x0. This requirement is met when allocating a
  ## string with newString() or newStringOfCap().
  var isEmpty = false
  
  if len(text) == 0:
    # Temporarily set Nim string length > 0 for adaptation to C library. If
    # length is 0, Nim passes a NULL char* as the cstring text buffer, which
    # causes a segmentation fault in ImGui.
    text.setLen(1)
    isEmpty = true
  if igInputTextEx(label, nil, text, (cap+1).int32, size, flags, callback):
    text.setLen(len(text.cstring))
    return true
  elif isEmpty:
    text.setLen(0)
  return false

proc textCapForMaxlen*(length: int): int =
  ## Provides the length for a buffer large enough for igInputTextCap(), given
  ## a length expressed as a count of characters.
  ##
  ## At time of writing, this function is somewhat defensive to make it easy to
  ## locate/alter how this calculation is performed, particularly for Unicode
  ## code points > U+0007F.
  assert(length > 0)
  # Triple the requested length to allow for %-encoded bytes (%9B), as well as
  # hex-encoded bytes separated by a space (9B 33 C2 ...). Tripling also
  # accommodates direct display of code points U+0080F to U+00FF, like accented
  # letters, which are encoded as two bytes in UTF-8.
  return length * 3

proc isFullyDisplayable*(str: string): bool =
  ## Returns true if the provided string contains only displayable ASCII
  ## text characters.
  result = true
  for c in str:
    if (c < ' ') or (c > '~'):
      result = false
      break

proc isEnterPressed*(): bool =
  ## Returns true if the Enter key has been pressed
  return igIsWindowFocused(ImGuiFocusedFlags.RootWindow) and
         igIsKeyReleased(igGetKeyIndex(ImGuiKey.Enter))

proc helpMarker*(desc: string) =
  ## Shows marker for help and displays tooltip for provided description.
  igTextDisabled("(?)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0f)
    igTextUnformatted(desc)
    igPopTextWrapPos()
    igEndTooltip()
