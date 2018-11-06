package mx.data
{
   import mx.rpc.AsyncRequest;
   
   public class MessagingDataServiceAdapter extends DataServiceAdapter
   {
       
      
      private var _dataStore:DataStore;
      
      private var _producer:AsyncRequest;
      
      public function MessagingDataServiceAdapter(rootDestination:String, dataStore:DataStore)
      {
         super();
         this._dataStore = dataStore;
         this._producer = new DataServiceAsyncRequest();
         this._producer.destination = rootDestination;
         this._producer.id = "ds-producer-" + rootDestination;
      }
      
      override public function get asyncRequest() : AsyncRequest
      {
         return this._producer;
      }
      
      override public function get connected() : Boolean
      {
         return this._producer.connected;
      }
      
      override function getConcreteDataService(destination:String) : ConcreteDataService
      {
         return ConcreteDataService.getService(destination);
      }
      
      override public function getDataManager(destination:String) : DataManager
      {
         var cds:ConcreteDataService = ConcreteDataService.getService(destination);
         return new DataService(cds.destination);
      }
   }
}

import mx.collections.ItemResponder;
import mx.messaging.events.MessageFaultEvent;
import mx.messaging.messages.CommandMessage;
import mx.rpc.AsyncRequest;

class DataServiceAsyncRequest extends AsyncRequest
{
    
   
   function DataServiceAsyncRequest()
   {
      super();
   }
   
   private function dummy(arg:*, arg2:*) : void
   {
   }
   
   private function faultHandler(messageFaultEvent:MessageFaultEvent, arg2:*) : void
   {
      dispatchEvent(messageFaultEvent);
   }
   
   override public function connect() : void
   {
      _disconnectBarrier = false;
      if(!connected)
      {
         _shouldBeConnected = true;
         invoke(this.buildConnectMessage(),new ItemResponder(this.dummy,this.faultHandler,null));
      }
   }
   
   private function buildConnectMessage() : CommandMessage
   {
      var msg:CommandMessage = new CommandMessage();
      msg.operation = CommandMessage.TRIGGER_CONNECT_OPERATION;
      msg.clientId = clientId;
      msg.destination = destination;
      return msg;
   }
}
