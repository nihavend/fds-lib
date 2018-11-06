package mx.data
{
   import flash.events.Event;
   import flash.events.IEventDispatcher;
   import mx.collections.ListCollectionView;
   import mx.data.errors.DataServiceError;
   import mx.data.events.DataServiceFaultEvent;
   import mx.data.messages.DataMessage;
   import mx.data.utils.AsyncTokenChain;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   
   [Event(name="propertyChange",type="mx.events.PropertyChangeEvent")]
   [Event(name="message",type="mx.messaging.events.MessageEvent")]
   [Event(name="conflict",type="mx.data.events.DataConflictEvent")]
   [Event(name="fault",type="mx.data.events.DataServiceFaultEvent")]
   [Event(name="result",type="mx.rpc.events.ResultEvent")]
   [ResourceBundle("data")]
   public class DataManager implements IEventDispatcher
   {
       
      
      public var adapter:DataServiceAdapter = null;
      
      protected var _implementation:ConcreteDataService = null;
      
      var propertyCache:Object;
      
      var eventListenerCache:Array;
      
      public function DataManager()
      {
         this.propertyCache = new Object();
         super();
      }
      
      public static function synchronizeDataServices(services:Array) : AsyncToken
      {
         var service:DataManager = null;
         var token:AsyncTokenChain = new AsyncTokenChain();
         for each(service in services)
         {
            token.addPendingInvocation(service.synchronizeAllFills);
         }
         return token;
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get autoCommit() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.autoCommit;
         }
         return Boolean(this.propertyCache.autoCommit)?Boolean(this.propertyCache.autoCommit):Boolean(false);
      }
      
      public function set autoCommit(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.autoCommit = value;
         }
         else
         {
            this.propertyCache.autoCommit = value;
         }
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get ignoreCollectionUpdates() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.ignoreCollectionUpdates;
         }
         return Boolean(this.propertyCache.ignoreCollectionUpdates)?Boolean(this.propertyCache.ignoreCollectionUpdates):Boolean(false);
      }
      
      public function set ignoreCollectionUpdates(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.ignoreCollectionUpdates = value;
         }
         else
         {
            this.propertyCache.ignoreCollectionUpdates = value;
         }
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get autoConnect() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.autoConnect;
         }
         return Boolean(this.propertyCache.autoConnect)?Boolean(this.propertyCache.autoConnect):Boolean(false);
      }
      
      public function set autoConnect(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.autoConnect = value;
         }
         else
         {
            this.propertyCache.autoConnect = value;
         }
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get encryptLocalCache() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.encryptLocalCache;
         }
         return Boolean(this.propertyCache.encryptLocalCache)?Boolean(this.propertyCache.encryptLocalCache):Boolean(false);
      }
      
      public function set encryptLocalCache(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.encryptLocalCache = value;
         }
         else
         {
            this.propertyCache.encryptLocalCache = value;
         }
      }
      
      public function get autoMerge() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.autoMerge;
         }
         return Boolean(this.propertyCache.autoMerge)?Boolean(this.propertyCache.autoMerge):Boolean(false);
      }
      
      public function set autoMerge(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.autoMerge = value;
         }
         else
         {
            this.propertyCache.autoMerge = value;
         }
      }
      
      public function get autoSaveCache() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.autoSaveCache;
         }
         return Boolean(this.propertyCache.autoSaveCache)?Boolean(this.propertyCache.autoSaveCache):Boolean(false);
      }
      
      public function set autoSaveCache(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.autoSaveCache = value;
         }
         else
         {
            this.propertyCache.autoSaveCache = value;
         }
      }
      
      public function get autoSyncEnabled() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.autoSyncEnabled;
         }
         return Boolean(this.propertyCache.autoSyncEnabled)?Boolean(this.propertyCache.autoSyncEnabled):Boolean(false);
      }
      
      public function set autoSyncEnabled(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.autoSyncEnabled = value;
         }
         else
         {
            this.propertyCache.autoSyncEnabled = value;
         }
      }
      
      public function get cacheID() : String
      {
         if(this._implementation != null)
         {
            return this._implementation.cacheID;
         }
         return Boolean(this.propertyCache.cacheID)?this.propertyCache.cacheID:null;
      }
      
      public function set cacheID(value:String) : void
      {
         if(this._implementation != null)
         {
            this._implementation.cacheID = value;
         }
         else
         {
            this.propertyCache.cacheID = value;
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get conflicts() : Conflicts
      {
         if(this._implementation == null)
         {
            if(this.propertyCache.conflicts == null)
            {
               this.propertyCache.conflicts = new Conflicts();
            }
            return this.propertyCache.conflicts;
         }
         return this._implementation.conflicts;
      }
      
      public function get conflictDetector() : ConflictDetector
      {
         if(this._implementation != null)
         {
            return this._implementation.conflictDetector;
         }
         return Boolean(this.propertyCache.conflictDetector)?this.propertyCache.conflictDetector:null;
      }
      
      public function set conflictDetector(value:ConflictDetector) : void
      {
         if(this._implementation != null)
         {
            this._implementation.conflictDetector = value;
         }
         else
         {
            this.propertyCache.conflictDetector = value;
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get connected() : Boolean
      {
         return this._implementation == null?Boolean(false):Boolean(this._implementation.connected);
      }
      
      [Bindable(event="propertyChange")]
      public function get subscribed() : Boolean
      {
         return this._implementation == null?Boolean(false):Boolean(this._implementation.subscribed);
      }
      
      [Bindable(event="propertyChange")]
      public function get commitRequired() : Boolean
      {
         return this._implementation == null?Boolean(false):Boolean(this._implementation.commitRequired);
      }
      
      public function commitRequiredOn(object:Object) : Boolean
      {
         return this._implementation == null?Boolean(false):Boolean(this._implementation.commitRequiredOn(object));
      }
      
      [Bindable(event="propertyChange")]
      public function get dataStore() : DataStore
      {
         if(this._implementation != null)
         {
            return this._implementation.dataStore;
         }
         var ds:DataStore = this.propertyCache.dataStore;
         if(ds != null)
         {
            return ds;
         }
         this.initialize();
         return this._implementation != null?this._implementation.dataStore:null;
      }
      
      public function set dataStore(ds:DataStore) : void
      {
         if(this._implementation != null)
         {
            this._implementation.dataStore = ds;
         }
         else
         {
            this.propertyCache.dataStore = ds;
         }
      }
      
      public function get offlineAdapter() : DataServiceOfflineAdapter
      {
         if(this._implementation != null)
         {
            return this._implementation.offlineAdapter;
         }
         var offline:DataServiceOfflineAdapter = this.propertyCache.offlineAdapter;
         if(offline != null)
         {
            return offline;
         }
         return null;
      }
      
      public function set offlineAdapter(offlineAdapter:DataServiceOfflineAdapter) : void
      {
         if(this._implementation != null)
         {
            this._implementation.offlineAdapter = offlineAdapter;
         }
         else
         {
            this.propertyCache.offlineAdapter = offlineAdapter;
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get fallBackToLocalFill() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.fallBackToLocalFill;
         }
         return this.propertyCache.fallBackToLocalFill;
      }
      
      public function set fallBackToLocalFill(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.fallBackToLocalFill = value;
         }
         else
         {
            this.propertyCache.fallBackToLocalFill = value;
         }
      }
      
      public function get indexReferences() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.indexReferences;
         }
         return Boolean(this.propertyCache.indexReferences)?Boolean(this.propertyCache.indexReferences):Boolean(true);
      }
      
      public function set indexReferences(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.indexReferences = value;
         }
         else
         {
            this.propertyCache.indexReferences = value;
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get isInitialized() : Boolean
      {
         return this._implementation == null?Boolean(false):Boolean(this._implementation.initialized);
      }
      
      [Bindable(event="propertyChange")]
      public function get mergeRequired() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.mergeRequired;
         }
         return false;
      }
      
      public function get pagingEnabled() : Boolean
      {
         return this._implementation != null?Boolean(this._implementation.pagingEnabled):Boolean(false);
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get pageSize() : int
      {
         if(this._implementation != null)
         {
            return this._implementation.pageSize;
         }
         return Boolean(this.propertyCache.pageSize)?int(this.propertyCache.pageSize):int(Metadata.DEFAULT_PAGE_SIZE);
      }
      
      public function set pageSize(value:int) : void
      {
         if(this._implementation != null)
         {
            this._implementation.pageSize = value;
         }
         else
         {
            this.propertyCache.pageSize = value;
         }
      }
      
      public function get priority() : int
      {
         if(this._implementation != null)
         {
            return this._implementation.priority;
         }
         return Boolean(this.propertyCache.priority)?int(this.propertyCache.priority):int(-1);
      }
      
      public function set priority(value:int) : void
      {
         if(this._implementation != null)
         {
            this._implementation.priority = value;
         }
         else
         {
            this.propertyCache.priority = value;
         }
      }
      
      [Inspectable(category="General",verbose="1")]
      public function get requestTimeout() : int
      {
         if(this._implementation != null)
         {
            return this._implementation.requestTimeout;
         }
         return this.propertyCache.requestTimeout != null?int(this.propertyCache.requestTimeout):int(-1);
      }
      
      public function set requestTimeout(value:int) : void
      {
         if(this._implementation != null)
         {
            this._implementation.requestTimeout = value;
         }
         else
         {
            this.propertyCache.requestTimeout = value;
         }
      }
      
      public function get manualSync() : ManualSyncConfiguration
      {
         return this._implementation.manualSync;
      }
      
      public function set manualSync(mrc:ManualSyncConfiguration) : void
      {
         this._implementation.manualSync = mrc;
      }
      
      public function get maxFrequency() : uint
      {
         if(this._implementation != null)
         {
            return this._implementation.maxFrequency;
         }
         return this.propertyCache.maxFrequency > 0?uint(this.propertyCache.maxFrequency):uint(0);
      }
      
      public function set maxFrequency(value:uint) : void
      {
         if(this._implementation != null)
         {
            this._implementation.maxFrequency = value;
         }
         else
         {
            this.propertyCache.maxFrequency = value;
         }
      }
      
      public function get throwItemPendingErrors() : Boolean
      {
         return this._implementation.throwItemPendingErrors;
      }
      
      public function set throwItemPendingErrors(value:Boolean) : void
      {
         this._implementation.throwItemPendingErrors = value;
      }
      
      public function get hierarchicalEventsDefault() : Boolean
      {
         return this._implementation.metadata.hierarchicalEventsDefault;
      }
      
      public function set hierarchicalEventsDefault(value:Boolean) : void
      {
         this._implementation.metadata.hierarchicalEventsDefault = value;
      }
      
      public function get deleteItemOnRemoveFromFill() : Boolean
      {
         if(this._implementation != null)
         {
            return this._implementation.deleteItemOnRemoveFromFill;
         }
         return this.propertyCache.deleteItemOnRemoveFromFill;
      }
      
      public function set deleteItemOnRemoveFromFill(value:Boolean) : void
      {
         if(this._implementation != null)
         {
            this._implementation.deleteItemOnRemoveFromFill = value;
         }
         else
         {
            this.propertyCache.deleteItemOnRemoveFromFill = value;
         }
      }
      
      public function set resubscribeAttempts(ra:int) : void
      {
         this._implementation.consumer.resubscribeAttempts = ra;
      }
      
      public function get resubscribeAttempts() : int
      {
         return this._implementation.consumer.resubscribeAttempts;
      }
      
      public function set resubscribeInterval(ri:int) : void
      {
         this._implementation.consumer.resubscribeInterval = ri;
      }
      
      public function get resubscribeInterval() : int
      {
         return this._implementation.consumer.resubscribeInterval;
      }
      
      public function get resetCollectionOnFill() : Boolean
      {
         return this._implementation.resetCollectionOnFill;
      }
      
      public function set resetCollectionOnFill(value:Boolean) : void
      {
         this._implementation.resetCollectionOnFill = value;
      }
      
      public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false) : void
      {
         if(this._implementation == null)
         {
            if(this.eventListenerCache == null)
            {
               this.eventListenerCache = new Array();
            }
            this.eventListenerCache.push({
               "type":type,
               "listener":listener,
               "useCapture":useCapture,
               "priority":priority,
               "useWeakReference":useWeakReference
            });
         }
         else
         {
            this._implementation.addEventListener(type,listener,useCapture,priority,useWeakReference);
         }
      }
      
      public function clearCache(value:Object = null) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.clearCache(value);
      }
      
      public function clearCacheData(descriptor:CacheDataDescriptor) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.clearCacheData(descriptor);
      }
      
      public function commit(itemsOrCollections:Array = null, cascadeCommit:Boolean = false) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.commit(itemsOrCollections,cascadeCommit);
      }
      
      public function connect() : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.connect();
      }
      
      public function count(... args) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.count(args);
      }
      
      public function createItem(item:Object) : ItemReference
      {
         this.checkImplementation();
         return this._implementation.createItem(item);
      }
      
      public function deleteItem(item:Object) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.deleteItem(item);
      }
      
      public function disconnect() : void
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return;
         }
         this._implementation.disconnect();
      }
      
      public function dispatchEvent(event:Event) : Boolean
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return false;
         }
         return this._implementation.dispatchEvent(event);
      }
      
      public function executeQuery(queryName:String, propertySpecifier:PropertySpecifier, ... args) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.executeQuery(queryName,propertySpecifier,args);
      }
      
      public function findItem(queryName:String, propertySpecifier:PropertySpecifier, ... args) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.executeQuery(queryName,propertySpecifier,args,true);
      }
      
      public function fill(value:ListCollectionView, ... args) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.fill(value,args,null);
      }
      
      public function synchronizeFill(... fillArgs) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.synchronizeFill(fillArgs);
      }
      
      public function synchronizeAllFills() : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.synchronizeAllFills();
      }
      
      public function fillSubset(value:ListCollectionView, ps:PropertySpecifier, ... args) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.fill(value,args,ps);
      }
      
      public function localFill(value:ListCollectionView, ps:PropertySpecifier, ... args) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.fill(value,args,ps,false,true);
      }
      
      public function refreshCollection(value:ListCollectionView) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.refreshCollection(value);
      }
      
      public function refresh() : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.refresh();
      }
      
      public function getCacheData(descriptor:CacheDataDescriptor) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.getCacheData(descriptor);
      }
      
      public function getCacheDescriptors(view:ListCollectionView, options:uint = 0, item:Object = null) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.getCacheDescriptors(view,options,item);
      }
      
      public function getCacheIDs(view:ListCollectionView) : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.getCacheIDs(view);
      }
      
      public function getItem(identity:Object, defaultValue:Object = null) : ItemReference
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return null;
         }
         return this._implementation.getItem(identity,defaultValue);
      }
      
      public function getLocalItem(identity:Object) : Object
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return null;
         }
         return this._implementation.getLocalItem(identity);
      }
      
      public function getPendingOperation(item:Object) : uint
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return DataMessage.UNKNOWN_OPERATION;
         }
         return this._implementation.getPendingOperation(item);
      }
      
      public function hasEventListener(type:String) : Boolean
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return false;
         }
         return this._implementation.hasEventListener(type);
      }
      
      public function initialize() : AsyncToken
      {
         this.checkImplementation();
         if(this._implementation == null)
         {
            return new AsyncToken();
         }
         return this._implementation.initialize();
      }
      
      public function merge() : void
      {
         this.checkImplementation();
         if(this._implementation != null)
         {
            this._implementation.merge();
         }
      }
      
      public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false) : void
      {
         var i:int = 0;
         var ent:Object = null;
         if(this._implementation != null)
         {
            this._implementation.removeEventListener(type,listener,useCapture);
         }
         else if(this.eventListenerCache != null)
         {
            for(i = 0; i < this.eventListenerCache.length; i++)
            {
               ent = this.eventListenerCache[i];
               if(ent.type == type && ent.listener == listener && ent.useCapture == useCapture)
               {
                  this.eventListenerCache = this.eventListenerCache.splice(i,1);
                  break;
               }
            }
         }
      }
      
      public function release(clear:Boolean = true, copyStillManagedItems:Boolean = true) : void
      {
         this.checkImplementation();
         this._implementation.release(clear,copyStillManagedItems);
      }
      
      public function isCollectionManaged(view:ListCollectionView) : Boolean
      {
         this.checkImplementation();
         return this._implementation.isCollectionManaged(view);
      }
      
      public function isCollectionPaged(view:ListCollectionView) : Boolean
      {
         this.checkImplementation();
         return this._implementation.isCollectionPaged(view);
      }
      
      public function isRangeResident(view:ListCollectionView, startIndex:int, numberOfItems:int) : Boolean
      {
         this.checkImplementation();
         return this._implementation.isRangeResident(view,startIndex,numberOfItems);
      }
      
      public function releaseCollection(view:ListCollectionView, clear:Boolean = false, copyStillManagedItems:Boolean = true) : void
      {
         this.checkImplementation();
         this._implementation.releaseCollection(view,clear,copyStillManagedItems);
      }
      
      public function releaseItem(item:IManaged, copyStillManagedItems:Boolean = true, enableStillManagedCheck:Boolean = true) : IManaged
      {
         this.checkImplementation();
         return this._implementation.releaseItem(item,copyStillManagedItems,enableStillManagedCheck);
      }
      
      public function releaseItemsFromCollection(collection:ListCollectionView, startIndex:int, numberOfItems:int) : int
      {
         this.checkImplementation();
         return this._implementation.releaseItemsFromCollection(collection,startIndex,numberOfItems);
      }
      
      public function releaseReference(item:Object, propName:String) : Boolean
      {
         return this._implementation.releaseReference(item,propName);
      }
      
      public function revertChanges(item:IManaged = null) : Boolean
      {
         this.checkImplementation();
         return this._implementation.revertChanges(item);
      }
      
      public function revertChangesForCollection(collection:ListCollectionView = null) : Boolean
      {
         this.checkImplementation();
         return this._implementation.revertChangesForCollection(collection);
      }
      
      public function saveCache(value:Object = null) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.saveCache(value);
      }
      
      public function updateItem(item:Object, origItem:Object = null, changes:Array = null) : AsyncToken
      {
         this.checkImplementation();
         return this._implementation.updateItem(item,origItem,changes);
      }
      
      public function willTrigger(type:String) : Boolean
      {
         this.checkImplementation();
         return this._implementation.willTrigger(type);
      }
      
      public function getPageInformation(view:ListCollectionView) : PageInformation
      {
         this.checkImplementation();
         return this._implementation.getPageInformation(view);
      }
      
      protected function checkImplementation() : void
      {
         var errorMsg:String = null;
         var fault:Fault = null;
         var initFaultEvent:DataServiceFaultEvent = null;
         var i:int = 0;
         if(this._implementation == null)
         {
            errorMsg = "DataManager cannot be initialized until its configuration is set";
            fault = new Fault("DataManager.InitializationFailed",errorMsg);
            initFaultEvent = DataServiceFaultEvent.createEvent(fault,null,null,null,null);
            if(this.eventListenerCache != null)
            {
               for(i = 0; i < this.eventListenerCache.length; i++)
               {
                  if(this.eventListenerCache[i].type == DataServiceFaultEvent.FAULT)
                  {
                     this.eventListenerCache[i].listener(initFaultEvent);
                  }
               }
            }
            else
            {
               throw new DataServiceError(errorMsg);
            }
         }
      }
      
      function setImplementation(impl:ConcreteDataService) : void
      {
         var prop:* = null;
         var i:int = 0;
         var ent:Object = null;
         this._implementation = impl;
         if(impl != null)
         {
            for(prop in this.propertyCache)
            {
               if(prop == "conflicts")
               {
                  impl.conflicts = this.propertyCache[prop];
               }
               else
               {
                  this[prop] = this.propertyCache[prop];
               }
            }
            this.propertyCache = null;
            if(this.eventListenerCache != null)
            {
               for(i = 0; i < this.eventListenerCache.length; i++)
               {
                  ent = this.eventListenerCache[i];
                  this._implementation.addEventListener(ent.type,ent.listener,ent.useCapture,ent.priority,ent.useWeakReference);
               }
            }
            this.eventListenerCache = null;
         }
      }
      
      function get concreteDataService() : ConcreteDataService
      {
         return this._implementation;
      }
   }
}
