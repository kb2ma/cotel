## View to generate client request and show response
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import imgui
import algorithm, json, random, strutils, std/jsonutils, tables, unicode
import conet, gui_util

const
  reqHostCapacity = 64
  reqPathCapacity = 255
    ## No need to validate user entry for this path length
  optValueCapacity = 1034
    ## Length of the string used to edit option value; the longest possible
    ## option value.
  reqPayloadCapacity = 1024
  reqPayloadTextWidth = 48
    ## Width in chars for display of payload in text mode

  protoItems = ["coap", "coaps"]
  methodItems = ["GET", "POST", "PUT", "DELETE"]
  payFormatItems = ["Text", "Hex"]
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
  PayloadFormats = enum
    FORMAT_TEXT,
    FORMAT_HEX

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
  childBgColor: ptr ImVec4
    ## Cache value for use in display loop; initialized below in init()
  tokenLen: int
    ## Length of randomly generated token, in bytes. Initialized to the
    ## multiplicative inverse (-tokenLen) as a flag to seed the random module
    ## on the first request. This approach should provide more variation in
    ## the seed than always generating it at application startup time.

  # widget contents
  reqProtoIndex = 0
  reqPort = 5683'i32
  reqHost = newStringOfCap(reqHostCapacity)
  reqPath = newStringOfCap(reqPathCapacity)
  reqMethodIndex = 0
  reqConfirm = false
  reqPayload = ""
  reqPayText = newStringOfCap(reqPayloadCapacity)
  reqPayFormatIndex = FORMAT_TEXT.int32
    ## Index into 'payFormatItems' and 'PayloadFormats'. Must be int32 to
    ## satsify ImGui radio button.
  isTextOnlyReqPayload = true
    ## Indicates request payload contains only editable text characters
  respCode = ""
  respPayload = ""
    ## Actual payload from conet.
  respPayText = ""
    ## Payload representation for display.
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
  isChangedOption = false
    ## Tracks if new option type or value have changed for a request option,
    ## to support use of Enter key to save option.

  # response options
  respOptions = newSeq[MessageOption]()
  respPayFormatIndex = FORMAT_TEXT.int32
    ## Index into 'payFormatItems' and 'PayloadFormats'. Must be int32 to
    ## satisfy ImGui radio button.
  respMsgHasMore = false
    ## If response received from conet includes a Block2 option, the boolean
    ## value of the More attribute of the option. If true, more response blocks
    ## are available and will be requested.

proc init*(defaultTokenLen: int) =
  ## Initialization triggered by app after ImGui initialized
  childBgColor = igGetStyleColorVec4(ImGuiCol.ChildBg)
  tokenLen = -1 * defaultTokenLen

proc sendRequestNextBlock(lastBlock: MessageOption) =
  ## Requests the next response block (Block2) in sequence. The new/revised
  ## Block2 option will not be added to the displayed request options.
  let nextBlock = MessageOption(optNum: COAP_OPTION_BLOCK2)
  let lastValue = readBlockValue(lastBlock)
  nextBlock.valueInt = genBlockValueInt(lastValue.num + 1, false,
                                        lastValue.size).uint

  var nextOptions = newSeq[MessageOption]()
  var isBlockAdded = false
  for opt in reqOptions:
    if opt.optNum == COAP_OPTION_BLOCK2:
      nextOptions.add(nextBlock)
      isBlockAdded = true
    else:
      nextOptions.add(opt)
  # Block likely not present in first request unless user manually added it.
  if not isBlockAdded:
    nextOptions.add(nextBlock)
  
  var msgType: string
  if reqConfirm: msgType = "CON" else: msgType = "NON"

  var jNode = %*
    { "msgType": msgType, "uriPath": $reqPath.cstring,
      "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
      "remPort": reqPort, "method": reqMethodIndex+1,
      "reqOptions": toJson(nextOptions), "payload": reqPayload }
  echo("Requesting block " & $(lastValue.num + 1))
  ctxChan.send( CoMsg(subject: "send_msg", payload: $jNode) )

proc buildValueLabel(optType: OptionType, o: MessageOption): string =
  ## Builds the display label from an option's value.
  case optType.dataType
  of TYPE_UINT:
    if o.optNum == COAP_OPTION_CONTENT_FORMAT:
      result = format("$#($#)", contentFmtTable[o.valueInt.int].name, $o.valueInt)
    else:
      result = $o.valueInt
  of TYPE_OPAQUE:
    for i in o.valueChars:
      result.add(toHex(cast[int](i), 2))
      result.add(' ')
    # Trim trailing space
    if len(o.valueChars) > 0: result.setLen(len(result) - 1)
  of TYPE_STRING:
    result = o.valueText

proc buildPayloadText(paySource: string, format: PayloadFormats): string =
  ## Build and return text suitable for payload display, based on provided raw
  ## payload and output text format.
  # Must initialize to max capacity due to ImGui InputText requirements.
  result = newStringOfCap(reqPayloadCapacity)
  case format
  of FORMAT_TEXT:
    # Convert any non-printable ASCII chars to a U00B7 dot. Also add line
    # break as required.
    var runeCount = 0
    for r in runes(paySource):
      if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
        result.add("\u{B7}")
      else:
        result.add(toUTF8(r))
      runeCount += 1
      if runeCount == reqPayloadTextWidth:
        result.add("\n")
        runeCount = 0
  of FORMAT_HEX:
    # Convert all chars to two-digit hex text, separated by a space. Also
    # add a line break as required.
    var charCount = 0
    for c in paySource:
      result.add(toHex(cast[int](c), 2))
      charCount += 1
      if charCount == 8:
        result.add(' ')
      if charCount == 16:
        result.add("\n")
        charCount = 0
      else:
        result.add(' ')

proc onNetMsgRequest*(msg: CoMsg) =
  if msg.subject == "response.payload":
    let msgJson = parseJson(msg.payload)
    respCode = msgJson["code"].getStr()

    # Must clear response options for each follow-on Block2 case.
    respOptions = newSeq[MessageOption]()
    respMsgHasMore = false
    var lastBlock: MessageOption
    for optJson in msgJson["options"]:
      echo("resp option " & $optJson)
      let option = jsonTo(optJson, MessageOption)
      if option.optNum == COAP_OPTION_BLOCK2:
        respMsgHasMore = readBlockValue(option).more
        lastBlock = option
      respOptions.add(option)

    if msgJson.hasKey("payload"):
      # Append rather than replace follow-on Block2 responses.
      if lastBlock != nil and readBlockValue(lastBlock).num > 0:
        respPayload.add(msgJson["payload"].getStr())
      else:
        respPayload = msgJson["payload"].getStr()
      respPayText = buildPayloadText(respPayload, respPayFormatIndex.PayloadFormats)
    else:
      # Don't clear response payload in Block2 case, although this should not
      # happen. We wish to retain the payloads from previous responses in the
      # series.
      if lastBlock == nil:
        respPayload = ""
        respPayText = ""
      
    if respMsgHasMore:
      sendRequestNextBlock(lastBlock)
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
        result = true
      if isSelected:
        igSetItemDefaultFocus()
    igEndCombo()

proc resetContents() =
  ## Resets many vars to blank/empty state.
  reqPath = newString(reqPathCapacity)
  reqOptions = newSeq[MessageOption]()
  isChangedOption = false
  optionIndex = -1
  optNameIndex = 0
  cfNameIndex = 0
  optValue = newStringofCap(optValueCapacity)
  reqPayload = newStringOfCap(reqPayloadCapacity)
  isTextOnlyReqPayload = true
  optErrText = ""
  respCode = ""
  respOptions = newSeq[MessageOption]()
  respPayload = ""
  respPayText = ""
  errText = ""

proc validateNewOption(optType: OptionType): MessageOption =
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
      result.valueChars = newSeq[char]()
      for text in strutils.splitWhitespace(optValue):
        if len(text) mod 2 != 0:
          optErrText = "Expecting hex digits, but length not a multiple of two"
          return nil
        let seqLen = (len(text) / 2).int
        try:
          for i in 0 ..< seqLen:
            result.valueChars.add(cast[char](fromHex[int](text.substr(i*2, i*2+1))))
        except ValueError:
          optErrText = "Expecting hex digits"
          return nil
      if len(result.valueChars) > optType.maxlen:
        optErrText = format("Byte length $# exceeds option maximum $#",
                            len(result.valueChars), $optType.maxlen)
        return nil

    of TYPE_STRING:
      if len(optValue) > optType.maxlen:
        optErrText = format("Length $# exceeds option maximum $#", $len(optValue),
                            $optType.maxlen)
        return nil
      result.valueText = optValue

proc validateHexPayload(payText: string): bool =
  # Strip whitespace including newlines from the provided text, and save as
  # variable 'reqPayload'.
  var stripped = ""
  try:
    for text in strutils.splitWhitespace(payText):
      if len(text) mod 2 != 0:
        errText = "Expecting pairs of hex digits in payload"
        return false
      for i in 0 ..< (len(text) / 2).int:
        #let charInt = fromHex[int](text.substr(i*2, i*2+1))
        #echo(format("char $#", fmt"{charInt:X}"))
        #stripped.add(cast[char](charInt))
        stripped.add(cast[char](fromHex[int](text.substr(i*2, i*2+1))))
    reqPayload = stripped
  except ValueError:
    errText = "Expecting hex digits in payload"
    return false
  return true

proc filterPayloadChar(data: ptr ImGuiInputTextCallbackData): int32 =
  ## Callback for request payload text entry to accept only ASCII chars, or
  ## CR/LF.
  if (data.eventChar >= ' '.uint16 and data.eventChar <= '~'.uint16) or
      data.eventChar == 0x0A'u16 or data.eventChar == 0x0D'u16:
    return 0
  return 1

proc validateTextPayload(payText: string) =
  # Strip newlines from the provided text and save as variable 'reqPayload'.
  var stripped = ""
  for line in splitLines(payText):
    stripped.add(line)
  reqPayload = stripped

proc showRequestWindow*(fixedFont: ptr ImFont) =
  igSetNextWindowSize(ImVec2(x: 500, y: 300), FirstUseEver)
  igBegin("Request", isRequestOpen.addr)
  let labelColWidth = 90f

  # top-level items
  igAlignTextToFramePadding()
  igText("Protocol")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  discard igComboString("##proto", reqProtoIndex, protoItems)

  igSameLine(220)
  igText("Port")
  igSameLine()
  igSetNextItemWidth(100)
  igInputInt("##port", reqPort.addr);

  igAlignTextToFramePadding()
  igText("Host")
  igSameLine(labelColWidth)
  igSetNextItemWidth(340)
  discard igInputTextCap("##host", reqHost, reqHostCapacity)

  igAlignTextToFramePadding()
  igText("URI Path")
  igSameLine(labelColWidth)
  igSetNextItemWidth(340)
  discard igInputTextCap("##path", reqPath, reqPathCapacity)

  igAlignTextToFramePadding()
  igText("Method")
  igSameLine(labelColWidth)
  igSetNextItemWidth(100)
  if igComboString("##method", reqMethodIndex, methodItems):
    if reqMethodIndex == 0:  # GET
      reqPayload = newStringOfCap(reqPayloadCapacity)
      isTextOnlyReqPayload = true

  igSameLine(220)
  igSetNextItemWidth(100)
  igCheckbox("Confirm", reqConfirm.addr)

  var isSubmitOption = false
  var optType: OptionType
  let optControlWidth = 80f
  let optListWidth = max(350, igGetWindowContentRegionWidth() - 80)
  igItemSize(ImVec2(x:0,y:8))
  if igCollapsingHeader("Options"):
    # Must create child to limit length of separator
    igBeginChild("OptListHeaderChild", ImVec2(x:optListWidth, y:24f))
    igTextColored(headingColor, "Type")
    igSameLine(150)
    igTextColored(headingColor, "Value")
    igSeparator()
    igEndChild()

    # Child offsets to right, so must push it left to align
    igSetCursorPosX(igGetCursorPosX() - 8f)
    igBeginChild("OptListChild", ImVec2(x:optListWidth, y:optListHeight))
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
        isChangedOption = false
      igNextColumn()
      igText(MessageOptionView(o.ctx).valueLabel)
    igEndChild()

    # buttons for option list
    igSameLine()
    igBeginChild("OptButtonsChild", ImVec2(x:optControlWidth, y:optListHeight))
    igSetCursorPosY(igGetCursorPosY() + 8f)
    if igButton("New"):
      isNewOption = true
      isChangedOption = false
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
      if igComboNamedObj[OptionType]("##optName", optNameIndex, optionTypes):
        isChangedOption = true
      igSameLine()
      igSetNextItemWidth(180 + max(0, igGetWindowContentRegionWidth() - 430))
      optType = optionTypes[optNameIndex]
      case optType.id
      of COAP_OPTION_CONTENT_FORMAT:
        if igComboNamedObj[NamedId]("##optValue", cfNameIndex, cfList):
          isChangedOption = true
      else:
        if igInputTextCap("##optValue", optValue, optValueCapacity):
          isChangedOption = true

      igSameLine(optListWidth)
      if igButton("OK") or (isEnterPressed() and isChangedOption):
        # Flag to handle option save below
        isSubmitOption = true

      igSameLine()
      if igButton("Done"):
        optErrText = ""
        isNewOption = false
        isChangedOption = false

      if len(optErrText) > 0:
        igTextColored(ImVec4(x: 1f, y: 0f, z: 0f, w: 1f), optErrText)
    igSeparator()

  # One of three actions may consume press of Enter key, listed below in
  # priority order.
  #   1. Create new line in request payload, when cursor in ##payload field
  #   2. Save new option (like press OK button)
  #   3. Send request (like press Send Request button)
  var isEnterHandled = false
  if reqMethodIndex == 1 or reqMethodIndex == 2:
    # Include payload for POST or PUT.
    igAlignTextToFramePadding()
    igText("Payload")
    igSameLine(labelColWidth)
    # Update payload from current InputText, and reformat. Disallow editing if
    # transitioning from hex to text and contains non-editable chars.
    if igRadioButton(payFormatItems[FORMAT_TEXT.int], reqPayFormatIndex.addr, 0):
      if validateHexPayload(reqPayText):
        isTextOnlyReqPayload = true
        for r in runes(reqPayload):
          if (r <% " ".runeAt(0)) or (r >% "~".runeAt(0)):
            isTextOnlyReqPayload = false
            break
        reqPayText = buildPayloadText(reqPayload, FORMAT_TEXT)
      else:
        reqPayFormatIndex = FORMAT_HEX.int32
    igSameLine()
    if igRadioButton(payFormatItems[FORMAT_HEX.int], reqPayFormatIndex.addr, 1):
      # Only read text if it was editable; otherwise it includes non-editable
      # chars. In either case hex payload is built from saved 'reqPayload' chars.
      if isTextOnlyReqPayload:
        validateTextPayload(reqPayText)
      reqPayText = buildPayloadText(reqPayload, FORMAT_HEX)

    var payFlags = ImGuiInputTextFlags.Multiline.int32 or
                   ImGuiInputTextFlags.CallbackCharFilter.int32
    # Can't edit in text mode if contains non-editable chars
    if not isTextOnlyReqPayload and reqPayFormatIndex == FORMAT_TEXT.int32:
      payFlags = payFlags or ImGuiInputTextFlags.ReadOnly.int32
      igSameLine(220)
      igTextColored(headingColor, "Read only")

    igSetNextItemWidth(420)
    igPushFont(fixedFont)
    # InputText is tall enough to show five lines.
    discard igInputTextCap("##payload", reqPayText, reqPayloadCapacity,
                           ImVec2(x: 0f, y: igGetTextLineHeightWithSpacing() * 4 + 6),
                           payFlags.ImGuiInputTextFlags,
                           cast[ImGuiInputTextCallback](filterPayloadChar))
    if igIsItemActive() and isEnterPressed():
      isEnterHandled = true
    igPopFont()

  if isSubmitOption and not isEnterHandled:
    # Must handle option save here, after determine if payload InputText
    # handled the Enter key.
    optErrText = ""
    let reqOption = validateNewOption(optType)
    if reqOption != nil:
      reqOptions.add(reqOption)
      # clear for next entry
      optValue = newStringOfCap(optValueCapacity)
    isEnterHandled = true
    isChangedOption = false

  # Send
  igSetCursorPosY(igGetCursorPosY() + 8f)
  if igButton("Send Request") or (isEnterPressed() and not isEnterHandled):
    errText = ""
    respCode = ""
    respOptions = newSeq[MessageOption]()
    respPayload = ""
    respPayText = ""
    var msgType: string
    if reqConfirm: msgType = "CON" else: msgType = "NON"

    # Generate token
    if tokenLen < 0:
      # Initialize random number generator on first request by the user.
      randomize()
      tokenLen *= -1
    var token: string
    if tokenLen > 0:
      let tokenInt = rand(uint64)
      for i in 0 ..< tokenLen:
        token.add(((tokenInt and (0xFF'u64 shl (8*i))) shr (8*i)).char)

    var isValidPayload = true
    case reqPayFormatIndex.PayloadFormats
    of FORMAT_TEXT:
      validateTextPayload(reqPayText)
    of FORMAT_Hex:
      isValidPayload = validateHexPayload(reqPayText)
    if isValidPayload:
      var jNode = %*
        { "msgType": msgType, "uriPath": $reqPath.cstring,
          "proto": $protoItems[reqProtoIndex], "remHost": $reqHost.cstring,
          "remPort": reqPort, "method": reqMethodIndex+1, "token": token,
          "reqOptions": toJson(reqOptions), "payload": reqPayload }
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
    if respMsgHasMore:
      igSameLine(labelColWidth)
      igTextColored(headingColor, "partial, more to come")
    else:
      igSameLine(labelColWidth)
      igTextColored(headingColor, "complete")
    igText("Code")
    igSameLine(labelColWidth)
    igSetNextItemWidth(100)
    igText(respCode)

    igSetCursorPosY(igGetCursorPosY() + 8f)
    if igCollapsingHeader("Options##resp"):
      # Must create child to limit length of separator
      igBeginChild("RespOptListHeaderChild", ImVec2(x:optListWidth, y:24f))
      igTextColored(headingColor, "Type")
      igSameLine(150)
      igTextColored(headingColor, "Value")
      igSeparator()
      igEndChild()

      # Child offsets to right, so must push it left to align
      igSetCursorPosX(igGetCursorPosX() - 8f)
      # Adjust height based on number of items, up to four rows
      igBeginChild("RespOptListChild",
                   ImVec2(x:optListWidth,
                          y:max(min(26 * len(respOptions), 80), 20).float))
      igColumns(2, "respOptcols", false)
      igSetColumnWidth(-1, 147)
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
        igText(MessageOptionView(o.ctx).typeLabel)
        igNextColumn()
        # Display with Text colors, but use InputText widget to allow copy text.
        # Also, red
        igPushStyleColor(ImGuiCol.FrameBg, childBgColor[])
        igPushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(x:0f, y:0f))
        discard igInputTextCap(format("##respOption$#",$i),
                               MessageOptionView(o.ctx).valueLabel,
                               len(MessageOptionView(o.ctx).valueLabel),
                               ImVec2(x: optListWidth - 150,
                                      y: igGetTextLineHeight()),
                               ImGuiInputTextFlags.ReadOnly)
        igPopStyleVar()
        igPopStyleColor()
      igEndChild()

      if len(respPayText) > 0:
        igSeparator()

    if len(respPayText) > 0:
      igSetCursorPosY(igGetCursorPosY() + 4f)
      igAlignTextToFramePadding()
      igText("Payload")
      igSameLine(labelColWidth)
      if igRadioButton(payFormatItems[FORMAT_TEXT.int], respPayFormatIndex.addr, 0):
        respPayText = buildPayloadText(respPayload, FORMAT_TEXT)
      igSameLine()
      if igRadioButton(payFormatItems[FORMAT_HEX.int], respPayFormatIndex.addr, 1):
        respPayText = buildPayloadText(respPayload, FORMAT_HEX)

      igSetNextItemWidth(420)
      igPushFont(fixedFont)
      discard igInputTextCap("##respPayload", respPayText, len(respPayText),
                             ImVec2(x: 0f, y: igGetTextLineHeightWithSpacing() * 8),
                             (ImGuiInputTextFlags.Multiline.int or ImGuiInputTextFlags.ReadOnly.int).ImGuiInputTextFlags)
      igPopFont()

  igEnd()
