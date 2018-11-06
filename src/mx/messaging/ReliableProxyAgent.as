package mx.messaging
{
   import mx.logging.Log;
   import mx.messaging.messages.AcknowledgeMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   
   public class ReliableProxyAgent extends MessageAgent
   {
       
      
      private var _agent:MessageAgent;
      
      public function ReliableProxyAgent(agent:MessageAgent)
      {
         super();
         _log = Log.getLogger("mx.messaging.ReliableProxyAgent");
         _agentType = "reliable-proxy";
         this._agent = agent;
         destination = this._agent.destination;
      }
      
      public function get targetAgent() : MessageAgent
      {
         return this._agent;
      }
      
      override public function acknowledge(ackMsg:AcknowledgeMessage, msg:IMessage) : void
      {
         AdvancedChannelSet(channelSet).processReliableReply(ackMsg,msg,this);
      }
      
      override public function fault(errMsg:ErrorMessage, msg:IMessage) : void
      {
         AdvancedChannelSet(channelSet).processReliableReply(errMsg,msg,this);
      }
      
      public function proxyAcknowledge(ackMsg:AcknowledgeMessage, msg:IMessage) : void
      {
         super.acknowledge(ackMsg,msg);
         this._agent.acknowledge(ackMsg,msg);
      }
      
      public function proxyFault(errMsg:ErrorMessage, msg:IMessage) : void
      {
         super.fault(errMsg,msg);
         this._agent.fault(errMsg,msg);
      }
   }
}
