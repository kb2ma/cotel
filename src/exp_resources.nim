## Server handler module for experimental resources.
##
## Includes the /chars resource.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import libcoap, nativesockets
import logging, strutils
import conet_ctx

type ValueBuffer = array[0..7, char]
  ## Holds arbitrary values for encoding/decoding with libcoap

#
# /chars resource, to get character values
#

proc handleCharsGet(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_chars_get", noconv.} =
  ## TD_COAP_CORE_01, TD_COAP_CORE_05, TD_COAP_CORE_12
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  resp.code = COAP_RESPONSE_CODE_205  # Content

  # add text/plain Content-Format
  var buf: ValueBuffer
  let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t,
                             0.uint)
  var optlist = newOptlist(COAP_OPTION_CONTENT_FORMAT.uint16, valLen,
                           cast[ptr uint8](buf.addr))
  discard addOptlistPdu(resp, addr optlist)

  var chars = newString(16)
  for i in 0..15:
    chars[i] = (0xA0 + i).char
  #chars = $chars.toRunes()
  discard addData(resp, len(chars).csize_t, chars)
    
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("GET /chars from $#", remote))

proc initResources*(ctx: CContext) =
  var r = initResource(makeStringConst("chars"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleCharsGet)
  addResource(ctx, r)
