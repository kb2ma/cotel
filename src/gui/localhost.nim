## View to setup Cotel, including the local CoAP server. Local server endpoints
## also maybe stopped/started.
##
## Since server/networking runs in a separate thread, retrieval and update of
## local server data is accomplished asynchronously. The window is opened in two
## steps. First it is notified via setPendingOpen() that it is waiting for
## server data (status STATUS_PENDING_DATA). The window does not display yet.
## Then the window receives the server configuration via setConfig()
## (status READY) and displays the window.
##
## When updating local server data, the data is sent to conet via a
## 'config.server.PUT' request. The response is received via onConfigUpdate()
## or onConfigError().
##
## Copyright 2020-2021 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import json, strutils, std/jsonutils, unicode
import conet, gui/util

type
  FormStatus = enum
    ## Window and editing status
    STATUS_INIT
      ## before first use
    STATUS_PENDING_DATA
      ## waiting for config data to display UI
    STATUS_READY

  KeyFormats = enum
    FORMAT_TEXT,
    FORMAT_HEX

const
  keyFormatItems = ["Text", "Hex"]
  # 16 pairs of hex digits with 15 spaces in between
  keyTextCapacity = (PSK_KEYLEN_MAX * 2) + PSK_KEYLEN_MAX

var
  isLocalhostOpen* = false
  status = STATUS_INIT
  statusText = ""
    ## result of pressing Save/Execute button
  netConfig: ConetConfig
    ## most recent config received from Conet
  appConfig: CotelConf
  appConfFile: string
  # PSK params
  pskKey: string
  keyFormatIndex = FORMAT_HEX.int32
  keyText = newStringOfCap(keyTextCapacity)
  isTextOnlyKey = false
  # server params
  nosecEnable = false
  nosecPort: int32
  secEnable = false
  secPort: int32
  listenAddr: string

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

proc buildKeyText(source: string, format: KeyFormats): string =
  ## Build and return UTF-8 text suitable for PSK key display, based on provided
  ## raw key and output text format.
  # Must initialize to max capacity due to ImGui InputText requirements.
  result = newStringOfCap(keyTextCapacity)
  case format
  of FORMAT_TEXT:
    # Convert any non-printable ASCII chars to a U00B7 dot.
    for r in runes(source):
      if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
        result.add("\u{B7}")
      else:
        result.add(toUTF8(r))
  of FORMAT_HEX:
    # Convert all chars to two-digit hex text, separated by a space.
    var isFirst = true
    for c in source:
      if isFirst:
        isFirst = false
      else:
        result.add(' ')
      result.add(toHex(cast[int](c), 2))

proc validateHexKey(hexText: string): bool =
  # Strip whitespace including newlines from the provided text, and save as
  # variable 'pskKey'.
  var stripped = ""
  try:
    for text in strutils.splitWhitespace(hexText):
      if len(text) mod 2 != 0:
        statusText = "Expecting pairs of hex digits in key"
        return false
      for i in 0 ..< (len(text) / 2).int:
        #let charInt = fromHex[int](text.substr(i*2, i*2+1))
        #echo(format("char $#", fmt"{charInt:X}"))
        #stripped.add(cast[char](charInt))
        stripped.add(cast[char](fromHex[int](text.substr(i*2, i*2+1))))
    pskKey = stripped
  except ValueError:
    statusText = "Expecting hex digits in key"
    return false
  return true

proc validateTextKey(hexText: string) =
  # Nothing to do; just save as variable 'pskKey'.
  pskKey = hexText

proc updateVars(srcNetConfig: ConetConfig) =
  ## Performs common actions when config is updated
  netConfig = srcNetConfig
  # seq[char] to string
  pskKey = ""
  for c in srcNetConfig.pskKey:
    pskKey.add(c)
  isTextOnlyKey = true
  for r in runes(pskKey):
    if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
      isTextOnlyKey = false
      break
  keyText = buildKeyText(pskKey, keyFormatIndex.KeyFormats)
  # server params
  nosecEnable = netConfig.nosecEnable
  nosecPort = netConfig.nosecPort.int32
  secEnable = netConfig.secEnable
  secPort = netConfig.secPort.int32
  listenAddr = newStringOfCap(64)
  listenAddr.add(netConfig.listenAddr)

proc onConfigUpdate*(netConfig: ConetConfig) =
  ## Assumes provided config reflects the actual state of conet server
  ## endpoints. So, if the UI requested to enable NoSec, then config.nosecEnable
  ## will be true here if the server endpoint actually is listening now.
  updateVars(netConfig)
  setStatus(status, "OK")

proc onConfigError*(netConfig: ConetConfig) =
  ## Assumes provided config reflects the actual state of conet server
  ## endpoints. So, if the update failed to enable PSK, then config.secEnable
  ## will be false here. Point user to the log for details.
  updateVars(netConfig)
  setStatus(status, "Error updating; see log")

proc setConfig*(netConfig: ConetConfig) =
  ## Sets configuration data when opening the window.
  updateVars(netConfig)
  setStatus(STATUS_READY)

proc setPendingOpen*(config: CotelConf, confFile: string) =
  ## Window will be opened; waiting for net config data in setConfig()
  appConfig = config
  appConfFile = confFile
  setStatus(STATUS_PENDING_DATA)

proc showWindow*(fixedFont: ptr ImFont) =
  if status == STATUS_PENDING_DATA:
    # don't have config data yet
    return

  igSetNextWindowSize(ImVec2(x: 600, y: 300), FirstUseEver)
  igBegin("Local Setup", isLocalhostOpen.addr)

  # Security section
  igTextColored(headingColor, "coaps Pre-shared Key")
  var keyFlags = ImGuiInputTextFlags.None
  if not netConfig.secEnable:
    igSameLine(260)
    if igRadioButton(keyFormatItems[FORMAT_TEXT.int], keyFormatIndex.addr, 0):
      if validateHexKey(keyText):
        isTextOnlyKey = true
        for r in runes(pskKey):
          if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
            isTextOnlyKey = false
            break
        keyText = buildKeyText(pskKey, FORMAT_TEXT)
      else:
        keyFormatIndex = FORMAT_HEX.int32
    igSameLine()
    if igRadioButton(keyFormatItems[FORMAT_HEX.int], keyFormatIndex.addr, 1):
      # Only read text if it was editable; otherwise it includes non-editable
      # chars. In either case hex key is built from saved 'pskKey' chars.
      if isTextOnlyKey:
        validateTextKey(keyText)
      keyText = buildKeyText(pskKey, FORMAT_HEX)
    if not isTextOnlyKey and keyFormatIndex == FORMAT_TEXT.int32:
      keyFlags = ImGuiInputTextFlags.ReadOnly
      igSameLine()
      igTextColored(headingColor, "Read only")

  igAlignTextToFramePadding()
  igText("Key")
  igSameLine(60)
  igSetNextItemWidth(400)
  igPushFont(fixedFont)
  if netConfig.secEnable:
    igText(keyText)
  else:
    discard igInputTextCap("##pskKey", keyText,
        if keyFormatIndex == FORMAT_TEXT.int32: PSK_KEYLEN_MAX + 1 else: keyTextCapacity,
                           flags = keyFlags)
  igPopFont()

  igItemSize(ImVec2(x:0,y:8))

  # Server endpoints
  if igCollapsingHeader("Experimental"):
    var colPos = 0f
    let colWidth = 90f
    let shim = 10f

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
    if netConfig.nosecEnable:
      igText($nosecPort)
    else:
      igInputInt("##nosecPort", nosecPort.addr)
    colPos += colWidth + shim*3
    igSameLine(colPos)
    igSetNextItemWidth(250)
    if netConfig.nosecEnable or netConfig.secEnable:
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
    if netConfig.secEnable:
      igText($secPort)
    else:
      igInputInt("##nosecPort", secPort.addr)
    colPos += colWidth + shim*3
    igSameLine(colPos)
    igText("same")

  igItemSize(ImVec2(x:0,y:12))

  if igButton("Save/Execute") or isEnterPressed():
    statusText = ""
    # Convert PSK key to seq[char].
    var isValidKey = true
    var charSeq: seq[char]
    case keyFormatIndex.KeyFormats
    of FORMAT_TEXT:
      validateTextKey(keyText)
      charSeq = cast[seq[char]](pskKey)
    of FORMAT_HEX:
      isValidKey = validateHexKey(keyText)
      if isValidKey:
        charSeq = cast[seq[char]](pskKey)
    # statusText is updated in the validate... functions, but we just test
    # 'isValidKey' here for simplicity. 'statusText' *is* used to display any
    # error below.
    if isValidKey:
      # Send new net config to conet.
      let netConfig = ConetConfig(listenAddr: listenAddr, nosecEnable: nosecEnable,
                                  nosecPort: nosecPort, secEnable: secEnable,
                                  secPort: secPort, pskKey: charSeq,
                                  pskClientId: appConfig.pskClientId)
      ctxChan.send( CoMsg(subject: "config.server.PUT",
                          token: "local_server.update", payload: $toJson(netConfig)) )
      # Save app config to disk.
      appConfig.serverAddr = listenAddr
      appConfig.nosecPort = nosecPort
      appConfig.secPort = secPort
      appConfig.pskKey = charSeq
      #appConfig.pskClientId = pskClientId
      #appConfig.tokenLen = tokenLen
      saveConfFile(appConfFile, appConfig)

  if len(statusText) > 0:
    igSameLine(120)
    var textColor: ImVec4
    if statusText == "OK":
      textColor = ImVec4(x: 0f, y: 1f, z: 0f, w: 1f)
    else:
      # red for error
      textColor = ImVec4(x: 1f, y: 0f, z: 0f, w: 1f)
    igTextColored(textColor, statusText)
  igEnd()
