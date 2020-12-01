## View to setup and enable a local CoAP server. Includes endpoints and
## security.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import base64, json, sequtils, strutils
import conet, gui_util

type
  LocalServerStatus = enum
    ## Window and editing status
    STATUS_INIT
      ## before first use
    STATUS_PENDING_OPEN
      ## waiting for config data to display UI
    STATUS_OPEN

let headingColor = ImVec4(x: 154f/256f, y: 152f/256f, z: 80f/256f, w: 230f/256f)
  ## dull gold color

var
  isLocalServerOpen* = false
  status = STATUS_INIT
  statusText = ""
  config: ServerConfig
  # must encode as 'var' rather than 'let' to find address for cstring
  formatItems = ["Base64 encoded".cstring, "Hex digits".cstring, "Plain text".cstring]

  nosecEnable = false
  nosecPort = 5683'i32
  secEnable = false
  secPort = 5684'i32
  listenAddr = newStringOfCap(64)
  pskKey = newStringOfCap(64)
  pskFormatId = FORMAT_BASE64
    ## index into PskKeyFormat enum

proc igInputTextCap(label: string, text: var string, cap: uint): bool =
  ## Synchronizes the length of the input Nim string text with its cstring as
  ## it is edited.
  if igInputText(label, text, cap):
    # disallow length of zero; causes conflict in ImGui
    text.setLen(max(text.cstring.len(), 1))
    return true
  return false

proc helpMarker(desc: string) =
  ## Shows marker for help and displays tooltip for provided description.
  igTextDisabled("(?)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0f)
    igTextUnformatted(desc)
    igPopTextWrapPos()
    igEndTooltip()

proc setStatus(status: LocalServerStatus, text: string = "") =
  gui_local_server.status = status
  statusText = text

proc updateVars(srcConfig: ServerConfig) =
  ## Convenience function for common actions when config is updated
  config = srcConfig
  nosecEnable = config.nosecEnable
  nosecPort = config.nosecPort.int32
  secEnable = config.secEnable
  secPort = config.secPort.int32
  # Must have 64 bytes allocated
  listenAddr = newStringOfCap(64)
  listenAddr.add(config.listenAddr)
  pskKey = newStringOfCap(64)
  # seq[int] to string
  case pskFormatId
  of FORMAT_BASE64:
    pskKey.add(encode(srcConfig.pskKey))
  of FORMAT_HEX_DIGITS:
    for i in srcConfig.pskKey:
      pskKey.add(toHex(i, 2))
  of FORMAT_PLAINTEXT:
    for i in srcConfig.pskKey:
      pskKey.add(chr(i))

proc onConfigUpdate*(config: ServerConfig) =
  ## Assumes provided config reflects the actual state of conet endpoints. So,
  ## if the UI requested NoSec to enable, then config.nosecEnable will be true
  ## here if in fact the server endpoint now is listening.
  updateVars(config)
  setStatus(status, "OK")

proc setConfig*(config: ServerConfig) =
  ## Sets configuration data when opening the window.
  updateVars(config)
  setStatus(STATUS_OPEN)

proc init*(format: PskKeyFormat) =
  ## One-time initialization.
  pskFormatId = format

proc setPendingOpen*() =
  ## Window will be opened; waiting for config data in setConfig()
  setStatus(STATUS_PENDING_OPEN)

proc showWindow*() =
  ## isActivePtr is used by enclosing context
  if status == STATUS_PENDING_OPEN:
    # don't have config data yet
    return

  igSetNextWindowSize(ImVec2(x: 600, y: 300), FirstUseEver)
  igBegin("Local Server", isLocalServerOpen.addr)
  # used for table of endpoints
  var colPos = 0f
  let colWidth = 90f
  let shim = 10f

  # headers
  igTextColored(headingColor, "Local Endpoints")
  igText("Enable")
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("Protocol")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igText("Port")
  colPos += colWidth
  igSameLine(colPos + shim*3)
  igText("Listen Address")
  igSameLine()
  helpMarker("Use :: for IPv6 all interfaces, or 0.0.0.0 for IPv4")

  # NoSec
  colPos = 0f
  igCheckbox("##nosecEnable", nosecEnable.addr)
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("coap")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igSetNextItemWidth(100)
  if config.nosecEnable:
    igText($nosecPort)
  else:
    igInputInt("##nosecPort", nosecPort.addr)
  colPos += colWidth + shim*3
  igSameLine(colPos)
  igSetNextItemWidth(250)
  if config.nosecEnable or config.secEnable:
    igText(listenAddr)
  else:
    discard igInputTextCap("##listenAddr", listenAddr, 64)

  # Secure
  colPos = 0f
  igCheckbox("##secEnable", secEnable.addr)
  colPos += colWidth - shim
  igSameLine(colPos)
  igText("coaps")
  colPos += colWidth - shim*2
  igSameLine(colPos)
  igSetNextItemWidth(100)
  if config.secEnable:
    igText($secPort)
  else:
    igInputInt("##nosecPort", secPort.addr)
  colPos += colWidth + shim*3
  igSameLine(colPos)
  igText("same")

  # Security entries
  igItemSize(ImVec2(x:0,y:8))
  igTextColored(headingColor, "coaps Pre-shared Key")
  colPos = 100f

  igText("Key format")
  igSameLine(colPos)
  igSetNextItemWidth(150)
  if config.secEnable:
    igText(formatItems[pskFormatId.int])
  else:
    # combo requires int32 ptr
    var pskFormatIndex = pskFormatId.int32
    if igCombo("##keyFormat", pskFormatIndex.addr, formatItems[0].addr, 3):
      pskFormatId = cast[PskKeyFormat](pskFormatIndex)

  igText("Key")
  igSameLine()
  helpMarker("Decoded key may be up to 16 bytes long")
  igSameLine(colPos)
  if config.secEnable:
    igText(pskKey)
  else:
    discard igInputTextCap("##pskKey", pskKey, 64)

  igItemSize(ImVec2(x:0,y:8))
  if igButton("Save/Execute"):
    # Convert PSK key to a seq[int]. Must first convert to seq[char].
    var intSeq: seq[int]
    case pskFormatId
    of FORMAT_BASE64:
      let charSeq = @(decode(pskKey))
      intSeq = charSeq.map(proc (c:char): int = cast[int](c))
    of FORMAT_HEX_DIGITS:
      let seqLen = (pskKey.len() / 2).int
      intSeq = newSeq[int](seqLen)
      for i in 0 ..< seqLen:
        intSeq[i] = fromHex[int](pskKey.substr(i*2, i*2+1))
    of FORMAT_PLAINTEXT:
      let charSeq = @pskKey
      intSeq = charSeq.map(proc (c:char): int = cast[int](c))
    echo("pskKey seq " & $intSeq)

    let config = ServerConfig(listenAddr: listenAddr, nosecEnable: nosecEnable,
                              nosecPort: nosecPort, secEnable: secEnable,
                              secPort: secPort, pskKey: intSeq, pskClientId: "")
    ctxChan.send( CoMsg(subject: "config.server.PUT",
                        token: "local_server.update", payload: $(%* config)) )
    statusText = ""

  if statusText != "":
    igSameLine(120)
    igTextColored(ImVec4(x: 0f, y: 1f, z: 0f, w: 1f), statusText)
  igEnd()
