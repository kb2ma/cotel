## Cotel networking
##
## Runs libcoap server and client
##
## Copyright 2020 Ken Bannister
## SPDX-License-Identifier: Apache-2.0

import libcoap, posix, nativesockets
import logging

var netChan*: Channel[string]
  ## Communication channel to UI

proc handleHi(context: CContext, resource: CResource, session: CSession,
              req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
              {.exportc: "hnd_hi", noconv.} =
  ## server /hi GET handler; greeting
  resp.`type` = COAP_MESSAGE_ACK
  resp.code = COAP_RESPONSE_CODE_205
  discard addData(resp, 5, "Howdy")
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  netChan.send(remote & " GET /hi")

proc netLoop*() =
  ## Setup server and run event loop
  var log = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  open(netChan)

  # init context, listen port/endpoint
  var ctx = newContext(nil)

  # CoAP server setup
  var address = create(CSockAddr)
  initAddress(address)
  address.`addr`.sin.sin_family = Domain.AF_INET.cushort
  address.`addr`.sin.sin_port = posix.htons(5683)

  var ep = newEndpoint(ctx, address, COAP_PROTO_UDP)

  log.log(lvlInfo, "Cotel networking started on port ",
          posix.ntohs(address.`addr`.sin.sin_port))

  # Establish server resources and request handlers, and also the client
  # response handler.
  var r = initResource(makeStringConst("hi"), 0)
  registerHandler(r, COAP_REQUEST_GET, handleHi)
  addResource(ctx, r)

  # Serve resources until quit
  while true:
    discard processIo(ctx, COAP_IO_WAIT)
