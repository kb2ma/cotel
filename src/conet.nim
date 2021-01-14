## Conet provides CoAP networking via the [libcoap module](libcoap.html).
## An application runs Conet in a thread and communicates via the async
## channels in the [conet_ctx module](conet_ctx.html).
##
## Start Conet with a call to [netLoop()](conet.html#netLoop%2CConetConfig),
## which monitors network sockets as well as the channels to the enclosing
## application. Conet provides two services:
##
## * send requests to other servers, either with the secure coaps protocol or
##   with the insecure coap protocol
## * receive requests from one or two endpoints, for NoSec and/or PSK security
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
import json, logging, parseutils, strformat, strutils, std/jsonutils, tables
import comsg, conet_ctx, etsi_plug
# Provides the core context data for conet module users to share
export comsg, conet_ctx, COAP_OPTION_ACCEPT, COAP_OPTION_BLOCK1, COAP_OPTION_BLOCK2,
  COAP_OPTION_CONTENT_FORMAT, COAP_OPTION_ETAG, COAP_OPTION_IF_MATCH,
  COAP_OPTION_IF_NONE_MATCH, COAP_OPTION_LOCATION_PATH, COAP_OPTION_LOCATION_QUERY,
  COAP_OPTION_MAXAGE, COAP_OPTION_NORESPONSE, COAP_OPTION_OBSERVE,
  COAP_OPTION_PROXY_SCHEME, COAP_OPTION_PROXY_URI, COAP_OPTION_URI_HOST,
  COAP_OPTION_URI_PATH, COAP_OPTION_URI_PORT, COAP_OPTION_URI_QUERY,
  COAP_OPTION_SIZE1, COAP_OPTION_SIZE2

type
  ConetConfig* = ref object
    # Configuration data required to operate Conet networking
    logDir*: string
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
      ## by convention, two endpoints: [0] is nosec, [1] is secure

  ConetError* = object of CatchableError
    ## Networking error recognized by conet

  ValueBuffer = array[8, char]
    ## Holds arbitrary values for encoding/decoding with libcoap

  NamedId* = tuple
    ## Generic match for an ID to a name. Used for content format.
    id: int
    name: string


proc toJsonHook*(ctx: MessageOptionContext): JsonNode =
  ## Required do-nothing function to marshall MessageOption context attribute.
  ## The conet module itself does not define an option context, so does not
  ## need to export it.
  return newJNull()

proc fromJsonHook*(a: var MessageOptionContext, b: JsonNode) =
  ## Required do-nothing function to unmarshall MessageOption context. The
  ## conet module does not use a provided option context, so does not need to
  ## read it.
  a = nil

proc handleResponse(context: CContext, session: CSession, sent: CPdu,
                    received: CPdu, id: CTxid)
                    {.exportc: "hnd_response", noconv.} =
  ## Client response handler. Logs an error for an unexpected exception.
  let codeStr = "$#.$#\n" % [fmt"{received.code shr 5}",
                             fmt"{received.code and 0x1F:>02}"]
  var
    options: seq[MessageOption]
    dataStr = ""

  try:
    options = readOptions(received)
    # read payload
    var dataLen: csize_t
    var dataPtr: ptr uint8
    discard getData(received, addr dataLen, addr dataPtr)
    if dataLen > 0:
      dataStr = newString(dataLen)
      copyMem(addr dataStr[0], dataPtr, dataLen)
      #echo("dataStr " & dataStr)
  except:
    oplog.log(lvlError, "Error reading response: " & getCurrentExceptionMsg())
    return

  let remote = getAddrString(addr session.addr_info.remote.`addr`.sa)
  var tokenSeq = newSeq[uint8](received.token_length)
  copyMem(tokenSeq[0].addr, received.token, received.token_length)
  var tokenHex: string
  for c in tokenSeq:
    tokenHex.add(toHex(cast[int](c), 2))
    tokenHex.add(' ')
  oplog.log(lvlInfo, format("Got response from $#, ID $#, token $#", remote, id,
                            tokenHex))

  var jNode = %* { "code": codeStr, "options": toJson(options),
                   "payload": dataStr }
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

proc doPctDecode(src: string): string =
  ## Returns a string derived from the input with any percent encodings, like
  ## "%D6" replaced with the decoded character. Simply returns the input string
  ## if an encoding is not found.
  ## Raises a ValueError if an encoding is not valid.
  if src.find('%') == -1:
    return src
  var pos = 0
  while pos < len(src):
    if src[pos] == '%':
      if len(src) < (pos + 1):
        raise newException(ValueError, "Invalid percent encoding in " & src)
      result.add(cast[char](fromHex[int8](src.substr(pos+1, pos+2))))
      pos += 3
    else:
      result.add(src[pos])
      pos += 1

proc sendMessage(ctx: CContext, config: ConetConfig, jsonStr: string) =
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

  let msgId = newMessageId(session)
  var pdu = initPdu(msgType, reqJson["method"].getInt().uint8, msgId,
                    maxSessionPduSize(session))
  if pdu == nil:
    releaseSession(session)
    raise newException(ConetError, "Can't create client PDU")

  # add token; must add before options or payload
  let token = reqJson["token"].getStr()
  if len(token) > 0:
    discard addToken(pdu, len(token).csize_t, token)
  
  # add options
  let uriPath = reqJson["uriPath"].getStr()
  var pos = 0
  var chain: COptlist

  # Uri-Path from path string
  while pos < uriPath.len:
    var segment: string
    let plen = parseUntil(uriPath, segment, '/', pos)
    segment = doPctDecode(segment)
    #echo("start pos: ", pos, ", segment: ", segment, " of len ", plen)
    if plen > 0:
      let optlist = newOptlist(COAP_OPTION_URI_PATH.uint16,
                               len(segment).csize_t,
                               cast[ptr uint8](segment.cstring))
      if optlist == nil:
        raise newException(ConetError, "Can't create option list")
      if not insertOptlist(addr chain, optlist).bool:
        raise newException(ConetError, "Can't add to option chain")
    pos = pos + plen + 1
    
  # other options
  for optJson in reqJson["reqOptions"]:
    let option = jsonTo(optJson, MessageOption)
    let optType = optionTypesTable[option.optNum]
    var
      buf: ValueBuffer
      optlist: COptlist
      
    case optType.dataType
    of TYPE_UINT:
      let valLen = encodeVarSafe(cast[ptr uint8](buf.addr), len(buf).csize_t,
                                 option.valueInt)
      optlist = newOptlist(option.optNum.uint16, valLen, cast[ptr uint8](buf.addr))
    of TYPE_OPAQUE:
      if len(option.valueChars) == 0:
        optlist = newOptlist(option.optNum.uint16, 0.csize_t, nil)
      else:
        optlist = newOptlist(option.optNum.uint16, len(option.valueChars).csize_t,
                             cast[ptr uint8](option.valueChars[0].addr))
    of TYPE_STRING:
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
  else:
    let methodEnum = $reqJson["method"].getInt().CRequestCode
    var tokenHex: string
    for c in token:
      tokenHex.add(toHex(cast[int](c), 2))
      tokenHex.add(' ')
    oplog.log(lvlInfo, format("Sent $# $# to $#, ID $#, token $#",
              methodEnum.split('_')[2], uriPath, host, $msgId,
              if len(tokenHex) == 0: "<none>" else: tokenHex))

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

proc updateConfig(state: ConetState, config: ConetConfig,
                  newConfig: ConetConfig) =
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
    # Must first assign new key to 'config' in order to generate a stable
    # address to it for libcoap.
    config.pskKey = newConfig.pskKey
    if not setContextPsk(state.ctx, "", cast[ptr uint8](addr config.pskKey[0]),
                         config.pskKey.len.csize_t).bool:
      # Can't enable; will propagate back to calling context
      newConfig.secEnable = false
      raise newException(ConetError, "Can't set context PSK")

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


proc netLoop*(config: ConetConfig) =
  ## Entry point for Conet. Setup server and run event loop. In particular,
  ## establishes libcoap Context and server resources.
  oplog = newFileLogger(config.logDir & "net.log", fmtStr="[$time] $levelname: ",
                        bufSize=0)
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
                       jsonTo(parseJson(msgTuple.msg.payload), ConetConfig))
          netChan.send( CoMsg(subject: "config.server.RESP",
                              token: msgTuple.msg.token, payload: $toJson(config)) )
        except CatchableError as e:
          oplog.log(lvlError, e.msg)
          # Return config, which likely was partially updated, so context can
          # update for it.
          netChan.send( CoMsg(subject: "config.server.ERR",
                        token: msgTuple.msg.token, payload: $toJson(config)) )
      of "quit":
        break
      else:
        oplog.log(lvlError, "msg not understood: " & msgTuple.msg.subject)

  if state.ctx != nil:
    freeContext(state.ctx)
  oplog.log(lvlInfo, "Exiting net gracefully")
