package mx.data
{
   import mx.messaging.ChannelSet;
   
   [Event(name="propertyChange",type="mx.events.PropertyChangeEvent")]
   [Event(name="message",type="mx.messaging.events.MessageEvent")]
   [Event(name="conflict",type="mx.data.events.DataConflictEvent")]
   [Event(name="fault",type="mx.data.events.DataServiceFaultEvent")]
   [Event(name="result",type="mx.rpc.events.ResultEvent")]
   public class DataService extends DataManager
   {
       
      
      public function DataService(destination:String)
      {
         super();
         if(destination)
         {
            _implementation = ConcreteDataService.getService(destination);
         }
      }
      
      public function get channelSet() : ChannelSet
      {
         if(_implementation != null)
         {
            return _implementation.channelSet;
         }
         return Boolean(propertyCache.channelSet)?propertyCache.channelSet:null;
      }
      
      public function set channelSet(value:ChannelSet) : void
      {
         if(_implementation != null)
         {
            _implementation.channelSet = value;
         }
         else
         {
            propertyCache.channelSet = value;
         }
      }
      
      public function get destination() : String
      {
         return _implementation.destination;
      }
      
      public function logout() : void
      {
         _implementation.logout();
      }
      
      public function setCredentials(username:String, password:String) : void
      {
         _implementation.setCredentials(username,password);
      }
      
      public function setRemoteCredentials(username:String, password:String) : void
      {
         _implementation.setRemoteCredentials(username,password);
      }
   }
}
