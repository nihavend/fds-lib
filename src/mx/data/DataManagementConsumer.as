package mx.data
{
   import mx.messaging.MultiTopicConsumer;
   import mx.messaging.messages.CommandMessage;
   import mx.messaging.messages.IMessage;
   
   public class DataManagementConsumer extends MultiTopicConsumer
   {
       
      
      public function DataManagementConsumer()
      {
         super();
      }
      
      override protected function internalSend(message:IMessage, waitForClientId:Boolean = true) : void
      {
         var connectMsg:CommandMessage = null;
         if(message.headers[CommandMessage.ADD_SUBSCRIPTIONS] != null || message.headers[CommandMessage.REMOVE_SUBSCRIPTIONS] != null)
         {
            super.internalSend(message,waitForClientId);
         }
         else
         {
            if(channelSet == null)
            {
               initChannelSet(message);
            }
            if(channelSet != null && !channelSet.connected && message is CommandMessage && CommandMessage(message).operation == CommandMessage.MULTI_SUBSCRIBE_OPERATION && (channelSet.currentChannel == null || !channelSet.currentChannel.reconnecting))
            {
               connectMsg = new CommandMessage();
               connectMsg.operation = CommandMessage.CLIENT_PING_OPERATION;
               connectMsg.clientId = clientId;
               connectMsg.destination = destination;
               connectMsg.headers[CommandMessage.ADD_SUBSCRIPTIONS] = {};
               super.internalSend(connectMsg);
            }
            if(message.headers.DSlastUnsub != null)
            {
               this.setSubscribed(false);
            }
            else if(channelSet != null && channelSet.connected)
            {
               this.setSubscribed(true);
            }
         }
      }
      
      override protected function setSubscribed(value:Boolean) : void
      {
         if(value)
         {
            stopResubscribeTimer();
         }
         super.setSubscribed(value);
      }
   }
}
