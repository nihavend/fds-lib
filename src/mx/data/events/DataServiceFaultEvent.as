package mx.data.events
{
   import flash.events.Event;
   import mx.messaging.messages.ErrorMessage;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.events.FaultEvent;
   
   public class DataServiceFaultEvent extends FaultEvent
   {
      
      public static const FAULT:String = FaultEvent.FAULT;
       
      
      public var item:Object;
      
      public var identity:Object;
      
      public var cacheResponse:Boolean;
      
      public function DataServiceFaultEvent(type:String, bubbles:Boolean = false, cancelable:Boolean = true, fault:Fault = null, token:AsyncToken = null, message:ErrorMessage = null, obj:Object = null, id:Object = null, cacheResponse:Boolean = false)
      {
         super(type,bubbles,cancelable,fault,token,message);
         this.identity = id;
         this.item = obj;
         this.cacheResponse = cacheResponse;
      }
      
      public static function createEvent(fault:Fault, token:AsyncToken, message:ErrorMessage, obj:Object, id:Object, cacheResponse:Boolean = false) : DataServiceFaultEvent
      {
         return new DataServiceFaultEvent(DataServiceFaultEvent.FAULT,false,true,fault,token,message,obj,id,cacheResponse);
      }
      
      override public function clone() : Event
      {
         return new DataServiceFaultEvent(type,bubbles,cancelable,fault,token,message as ErrorMessage,this.item,this.identity,this.cacheResponse);
      }
   }
}
