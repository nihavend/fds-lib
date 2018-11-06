package mx.data
{
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IEventDispatcher;
   import mx.core.mx_internal;
   import mx.data.events.DataServiceFaultEvent;
   import mx.data.events.DataServiceResultEvent;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.ErrorMessage;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.events.FaultEvent;
   
   public class DataStoreEventDispatcher implements IEventDispatcher
   {
       
      
      private var _source:EventDispatcher;
      
      public function DataStoreEventDispatcher(source:EventDispatcher)
      {
         super();
         this._source = source;
      }
      
      public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false) : void
      {
         this._source.addEventListener(type,listener,useCapture,priority,useWeakReference);
      }
      
      public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false) : void
      {
         this._source.removeEventListener(type,listener,useCapture);
      }
      
      public function dispatchEvent(event:Event) : Boolean
      {
         return this._source.dispatchEvent(event);
      }
      
      public function hasEventListener(type:String) : Boolean
      {
         return this._source.hasEventListener(type);
      }
      
      public function willTrigger(type:String) : Boolean
      {
         return this._source.willTrigger(type);
      }
      
      public function dispatchCacheFaultEvent(dispatcher:IEventDispatcher, event:MessageFaultEvent, token:AsyncToken, cacheResponse:Boolean = false) : void
      {
         var fault:Fault = new Fault(event.faultCode,event.faultString,event.faultDetail);
         fault.rootCause = event.rootCause;
         if(dispatcher == null)
         {
            dispatcher = this._source;
         }
         var handled:Boolean = false;
         var fltEvent:DataServiceFaultEvent = new DataServiceFaultEvent(FaultEvent.FAULT,false,true,fault,token,event.message,cacheResponse);
         if(token != null && token.hasResponder())
         {
            fltEvent.mx_internal::callTokenResponders();
            handled = true;
         }
         if(dispatcher.hasEventListener(FaultEvent.FAULT))
         {
            dispatcher.dispatchEvent(fltEvent);
            if(dispatcher != this._source && this._source.hasEventListener(FaultEvent.FAULT))
            {
               this._source.dispatchEvent(fltEvent);
            }
            handled = true;
         }
         if(!handled)
         {
            throw fault;
         }
      }
      
      public function dispatchFileAccessFault(e:Error, dispatcher:IEventDispatcher, token:AsyncToken, cacheResponse:Boolean = false) : void
      {
         var msg:ErrorMessage = new ErrorMessage();
         msg.faultCode = "Client.FileAccess.Failed";
         msg.faultDetail = e.message;
         msg.faultString = e.name;
         if(token != null && "setMessage" in token)
         {
            token.setMessage(msg);
         }
         var fault:MessageFaultEvent = MessageFaultEvent.createEvent(msg);
         this.dispatchCacheFaultEvent(dispatcher,fault,token,cacheResponse);
      }
      
      public function dispatchResultEvent(dispatcher:IEventDispatcher, event:MessageEvent, token:AsyncToken, result:Object, cacheResponse:Boolean = false) : void
      {
         var resultEvent:DataServiceResultEvent = DataServiceResultEvent.createEvent(result,token,event.message,cacheResponse);
         resultEvent.mx_internal::callTokenResponders();
         if(dispatcher == null)
         {
            dispatcher = this._source;
         }
         if(dispatcher.hasEventListener(DataServiceResultEvent.RESULT))
         {
            dispatcher.dispatchEvent(resultEvent);
            if(dispatcher != this._source && this._source.hasEventListener(DataServiceResultEvent.RESULT))
            {
               this._source.dispatchEvent(resultEvent);
            }
         }
      }
      
      function doCacheFault(dispatcher:IEventDispatcher, e:Error, faultCode:String, faultString:String, token:AsyncToken) : void
      {
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = faultCode;
         errMsg.faultDetail = e.message;
         errMsg.faultString = faultString;
         var fltEvent:MessageFaultEvent = MessageFaultEvent.createEvent(errMsg);
         new AsyncDispatcher(this.dispatchCacheFaultEvent,[dispatcher,fltEvent,token],10);
      }
   }
}
