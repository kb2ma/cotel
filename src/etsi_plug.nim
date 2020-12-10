## Server handler module for ETSI CoAP plugtests. Provides an array of resources
## to exercise a client.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

import libcoap, nativesockets
import logging, strutils
import conet_ctx

var testContents = "A. Corelli"

proc handleTestGet(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_get", noconv.} =
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  resp.code = COAP_RESPONSE_CODE_205
  discard addData(resp, len(testContents).csize_t, testContents)
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("GET /test from $#", remote))

proc handleTestPut(context: CContext, resource: CResource, session: CSession,
                   req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
                   {.exportc: "hnd_test_put", noconv.} =
  if req.`type` == COAP_MESSAGE_CON:
    resp.`type` = COAP_MESSAGE_ACK
  else:
    resp.`type` = COAP_MESSAGE_NON
  resp.code = COAP_RESPONSE_CODE_204  # Changed

  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(req, addr dataLen, addr dataPtr)
  var dataStr = newString(dataLen)
  copyMem(addr dataStr[0], dataPtr, dataLen)
  testContents = dataStr

  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  oplog.log(lvlInfo, format("PUT /test from $#", remote))


proc initResources*(ctx: CContext) =
  var r = initResource(makeStringConst("test"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleTestGet)
  registerHandler(r, COAP_REQUEST_PUT, handleTestPut)
  addResource(ctx, r)
