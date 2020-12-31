## View to setup and enable a local CoAP server. Includes endpoints and
## security.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import base64, json, sequtils, strutils, std/jsonutils
import conet, gui/util

type
  FormStatus = enum
    ## Window and editing status
    STATUS_INIT
      ## before first use
    STATUS_PENDING_DATA
      ## waiting for config data to display UI
    STATUS_READY

let formatItems = ["hex", "text", "base64"]

var
  isLocalhostOpen* = false
  status = STATUS_INIT
  statusText = ""
    ## result of pressing Save/Execute button
  config: ServerConfig
    ## most recent config received from Conet
  # must encode as 'var' rather than 'let' to find address for cstring

  nosecEnable = false
  nosecPort: int32
  secEnable = false
  secPort: int32
  listenAddr: string
  pskKey: string
  pskFormatId: PskKeyFormat

proc helpMarker(desc: string) =
  ## Shows marker for help and displays tooltip for provided description.
  igTextDisabled("(?)")
  if igIsItemHovered():
    igBeginTooltip()
    igPushTextWrapPos(igGetFontSize() * 35.0f)
    igTextUnformatted(desc)
    igPopTextWrapPos()
    igEndTooltip()

proc setStatus(status: FormStatus, text: string = "") =
  localhost.status = status
  statusText = text

proc updateVars(srcConfig: ServerConfig) =
  ## Performs common actions when config is updated
  config = srcConfig
  nosecEnable = config.nosecEnable
  nosecPort = config.nosecPort.int32
  secEnable = config.secEnable
  secPort = config.secPort.int32
  listenAddr = newStringOfCap(64)
  listenAddr.add(config.listenAddr)
  pskKey = newStringOfCap(64)
  # seq[char] to string
  case pskFormatId
  of FORMAT_BASE64:
    pskKey.add(encode(srcConfig.pskKey))
  of FORMAT_HEX_DIGITS:
    for i in srcConfig.pskKey:
      pskKey.add(toHex(cast[int](i), 2))
  of FORMAT_PLAINTEXT:
    for i in srcConfig.pskKey:
      pskKey.add(i)

proc onConfigUpdate*(config: ServerConfig) =
  ## Assumes provided config reflects the actual state of conet server
  ## endpoints. So, if the UI requested to enable NoSec, then config.nosecEnable
  ## will be true here if the server endpoint actually is listening now.
  updateVars(config)
  setStatus(status, "OK")

proc onConfigError*(config: ServerConfig) =
  ## Assumes provided config reflects the actual state of conet server
  ## endpoints. So, if the update failed to enable PSK, then config.secEnable
  ## will be false here. Point user to the log for details.
  updateVars(config)
  setStatus(status, "Error updating; see log")

proc setConfig*(config: ServerConfig) =
  ## Sets configuration data when opening the window.
  updateVars(config)
  setStatus(STATUS_READY)

proc init*(format: PskKeyFormat) =
  ## One-time initialization
  pskFormatId = format

proc setPendingOpen*() =
  ## Window will be opened; waiting for config data in setConfig()
  setStatus(STATUS_PENDING_DATA)

proc showWindow*() =
  if status == STATUS_PENDING_DATA:
    # don't have config data yet
    return

  igSetNextWindowSize(ImVec2(x: 600, y: 300), FirstUseEver)
  igBegin("Local Setup", isLocalhostOpen.addr)
  # used for table of endpoints
  var colPos = 0f
  let colWidth = 90f
  let shim = 10f

  # headers
  igTextColored(headingColor, "Server Endpoints")
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

  # Security section
  igItemSize(ImVec2(x:0,y:8))
  igTextColored(headingColor, "coaps Pre-shared Key")
  colPos = 100f

  igAlignTextToFramePadding()
  igText("Key")
  igSameLine(60)
  igSetNextItemWidth(300)
  if config.secEnable:
    igText(pskKey)
  else:
    discard igInputTextCap("##pskKey", pskKey, 64)
    igSameLine()
    helpMarker("Key in format at right, and may be up to 16 bytes long when decoded")

  igSameLine()
  igSetNextItemWidth(80)
  if config.secEnable:
    igText(formatItems[pskFormatId.int])
  else:
    var pskFormatIndex = pskFormatId.int
    if igComboString("##keyFormat", pskFormatIndex, formatItems):
      pskFormatId = cast[PskKeyFormat](pskFormatIndex)

  igItemSize(ImVec2(x:0,y:12))

  if igButton("Save/Execute") or isEnterPressed():
    # Convert PSK key to seq[char].
    statusText = ""
    var charSeq: seq[char]
    case pskFormatId
    of FORMAT_HEX_DIGITS:
      if pskKey.len() mod 2 != 0:
        statusText = "Key length $# not a multiple of two"
      else:
        let seqLen = (pskKey.len() / 2).int
        if seqLen > PSK_KEYLEN_MAX:
          statusText = format("Key length $# longer than 16", $seqLen)
        charSeq = newSeq[char](seqLen)
        for i in 0 ..< seqLen:
          charSeq[i] = cast[char](fromHex[int](pskKey.substr(i*2, i*2+1)))
    of FORMAT_PLAINTEXT:
      if pskKey.len() > PSK_KEYLEN_MAX:
        statusText = format("Key length $# longer than 16", $pskKey.len())
      else:
        charSeq = cast[seq[char]](pskKey)
    of FORMAT_BASE64:
      charSeq = toSeq(decode(pskKey))

    if statusText == "":
      let config = ServerConfig(listenAddr: listenAddr, nosecEnable: nosecEnable,
                                nosecPort: nosecPort, secEnable: secEnable,
                                secPort: secPort, pskKey: charSeq, pskClientId: "")
      ctxChan.send( CoMsg(subject: "config.server.PUT",
                          token: "local_server.update", payload: $toJson(config)) )

  if statusText != "":
    igSameLine(120)
    var textColor: ImVec4
    if statusText == "OK":
      textColor = ImVec4(x: 0f, y: 1f, z: 0f, w: 1f)
    else:
      # red for error
      textColor = ImVec4(x: 1f, y: 0f, z: 0f, w: 1f)
    igTextColored(textColor, statusText)
  igEnd()
