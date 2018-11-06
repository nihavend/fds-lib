package mx.data
{
   import mx.collections.errors.ItemPendingError;
   import mx.core.mx_internal;
   import mx.data.messages.DataMessage;
   import mx.data.messages.PagedMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.rpc.IResponder;
   import mx.utils.ArrayUtil;
   
   [ExcludeClass]
   public class PageRequest
   {
      
      private static const dependency:PagedMessage = null;
       
      
      private var _pageIndex:int;
      
      private var _pageSize:int;
      
      private var _pendingErrors:Array;
      
      private var _idList:Array = null;
      
      private var _propList:Array = null;
      
      public var sync:Boolean;
      
      public var released:Boolean = false;
      
      public var messageSent:Boolean = false;
      
      public function PageRequest(sync:Boolean, index:int, pageSize:int, idList:Array, propList:Array = null)
      {
         this._pendingErrors = [];
         super();
         this.sync = sync;
         this._pageSize = pageSize;
         this._pageIndex = Math.floor(index / this._pageSize);
         this._idList = idList;
         this._propList = propList;
      }
      
      public function get lowerBound() : int
      {
         return this._pageIndex * this._pageSize;
      }
      
      public function get upperBound() : int
      {
         return this.lowerBound + this._pageSize;
      }
      
      public function get idList() : Array
      {
         return this._idList;
      }
      
      public function get propList() : Array
      {
         return this._propList;
      }
      
      public function addPendingError(error:ItemPendingError) : void
      {
         this._pendingErrors.push(error);
      }
      
      public function createDataMessage() : DataMessage
      {
         var result:DataMessage = new DataMessage();
         if(this._idList == null)
         {
            result.operation = DataMessage.PAGE_OPERATION;
            result.headers.pageIndex = this._pageIndex;
            result.headers.pageSize = this._pageSize;
         }
         else
         {
            result.operation = DataMessage.PAGE_ITEMS_OPERATION;
            result.headers.DSids = this._idList;
            if(this._propList != null)
            {
               result.headers.DSincludeSpec = this._propList.join(",");
            }
         }
         return result;
      }
      
      public function sendResponderNotification(message:IMessage) : void
      {
         var responder:IResponder = null;
         var responders:Array = null;
         var i:uint = 0;
         while(this._pendingErrors.length)
         {
            responders = ItemPendingError(this._pendingErrors.pop()).responders;
            if(responders)
            {
               for(i = 0; i < responders.length; i++)
               {
                  responder = responders[i];
                  if(responder)
                  {
                     if(message is ErrorMessage)
                     {
                        responder.fault(message);
                     }
                     else
                     {
                        responder.result(message);
                     }
                  }
               }
               continue;
            }
         }
      }
      
      public function includesPageRequest(other:PageRequest) : Boolean
      {
         var i:int = 0;
         if(other.sync != this.sync)
         {
            return false;
         }
         if(this._idList != null)
         {
            if(other._idList == null)
            {
               return false;
            }
            for(i = 0; i < other._idList.length; i++)
            {
               if(DataList.mx_internal::objectGetItemIndex(other._idList[i],this._idList) == -1)
               {
                  return false;
               }
            }
            if(other._propList == null && this._propList == null)
            {
               return true;
            }
            if(other._propList == null || this._propList == null)
            {
               return false;
            }
            for(i = 0; i < other._propList.length; i++)
            {
               if(ArrayUtil.getItemIndex(other._propList[i],this._propList) == -1)
               {
                  if(this.messageSent)
                  {
                     return false;
                  }
                  this._propList = this._propList.concat(other._propList[i]);
               }
            }
            return true;
         }
         if(other._idList != null)
         {
            return false;
         }
         return this.upperBound >= other.upperBound && this.lowerBound <= other.lowerBound;
      }
   }
}
