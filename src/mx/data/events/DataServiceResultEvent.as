package mx.data.events
{
   import mx.messaging.messages.IMessage;
   import mx.rpc.AsyncToken;
   import mx.rpc.events.ResultEvent;
   
   public class DataServiceResultEvent extends ResultEvent
   {
      
      public static const RESULT:String = ResultEvent.RESULT;
       
      
      public var cacheResponse:Boolean;
      
      public function DataServiceResultEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = true, result:Object = null, token:AsyncToken = null, message:IMessage = null, cacheResponse:Boolean = false)
      {
         super(type,bubbles,cancelable,result,token,message);
         this.cacheResponse = cacheResponse;
      }
      
      public static function createEvent(result:Object, token:AsyncToken, message:IMessage, cacheResponse:Boolean = false) : DataServiceResultEvent
      {
         return new DataServiceResultEvent(DataServiceResultEvent.RESULT,false,true,result,token,message,cacheResponse);
      }
   }
}
