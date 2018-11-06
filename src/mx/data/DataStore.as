package mx.data
{
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IEventDispatcher;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   import mx.collections.ArrayCollection;
   import mx.collections.IViewCursor;
   import mx.collections.ItemResponder;
   import mx.collections.ListCollectionView;
   import mx.collections.errors.ItemPendingError;
   import mx.data.errors.DataServiceError;
   import mx.data.errors.UnresolvedConflictsError;
   import mx.data.events.DataConflictEvent;
   import mx.data.events.DataServiceFaultEvent;
   import mx.data.events.UnresolvedConflictsEvent;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.Managed;
   import mx.events.CollectionEvent;
   import mx.events.CollectionEventKind;
   import mx.events.PropertyChangeEvent;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.ChannelSet;
   import mx.messaging.MultiTopicConsumer;
   import mx.messaging.channels.PollingChannel;
   import mx.messaging.config.ServerConfig;
   import mx.messaging.events.ChannelEvent;
   import mx.messaging.events.ChannelFaultEvent;
   import mx.messaging.events.MessageAckEvent;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncRequest;
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.IResponder;
   import mx.rpc.Responder;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   
   [ResourceBundle("data")]
   [Event(name="conflict",type="mx.data.events.DataConflictEvent")]
   [Event(name="fault",type="mx.rpc.events.FaultEvent")]
   [Event(name="result",type="mx.rpc.events.ResultEvent")]
   public class DataStore extends EventDispatcher
   {
      
      public static const CQ_ONE_AT_A_TIME:int = 0;
      
      public static const CQ_AUTO:int = 1;
      
      public static const CQ_NOWAIT:int = 3;
      
      static var TOKEN_CHAIN:String = "__token_chain__";
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
      
      private static var _log:ILogger;
      
      private static var _sharedDataStores:Dictionary = new Dictionary(true);
       
      
      public var throwErrorOnIDChange:Boolean = true;
      
      public var detectConflictsOnRefresh:Boolean = true;
      
      private var lastSaveTime:int = 0;
      
      public var saveCacheMinIntervalMillis:int = 0;
      
      private var saveCacheTimer:Timer = null;
      
      private var _adapter:DataServiceAdapter;
      
      private var _offlineAdapter:DataServiceOfflineAdapter;
      
      private var _autoCommit:Boolean = true;
      
      private var _autoCommitPropertyChanges:Boolean = true;
      
      private var _autoCommitCollectionChanges:Boolean = true;
      
      private var _autoConnect:Boolean = true;
      
      private var _autoConnectTimer:Timer = null;
      
      private var _autoMerge:Boolean = true;
      
      private var _autoSaveCache:Boolean = false;
      
      private var _cacheId:String;
      
      private var _conflicts:Conflicts;
      
      private var commitInProgress:Boolean = false;
      
      private var dataServices:Object;
      
      private var _initialized:Boolean;
      
      private var _initializedCallbacks:Array;
      
      private var _sharedDataStore:Boolean = false;
      
      private var _id:String;
      
      private var _localStore:IDatabase;
      
      private var _logChanges:int = 0;
      
      private var producer:AsyncRequest;
      
      private var _ignoreCollectionUpdates:Boolean = false;
      
      private var _messageCache:DataMessageCache;
      
      private var _resolver:ConflictResolver;
      
      private var saveCacheAfterCommit:Boolean = false;
      
      private var executingSaveCache:Boolean = false;
      
      private var runtimeConfigured:Boolean = false;
      
      private var saveCacheWaiters:Array;
      
      private var _unmergedMessages:Array;
      
      private var _useTransactions:Boolean;
      
      private var _fallBackToLocalFill:Boolean;
      
      var dataStoreEventDispatcher:DataStoreEventDispatcher;
      
      public var autoConnectInterval:int = 5000;
      
      public var restoreCommittedUnsentBatchesOnFault:Boolean = false;
      
      private var _1403190867processingServerChanges:Boolean = false;
      
      public function DataStore(destination:String, useTransactions:Boolean, adapter:DataServiceAdapter = null, offlineAdapter:DataServiceOfflineAdapter = null)
      {
         this.dataServices = {};
         this._initializedCallbacks = [];
         this.saveCacheWaiters = new Array();
         super();
         _log = Log.getLogger("mx.data.DataStore");
         this._useTransactions = useTransactions;
         this.dataStoreEventDispatcher = new DataStoreEventDispatcher(this);
         this._conflicts = new Conflicts();
         this._conflicts.addEventListener(CollectionEvent.COLLECTION_CHANGE,this.conflictsCollectionChangeHandler);
         if(adapter == null)
         {
            this._adapter = new MessagingDataServiceAdapter(destination,this);
         }
         else
         {
            this._adapter = adapter;
            this.autoCommit = false;
         }
         this.producer = this._adapter.asyncRequest;
         this.producer.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.producerPropertyChangeHandler);
         this._adapter.dataStore = this;
         this._localStore = LocalStoreFactory.create();
         this.offlineAdapter = Boolean(offlineAdapter)?offlineAdapter:new DataServiceOfflineAdapter();
         this.offlineAdapter.localStore = this._localStore;
         this.offlineAdapter.dataStoreEventDispatcher = this.dataStoreEventDispatcher;
      }
      
      static function getSharedDataStore(destination:String, useTransactions:Boolean, channelSet:ChannelSet, adapter:DataServiceAdapter, offlineAdapter:DataServiceOfflineAdapter) : DataStore
      {
         var dataStoreId:Object = getDataStoreId(destination,useTransactions,channelSet);
         var result:DataStore = _sharedDataStores[dataStoreId];
         if(result == null)
         {
            result = new DataStore(destination,useTransactions,adapter,offlineAdapter);
            result._sharedDataStore = true;
            if(dataStoreId is String)
            {
               result.identifier = dataStoreId as String;
            }
            _sharedDataStores[dataStoreId] = result;
            if(Log.isDebug())
            {
               _log.debug("Creating shared data store with id: \'{0}\' for destination: \'{1}\'",dataStoreId,destination);
            }
            if(channelSet != null && destination != null)
            {
               resetDataStore(result,destination,useTransactions,null);
            }
         }
         else if(Log.isDebug())
         {
            _log.debug("Using shared data store with id \'{0}\' for destination \'{1}\'",dataStoreId,destination);
         }
         return result;
      }
      
      private static function resetDataStore(dataStore:DataStore, destination:String, useTransactions:Boolean, channelSet:ChannelSet) : void
      {
         var dataStoreId:Object = getDataStoreId(destination,useTransactions,channelSet);
         if(_sharedDataStores[dataStoreId] == null)
         {
            _sharedDataStores[dataStoreId] = dataStore;
            if(Log.isDebug())
            {
               _log.debug("Registering shared data store under default channel set for destination: " + destination + " with id: " + dataStoreId);
            }
         }
      }
      
      static function clearSharedDataStores() : void
      {
         _sharedDataStores = new Dictionary(true);
      }
      
      static function getDataStoreId(destination:String, useTransactions:Boolean, channelSet:ChannelSet) : Object
      {
         var dataStoreId:Object = null;
         var channelIds:Array = null;
         if(channelSet == null)
         {
            dataStoreId = getId(ServerConfig.getChannelIdList(destination),useTransactions);
         }
         else
         {
            channelIds = getChannelIds(channelSet);
            if(channelIds.length == 0)
            {
               dataStoreId = channelSet;
            }
            else
            {
               dataStoreId = getId(channelIds,useTransactions);
            }
         }
         return dataStoreId;
      }
      
      private static function getChannelIds(channelSet:ChannelSet) : Array
      {
         var channelIds:Array = channelSet.channelIds;
         var result:Array = [];
         for(var i:int = 0; i < channelIds.length; i++)
         {
            if(channelIds[i] == null)
            {
               result.push(channelSet.channels[i].uri);
            }
            else
            {
               result.push(channelIds[i]);
            }
         }
         return result;
      }
      
      private static function getId(ids:Array, useTransactions:Boolean) : String
      {
         var channelIds:String = ids.join(":");
         return channelIds + ":" + useTransactions;
      }
      
      function get offlineAdapter() : DataServiceOfflineAdapter
      {
         return this._offlineAdapter;
      }
      
      function set offlineAdapter(value:DataServiceOfflineAdapter) : void
      {
         this._offlineAdapter = value;
      }
      
      public function get fallBackToLocalFill() : Boolean
      {
         return this._fallBackToLocalFill;
      }
      
      public function set fallBackToLocalFill(value:Boolean) : void
      {
         this._fallBackToLocalFill = value;
      }
      
      public function get autoCommit() : Boolean
      {
         return this._autoCommit;
      }
      
      public function set autoCommit(value:Boolean) : void
      {
         var old:Boolean = this._autoCommit;
         this._autoCommit = value;
         if(!old && value && this.isInitialized)
         {
            this.commit();
         }
      }
      
      function restoreAutoCommit(ac:Boolean) : void
      {
         this._autoCommit = ac;
      }
      
      public function get autoCommitPropertyChanges() : Boolean
      {
         return this.autoCommit && this._autoCommitPropertyChanges;
      }
      
      public function set autoCommitPropertyChanges(value:Boolean) : void
      {
         this._autoCommitPropertyChanges = value;
      }
      
      public function get autoCommitCollectionChanges() : Boolean
      {
         return this.autoCommit && this._autoCommitCollectionChanges;
      }
      
      public function set autoCommitCollectionChanges(value:Boolean) : void
      {
         this._autoCommitCollectionChanges = value;
      }
      
      public function get autoConnect() : Boolean
      {
         return this._autoConnect;
      }
      
      public function set autoConnect(value:Boolean) : void
      {
         if(this._autoConnect != value)
         {
            this._autoConnect = value;
            if(value)
            {
               this.connect();
            }
            else if(this._autoConnectTimer != null)
            {
               this._autoConnectTimer.stop();
               this._autoConnectTimer = null;
            }
         }
      }
      
      public function get encryptLocalCache() : Boolean
      {
         return this._localStore && this._localStore.encryptLocalCache;
      }
      
      public function set encryptLocalCache(value:Boolean) : void
      {
         if(this._localStore)
         {
            this._localStore.encryptLocalCache = value;
         }
      }
      
      public function get autoMerge() : Boolean
      {
         return this._autoMerge;
      }
      
      public function set autoMerge(value:Boolean) : void
      {
         var oldValue:Boolean = this._autoMerge;
         this._autoMerge = value;
         if(!oldValue && value)
         {
            this.merge();
         }
      }
      
      public function get autoSaveCache() : Boolean
      {
         return this._autoSaveCache;
      }
      
      public function set autoSaveCache(value:Boolean) : void
      {
         if(this._autoSaveCache != value)
         {
            if(value && this.isInitialized)
            {
               this.saveCache(null);
            }
         }
         this._autoSaveCache = value;
      }
      
      function restoreAutoSaveCache(value:Boolean) : void
      {
         this._autoSaveCache = value;
      }
      
      public function get cacheID() : String
      {
         return this._cacheId;
      }
      
      public function set cacheID(value:String) : void
      {
         if(this._cacheId != value)
         {
            if(this.commitInProgress)
            {
               throw new DataServiceError("CacheID cannot be changed while a commit is in progress.");
            }
            this._initialized = false;
            this._cacheId = value;
            this.offlineAdapter.close();
            if(this._cacheId)
            {
               this.offlineAdapter.initializeCacheStore();
            }
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get uncommittedBatches() : ArrayCollection
      {
         return this.messageCache.uncommittedBatches;
      }
      
      [Bindable(event="propertyChange")]
      public function get currentBatch() : MessageBatch
      {
         return this.messageCache.currentBatch;
      }
      
      public function set commitQueueMode(cqm:int) : void
      {
         if(cqm > CQ_NOWAIT || cqm < 0)
         {
            throw new DataServiceError("DataStore.commitQueueMode must be: CQ_ONE_AT_A_TIME, CQ_AUTO, or CQ_NOWAIT");
         }
         this.messageCache.commitQueueMode = cqm;
      }
      
      public function get commitQueueMode() : int
      {
         return this.messageCache.commitQueueMode;
      }
      
      [Bindable(event="propertyChange")]
      public function get connected() : Boolean
      {
         return this._adapter.connected;
      }
      
      [Bindable(event="propertyChange")]
      public function get conflicts() : Conflicts
      {
         return this._conflicts;
      }
      
      [Bindable(event="propertyChange")]
      public function get commitRequired() : Boolean
      {
         if(this._messageCache != null)
         {
            return this._messageCache.commitRequired;
         }
         return false;
      }
      
      public function commitRequiredOn(item:Object) : Boolean
      {
         if(this._messageCache == null || item == null)
         {
            return false;
         }
         return this._messageCache.commitRequiredOn(item);
      }
      
      public function get destination() : String
      {
         return this.producer.destination;
      }
      
      public function get identifier() : String
      {
         return this._id;
      }
      
      public function set identifier(value:String) : void
      {
         this._id = value;
      }
      
      [Bindable(event="propertyChange")]
      public function get isInitialized() : Boolean
      {
         return this._initialized;
      }
      
      [Bindable(event="propertyChange")]
      public function get mergeRequired() : Boolean
      {
         if(this.isInitialized)
         {
            return this.unmergedMessages.length > 0;
         }
         return false;
      }
      
      public function get priority() : int
      {
         return this.producer.priority;
      }
      
      public function set priority(value:int) : void
      {
         this.producer.priority = value;
      }
      
      public function get requestTimeout() : int
      {
         return this.producer.requestTimeout;
      }
      
      public function set requestTimeout(value:int) : void
      {
         this.producer.requestTimeout = value;
      }
      
      public function commit(itemsOrCollections:Array = null, cascadeCommit:Boolean = false) : AsyncToken
      {
         return this.internalCommit(null,itemsOrCollections,cascadeCommit);
      }
      
      public function connect() : AsyncToken
      {
         var result:AsyncToken = null;
         var dispatcher:IEventDispatcher = null;
         result = new AsyncToken(null);
         dispatcher = this;
         var localConnect:Function = function():void
         {
            internalConnect(dispatcher,result);
         };
         if(this.isInitialized)
         {
            localConnect();
         }
         else
         {
            this.initialize(localConnect,localConnect);
         }
         return result;
      }
      
      private function connectServices() : void
      {
         var d:* = null;
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).reconnect(null);
         }
      }
      
      public function disconnect() : void
      {
         var d:* = null;
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).disconnect();
         }
      }
      
      public function getCacheIDs(view:ListCollectionView) : AsyncToken
      {
         var result:AsyncToken = new AsyncToken(null);
         this.internalGetCacheIDs(this,view,result);
         return result;
      }
      
      public function logout() : void
      {
         this.producer.logout();
         this.messageCache.clear();
      }
      
      public function merge() : void
      {
         var pending:Boolean = false;
         var d:* = null;
         var msg:DataMessage = null;
         if(this.isInitialized)
         {
            pending = this.unmergedMessages.length > 0;
            while(this.unmergedMessages.length > 0)
            {
               msg = DataMessage(this.unmergedMessages.shift());
               this.dataServices[msg.destination].mergeMessage(msg);
            }
            for(d in this.dataServices)
            {
               ConcreteDataService(this.dataServices[d]).processPendingRequests();
            }
            if(pending)
            {
               dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"mergeRequired",true,false));
            }
         }
      }
      
      public function refresh() : AsyncToken
      {
         var d:* = null;
         var tokens:Array = [];
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).internalRefresh(tokens);
         }
         if(tokens.length == 0)
         {
            return null;
         }
         return tokens[tokens.length - 1];
      }
      
      public function release(clear:Boolean = true, copyStillManagedItems:Boolean = true) : void
      {
         var d:* = null;
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).release(clear,copyStillManagedItems);
         }
      }
      
      public function revertChanges() : Boolean
      {
         if(this.isInitialized)
         {
            return this.doRevertChanges(null,null);
         }
         return false;
      }
      
      public function revertChangesForCollection(collection:ListCollectionView) : Boolean
      {
         var cds:ConcreteDataService = null;
         if(this.isInitialized)
         {
            if(collection.list is DataList)
            {
               cds = DataList(collection.list).service;
               return this.doRevertChanges(cds,null,collection);
            }
            throw new ArgumentError("revertChangesForCollection called on collection which is not managed");
         }
         return false;
      }
      
      public function setCredentials(username:String, password:String) : void
      {
         this.producer.setCredentials(username,password);
      }
      
      public function setRemoteCredentials(username:String, password:String) : void
      {
         this.producer.setRemoteCredentials(username,password);
      }
      
      public function get channelSet() : ChannelSet
      {
         return this.producer.channelSet;
      }
      
      public function set channelSet(value:ChannelSet) : void
      {
         var d:* = null;
         var dataStoreId:Object = null;
         if(this.producer.channelSet != value)
         {
            this.producer.channelSet = value;
            if(value != null && this._sharedDataStore)
            {
               dataStoreId = getDataStoreId(null,this.useTransactions,value);
               _sharedDataStores[dataStoreId] = this;
               if(Log.isDebug())
               {
                  _log.debug("Changing channelSet of a shared data store.  It is now used also for id: " + dataStoreId);
               }
            }
            for(d in this.dataServices)
            {
               ConcreteDataService(this.dataServices[d]).channelSet = value;
            }
         }
      }
      
      function getStatusInfo(dumpCache:Boolean) : String
      {
         var d:* = null;
         var result:String = "DataStore information for: " + this.identifier + "\n  uncommitted messages:  " + this.messageCache.currentBatch.length + "\n  uncommittedBatches: " + this.messageCache.uncommittedBatches.length + "\n  committed not acked batches: " + this.messageCache.committed.length + "\n  conflicts: " + this.conflicts.length + "\n  unmerged messages: " + this.unmergedMessages.length + "\n  destinations [\n";
         for(d in this.dataServices)
         {
            result = result + ("  " + ConcreteDataService(this.dataServices[d]).getStatusInfo(dumpCache) + "\n");
         }
         result = result + "  ]";
         return result;
      }
      
      function get producerClientId() : String
      {
         return this.producer.clientId;
      }
      
      function disableDelayedReleases() : void
      {
         var d:* = null;
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).disableDelayedReleases();
         }
      }
      
      function enableDelayedReleases() : void
      {
         var d:* = null;
         for(d in this.dataServices)
         {
            ConcreteDataService(this.dataServices[d]).enableDelayedReleases();
         }
      }
      
      function disableLogging() : void
      {
         this._logChanges--;
      }
      
      function enableLogging() : void
      {
         this._logChanges++;
         if(this._logChanges > 0)
         {
            this._logChanges = 0;
         }
      }
      
      function get logChanges() : int
      {
         return this._logChanges;
      }
      
      function internalCommit(ds:ConcreteDataService, itemsOrCollections:Array, cascadeCommit:Boolean, batch:MessageBatch = null) : AsyncToken
      {
         var token:AsyncToken = null;
         var success:Function = null;
         var failed:Function = null;
         if(this.isInitialized || this.mergeRequired || !this.conflicts.resolved)
         {
            return this.doCommit(CommitResponder,ds,false,null,itemsOrCollections,cascadeCommit,batch);
         }
         token = new AsyncToken(null);
         success = function():void
         {
            doCommit(CommitResponder,ds,false,token,itemsOrCollections,cascadeCommit);
         };
         failed = function(info:Object, tk:Object):void
         {
            var errMsg:ErrorMessage = new ErrorMessage();
            errMsg.faultCode = "Client.Commit.Failed";
            errMsg.faultString = "Commit operation failed because a connection can\'t be established.";
            errMsg.faultDetail = info.toString();
            var event:MessageFaultEvent = MessageFaultEvent.createEvent(errMsg);
            token.setMessage(errMsg);
            dataStoreEventDispatcher.dispatchCacheFaultEvent(ds != null?ds:this,event,token);
         };
         this.initialize(success,failed);
         return token;
      }
      
      function internalConnect(dispatcher:IEventDispatcher, token:AsyncToken) : void
      {
         var producerConnectHandler:Function = null;
         producerConnectHandler = function(event:Event):void
         {
            producer.removeEventListener(ChannelEvent.CONNECT,producerConnectHandler);
            producer.removeEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
            if(token != null)
            {
               dataStoreEventDispatcher.dispatchResultEvent(dispatcher,MessageEvent.createEvent(MessageEvent.RESULT,null),token,connected);
            }
            if(!connected)
            {
               if(autoConnect)
               {
                  enableAutoConnectTimer();
               }
            }
            else
            {
               connectServices();
               disableAutoConnectTimer();
            }
         };
         if(this.connected)
         {
            if(token != null)
            {
               new AsyncDispatcher(this.dataStoreEventDispatcher.dispatchResultEvent,[dispatcher,MessageEvent.createEvent(MessageEvent.RESULT,null),token,this.connected],1);
            }
         }
         else
         {
            this.producer.addEventListener(ChannelEvent.CONNECT,producerConnectHandler);
            this.producer.addEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
            this.producer.connect();
         }
      }
      
      private function enableAutoConnectTimer() : void
      {
         if(this._autoConnectTimer == null)
         {
            this._autoConnectTimer = new Timer(this.autoConnectInterval);
            this._autoConnectTimer.addEventListener(TimerEvent.TIMER,this.connectHandler);
            this._autoConnectTimer.start();
            if(Log.isDebug())
            {
               _log.debug("Enabled autoConnect timer: " + this.autoConnectInterval);
            }
         }
      }
      
      private function connectHandler(event:TimerEvent) : void
      {
         if(Log.isDebug())
         {
            _log.debug("Connect attempt for autoConnect");
         }
         if(this.connected)
         {
            this.disableAutoConnectTimer();
         }
         else
         {
            this.connect();
         }
      }
      
      private function disableAutoConnectTimer() : void
      {
         if(this._autoConnectTimer != null)
         {
            this._autoConnectTimer.stop();
            this._autoConnectTimer = null;
            if(Log.isDebug())
            {
               _log.debug("Disabling auto-connect timer - connected: " + this.connected);
            }
         }
      }
      
      function internalGetCacheIDs(dispatcher:IEventDispatcher, view:ListCollectionView, token:AsyncToken) : void
      {
         this.offlineAdapter.internalGetCacheIDs(dispatcher,view,token);
      }
      
      function get log() : ILogger
      {
         return _log;
      }
      
      function get messageCache() : DataMessageCache
      {
         if(this._messageCache == null)
         {
            this.messageCache = new DataMessageCache();
         }
         return this._messageCache;
      }
      
      function set messageCache(value:DataMessageCache) : void
      {
         if(this._messageCache != null)
         {
            this._messageCache.removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,dispatchEvent);
         }
         this._messageCache = value;
         this._messageCache.currentBatch.dataStore = this._messageCache.dataStore = this;
         if(value != null)
         {
            value.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,dispatchEvent,false,0,true);
         }
      }
      
      function get useTransactions() : Boolean
      {
         return this._useTransactions;
      }
      
      function set useTransactions(value:Boolean) : void
      {
         if(this._useTransactions != value)
         {
            this._useTransactions = value;
         }
      }
      
      function count(countMsg:IMessage, responder:IResponder, token:AsyncToken) : void
      {
         this.invoke(countMsg,responder);
      }
      
      function fill(dataList:DataList, cds:ConcreteDataService, dataMsg:IMessage, responder:IResponder, token:AsyncToken, localFill:Boolean = false) : void
      {
         var ds:DataStore = null;
         var smo:Boolean = false;
         var singleResult:Boolean = false;
         var fillInternal:Function = null;
         var fillFailed:Function = null;
         var localQuerySuccess:Function = null;
         var localQueryFailure:Function = null;
         ds = this;
         smo = dataList.smo;
         singleResult = dataList.singleResult;
         fillInternal = function(event:Object, async:Boolean):void
         {
            var singleItem:Object = null;
            var offlineResultMessage:SequencedMessage = null;
            var localData:Boolean = false;
            var getLocalSMO:Boolean = false;
            var hasOfflineResult:Boolean = false;
            var refs:Array = null;
            var identity:Object = null;
            var uid:String = null;
            var dataMessage:DataMessage = null;
            var propSpecifier:PropertySpecifier = null;
            var localItems:Array = null;
            var properties:Array = null;
            var parentItem:Object = null;
            var referencedIdTable:Object = null;
            var property:String = null;
            var association:ManagedAssociation = null;
            var associationDataList:DataList = null;
            var referencedIds:Array = null;
            var referencedIdsCopy:Array = null;
            var fillParameters:Array = null;
            var internalToken:AsyncToken = null;
            var dsOfflineAdapter:DataServiceOfflineAdapter = cds.offlineAdapter;
            var descriptor:CacheDataDescriptor = null;
            try
            {
               descriptor = restoreDataList(dataList,cds);
            }
            catch(e:ItemPendingError)
            {
               e.addResponder(new ItemResponder(fillInternal,fillFailed,true));
            }
            if(!dsOfflineAdapter.isQuerySupported())
            {
               localData = cacheID != null && !dsOfflineAdapter.isStoreEmpty();
               getLocalSMO = localData && smo && descriptor == null;
               hasOfflineResult = false;
               if(!getLocalSMO)
               {
                  if(descriptor != null)
                  {
                     if(Log.isDebug())
                     {
                        _log.debug("Restoring cached query: " + descriptor.toString());
                     }
                     descriptor.setTimeAttributes(null,new Date());
                     dataList.setReferences(descriptor.references,false);
                     try
                     {
                        dsOfflineAdapter.beginTransaction();
                        dsOfflineAdapter.saveQuery(dataList.collectionId,descriptor);
                        dsOfflineAdapter.commitLocalStore(cds,token,true);
                        dataList.cacheStale = false;
                     }
                     catch(e:Error)
                     {
                        if(Log.isError())
                        {
                           log.error("Attempt to update descriptor timestamp for data from the local cache failed." + e + " stack: " + e.getStackTrace());
                        }
                     }
                     if(descriptor.synced)
                     {
                        dataList.sequenceIdStale = true;
                        cds.staleSequencesCount++;
                     }
                     hasOfflineResult = true;
                  }
                  else
                  {
                     hasOfflineResult = dataList.cacheRestored;
                  }
               }
               else
               {
                  singleItem = cds.getLocalItem(dataList.fillParameters);
                  if(singleItem != null)
                  {
                     refs = [];
                     refs.push(IManaged(singleItem).uid);
                     dataList.references = refs;
                     hasOfflineResult = true;
                  }
               }
               if(hasOfflineResult)
               {
                  offlineResultMessage = new SequencedMessage();
                  if(smo || singleResult)
                  {
                     offlineResultMessage.body = dataList.getItemAt(0);
                  }
                  else
                  {
                     offlineResultMessage.body = dataList.localItems;
                  }
               }
               offlineResultReady(offlineResultMessage,async);
            }
            else if(smo)
            {
               if(!connected && fallBackToLocalFill)
               {
                  identity = dataList.fillParameters;
                  uid = identity is String?String(identity):cds.metadata.getUID(identity);
                  restoreReferencedItems(cds,null,[uid],false);
                  singleItem = cds.getItem(uid);
                  if(singleItem)
                  {
                     dataList.references = [uid];
                     offlineResultMessage = new SequencedMessage();
                     offlineResultMessage.body = singleItem;
                  }
               }
               offlineResultReady(offlineResultMessage,async);
            }
            else if(localFill || !connected && fallBackToLocalFill)
            {
               dataMessage = dataMsg as DataMessage;
               propSpecifier = cds.getMessagePropertySpecifier(dataMessage);
               if(dataMessage.operation == DataMessage.PAGE_ITEMS_OPERATION)
               {
                  localItems = dataList.localItems;
                  properties = propSpecifier.extraProperties;
                  for each(parentItem in localItems)
                  {
                     referencedIdTable = Managed.getReferencedIds(parentItem);
                     if(referencedIdTable)
                     {
                        for each(property in properties)
                        {
                           association = cds.metadata.associations[property];
                           if(association)
                           {
                              associationDataList = cds.getDataListForAssociation(parentItem,association);
                              if(associationDataList)
                              {
                                 referencedIds = referencedIdTable[property];
                                 if(referencedIds is Array)
                                 {
                                    referencedIdsCopy = ObjectUtil.copy(referencedIds) as Array;
                                    associationDataList.setReferences(referencedIdsCopy);
                                    restoreReferencedItems(association.service,associationDataList,associationDataList.references,true);
                                 }
                                 else
                                 {
                                    associationDataList.fetched = true;
                                 }
                              }
                           }
                        }
                     }
                  }
                  offlineResultMessage = new SequencedMessage();
                  offlineResultMessage.body = localItems;
                  offlineResultReady(offlineResultMessage,async);
               }
               else
               {
                  fillParameters = ArrayUtil.toArray(dataList.fillParameters);
                  internalToken = dsOfflineAdapter.executeOfflineQuery(propSpecifier,fillParameters,0,-1);
                  internalToken.addResponder(new Responder(localQuerySuccess,localQueryFailure));
               }
            }
            else
            {
               offlineResultReady(offlineResultMessage,async);
            }
         };
         var offlineResultReady:Function = function(offlineResultMessage:SequencedMessage, async:Boolean):void
         {
            var offlineResultEvent:MessageEvent = null;
            if(offlineResultMessage)
            {
               offlineResultEvent = MessageEvent.createEvent(MessageEvent.RESULT,offlineResultMessage);
            }
            var result:Object = dataList.view;
            if((smo || singleResult) && offlineResultMessage)
            {
               result = offlineResultMessage.body;
            }
            if((!connected || localFill) && offlineResultEvent)
            {
               if(token.request)
               {
                  if(async)
                  {
                     dataList.removeRequest(token.request,offlineResultMessage);
                  }
                  else
                  {
                     new AsyncDispatcher(dataList.removeRequest,[token.request,offlineResultMessage],1);
                  }
               }
               if(async)
               {
                  cds.dispatchResultEvent(offlineResultEvent,token,result,true);
               }
               else
               {
                  new AsyncDispatcher(cds.dispatchResultEvent,[offlineResultEvent,token,result,true],1);
               }
               offlineResultEvent = null;
            }
            if(!localFill)
            {
               if(offlineResultEvent != null)
               {
                  responder = new CachedQueryResponder(ds,cds,ITokenResponder(responder),offlineResultEvent,token,result);
               }
               invoke(dataMsg,responder);
            }
         };
         fillFailed = function(info:Object):void
         {
            var err:Error = null;
            if(!connected && !autoConnect)
            {
               err = new Error(info.details);
               dataStoreEventDispatcher.dispatchFileAccessFault(err,cds,token);
            }
            else
            {
               invoke(dataMsg,responder);
            }
         };
         localQuerySuccess = function(event:ResultEvent):void
         {
            var item:IManaged = null;
            var offlineResultMessage:SequencedMessage = null;
            var uid:String = null;
            var uids:Array = [];
            var restoredItems:Dictionary = new Dictionary();
            var items:Array = event.result as Array;
            for each(item in items)
            {
               uid = item.uid;
               uids.push(uid);
               restoredItems[uid] = item;
            }
            restoreReferencedItems(cds,null,null,false,restoredItems);
            dataList.setReferences(uids);
            offlineResultMessage = new SequencedMessage();
            offlineResultMessage.sequenceId = -1;
            offlineResultMessage.sequenceSize = items.length;
            offlineResultMessage.body = items;
            offlineResultReady(offlineResultMessage,true);
         };
         localQueryFailure = function(event:MessageEvent):void
         {
            responder.fault(event.clone());
         };
         if(dataMsg is DataMessage && DataMessage(dataMsg).operation == DataMessage.PAGE_OPERATION)
         {
            offlineResultReady(null,false);
         }
         else
         {
            fillInternal(null,false);
         }
      }
      
      function reloadDataList(dataList:DataList, cds:ConcreteDataService) : void
      {
         var descriptor:CacheDataDescriptor = this.restoreDataList(dataList,cds);
         if(descriptor)
         {
            dataList.setReferences(descriptor.references,false);
         }
      }
      
      private function restoreDataList(dataList:DataList, cds:ConcreteDataService) : CacheDataDescriptor
      {
         var deletedItems:Array = null;
         var i:int = 0;
         var item:IManaged = null;
         var idx:int = 0;
         var descriptor:CacheDataDescriptor = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = cds.offlineAdapter;
         var localData:Boolean = this.cacheID != null && !dsOfflineAdapter.isStoreEmpty();
         if(localData && !dataList.cacheRestoreAttempted)
         {
            dataList.cacheRestoreAttempted = true;
            descriptor = CacheDataDescriptor(dsOfflineAdapter.restoreQuery(dataList.collectionId));
            dataList.inCache = descriptor != null;
            if(descriptor != null)
            {
               deletedItems = this.restoreReferencedItems(cds,dataList,descriptor.references,false);
               if(deletedItems != null)
               {
                  for(i = 0; i < deletedItems.length; i++)
                  {
                     item = IManaged(deletedItems[i]);
                     idx = ArrayUtil.getItemIndex(item.uid,descriptor.references);
                     dataList.logDeleteFromCollectionForDeletedItem(item,idx);
                     descriptor.references.splice(idx,1);
                  }
               }
               dataList.fillTimestamp = descriptor.lastFilled;
            }
            return descriptor;
         }
         return null;
      }
      
      function logStatus(opName:String) : void
      {
         if(Log.isDebug() && this.isInitialized)
         {
            _log.debug(this.getStatusInfo(false));
         }
      }
      
      function processPageRequest(dataList:DataList, ds:ConcreteDataService, dataMsg:IMessage, responder:IResponder, token:AsyncToken) : void
      {
         this.fill(dataList,ds,dataMsg,responder,token);
      }
      
      function addDataService(ds:ConcreteDataService) : void
      {
         var event:PropertyChangeEvent = null;
         var configCol:Object = null;
         if(Log.isDebug())
         {
            _log.debug("Adding data service: " + ds.destination + " to the data store: " + this._id + " initialized: " + this._initialized);
         }
         ds.channelSet = this.channelSet;
         if(ds.runtimeConfigured)
         {
            this.runtimeConfigured = true;
         }
         if(this._adapter is MessagingDataServiceAdapter)
         {
            if(!ds.runtimeConfigured || ds.initialized)
            {
               ServerConfig.checkChannelConsistency(this.destination,ds.destination);
            }
         }
         this.dataServices[ds.destination] = ds;
         if(this.isInitialized)
         {
            if(!ds.initialized)
            {
               configCol = null;
               configCol = this.getConfigCollection(ds);
               if(!ds.metadata.initialize(null,null,configCol))
               {
                  throw new DataServiceError("Unable to initialize destination: " + ds.destination + " added after data store has been initialized");
               }
            }
            if(!ds.metadata.validated)
            {
               ds.metadata.validate(this,ds);
            }
         }
         addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,ds.dispatchEvent);
         event = PropertyChangeEvent.createUpdateEvent(this,"commitRequired",!this.commitRequired,this.commitRequired);
         dispatchEvent(event);
         event = PropertyChangeEvent.createUpdateEvent(this,"mergeRequired",!this.mergeRequired,this.mergeRequired);
         dispatchEvent(event);
      }
      
      function addUnmergedMessage(ds:ConcreteDataService, msg:DataMessage) : void
      {
         this.unmergedMessages.push(msg);
         if(this.unmergedMessages.length == 1)
         {
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"mergeRequired",false,true));
         }
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
      }
      
      function attemptSaveAterCommit(force:Boolean = false) : void
      {
         this.commitInProgress = false;
         if((this.saveCacheAfterCommit || force) && this.cacheID && this.offlineAdapter.isConnected())
         {
            this.saveCache(this,true);
         }
      }
      
      function clearCache(dispatcher:IEventDispatcher, token:AsyncToken) : void
      {
         var ds:ConcreteDataService = null;
         this.offlineAdapter.clearCache(dispatcher,token,this.isInitialized);
         for each(ds in this.dataServices)
         {
            ds.metadata.serverConfigChanged = true;
         }
      }
      
      function clearCacheValue(dispatcher:IEventDispatcher, value:Object, token:AsyncToken) : void
      {
         var col:ArrayCollection = null;
         var ds:ConcreteDataService = null;
         var faultHandler:Function = null;
         var evnt:MessageEvent = null;
         col = new ArrayCollection();
         var cdResponse:AsyncToken = new AsyncToken(null);
         if(dispatcher is ConcreteDataService)
         {
            ds = ConcreteDataService(dispatcher);
         }
         else
         {
            ds = value is ListCollectionView?DataList(ListCollectionView(value).list).service:this.getDataServiceForValue(value);
         }
         faultHandler = function(event:FaultEvent, o:Object):void
         {
            o.applyFault(event);
         };
         if(!this.offlineAdapter.isStoreEmpty())
         {
            cdResponse.addResponder(new AsyncResponder(function(event:ResultEvent, t:Object):void
            {
               var tkn:* = new AsyncToken(null);
               tkn.addResponder(new AsyncResponder(function(event:ResultEvent, o:Object):void
               {
                  o.applyResult(event);
                  var et:* = MessageEvent.createEvent(MessageEvent.RESULT,null);
                  new AsyncDispatcher(dataStoreEventDispatcher.dispatchResultEvent,[ds,et,token,null,true],1);
               },faultHandler,t));
               clearCacheData(ds,CacheDataDescriptor(col.getItemAt(0)),tkn);
            },faultHandler,token));
            this.getCacheDescriptors(ds,col,0,value,cdResponse);
         }
         else
         {
            evnt = MessageEvent.createEvent(MessageEvent.RESULT,null);
            new AsyncDispatcher(this.dataStoreEventDispatcher.dispatchResultEvent,[ds,evnt,token,null,true],1);
         }
      }
      
      function clearCacheData(ds:ConcreteDataService, descriptor:CacheDataDescriptor, token:AsyncToken) : void
      {
         this.offlineAdapter.clearCacheData(this,ds,descriptor,token);
      }
      
      function commitResultHandler(messages:Array, token:AsyncToken, batch:MessageBatch) : void
      {
         var currentMsg:AsyncMessage = null;
         var msg:DataMessage = null;
         var orgMsg:DataMessage = null;
         var cds:ConcreteDataService = null;
         var smsg:SequencedMessage = null;
         var dataList:DataList = null;
         var createToken:Object = null;
         var ucmsg:UpdateCollectionMessage = null;
         var serverOverride:UpdateCollectionMessage = null;
         var ucMsgs:Array = null;
         var j:int = 0;
         var revert:Boolean = false;
         var serverOverrideMsgs:Array = [];
         batch.updateNewIdentities(messages);
         var pendingServerMessages:Object = {};
         for(var i:uint = 0; i < messages.length; i++)
         {
            currentMsg = messages[i];
            if(currentMsg is SequencedMessage)
            {
               smsg = SequencedMessage(currentMsg);
               msg = smsg.dataMessage;
               cds = this.getDataService(msg.destination);
               if(msg.operation == DataMessage.CREATE_AND_SEQUENCE_OPERATION)
               {
                  msg.operation = DataMessage.CREATE_OPERATION;
               }
               cds.processCommitMessage(msg,batch.getCacheItem(msg.messageId).message,messages,pendingServerMessages);
               dataList = new DataList(cds);
               dataList.fillParameters = msg.identity;
               dataList.smo = true;
               dataList.processSequence(smsg.body as Array,cds.includeAllSpecifier,0,smsg.sequenceProxies,null,null,true,false,null,null,false,false);
               if(smsg.sequenceId == -1)
               {
                  dataList.sequenceId = cds.getNewClientSequenceId();
               }
               else
               {
                  dataList.sequenceId = smsg.sequenceId;
                  if(smsg.sequenceId >= 0 && !dataList.sequenceAutoSubscribed)
                  {
                     cds.autoSubscribe();
                     dataList.sequenceAutoSubscribed = true;
                  }
               }
               dataList.setSequenceSize(smsg.sequenceSize);
               if(token[TOKEN_CHAIN] != null && (createToken = token[TOKEN_CHAIN][msg.messageId]) != null)
               {
                  dataList.itemReference = ItemReference(createToken);
               }
            }
            else if(currentMsg is DataMessage && DataMessage(currentMsg).isCreate())
            {
               msg = DataMessage(currentMsg);
               cds = this.getDataService(msg.destination);
               orgMsg = batch.getMessage(msg.messageId);
               if(orgMsg == null)
               {
                  cds.mergeMessage(msg);
               }
               else
               {
                  cds.processCommitMessage(msg,orgMsg,messages,pendingServerMessages);
               }
            }
         }
         for(i = 0; i < messages.length; i++)
         {
            currentMsg = messages[i];
            if(currentMsg is DataMessage)
            {
               msg = DataMessage(currentMsg);
               cds = this.getDataService(msg.destination);
               if(msg is UpdateCollectionMessage)
               {
                  ucmsg = UpdateCollectionMessage(msg);
                  if(ucmsg.updateMode == UpdateCollectionMessage.SERVER_OVERRIDE)
                  {
                     serverOverrideMsgs.push(ucmsg);
                  }
                  else
                  {
                     serverOverride = null;
                     if(ucmsg.updateMode == UpdateCollectionMessage.SERVER_UPDATE)
                     {
                        for(j = 0; j < serverOverrideMsgs.length; j++)
                        {
                           if(ObjectUtil.compare(serverOverrideMsgs[j].collectionId,ucmsg.collectionId) == 0)
                           {
                              serverOverride = serverOverrideMsgs[j];
                              serverOverrideMsgs.splice(j,1);
                              break;
                           }
                        }
                     }
                     ucMsgs = batch.getUpdateCollectionMessages(ucmsg.destination,ucmsg.collectionId);
                     if(ucMsgs.length == 0)
                     {
                        orgMsg = batch.getMessage(ucmsg.messageId);
                        if(orgMsg != null)
                        {
                           ucMsgs = [orgMsg];
                        }
                     }
                     cds.processUpdateCollection(ucmsg.collectionId,ucmsg,ucMsgs.length == 0?null:ucMsgs[0],serverOverride);
                  }
               }
               else if(!msg.isCreate())
               {
                  orgMsg = batch.getMessage(msg.messageId);
                  if(orgMsg == null)
                  {
                     cds.mergeMessage(msg);
                  }
                  else
                  {
                     cds.processCommitMessage(msg,orgMsg,messages,pendingServerMessages);
                  }
               }
            }
         }
         for(i = 0; i < serverOverrideMsgs.length; i++)
         {
            cds.processUpdateCollection(serverOverrideMsgs[i].collectionId,null,null,serverOverrideMsgs[i]);
         }
         for(i = 0; i < messages.length; i++)
         {
            if(messages[i] is UpdateCollectionMessage)
            {
               cds = this.getDataService(msg.destination);
               ucmsg = UpdateCollectionMessage(messages[i]);
               revert = ucmsg.updateMode == UpdateCollectionMessage.SERVER_OVERRIDE;
               dataList = cds.getDataListWithCollectionId(ucmsg.collectionId);
               if(dataList != null)
               {
                  dataList.releaseItemsFromUpdateCollection(ucmsg,revert);
               }
            }
         }
      }
      
      function disconnectDataStore() : void
      {
         var d:* = null;
         var ds:ConcreteDataService = null;
         var okToDisconnect:Boolean = true;
         for(d in this.dataServices)
         {
            ds = this.dataServices[d] as ConcreteDataService;
            if(ds.connected)
            {
               okToDisconnect = false;
               break;
            }
         }
         if(okToDisconnect)
         {
            this.producer.disconnect();
         }
      }
      
      function doAutoCommit(commitResponderClass:Class, createToken:Boolean = false, createItemReference:Boolean = false, token:AsyncToken = null) : AsyncToken
      {
         if(this.autoCommit)
         {
            token = this.doCommit(commitResponderClass,null,createItemReference,token);
            if(token == null && createToken)
            {
               if(createItemReference)
               {
                  token = new ItemReference(null);
               }
               else
               {
                  token = new AsyncToken(null);
               }
            }
         }
         else if(createToken)
         {
            if(createItemReference)
            {
               token = new ItemReference(null);
            }
            else
            {
               token = new AsyncToken(null);
            }
         }
         if(token != null)
         {
            this.currentBatch.tokenCache.push(token);
         }
         return token;
      }
      
      function getOrCreateToken(message:DataMessage) : AsyncToken
      {
         var token:AsyncToken = this.currentBatch.tokenCacheIndex[message.messageId];
         if(token == null)
         {
            token = new AsyncToken(null);
            token.setMessage(message);
            this.currentBatch.tokenCache.push(token);
            this.currentBatch.tokenCacheIndex[token.message.messageId] = token;
         }
         return token;
      }
      
      function doCommit(param1:Class, param2:ConcreteDataService, param3:Boolean = false, param4:AsyncToken = null, param5:Array = null, param6:Boolean = false, param7:MessageBatch = null) : AsyncToken
      {
         var _loc8_:DataMessage = null;
         var _loc9_:Boolean = false;
         var _loc10_:IViewCursor = null;
         var _loc11_:Array = null;
         var _loc12_:MessageBatch = null;
         var _loc13_:int = 0;
         var _loc14_:int = 0;
         var _loc15_:* = null;
         var _loc16_:ConcreteDataService = null;
         if(this.mergeRequired && this.commitRequired)
         {
            throw new DataServiceError(resourceManager.getString("data","mergeBeforeCommit"));
         }
         if(!this.commitsConflictingItems(param2,param5,param6,param7))
         {
            this.conflicts.removeAllResolved();
            if(this.commitRequired)
            {
               if(param7 == null)
               {
                  if(this.messageCache.uncommittedBatches.length > 1)
                  {
                     _loc10_ = this.messageCache.uncommittedBatches.createCursor();
                     while(!_loc10_.afterLast)
                     {
                        param7 = MessageBatch(_loc10_.current);
                        if(!_loc10_.moveNext())
                        {
                           break;
                        }
                        this.doCommit(param1,param2,param3,param4,param5,param6,param7);
                     }
                  }
                  param7 = this.messageCache.currentBatch;
               }
               if(param5 == null)
               {
                  _loc8_ = param7.batchMessage;
                  param4 = this.setupBatchMessage(_loc8_,param7,param4,param3);
                  if(!this.connected && !this.autoConnect)
                  {
                     this.sendCommitFailed(param2,param4);
                     return param4;
                  }
                  this.commitInProgress = true;
                  _loc8_.body = param7.getMessages(null,null,param7.id,true);
                  param7.addUpdateCollectionMessages(_loc8_.body as Array,param7.id);
                  if(_loc8_.body.length == 0)
                  {
                     if(param7 != this.currentBatch)
                     {
                        this.messageCache.removeBatch(param7.id);
                     }
                     return null;
                  }
                  if(param7 == this.currentBatch)
                  {
                     _loc9_ = this.messageCache.commitUncommitted();
                  }
                  else
                  {
                     _loc9_ = this.messageCache.commitNewBatch(param7);
                  }
               }
               else
               {
                  if(!this.connected && !this.autoConnect)
                  {
                     if(param4 == null)
                     {
                        param4 = new AsyncToken();
                     }
                     this.sendCommitFailed(param2,param4);
                     return param4;
                  }
                  _loc11_ = new Array();
                  _loc12_ = param7;
                  param7 = param7.extractMessages(_loc11_,param5,param6);
                  if(param7 != null)
                  {
                     _loc8_ = param7.batchMessage;
                     _loc8_.body = _loc11_;
                     this.messageCache.addBatch(param7,true);
                     _loc12_.batchSequence = DataMessageCache.currentBatchSequence++;
                     param4 = this.setupBatchMessage(_loc8_,param7,param4,param3);
                     _loc9_ = this.messageCache.commitNewBatch(param7);
                  }
                  else
                  {
                     return null;
                  }
               }
               if(Log.isDebug())
               {
                  _log.debug((!!_loc9_?"committing: ":"committing (queued):") + param7.toString());
               }
               param7.tokenCache = [];
               param7.tokenCacheIndex = {};
               if(_loc9_)
               {
                  this.doPollIfNecessary();
                  this.producer.invoke(_loc8_,new param1(this,param4));
               }
               else
               {
                  param7.batchMessage = _loc8_;
                  param7.commitResponder = new param1(this,param4);
               }
            }
         }
         else if(hasEventListener(UnresolvedConflictsEvent.FAULT))
         {
            dispatchEvent(new UnresolvedConflictsEvent(UnresolvedConflictsEvent.FAULT));
         }
         else
         {
            _loc13_ = 0;
            _loc14_ = 0;
            for(_loc15_ in this.dataServices)
            {
               _loc16_ = this.dataServices[_loc15_];
               _loc14_++;
               if(_loc16_.hasEventListener(UnresolvedConflictsEvent.FAULT))
               {
                  if(this.hasConflicts(_loc16_))
                  {
                     _loc16_.dispatchEvent(new UnresolvedConflictsEvent(UnresolvedConflictsEvent.FAULT));
                  }
                  _loc13_++;
               }
            }
            if(_loc13_ != _loc14_)
            {
               throw new UnresolvedConflictsError(resourceManager.getString("data","unresolvedConflictsExist"));
            }
         }
         return param4;
      }
      
      private function sendCommitFailed(cds:ConcreteDataService, token:AsyncToken) : void
      {
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = "Client.Commit.Failed";
         errMsg.faultString = "Commit operation not allowed if a connection can\'t be established.";
         errMsg.faultDetail = "Remote destination is not available.";
         var event:MessageFaultEvent = MessageFaultEvent.createEvent(errMsg);
         new AsyncDispatcher(this.dataStoreEventDispatcher.dispatchCacheFaultEvent,[cds != null?cds:this,event,token,true],10);
      }
      
      private function setupBatchMessage(msg:DataMessage, batch:MessageBatch, token:AsyncToken, createItemReference:Boolean) : AsyncToken
      {
         msg.operation = !!this._useTransactions?uint(DataMessage.TRANSACTED_OPERATION):uint(DataMessage.BATCHED_OPERATION);
         if(token == null)
         {
            if(createItemReference)
            {
               token = new ItemReference(msg);
            }
            else
            {
               token = new AsyncToken(msg);
            }
         }
         else
         {
            token.setMessage(msg);
         }
         batch.applyTokenChain(token);
         return token;
      }
      
      private function commitsConflictingItems(cds:ConcreteDataService, itemsOrCollections:Array, cascadeCommit:Boolean, batch:MessageBatch) : Boolean
      {
         var changes:Object = null;
         var i:int = 0;
         var changedUIDs:Object = null;
         var messageId:* = null;
         var conflict:Conflict = null;
         if(this.conflicts.resolved)
         {
            return false;
         }
         if(batch == null)
         {
            if(itemsOrCollections == null)
            {
               return true;
            }
            for(i = 0; i < this.messageCache.uncommittedBatches.length; i++)
            {
               if(this.commitsConflictingItems(cds,itemsOrCollections,cascadeCommit,MessageBatch(this.uncommittedBatches[i])))
               {
                  return true;
               }
            }
            batch = this.messageCache.currentBatch;
         }
         if(itemsOrCollections != null)
         {
            changes = batch.getMessageIdsForItems(itemsOrCollections,cascadeCommit);
            if(changes == null)
            {
               return false;
            }
            changedUIDs = new Object();
            for(messageId in changes)
            {
               changedUIDs[batch.getCacheItem(messageId).uid] = true;
            }
         }
         else
         {
            changes = null;
         }
         for(var ci:int = 0; ci < this.conflicts.length; ci++)
         {
            conflict = Conflict(this.conflicts.getItemAt(ci));
            if(!conflict.resolved && (changes == null || changedUIDs[conflict.uid]))
            {
               return true;
            }
         }
         return false;
      }
      
      public function createBatch(itemsOrCollection:Array = null, cascadeCommit:Boolean = false, properties:Object = null) : MessageBatch
      {
         var batch:MessageBatch = this.messageCache.createBatch(itemsOrCollection,cascadeCommit,properties);
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
         return batch;
      }
      
      function setAutoConnect(value:Boolean) : void
      {
         this._autoConnect = value;
      }
      
      function sendUnsentCommits() : void
      {
         var batch:MessageBatch = null;
         var committedUnsent:Array = this.messageCache.committedUnsent;
         if(!this.conflicts.resolved)
         {
            return;
         }
         while(committedUnsent.length > 0 && this.messageCache.allowedToSend(committedUnsent[0]))
         {
            batch = committedUnsent[0];
            this.messageCache.committedUnsent.splice(0,1);
            this.messageCache.commitNewBatch(batch);
            this.doPollIfNecessary();
            this.producer.invoke(batch.batchMessage,batch.commitResponder);
         }
      }
      
      function checkDataStoreConsistency() : void
      {
         var dest:* = null;
         var cds:ConcreteDataService = null;
         for(dest in this.dataServices)
         {
            cds = this.dataServices[dest];
            cds.checkAssociatedDataStores();
         }
      }
      
      function doRevertChanges(ds:ConcreteDataService = null, item:IManaged = null, collection:ListCollectionView = null, batch:MessageBatch = null) : Boolean
      {
         var messages:Array = null;
         var ucMsgs:Array = null;
         var ucMsg:UpdateCollectionMessage = null;
         var cds:ConcreteDataService = null;
         var msg:DataMessage = null;
         var destination:String = null;
         var i:int = 0;
         var identity:Object = null;
         var j:int = 0;
         var rb:int = 0;
         var rangeInfos:Array = null;
         var dataList:DataList = null;
         var ranges:Array = null;
         var k:int = 0;
         var rangeIdx:int = 0;
         var idIndex:int = 0;
         var revertCount:int = -1;
         var revertedBatches:Boolean = false;
         this.enableDelayedReleases();
         try
         {
            if(this.isInitialized)
            {
               if(batch == null)
               {
                  for(rb = this.messageCache.uncommittedBatches.length - 1; rb >= 0; rb--)
                  {
                     var batch:MessageBatch = this.messageCache.uncommittedBatches[rb];
                     if(collection != null)
                     {
                        if(batch.revertChangesForCollection(collection))
                        {
                           revertedBatches = true;
                        }
                     }
                     else if(batch.doRevertChanges(ds,item))
                     {
                        revertedBatches = true;
                     }
                  }
                  if(this.autoSaveCache)
                  {
                     this.saveCache(null,true);
                  }
               }
               else
               {
                  if(item == null && collection == null)
                  {
                     messages = batch.getMessages(null,null);
                  }
                  else
                  {
                     messages = batch.getMessages(ds,item == null?null:item.uid,null,false,collection);
                  }
                  if(messages.length > 0)
                  {
                     revertCount = messages.length;
                  }
                  destination = null;
                  for(i = messages.length - 1; i >= 0; i--)
                  {
                     msg = DataMessage(messages[i]);
                     cds = this.getDataService(msg.destination);
                     if(batch.getCacheItem(msg.messageId) != null && cds.revertMessage(msg))
                     {
                        this.messageCache.removeMessage(msg,batch.id);
                        revertCount--;
                     }
                  }
                  identity = null;
                  if(item != null)
                  {
                     if(ds == null)
                     {
                        var ds:ConcreteDataService = this.getDataServiceForValue(item);
                     }
                     identity = ds.getIdentityMap(item);
                  }
                  if(ds != null)
                  {
                     destination = ds.destination;
                  }
                  ucMsgs = batch.getUpdateCollectionMessages(destination,null,identity);
                  revertCount = revertCount + ucMsgs.length;
                  for(j = ucMsgs.length - 1; j >= 0; j--)
                  {
                     ucMsg = UpdateCollectionMessage(ucMsgs[j]);
                     cds = this.getDataService(ucMsg.destination);
                     if(item != null)
                     {
                        revertCount--;
                        rangeInfos = ucMsg.getRangeInfoForIdentity(identity);
                        dataList = cds.getDataListWithCollectionId(ucMsg.collectionId);
                        if(dataList != null)
                        {
                           ranges = ucMsg.body as Array;
                           for(k = rangeInfos.length - 1; k >= 0; k--)
                           {
                              rangeIdx = rangeInfos[k].rangeIndex;
                              idIndex = rangeInfos[k].idIndex;
                              dataList.applyUpdateCollectionRangeIndex(UpdateCollectionRange(ranges[rangeIdx]),idIndex,true,true,true);
                           }
                        }
                        ucMsg.removeRanges(rangeInfos);
                        if(ucMsg.body == null)
                        {
                           this.messageCache.removeMessage(ucMsg);
                        }
                     }
                     else if(cds.revertMessage(ucMsg))
                     {
                        this.messageCache.removeMessage(ucMsg,batch.id);
                        revertCount--;
                     }
                  }
                  this.removeConflicts(ds,item);
                  if(batch.length == 0)
                  {
                     this.messageCache.removeBatch(batch.id);
                  }
                  if(this.autoSaveCache)
                  {
                     this.saveCache(null,true);
                  }
               }
               return _loc6_;
            }
         }
         finally
         {
            while(true)
            {
               this.disableDelayedReleases();
            }
            return revertedBatches || revertCount == 0;
         }
         break loop6;
      }
      
      function getCacheData(ds:ConcreteDataService, descriptor:CacheDataDescriptor, token:AsyncToken) : void
      {
         var assocKind:uint = 0;
         var riSuccess:Function = null;
         var success:Function = null;
         var failed:Function = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = ds.offlineAdapter;
         var cachedDescriptor:Object = dsOfflineAdapter.restoreQuery(descriptor.id);
         assocKind = descriptor.type == CacheDataDescriptor.FILL?uint(ManagedAssociation.MANY):uint(ManagedAssociation.ONE);
         riSuccess = function(data:Object):void
         {
            var event:MessageEvent = MessageEvent.createEvent(MessageEvent.RESULT,null);
            dataStoreEventDispatcher.dispatchResultEvent(ds,event,token,data,true);
         };
         success = function(data:Object, tk:Object):void
         {
            var refs:Array = null;
            if(data != null)
            {
               refs = CacheDataDescriptor(data).references;
               getReferencedItemsFromCache(ds,assocKind,refs,riSuccess,failed);
            }
         };
         failed = function(info:Object, tk:Object):void
         {
            var error:Error = new Error(info.toString());
            dataStoreEventDispatcher.dispatchFileAccessFault(error,ds,token,true);
         };
         try
         {
            var descriptor:CacheDataDescriptor = CacheDataDescriptor(cachedDescriptor);
            success(descriptor,null);
         }
         catch(e:ItemPendingError)
         {
            e.addResponder(new ItemResponder(success,failed));
         }
      }
      
      function getCacheDescriptors(ds:ConcreteDataService, view:ListCollectionView, options:uint, value:Object, token:AsyncToken) : void
      {
         var success:Function = null;
         var failed:Function = null;
         success = function(data:Object, tk:Object):void
         {
            var descriptor:CacheDataDescriptor = null;
            var desc:Object = null;
            var event:MessageEvent = null;
            var id:Object = null;
            view.removeAll();
            var descList:Array = offlineAdapter.getFillList();
            for each(desc in descList)
            {
               try
               {
                  descriptor = CacheDataDescriptor(desc);
                  if(descriptor != null)
                  {
                     if(value == null)
                     {
                        if(options == CacheDataDescriptor.ALL || options == descriptor.type)
                        {
                           configureDescriptor(descriptor,ds.destination);
                           view.addItem(descriptor);
                        }
                     }
                     else
                     {
                        id = null;
                        if(value is ListCollectionView)
                        {
                           id = DataList(ListCollectionView(value).list).collectionId;
                        }
                        else if(value is IManaged)
                        {
                           id = ds.getIdentityMap(IManaged(value));
                        }
                        if(ObjectUtil.compare(id,descriptor.id) == 0)
                        {
                           configureDescriptor(descriptor,ds.destination);
                           view.addItem(descriptor);
                        }
                     }
                  }
               }
               catch(e:ItemPendingError)
               {
                  e.addResponder(new ItemResponder(success,failed));
                  return;
               }
            }
            event = MessageEvent.createEvent(MessageEvent.RESULT,null);
            dataStoreEventDispatcher.dispatchResultEvent(ds,event,token,null,true);
         };
         failed = function(info:Object, tk:Object):void
         {
            var error:Error = new Error("Problem retrieving cache descriptors");
            dataStoreEventDispatcher.dispatchFileAccessFault(error,ds,token,true);
         };
         try
         {
            success(null,null);
         }
         catch(e:ItemPendingError)
         {
            e.addResponder(new ItemResponder(success,failed));
         }
      }
      
      function getDataService(destination:String) : ConcreteDataService
      {
         var result:ConcreteDataService = this.dataServices[destination];
         if(result == null)
         {
            result = this._adapter.getConcreteDataService(destination);
         }
         return result;
      }
      
      function getDataServiceForValue(value:Object) : ConcreteDataService
      {
         var i:* = null;
         var destName:String = null;
         var result:ConcreteDataService = null;
         var uid:String = IManaged(value).uid;
         if(uid == null)
         {
            return null;
         }
         var ix:int = uid.indexOf(Metadata.UID_TYPE_SEPARATOR);
         if(ix != -1)
         {
            destName = uid.substring(0,ix);
            result = this.dataServices[destName];
            if(result != null)
            {
               return result;
            }
         }
         for(i in this.dataServices)
         {
            result = this.dataServices[i];
            if(ConcreteDataService.equalItems(result.getItem(uid),value))
            {
               return result;
            }
         }
         throw new DataServiceError("Unable to find data service for value: " + ConcreteDataService.itemToString(value));
      }
      
      function getUnmergedUpdateCollectionMessages(destination:String, collectionId:Object) : Array
      {
         var msg:DataMessage = null;
         var result:Array = [];
         for(var i:int = 0; i < this.unmergedMessages.length; i++)
         {
            msg = DataMessage(this.unmergedMessages[i]);
            if(msg is UpdateCollectionMessage && msg.destination == destination && ObjectUtil.compare(UpdateCollectionMessage(msg).collectionId,collectionId) == 0)
            {
               result.push(msg);
            }
         }
         return result;
      }
      
      function hasUnmergedUpdateCollectionMessages(destination:String, collectionId:Object) : Boolean
      {
         var msg:DataMessage = null;
         for(var i:int = 0; i < this.unmergedMessages.length; i++)
         {
            msg = DataMessage(this.unmergedMessages[i]);
            if(msg is UpdateCollectionMessage && msg.destination == destination && ObjectUtil.compare(UpdateCollectionMessage(msg).collectionId,collectionId) == 0)
            {
               return true;
            }
         }
         return false;
      }
      
      private function getAllConfigCollections(dataServiceByDestination:Object, configCollectionByDestination:Object, success:Function) : void
      {
         var traversedDataServiceByDestination:Object = null;
         var getConfigCollections:Function = null;
         traversedDataServiceByDestination = {};
         getConfigCollections = function(result:Object, lastPendingDestination:String):void
         {
            var destination:String = null;
            var cds:ConcreteDataService = null;
            var configCollection:* = undefined;
            var hasPendingGet:Boolean = false;
            for(destination in dataServiceByDestination)
            {
               if(!traversedDataServiceByDestination.hasOwnProperty(destination))
               {
                  cds = ConcreteDataService(dataServiceByDestination[destination]);
                  try
                  {
                     configCollection = getConfigCollection(cds);
                     traversedDataServiceByDestination[destination] = cds;
                     configCollectionByDestination[destination] = configCollection;
                  }
                  catch(error:ItemPendingError)
                  {
                     if(destination == lastPendingDestination)
                     {
                        traversedDataServiceByDestination[destination] = cds;
                        continue;
                     }
                     error.addResponder(new ItemResponder(getConfigCollections,getConfigCollections,destination));
                     hasPendingGet = true;
                     break;
                  }
               }
            }
            if(!hasPendingGet)
            {
               success();
            }
         };
         getConfigCollections(null,null);
      }
      
      public function initialize(success:Function, failed:Function) : void
      {
         var lds:Object = null;
         var mdLeftToInit:uint = 0;
         var dataStore:DataStore = null;
         var configCollectionByDestination:Object = null;
         var initSuccess:Function = null;
         var metadataInitSuccess:Function = null;
         var initMetadata:Function = null;
         var localStoreConnectSuccessHandler:Function = null;
         var localStoreConnectFailureHandler:Function = null;
         var producerConnectHandler:Function = null;
         lds = this.dataServices;
         mdLeftToInit = 0;
         dataStore = this;
         configCollectionByDestination = {};
         if(success != null || failed != null)
         {
            this._initializedCallbacks.push({
               "s":success,
               "f":failed
            });
         }
         if(this._initializedCallbacks.length > 1)
         {
            return;
         }
         if(this.isInitialized)
         {
            this.invokeInitializedCallbacks();
            return;
         }
         initSuccess = function():void
         {
            _initialized = true;
            for(var c:int = 0; c < conflicts.length; c++)
            {
               dispatchConflictEvent(Conflict(conflicts.getItemAt(c)));
            }
            if(Log.isDebug())
            {
               _log.debug("data store: " + _id + " is initialized");
            }
            invokeInitializedCallbacks();
            if(dataStore.messageCache.commitRequired)
            {
               dataStore.dispatchEvent(PropertyChangeEvent.createUpdateEvent(dataStore,"commitRequired",false,true));
            }
            dataStore.checkDataStoreConsistency();
         };
         metadataInitSuccess = function():void
         {
            mdLeftToInit--;
            if(mdLeftToInit == 0)
            {
               initMessageCache(initSuccess);
            }
         };
         initMetadata = function():void
         {
            var cds:ConcreteDataService = null;
            var configCol:Object = null;
            var cdsArray:Array = null;
            var i:String = null;
            var j:int = 0;
            var first:ConcreteDataService = null;
            var ut:Boolean = false;
            var invalidExtDests:Array = null;
            var configData:Metadata = null;
            var fault:Fault = null;
            var initFaultEvent:DataServiceFaultEvent = null;
            var invalidDestinations:Array = null;
            var alreadyInitialized:Dictionary = new Dictionary();
            try
            {
               Metadata.clearSubTypeGraph();
               cdsArray = new Array();
               for(i in lds)
               {
                  cds = ConcreteDataService(lds[i]);
                  cdsArray.push(cds);
               }
               for(j = 0; j < cdsArray.length; j++)
               {
                  configCol = null;
                  cds = ConcreteDataService(cdsArray[j]);
                  if(!cds.metadata.isInitialized)
                  {
                     mdLeftToInit++;
                     configCol = configCollectionByDestination[cds.destination];
                     if(!cds.metadata.initialize(metadataInitSuccess,null,configCol))
                     {
                        if(invalidDestinations == null)
                        {
                           invalidDestinations = [];
                        }
                        invalidDestinations.push(cds.destination);
                     }
                     else
                     {
                        resetDataStore(dataStore,cds.destination,useTransactions,null);
                     }
                  }
                  else
                  {
                     configCol = configCollectionByDestination[cds.destination];
                     configData = configCol as Metadata;
                     if(configData)
                     {
                        if(!cds.metadata.itemClass && configData.itemClass)
                        {
                           cds.metadata.itemClass = configData.itemClass;
                        }
                        if(cds.metadata.hasChangedItemClassDynamicProperties)
                        {
                           cds.setItemClassDynamicProperties(configData.itemClassDynamicProperties);
                        }
                        else
                        {
                           cds.metadata.itemClassDynamicProperties = configData.itemClassDynamicProperties;
                        }
                     }
                  }
                  invalidExtDests = cds.initClassTreeDestinations(alreadyInitialized,metadataInitSuccess,null);
                  if(invalidDestinations == null)
                  {
                     invalidDestinations = invalidExtDests;
                  }
                  else if(invalidExtDests != null)
                  {
                     invalidDestinations.concat(invalidExtDests);
                  }
               }
               first = null;
               for(i in lds)
               {
                  cds = ConcreteDataService(lds[i]);
                  cds.channelSet = channelSet;
                  if(_adapter is MessagingDataServiceAdapter && !cds.runtimeConfigured)
                  {
                     ServerConfig.checkChannelConsistency(destination,cds.destination);
                  }
                  if(first == null)
                  {
                     first = cds;
                     ut = cds.metadata.useTransactions;
                  }
                  else if(ut != cds.metadata.useTransactions)
                  {
                     throw new DataServiceError("Value of useTransactions setting must be the same for all destinations.  " + first.destination + " has: " + ut + " but: " + cds.destination + " has: " + cds.metadata.useTransactions);
                  }
                  if(cds.metadata.isInitialized)
                  {
                     cds.metadata.validate(dataStore,cds);
                  }
                  cds.initializeOfflineAdapter();
               }
               useTransactions = ut;
               if(mdLeftToInit == 0)
               {
                  initMessageCache(initSuccess);
               }
            }
            catch(dse:DataServiceError)
            {
               throw dse;
            }
            catch(e:Error)
            {
               offlineAdapter.close();
               if(Log.isError())
               {
                  _log.error("Caught error initializing metadata for datastore: " + _id + " error: " + e.getStackTrace());
               }
               _initialized = false;
               invokeInitializedCallbacks(e.message);
               dispatchEvent(DataServiceFaultEvent.createEvent(new Fault("DataManager.InitializationFailed",e.message),null,null,null,null));
            }
            if(invalidDestinations != null)
            {
               fault = new Fault("DataManager.InitializationFailed",(!!connected?"Missing or invalid configuration for destinations: ":"Cannot connect to the server to load configuration for destinations: ") + Managed.toString(invalidDestinations));
               initFaultEvent = DataServiceFaultEvent.createEvent(fault,null,null,null,null);
               dispatchEvent(initFaultEvent);
               invokeInitializedCallbacks(fault.faultString);
               if(!connected && autoConnect)
               {
                  enableAutoConnectTimer();
               }
               _initialized = false;
            }
         };
         localStoreConnectSuccessHandler = function(event:ResultEvent):void
         {
            getAllConfigCollections(dataServices,configCollectionByDestination,initMetadata);
         };
         localStoreConnectFailureHandler = function(event:FaultEvent):void
         {
            invokeInitializedCallbacks(event.fault.faultString);
         };
         producerConnectHandler = function(event:Event):void
         {
            var connectToken:AsyncToken = null;
            producer.removeEventListener(ChannelEvent.CONNECT,producerConnectHandler);
            producer.removeEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
            producer.removeEventListener(MessageAckEvent.ACKNOWLEDGE,producerConnectHandler);
            if(cacheID != null)
            {
               if(event is MessageFaultEvent || event is ChannelFaultEvent)
               {
                  producer.disconnect();
               }
               connectToken = offlineAdapter.connect(cacheID);
               connectToken.addResponder(new Responder(localStoreConnectSuccessHandler,localStoreConnectFailureHandler));
            }
            else
            {
               getAllConfigCollections(dataServices,configCollectionByDestination,initMetadata);
            }
            if(producer.channelSet != null && producer.channelSet.connected)
            {
               producer.channelConnectHandler(ChannelEvent.createEvent(ChannelEvent.CONNECT,channelSet.currentChannel,false,false,true));
            }
            if(!connected)
            {
               if(autoConnect)
               {
                  enableAutoConnectTimer();
               }
            }
            else
            {
               connectServices();
               disableAutoConnectTimer();
            }
         };
         var alreadyConnected:Boolean = this.producer.connected;
         this.producer.needsConfig = this.needsConfig();
         if((this.autoConnect || alreadyConnected) && !this.producer.connected)
         {
            if(this.producer.needsConfig)
            {
               this.producer.addEventListener(ChannelEvent.CONNECT,producerConnectHandler);
               this.producer.addEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
               this.producer.addEventListener(MessageAckEvent.ACKNOWLEDGE,producerConnectHandler);
            }
            else
            {
               producerConnectHandler(null);
            }
            this.producer.connect();
         }
         else
         {
            producerConnectHandler(null);
         }
      }
      
      function getConfigCollection(cds:ConcreteDataService) : Object
      {
         var metadata:Object = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = cds.offlineAdapter;
         if(this.cacheID != null && dsOfflineAdapter.isConnected())
         {
            metadata = dsOfflineAdapter.retrieveMetaData();
         }
         return metadata;
      }
      
      function invoke(msg:IMessage, responder:IResponder) : void
      {
         if(this.connected || this.autoConnect)
         {
            this.producer.invoke(msg,responder);
         }
      }
      
      function logCollectionUpdate(dataService:ConcreteDataService, dataList:DataList, changeType:int, position:int, identity:Object, item:Object) : void
      {
         if(this.ignoreCollectionUpdates)
         {
            return;
         }
         this.messageCache.logCollectionUpdate(dataService,dataList,changeType,position,identity,item);
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
      }
      
      public function get ignoreCollectionUpdates() : Boolean
      {
         return this._ignoreCollectionUpdates;
      }
      
      public function set ignoreCollectionUpdates(value:Boolean) : void
      {
         this._ignoreCollectionUpdates = value;
      }
      
      function logCreate(dataService:ConcreteDataService, item:Object, op:uint) : DataMessage
      {
         var msg:DataMessage = this.messageCache.logCreate(dataService,item,op);
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
         return msg;
      }
      
      function logRemove(dataService:ConcreteDataService, item:Object) : DataMessage
      {
         var msg:DataMessage = this.messageCache.logRemove(dataService,item);
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
         return msg;
      }
      
      function logUpdate(dataService:ConcreteDataService, item:Object, propName:Object, oldValue:Object, newValue:Object, stopAtItem:DataMessage, leafChange:Boolean, assoc:ManagedAssociation) : void
      {
         this.messageCache.logUpdate(dataService,item,propName,oldValue,newValue,stopAtItem,leafChange,assoc);
         if(this.autoSaveCache)
         {
            this.saveCache(null,true);
         }
      }
      
      function processConflict(dataService:ConcreteDataService, message:DataErrorMessage, clientMessage:DataMessage) : void
      {
         var conflict:Conflict = new Conflict(dataService,message,this.resolver,clientMessage);
         if(this.conflicts.addConflict(conflict))
         {
            this._messageCache.requiresSave = true;
            this.dispatchConflictEvent(conflict);
         }
      }
      
      private function dispatchConflictEvent(conflict:Conflict) : void
      {
         var d:* = null;
         var ds:ConcreteDataService = null;
         var conflictEvent:DataConflictEvent = DataConflictEvent.createEvent(conflict);
         dispatchEvent(conflictEvent);
         var errorHandled:Boolean = hasEventListener(DataConflictEvent.CONFLICT);
         for(d in this.dataServices)
         {
            ds = ConcreteDataService(this.dataServices[d]);
            if(ds.destination == conflictEvent.conflict.destination)
            {
               conflictEvent = DataConflictEvent.createEvent(conflict);
               ds.dispatchConflictEvent(conflictEvent,errorHandled);
            }
         }
      }
      
      function removeConflicts(ds:ConcreteDataService, item:IManaged = null) : void
      {
         var conflict:Conflict = null;
         var j:int = 0;
         if(this._conflicts != null)
         {
            for(j = this._conflicts.length - 1; j >= 0; j--)
            {
               conflict = Conflict(this._conflicts.getItemAt(j));
               if(item == null || ds.metadata.getUID(conflict.cause.identity) === item.uid)
               {
                  this._conflicts.removeItemAt(j);
               }
            }
         }
      }
      
      function removeDataService(ds:ConcreteDataService) : void
      {
         var i:* = null;
         removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,ds.dispatchEvent);
         delete this.dataServices[ds.destination];
         var total:int = 0;
         for(i in this.dataServices)
         {
            total++;
         }
         this.doRevertChanges(ds);
         if(total == 0)
         {
            if(this.isInitialized)
            {
               this.messageCache.clear();
               if(this.cacheID != null && this.offlineAdapter.isConnected())
               {
                  this.offlineAdapter.close();
               }
            }
            else
            {
               this._initializedCallbacks = [];
            }
            this.producer.logout();
            this.producer.disconnect();
         }
      }
      
      function saveCache(dispatcher:IEventDispatcher, faultsOnly:Boolean = false, value:Object = null, token:AsyncToken = null, asyncOnly:Boolean = true) : void
      {
         var waiter:Object = null;
         if(this.executingSaveCache)
         {
            if(dispatcher != null || this.saveCacheWaiters.length == 0)
            {
               waiter = {};
               waiter.dispatcher = dispatcher;
               waiter.faultsOnly = faultsOnly;
               waiter.value = value;
               waiter.token = token;
               this.saveCacheWaiters.push(waiter);
            }
            return;
         }
         var timedCacheSaver:Function = function(event:Event):void
         {
            if(saveCacheTimer != null && event != null)
            {
               saveCacheTimer.stop();
               saveCacheTimer = null;
            }
            doSaveCache(dispatcher,faultsOnly,value,token);
         };
         var now:int = getTimer();
         if(asyncOnly || value == null && this.lastSaveTime != 0 && this.saveCacheMinIntervalMillis != 0 && now - this.lastSaveTime < this.saveCacheMinIntervalMillis)
         {
            if(this.saveCacheTimer == null)
            {
               this.saveCacheTimer = new Timer(Math.max(this.saveCacheMinIntervalMillis - (now - this.lastSaveTime),1),1);
               this.saveCacheTimer.addEventListener(TimerEvent.TIMER,timedCacheSaver);
               this.saveCacheTimer.start();
            }
         }
         else
         {
            timedCacheSaver(null);
         }
      }
      
      private function doSaveCache(dispatcher:IEventDispatcher, faultsOnly:Boolean = false, value:Object = null, token:AsyncToken = null) : void
      {
         var ds:ConcreteDataService = null;
         var i:String = null;
         var dl:DataList = null;
         var w:Object = null;
         if(this._cacheId == null || !this.offlineAdapter.isConnected())
         {
            return;
         }
         this.executingSaveCache = true;
         try
         {
            this.offlineAdapter.beginTransaction();
            if(value == null)
            {
               for(i in this.dataServices)
               {
                  ds = ConcreteDataService(this.dataServices[i]);
                  this.persistDataService(ds);
               }
               this.lastSaveTime = getTimer();
            }
            else
            {
               dl = this.getDataListForValue(value);
               if(dl != null)
               {
                  this.persistDataList(dl);
                  this.persistCacheItems(dl.service);
               }
            }
            if(this._messageCache.requiresSave)
            {
               this.offlineAdapter.saveMessageCache(this._messageCache,this._unmergedMessages);
               this._messageCache.requiresSave = false;
            }
            this.saveCacheAfterCommit = this._messageCache.currentBatch.length > 0 || this._messageCache.committed.length > 0;
            this.offlineAdapter.commit(dispatcher,token,faultsOnly);
         }
         catch(e:Error)
         {
            offlineAdapter.rollback();
            if(Log.isError())
            {
               log.error("Error occurred saving the cache: " + e + " stack: " + e.getStackTrace());
            }
            if(dispatcher != null)
            {
               dataStoreEventDispatcher.doCacheFault(dispatcher,e,"Client.Save.Failed","Could not save local cache: " + e.getStackTrace(),token);
            }
         }
         if(this.saveCacheWaiters.length > 0)
         {
            w = this.saveCacheWaiters.shift();
            new AsyncDispatcher(this.saveCache,[w.dispatcher,w.faultsOnly,w.value,w.token],10);
         }
         this.executingSaveCache = false;
      }
      
      public function get localStore() : IDatabase
      {
         if(this._localStore == null)
         {
            this._localStore = LocalStoreFactory.create();
         }
         return this._localStore;
      }
      
      function get resolver() : ConflictResolver
      {
         if(this._resolver == null)
         {
            this._resolver = new ConflictResolver(this);
         }
         return this._resolver;
      }
      
      private function get unmergedMessages() : Array
      {
         this.checkInitialized();
         return this._unmergedMessages;
      }
      
      private function checkInitialized() : void
      {
         if(!this.isInitialized)
         {
            throw new DataServiceError("DataStore is not initialized. Operation failed.");
         }
      }
      
      private function getDataListForValue(value:Object) : DataList
      {
         var result:DataList = null;
         var ds:ConcreteDataService = null;
         var id:Object = null;
         if(value is ListCollectionView)
         {
            result = DataList(ListCollectionView(value).list);
         }
         else if(value is ItemReference)
         {
            result = ItemReference(value)._dataList;
         }
         else
         {
            ds = this.getDataServiceForValue(value);
            if(ds == null)
            {
               throw new DataServiceError("Can\'t find a dataService for the value: " + Managed.toString(value));
            }
            id = ds.getIdentityMap(value);
            result = ds.getDataListWithFillParams(id);
         }
         return result;
      }
      
      function clearReferencedItemsFromCache(ds:ConcreteDataService, referencedIds:Array, success:Function, failure:Function) : void
      {
         var associations:Object = null;
         var association:ManagedAssociation = null;
         var itemAdapter:Object = null;
         var i:int = 0;
         var clearReferencedItemsInternal:Function = null;
         associations = ds.metadata.associations;
         itemAdapter = {};
         i = 0;
         clearReferencedItemsInternal = function():void
         {
            var item:Object = null;
            var itemDest:ConcreteDataService = null;
            var j:String = null;
            var dataList:DataList = null;
            var referenceTracker:Object = null;
            var dsOfflineAdapter:DataServiceOfflineAdapter = ds.offlineAdapter;
            for(var itemDic:Dictionary = dsOfflineAdapter.getItems(referencedIds); i < referencedIds.length; )
            {
               try
               {
                  item = itemDic[referencedIds[i]];
                  if(item is IManaged)
                  {
                     itemAdapter.item = DataMessage.wrapItem(item,ds.destination);
                     itemAdapter.referencedIds = Managed.getReferencedIds(item);
                     itemAdapter.destination = Managed.getDestination(item);
                     itemAdapter.uid = referencedIds[i];
                  }
                  else
                  {
                     itemAdapter = item;
                  }
               }
               catch(ipe:ItemPendingError)
               {
                  ipe.addResponder(new ItemResponder(clearReferencedItemsInternal,failure));
                  return;
               }
               if(itemAdapter != null)
               {
                  if(itemAdapter.destination != null)
                  {
                     itemDest = getDataService(itemAdapter.destination);
                  }
                  else
                  {
                     itemDest = ds;
                  }
                  for(j in associations)
                  {
                     association = ManagedAssociation(associations[j]);
                     if(Managed.propertyFetched(item,association.property))
                     {
                        if(association.pagedUpdates)
                        {
                           dataList = itemDest.getDataListForAssociation(item,association);
                           if(dataList.fetched)
                           {
                              clearCacheValue(null,dataList.view,null);
                           }
                        }
                        else
                        {
                           clearReferencedItemsFromCache(association.service,association.service.convertIdentitiesToUIDs(itemAdapter.referencedIds[j]),null,null);
                        }
                     }
                  }
                  if(referenceTracker == null)
                  {
                     referenceTracker = createAllReferencedMap();
                  }
                  if(referenceTracker == null || !referenceTracker[referencedIds[i]])
                  {
                     dsOfflineAdapter.deleteOfflineItem(referencedIds[i]);
                  }
               }
               i++;
            }
            if(success != null)
            {
               success();
            }
         };
         clearReferencedItemsInternal();
      }
      
      private function createAllReferencedMap() : Object
      {
         var descriptor:Object = null;
         var cachedData:CacheDataDescriptor = null;
         var references:Array = null;
         var a:int = 0;
         var fillList:Array = this.offlineAdapter.getFillList();
         var referenceMap:Object = new Object();
         try
         {
            for each(descriptor in fillList)
            {
               cachedData = CacheDataDescriptor(descriptor);
               for(references = cachedData.references; a < references.length; )
               {
                  referenceMap[references[a]] = true;
                  a++;
               }
            }
         }
         catch(e:Error)
         {
            if(Log.isWarn()())
            {
               _log.error("Unable to build all fills reference map due to: " + e.errorID + " error: " + e.getStackTrace());
            }
         }
         return referenceMap;
      }
      
      private function configureDescriptor(descriptor:CacheDataDescriptor, destination:String) : void
      {
         if(!descriptor.hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE))
         {
            descriptor.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.descriptorChangeHandler);
         }
         descriptor.destination = destination;
      }
      
      private function configureItemFromCache(ds:ConcreteDataService, item:Object, referencedIds:Object, success:Function, failed:Function) : void
      {
         var md:Metadata = null;
         var associations:Array = null;
         var assocIter:uint = 0;
         var assocName:String = null;
         var association:ManagedAssociation = null;
         var item:Object = DataMessage.unwrapItem(item);
         md = ds.getItemMetadata(item);
         associations = md.associationNames;
         assocIter = 0;
         var cis:Function = function(data:Object):void
         {
            var prop:Object = null;
            var assocName:String = associations[assocIter];
            var assoc:ManagedAssociation = md.associations[assocName];
            if(assoc.typeCode == ManagedAssociation.MANY)
            {
               prop = new ArrayCollection();
               prop.source = data;
               item[assocName] = prop;
            }
            else
            {
               item[assocName] = data;
            }
         };
         if(associations != null)
         {
            while(assocIter < associations.length)
            {
               assocName = associations[assocIter];
               association = md.associations[assocName];
               this.getReferencedItemsFromCache(association.service,association.typeCode,association.service.convertIdentitiesToUIDs(referencedIds[assocName]),cis,failed);
               assocIter++;
            }
         }
         else if(success != null)
         {
            new AsyncDispatcher(success,[item],1);
         }
      }
      
      private function descriptorChangeHandler(event:PropertyChangeEvent) : void
      {
         var ds:ConcreteDataService = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = null;
         var descriptor:CacheDataDescriptor = CacheDataDescriptor(event.target);
         ds = ConcreteDataService.getService(descriptor.destination);
         try
         {
            dsOfflineAdapter = ds.offlineAdapter;
            dsOfflineAdapter.beginTransaction();
            dsOfflineAdapter.saveQuery(descriptor.id,descriptor);
            dsOfflineAdapter.commit(ds,null,true);
            if(Log.isDebug())
            {
               if(descriptor == null)
               {
                  _log.debug("YIKES - null descriptor in descriptorChangeHandler");
               }
               else
               {
                  _log.debug("Saving cached query in descriptor change handler: " + descriptor.toString());
               }
            }
         }
         catch(e:Error)
         {
            dataStoreEventDispatcher.doCacheFault(ds,e,"Client.Save.Failed","Descriptor property \'" + event.property + "\' was updated but could not be saved.",null);
         }
      }
      
      private function doPollIfNecessary() : void
      {
         var d:* = null;
         var consumer:MultiTopicConsumer = null;
         var cs:ChannelSet = null;
         for(d in this.dataServices)
         {
            consumer = ConcreteDataService(this.dataServices[d]).consumer;
            cs = consumer.channelSet;
            if(consumer.subscribed && cs != null && cs.currentChannel != null && cs.currentChannel.hasOwnProperty("pollingEnabled") && cs.currentChannel["pollingEnabled"])
            {
               (consumer.channelSet.currentChannel as PollingChannel).poll();
               break;
            }
         }
      }
      
      private function getReferencedItemsFromCache(ds:ConcreteDataService, type:uint, referencedIds:Array, success:Function, failed:Function) : void
      {
         var items:Array = null;
         var index:int = 0;
         var itemAdapter:Object = null;
         var item:Object = null;
         var ciSuccess:Function = null;
         var getReferencedItemsFromCacheInternal:Function = null;
         items = [];
         index = 0;
         itemAdapter = {};
         ciSuccess = function():void
         {
            success(itemAdapter.item);
         };
         getReferencedItemsFromCacheInternal = function():void
         {
            var dsOfflineAdapter:DataServiceOfflineAdapter = null;
            var itemDic:Dictionary = null;
            try
            {
               if(referencedIds != null)
               {
                  dsOfflineAdapter = ds.offlineAdapter;
                  itemDic = dsOfflineAdapter.getItems(referencedIds);
                  if(type == ManagedAssociation.ONE)
                  {
                     item = itemDic[referencedIds[0]];
                     if(item is IManaged)
                     {
                        itemAdapter.item = DataMessage.wrapItem(item,ds.destination);
                        itemAdapter.referencedIds = Managed.getReferencedIds(item);
                     }
                     else
                     {
                        itemAdapter = item;
                     }
                     configureItemFromCache(ds,itemAdapter.item,itemAdapter.referencedIds,ciSuccess,failed);
                  }
                  else
                  {
                     while(index < referencedIds.length)
                     {
                        item = itemDic[referencedIds[index]];
                        if(item is IManaged)
                        {
                           itemAdapter.item = DataMessage.wrapItem(item,ds.destination);
                           itemAdapter.referencedIds = Managed.getReferencedIds(item);
                        }
                        else
                        {
                           itemAdapter = item;
                        }
                        items.push(itemAdapter.item);
                        configureItemFromCache(ds,itemAdapter.item,itemAdapter.referencedIds,null,failed);
                        index++;
                     }
                     success(new ArrayCollection(items));
                  }
               }
            }
            catch(e:ItemPendingError)
            {
               e.addResponder(new ItemResponder(getReferencedItemsFromCacheInternal,failed));
            }
         };
         getReferencedItemsFromCacheInternal();
      }
      
      private function hasConflicts(ds:ConcreteDataService) : Boolean
      {
         var conflict:Conflict = null;
         for(var i:int = 0; i < this._conflicts.length; i++)
         {
            conflict = Conflict(this._conflicts.getItemAt(i));
            if(ds.destination == conflict.destination && !conflict.resolved)
            {
               return true;
            }
         }
         return false;
      }
      
      private function initMessageCache(complete:Function) : void
      {
         var cacheCollection:Object = null;
         var unmergedResult:Function = null;
         var unmergedFault:Function = null;
         var cacheFault:Function = null;
         var cacheResult:Function = null;
         var msgCache:DataMessageCache = null;
         var allPending:Array = null;
         var p:int = 0;
         unmergedResult = function(data:Object, token:Object):void
         {
            _unmergedMessages = data as Array;
            if(_unmergedMessages == null)
            {
               _unmergedMessages = [];
            }
            complete();
         };
         unmergedFault = function(info:Object, token:Object):void
         {
            unmergedResult(null,null);
         };
         cacheFault = function(info:Object, token:Object):void
         {
            cacheResult(null,null);
         };
         cacheResult = function(data:Object, token:Object):void
         {
            var oldBatches:Object = null;
            var oldUncommitted:MessageBatch = null;
            var mc:DataMessageCache = null;
            var c:int = 0;
            var unmerged:Array = null;
            if(_messageCache == null)
            {
               oldBatches = null;
               oldUncommitted = null;
            }
            else
            {
               oldBatches = _messageCache.uncommittedBatches;
               oldUncommitted = _messageCache.currentBatch;
            }
            if(data == null)
            {
               if(_messageCache == null)
               {
                  mc = messageCache;
               }
            }
            else
            {
               messageCache = DataMessageCache(data);
               registerItemsWithMessageCache();
               if(messageCache.restoredConflicts != null)
               {
                  for(c = 0; c < messageCache.restoredConflicts.length; c++)
                  {
                     conflicts.addConflict(Conflict(messageCache.restoredConflicts[c]));
                  }
                  messageCache.restoredConflicts = null;
               }
            }
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"uncommittedBatches",oldBatches,uncommittedBatches));
            sendCurrentBatchChange(oldUncommitted,currentBatch);
            saveCacheAfterCommit = _messageCache.currentBatch.length > 0 || _messageCache.committed.length > 0;
            if(_unmergedMessages == null)
            {
               unmerged = null;
               try
               {
                  if(data != null)
                  {
                     unmerged = cacheCollection.unmergedMessage;
                  }
                  unmergedResult(unmerged,null);
               }
               catch(e:ItemPendingError)
               {
                  e.addResponder(new ItemResponder(unmergedResult,unmergedFault));
               }
            }
            else
            {
               complete();
            }
         };
         if(this.cacheID == null || !this.offlineAdapter.isConnected() || this.offlineAdapter.isStoreEmpty())
         {
            cacheResult(null,null);
         }
         else
         {
            try
            {
               cacheCollection = this.offlineAdapter.getMessageCache();
               if(cacheCollection != null)
               {
                  msgCache = cacheCollection.messageCache;
                  msgCache.dataStore = this;
                  allPending = msgCache.pending;
                  for(p = 0; p < allPending.length; p++)
                  {
                     allPending[p].dataStore = this;
                  }
                  if(Log.isDebug())
                  {
                     _log.debug("Restored message cache: " + msgCache.toString());
                  }
               }
               cacheResult(msgCache,null);
            }
            catch(e:ItemPendingError)
            {
               e.addResponder(new ItemResponder(cacheResult,cacheFault));
            }
         }
      }
      
      function sendCurrentBatchChange(old:MessageBatch, newBatch:MessageBatch) : void
      {
         dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"currentBatch",old,newBatch));
      }
      
      private function registerItemsWithMessageCache() : void
      {
         var batch:MessageBatch = null;
         var i:int = 0;
         var cacheItem:MessageCacheItem = null;
         var uid:String = null;
         var item:IManaged = null;
         var allPending:Array = this.messageCache.pending;
         for(var p:int = 0; p < allPending.length; p++)
         {
            batch = allPending[p];
            for(i = 0; i < batch.items.length; i++)
            {
               cacheItem = batch.items[i];
               uid = cacheItem.uid;
               if(cacheItem.message is UpdateCollectionMessage)
               {
                  this.restoreUpdateCollection(cacheItem.message as UpdateCollectionMessage);
               }
               else if(uid != null && cacheItem.dataService != null && cacheItem.message.operation != DataMessage.DELETE_OPERATION)
               {
                  this.restoreReferencedItems(cacheItem.dataService,null,[uid],false);
                  item = cacheItem.dataService.getItem(uid);
                  if(item == null)
                  {
                     if(cacheItem.message.operation == DataMessage.DELETE_OPERATION)
                     {
                        item = cacheItem.dataService.normalize(DataMessage.unwrapItem(cacheItem.message.body));
                     }
                     else
                     {
                        throw new DataServiceError("Unable to restore item in message cache: " + uid);
                     }
                  }
                  batch.setCacheItem(cacheItem,item);
               }
            }
            if(batch.updateCollectionMessages != null)
            {
               for(i = 0; i < batch.updateCollectionMessages.length; i++)
               {
                  this.restoreUpdateCollection(UpdateCollectionMessage(batch.updateCollectionMessages[i]));
               }
            }
         }
      }
      
      private function restoreUpdateCollection(ucmsg:UpdateCollectionMessage) : void
      {
         var parentDataService:ConcreteDataService = null;
         var uid:String = null;
         var descriptor:CacheDataDescriptor = null;
         var cds:ConcreteDataService = this.getDataService(ucmsg.destination);
         if(cds == null)
         {
            throw DataServiceError("Can\'t restore update collection - no destination: " + ucmsg.destination);
         }
         var dataList:DataList = cds.getDataListWithCollectionId(ucmsg.collectionId);
         if(dataList == null)
         {
            if(!(ucmsg.collectionId is Array))
            {
               parentDataService = this.getDataService(ucmsg.collectionId.parent);
               uid = parentDataService.metadata.getUID(ucmsg.collectionId.id);
               this.restoreReferencedItems(parentDataService,null,[uid],false);
               dataList = cds.getDataListWithCollectionId(ucmsg.collectionId);
               dataList.referenceCount++;
               dataList.updateCollectionReferences++;
            }
            else
            {
               dataList = new DataList(cds);
               dataList.fillParameters = ucmsg.collectionId;
               descriptor = this.restoreDataList(dataList,cds);
               if(descriptor)
               {
                  dataList.setReferences(descriptor.references,false);
               }
            }
         }
         else
         {
            dataList.referenceCount++;
            dataList.updateCollectionReferences++;
         }
      }
      
      private function invokeInitializedCallbacks(errorDetails:String = null) : void
      {
         var methods:Object = null;
         var callbacks:Array = this._initializedCallbacks;
         this._initializedCallbacks = [];
         while(callbacks.length)
         {
            methods = callbacks.shift();
            if(errorDetails == null)
            {
               if(methods.s != null)
               {
                  methods.s();
               }
            }
            else if(methods.f != null)
            {
               methods.f(errorDetails);
            }
         }
         if(errorDetails == null)
         {
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"isInitialized",false,true));
         }
      }
      
      private function needsConfig() : Boolean
      {
         var i:* = null;
         for(i in this.dataServices)
         {
            if(this.dataServices[i].needsConfig)
            {
               return true;
            }
         }
         return false;
      }
      
      private function persistCacheItems(ds:ConcreteDataService) : void
      {
         var item:* = null;
         var itemCache:Object = null;
         var uid:* = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = ds.offlineAdapter;
         if(!ds.requiresSave)
         {
            return;
         }
         var itemList:Array = new Array();
         var itemRemoveList:Array = new Array();
         var itemUpdateDic:Dictionary = new Dictionary();
         if(ds.offlineDirtyList == null)
         {
            if(Log.isDebug())
            {
               _log.debug("Saving entire item cache for: " + ds.destination);
            }
            itemCache = ds.getItemCache();
            for(uid in itemCache)
            {
               item = IManaged(itemCache[uid]);
               itemList.push(item);
            }
            dsOfflineAdapter.saveItems(itemList);
         }
         else
         {
            for(item in ds.offlineDirtyList)
            {
               if(item is String || item is int)
               {
                  if(item is int)
                  {
                     item = String(item);
                  }
                  itemRemoveList.push(item);
               }
               else if(item is IManaged)
               {
                  itemUpdateDic[item] = ds.offlineDirtyList[item];
               }
            }
            dsOfflineAdapter.updateOfflineItems(itemUpdateDic);
            dsOfflineAdapter.deleteOfflineItems(itemRemoveList);
         }
         ds.offlineDirtyList = new Dictionary();
         ds.requiresSave = false;
      }
      
      function saveDataList(dl:DataList) : void
      {
         if(this._cacheId == null)
         {
            return;
         }
         try
         {
            this.offlineAdapter.beginTransaction();
            this.persistDataList(dl);
            this.offlineAdapter.commit(dl.service,null,true);
         }
         finally
         {
         }
      }
      
      private function persistDataList(dl:DataList) : void
      {
         var success:Function = null;
         var failure:Function = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = null;
         var descriptor:CacheDataDescriptor = null;
         if(!dl.cacheStale || !dl.fetched || dl.association != null && !dl.association.pagedUpdates)
         {
            return;
         }
         dl.inCache = true;
         success = function(data:CacheDataDescriptor, tk:Object):void
         {
            var wasListening:Boolean = false;
            if(data != null)
            {
               wasListening = data.hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE);
               try
               {
                  if(wasListening)
                  {
                     data.removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,descriptorChangeHandler);
                  }
                  data.setTimeAttributes(new Date(),null);
                  data.references = dl.references;
                  data.lastFilled = dl.fillTimestamp;
               }
               finally
               {
                  if(wasListening)
                  {
                     data.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,descriptorChangeHandler);
                  }
               }
            }
            else
            {
               var data:CacheDataDescriptor = new CacheDataDescriptor(dl);
               if(Log.isDebug())
               {
                  _log.debug("Creating new cached descriptor for query: " + data.toString());
               }
            }
            var dsOfflineAdapter:DataServiceOfflineAdapter = dl.service.offlineAdapter;
            dsOfflineAdapter.saveQuery(dl.collectionId,data);
            if(Log.isDebug())
            {
               _log.debug("Saving cached query: " + data.toString());
            }
            dl.cacheStale = false;
            dl.cacheRestored = true;
         };
         failure = function(info:Object, tk:Object):void
         {
         };
         try
         {
            dsOfflineAdapter = dl.service.offlineAdapter;
            descriptor = CacheDataDescriptor(dsOfflineAdapter.restoreQuery(dl.collectionId));
            success(descriptor,null);
         }
         catch(e:ItemPendingError)
         {
            e.addResponder(new ItemResponder(success,failure));
         }
      }
      
      private function persistConfiguration(ds:ConcreteDataService) : void
      {
         var dsOfflineAdapter:DataServiceOfflineAdapter = null;
         if(ds.metadata.serverConfigChanged && ds.metadata.isInitialized)
         {
            dsOfflineAdapter = ds.offlineAdapter;
            dsOfflineAdapter.saveMetaData(ds.metadata);
            ds.metadata.serverConfigChanged = false;
         }
      }
      
      private function persistDataService(ds:ConcreteDataService) : void
      {
         var dl:DataList = null;
         var shouldPersistDataList:Boolean = false;
         for each(dl in ds.dataLists.toArray())
         {
            shouldPersistDataList = true;
            if(this.offlineAdapter.isQuerySupported() && dl.association)
            {
               shouldPersistDataList = false;
            }
            if(shouldPersistDataList)
            {
               this.persistDataList(dl);
            }
         }
         this.persistCacheItems(ds);
         this.persistConfiguration(ds);
      }
      
      private function producerPropertyChangeHandler(event:PropertyChangeEvent) : void
      {
         if(event.property == "connected")
         {
            dispatchEvent(event);
         }
      }
      
      public function restoreReferencedItems(ds:ConcreteDataService, dataList:DataList, references:Array, prefetch:Boolean, restoredItems:Dictionary = null) : Array
      {
         var itemDic:Dictionary = null;
         var itemAdapter:Object = null;
         var uid:* = null;
         var localItem:Object = null;
         var pendingMessage:DataMessage = null;
         var extra:Object = null;
         var deletedItems:Array = null;
         if(dataList != null && dataList.cacheRestored || references == null && restoredItems == null)
         {
            return null;
         }
         var dsOfflineAdapter:DataServiceOfflineAdapter = ds.offlineAdapter;
         if(references == null && restoredItems != null)
         {
            itemDic = restoredItems;
         }
         else
         {
            itemDic = dsOfflineAdapter.getItems(references);
         }
         var newItems:Array = new Array();
         for(uid in itemDic)
         {
            if(ds.getItem(uid) == null)
            {
               localItem = itemDic[uid];
               if(localItem is IManaged)
               {
                  itemAdapter = {};
                  itemAdapter.item = DataMessage.wrapItem(localItem,ds.destination);
                  itemAdapter.referencedIds = Managed.getReferencedIds(localItem);
                  itemAdapter.destination = Managed.getDestination(localItem);
                  itemAdapter.uid = uid;
                  extra = ds.getFetchedProperties(localItem);
                  if(extra != null)
                  {
                     itemAdapter.extra = extra;
                  }
               }
               else
               {
                  itemAdapter = localItem;
               }
               if(itemAdapter != null)
               {
                  this.restoreReferencedIds(ds,itemAdapter);
                  newItems.push(itemAdapter);
               }
               else if((pendingMessage = this.messageCache.getPendingDeleteMessage(ds,uid)) != null)
               {
                  itemAdapter = {
                     "item":pendingMessage.unwrapBody(),
                     "destination":pendingMessage.destination,
                     "referencedIds":DataMessage.unwrapItem(pendingMessage.headers.referencedIds),
                     "uid":uid
                  };
                  newItems.push(itemAdapter);
               }
               else if((pendingMessage = this.messageCache.getCreateMessage(ds,uid)) != null)
               {
                  itemAdapter = {
                     "item":pendingMessage.unwrapBody(),
                     "destination":pendingMessage.destination,
                     "referencedIds":DataMessage.unwrapItem(pendingMessage.headers.referencedIds),
                     "uid":uid
                  };
                  newItems.push(itemAdapter);
               }
            }
         }
         if(!prefetch)
         {
            deletedItems = ds.restoreItemCache(newItems);
            if(dataList != null)
            {
               dataList.cacheRestored = true;
            }
         }
         this.restoreAssociations(ds,newItems,prefetch);
         return deletedItems;
      }
      
      private function restoreReferencedIds(ds:ConcreteDataService, itemAdapter:Object) : void
      {
         var a:int = 0;
         var assocName:String = null;
         var assoc:ManagedAssociation = null;
         var uids:Array = null;
         var uid:String = itemAdapter.uid;
         var item:Object = DataMessage.unwrapItem(itemAdapter.item);
         var referenceIdTable:Object = itemAdapter.referencedIds;
         var itemDS:ConcreteDataService = ds.getItemDestination(item);
         var dsOfflineAdapter:DataServiceOfflineAdapter = itemDS.offlineAdapter;
         if(dsOfflineAdapter.isQuerySupported())
         {
            for(a = 0; a < itemDS.metadata.associationNames.length; a++)
            {
               assocName = itemDS.metadata.associationNames[a];
               assoc = itemDS.metadata.associations[assocName];
               if(assoc.typeCode == ManagedAssociation.MANY && !assoc.pagedUpdates)
               {
                  if(referenceIdTable && !referenceIdTable.hasOwnProperty(assoc.property))
                  {
                     uids = dsOfflineAdapter.getItemReferenceIds(uid,assoc.property);
                     if(uids && uids.length > 0)
                     {
                        if(referenceIdTable == null)
                        {
                           itemAdapter.referencedIds = referenceIdTable = {};
                           Managed.setReferencedIds(item,referenceIdTable);
                        }
                        referenceIdTable[assoc.property] = uids;
                     }
                  }
               }
            }
         }
      }
      
      private function restoreAssociations(ds:ConcreteDataService, newItems:Array, prefetch:Boolean) : void
      {
         var itemAdapter:Object = null;
         var item:Object = null;
         var referenceIdTable:Object = null;
         var itemDS:ConcreteDataService = null;
         var a:int = 0;
         var assocName:String = null;
         var assoc:ManagedAssociation = null;
         var dataList:DataList = null;
         var dsOfflineAdapter:DataServiceOfflineAdapter = null;
         var mappedAssociation:ManagedAssociation = null;
         var refIds:Object = null;
         var refUIDs:Array = null;
         for(var i:int = 0; i < newItems.length; i++)
         {
            itemAdapter = newItems[i];
            if(prefetch)
            {
               if(itemAdapter.prefetched)
               {
                  return;
               }
               itemAdapter.prefetched = true;
            }
            item = DataMessage.unwrapItem(itemAdapter.item);
            referenceIdTable = Managed.getReferencedIds(item);
            itemDS = ds.getItemDestination(item);
            for(a = 0; a < itemDS.metadata.associationNames.length; a++)
            {
               assocName = itemDS.metadata.associationNames[a];
               assoc = itemDS.metadata.associations[assocName];
               if(!assoc.pagedUpdates)
               {
                  dataList = itemDS.getDataListForAssociation(item,assoc);
                  dsOfflineAdapter = assoc.service.offlineAdapter;
                  if(dataList != null)
                  {
                     this.restoreReferencedItems(assoc.service,dataList,dataList.references,prefetch);
                  }
                  else if(prefetch)
                  {
                     itemAdapter.prefetched = true;
                     refIds = itemAdapter.referencedIds[assocName];
                     if(assoc.typeCode == ManagedAssociation.ONE)
                     {
                        refIds = [refIds];
                     }
                     refUIDs = assoc.service.convertIdentitiesToUIDs(refIds as Array);
                     this.restoreReferencedItems(assoc.service,null,refUIDs,true);
                  }
               }
            }
         }
      }
      
      private function conflictsCollectionChangeHandler(event:CollectionEvent) : void
      {
         var markDirty:Boolean = false;
         if(this._messageCache.restoredConflicts == null)
         {
            switch(event.kind)
            {
               case CollectionEventKind.ADD:
               case CollectionEventKind.REMOVE:
               case CollectionEventKind.REPLACE:
               case CollectionEventKind.RESET:
                  markDirty = true;
                  break;
               case CollectionEventKind.UPDATE:
                  markDirty = true;
            }
         }
         if(markDirty)
         {
            this._messageCache.requiresSave = true;
            if(this.autoSaveCache)
            {
               this.saveCache(null,true);
            }
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get processingServerChanges() : Boolean
      {
         return this._1403190867processingServerChanges;
      }
      
      public function set processingServerChanges(param1:Boolean) : void
      {
         var _loc2_:Object = this._1403190867processingServerChanges;
         if(_loc2_ !== param1)
         {
            this._1403190867processingServerChanges = param1;
            if(this.hasEventListener("propertyChange"))
            {
               this.dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"processingServerChanges",_loc2_,param1));
            }
         }
      }
   }
}

import mx.data.ConcreteDataService;
import mx.data.DataStore;
import mx.data.ITokenResponder;
import mx.messaging.events.MessageEvent;
import mx.rpc.AsyncToken;
import mx.rpc.IResponder;

class CachedQueryResponder implements IResponder, ITokenResponder
{
    
   
   private var _cds:ConcreteDataService;
   
   private var _ds:DataStore;
   
   private var _responder:ITokenResponder;
   
   private var _offlineResult:MessageEvent;
   
   private var _token:AsyncToken;
   
   private var _result:Object;
   
   function CachedQueryResponder(ds:DataStore, cds:ConcreteDataService, responder:ITokenResponder, or:MessageEvent, token:AsyncToken, result:Object)
   {
      super();
      this._responder = responder;
      this._cds = cds;
      this._ds = ds;
      this._offlineResult = or;
      this._token = token;
      this._result = result;
   }
   
   public function get resultToken() : AsyncToken
   {
      return this._responder.resultToken;
   }
   
   public function result(data:Object) : void
   {
      this._responder.result(data);
   }
   
   public function fault(info:Object) : void
   {
      this._responder.fault(info);
      if(this._offlineResult != null)
      {
         this._cds.dispatchResultEvent(this._offlineResult,this._token,this._result,true);
      }
   }
}
