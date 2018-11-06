package mx.data
{
   import mx.data.messages.DataMessage;
   import mx.data.messages.UpdateCollectionMessage;
   
   public class MessageCacheItem
   {
       
      
      public var message:DataMessage;
      
      public var dataService:ConcreteDataService;
      
      var newIdentity:Object;
      
      private var _item:Object;
      
      private var _uid:String;
      
      public function MessageCacheItem()
      {
         super();
      }
      
      public function get item() : Object
      {
         if(this._item == null && this.dataService != null)
         {
            this._item = this.dataService.getItem(this.uid);
         }
         return this._item;
      }
      
      public function set item(value:Object) : void
      {
         this._item = value;
      }
      
      public function set uid(u:String) : void
      {
         this._uid = u;
      }
      
      public function get uid() : String
      {
         var result:String = null;
         var collId:Object = null;
         if(this._item != null)
         {
            result = IManaged(this._item).uid;
         }
         else
         {
            if(this._uid != null)
            {
               return this._uid;
            }
            if(this.dataService != null)
            {
               if(this.message.operation == DataMessage.UPDATE_COLLECTION_OPERATION)
               {
                  collId = UpdateCollectionMessage(this.message).collectionId;
                  if(collId is Array)
                  {
                     return null;
                  }
                  return this.dataService.dataStore.getDataService(collId["parent"]).getUIDFromReferencedId(collId["id"]);
               }
               result = this.dataService.metadata.getUID(this.message.identity);
            }
         }
         return result;
      }
   }
}
