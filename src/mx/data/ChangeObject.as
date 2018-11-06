package mx.data
{
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.utils.ObjectUtil;
   
   public final class ChangeObject implements IChangeObject
   {
       
      
      private var _conflict:DataErrorMessage;
      
      private var _currentItem:Object;
      
      private var _dataService:ConcreteDataService;
      
      private var _message:DataMessage;
      
      private var _newItem:Object;
      
      private var _previousItem:Object;
      
      private var _properties:Array;
      
      public function ChangeObject(message:DataMessage, current:Object, dataService:ConcreteDataService)
      {
         super();
         this._message = message;
         this._dataService = dataService;
         this._currentItem = current;
         this.init();
      }
      
      private function init() : void
      {
         var i:int = 0;
         var prop:Object = null;
         var qName:QName = null;
         if(this.isUpdate())
         {
            this._previousItem = DataMessage.unwrapItem(this.message.body[DataMessage.UPDATE_BODY_PREV]);
            this._newItem = DataMessage.unwrapItem(this.message.body[DataMessage.UPDATE_BODY_NEW]);
            this._properties = this.message.body[DataMessage.UPDATE_BODY_CHANGES] as Array;
            if(this._properties == null)
            {
               this._properties = ObjectUtil.getClassInfo(this._newItem,null,ConcreteDataService.CLASS_INFO_OPTIONS).properties;
               for(i = 0; i < this._properties.length; i++)
               {
                  prop = this._properties[i];
                  qName = prop as QName;
                  if(qName && !qName.uri)
                  {
                     this._properties[i] = qName.localName;
                  }
               }
            }
         }
         else if(this.isCreate())
         {
            this._newItem = DataMessage.unwrapItem(this.message.body);
         }
         else
         {
            this._previousItem = DataMessage.unwrapItem(this.message.body);
         }
      }
      
      public function get changedPropertyNames() : Array
      {
         return this._properties;
      }
      
      public function get currentVersion() : Object
      {
         return this._currentItem;
      }
      
      public function get identity() : Object
      {
         return this._message == null?null:this._message.identity;
      }
      
      public function get message() : DataMessage
      {
         return this._message;
      }
      
      public function get newVersion() : Object
      {
         return this._newItem;
      }
      
      public function get previousVersion() : Object
      {
         return this._previousItem;
      }
      
      public function conflict(description:String, properties:Array) : void
      {
         var errMsg:DataErrorMessage = new DataErrorMessage();
         errMsg.cause = this._message;
         errMsg.faultString = description;
         errMsg.propertyNames = properties;
         if(this.isDelete())
         {
            errMsg.serverObject = this._dataService.normalize(DataMessage.unwrapItem(this.previousVersion));
            errMsg.headers.referencedIds = this._message.headers.referencedIds;
         }
         else
         {
            errMsg.serverObject = this._dataService.normalize(DataMessage.unwrapItem(this.newVersion));
            if(this.isCreate())
            {
               errMsg.headers.referencedIds = this._message.headers.referencedIds;
            }
            else
            {
               errMsg.headers.referencedIds = this._message.headers.newReferencedIds;
            }
         }
         var mci:MessageCacheItem = this._dataService.dataStore.messageCache.getAnyCacheItem(this._message.messageId);
         if(mci == null || mci.message != this._message)
         {
            if(errMsg.headers.referencedIds == null)
            {
               errMsg.headers.referencedIds = {};
            }
            this._dataService.metadata.convertServerToClientReferencedIds(errMsg.serverObject,errMsg.headers.referencedIds,this._dataService.getOperationPropertySpecifier(this._message));
         }
         this._dataService.metadata.configureItem(this._dataService,errMsg.serverObject,errMsg.serverObject,this._dataService.getOperationPropertySpecifier(this._message),null,errMsg.headers.referencedIds,false,false,null,true);
         this._conflict = errMsg;
      }
      
      public function getConflict() : DataErrorMessage
      {
         return this._conflict;
      }
      
      public function isCreate() : Boolean
      {
         return this._message.operation == DataMessage.CREATE_OPERATION || this._message.operation == DataMessage.CREATE_AND_SEQUENCE_OPERATION;
      }
      
      public function isDelete() : Boolean
      {
         return this._message.operation == DataMessage.DELETE_OPERATION;
      }
      
      public function isUpdate() : Boolean
      {
         return this._message.operation == DataMessage.UPDATE_OPERATION;
      }
   }
}
