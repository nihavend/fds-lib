package mx.messaging.channels
{
   import flash.events.IOErrorEvent;
   import flash.events.NetStatusEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.TimerEvent;
   import flash.net.NetConnection;
   import flash.net.ObjectEncoding;
   import flash.utils.Timer;
   import mx.logging.Log;
   import mx.messaging.FlexClient;
   import mx.messaging.config.ServerConfig;
   import mx.messaging.events.ChannelFaultEvent;
   import mx.messaging.messages.AbstractMessage;
   import mx.messaging.messages.CommandMessage;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   import mx.utils.URLUtil;
   
   public class RTMPChannel extends NetConnectionChannel
   {
      
      protected static const RTMP_SESSION_ID_HEADER:String = "DSrtmpId";
      
      protected static const CODE_CONNECT_CLOSED:String = "Connect.Closed";
      
      protected static const CODE_CONNECT_FAILED:String = "Connect.Failed";
      
      protected static const CODE_CONNECT_NETWORKCHANGE:String = "Connect.NetworkChange";
      
      protected static const CODE_CONNECT_SUCCESS:String = "Connect.Success";
      
      protected static const CODE_CONNECT_REJECTED:String = "Connect.Rejected";
       
      
      protected var _concurrentConnectTimer:Timer;
      
      protected var _sessionId:String;
      
      protected var _tempNCs:Array;
      
      public function RTMPChannel(id:String = null, uri:String = null)
      {
         this._concurrentConnectTimer = new Timer(2000,1);
         this._tempNCs = [];
         super(id,uri);
         this._concurrentConnectTimer.addEventListener(TimerEvent.TIMER,this.concurrentConnectHandler);
      }
      
      override public function get protocol() : String
      {
         var proto:String = URLUtil.getProtocol(uri);
         if(proto == "rtmpt")
         {
            return "rtmpt";
         }
         return "rtmp";
      }
      
      override function get realtime() : Boolean
      {
         return true;
      }
      
      override protected function connectTimeoutHandler(event:TimerEvent) : void
      {
         this.shutdownTempNCs();
         shutdownNetConnection();
         super.connectTimeoutHandler(event);
      }
      
      override public function disablePolling() : void
      {
      }
      
      override public function enablePolling() : void
      {
      }
      
      override public function poll() : void
      {
      }
      
      override protected function internalConnect() : void
      {
         var nc:NetConnection = this.buildTempNC();
         this._tempNCs.push(nc);
         var id:String = FlexClient.getInstance().id;
         if(id == null)
         {
            id = FlexClient.NULL_FLEXCLIENT_ID;
         }
         this.attemptConcurrentConnect();
         if(credentials != null)
         {
            nc.connect(endpoint,ServerConfig.needsConfig(this),id,credentials,this.buildHandshakeMessage());
         }
         else
         {
            nc.connect(endpoint,ServerConfig.needsConfig(this),id,"",this.buildHandshakeMessage());
         }
      }
      
      override protected function internalDisconnect(rejected:Boolean = false) : void
      {
         this.shutdownTempNCs();
         super.internalDisconnect(rejected);
      }
      
      override protected function statusHandler(event:NetStatusEvent) : void
      {
         var channelFault:ChannelFaultEvent = null;
         var level:String = null;
         var code:String = null;
         if(Log.isDebug())
         {
            _log.debug("\'{0}\' channel got runtime status. {1}",id,ObjectUtil.toString(event.info));
         }
         var info:Object = event.info;
         try
         {
            level = info.level;
            code = info.code;
         }
         catch(error:Error)
         {
            return;
         }
         if(code.indexOf(CODE_CONNECT_CLOSED) > -1)
         {
            if(info.description != null && (info.description.indexOf("Timed Out") != -1 || info.description.indexOf("Force Close") != -1))
            {
               this.internalDisconnect(true);
            }
            else
            {
               this.internalDisconnect();
            }
            return;
         }
         if(code.indexOf(CODE_CONNECT_NETWORKCHANGE) > -1)
         {
            return;
         }
         if(Log.isWarn())
         {
            _log.warn("\'{0}\' channel connection failed. {1}",id,ObjectUtil.toString(event.info));
         }
         channelFault = ChannelFaultEvent.createEvent(this,false,"Channel.Connect.Failed",info.level,info.description + " url:\'" + endpoint + "\'");
         channelFault.rootCause = info;
         shutdownNetConnection();
         connectFailed(channelFault);
      }
      
      override protected function timerRequired() : Boolean
      {
         return false;
      }
      
      protected function attemptConcurrentConnect() : void
      {
         var proto:String = URLUtil.getProtocol(uri);
         if(proto == "rtmpt")
         {
            return;
         }
         this._concurrentConnectTimer.start();
      }
      
      protected function buildHandshakeMessage() : CommandMessage
      {
         var message:CommandMessage = new CommandMessage();
         message.headers[CommandMessage.MESSAGING_VERSION] = messagingVersion;
         if(ServerConfig.needsConfig(this))
         {
            message.headers[CommandMessage.NEEDS_CONFIG_HEADER] = true;
         }
         message.headers[AbstractMessage.FLEX_CLIENT_ID_HEADER] = id;
         if(this._sessionId != null)
         {
            message.headers[RTMP_SESSION_ID_HEADER] = this._sessionId;
         }
         if(credentials != null)
         {
            message.operation = CommandMessage.LOGIN_OPERATION;
            message.body = credentials;
         }
         else
         {
            message.operation = CommandMessage.CLIENT_PING_OPERATION;
         }
         return message;
      }
      
      protected function buildTempNC() : NetConnection
      {
         var nc:NetConnection = new NetConnection();
         nc.objectEncoding = netConnection != null?uint(netConnection.objectEncoding):uint(ObjectEncoding.AMF3);
         nc.client = this;
         nc.proxyType = "best";
         nc.addEventListener(NetStatusEvent.NET_STATUS,this.tempStatusHandler);
         nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.tempSecurityErrorHandler);
         nc.addEventListener(IOErrorEvent.IO_ERROR,this.tempIOErrorHandler);
         return nc;
      }
      
      protected function concurrentConnectHandler(event:TimerEvent) : void
      {
         this._concurrentConnectTimer.stop();
         var nc:NetConnection = this.buildTempNC();
         nc.proxyType = "http";
         this._tempNCs.push(nc);
         var tunneledEndpoint:String = endpoint.replace("rtmp:","rtmpt:");
         var id:String = FlexClient.getInstance().id;
         if(id == null)
         {
            id = FlexClient.NULL_FLEXCLIENT_ID;
         }
         if(credentials != null)
         {
            nc.connect(tunneledEndpoint,ServerConfig.needsConfig(this),id,credentials,this.buildHandshakeMessage());
         }
         else
         {
            nc.connect(tunneledEndpoint,ServerConfig.needsConfig(this),id,"",this.buildHandshakeMessage());
         }
      }
      
      protected function isLastTempNC() : Boolean
      {
         return this._tempNCs.length == 0 && !this._concurrentConnectTimer.running?Boolean(true):Boolean(false);
      }
      
      protected function setUpMainNC(nc:NetConnection) : void
      {
         this.shutdownTempNCs(nc);
         nc.removeEventListener(NetStatusEvent.NET_STATUS,this.tempStatusHandler);
         nc.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.tempSecurityErrorHandler);
         nc.removeEventListener(IOErrorEvent.IO_ERROR,this.tempIOErrorHandler);
         nc.addEventListener(NetStatusEvent.NET_STATUS,this.statusHandler);
         nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR,securityErrorHandler);
         nc.addEventListener(IOErrorEvent.IO_ERROR,ioErrorHandler);
         _nc = nc;
         connectSuccess();
         setAuthenticated(credentials != null);
      }
      
      protected function shutdownTempNC(nc:NetConnection) : void
      {
         nc.close();
         var i:int = ArrayUtil.getItemIndex(nc,this._tempNCs);
         if(i != -1)
         {
            this._tempNCs.splice(i,1);
         }
      }
      
      protected function shutdownTempNCs(nc:NetConnection = null) : void
      {
         var connection:NetConnection = null;
         if(this._concurrentConnectTimer.running)
         {
            this._concurrentConnectTimer.stop();
         }
         while(this._tempNCs.length)
         {
            connection = this._tempNCs.pop() as NetConnection;
            if(connection != nc)
            {
               this.shutdownTempNC(connection);
            }
         }
      }
      
      protected function tempIOErrorHandler(event:IOErrorEvent) : void
      {
         var nc:NetConnection = event.target as NetConnection;
         if(!this.shouldHandleEvent(nc))
         {
            return;
         }
         if(Log.isDebug())
         {
            _log.debug("\'{0}\' channel got IOError from temporary NetConnection connect attempt. {1}",id,ObjectUtil.toString(event));
         }
         this.shutdownTempNC(nc);
         if(this.isLastTempNC())
         {
            ioErrorHandler(event);
         }
      }
      
      protected function tempSecurityErrorHandler(event:SecurityErrorEvent) : void
      {
         var nc:NetConnection = event.target as NetConnection;
         if(!this.shouldHandleEvent(nc))
         {
            return;
         }
         if(Log.isDebug())
         {
            _log.debug("\'{0}\' channel got SecurityError from temporary NetConnection connect attempt. {1}",id,ObjectUtil.toString(event));
         }
         this.shutdownTempNC(nc);
         if(this.isLastTempNC())
         {
            securityErrorHandler(event);
         }
      }
      
      protected function tempStatusHandler(event:NetStatusEvent) : void
      {
         var channelFault:ChannelFaultEvent = null;
         var level:String = null;
         var code:String = null;
         var serverVersion:Number = NaN;
         var nc:NetConnection = event.target as NetConnection;
         if(!this.shouldHandleEvent(nc))
         {
            return;
         }
         if(Log.isDebug())
         {
            _log.debug("\'{0}\' channel got connect attempt status. {1}",id,ObjectUtil.toString(event.info));
         }
         var info:Object = event.info;
         try
         {
            level = info.level;
            code = info.code;
         }
         catch(error:Error)
         {
            return;
         }
         if(code.indexOf(CODE_CONNECT_SUCCESS) > -1)
         {
            this._sessionId = info[RTMP_SESSION_ID_HEADER];
            ServerConfig.updateServerConfigData(info.serverConfig,endpoint);
            if(FlexClient.getInstance().id == null)
            {
               FlexClient.getInstance().id = info.id;
            }
            if(info[CommandMessage.MESSAGING_VERSION] != null)
            {
               serverVersion = info[CommandMessage.MESSAGING_VERSION] as Number;
               handleServerMessagingVersion(serverVersion);
            }
            this.setUpMainNC(nc);
            return;
         }
         if(code.indexOf(CODE_CONNECT_FAILED) > -1)
         {
            channelFault = ChannelFaultEvent.createEvent(this,false,"Channel.Connect.Failed",info.level,info.description + " url:\'" + endpoint + "\'");
            channelFault.rootCause = info;
         }
         else
         {
            if(code.indexOf(CODE_CONNECT_REJECTED) > -1)
            {
               this.shutdownTempNCs();
               channelFault = ChannelFaultEvent.createEvent(this,false,"Channel.Connect.Failed","Connection rejected: \'" + endpoint + "\'",info.description + " url:\'" + endpoint + "\'",true);
               channelFault.rootCause = info;
               connectFailed(channelFault);
               return;
            }
            if(code.indexOf("SSLNotAvailable") > -1 || code.indexOf("SSLHandshakeFailed") > -1 || code.indexOf("CertificateExpired") > -1 || code.indexOf("CertificatePrincipalMismatch") > -1 || code.indexOf("CertificateUntrustedSigner") > -1 || code.indexOf("CertificateRevoked") > -1 || code.indexOf("CertificateInvalid") > -1 || code.indexOf("ClientCertificateInvalid") > -1 || code.indexOf("SSLCipherFailure") > -1 || code.indexOf("CertificateAPIError") > -1)
            {
               this._concurrentConnectTimer.stop();
               return;
            }
            channelFault = ChannelFaultEvent.createEvent(this,false,"Channel.Connect.Failed","error","Failed on url: \'" + endpoint + "\'");
            channelFault.rootCause = info;
         }
         this.shutdownTempNC(nc);
         if(this.isLastTempNC())
         {
            connectFailed(channelFault);
         }
      }
      
      protected function shouldHandleEvent(nc:NetConnection) : Boolean
      {
         return ArrayUtil.getItemIndex(nc,this._tempNCs) != -1?Boolean(true):Boolean(false);
      }
   }
}
