## Conet provides CoAP networking via the [libcoap module](libcoap.html).
## An application runs Conet in a thread and communicates via the async
## channels in the [conet_ctx module](conet_ctx.html).
##
## Start Conet with a call to [netLoop()](conet.html#netLoop%2CServerConfig),
## which monitors network sockets as well as the channels to the enclosing
## application. Conet provides two services:
##
## * receive requests from a single server endpoint with either NoSec or PSK security
## * send requests to other servers, either with the secure coaps protocol or
##   with the insecure coap protocol
##
## As a CoAP server, Conet listens only for a GET request to th `/hi` resource.
##
## Copyright 2020 Ken Bannister
##
## SPDX-License-Identifier: Apache-2.0

const useWinVersion = defined(Windows) or defined(nimdoc)
when useWinVersion:
  import winlean
  # copy values from posix if not defined in winlean
  const posix_AF_UNSPEC = winlean.AF_UNSPEC
  const posix_SOCK_DGRAM = cint(2)
  const posix_AF_INET = winlean.AF_INET
  const posix_AF_INET6 = winlean.AF_INET6
else:
  import posix
  const posix_AF_UNSPEC = posix.AF_UNSPEC
  const posix_SOCK_DGRAM = posix.SOCK_DGRAM
  const posix_AF_INET = posix.AF_INET
  const posix_AF_INET6 = posix.AF_INET6

import libcoap, nativesockets
import json, logging, parseutils, strformat, strutils, std/jsonutils
import conet_ctx, etsi_plug
# Provides the core context data for conet module users to share
export conet_ctx, libcoap.COptionId


type
  OptionDataType* = enum
    ## data type for a CoAP option
    TYPE_UINT,
    TYPE_STRING,
    TYPE_OPAQUE

  OptionType* = tuple
    id: int
      # a libcoap COAP_OPTION... const
    dataType: OptionDataType
    maxlen: int
    name: string

  MessageOption* = ref object
    ## Option in a CoAP message
    optNum*: int
    typesIndex*: int
      ## index into optionTypes array
    # Only one of the following is used, based on optNum (really, option data type)
    valueText*: string
    valueChars*: seq[char]
    valueInt*: int

  ServerConfig* = ref object
    # Configuration data for important aspects of the server
    listenAddr*: string
    nosecEnable*: bool
    nosecPort*: int
    secEnable*: bool
    secPort*: int
    pskKey*: seq[char]
    pskClientId*: string

  ConetState = ref object
    ## Running state of Conet
    ctx: CContext
    endpoints: seq[CEndpoint]
      ## by conventaion, two endpoints: [0] is nosec, [1] is secure

  ConetError* = object of CatchableError
    ## Networking error recognized by conet

  ValueBuffer = array[0..7, char]
    ## Holds arbitrary values for encoding/decoding with libcoap

let optionTypes* = [
  (id: OPTION_ACCEPT.int,         dataType: TYPE_UINT,   maxlen:    2, name: "Accept"),
  (id: OPTION_BLOCK1.int,         dataType: TYPE_UINT,   maxlen:    3, name: "Block1"),
  (id: OPTION_BLOCK2.int,         dataType: TYPE_UINT,   maxlen:    3, name: "Block2"),
  (id: OPTION_CONTENT_FORMAT.int, dataType: TYPE_UINT,   maxlen:    2, name: "Content-Format"),
  (id: OPTION_ETAG.int,           dataType: TYPE_OPAQUE, maxlen:    8, name: "ETag"),
  (id: OPTION_IF_MATCH.int,       dataType: TYPE_OPAQUE, maxlen:    8, name: "If-Match"),
  (id: OPTION_IF_NONE_MATCH.int,  dataType: TYPE_UINT,   maxlen:    1, name: "If-None-Match"),
  (id: OPTION_LOCATION_PATH.int,  dataType: TYPE_STRING, maxlen:  255, name: "Location-Path"),
  (id: OPTION_LOCATION_QUERY.int, dataType: TYPE_STRING, maxlen:  255, name: "Location-Query"),
  (id: OPTION_MAXAGE.int,         dataType: TYPE_UINT,   maxlen:    4, name: "Max-Age"),
  (id: OPTION_NORESPONSE.int,     dataType: TYPE_UINT,   maxlen:    1, name: "No-Response"),
  (id: OPTION_OBSERVE.int,        dataType: TYPE_UINT,   maxlen:    3, name: "Observe"),
  (id: OPTION_PROXY_SCHEME.int,   dataType: TYPE_STRING, maxlen:  255, name: "Proxy-Scheme"),
  (id: OPTION_PROXY_URI.int,      dataType: TYPE_STRING, maxlen: 1034, name: "Proxy-Uri"),
  (id: OPTION_SIZE1.int,          dataType: TYPE_UINT,   maxlen:    4, name: "Size1"),
  (id: OPTION_SIZE2.int,          dataType: TYPE_UINT,   maxlen:    4, name: "Size2"),
  (id: OPTION_URI_HOST.int,       dataType: TYPE_STRING, maxlen:  255, name: "Uri-Host"),
  (id: OPTION_URI_PATH.int,       dataType: TYPE_STRING, maxlen:  255, name: "Uri-Path"),
  (id: OPTION_URI_PORT.int,       dataType: TYPE_UINT,   maxlen:    2, name: "Uri-Port"),
  (id: OPTION_URI_QUERY.int,      dataType: TYPE_STRING, maxlen:  255, name: "Uri-Query")
]

proc handleHi(context: CContext, resource: CResource, session: CSession,
              req: CPdu, token: CCoapString, query: CCoapString, resp: CPdu)
              {.exportc: "hnd_hi", noconv.} =
  ## server /hi GET handler; greeting
  resp.`type` = COAP_MESSAGE_ACK
  resp.code = COAP_RESPONSE_CODE_205
  discard addData(resp, 5, "Howdy")
  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  netChan.send( CoMsg(subject: "request.log", payload: remote & " GET /hi") )

proc handleResponse(context: CContext, session: CSession, sent: CPdu,
                    received: CPdu, id: CTxid)
                    {.exportc: "hnd_response", noconv.} =
  ## client response handler
  #oplog.log(lvlDebug, "Response received")
  var dataLen: csize_t
  var dataPtr: ptr uint8
  discard getData(received, addr dataLen, addr dataPtr)

  let codeStr = "$#.$#\n" % [fmt"{received.code shr 5}",
                             fmt"{received.code and 0x1F:>02}"]
  var jNode: JsonNode
  
  if dataLen > 0:
    var dataStr = newString(dataLen)
    copyMem(addr dataStr[0], dataPtr, dataLen)
    jNode = %* { "code": codeStr, "payload": dataStr }
  else:
    jNode = %* { "code": codeStr }

  netChan.send( CoMsg(subject: "response.payload", payload: $jNode) )


proc handleCoapLog(level: CLogLevel, message: cstring)
                   {.exportc: "hnd_log", noconv.} =
  var lvl: Level
  case level
  of LOG_EMERG, LOG_ALERT, LOG_CRIT, LOG_ERR:
    lvl = lvlError
  of LOG_WARNING:
    lvl = lvlWarn
  of LOG_NOTICE:
    lvl = lvlNotice
  of LOG_INFO:
    lvl = lvlInfo
  of LOG_DEBUG, COAP_LOG_CIPHERS:
    lvl = lvlDebug

  # strip trailing whitespace to avoid extra newline
  oplog.log(lvl, strip($message, false))

proc resolveAddress(ctx: CContext, host: string, port: string,
                    sockAddr: ptr CSockAddr) =
  ## Looks up network address info. Initializes and updates 'sockAddr'.
  ## Prefers IPv6 address, although the format of the host address should
  ## suggest the IP version.

  var hints: AddrInfo
  hints.ai_family = posix_AF_UNSPEC
  hints.ai_socktype = posix_SOCK_DGRAM
  # Use 'info' to iterate over linked list, and retain first element in 'firstInfo'.
  var info, firstInfo: ptr AddrInfo

  initAddress(sockAddr)
  if getaddrinfo(host, port, addr hints, firstInfo).bool:
    raise newException(ConetError,
                       "Can't resolve address for host $#, port $#" % [host, port])
  info = firstInfo

  while info != nil:
    case info.ai_family
    of posix_AF_INET6:
      sockAddr.size = sizeof(SockAddr_in6).SockLen
      copyMem(addr sockAddr.`addr`.sin6, info.ai_addr, sockAddr.size)
      break
    of posix_AF_INET:
      sockAddr.size = sizeof(SockAddr_in).SockLen
      copyMem(addr sockAddr.`addr`.sin, info.ai_addr, sockAddr.size)
    else:
      discard
    info = info.ai_next

  freeaddrinfo(firstInfo)

proc sendMessage(ctx: CContext, config: ServerConfig, jsonStr: string) =
  ## Send a message to exercise client flow with a server.
  let reqJson = parseJson(jsonStr)

  # init server address/port
  let address = create(CSockAddr)
  let host = reqJson["remHost"].getStr()
  let port = reqJson["remPort"].getInt()
  resolveAddress(ctx, host, $port, address)

  #init session
  var session: CSession
  if getStr(reqJson["proto"]) == "coaps":
    # Assume libcoap retains PSK session, so look for it. Also assume use of
    # local interface 0.
    session = findSession(ctx, address, 0)
    if session == nil:
      session = newClientSessionPsk(ctx, nil, address, COAP_PROTO_DTLS,
                                    config.pskClientId,
                                    cast[ptr uint8](addr config.pskKey[0]),
                                    config.pskKey.len.uint)
    elif session.proto != COAP_PROTO_DTLS:
      raise newException(ConetError,
                         format("Protocol coaps not valid to $#", fmt"{port}"))
  else:
    # proto must be 'coap'
    session = newClientSession(ctx, nil, address, COAP_PROTO_UDP)
  if session == nil:
    raise newException(ConetError, "Can't create client session")

  # init PDU, including type and code
  var msgType: uint8
  if reqJson["msgType"].getStr() == "CON":
    msgType = COAP_MESSAGE_CON
  else:
    msgType = COAP_MESSAGE_NON

  var pdu = initPdu(msgType, reqJson["method"].getInt().uint8, 1000'u16,
                    maxSessionPduSize(session))
  if pdu == nil:
    releaseSession(session)
    raise newException(ConetError, "Can't create client PDU")

  # add options
  let uriPath = reqJson["uriPath"].getStr()
  var pos = 0
  var chain: COptlist

  # Uri-Path from path string
  while pos < uriPath.len:
    var token: string
    let plen = parseUntil(uriPath, token, '/', pos)
    #echo("start pos: ", pos, ", token: ", token, " of len ", plen)
    if plen > 0:
      let optlist = newOptlist(OPTION_URI_PATH.uint16, len(token).csize_t,
                               cast[ptr uint8](token.cstring))
      if optlist == nil:
        raise newException(ConetError, "Can't create option list")
      if not insertOptlist(addr chain, optlist).bool:
        raise newException(ConetError, "Can't add to option chain")
    pos = pos + plen + 1
    
  # other options
  for optJson in reqJson["reqOptions"]:
    let option = jsonTo(optJson, MessageOption)
    var
      buf: ValueBuffer
      optlist: COptlist
    if option.valueInt > -1:
      let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t,
                                 option.valueInt.uint)
      optlist = newOptlist(option.optNum.uint16, valLen, cast[ptr uint8](buf.addr))
    else:
      optlist = newOptlist(option.optNum.uint16, len(option.valueText).csize_t,
                           cast[ptr uint8](option.valueText.cstring))
    if optlist == nil:
      raise newException(ConetError, "Can't create option list")
    if not insertOptlist(addr chain, optlist).bool:
      raise newException(ConetError, "Can't add to option chain")

  # Path may just be "/". No PDU option in that case.
  if chain == nil and uriPath != "/":
    raise newException(ConetError, "Can't create option list (2)")
  if chain != nil and not addOptlistPdu(pdu, addr chain).bool:
    deleteOptlist(chain)
    deletePdu(pdu)
    releaseSession(session)
    raise newException(ConetError, "Can't create option list (3)")
  deleteOptlist(chain)

  if reqJson.hasKey("payload"):
    let payload = reqJson["payload"].getStr()
    discard addData(pdu, len(payload).csize_t, payload)

  # send
  if send(session, pdu) == COAP_INVALID_TXID:
    deletePdu(pdu)

proc createEndpoint(ctx: CContext, listenAddr: string, port: int,
                    proto: CProto): CEndpoint =
      # CoAP server setup
      var address = create(CSockAddr)
      resolveAddress(ctx, listenAddr, $port, address)

      result = newEndpoint(ctx, address, proto)
      if result == nil:
        var protoText: string
        if proto == COAP_PROTO_UDP: protoText = "NoSec" else: protoText = "Secure"
        raise newException(ConetError, format("Can't create $# server listener on $#",
                           protoText, $port))

proc updateConfig(state: ConetState, config: ServerConfig,
                  newConfig: ServerConfig) =
  ## Starts/Stops local server endpoints based on newConfig.
  ## Updates the xxxEnable vars to reflect the actual state of the endpoint.
  ## So if NoSec is enabled, then config.nosecEnable is set true.

  if state.endpoints[0] == nil and state.endpoints[1] == nil:
    # Same listen address used by both protocols, so must not currently be
    # listening to change it.
    config.listenAddr = newConfig.listenAddr

  # update for NoSec
  if state.endpoints[0] == nil:
    # can only start/change NoSec if not running
    config.nosecPort = newConfig.nosecPort
    if newConfig.nosecEnable:
      let ep = createEndpoint(state.ctx, config.listenAddr, config.nosecPort,
                              COAP_PROTO_UDP)
      state.endpoints[0] = ep
      config.nosecEnable = true
      oplog.log(lvlInfo, "Cotel server NoSec enabled on " & $config.nosecPort)

  elif not newConfig.nosecEnable:
    # disable NoSec
    freeEndpoint(state.endpoints[0])
    state.endpoints[0] = nil
    config.nosecEnable = false
    oplog.log(lvlInfo, "Cotel server NoSec disabled")

  # update for Secure
  if state.endpoints[1] == nil:
    config.secPort = newConfig.secPort
    if not setContextPsk(state.ctx, "", cast[ptr uint8](addr newConfig.pskKey[0]),
                         newConfig.pskKey.len.csize_t).bool:
      raise newException(ConetError, "Can't set context PSK")
    config.pskKey = newConfig.pskKey

    if newConfig.secEnable:
      let ep = createEndpoint(state.ctx, config.listenAddr, config.secPort,
                              COAP_PROTO_DTLS)
      state.endpoints[1] = ep
      config.secEnable = true
      oplog.log(lvlInfo, "Cotel server Secure enabled on " & $config.secPort)

  elif not newConfig.secEnable:
    # disable Secure
    freeEndpoint(state.endpoints[1])
    state.endpoints[1] = nil
    config.secEnable = false
    oplog.log(lvlInfo, "Cotel server Secure disabled")


proc netLoop*(config: ServerConfig) =
  ## Entry point for Conet. Setup server and run event loop. In particular,
  ## establishes libcoap Context and server resources.
  oplog = newFileLogger("net.log", fmtStr="[$time] $levelname: ", bufSize=0)
  let state = ConetState(endpoints: newSeq[CEndpoint](2))

  open(netChan)
  open(ctxChan)
  setLogLevel(LOG_DEBUG)
  setLogHandler(handleCoapLog)
  setDtlsLogLevel(LOG_DEBUG)

  # init context, listen port/endpoint
  state.ctx = newContext(nil)

  # Establish server resources and request handlers, and also the client
  # response handler.
  try:
    var r = initResource(makeStringConst("hi"), 0)
    registerHandler(r, COAP_REQUEST_GET, handleHi)
    addResource(state.ctx, r)

    etsi_plug.initResources(state.ctx)

    registerResponseHandler(state.ctx, handleResponse)
  except CatchableError as e:
    oplog.log(lvlError, e.msg)
    quit(QuitFailure)

  # Serve resources until quit
  while true:
    discard processIo(state.ctx, 500'u32)

    var msgTuple = ctxChan.tryRecv()
    if msgTuple.dataAvailable:
      case msgTuple.msg.subject
      of "send_msg":
        try:
          send_message(state.ctx, config, msgTuple.msg.payload)
        except CatchableError as e:
          oplog.log(lvlError, e.msg)
          netChan.send( CoMsg(subject: "send_msg.error", payload: e.msg) )
      of "config.server.GET":
        netChan.send( CoMsg(subject: "config.server.RESP",
                            token: msgTuple.msg.token, payload: $toJson(config)) )
      of "config.server.PUT":
        try:
          updateConfig(state, config,
                       jsonTo(parseJson(msgTuple.msg.payload), ServerConfig))
          netChan.send( CoMsg(subject: "config.server.RESP",
                              token: msgTuple.msg.token, payload: $toJson(config)) )
        except CatchableError as e:
          oplog.log(lvlError, e.msg)
          netChan.send( CoMsg(subject: "config.server.ERR", payload: e.msg) )
      of "quit":
        break
      else:
        oplog.log(lvlError, "msg not understood: " & msgTuple.msg.subject)

  if state.ctx != nil:
    freeContext(state.ctx)
  oplog.log(lvlInfo, "Exiting net gracefully")
