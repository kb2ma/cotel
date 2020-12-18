## Library for CoAP messaging. Contains common messaging functionality on top
## of libcoap, like reading options from a PDU.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import libcoap
# import the minimum fron conet_ctx to allow logging
from conet_ctx import oplog
import logging, tables

type
  OptionDataType* = enum
    ## data type for a CoAP option type
    TYPE_UINT,
    TYPE_STRING,
    TYPE_OPAQUE

  OptionType* = tuple
    ## Value parameters for a type of option
    id: int
      ## A COAP_OPTION... const
    dataType: OptionDataType
    maxlen: int
    name: string
      ## Canonical name for the type of option, like "Uri-Path"

  MessageOptionContext* = ref object of RootObj
    ## Abstract superclass for context/holder of a message option. See
    ## MessageOption definition below.

  MessageOption* = ref object
    ## Option value in a CoAP message. Provides a single entity for back-end
    ## and front-end use.
    ##
    ## At least one of valueInt, valueChars, valueText must be populated,
    ## corresponding to option type.
    optNum*: int
      ## A COAP_OPTION... const; provides a link to an OptionType
    valueText*: string
    valueChars*: seq[char]
      ## For value data for an opaque option type
    valueInt*: uint
    ctx*: MessageOptionContext
      ## (optional) Context specific data about a message option; not used by
      ## the conet module. We expect any context using the conet module to
      ## define a concrete subclass if needed.

const optionTypesTable* = {
  COAP_OPTION_ACCEPT:         (id: COAP_OPTION_ACCEPT,         dataType: TYPE_UINT,   maxlen:    2, name: "Accept"),
  COAP_OPTION_BLOCK1:         (id: COAP_OPTION_BLOCK1,         dataType: TYPE_UINT,   maxlen:    3, name: "Block1"),
  COAP_OPTION_BLOCK2:         (id: COAP_OPTION_BLOCK2,         dataType: TYPE_UINT,   maxlen:    3, name: "Block2"),
  COAP_OPTION_CONTENT_FORMAT: (id: COAP_OPTION_CONTENT_FORMAT, dataType: TYPE_UINT,   maxlen:    2, name: "Content-Format"),
  COAP_OPTION_ETAG:           (id: COAP_OPTION_ETAG,           dataType: TYPE_OPAQUE, maxlen:    8, name: "ETag"),
  COAP_OPTION_IF_MATCH:       (id: COAP_OPTION_IF_MATCH,       dataType: TYPE_OPAQUE, maxlen:    8, name: "If-Match"),
  COAP_OPTION_IF_NONE_MATCH:  (id: COAP_OPTION_IF_NONE_MATCH,  dataType: TYPE_UINT,   maxlen:    1, name: "If-None-Match"),
  COAP_OPTION_LOCATION_PATH:  (id: COAP_OPTION_LOCATION_PATH,  dataType: TYPE_STRING, maxlen:  255, name: "Location-Path"),
  COAP_OPTION_LOCATION_QUERY: (id: COAP_OPTION_LOCATION_QUERY, dataType: TYPE_STRING, maxlen:  255, name: "Location-Query"),
  COAP_OPTION_MAXAGE:         (id: COAP_OPTION_MAXAGE,         dataType: TYPE_UINT,   maxlen:    4, name: "Max-Age"),
  COAP_OPTION_NORESPONSE:     (id: COAP_OPTION_NORESPONSE,     dataType: TYPE_UINT,   maxlen:    1, name: "No-Response"),
  COAP_OPTION_OBSERVE:        (id: COAP_OPTION_OBSERVE,        dataType: TYPE_UINT,   maxlen:    3, name: "Observe"),
  COAP_OPTION_PROXY_SCHEME:   (id: COAP_OPTION_PROXY_SCHEME,   dataType: TYPE_STRING, maxlen:  255, name: "Proxy-Scheme"),
  COAP_OPTION_PROXY_URI:      (id: COAP_OPTION_PROXY_URI,      dataType: TYPE_STRING, maxlen: 1034, name: "Proxy-Uri"),
  COAP_OPTION_SIZE1:          (id: COAP_OPTION_SIZE1,          dataType: TYPE_UINT,   maxlen:    4, name: "Size1"),
  COAP_OPTION_SIZE2:          (id: COAP_OPTION_SIZE2,          dataType: TYPE_UINT,   maxlen:    4, name: "Size2"),
  COAP_OPTION_URI_HOST:       (id: COAP_OPTION_URI_HOST,       dataType: TYPE_STRING, maxlen:  255, name: "Uri-Host"),
  COAP_OPTION_URI_PATH:       (id: COAP_OPTION_URI_PATH,       dataType: TYPE_STRING, maxlen:  255, name: "Uri-Path"),
  COAP_OPTION_URI_PORT:       (id: COAP_OPTION_URI_PORT,       dataType: TYPE_UINT,   maxlen:    2, name: "Uri-Port"),
  COAP_OPTION_URI_QUERY:      (id: COAP_OPTION_URI_QUERY,      dataType: TYPE_STRING, maxlen:  255, name: "Uri-Query")
}.toTable

# sanity check at startup
for item in optionTypesTable.values:
  if item.dataType == TYPE_UINT:
    assert(item.maxlen <= sizeof(uint))

const contentFmtTable* = {
    0: (id: 0, name: "text/plain"), 60: (id: 60, name: "app/cbor"),
   50: (id: 50 , name: "app/json"), 40: (id: 40, name: "app/link-format"),
  112: (id: 112, name: "app/senml+cbor"), 110: (id: 110, name: "app/senml+json"),
  113: (id: 113, name: "app/sensml+cbor"), 111: (id: 111, name: "app/sensml+json"),
   41: (id: 42, name: "octet-stream") }.toTable
  ## Content-Format option values


proc readOptions*(pdu: CPdu): seq[MessageOption] =
  ## Reads and returns all options from the provided PDU. A caller should wrap
  ## this function in a try: block for unexpected errors.
  var it = new COptIterator

  discard initOptIterator(pdu, it, COAP_OPT_ALL)
  var itIndex = 0
  while true:
    let rawOpt = nextOption(it)
    if rawOpt == nil:
      break
    #echo("optType " & $it.optType)
    itIndex += 1

    # fill in the MessageOption object
    let
      option = MessageOption(optNum: it.optType.int)
      optType = optionTypesTable[option.optNum]
      valLen = optLength(rawOpt).int

    # Discard oversized option. In some contexts it might make more sense to
    # just throw an exception.
    if valLen > optType.maxlen:
      oplog.log(lvlError, "Option $# length $#, discarded", $itIndex, $valLen)
      continue

    case optType.dataType
    of TYPE_UINT:
      if valLen == 0:
        option.valueInt = 0
      else:
        var rawValue = newSeq[uint8](valLen)
        copyMem(rawValue[0].addr, optValue(rawOpt), valLen)
        for i in 0 ..< valLen:
          option.valueInt += rawValue[i].uint shl (8*(valLen-(i+1)))
    of TYPE_STRING:
      option.valueText = newString(min(valLen+1, optType.maxlen+1))
      copyMem(option.valueText[0].addr, optValue(rawOpt), valLen)
      option.valueText.setLen(valLen)
    of TYPE_OPAQUE:
      option.valueChars = newSeq[char](min(valLen+1, optType.maxlen+1))
      copyMem(option.valueChars[0].addr, optValue(rawOpt), valLen)
      option.valueChars.setLen(valLen)

    result.add(option)
