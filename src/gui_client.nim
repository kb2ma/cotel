## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import algorithm, json, strutils, std/jsonutils, tables, unicode
import conet, gui_util

const
  reqHostCapacity = 64
  reqPathCapacity = 255
    ## No need to validate user entry for this path length
  optValueCapacity = 1034
    ## Length of the string used to edit option value; the longest possible
    ## option value.
  payloadCapacity = 64

  protoItems = ["coap", "coaps"]
  methodItems = ["GET", "POST", "PUT", "DELETE"]
  headingColor = ImVec4(x: 154f/256f, y: 152f/256f, z: 80f/256f, w: 230f/256f)
    ## dull gold color
  optListHeight = 80f

# Construct sorted list of content format items from the table of those items,
# which is generated in the conet module.
var cfList = newSeqOfCap[NamedId](len(contentFmtTable))
for item in contentFmtTable.values:
  cfList.add(item)

# Sort text/plain (id 0) first for convenience when defining a new option
cfList.sort(proc (x, y: NamedId): int = 
  if x.id == 0: -1
  elif y.id == 0: 1
  elif x.name < y.name: -1
  elif x.name == y.name: 0
  else: 1)

# Construct sorted list of option type items from the table of those items,
# which is generated in the conet module.
var optionTypes = newSeqOfCap[OptionType](len(optionTypesTable))
for item in optionTypesTable.values:
  optionTypes.add(item)
optionTypes.sort(proc (x, y: OptionType): int = cmp(x.name, y.name))

type
  MessageOptionView = ref object of MessageOptionContext
    ## Provides gui_client specific information for a message option. We do not
    ## define to/fromJsonHook functions because we don't need to share these
    ## values with the conet module.
    typeLabel: string
    valueLabel: string

var
  isRequestOpen* = false
    ## Enclosing context sets this value
  isNewOption = false
    ## True if editing a new option

  # widget contents
  reqProtoIndex = 0
  reqPort = 5683'i32
  reqHost = newStringOfCap(reqHostCapacity)
  reqPath = newStringOfCap(reqPathCapacity)
  reqMethodIndex = 0
  reqConfirm = false
  payload = newStringOfCap(payloadCapacity)
  respCode = ""
  respText = ""
  errText = ""

  # request options entry
  reqOptions = newSeq[MessageOption]()
  optionIndex = -1
    ## active index into reqOptions listbox
  optNameIndex = 0
    ## active index into optionTypes dropdown for a new option
  cfNameIndex = 0
    ## active index into cfList dropdown for a new Content-Format value
  optValue = newStringOfCap(optValueCapacity)
    ## user text representation of value for a new option
  optErrText = ""

  # response options
  respOptions = newSeq[MessageOption]()
  respPayFormatIndex = 0'i32


proc onNetMsgRequest*(msg: CoMsg) =
  if msg.subject == "response.payload":
    let msgJson = parseJson(msg.payload)
    respCode = msgJson["code"].getStr()

    #echo("resp options " & $msgJson["options"])
    for optJson in msgJson["options"]:
      respOptions.add(jsonTo(optJson, MessageOption))

    if msgJson.hasKey("payload"):
      # Convert any non-printable ASCII chars to a U00B7 dot. Also add line
      # break at 50 chars.
      var runeCount = 0
      for r in runes(msgJson["payload"].getStr()):
        if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
          respText.add("\u{B7}")
        else:
          respText.add(toUTF8(r))
        runeCount += 1
        if runeCount == 50:
          respText.add("\n")
          runeCount = 0
    else:
      respText = ""
  elif msg.subject == "send_msg.error":
    errText = "Error sending, see log"

proc igComboNamedObj[T](label: string, currentIndex: var int,
                    idList: openArray[T]): bool =
  ## Combo box to display a list of types T, which must have a `name` attribute.
  result = false
  if igBeginCombo(label, idList[currentIndex].name):
    for i in 0 ..< len(idList):
      let isSelected = (i == currentIndex)
      if igSelectable(idList[i].name, isSelected):
        currentIndex = i
      if isSelected:
        igSetItemDefaultFocus()
        result = true
    igEndCombo()

proc resetContents() =
  ## Resets many vars to blank/empty state.
  reqPath = newString(reqPathCapacity)
  reqOptions = newSeq[MessageOption]()
  optionIndex = -1
  optNameIndex = 0
  cfNameIndex = 0
  optValue = newStringofCap(optValueCapacity)
  payload = newStringOfCap(payloadCapacity)
  optErrText = ""
  respCode = ""
  respOptions = newSeq[MessageOption]()
  respText = ""

proc buildNewOption(optType: OptionType): MessageOption =
  ## Reads the user entered option type and value for a new option.
  ## Returns the new option, or nil on the first failure. If nil, also sets
  ## 'optErrText'.
  result = MessageOption(optNum: optType.id)
  if optType.id == COAP_OPTION_CONTENT_FORMAT:
    # value from drop down, not text entry
    result.valueInt = cfList[cfNameIndex].id.uint
  else:
    if len(optValue) == 0:
      optErrText = "Empty value"
      return nil
    case optType.dataType
    of TYPE_UINT:
      try:
        result.valueInt = parseUint(optValue)
      except ValueError:
        optErrText = "Expecting non-negative integer value"
        return nil
      let maxval = 1.uint shl (optType.maxlen * 8) - 1
      if result.valueInt > maxval:
        optErrText = "Value exceeds option maximum " & $maxval
        return nil
    of TYPE_OPAQUE:
      if len(optValue) mod 2 != 0:
        optErrText = "Expecting hex digits, but length not a multiple of two"
        return nil
      let seqLen = (len(optValue) / 2).int
      if seqLen > optType.maxlen:
        optErrText = format("Byte length $# exceeds option maximum $#", $seqLen,
                     $optType.maxlen)
        return nil
      result.valueChars = newSeq[char](seqLen)
      try:
        for i in 0 ..< seqLen:
          result.valueChars[i] = cast[char](fromHex[int](optValue.substr(i*2, i*2+1)))
      except ValueError:
        optErrText = "Expecting hex digits"
        return nil
    of TYPE_STRING:
      if len(optValue) > optType.maxlen:
        optErrText = format("Length $# exceeds option maximum $#", $len(optValue),
                     $optType.maxlen)
        return nil
      result.valueText = optValue

proc buildValueLabel(optType: OptionType, o: MessageOption): string =
  ## Builds the display label for an option's value.
  case optType.dataType
  of TYPE_UINT:
    if o.optNum == COAP_OPTION_CONTENT_FORMAT:
      result = format("$#($#)", contentFmtTable[o.valueInt.int].name, $o.valueInt)
    else:
      result = $o.valueInt
  of TYPE_OPAQUE:
    for i in o.valueChars:
      result.add(toHex(cast[int](i), 2))
  of TYPE_STRING:
    result = o.valueText

proc showRequestWindow*(fixedFont: ptr ImFont) =
  # Depending on UI state, the handler for isEnterPressed() may differ. Ensure
  # it's handled only once.
  var isEnterHandled = false

  igSetNextWindowSize(ImVec2(x: 500, y: 300), FirstUseEver)
  igBegin("Request", isRequestOpen.addr)
  let labelColWidth = 90f

  # top-level items
  igAlignTextToFramePadding()
  igText("Protocol")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igComboString("##proto", reqProtoIndex, protoItems)

  igSameLine(250)
  igText("Port")
  igSameLine()
  igSetNextItemWidth(100)
  igInputInt("##port", reqPort.addr);

  igAlignTextToFramePadding()
  igText("Host")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  discard igInputTextCap("##host", reqHost, reqHostCapacity)

  igAlignTextToFramePadding()
  igText("URI Path")
  igSameLine(labelColWidth)
  igSetNextItemWidth(300)
  discard igInputTextCap("##path", reqPath, reqPathCapacity)

  igAlignTextToFramePadding()
  igText("Method")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  if igComboString("##method", reqMethodIndex, methodItems):
    if reqMethodIndex == 0:  # GET
      payload = newStringOfCap(payloadCapacity)

  igSameLine(220)
  igSetNextItemWidth(100)
  igCheckbox("Confirm", reqConfirm.addr)

  igItemSize(ImVec2(x:0,y:8))
  if igCollapsingHeader("Options"):
    # Must create child to limit length of separator
    igBeginChild("OptListHeaderChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.8f, y:24f))
    igTextColored(headingColor, "Type")
    igSameLine(150)
    igTextColored(headingColor, "Value")
    igSeparator()
    igEndChild()

    # Child offsets to right, so must push it left to align
    igSetCursorPosX(igGetCursorPosX() - 8f)
    igBeginChild("OptListChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.8f, y:optListHeight))
    igColumns(2, "optcols", false)
    igSetColumnWidth(-1, 150)

    for i in 0 ..< len(reqOptions):
      let o = reqOptions[i]
      let optType = optionTypesTable[o.optNum]
      if o.ctx == nil:
        # ImGui requires '##' suffix to uniquely identify a selectable object
        let v = MessageOptionView()
        v.typeLabel = format("$#($#)##reqOpt$#", optType.name, $o.optNum, $i)
        v.valueLabel = buildValueLabel(optType, o)
        o.ctx = v
      if i > 0:
        igNextColumn()
      if igSelectable(MessageOptionView(o.ctx).typeLabel, i == optionIndex,
                      ImGuiSelectableFlags.SpanAllColumns):
        optionIndex = i;
        optErrText = ""
        isNewOption = false

      igNextColumn()
      igText(MessageOptionView(o.ctx).valueLabel)
    igEndChild()

    # buttons for option list
    igSameLine()
    igBeginChild("OptButtonsChild",
                 ImVec2(x:igGetWindowContentRegionWidth() * 0.2f, y:optListHeight))
    igSetCursorPosY(igGetCursorPosY() + 8f)
    if igButton("New"):
      isNewOption = true
      optionIndex = -1
      optValue = newStringofCap(optValueCapacity)
    if igButton("Delete") and optionIndex >= 0:
      reqOptions.delete(optionIndex)
      # Trigger relabel on next display since index in collection may change
      for o in reqOptions:
        o.ctx = nil
      #optionIndex = -1
    igEndChild()

    # new option entry
    if isNewOption:
      igSetNextItemWidth(140)
      discard igComboNamedObj[OptionType]("##optName", optNameIndex, optionTypes)
      igSameLine()
      igSetNextItemWidth(150)
      let optType = optionTypes[optNameIndex]
      case optType.id
      of COAP_OPTION_CONTENT_FORMAT:
        discard igComboNamedObj[NamedId]("##optValue", cfNameIndex, cfList)
      else:
        discard igInputTextCap("##optValue", optValue, optValueCapacity)

      igSameLine(350)
      if igButton("OK") or (isEnterPressed() and not isEnterHandled):
        optErrText = ""
        let reqOption = buildNewOption(optType)
        if reqOption != nil:
          reqOptions.add(reqOption)
          # clear for next entry
          optValue = newStringOfCap(optValueCapacity)
        isEnterHandled = true

      igSameLine()
      if igButton("Done"):
        optErrText = ""
        isNewOption = false

      if optErrText != "":
        igTextColored(ImVec4(x: 1f, y: 0f, z: 0f, w: 1f), optErrText)

  if reqMethodIndex == 1 or reqMethodIndex == 2:
    # Include payload for POST or PUT
    igText("Payload")
    igSetNextItemWidth(420)
    igPushFont(fixedFont)
    discard igInputTextCap("##payload", payload, payloadCapacity,
                           ImVec2(x: 0f, y: igGetTextLineHeightWithSpacing() * 2),
                           Multiline)
    igPopFont()

  # Send
  igSetCursorPosY(igGetCursorPosY() + 8f)
  if igButton("Send Request") or (isEnterPressed() and not isEnterHandled):
    errText = ""
    respCode = ""
    respOptions = newSeq[MessageOption]()
    respText = ""
    var msgType: string
    if reqConfirm: msgType = "CON" else: msgType = "NON"
    var jNode = %*
      { "msgType": msgType, "uriPath": $reqPath.cstring,
        "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
        "remPort": reqPort, "method": reqMethodIndex+1,
        "reqOptions": toJson(reqOptions), "payload": payload }
    ctxChan.send( CoMsg(subject: "send_msg", payload: $jNode) )
    isEnterHandled = true
  igSameLine(150)
  if igButton("Reset"):
    resetContents()

  if len(errText) > 0:
    igSetNextItemWidth(400)
    igTextColored(ImVec4(x: 1f, y: 0f, z: 0f, w: 1f), errText)

  # Response, when available
  if len(respCode) > 0:
    igSetCursorPosY(igGetCursorPosY() + 8f)
    igSeparator()
    igTextColored(ImVec4(x: 1f, y: 1f, z: 0f, w: 1f), "Response")
    igText("Code")
    igSameLine(labelColWidth)
    igSetNextItemWidth(100)
    igText(respCode)

    igSetCursorPosY(igGetCursorPosY() + 8f)
    if igCollapsingHeader("Options##resp"):
      # Must create child to limit length of separator
      igBeginChild("RespOptListHeaderChild",
                   ImVec2(x:igGetWindowContentRegionWidth() * 0.8f, y:24f))
      igTextColored(headingColor, "Type")
      igSameLine(150)
      igTextColored(headingColor, "Value")
      igSeparator()
      igEndChild()

      # Child offsets to right, so must push it left to align
      igSetCursorPosX(igGetCursorPosX() - 8f)
      # Adjust height based on number of items, up to four rows
      igBeginChild("RespOptListChild",
                   ImVec2(x:igGetWindowContentRegionWidth() * 0.8f,
                          y:max(min(26 * len(respOptions), 80), 20).float))
      igColumns(2, "respOptcols", false)
      igSetColumnWidth(-1, 150)

      for i in 0 ..< len(respOptions):
        let o = respOptions[i]
        let optType = optionTypesTable[o.optNum]
        if o.ctx == nil:
          let v = MessageOptionView()
          v.typeLabel = format("$#($#)", optType.name, $o.optNum, $i)
          v.valueLabel = buildValueLabel(optType, o)
          o.ctx = v
          
        if i > 0:
          igNextColumn()
        igAlignTextToFramePadding()
        igText(MessageOptionView(o.ctx).typeLabel)
        igNextColumn()
        #igText(MessageOptionView(o.ctx).valueLabel)
        discard igInputTextCap(format("##respOption$#",$i),
                               MessageOptionView(o.ctx).valueLabel,
                               len(MessageOptionView(o.ctx).valueLabel),
                               ImVec2(x: 0f, y: igGetTextLineHeightWithSpacing()+2),
                               ImGuiInputTextFlags.ReadOnly)
      igEndChild()
      if len(respText) > 0:
        igSeparator()

    if len(respText) > 0:
      igSetCursorPosY(igGetCursorPosY() + 4f)
      igAlignTextToFramePadding()
      igText("Payload")
      #igSameLine(labelColWidth)
      #igRadioButton("Text", respPayFormatIndex.addr, 0)
      #igSameLine()
      #igRadioButton("Hex", respPayFormatIndex.addr, 1)

      igSetNextItemWidth(420)
      igPushFont(fixedFont)
      discard igInputTextCap("##respPayload", respText, len(respText),
                             ImVec2(x: 0f, y: igGetTextLineHeightWithSpacing() * 4),
                             (ImGuiInputTextFlags.Multiline.int or ImGuiInputTextFlags.ReadOnly.int).ImGuiInputTextFlags)
      igPopFont()

  igEnd()
