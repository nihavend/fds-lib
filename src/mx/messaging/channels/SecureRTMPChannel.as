package mx.messaging.channels
{
   import flash.events.TimerEvent;
   import flash.net.NetConnection;
   import mx.messaging.FlexClient;
   import mx.messaging.config.ServerConfig;
   
   public class SecureRTMPChannel extends RTMPChannel
   {
       
      
      public function SecureRTMPChannel(id:String = null, uri:String = null)
      {
         super(id,uri);
      }
      
      override public function get protocol() : String
      {
         return "rtmps";
      }
      
      override protected function attemptConcurrentConnect() : void
      {
         _concurrentConnectTimer.delay = 15000;
         _concurrentConnectTimer.start();
      }
      
      override protected function concurrentConnectHandler(event:TimerEvent) : void
      {
         _concurrentConnectTimer.stop();
         var nc:NetConnection = buildTempNC();
         nc.proxyType = "http";
         _tempNCs.push(nc);
         var id:String = FlexClient.getInstance().id;
         if(id == null)
         {
            id = FlexClient.NULL_FLEXCLIENT_ID;
         }
         if(credentials != null)
         {
            nc.connect(endpoint,ServerConfig.needsConfig(this),id,credentials,buildHandshakeMessage());
         }
         else
         {
            nc.connect(endpoint,ServerConfig.needsConfig(this),id,"",buildHandshakeMessage());
         }
      }
   }
}
