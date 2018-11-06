package mx.data
{
   import flash.events.IEventDispatcher;
   import flash.utils.Dictionary;
   import flash.xml.XMLNode;
   import mx.collections.ItemResponder;
   import mx.collections.ListCollectionView;
   import mx.collections.errors.ItemPendingError;
   import mx.data.events.DatabaseResultEvent;
   import mx.data.events.DatabaseStatusEvent;
   import mx.data.messages.DataMessage;
   import mx.data.utils.Managed;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.ErrorMessage;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.ObjectUtil;
   
   public class DataServiceOfflineAdapter
   {
      
      private static const CACHE_IDS_STORE_ID:String = "_cacheids";
      
      private static const CACHE_IDS_COLLECTION_ID:String = "_cache_ids_col";
      
      private static const FILLS_COLLECTION_ID:String = "_fills";
      
      private static const DESCRIPTOR_KEY:String = "_desc";
      
      private static const MESSAGE_CACHE_COLLECTION_ID:String = "_mc_";
      
      private static const MESSAGE_CACHE_KEY:String = "_mc";
      
      private static const UNMERGED_MESSAGES_KEY:String = "_um";
      
      private static const CONFIG_KEY:String = "_config_";
      
      private static const METADATA_STORE:String = "metadata";
      
      private static var cacheIdWritten:Boolean = false;
      
      private static var cacheIdStore:IDatabase;
      
      private static var _log:ILogger;
       
      
      private var _localStore:IDatabase;
      
      private var _cacheID:String;
      
      private var _destination:String;
      
      var dataStoreEventDispatcher:DataStoreEventDispatcher;
      
      public function DataServiceOfflineAdapter()
      {
         super();
         if(_log == null)
         {
            _log = Log.getLogger("mx.data.DataServiceOfflineAdapter");
         }
      }
      
      protected function get destination() : String
      {
         return this._destination;
      }
      
      function set destination(value:String) : void
      {
         this._destination = value;
      }
      
      public function isQuerySupported() : Boolean
      {
         return false;
      }
      
      public final function initializeCacheStore() : void
      {
         if(cacheIdStore != null && cacheIdStore.connected)
         {
            cacheIdStore.close();
         }
         cacheIdWritten = false;
         if(cacheIdStore == null)
         {
            cacheIdStore = LocalStoreFactory.create();
         }
      }
      
      public function connect(cacheID:String) : AsyncToken
      {
         var token:AsyncToken = null;
         var localStoreConnectHandler:Function = null;
         var resultEvent:ResultEvent = null;
         token = new AsyncToken();
         localStoreConnectHandler = function(event:DatabaseStatusEvent):void
         {
            var faultEvent:FaultEvent = null;
            var resultEvent:ResultEvent = null;
            if(event.level == "status" && event.code == "Client.Connect.Success")
            {
               localStore.removeEventListener(DatabaseStatusEvent.STATUS,localStoreConnectHandler);
               if(localStore.connected)
               {
                  resultEvent = ResultEvent.createEvent(null,token);
                  new AsyncDispatcher(token.applyResult,[resultEvent],10);
               }
               else
               {
                  faultEvent = FaultEvent.createEvent(new Fault(event.code,event.details),token);
                  new AsyncDispatcher(token.applyFault,[faultEvent],10);
               }
            }
            else if(event.level == "error")
            {
               localStore.removeEventListener(DatabaseStatusEvent.STATUS,localStoreConnectHandler);
               faultEvent = FaultEvent.createEvent(new Fault(event.code,event.details),token);
               new AsyncDispatcher(token.applyFault,[faultEvent],10);
            }
         };
         if(this.localStore.connected)
         {
            resultEvent = ResultEvent.createEvent(null,token);
            new AsyncDispatcher(token.applyResult,[resultEvent],10);
         }
         else
         {
            this._cacheID = cacheID;
            this.localStore.addEventListener(DatabaseStatusEvent.STATUS,localStoreConnectHandler);
            this.localStore.connect(cacheID);
         }
         return token;
      }
      
      public function close() : void
      {
         if(this.localStore)
         {
            this.localStore.close();
         }
      }
      
      public function beginTransaction() : void
      {
         this.localStore.begin();
      }
      
      public function commit(dispatcher:IEventDispatcher = null, token:AsyncToken = null, faultsOnly:Boolean = false) : void
      {
         if(this.localStore.inTransaction)
         {
            this.commitLocalStore(dispatcher,token,faultsOnly);
         }
         else
         {
            this.localStore.rollback();
         }
      }
      
      public function rollback() : void
      {
         this.localStore.rollback();
      }
      
      public function isConnected() : Boolean
      {
         return this.localStore && this.localStore.connected;
      }
      
      function isStoreEmpty() : Boolean
      {
         return this.localStore.empty;
      }
      
      function get localStore() : IDatabase
      {
         return this._localStore;
      }
      
      function set localStore(localStore:IDatabase) : void
      {
         this._localStore = localStore;
      }
      
      function get cacheID() : String
      {
         return this._cacheID;
      }
      
      function set cacheID(value:String) : void
      {
         this._cacheID = value;
      }
      
      public final function saveMessageCache(messageCache:DataMessageCache, unmergedMessages:Array) : void
      {
         var collection:IDatabaseCollection = this.localStore.getCollection(MESSAGE_CACHE_COLLECTION_ID);
         if(Log.isDebug())
         {
            _log.debug("Saving message cache: " + messageCache.toString());
         }
         collection.put(MESSAGE_CACHE_KEY,messageCache);
         collection.put(UNMERGED_MESSAGES_KEY,unmergedMessages);
      }
      
      public final function getMessageCache() : Object
      {
         var msgCache:Object = null;
         var cacheCollection:IDatabaseCollection = null;
         cacheCollection = this.localStore.getCollection(MESSAGE_CACHE_COLLECTION_ID);
         var msg:Object = cacheCollection.get(MESSAGE_CACHE_KEY);
         if(msg != null)
         {
            msgCache = {};
            msgCache.messageCache = DataMessageCache(msg);
            msgCache.unmergedMessage = cacheCollection.get(UNMERGED_MESSAGES_KEY) as Array;
         }
         return msgCache;
      }
      
      public function saveQuery(queryParams:Object, data:Object) : void
      {
         var colName:String = this.getPersistentFillID(queryParams,this.destination);
         var refsCol:IDatabaseCollection = this.localStore.getCollection(colName);
         var fillsCol:IDatabaseCollection = this.localStore.getCollection(FILLS_COLLECTION_ID);
         refsCol.put(DESCRIPTOR_KEY,data);
         fillsCol.put(colName,colName);
      }
      
      public function restoreQuery(queryParams:Object) : Object
      {
         var colName:String = this.getPersistentFillID(queryParams,this.destination);
         var refsCol:IDatabaseCollection = this.localStore.getCollection(colName);
         var desc:Object = refsCol.get(DESCRIPTOR_KEY);
         return desc;
      }
      
      public function getFillList() : Array
      {
         var fillsCol:IDatabaseCollection = this.localStore.getCollection(FILLS_COLLECTION_ID);
         var fillsIter:IDatabaseCursor = fillsCol.createCursor();
         fillsIter.seek(0,-1,-1);
         var fillName:Object = null;
         var refsCol:IDatabaseCollection = null;
         var descriptor:Object = null;
         var fillList:Array = new Array();
         while(!fillsIter.afterLast)
         {
            fillName = fillsIter.current;
            if(fillName != null)
            {
               refsCol = this.localStore.getCollection(fillName.toString());
               descriptor = refsCol.get(DESCRIPTOR_KEY);
               fillList.push(descriptor);
            }
            fillsIter.moveNext();
         }
         return fillList;
      }
      
      public function saveItems(items:Array) : void
      {
         var item:Object = null;
         var itemAdapter:Object = null;
         var extra:Array = null;
         var uid:String = null;
         var colName:String = this.getPersistentItemCacheID(this.destination);
         var itemCacheCol:IDatabaseCollection = this.localStore.getCollection(colName);
         var cds:ConcreteDataService = ConcreteDataService.lookupService(this.destination);
         for(var i:int = 0; i < items.length; i++)
         {
            item = items[i];
            if(item is IManaged)
            {
               itemAdapter = {};
               itemAdapter.item = DataMessage.wrapItem(item,this.destination);
               itemAdapter.referencedIds = Managed.getReferencedIds(item);
               itemAdapter.destination = Managed.getDestination(item);
               itemAdapter.uid = IManaged(item).uid;
               extra = cds.getFetchedProperties(item);
               if(extra != null)
               {
                  itemAdapter.extra = extra;
               }
               uid = IManaged(item).uid;
               itemCacheCol.put(uid,itemAdapter);
            }
            else if(Log.isDebug())
            {
               _log.debug("Found a invalid item: " + item);
            }
         }
      }
      
      public function getItems(uid:Array) : Dictionary
      {
         var itemCacheId:String = this.getPersistentItemCacheID(this.destination);
         var itemsCol:IDatabaseCollection = this.localStore.getCollection(itemCacheId);
         var itemDic:Dictionary = new Dictionary();
         for(var index:int = 0; index < uid.length; index++)
         {
            itemDic[uid[index]] = itemsCol.get(uid[index]);
         }
         return itemDic;
      }
      
      public function deleteOfflineItems(uidArray:Array) : void
      {
         for(var i:int = 0; i < uidArray.length; i++)
         {
            this.deleteOfflineItem(uidArray[i]);
         }
      }
      
      public function deleteOfflineItem(uid:String) : void
      {
         var itemCacheColId:String = this.getPersistentItemCacheID(this.destination);
         var itemCacheCol:IDatabaseCollection = this.localStore.getCollection(itemCacheColId);
         itemCacheCol.remove(uid);
      }
      
      public function addOfflineItem(item:Object) : void
      {
         var itemList:Array = new Array();
         itemList.push(item);
         this.saveItems(itemList);
      }
      
      public function updateOfflineItem(item:Object, propChangeList:Array) : void
      {
         var update:Dictionary = new Dictionary();
         update[item] = propChangeList;
         this.updateOfflineItems(update);
      }
      
      public function updateOfflineItems(itemUpdates:Dictionary) : void
      {
         var item:* = null;
         var itemList:Array = new Array();
         for(item in itemUpdates)
         {
            itemList.push(item);
         }
         this.saveItems(itemList);
      }
      
      public function saveMetaData(metadata:Object) : void
      {
         var itemCacheCol:IDatabaseCollection = this.localStore.getCollection(METADATA_STORE);
         if(Log.isDebug())
         {
            _log.debug("Saving offline configuration for destination: " + this.destination);
         }
         itemCacheCol.put(this.destination,metadata);
      }
      
      public function retrieveMetaData() : Object
      {
         var itemCacheCol:IDatabaseCollection = this.localStore.getCollection(METADATA_STORE);
         if(Log.isDebug())
         {
            _log.debug("Retrieving offline configuration for destination: " + this.destination);
         }
         return itemCacheCol.get(this.destination);
      }
      
      public function executeOfflineQuery(propSpecifier:PropertySpecifier, args:Array, startIndex:int, numItems:int) : AsyncToken
      {
         return null;
      }
      
      public function getItemReferenceIds(uid:String, propName:String) : Array
      {
         return null;
      }
      
      public function initializeOfflineMetadata(metadata:Metadata) : void
      {
      }
      
      private function getPersistentFillID(id:Object, destination:String) : String
      {
         var result:String = null;
         var params:Array = null;
         var fillParams:String = null;
         var i:int = 0;
         if(id is Array)
         {
            params = id as Array;
            if(params.length == 0)
            {
               result = "_d" + destination;
            }
            else
            {
               for(fillParams = ""; i < params.length; )
               {
                  fillParams = fillParams + this.convertFillParams(params[i]);
                  if(i < params.length - 1)
                  {
                     fillParams = fillParams + "_";
                  }
                  i++;
               }
               if(fillParams.length == 0)
               {
                  fillParams = "_";
               }
               result = fillParams + destination;
            }
         }
         else
         {
            result = destination + "_" + ObjectUtil.toString(id);
         }
         return result;
      }
      
      private function getPersistentItemCacheID(destination:String) : String
      {
         return "_" + destination + "_ic";
      }
      
      function commitLocalStore(dispatcher:IEventDispatcher, token:AsyncToken, faultsOnly:Boolean) : void
      {
         var cacheID:String = null;
         var statusHandler:Function = null;
         cacheID = this.cacheID;
         statusHandler = function(event:DatabaseStatusEvent):void
         {
            var errMsg:ErrorMessage = null;
            var fltEvent:MessageFaultEvent = null;
            localStore.removeEventListener(DatabaseStatusEvent.STATUS,statusHandler);
            if(event.level == "error")
            {
               if(dispatcher != null)
               {
                  errMsg = new ErrorMessage();
                  errMsg.faultCode = event.code;
                  errMsg.faultDetail = event.details;
                  errMsg.faultString = event.level;
                  fltEvent = MessageFaultEvent.createEvent(errMsg);
                  dataStoreEventDispatcher.dispatchCacheFaultEvent(dispatcher,fltEvent,token);
               }
            }
            else if(event.level == "status" && event.code == "Client.Commit.Success")
            {
               addCacheId(cacheID,dispatcher,token,faultsOnly);
            }
         };
         this.localStore.addEventListener(DatabaseStatusEvent.STATUS,statusHandler);
         this.localStore.commit();
      }
      
      private function convertFillParams(value:Object) : String
      {
         var str:String = null;
         var classInfo:Object = null;
         var properties:Array = null;
         var isArray:Boolean = false;
         var prop:* = undefined;
         var j:int = 0;
         if(ObjectUtil.isSimple(value) && !(value is Array) || value is XMLNode)
         {
            return value.toString();
         }
         if(value == null)
         {
            return "null";
         }
         str = "";
         var type:String = typeof value;
         switch(type)
         {
            case "xml":
               return value.toString();
            case "object":
               if(value is Date)
               {
                  return value.toString();
               }
               if(value is XMLNode)
               {
                  return value.toString();
               }
               if(value is Class)
               {
                  return value.toString();
               }
               classInfo = ObjectUtil.getClassInfo(value);
               properties = classInfo.properties;
               isArray = value is Array;
               for(j = 0; j < properties.length; j++)
               {
                  prop = properties[j];
                  if(isArray)
                  {
                     str = str + "[";
                  }
                  str = str + prop.toString();
                  if(isArray)
                  {
                     str = str + "] ";
                  }
                  else
                  {
                     str = str + "=";
                  }
                  try
                  {
                     str = str + this.convertFillParams(value[prop]);
                  }
                  catch(e:Error)
                  {
                     str = str + "?";
                  }
               }
               return str;
            default:
               return value.toString();
         }
      }
      
      function internalGetCacheIDs(dispatcher:IEventDispatcher, view:ListCollectionView, token:AsyncToken) : void
      {
         var collection:IDatabaseCollection = null;
         var iter:IDatabaseCursor = null;
         var failed:Function = null;
         var iterSuccess:Function = null;
         var statusHandler:Function = null;
         view.removeAll();
         failed = function(info:ErrorMessage, tk:Object = null):void
         {
            cacheIdStore.close();
            var error:Error = new Error("Problem retrieving cache ids");
            dataStoreEventDispatcher.dispatchFileAccessFault(error,dispatcher,token,true);
         };
         iterSuccess = function():void
         {
            while(!iter.afterLast)
            {
               view.addItem(iter.current);
               iter.moveNext();
            }
            cacheIdStore.close();
            var event:MessageEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
            dataStoreEventDispatcher.dispatchResultEvent(dispatcher,event,token,null,true);
         };
         statusHandler = function(event:DatabaseStatusEvent):void
         {
            cacheIdStore.removeEventListener(DatabaseStatusEvent.STATUS,statusHandler);
            if(event != null && event.level == "error")
            {
               failed(null);
               return;
            }
            collection = cacheIdStore.getCollection(CACHE_IDS_COLLECTION_ID);
            iter = collection.createCursor();
            try
            {
               iter.seek(0,-1,-1);
               iterSuccess();
            }
            catch(e:ItemPendingError)
            {
               e.addResponder(new ItemResponder(iterSuccess,failed));
            }
         };
         if(cacheIdStore == null)
         {
            cacheIdStore = LocalStoreFactory.create();
         }
         cacheIdStore.addEventListener(DatabaseStatusEvent.STATUS,statusHandler);
         cacheIdStore.connect(CACHE_IDS_STORE_ID);
      }
      
      function clearCache(dispatcher:IEventDispatcher, token:AsyncToken, isDSInitialized:Boolean) : void
      {
         var dropStatusHandler:Function = null;
         var connectStatusHandler:Function = null;
         if(Log.isDebug())
         {
            _log.debug("clearCache called");
         }
         dropStatusHandler = function(event:DatabaseStatusEvent):void
         {
            var e:Error = null;
            localStore.removeEventListener(DatabaseStatusEvent.STATUS,dropStatusHandler);
            if(event.level == DatabaseStatusEvent.STATUS)
            {
               clearCacheId(dispatcher,token);
            }
            else
            {
               e = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
            }
         };
         connectStatusHandler = function(event:DatabaseStatusEvent):void
         {
            var rsltEvent:MessageEvent = null;
            var err:Error = null;
            localStore.removeEventListener(DatabaseStatusEvent.STATUS,connectStatusHandler);
            if(event.level == DatabaseStatusEvent.STATUS)
            {
               if(!localStore.empty)
               {
                  try
                  {
                     localStore.addEventListener(DatabaseStatusEvent.STATUS,dropStatusHandler);
                     localStore.drop();
                  }
                  catch(e:Error)
                  {
                     dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
                  }
               }
               else
               {
                  rsltEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
                  dataStoreEventDispatcher.dispatchResultEvent(dispatcher,rsltEvent,token,null,true);
               }
            }
            else
            {
               err = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(err,dispatcher,token,true);
            }
         };
         if(isDSInitialized)
         {
            if(!this.localStore.connected)
            {
               this.localStore.addEventListener(DatabaseStatusEvent.STATUS,connectStatusHandler);
               this.localStore.connect(this.cacheID);
            }
            else
            {
               connectStatusHandler(new DatabaseStatusEvent(null,false,false,"Client.Connect.Success",DatabaseStatusEvent.STATUS));
            }
         }
         else
         {
            dropStatusHandler(new DatabaseStatusEvent(null,false,false,"Client.Drop.Success",DatabaseStatusEvent.STATUS));
         }
      }
      
      function clearCacheData(dataStore:DataStore, ds:ConcreteDataService, descriptor:CacheDataDescriptor, token:AsyncToken) : void
      {
         var itemCol:IDatabaseCollection = null;
         var fillsCol:IDatabaseCollection = null;
         var countResultHandler:Function = null;
         var countStatusHandler:Function = null;
         var dropStatusHandler:Function = null;
         var colName:String = this.getPersistentFillID(descriptor.id,ds.destination);
         itemCol = this.localStore.getCollection(colName);
         var references:Array = descriptor.references;
         fillsCol = this.localStore.getCollection(FILLS_COLLECTION_ID);
         if(Log.isDebug())
         {
            _log.debug("clearCacheData called for descriptor: " + descriptor.toString());
         }
         var failure:Function = function(details:String):void
         {
            localStore.rollback();
            var error:Error = new Error(details);
            dataStoreEventDispatcher.dispatchFileAccessFault(error,ds,token,true);
         };
         countResultHandler = function(event:DatabaseResultEvent):void
         {
            fillsCol.removeEventListener(DatabaseResultEvent.RESULT,countResultHandler);
            fillsCol.removeEventListener(DatabaseStatusEvent.STATUS,countStatusHandler);
            var fillsRemaining:uint = event.result as uint;
            if(fillsRemaining == 0 && !(dataStore.commitRequired || dataStore.mergeRequired))
            {
               localStore.drop();
               clearCacheId(ds,token);
            }
            else
            {
               commitLocalStore(ds,token,false);
            }
         };
         countStatusHandler = function(event:DatabaseStatusEvent):void
         {
            if(event.level == "error")
            {
               failure(event.details);
            }
         };
         dropStatusHandler = function(event:DatabaseStatusEvent):void
         {
            itemCol.removeEventListener(DatabaseStatusEvent.STATUS,dropStatusHandler);
            if(event.level == DatabaseStatusEvent.STATUS)
            {
               fillsCol.addEventListener(DatabaseResultEvent.RESULT,countResultHandler);
               fillsCol.addEventListener(DatabaseStatusEvent.STATUS,countStatusHandler);
               fillsCol.count();
            }
            else
            {
               failure(event.details);
            }
         };
         var success:Function = function():void
         {
            itemCol.addEventListener(DatabaseStatusEvent.STATUS,dropStatusHandler);
            itemCol.drop();
         };
         try
         {
            this.localStore.begin();
            fillsCol.remove(colName);
            dataStore.clearReferencedItemsFromCache(ds,references,success,failure);
         }
         catch(e:Error)
         {
            localStore.rollback();
            dataStoreEventDispatcher.doCacheFault(ds,e,"Client.ClearCache.Failed","Attempt to clear the local cache failed.",token);
         }
      }
      
      private function addCacheId(value:String, dispatcher:IEventDispatcher, token:AsyncToken, faultsOnly:Boolean) : void
      {
         var collection:IDatabaseCollection = null;
         var commitStatusHandler:Function = null;
         var cacheConnectHandler:Function = null;
         var rsltEvent:MessageEvent = null;
         commitStatusHandler = function(event:DatabaseStatusEvent):void
         {
            var e:Error = null;
            var rsltEvent:MessageEvent = null;
            cacheIdStore.removeEventListener(DatabaseStatusEvent.STATUS,commitStatusHandler);
            cacheIdStore.close();
            if(event.level == "error")
            {
               cacheIdWritten = false;
               e = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
            }
            else if(!faultsOnly)
            {
               rsltEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
               dataStoreEventDispatcher.dispatchResultEvent(dispatcher,rsltEvent,token,null,true);
            }
         };
         cacheConnectHandler = function(event:DatabaseStatusEvent):void
         {
            var e:Error = null;
            cacheIdStore.removeEventListener(DatabaseStatusEvent.STATUS,cacheConnectHandler);
            if(event != null && event.level == "error")
            {
               e = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
            }
            else if(cacheIdStore.connected)
            {
               cacheIdStore.begin();
               collection = cacheIdStore.getCollection(CACHE_IDS_COLLECTION_ID);
               collection.put(value,value);
               cacheIdStore.addEventListener(DatabaseStatusEvent.STATUS,commitStatusHandler);
               cacheIdStore.commit();
            }
            else
            {
               cacheIdWritten = false;
               addCacheId(value,dispatcher,token,faultsOnly);
            }
         };
         if(!cacheIdWritten)
         {
            cacheIdWritten = true;
            cacheIdStore.addEventListener(DatabaseStatusEvent.STATUS,cacheConnectHandler);
            cacheIdStore.connect(CACHE_IDS_STORE_ID);
         }
         else if(!faultsOnly)
         {
            rsltEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
            this.dataStoreEventDispatcher.dispatchResultEvent(dispatcher,rsltEvent,token,null,true);
         }
      }
      
      private function clearCacheId(dispatcher:IEventDispatcher, token:AsyncToken) : void
      {
         var cacheID:String = null;
         var collection:IDatabaseCollection = null;
         var countResultHandler:Function = null;
         var commitStatusHandler:Function = null;
         var cacheConnectHandler:Function = null;
         cacheID = this.cacheID;
         countResultHandler = function(event:DatabaseResultEvent):void
         {
            collection.removeEventListener(DatabaseResultEvent.RESULT,countResultHandler);
            var idsRemaining:uint = event.result as uint;
            if(idsRemaining == 0 && cacheIdStore.connected)
            {
               cacheIdStore.drop();
            }
            cacheIdStore.close();
            var rsltEvent:MessageEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
            dataStoreEventDispatcher.dispatchResultEvent(dispatcher,rsltEvent,token,null,true);
         };
         commitStatusHandler = function(event:DatabaseStatusEvent):void
         {
            var e:Error = null;
            cacheIdStore.removeEventListener(DatabaseStatusEvent.STATUS,commitStatusHandler);
            if(event.level == "status")
            {
               collection.addEventListener(DatabaseResultEvent.RESULT,countResultHandler);
               collection.count();
            }
            else if(event.level == "error")
            {
               cacheIdStore.close();
               e = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
            }
         };
         cacheConnectHandler = function(event:DatabaseStatusEvent):void
         {
            var e:Error = null;
            var rsltEvent:MessageEvent = null;
            cacheIdStore.removeEventListener(DatabaseStatusEvent.STATUS,cacheConnectHandler);
            if(event != null && event.level == "error")
            {
               e = new Error(event.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(e,dispatcher,token,true);
            }
            else if(cacheIdStore.empty)
            {
               cacheIdStore.close();
               rsltEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
               dataStoreEventDispatcher.dispatchResultEvent(dispatcher,rsltEvent,token,null,true);
            }
            else
            {
               cacheIdStore.begin();
               collection = cacheIdStore.getCollection(CACHE_IDS_COLLECTION_ID);
               collection.remove(cacheID);
               cacheIdStore.addEventListener(DatabaseStatusEvent.STATUS,commitStatusHandler);
               cacheIdStore.commit();
            }
         };
         cacheIdStore.addEventListener(DatabaseStatusEvent.STATUS,cacheConnectHandler);
         cacheIdStore.connect(CACHE_IDS_STORE_ID);
      }
   }
}
