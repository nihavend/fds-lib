package mx.data
{
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.TimerEvent;
   import flash.utils.ByteArray;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;
   import mx.collections.ArrayCollection;
   import mx.collections.ArrayList;
   import mx.collections.IList;
   import mx.collections.ListCollectionView;
   import mx.collections.errors.ItemPendingError;
   import mx.core.EventPriority;
   import mx.data.errors.DataServiceError;
   import mx.data.events.DataConflictEvent;
   import mx.data.events.DataServiceFaultEvent;
   import mx.data.events.DataServiceResultEvent;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SyncFillRequest;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.AsyncTokenChain;
   import mx.data.utils.Managed;
   import mx.data.utils.SerializationProxy;
   import mx.events.CollectionEvent;
   import mx.events.CollectionEventKind;
   import mx.events.PropertyChangeEvent;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.ChannelSet;
   import mx.messaging.MultiTopicConsumer;
   import mx.messaging.channels.PollingChannel;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.CommandMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.IResponder;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectProxy;
   import mx.utils.ObjectUtil;
   import mx.utils.StringUtil;
   import mx.utils.UIDUtil;
   import mx.utils.object_proxy;
   
   [ExcludeClass]
   [ResourceBundle("data")]
   public class ConcreteDataService extends EventDispatcher
   {
      
      static const INIT_TREE_SUB:int = 1;
      
      static const INIT_TREE_SUPER:int = 2;
      
      static const INIT_TREE_TYPE:int = 3;
      
      private static var _dataServicePool:Object = {};
      
      private static var _globalLog:ILogger = Log.getLogger("mx.data.DataService");
      
      private static var _pagingDisabled:int = 0;
      
      private static var _indexReferences:Boolean = true;
      
      public static const CLASS_INFO_OPTIONS:Object = {
         "includeReadOnly":false,
         "includeTransient":false
      };
      
      private static const EXCLUDE_PROPERTIES:Array = ["constructor"];
      
      static const PENDING_STATE_CONFIGURED:int = 1;
      
      static const PENDING_STATE_ADDING_NESTED:int = 2;
      
      static const PENDING_STATE_CACHED:int = 4;
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      var inAssociation:Boolean = false;
      
      var numItems:int = 0;
      
      var runtimeConfigured:Boolean = false;
      
      var requiresSave:Boolean = false;
      
      var offlineDirtyList:Dictionary = null;
      
      private const REFERENCE_CHECK_INTERVAL:int = 5000;
      
      private const KEEP_REFERENCE_INTERVAL:int = 15000;
      
      private var _clientSequenceIdCounter:int = -2;
      
      private var _consumer:MultiTopicConsumer;
      
      private var _connecting:Boolean = false;
      
      private var _conflictDetector:ConflictDetector;
      
      private var _defaultAutoCommit:Boolean = true;
      
      private var _defaultAutoConnect:Boolean = true;
      
      private var _defaultAutoMerge:Boolean = true;
      
      private var _defaultAutoSaveCache:Boolean = false;
      
      private var _dataLists:ArrayList;
      
      private var _dataStore:DataStore;
      
      private var _delayedReleases:int = 0;
      
      private var _delayedCollectionEvents:int = 0;
      
      private var _pendingCollectionEvents:Array = null;
      
      private var _disconnectBarrier:Boolean = true;
      
      private var _itemCache:Object;
      
      private var _itemDataListIndex:Object;
      
      private var _itemChildDataListIndex:Dictionary;
      
      private var _maxFrequencySent:Boolean = false;
      
      private var _releasedItems:Dictionary;
      
      private var _releasedUIDs:Object = null;
      
      private var _referenceCheckItems:Array;
      
      private var _referenceCheckTimer:Timer = null;
      
      private var _log:ILogger;
      
      public var metadata:Metadata;
      
      private var _reconnecting:Boolean = false;
      
      private var _releaseBarrier:Boolean;
      
      private var _toRelease:Array;
      
      private var _autoSyncCount:int = 0;
      
      var staleSequencesCount:int = 0;
      
      private var _manuallySubscribed:Boolean = false;
      
      private var _manualSync:ManualSyncConfiguration;
      
      private var _shouldBeConnected:Boolean = false;
      
      private var _conflicts:Conflicts;
      
      private var _subTypes:Array = null;
      
      private var _classToSubDest:Object = null;
      
      var clientIdsAdded:Boolean = false;
      
      var extendsDestinations:Array = null;
      
      var includeAllSpecifier:PropertySpecifier;
      
      var includeDefaultSpecifier:PropertySpecifier;
      
      public var throwItemPendingErrors:Boolean = true;
      
      public var deleteItemOnRemoveFromFill:Boolean = true;
      
      public var defaultHierarchicalEvents:Boolean = false;
      
      public var resetCollectionOnFill:Boolean = true;
      
      public var adapter:DataServiceAdapter = null;
      
      private var _offlineAdapter:DataServiceOfflineAdapter = null;
      
      private var _offlineAdapterInitialized:Boolean = false;
      
      private var _allowDynamicPropertyChangesWithCachedData:Boolean = false;
      
      public function ConcreteDataService(destination:String, id:String = null, adapt:DataServiceAdapter = null, md:Metadata = null)
      {
         this._dataLists = new ArrayList();
         this._itemCache = {};
         this._itemDataListIndex = {};
         this._itemChildDataListIndex = new Dictionary(true);
         this._releasedItems = new Dictionary(true);
         this._referenceCheckItems = new Array();
         super();
         this.adapter = adapt;
         if(destination == null || destination.length == 0)
         {
            throw new DataServiceError("Destination specified is invalid, null and \'\' are not allowed.");
         }
         this._log = Log.getLogger("mx.data.DataService." + destination);
         this._consumer = new DataManagementConsumer();
         this._consumer.id = "cds-consumer-" + destination + "-" + id;
         this._consumer.destination = destination;
         this._consumer.setClientId(UIDUtil.createUID());
         this._consumer.resubscribeAttempts = -1;
         this._consumer.resubscribeInterval = 5000;
         this._consumer.addEventListener(MessageEvent.MESSAGE,this.messageHandler);
         this._consumer.addEventListener(MessageFaultEvent.FAULT,this.consumerFaultHandler);
         this._consumer.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.consumerPropertyChangeHandler);
         _dataServicePool[destination] = this;
         if(md == null)
         {
            this.metadata = new Metadata(this.adapter,destination);
         }
         else
         {
            this.metadata = md;
         }
         if(!this.metadata.initialize())
         {
            this.runtimeConfigured = true;
         }
         else
         {
            this.inAssociation = this.inAssociation || this.metadata.needsReferencedIds;
            this.initClassTreeDestinations(new Dictionary());
         }
         this.manualSync = new ManualSyncConfiguration();
         if(Log.isDebug())
         {
            this._log.debug("New DataManager for destination: {0}",destination);
         }
         this.includeAllSpecifier = new PropertySpecifier(this,PropertySpecifier.INCLUDE_ALL,null);
         this.includeDefaultSpecifier = new PropertySpecifier(this,PropertySpecifier.INCLUDE_DEFAULT,null);
      }
      
      public static function getService(destination:String) : ConcreteDataService
      {
         var result:ConcreteDataService = ConcreteDataService(_dataServicePool[destination]);
         if(result == null)
         {
            result = new ConcreteDataService(destination);
         }
         return result;
      }
      
      static function clearServicePool() : void
      {
         _dataServicePool = {};
      }
      
      public static function lookupService(destination:String) : ConcreteDataService
      {
         return ConcreteDataService(_dataServicePool[destination]);
      }
      
      static function get pagingDisabled() : int
      {
         return _pagingDisabled;
      }
      
      static function copyValues(objTo:Object, objFrom:Object, includes:Array = null, excludes:Array = null, denormalize:Boolean = true) : void
      {
         var properties:Array = null;
         var propName:String = null;
         objTo = DataMessage.unwrapItem(objTo);
         objFrom = DataMessage.unwrapItem(objFrom);
         if(objTo is ObjectProxy && denormalize)
         {
            objTo = ObjectProxy(objTo).object_proxy::object;
         }
         if(includes != null)
         {
            properties = includes;
         }
         else
         {
            properties = getObjectProperties(objFrom);
         }
         for(var i:uint = 0; i < properties.length; i++)
         {
            propName = properties[i];
            if(excludes == null || ArrayUtil.getItemIndex(propName,excludes) == -1)
            {
               objTo[propName] = objFrom[propName];
            }
         }
      }
      
      static function disablePaging() : void
      {
         _pagingDisabled++;
      }
      
      static function enablePaging() : void
      {
         _pagingDisabled--;
      }
      
      static function equalItems(obj1:Object, obj2:Object) : Boolean
      {
         if(obj1 is ObjectProxy)
         {
            obj1 = ObjectProxy(obj1).object_proxy::object;
         }
         if(obj2 is ObjectProxy)
         {
            obj2 = ObjectProxy(obj2).object_proxy::object;
         }
         return obj1 == obj2;
      }
      
      static function get globalLog() : ILogger
      {
         return _globalLog;
      }
      
      static function getObjectProperties(obj:Object) : Array
      {
         var result:Array = null;
         try
         {
            disablePaging();
            result = ObjectUtil.getClassInfo(obj,EXCLUDE_PROPERTIES,CLASS_INFO_OPTIONS).properties;
         }
         finally
         {
            enablePaging();
         }
         return result;
      }
      
      static function itemToString(item:Object, destination:String = null, indent:int = 0, refs:Dictionary = null, exclude:Array = null, summaryOnly:Boolean = false) : String
      {
         var result:String = null;
         var cds:ConcreteDataService = null;
         var idName:String = null;
         if(item == null)
         {
            return "null";
         }
         if(item is Array || item is ListCollectionView)
         {
            return Managed.internalToString(item,indent,refs,null,exclude,false,summaryOnly);
         }
         try
         {
            disablePaging();
            try
            {
               if(destination == null)
               {
                  var destination:String = item.destination;
               }
            }
            catch(e:Error)
            {
            }
            if(destination == null || destination == "")
            {
               result = Managed.internalToString(item,indent,refs,null,exclude,false);
            }
            else
            {
               cds = _dataServicePool[destination];
               if(summaryOnly && cds != null)
               {
                  if(cds.metadata.identities.length == 1)
                  {
                     idName = cds.metadata.identities[0];
                     result = idName + "=" + Managed.toString(item[idName],null,null,indent + 2,false,refs);
                  }
                  else
                  {
                     result = Managed.toString(cds.getIdentityMap(item),null,null,indent + 2,false,refs);
                  }
               }
               else
               {
                  result = Managed.internalToString(item,indent,refs,null,null,false,false,cds);
               }
            }
         }
         finally
         {
            enablePaging();
         }
         return result;
      }
      
      static function unnormalize(item:Object) : Object
      {
         if(item is ManagedObjectProxy)
         {
            item = ManagedObjectProxy(item).object_proxy::object;
         }
         return item;
      }
      
      static function intersectArrays(arr1:Array, arr2:Array) : Array
      {
         if(arr1 == null)
         {
            return arr2;
         }
         if(arr2 == null)
         {
            return arr1;
         }
         var result:Array = [];
         for(var i:int = 0; i < arr1.length; i++)
         {
            if(ArrayUtil.getItemIndex(arr1[i],arr2) != -1)
            {
               result.push(arr1[i]);
            }
         }
         return result;
      }
      
      static function concatArrays(arr1:Array, arr2:Array) : Array
      {
         var result:Array = [];
         if(arr1 == null || arr1.length == 0)
         {
            return arr2;
         }
         if(arr2 == null || arr2.length == 0)
         {
            return arr1;
         }
         result = arr2.concat();
         for(var i:int = 0; i < arr1.length; i++)
         {
            if(ArrayUtil.getItemIndex(arr1[i],arr2) == -1)
            {
               result.push(arr1[i]);
            }
         }
         return result;
      }
      
      static function splitAndTrim(value:String, delimiter:String) : Array
      {
         var items:Array = null;
         var len:int = 0;
         var i:int = 0;
         if(value != "" && value != null)
         {
            items = value.split(delimiter);
            len = items.length;
            for(i = 0; i < len; i++)
            {
               items[i] = StringUtil.trim(items[i]);
            }
            return items;
         }
         return null;
      }
      
      public function get autoCommit() : Boolean
      {
         return this.dataStore.autoCommit;
      }
      
      public function set autoCommit(value:Boolean) : void
      {
         this.dataStore.autoCommit = value;
      }
      
      public function get ignoreCollectionUpdates() : Boolean
      {
         return this.dataStore.ignoreCollectionUpdates;
      }
      
      public function set ignoreCollectionUpdates(value:Boolean) : void
      {
         this.dataStore.ignoreCollectionUpdates = value;
      }
      
      public function get autoConnect() : Boolean
      {
         return this.dataStore.autoConnect;
      }
      
      public function set autoConnect(value:Boolean) : void
      {
         this.dataStore.autoConnect = value;
      }
      
      public function get encryptLocalCache() : Boolean
      {
         return this.dataStore.encryptLocalCache;
      }
      
      public function set encryptLocalCache(value:Boolean) : void
      {
         this.dataStore.encryptLocalCache = value;
      }
      
      public function get autoMerge() : Boolean
      {
         return this.dataStore.autoMerge;
      }
      
      public function set autoMerge(value:Boolean) : void
      {
         this.dataStore.autoMerge = value;
      }
      
      public function get autoSaveCache() : Boolean
      {
         return this.dataStore.autoSaveCache;
      }
      
      public function set autoSaveCache(value:Boolean) : void
      {
         this.dataStore.autoSaveCache = value;
      }
      
      public function get autoSyncEnabled() : Boolean
      {
         return this.metadata.autoSyncEnabled;
      }
      
      public function set autoSyncEnabled(value:Boolean) : void
      {
         this.metadata.autoSyncEnabled = value;
      }
      
      public function get cacheID() : String
      {
         return this.dataStore.cacheID;
      }
      
      public function set cacheID(value:String) : void
      {
         this.dataStore.cacheID = value;
      }
      
      public function get channelSet() : ChannelSet
      {
         if(this._dataStore == null)
         {
            return this.consumer.channelSet;
         }
         return this.dataStore.channelSet;
      }
      
      public function set channelSet(value:ChannelSet) : void
      {
         if(this.consumer.channelSet != value)
         {
            this.consumer.channelSet = value;
            this.dataStore.channelSet = value;
         }
      }
      
      public function set conflicts(c:Conflicts) : void
      {
         this._conflicts = c;
         if(c != null)
         {
            c.dataService = this;
         }
      }
      
      [Bindable(event="propertyChange")]
      public function get conflicts() : Conflicts
      {
         if(this._conflicts == null)
         {
            this._conflicts = new Conflicts(this);
         }
         return this._conflicts;
      }
      
      public function get commitRequired() : Boolean
      {
         if(this._dataStore == null)
         {
            return false;
         }
         return this.dataStore.commitRequired;
      }
      
      public function commitRequiredOn(object:Object) : Boolean
      {
         if(this._dataStore == null || object == null)
         {
            return false;
         }
         return this.dataStore.commitRequiredOn(object);
      }
      
      public function clearCache(value:Object = null) : AsyncToken
      {
         var token:AsyncToken = null;
         var ds:ConcreteDataService = null;
         this.checkCacheId();
         token = new AsyncToken(null);
         ds = this;
         var success:Function = function():void
         {
            if(value == null)
            {
               ds.dataStore.clearCache(ds,token);
            }
            else
            {
               ds.dataStore.clearCacheValue(ds,value,token);
            }
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],1);
         }
         return token;
      }
      
      public function clearCacheData(descriptor:CacheDataDescriptor) : AsyncToken
      {
         var token:AsyncToken = null;
         var ds:ConcreteDataService = null;
         this.checkCacheId();
         token = new AsyncToken(null);
         ds = this;
         var success:Function = function():void
         {
            dataStore.clearCacheData(ds,descriptor,token);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],1);
         }
         return token;
      }
      
      public function commit(itemsOrCollections:Array = null, cascadeCommit:Boolean = false) : AsyncToken
      {
         this.reconnect();
         return this.dataStore.internalCommit(this,itemsOrCollections,cascadeCommit);
      }
      
      public function connect() : AsyncToken
      {
         var result:AsyncToken = new AsyncToken(null);
         var oldValue:Boolean = this.autoConnect;
         try
         {
            this.dataStore.setAutoConnect(true);
            this.reconnect(result);
         }
         finally
         {
            this.dataStore.setAutoConnect(oldValue);
         }
         return result;
      }
      
      public function get conflictDetector() : ConflictDetector
      {
         if(this._conflictDetector == null)
         {
            this._conflictDetector = new ConflictDetector(this);
         }
         return this._conflictDetector;
      }
      
      public function set conflictDetector(value:ConflictDetector) : void
      {
         this._conflictDetector = value;
      }
      
      [Bindable(event="connectedChanged")]
      public function get connected() : Boolean
      {
         if(!this._shouldBeConnected)
         {
            return false;
         }
         if(this._dataStore == null)
         {
            return false;
         }
         return this.dataStore.connected;
      }
      
      [Bindable(event="propertyChange")]
      public function get subscribed() : Boolean
      {
         return this._consumer.subscribed;
      }
      
      public function get dataStore() : DataStore
      {
         if(this._dataStore == null)
         {
            Metadata.checkInverseAssociations();
            if(this.inAssociation || this.runtimeConfigured || Metadata.inverseAssociations[this.destination] || this.metadata.subTypeNames != null)
            {
               this._dataStore = DataStore.getSharedDataStore(this.destination,this.useTransactions,this.channelSet,this.adapter,this._offlineAdapter);
            }
            else
            {
               this._dataStore = new DataStore(this.destination,this.useTransactions,this.adapter,this._offlineAdapter);
               if(Log.isDebug())
               {
                  this._log.debug("Creating a new independent data store for destination: " + this.destination);
               }
            }
            this.setupNewDataStore();
         }
         return this._dataStore;
      }
      
      function checkAssociatedDataStores() : void
      {
         var propName:* = null;
         var association:ManagedAssociation = null;
         var i:int = 0;
         var other:ConcreteDataService = null;
         if(this._dataStore == null)
         {
            return;
         }
         if(this.metadata.isInitialized)
         {
            for(propName in this.metadata.associations)
            {
               association = ManagedAssociation(this.metadata.associations[propName]);
               if(association.service != null && association.service._dataStore != null && association.service._dataStore != this._dataStore)
               {
                  throw new DataServiceError("Destinations with associations must have the same data store: " + this.destination + " has dataStore: " + this._dataStore.identifier + " and " + association.service.destination + " has: " + association.service._dataStore.identifier);
               }
            }
            if(this._subTypes != null)
            {
               for(i = 0; i < this._subTypes.length; i++)
               {
                  other = ConcreteDataService(this._subTypes[i]);
                  if(other.dataStore != this._dataStore)
                  {
                     throw new DataServiceError("Destinations which extend each other must have the same data store: " + this.destination + " has DataStore: " + this._dataStore.identifier + " and " + other.destination + " has: " + other._dataStore.identifier);
                  }
               }
            }
         }
      }
      
      function initClassTreeDestinations(alreadyInitialized:Dictionary, success:Function = null, failed:Function = null, mode:int = 3) : Array
      {
         var invalidDestinations:Array = null;
         if(alreadyInitialized[this] != null)
         {
            return invalidDestinations;
         }
         alreadyInitialized[this] = true;
         if(mode & INIT_TREE_SUPER)
         {
            invalidDestinations = this.initDestinationList(this.metadata.extendsNames,null,success,failed,INIT_TREE_SUPER,alreadyInitialized);
         }
         if(mode & INIT_TREE_SUB)
         {
            invalidDestinations = this.initDestinationList(this.metadata.subTypeNames,invalidDestinations,success,failed,INIT_TREE_SUB,alreadyInitialized);
         }
         invalidDestinations = this.initDestinationList(this.metadata.associatedDestinationNames,invalidDestinations,success,failed,INIT_TREE_TYPE,alreadyInitialized);
         return invalidDestinations;
      }
      
      function initDestinationList(names:Array, invalidDestinations:Array, success:Function, failed:Function, mode:int, alreadyInitialized:Dictionary) : Array
      {
         var i:int = 0;
         var extService:ConcreteDataService = null;
         if(names != null)
         {
            for(i = 0; i < names.length; i++)
            {
               extService = getService(names[i]);
               if(this._dataStore != null)
               {
                  if(extService._dataStore == null)
                  {
                     extService.dataStore = this.dataStore;
                  }
               }
               if(!extService.metadata.isInitialized)
               {
                  if(!extService.metadata.initialize(success,failed,this.dataStore.getConfigCollection(extService)))
                  {
                     if(invalidDestinations == null)
                     {
                        invalidDestinations = [extService.destination];
                     }
                     else
                     {
                        invalidDestinations.push(extService.destination);
                     }
                  }
               }
               extService.initClassTreeDestinations(alreadyInitialized,success,failed,mode);
            }
         }
         return invalidDestinations;
      }
      
      public function set dataStore(ds:DataStore) : void
      {
         if(ds == this._dataStore)
         {
            return;
         }
         if(this._dataStore != null)
         {
            this._dataStore.removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.dataStorePropertyChangeHandler);
            this._dataStore.removeDataService(this);
            this._consumer.channelSet = null;
         }
         this._dataStore = ds;
         if(this._dataStore != null)
         {
            this.setupNewDataStore();
            this._consumer.channelSet = this._dataStore.channelSet;
         }
      }
      
      public function set offlineAdapter(adapter:DataServiceOfflineAdapter) : void
      {
         if(adapter != null)
         {
            this.setOfflineAdapterInternal(adapter);
         }
      }
      
      public function get offlineAdapter() : DataServiceOfflineAdapter
      {
         if(this._offlineAdapter != null)
         {
            if(this._offlineAdapter.localStore)
            {
               return this._offlineAdapter;
            }
            this.setOfflineAdapterInternal(this._offlineAdapter);
            return this._offlineAdapter;
         }
         this.setOfflineAdapterInternal(new DataServiceOfflineAdapter());
         return this._offlineAdapter;
      }
      
      private function setOfflineAdapterInternal(offlineAdapter:DataServiceOfflineAdapter) : void
      {
         this._offlineAdapter = offlineAdapter;
         this._offlineAdapter.destination = this.destination;
         if(this._dataStore)
         {
            this._offlineAdapter.localStore = this._dataStore.localStore;
            this._offlineAdapter.cacheID = this._dataStore.cacheID;
            this._offlineAdapter.dataStoreEventDispatcher = this._dataStore.dataStoreEventDispatcher;
         }
         if(this._offlineAdapterInitialized)
         {
            this.initializeOfflineAdapter();
         }
      }
      
      function initializeOfflineAdapter() : void
      {
         this.offlineAdapter.initializeOfflineMetadata(this.metadata);
         this._offlineAdapterInitialized = true;
      }
      
      public function get fallBackToLocalFill() : Boolean
      {
         return this.dataStore.fallBackToLocalFill;
      }
      
      public function set fallBackToLocalFill(value:Boolean) : void
      {
         this.dataStore.fallBackToLocalFill = value;
      }
      
      public function get destination() : String
      {
         return this._consumer.destination;
      }
      
      public function get indexReferences() : Boolean
      {
         return _indexReferences;
      }
      
      public function set indexReferences(ir:Boolean) : void
      {
         _indexReferences = ir;
      }
      
      public function get initialized() : Boolean
      {
         return this._dataStore != null && this._dataStore.isInitialized && this.metadata.isInitialized;
      }
      
      public function get manualSync() : ManualSyncConfiguration
      {
         return this._manualSync;
      }
      
      public function set manualSync(mr:ManualSyncConfiguration) : void
      {
         this._manualSync = mr;
         if(mr.dataService != null && mr.dataService != this)
         {
            throw new DataServiceError("The manualSync property cannot be shared by data services with different types.");
         }
         mr.dataService = this;
      }
      
      public function get maxFrequency() : uint
      {
         return this._consumer.maxFrequency;
      }
      
      public function set maxFrequency(value:uint) : void
      {
         this._consumer.maxFrequency = value;
      }
      
      public function get mergeRequired() : Boolean
      {
         return this.dataStore.mergeRequired;
      }
      
      public function get pagingEnabled() : Boolean
      {
         return this.metadata.pagingEnabled;
      }
      
      public function get pageSize() : int
      {
         return this.metadata.pageSize;
      }
      
      public function set pageSize(value:int) : void
      {
         this.metadata.pageSize = value;
      }
      
      public function get priority() : int
      {
         return this.dataStore.priority;
      }
      
      public function set priority(value:int) : void
      {
         this.dataStore.priority = value;
      }
      
      public function get requestTimeout() : int
      {
         return this.dataStore.requestTimeout;
      }
      
      public function set requestTimeout(value:int) : void
      {
         this.dataStore.requestTimeout = value;
      }
      
      public function get useTransactions() : Boolean
      {
         return this.metadata.useTransactions;
      }
      
      public function count(args:Array) : AsyncToken
      {
         var token:AsyncToken = null;
         if(Log.isDebug())
         {
            this._log.debug("DataService.count() called for destination: {0} with {1} arguments. {2}",this.destination,Boolean(args)?args.length:0,itemToString(args,this.destination));
         }
         var countMsg:DataMessage = new DataMessage();
         countMsg.operation = DataMessage.COUNT_OPERATION;
         countMsg.destination = this.destination;
         countMsg.clientId = this._consumer.clientId;
         this.addMaxFrequencyHeaderIfNecessary(countMsg);
         if(args)
         {
            if(args.length == 1)
            {
               countMsg.body = args[0];
            }
            else if(args.length > 1)
            {
               countMsg.body = args;
            }
         }
         token = new AsyncToken(countMsg);
         var success:Function = function():void
         {
            internalCount(token);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      public function createItem(item:Object) : ItemReference
      {
         var token:ItemReference = null;
         if(Log.isDebug())
         {
            this._log.debug("DataService.createItem() called for destination: {0} called with item:\n  {1}",this.destination,itemToString(item,this.destination));
         }
         token = new ItemReference(null);
         var success:Function = function():void
         {
            internalCreateItem(item,token);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      public function deleteItem(item:Object) : AsyncToken
      {
         var error:ErrorMessage = null;
         var fault:MessageFaultEvent = null;
         if(item == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullInputForDeleteItem"));
         }
         if(Log.isDebug())
         {
            this._log.debug("DataService.deleteItem() called for destination: {0} with item:\n  {1}",this.destination,itemToString(item,this.destination));
         }
         var leafDS:ConcreteDataService = this.getItemDestination(item);
         if(leafDS != this)
         {
            return leafDS.deleteItem(item);
         }
         this.reconnect();
         var uid:String = IManaged(item).uid;
         var token:AsyncToken = null;
         if(this._itemCache[uid] != null)
         {
            token = AsyncToken(this.removeItem(uid,true));
         }
         else if(this._releasedItems[item] != null)
         {
            this._itemCache[uid] = item;
            token = AsyncToken(this.removeItem(uid,true));
            delete this._itemCache[uid];
            delete this._releasedItems[item];
            delete this._releasedUIDs[uid];
         }
         else
         {
            error = this.createLocalCallError(resourceManager.getString("data","itemManagedByAnother",[uid,this.destination]));
            fault = MessageFaultEvent.createEvent(error);
            token = new AsyncToken(null);
            this.asyncDispatchFaultEvent(fault,token,this.getIdentityMap(item));
         }
         return token;
      }
      
      public function updateItem(item:Object, origItem:Object = null, changes:Array = null) : AsyncToken
      {
         var saveAutoCommit:Boolean = false;
         var i:int = 0;
         var token:AsyncToken = null;
         var uid:String = this.metadata.getUID(item);
         var managedItem:IManaged = this.getItem(uid);
         if(managedItem == null)
         {
            throw new ArgumentError("updateItem called with an item which is not managed on this client: " + this.destination + "." + uid);
         }
         if(managedItem != item)
         {
            saveAutoCommit = this.dataStore.autoCommit;
            if(changes == null)
            {
               var changes:Array = getObjectProperties(item);
            }
            try
            {
               this.dataStore.autoCommit = false;
               for(i = 0; i < changes.length; i++)
               {
                  managedItem[changes[i]] = item[changes[i]];
               }
            }
            finally
            {
               this.dataStore.restoreAutoCommit(saveAutoCommit);
            }
         }
         var msg:DataMessage = this.dataStore.messageCache.getLastUncommittedMessage(this,uid);
         if(msg != null)
         {
            if(origItem != null && origItem != DataMessage.unwrapItem(msg.body[DataMessage.UPDATE_BODY_PREV]))
            {
               msg.body[DataMessage.UPDATE_BODY_PREV] = DataMessage.wrapItem(this.copyItem(origItem),this.destination);
            }
            token = this.dataStore.getOrCreateToken(msg);
            if(this.autoCommit)
            {
               this.dataStore.commit([item]);
            }
            return token;
         }
         return null;
      }
      
      public function disconnect() : void
      {
         var names:Array = null;
         var associations:Object = null;
         var n:int = 0;
         var i:int = 0;
         var association:ManagedAssociation = null;
         this.clientIdsAdded = false;
         if(!this._disconnectBarrier)
         {
            this._disconnectBarrier = true;
            this._connecting = false;
            this._maxFrequencySent = false;
            this._shouldBeConnected = false;
            this._consumer.disconnect();
            this._manuallySubscribed = false;
            if(this._dataStore != null)
            {
               this._dataStore.disconnectDataStore();
            }
            names = this.metadata.associationNames;
            if(names != null && names.length > 0)
            {
               associations = this.metadata.associations;
               n = names.length;
               for(i = 0; i < n; i++)
               {
                  association = ManagedAssociation(associations[names[i]]);
                  association.service.disconnect();
               }
            }
         }
      }
      
      public function fill(view:ListCollectionView, args:Array, includeSpecifier:PropertySpecifier = null, singleResult:Boolean = false, localFill:Boolean = false, token:AsyncToken = null) : AsyncToken
      {
         if(includeSpecifier == null)
         {
            var includeSpecifier:PropertySpecifier = this.includeDefaultSpecifier;
         }
         if(Log.isDebug())
         {
            this._log.debug("DataService.fill() called for destination: {0} with args: {1} includesProperties: {2}",this.destination,itemToString(args,this.destination),includeSpecifier.toString());
         }
         if(token == null)
         {
            var token:AsyncToken = new AsyncToken(null);
         }
         var success:Function = function():void
         {
            internalFill(view,includeSpecifier,args,token,singleResult,localFill);
         };
         var failed:Function = function(details:String):void
         {
            var msg:DataMessage = new DataMessage();
            msg.operation = DataMessage.FILL_OPERATION;
            token.setMessage(msg);
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(view == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullViewInputForFill"));
         }
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      public function synchronizeFill(fillArgs:Array) : AsyncToken
      {
         var reloadFromCache:Boolean = false;
         var dataList:DataList = null;
         var token:AsyncToken = null;
         var thisCds:ConcreteDataService = null;
         if(!fillArgs)
         {
            var fillArgs:Array = [];
         }
         reloadFromCache = false;
         dataList = this.getDataListWithFillParams(fillArgs);
         if(dataList)
         {
            dataList.ensureSynchronizeSupported();
         }
         else
         {
            dataList = new DataList(this);
            dataList.fillParameters = this.copyFillArgs(fillArgs);
            dataList.view = new ArrayCollection();
            dataList.view.list = dataList;
            reloadFromCache = true;
         }
         token = new AsyncToken(null);
         thisCds = this;
         var success:Function = function():void
         {
            if(reloadFromCache)
            {
               try
               {
                  dataStore.reloadDataList(dataList,thisCds);
               }
               catch(pending:ItemPendingError)
               {
                  throw new Error(resourceManager.getString("data","cannotSynchronizeFill"));
               }
            }
            internalSyncFill(fillArgs,token);
         };
         var failed:Function = function(details:String):void
         {
            var msg:DataMessage = new DataMessage();
            msg.operation = DataMessage.SYNCHRONIZE_FILL_OPERATION;
            token.setMessage(msg);
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      public function synchronizeAllFills() : AsyncToken
      {
         var dataList:DataList = null;
         var fillArgs:Array = null;
         var token:AsyncTokenChain = new AsyncTokenChain();
         var allLists:Array = this._dataLists.toArray();
         if(allLists.length > 0)
         {
            for each(dataList in allLists)
            {
               fillArgs = dataList.fillParameters as Array;
               if(fillArgs)
               {
                  token.addPendingInvocation(this.synchronizeFill,fillArgs);
               }
            }
         }
         else
         {
            token.applyFinalResultLater();
         }
         return token;
      }
      
      public function applyChangedItems(changedItems:ChangedItems) : AsyncToken
      {
         var applyToken:AsyncTokenChain = null;
         var refreshAllLocalFills:Function = function():void
         {
            var currDataList:DataList = null;
            for each(currDataList in _dataLists.toArray())
            {
               applyToken.addPendingInvocation(refreshLocalFill,currDataList);
            }
         };
         applyToken = new AsyncTokenChain();
         applyToken.setResult(changedItems);
         var dataList:DataList = this.getDataListWithFillParams(changedItems.fillParameters);
         if(!dataList)
         {
            dataList = new DataList(this);
            dataList.fillParameters = changedItems.fillParameters;
         }
         dataList.fillTimestamp = new Date(changedItems.resultTimestamp);
         if(!dataList.view)
         {
            dataList.view = new ArrayCollection();
            dataList.view.list = dataList;
         }
         var oldAutoSave:Boolean = this.dataStore.autoSaveCache;
         try
         {
            this.dataStore.autoSaveCache = false;
            this.disableLogging();
            disablePaging();
            dataList.listChanged();
            this.applyDeletedItems(dataList,changedItems.deletedItemIds);
            this.applyUpdatedItems(dataList,changedItems.updatedItems);
            this.applyUpdatedItems(dataList,changedItems.createdItems);
         }
         finally
         {
            enablePaging();
            this.enableLogging();
            this.dataStore.restoreAutoSaveCache(oldAutoSave);
         }
         var faultsOnly:Boolean = false;
         var asyncOnly:Boolean = true;
         var saveCompleteToken:AsyncToken = new AsyncToken();
         saveCompleteToken.addResponder(new AsyncResponder(refreshAllLocalFills,this.dispatchDataServiceFaultEvent));
         this.dataStore.saveCache(null,faultsOnly,null,saveCompleteToken,asyncOnly);
         return applyToken;
      }
      
      private function refreshLocalFill(dataList:DataList) : AsyncToken
      {
         var fillToken:AsyncToken = null;
         var fillArgs:Array = dataList.fillParameters as Array;
         if(fillArgs && dataList.isSynchronizeSupported)
         {
            fillToken = new AsyncToken();
            this.internalFill(dataList.view,PropertySpecifier.ALL,fillArgs,fillToken,false,true);
            return fillToken;
         }
         return null;
      }
      
      private function applyUpdatedItems(dataList:DataList, updatedItems:Array) : void
      {
         var newItems:Array = null;
         var i:int = 0;
         var updatedItem:IManaged = null;
         var uid:String = null;
         var index:int = 0;
         var cachedItem:Object = null;
         var associationIds:Object = null;
         if(updatedItems)
         {
            newItems = [];
            for(i = 0; i < updatedItems.length; i++)
            {
               updatedItem = updatedItems[i];
               uid = this.metadata.getUID(updatedItem);
               if(uid)
               {
                  updatedItem.uid = uid;
                  index = dataList.getUIDIndex(uid);
                  if(index < 0)
                  {
                     newItems.push(updatedItem);
                  }
                  else
                  {
                     cachedItem = this.getItemForReference(uid,false);
                     if(cachedItem)
                     {
                        associationIds = this.metadata.getReferencedIds(updatedItem);
                        this.updateItemInCache(cachedItem,updatedItem,null,null,associationIds);
                        updatedItems[i] = cachedItem;
                     }
                     else
                     {
                        this.addItemToOffline(uid,updatedItem);
                     }
                  }
               }
            }
            this.applyCreatedItems(dataList,newItems);
         }
      }
      
      private function applyCreatedItems(dataList:DataList, createdItems:Array) : void
      {
         var item:IManaged = null;
         var uid:String = null;
         var commit:Boolean = false;
         var configureNew:Boolean = false;
         var associationIds:Object = null;
         if(createdItems)
         {
            for each(item in createdItems)
            {
               uid = this.metadata.getUID(item);
               item.uid = uid;
               commit = false;
               configureNew = true;
               associationIds = this.metadata.getReferencedIds(item);
               this.addItem(item,DataMessage.CREATE_OPERATION,commit,configureNew,associationIds);
               this.addItemToOffline(uid,item);
               dataList.addItemReferenceAt(uid,dataList.length);
            }
         }
      }
      
      private function applyDeletedItems(dataList:DataList, deletedItemIds:Array) : void
      {
         var identity:Object = null;
         var uid:String = null;
         if(deletedItemIds)
         {
            for each(identity in deletedItemIds)
            {
               identity = this.getSimpleOrComplexIdentityMap(identity);
               uid = this.metadata.getUID(identity);
               if(uid)
               {
                  this.removeItem(uid,false,true);
               }
            }
         }
      }
      
      public function executeQuery(queryName:String, propertySpecifier:PropertySpecifier, args:Array, singleResult:Boolean = false, localFill:Boolean = false) : AsyncToken
      {
         var fillParams:Array = new Array(args.length + 1);
         fillParams[0] = queryName;
         for(var i:int = 0; i < args.length; i++)
         {
            fillParams[i + 1] = args[i];
         }
         var ac:ArrayCollection = new ArrayCollection();
         return this.fill(ac,fillParams,propertySpecifier,singleResult,localFill);
      }
      
      public function refreshCollection(view:ListCollectionView) : AsyncToken
      {
         var dataList:DataList = null;
         var tokens:Array = null;
         if(Log.isDebug())
         {
            this._log.debug("DataService.refreshCollection() called for destination: {0}",this.destination);
         }
         this.reconnect();
         if(view.list is DataList)
         {
            dataList = DataList(view.list);
            if(this._dataLists.getItemIndex(dataList) == -1)
            {
               throw new DataServiceError(resourceManager.getString("data","collectionManagedByAnother"));
            }
            tokens = new Array();
            this.refreshDataList(dataList,tokens);
            if(tokens.length == 0)
            {
               return null;
            }
            return AsyncToken(tokens[tokens.length - 1]);
         }
         throw new DataServiceError("DataService.refreshFill called for an array collection which is not managed");
      }
      
      public function refresh() : AsyncToken
      {
         var tokens:Array = new Array();
         return this.internalRefresh(tokens);
      }
      
      function internalRefresh(tokens:Array) : AsyncToken
      {
         var dataList:DataList = null;
         var lastToken:AsyncToken = null;
         var resultToken:AsyncToken = null;
         if(Log.isDebug())
         {
            this._log.debug("DataService.refresh() called for destination: {0}",this.destination);
         }
         var staleReferences:Object = new Object();
         for(var i:uint = 0; i < this._dataLists.length; i++)
         {
            dataList = DataList(this._dataLists.getItemAt(i));
            this.refreshDataList(dataList,tokens,staleReferences);
         }
         if(tokens.length > 0)
         {
            lastToken = tokens[tokens.length - 1];
            resultToken = new AsyncToken(null);
            resultToken.staleReferences = staleReferences;
            lastToken.addResponder(new AsyncResponder(this.doRefreshStaleReferences,this.sendRefreshFault,resultToken));
            return resultToken;
         }
         this.refreshStaleReferences(staleReferences,tokens);
         if(tokens.length > 0)
         {
            return tokens[tokens.length - 1];
         }
         return null;
      }
      
      private function doRefreshStaleReferences(data:Object, token:Object) : void
      {
         var lastToken:AsyncToken = null;
         this._reconnecting = false;
         var tokens:Array = new Array();
         this.refreshStaleReferences(token.staleReferences,tokens);
         if(tokens.length == 0)
         {
            this.dispatchResultEvent(MessageEvent(data),AsyncToken(token),null);
         }
         else
         {
            lastToken = tokens[tokens.length - 1];
            lastToken.addResponder(new AsyncResponder(this.sendRefreshResult,this.sendRefreshFault,token));
         }
      }
      
      private function sendRefreshResult(data:Object, token:Object) : void
      {
         this.dispatchResultEvent(MessageEvent(data),AsyncToken(token),null);
      }
      
      private function sendRefreshFault(data:Object, token:Object) : void
      {
         this._reconnecting = false;
         this.dispatchDataServiceFaultEvent(DataServiceFaultEvent(data),AsyncToken(token),false);
      }
      
      private function refreshStaleReferences(staleReferences:Object, tokens:Array) : void
      {
         var uid:* = null;
         var dls:Array = null;
         var dataList:DataList = null;
         var ix:int = 0;
         for(uid in staleReferences)
         {
            dls = this.getAllDataLists(uid,true);
            if(dls != null && dls.length > 0)
            {
               dataList = dls[0];
               ix = dataList.getUIDIndex(uid);
               if(ix != -1)
               {
                  dls[0].requestItemAt(ix,0,null,true,tokens);
               }
            }
         }
      }
      
      public function getCacheData(descriptor:CacheDataDescriptor) : AsyncToken
      {
         var token:AsyncToken = null;
         var ds:ConcreteDataService = null;
         this.checkCacheId();
         token = descriptor.type == CacheDataDescriptor.FILL?new AsyncToken(null):new ItemReference(null);
         ds = this;
         var success:Function = function():void
         {
            dataStore.getCacheData(ds,descriptor,token);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],10);
         }
         return token;
      }
      
      public function getCacheDescriptors(view:ListCollectionView, options:uint = 0, item:Object = null) : AsyncToken
      {
         var result:AsyncToken = null;
         var cds:ConcreteDataService = null;
         this.checkCacheId();
         result = new AsyncToken(null);
         if(view == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullViewInputForFill"));
         }
         cds = this;
         var success:Function = function():void
         {
            dataStore.getCacheDescriptors(cds,view,options,item,result);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),result);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],10);
         }
         return result;
      }
      
      public function getCacheIDs(view:ListCollectionView) : AsyncToken
      {
         var result:AsyncToken = null;
         var cds:ConcreteDataService = null;
         result = new AsyncToken(null);
         if(view == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullViewInputForFill"));
         }
         cds = this;
         var success:Function = function():void
         {
            dataStore.internalGetCacheIDs(cds,view,result);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),result);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],10);
         }
         return result;
      }
      
      public function getItem(identity:Object, defaultValue:Object = null) : ItemReference
      {
         var token:ItemReference = null;
         token = new ItemReference(null);
         var success:Function = function():void
         {
            internalGetItem(identity,defaultValue,token);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      public function getLocalItem(identity:Object) : Object
      {
         var uid:String = this.metadata.getUID(identity);
         if(uid == null)
         {
            throw new DataServiceError("Null identity passed into getLocalItem");
         }
         return this.getItem(uid);
      }
      
      public function getIdentityMap(value:Object) : Object
      {
         var prop:String = null;
         var result:Object = {};
         var uidProps:Array = this.metadata.identities;
         if(value is ObjectProxy)
         {
            value = ObjectProxy(value).object_proxy::object;
         }
         for(var i:int = 0; i < uidProps.length; i++)
         {
            prop = uidProps[i];
            result[prop] = value[prop];
         }
         return result;
      }
      
      private function getSimpleOrComplexIdentityMap(identity:Object) : Object
      {
         var identityField:String = null;
         var map:Object = null;
         if(identity is String || identity is Number || identity is int || identity is uint)
         {
            if(this.metadata.identities.length != 1)
            {
               throw new Error(resourceManager.getString("data","cannotDetermineIdentity",[identity]));
            }
            identityField = this.metadata.identities[0];
            map = {};
            map[identityField] = identity;
            return map;
         }
         return this.getIdentityMap(identity);
      }
      
      public function isRangeResident(view:ListCollectionView, startIndex:int, numberOfItems:int) : Boolean
      {
         var max:int = 0;
         var references:Array = null;
         var uid:String = null;
         var i:int = 0;
         if(view == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullViewInputForFill"));
         }
         var dataList:DataList = view.list as DataList;
         if(view.list != null)
         {
            max = startIndex + numberOfItems;
            if(dataList.referenceCount == 0)
            {
               throw new DataServiceError(resourceManager.getString("data","collectionNotManaged"));
            }
            if(startIndex < 0 || numberOfItems < 0 || max > dataList.length)
            {
               throw new DataServiceError(resourceManager.getString("data","invalidRangeInIsRangeResident",[this.destination,startIndex,numberOfItems]));
            }
            references = dataList.references;
            if(max > references.length)
            {
               return false;
            }
            for(i = startIndex; i < max; i++)
            {
               uid = references[i];
               if(uid == null || dataList.service.getItem(uid) == null)
               {
                  return false;
               }
            }
            return true;
         }
         throw new DataServiceError(resourceManager.getString("data","collectionNotManaged"));
      }
      
      public function getPageInformation(view:ListCollectionView) : PageInformation
      {
         var dataList:DataList = null;
         var references:Array = null;
         var uid:String = null;
         var loadedPages:Object = null;
         var pageSize:int = 0;
         var i:int = 0;
         if(view == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullViewInputForFill"));
         }
         if(view.list is DataList)
         {
            dataList = DataList(view.list);
            if(this._dataLists.getItemIndex(dataList) == -1)
            {
               throw new DataServiceError(resourceManager.getString("data","collectionManagedByAnother"));
            }
            references = dataList.references;
            loadedPages = {};
            pageSize = this.metadata.pageSize;
            for(i = 0; i < references.length; i = i + pageSize)
            {
               uid = references[i];
               if(uid != null && this._itemCache[uid] != null)
               {
                  loadedPages[i] = true;
               }
            }
            return new PageInformation(pageSize,dataList.length / pageSize,loadedPages);
         }
         throw new DataServiceError(resourceManager.getString("data","collectionNotManaged"));
      }
      
      public function getPendingOperation(item:Object) : uint
      {
         if(item != null)
         {
            return this.dataStore.messageCache.getLastUncommittedOperation(this,this.getItemCacheId(item));
         }
         return DataMessage.UNKNOWN_OPERATION;
      }
      
      public function initialize() : AsyncToken
      {
         var result:AsyncToken = null;
         result = new AsyncToken(null);
         var success:Function = function():void
         {
            var event:DataServiceResultEvent = DataServiceResultEvent.createEvent(null,result,null);
            new AsyncDispatcher(dispatchResultEvent,[event,result,null],1);
         };
         var failed:Function = function(details:String):void
         {
            asyncDispatchFaultEvent(getFailedInitializationFault(details),result);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            success();
         }
         return result;
      }
      
      public function logout() : void
      {
         this.dataStore.release();
         this._consumer.logout();
         this.dataStore.logout();
      }
      
      public function merge() : void
      {
         this.dataStore.merge();
      }
      
      public function release(clear:Boolean = true, copyStillManagedItems:Boolean = true) : void
      {
         this.internalRelease(clear,copyStillManagedItems);
      }
      
      public function isCollectionManaged(view:ListCollectionView) : Boolean
      {
         var dataList:DataList = view.list as DataList;
         if(dataList == null)
         {
            return false;
         }
         return dataList.service == this && dataList.referenceCount > 0;
      }
      
      public function isCollectionPaged(view:ListCollectionView) : Boolean
      {
         var dataList:DataList = view.list as DataList;
         return dataList != null && (dataList.association == null || dataList.association.paged);
      }
      
      public function releaseCollection(view:ListCollectionView, clear:Boolean = false, copyStillManagedItems:Boolean = true) : void
      {
         var dataList:DataList = null;
         var items:Array = null;
         this.checkInitialized();
         if(view.list is DataList)
         {
            dataList = DataList(view.list);
            items = this.releaseDataList(dataList,copyStillManagedItems,clear,new Dictionary(),null,false,true);
            if(clear || copyStillManagedItems)
            {
               view.list = new ArrayList(!!clear?[]:items);
            }
            return;
         }
         throw new DataServiceError(resourceManager.getString("data","invalidReleaseCollection",[this.destination]));
      }
      
      public function releaseItem(item:IManaged, dontClearStillManagedItems:Boolean = true, copyStillManagedItems:Boolean = true) : IManaged
      {
         var dl:DataList = null;
         var leafDS:ConcreteDataService = null;
         var items:Array = null;
         this.checkInitialized();
         var result:IManaged = null;
         if(item && this._itemCache[item.uid])
         {
            dl = this.getSMODataList(item);
            if(dl)
            {
               items = this.releaseDataList(dl,copyStillManagedItems,!dontClearStillManagedItems,new Dictionary(),null,false,true);
               if(items && items.length > 0)
               {
                  result = items[0];
               }
               else
               {
                  result = item;
               }
            }
            leafDS = this.getItemDestination(item);
            if(this._itemCache[item.uid] && !leafDS.isItemReferenced(item,new Dictionary(),new Object()))
            {
               this.removeItemFromCache(item.uid);
               if(!result)
               {
                  result = item;
               }
            }
         }
         return result;
      }
      
      public function releaseItemsFromCollection(collection:ListCollectionView, startIndex:int, numberOfItems:int) : int
      {
         var noOp:Function = null;
         var dataList:DataList = collection.list as DataList;
         if(dataList == null || dataList.referenceCount == 0)
         {
            if(Log.isWarn())
            {
               this._log.warn("releaseItemsFromCollection called with: " + (dataList == null?"unmanaged list":"a managed list which has been released"));
            }
            return 0;
         }
         if(startIndex < 0 || numberOfItems < 0 || startIndex + numberOfItems > dataList.length)
         {
            throw new DataServiceError(resourceManager.getString("data","invalidReleaseItemsFromCollection",[this.destination,startIndex,numberOfItems]));
         }
         if(numberOfItems == 0)
         {
            return 0;
         }
         var releaseMessage:DataMessage = this.getReleaseMessage(dataList,startIndex,numberOfItems);
         if(releaseMessage != null)
         {
            noOp = function(x:Object, y:AsyncToken):void
            {
            };
            this.dataStore.invoke(releaseMessage,new AsyncResponder(noOp,noOp));
         }
         return dataList.releaseItemsFromCollection(startIndex,numberOfItems);
      }
      
      public function releaseReference(item:Object, prop:String) : Boolean
      {
         var refItem:IManaged = null;
         var assoc:ManagedAssociation = this.metadata.associations[prop];
         if(assoc == null)
         {
            throw new DataServiceError("releaseReference called for destination: " + this.destination + "." + prop + ".\n\tProperty \'" + prop + "\' not found in this context.");
         }
         if(assoc.typeCode != ManagedAssociation.ONE)
         {
            if(assoc.typeCode == ManagedAssociation.MANY)
            {
               throw new DataServiceError("releaseReference called for destination: " + this.destination + "." + prop + ".\n\tThe property \'" + prop + "\' represents a collection. Use releaseCollection() or releaseItemsFromCollection()");
            }
            throw new DataServiceError("releaseReference called for destination: " + this.destination + "." + prop + ".\n\tThe property \'" + prop + "\' is not a single-valued association (one-to-one).");
         }
         try
         {
            this.disableLogging();
            disablePaging();
            refItem = item[prop] as IManaged;
            if(refItem != null)
            {
               assoc.service.removeItemFromCache(refItem.uid);
               item[prop] = null;
            }
         }
         finally
         {
            enablePaging();
            this.enableLogging();
         }
         return true;
      }
      
      public function resolveReference(item:Object, assoc:ManagedAssociation) : Object
      {
         var uid:String = null;
         var dataList:DataList = null;
         var userPendingError:ItemPendingError = null;
         var referencedIdTable:Object = item.referencedIds;
         var identity:Object = referencedIdTable == null?null:referencedIdTable[assoc.property];
         var childItem:Object = null;
         if(identity != null)
         {
            if(assoc.typeCode != ManagedAssociation.ONE)
            {
               throw new DataServiceError(resourceManager.getString("data","resolveReferenceNotSingleAssociation",[assoc.property]));
            }
            uid = identity is String?identity as String:assoc.service.metadata.getUID(identity);
            childItem = assoc.service.getItemForReference(uid);
            if(childItem == null)
            {
               dataList = this.getDataListForAssociation(item,assoc);
               userPendingError = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
               if(dataList != null)
               {
                  try
                  {
                     dataList.requestItemAt(0);
                  }
                  catch(sysPendingError:ItemPendingError)
                  {
                     sysPendingError.addResponder(new ResolveReferenceResponder(item,assoc.property,uid,this,assoc.service,userPendingError));
                     throw userPendingError;
                  }
               }
            }
         }
         else if(assoc.loadOnDemand)
         {
            dataList = this.getDataListForAssociation(item,assoc);
            if(dataList != null)
            {
               dataList.fetchValue();
            }
         }
         return childItem;
      }
      
      public function fetchItemProperty(item:IManaged, prop:String) : void
      {
         if(ConcreteDataService.pagingDisabled > 0)
         {
            return;
         }
         var refs:Array = this.getAllDataLists(item.uid,false);
         if(refs == null || refs.length == 0)
         {
            return;
         }
         var refDataList:DataList = DataList(refs[0]);
         for(var i:int = 0; i < refs.length; i++)
         {
            if(refs[i].sequenceId >= 0)
            {
               refDataList = DataList(refs[i]);
               break;
            }
         }
         refDataList.fetchItemProperty(item,prop);
      }
      
      public function revertChanges(item:IManaged = null) : Boolean
      {
         return this.dataStore.doRevertChanges(this,item);
      }
      
      public function revertChangesForCollection(collection:ListCollectionView = null) : Boolean
      {
         return this.dataStore.doRevertChanges(this,null,collection);
      }
      
      public function saveCache(value:Object) : AsyncToken
      {
         var token:AsyncToken = null;
         var ds:ConcreteDataService = null;
         this.checkCacheId();
         token = new AsyncToken(null);
         ds = this;
         var success:Function = function():void
         {
            dataStore.saveCache(ds,false,value,token,false);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.initialized)
         {
            this.dataStore.initialize(success,failed);
         }
         else
         {
            new AsyncDispatcher(success,[],1);
         }
         return token;
      }
      
      public function setCredentials(username:String, password:String) : void
      {
         this.dataStore.setCredentials(username,password);
         this._consumer.setCredentials(username,password);
      }
      
      public function setRemoteCredentials(username:String, password:String) : void
      {
         this.dataStore.setRemoteCredentials(username,password);
         this._consumer.setRemoteCredentials(username,password);
      }
      
      public function get itemClassDynamicProperties() : Array
      {
         return Boolean(this.metadata)?this.metadata.itemClassDynamicProperties:[];
      }
      
      public function setItemClassDynamicProperties(newProperties:Array) : void
      {
         Metadata.validateDynamicProperties(newProperties);
         if(this.metadata && this._dataStore)
         {
            if(!this.metadata.hasMatchingDynamicProperties(newProperties))
            {
               if(this.dataStore.localStore.empty || this.allowDynamicPropertyChangesWithCachedData)
               {
                  this.metadata.itemClassDynamicProperties = newProperties;
                  this.metadata.serverConfigChanged = true;
               }
               else
               {
                  throw new Error(resourceManager.getString("data","dynamicPropertiesCannotChangeWithCache"));
               }
            }
            return;
         }
         throw new Error("cannot apply properties without metadata and dataStore");
      }
      
      public function get allowDynamicPropertyChangesWithCachedData() : Boolean
      {
         return this._allowDynamicPropertyChangesWithCachedData;
      }
      
      public function set allowDynamicPropertyChangesWithCachedData(value:Boolean) : void
      {
         this._allowDynamicPropertyChangesWithCachedData = value;
      }
      
      function get consumer() : MultiTopicConsumer
      {
         return this._consumer;
      }
      
      function get dataLists() : ArrayList
      {
         return this._dataLists;
      }
      
      function get id() : String
      {
         return this._consumer.id;
      }
      
      function get log() : ILogger
      {
         return this._log;
      }
      
      function get logChanges() : int
      {
         return this.dataStore.logChanges;
      }
      
      function get needsConfig() : Boolean
      {
         return this.runtimeConfigured && !this.metadata.isInitialized;
      }
      
      function get reconnecting() : Boolean
      {
         return this._reconnecting;
      }
      
      function addDataList(dataList:DataList) : void
      {
         this._dataLists.addItem(dataList);
      }
      
      function getManagedItemUID(item:Object) : String
      {
         var uid:String = this.metadata.getUID(item);
         if(this._itemCache[uid] != null)
         {
            return uid;
         }
         var identity:Object = this.dataStore.messageCache.getCreateMessageIdentity(this,item);
         if(identity is String)
         {
            return identity as String;
         }
         return this.metadata.getUID(identity);
      }
      
      function convertIdentitiesToUIDs(arr:Array) : Array
      {
         if(arr == null)
         {
            return null;
         }
         var uidArr:Array = new Array(arr.length);
         for(var i:int = 0; i < arr.length; i++)
         {
            if(arr[i] is String)
            {
               uidArr[i] = arr[i];
            }
            else
            {
               uidArr[i] = this.metadata.getUID(arr[i]);
            }
         }
         return uidArr;
      }
      
      function addItem(item:Object, op:uint = 0, commit:Boolean = true, configureNew:Boolean = false, referencedIds:Object = null, pendingItems:Object = null, clientReferencedIds:Boolean = false) : Object
      {
         var addToCache:Boolean = false;
         var newMsg:DataMessage = null;
         var added:Boolean = false;
         var msg:DataMessage = null;
         var leafDS:ConcreteDataService = this.getItemDestination(item);
         if(leafDS != this)
         {
            return leafDS.addItem(item,op,commit,configureNew,referencedIds,pendingItems,clientReferencedIds);
         }
         var uid:String = this.metadata.getUID(item);
         var result:Object = {
            "uid":uid,
            "message":null,
            "added":false
         };
         if(this.getItem(uid) == null)
         {
            addToCache = true;
            if(this._releasedItems[item] != null || this._releasedUIDs != null && this._releasedUIDs[uid] != null)
            {
               if(Log.isDebug())
               {
                  this._log.debug("Adding released item back into the cache: " + uid + " destination: " + this.destination);
               }
               delete this._releasedItems[item];
               delete this._releasedUIDs[item.uid];
               if(item == null)
               {
                  var item:Object = this.getItemForReference(uid);
               }
               this.putItemInCache(item.uid,item);
               addToCache = false;
            }
            newMsg = this.dataStore.messageCache.getCreateMessage(this,item);
            added = false;
            if(newMsg != null)
            {
               result.uid = newMsg.messageId;
               result.message = newMsg;
               return result;
            }
            try
            {
               this.checkAssociations(item);
               if(this.logChanges == 0)
               {
                  uid = this.addNestedForwardReferences(item);
                  this.addNestedAssociations(item,true,pendingItems);
                  newMsg = this.dataStore.messageCache.getCreateMessage(this,item);
                  if(newMsg != null)
                  {
                     result.uid = newMsg.messageId;
                     result.message = newMsg;
                     result.added = true;
                     added = true;
                  }
               }
               item = this.normalize(item);
               if(configureNew && !added)
               {
                  this.getItemMetadata(item).configureItem(this,item,item,this.logChanges == 0?this.includeAllSpecifier:this.includeDefaultSpecifier,null,referencedIds,false,this.logChanges == 0,pendingItems,false,clientReferencedIds);
               }
               if(this.logChanges == 0)
               {
                  if(addToCache && !added)
                  {
                     IManaged(item).uid = uid;
                     msg = this.dataStore.messageCache.logCreate(this,item,op);
                     uid = msg.messageId;
                     result.uid = uid;
                     result.message = msg;
                     if(this.autoSyncEnabled)
                     {
                        this.addAssociationClientIdsToMessage(msg);
                     }
                  }
                  if(commit && this.dataStore.autoCommitCollectionChanges)
                  {
                     this.dataStore.doAutoCommit(CommitResponder);
                  }
                  this.addNestedAssociations(item,false,pendingItems);
               }
               else
               {
                  IManaged(item).uid = uid;
               }
               if(!added)
               {
                  if(addToCache)
                  {
                     this.addChangeListener(IManaged(item));
                     this.putItemInCache(uid,item);
                     if(Log.isDebug())
                     {
                        this._log.debug("Adding item to cache: " + uid + " destination: " + this.destination);
                     }
                  }
                  result.added = true;
                  if(this.dataStore.autoSaveCache)
                  {
                     this.dataStore.saveCache(null,true);
                  }
               }
            }
            finally
            {
               if(pendingItems == null)
               {
                  this.dataStore.messageCache.clearForwardRefs();
               }
            }
         }
         return result;
      }
      
      function putItemInCache(uid:String, item:Object) : void
      {
         var persistingAtLeaf:Boolean = this.offlineAdapter.isQuerySupported();
         if(persistingAtLeaf)
         {
            this.putItemInCacheInternal(uid,item,false);
            this.addItemToOffline(uid,IManaged(item));
         }
         else
         {
            this.putItemInCacheInternal(uid,item,true);
            this.rootDataService.addItemToOffline(uid,IManaged(item));
         }
      }
      
      private function putItemInCacheInternal(uid:String, item:Object, putInParent:Boolean) : void
      {
         var i:int = 0;
         this._itemCache[uid] = item;
         this.numItems++;
         if(putInParent)
         {
            if(this.extendsDestinations != null)
            {
               for(i = 0; i < this.extendsDestinations.length; i++)
               {
                  ConcreteDataService(this.extendsDestinations[i]).putItemInCacheInternal(uid,item,putInParent);
               }
            }
         }
      }
      
      function removeItemFromCache(uid:String, removeFromOffline:Boolean = false) : void
      {
         var itemToRemove:IManaged = null;
         var rootDS:ConcreteDataService = null;
         var persistingAtLeaf:Boolean = this.offlineAdapter.isQuerySupported();
         if(persistingAtLeaf)
         {
            itemToRemove = this._itemCache[uid];
            this.removeItemFromCacheInternal(uid,false);
            if(removeFromOffline)
            {
               this.removeItemFromOffline(uid,itemToRemove);
            }
         }
         else
         {
            rootDS = this.rootDataService;
            itemToRemove = rootDS.getItem(uid);
            this.removeItemFromCacheInternal(uid,true);
            if(removeFromOffline)
            {
               rootDS.removeItemFromOffline(uid,itemToRemove);
            }
         }
      }
      
      private function removeItemFromCacheInternal(uid:String, removeFromParent:Boolean) : void
      {
         var i:int = 0;
         if(removeFromParent)
         {
            if(this.extendsDestinations != null)
            {
               for(i = 0; i < this.extendsDestinations.length; i++)
               {
                  ConcreteDataService(this.extendsDestinations[i]).removeItemFromCacheInternal(uid,removeFromParent);
               }
            }
         }
         if(delete this._itemCache[uid])
         {
            this.numItems--;
         }
      }
      
      function addItemToOffline(uid:String, item:IManaged, updatedPropName:String = null) : void
      {
         var propList:Array = null;
         if(this.offlineDirtyList != null)
         {
            delete this.offlineDirtyList[uid];
            if(item)
            {
               propList = this.offlineDirtyList[item];
               if(propList == null)
               {
                  this.offlineDirtyList[item] = propList = new Array();
                  if(updatedPropName)
                  {
                     propList.push(updatedPropName);
                  }
               }
               else if(propList.length > 0)
               {
                  if(updatedPropName)
                  {
                     if(propList.indexOf(updatedPropName) < 0)
                     {
                        propList.push(updatedPropName);
                     }
                  }
                  else
                  {
                     propList.splice(0,propList.length);
                  }
               }
            }
         }
         this.requiresSave = true;
      }
      
      function removeItemFromOffline(uid:String, item:IManaged) : void
      {
         if(this.offlineDirtyList != null)
         {
            if(item)
            {
               delete this.offlineDirtyList[item];
            }
            this.offlineDirtyList[uid] = null;
         }
         this.requiresSave = true;
      }
      
      function checkAssociations(item:Object) : void
      {
         var propName:String = null;
         var association:ManagedAssociation = null;
         var propVal:* = undefined;
         var isArray:Boolean = false;
         var m:String = null;
         var md:Metadata = this.getItemMetadata(item);
         for(propName in md.associations)
         {
            association = ManagedAssociation(md.associations[propName]);
            try
            {
               propVal = item[propName];
               if(propVal == null)
               {
                  if(association.typeCode == ManagedAssociation.MANY)
                  {
                     item[propName] = new ArrayCollection();
                  }
                  continue;
               }
               isArray = propVal is ListCollectionView;
               if(isArray && association.typeCode != ManagedAssociation.MANY)
               {
                  m = "Single-valued association: " + this.destination + "." + propName + " is an ArrayCollection type - expected a managed object for destination: " + association.destination;
                  if(Log.isDebug())
                  {
                     this._log.debug(m);
                  }
                  throw new DataServiceError(m);
               }
               if(!isArray && association.typeCode == ManagedAssociation.MANY)
               {
                  m = "Multi-valued association: " + this.destination + "." + propName + " does not define an ArrayCollection type. - type is: " + getQualifiedClassName(propVal) + " instead.";
                  if(Log.isDebug())
                  {
                     this._log.debug(m);
                  }
                  throw new DataServiceError(m);
               }
            }
            catch(te:TypeError)
            {
               if(Log.isDebug())
               {
                  _log.debug("Multi-valued associations should be of type ListCollectionView or ArrayCollection for property: " + propName + " exception: " + te);
               }
               throw new DataServiceError(resourceManager.getString("data","badTypeForMultiValuedAssociation",[destination,getQualifiedClassName(item),propName]));
            }
            catch(re:ReferenceError)
            {
               if(Log.isDebug())
               {
                  _log.debug("Reference error checking associations for property: " + propName + " exception: " + re);
               }
               throw new DataServiceError(resourceManager.getString("data","itemMissingAssociation",[destination,getQualifiedClassName(item),propName]));
            }
         }
      }
      
      private function addNestedForwardReferences(item:Object) : String
      {
         var propName:* = null;
         var association:ManagedAssociation = null;
         var prop:Object = null;
         var i:int = 0;
         var val:Object = null;
         var uid:String = this.getManagedItemUID(item);
         if(uid != null)
         {
            return uid;
         }
         uid = this.dataStore.messageCache.addForwardReference(item);
         var md:Metadata = this.getItemMetadata(item);
         for(propName in md.associations)
         {
            association = ManagedAssociation(md.associations[propName]);
            prop = item[propName];
            if(association.typeCode == ManagedAssociation.MANY)
            {
               if(prop != null)
               {
                  for(i = 0; i < prop.length; i++)
                  {
                     val = prop[i];
                     if(val != null)
                     {
                        association.service.addNestedForwardReferences(val);
                     }
                  }
               }
            }
            else if(prop != null)
            {
               association.service.addNestedForwardReferences(prop);
            }
         }
         return uid;
      }
      
      private function setupNewDataStore() : void
      {
         this._dataStore.addDataService(this);
         this._dataStore.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.dataStorePropertyChangeHandler);
         this.checkAssociatedDataStores();
         dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"dataStore",null,this._dataStore));
      }
      
      function addNestedAssociations(item:Object, firstPass:Boolean, pendingItems:Object) : Boolean
      {
         var association:ManagedAssociation = null;
         var prop:Object = null;
         var i:int = 0;
         var propName:String = null;
         var propUID:String = null;
         var md:Metadata = this.getItemMetadata(item);
         if(md.associations.length == 0)
         {
            return false;
         }
         if(pendingItems == null)
         {
            var pendingItems:Object = new Object();
         }
         var itemId:String = this.getItemCacheId(item);
         var pendingState:int = int(pendingItems[itemId]);
         if(pendingState & PENDING_STATE_ADDING_NESTED)
         {
            return true;
         }
         pendingItems[itemId] = pendingState | PENDING_STATE_ADDING_NESTED;
         disablePaging();
         try
         {
            for(propName in md.associations)
            {
               association = ManagedAssociation(md.associations[propName]);
               if(firstPass && !association.readOnly || !firstPass && association.readOnly)
               {
                  prop = item[propName];
                  if(prop != null)
                  {
                     if(association.typeCode == ManagedAssociation.MANY)
                     {
                        for(i = 0; i < prop.length; i++)
                        {
                           if(prop[i] != null)
                           {
                              if(!firstPass)
                              {
                                 propUID = this.getItemCacheId(prop[i]);
                                 if((int(pendingItems[propUID]) & PENDING_STATE_ADDING_NESTED) != 0)
                                 {
                                    continue;
                                 }
                              }
                              association.service.addItem(prop[i],DataMessage.CREATE_OPERATION,false,true,null,pendingItems);
                              continue;
                           }
                        }
                     }
                     else
                     {
                        if(!firstPass)
                        {
                           propUID = this.getItemCacheId(prop);
                           if((int(pendingItems[propUID]) & PENDING_STATE_ADDING_NESTED) != 0)
                           {
                              continue;
                           }
                        }
                        association.service.addItem(prop,DataMessage.CREATE_OPERATION,false,true,null,pendingItems);
                     }
                  }
               }
            }
         }
         finally
         {
            enablePaging();
         }
         pendingState = pendingItems[itemId];
         pendingItems[itemId] = pendingState & ~PENDING_STATE_ADDING_NESTED;
         return false;
      }
      
      function addToChildDataListIndex(dl:DataList) : void
      {
         var dls:Array = this._itemChildDataListIndex[dl.parentItem];
         if(dls == null)
         {
            dls = this._itemChildDataListIndex[dl.parentItem] = [dl];
         }
         else
         {
            dls.push(dl);
         }
      }
      
      function removeFromChildDataListIndex(dl:DataList) : void
      {
         var dls:Array = this._itemChildDataListIndex[dl.parentItem];
         if(dls == null)
         {
            throw new DataServiceError("Can\'t find child data list to remove in index");
         }
         var ix:int = ArrayUtil.getItemIndex(dl,dls);
         if(ix == -1)
         {
            throw new DataServiceError("Can\'t find child data list to remove in index");
         }
         dls.splice(ix,1);
         if(dls.length == 0)
         {
            delete this._itemChildDataListIndex[dl.parentItem];
         }
      }
      
      function createDLResponder(dl:DataList, token:AsyncToken) : DataListRequestResponder
      {
         var result:DataListRequestResponder = new DataListRequestResponder(dl,token);
         return result;
      }
      
      function createMessage(item:Object, op:uint) : DataMessage
      {
         if(item is ObjectProxy)
         {
            item = ObjectProxy(item).object_proxy::object;
         }
         var msg:DataMessage = new DataMessage();
         msg.operation = op;
         msg.identity = this.getItemIdentifier(item);
         this.addMaxFrequencyHeaderIfNecessary(msg);
         msg.destination = this.destination;
         msg.clientId = this._consumer.clientId;
         msg.body = item;
         if(!this.autoSyncEnabled && (op == DataMessage.FILL_OPERATION || op == DataMessage.FIND_ITEM_OPERATION || op == DataMessage.FILLIDS_OPERATION || op == DataMessage.GET_OPERATION || op == DataMessage.GET_OR_CREATE_OPERATION || op == DataMessage.CREATE_AND_SEQUENCE_OPERATION))
         {
            msg.headers.sync = false;
         }
         return msg;
      }
      
      function createFillMessage(dataList:DataList, refresh:Boolean, singleResult:Boolean) : DataMessage
      {
         var result:DataMessage = new DataMessage();
         result.operation = !!singleResult?uint(DataMessage.FIND_ITEM_OPERATION):uint(DataMessage.FILL_OPERATION);
         this.addMaxFrequencyHeaderIfNecessary(result);
         result.destination = this.destination;
         result.clientId = this._consumer.clientId;
         if(this.metadata.pagingEnabled)
         {
            result.headers.pageSize = this.metadata.pageSize == 0?-1:this.metadata.pageSize;
         }
         if(refresh)
         {
            result.headers.DSrefresh = true;
         }
         result.body = dataList.fillParameters;
         if(!this.autoSyncEnabled)
         {
            result.headers.sync = false;
            if(dataList.sequenceAutoSubscribed)
            {
               this.autoUnsubscribe();
               dataList.sequenceAutoSubscribed = false;
            }
            dataList.sequenceId = this.getNewClientSequenceId();
         }
         else
         {
            this.addAssociationClientIdsToMessage(result);
         }
         return result;
      }
      
      function createSynchronizeFillMessage(sinceLastTimestamp:Date, fillParameters:Array) : DataMessage
      {
         var result:DataMessage = new DataMessage();
         result.operation = DataMessage.SYNCHRONIZE_FILL_OPERATION;
         result.destination = this.destination;
         result.clientId = this._consumer.clientId;
         var syncRequest:SyncFillRequest = new SyncFillRequest();
         syncRequest.sinceTimestamp = sinceLastTimestamp;
         syncRequest.fillParameters = fillParameters;
         result.body = syncRequest;
         return result;
      }
      
      function copyCurrentItemState(obj:Object) : Object
      {
         var result:Object = null;
         try
         {
            disablePaging();
            result = ObjectUtil.copy(obj);
         }
         finally
         {
            enablePaging();
         }
         return result;
      }
      
      function copyItem(obj:Object) : Object
      {
         var buffer:ByteArray = null;
         var result:Object = null;
         try
         {
            disablePaging();
            if(obj is ObjectProxy)
            {
               var obj:Object = ObjectProxy(obj).object_proxy::object;
            }
            buffer = new ByteArray();
            buffer.writeObject(DataMessage.wrapItem(obj,this.destination));
            buffer.position = 0;
            result = buffer.readObject();
            result = DataMessage.unwrapItem(result);
            if(result is IManaged)
            {
               IManaged(result).uid = IManaged(obj).uid;
            }
         }
         finally
         {
            enablePaging();
         }
         return result;
      }
      
      function disableLogging() : void
      {
         this.dataStore.disableLogging();
      }
      
      function dispatchConflictEvent(event:DataConflictEvent, errorHandled:Boolean) : void
      {
         if(hasEventListener(DataConflictEvent.CONFLICT))
         {
            dispatchEvent(event);
         }
         else if(!errorHandled)
         {
            throw event.conflict;
         }
      }
      
      function dispatchFaultEvent(event:Event, token:AsyncToken, id:Object = null, cacheResponse:Boolean = false, handled:Boolean = false, ignoreAdapterThrowUnhandledFaults:Boolean = false) : void
      {
         var fault:Fault = null;
         var message:ErrorMessage = null;
         var mef:MessageFaultEvent = null;
         if(Log.isDebug())
         {
            this._log.debug("Dispatching fault event for destination: " + this.destination);
         }
         if(event is FaultEvent)
         {
            fault = FaultEvent(event).fault;
            message = null;
         }
         else if(event is MessageFaultEvent)
         {
            mef = event as MessageFaultEvent;
            fault = new Fault(mef.faultCode,mef.faultString,mef.faultDetail);
            fault.rootCause = mef.rootCause;
            message = mef.message;
         }
         var item:Object = id == null?null:this.getItem(this.metadata.getUID(id));
         var fltEvent:DataServiceFaultEvent = DataServiceFaultEvent.createEvent(fault,token,message,item,id,cacheResponse);
         this.dispatchDataServiceFaultEvent(fltEvent,token,handled,ignoreAdapterThrowUnhandledFaults);
      }
      
      function dispatchDataServiceFaultEvent(fltEvent:DataServiceFaultEvent, token:AsyncToken, handled:Boolean, ignoreAdapterThrowUnhandledFaults:Boolean = false) : void
      {
         if(token.hasResponder())
         {
            fltEvent.callTokenResponders();
            handled = true;
         }
         if(hasEventListener(FaultEvent.FAULT))
         {
            dispatchEvent(fltEvent);
            handled = true;
         }
         if(this.dataStore.hasEventListener(FaultEvent.FAULT))
         {
            handled = true;
         }
         if(Log.isDebug())
         {
            this._log.debug((!!handled?"Finished calling fault handlers":"No registered fault handler or token responder - throwing an error") + " for destination: " + this.destination);
         }
         if(!handled && (ignoreAdapterThrowUnhandledFaults || this.adapter == null || this.adapter.throwUnhandledFaults))
         {
            throw fltEvent.fault;
         }
         if(Log.isDebug())
         {
            this._log.debug("The adapter says not to throw unhandled faults, so NOT throwing unhandled fault: " + fltEvent.fault);
         }
      }
      
      function dispatchResultEvent(event:MessageEvent, token:AsyncToken, result:Object, cacheResponse:Boolean = false, sendResultEvent:Boolean = true) : void
      {
         if(Log.isDebug())
         {
            this._log.debug("About to dispatch result event for destination: " + this.destination);
         }
         var resultEvent:DataServiceResultEvent = DataServiceResultEvent.createEvent(result,token,event.message,cacheResponse);
         resultEvent.callTokenResponders();
         if(sendResultEvent && hasEventListener(DataServiceResultEvent.RESULT))
         {
            dispatchEvent(resultEvent);
         }
         if(Log.isDebug())
         {
            this._log.debug("Finished dispatching result event");
         }
      }
      
      function enableLogging() : void
      {
         this.dataStore.enableLogging();
      }
      
      function getItem(uid:String) : IManaged
      {
         return IManaged(this._itemCache[uid]);
      }
      
      function getItemForReferenceFromIdentity(identity:Object, addRef:Boolean) : IManaged
      {
         var uid:String = this.getUIDFromIdentity(identity);
         return this.getItemForReference(uid,addRef);
      }
      
      function getItemForReference(uid:String, addRef:Boolean = true) : IManaged
      {
         var releasedItem:* = undefined;
         var item:IManaged = IManaged(this._itemCache[uid]);
         if(item == null)
         {
            if(this._releasedUIDs != null && this._releasedUIDs[uid] != null)
            {
               for(releasedItem in this._releasedItems)
               {
                  if(IManaged(releasedItem).uid == uid)
                  {
                     item = releasedItem;
                     if(addRef)
                     {
                        this.reAddItem(uid,item);
                     }
                     break;
                  }
               }
               if(item == null)
               {
                  this.refreshReleasedUIDs();
               }
            }
         }
         return item;
      }
      
      function getPendingItem(uid:String, addRef:Boolean = true, includeSent:Boolean = false) : IManaged
      {
         var item:IManaged = this.getItemForReference(uid,addRef);
         if(item != null)
         {
            return item;
         }
         var messageCache:DataMessageCache = this.dataStore.messageCache;
         var mci:MessageCacheItem = !!includeSent?messageCache.getLastCacheItem(this,uid):messageCache.currentBatch.getLastCacheItem(this,uid,null);
         if(mci != null)
         {
            return IManaged(mci.item);
         }
         return null;
      }
      
      private function refreshReleasedUIDs() : void
      {
         var releasedItem:* = undefined;
         this._releasedUIDs = new Object();
         for(releasedItem in this._releasedItems)
         {
            this._releasedUIDs[IManaged(releasedItem).uid] = true;
         }
      }
      
      function getCreatedOrCachedItem(uid:String) : IManaged
      {
         var result:IManaged = this.getItemForReference(uid);
         if(result != null)
         {
            return result;
         }
         var res:Object = this.dataStore.messageCache.getCreatedItem(this,uid);
         if(res != null)
         {
            return this.normalize(res);
         }
         return null;
      }
      
      function getItemCache() : Object
      {
         return this._itemCache;
      }
      
      function getItemIdentifier(item:Object) : Object
      {
         var newIdentity:Object = this.dataStore.messageCache.getCreateMessageIdentity(this,item);
         if(newIdentity != null)
         {
            return newIdentity;
         }
         return this.getIdentityMap(item);
      }
      
      function getItemCacheId(item:Object) : String
      {
         var newIdentity:Object = this.dataStore.messageCache.getCreateMessageIdentity(this,item);
         if(newIdentity != null)
         {
            if(newIdentity is String)
            {
               return newIdentity as String;
            }
            item = newIdentity;
         }
         return this.metadata.getUID(item);
      }
      
      function getOriginalItemByIdentity(identity:Object) : Object
      {
         var result:Object = null;
         var uid:String = this.metadata.getUID(identity);
         var m:DataMessage = this.dataStore.messageCache.getOldestMessage(this,uid);
         var resultReferencedIds:Object = null;
         if(m == null)
         {
            result = null;
         }
         else if(m.operation == DataMessage.UPDATE_OPERATION)
         {
            result = DataMessage.unwrapItem(m.body[DataMessage.UPDATE_BODY_PREV]);
            resultReferencedIds = DataMessage.unwrapItem(m.headers.prevReferencedIds);
         }
         else if(m.operation == DataMessage.DELETE_OPERATION)
         {
            result = m.unwrapBody();
            resultReferencedIds = DataMessage.unwrapItem(m.headers.referencedIds);
         }
         else
         {
            result = null;
         }
         if(result != null)
         {
            result = this.normalize(this.copyItem(result));
            IManaged(result).uid = uid;
            this.getItemMetadata(result).configureItem(this,result,result,this.getOperationPropertySpecifier(m),null,resultReferencedIds,false,false,null,true,true,false,true);
         }
         return result;
      }
      
      function getDataListForAssociation(parentItem:Object, association:ManagedAssociation) : DataList
      {
         var i:uint = 0;
         var dataList:DataList = null;
         var dls:Array = this._itemChildDataListIndex[parentItem] as Array;
         if(dls != null)
         {
            for(i = 0; i < dls.length; i++)
            {
               dataList = DataList(dls[i]);
               if(dataList.association == association)
               {
                  return dataList;
               }
            }
         }
         return null;
      }
      
      function getDataListWithCollectionId(collectionId:Object) : DataList
      {
         var i:uint = 0;
         var dataList:DataList = null;
         var prop:String = null;
         var parentDestName:String = null;
         var parentDS:ConcreteDataService = null;
         var parentItem:Object = null;
         var assoc:ManagedAssociation = null;
         if(collectionId is Array)
         {
            for(i = 0; i < this._dataLists.length; i++)
            {
               dataList = DataList(this._dataLists.getItemAt(i));
               if(dataList.association == null && Managed.compare(dataList.collectionId,collectionId,-1,["uid"]) == 0)
               {
                  return dataList;
               }
            }
            return null;
         }
         prop = collectionId.prop;
         if(prop == null)
         {
            throw new DataServiceError("getDataListWithCollectionId called with invalid collection id!");
         }
         parentDestName = collectionId.parent;
         parentDS = this.dataStore.getDataService(parentDestName);
         if(collectionId.id is String)
         {
            parentItem = parentDS.dataStore.messageCache.getCreatedItem(parentDS,collectionId.id);
         }
         else
         {
            parentItem = parentDS.getLocalItem(collectionId.id);
         }
         if(parentItem == null)
         {
            if(Log.isDebug())
            {
               this._log.debug("Can\'t find parent item for update collection: " + itemToString(collectionId));
            }
            return null;
         }
         assoc = parentDS.metadata.associations[prop];
         if(assoc == null)
         {
            throw new DataServiceError("getDataListWithCollectionId called with invalid association");
         }
         return parentDS.getDataListForAssociation(parentItem,assoc);
      }
      
      function getDataListWithFillParams(fillParams:Object) : DataList
      {
         var dataList:DataList = null;
         for(var i:uint = 0; i < this._dataLists.length; i++)
         {
            dataList = DataList(this._dataLists.getItemAt(i));
            if(dataList.fillParameters != null && Managed.compare(dataList.fillParameters,fillParams,-1,["uid"]) == 0)
            {
               return dataList;
            }
         }
         return null;
      }
      
      function getNewClientSequenceId() : int
      {
         var seqId:int = this._clientSequenceIdCounter;
         this._clientSequenceIdCounter--;
         return seqId;
      }
      
      function getMessagePropertySpecifier(dmsg:DataMessage) : PropertySpecifier
      {
         return this.parsePropertySpecifierString(dmsg.headers.DSincludeSpec);
      }
      
      function parsePropertySpecifierString(includeModeStr:String) : PropertySpecifier
      {
         var props:Array = null;
         if(includeModeStr == null)
         {
            return this.includeDefaultSpecifier;
         }
         if(includeModeStr == "")
         {
            return PropertySpecifier.EMPTY;
         }
         var firstChar:String = includeModeStr.charAt(0);
         if(firstChar == "*")
         {
            return this.includeAllSpecifier;
         }
         if(firstChar == "+")
         {
            props = splitAndTrim(includeModeStr,",");
            props[0] = props[0].substring(1);
            return PropertySpecifier.getPropertySpecifier(this,props,true);
         }
         props = splitAndTrim(includeModeStr,",");
         return PropertySpecifier.getPropertySpecifier(this,props,false);
      }
      
      function getOperationPropertySpecifier(dmsg:DataMessage) : PropertySpecifier
      {
         var ps:PropertySpecifier = null;
         var changes:Array = null;
         if(dmsg.isCreate())
         {
            return this.getMessagePropertySpecifier(dmsg);
         }
         if(dmsg.operation == DataMessage.UPDATE_OPERATION)
         {
            ps = this.getMessagePropertySpecifier(dmsg);
            if(ps == this.includeDefaultSpecifier)
            {
               changes = dmsg.body[DataMessage.UPDATE_BODY_CHANGES] as Array;
               if(changes == null)
               {
                  return this.includeAllSpecifier;
               }
               return PropertySpecifier.getPropertySpecifier(this,changes);
            }
            return ps;
         }
         return this.includeDefaultSpecifier;
      }
      
      function getReleaseMessage(dataList:DataList, startIndex:int = -1, num:int = 0) : DataMessage
      {
         var result:DataMessage = null;
         var item:Object = null;
         if(dataList.sequenceId >= 0 && (startIndex != -1 || dataList.referenceCount == 0))
         {
            result = new DataMessage();
            result.destination = this.destination;
            result.clientId = this._consumer.clientId;
            if(dataList.smo)
            {
               if(dataList.references.length != 1)
               {
                  return null;
               }
               result.operation = DataMessage.RELEASE_ITEM_OPERATION;
               item = this.getItem(dataList.references[0]);
               if(item == null)
               {
                  return null;
               }
               result.body = this.getIdentityMap(item);
            }
            else if(dataList.fillParameters != null || dataList.association != null && dataList.association.paged && dataList.fetched)
            {
               result.operation = DataMessage.RELEASE_COLLECTION_OPERATION;
               result.body = dataList.collectionId;
            }
            else
            {
               return null;
            }
            result.headers.sequenceId = dataList.sequenceId;
            if(startIndex != -1)
            {
               result.headers.DSrange = startIndex + ":" + num;
            }
            return result;
         }
         return null;
      }
      
      function itemToIdString(val:Object) : String
      {
         var list:IList = null;
         var elem:Object = null;
         var str:String = null;
         var j:int = 0;
         var idForIndex:Object = null;
         var arr:Array = null;
         var i:int = 0;
         var pce:PropertyChangeEvent = null;
         if(val is ListCollectionView)
         {
            list = ListCollectionView(val).list;
            str = "[";
            try
            {
               if(list != null)
               {
                  for(j = 0; j < list.length; j++)
                  {
                     elem = list.getItemAt(j);
                     if(elem == null)
                     {
                        if(list is DataList && (idForIndex = (list as DataList).getIdentityForIndex(j) != null))
                        {
                           str = str + Managed.toString(idForIndex);
                        }
                        else
                        {
                           str = str + "null";
                        }
                     }
                     else
                     {
                        str = str + this.itemToIdString(elem);
                     }
                     if(j != list.length - 1)
                     {
                        str = str + ",";
                     }
                  }
                  str = str + "]";
                  return str;
               }
            }
            catch(ipe:ItemPendingError)
            {
               str = str + "pending....";
            }
            return str;
         }
         if(val is Array)
         {
            arr = val as Array;
            str = "[";
            for(i = 0; i < arr.length; i++)
            {
               if(i != 0)
               {
                  str = str + ", ";
               }
               str = str + this.itemToIdString(arr[i]);
            }
            str = str + "]";
            return str;
         }
         if(val is PropertyChangeEvent)
         {
            pce = val as PropertyChangeEvent;
            return "[" + pce.property + " " + this.itemToIdString(val.oldValue) + " to " + this.itemToIdString(val.newValue) + "]";
         }
         if(val is IManaged)
         {
            return IManaged(val).uid;
         }
         return Managed.toString(val);
      }
      
      function getStatusInfo(dumpCache:Boolean) : String
      {
         var uid:* = null;
         var i:int = 0;
         var item:* = undefined;
         var info:String = this.destination + "\n    num items in cache: " + this.numItems + "\n    num managed lists (associations, items, fills): " + this._dataLists.length;
         if(dumpCache)
         {
            info = info + "\n    cached items [\n";
            for(uid in this._itemCache)
            {
               info = info + ("      [" + uid + "]: " + itemToString(this._itemCache[uid],this.destination,6) + "\n");
            }
            info = info + "    ]\n";
            info = info + "\n    weak reference items [\n";
            i = 0;
            for(item in this._releasedItems)
            {
               info = info + ("      [" + i + "]: " + itemToString(item,this.destination,6) + "\n");
               i++;
            }
            info = info + "    ]\n";
            info = info + "\n    weak reference uids [\n";
            i = 0;
            for(uid in this._releasedUIDs)
            {
               info = info + ("      [" + i + "]: " + uid + "\n");
               i++;
            }
            info = info + "    ]\n";
         }
         else
         {
            i = 0;
            for(item in this._releasedItems)
            {
               i++;
            }
            info = info + ("\n    num weak reference items: " + i);
            i = 0;
            for(uid in this._releasedUIDs)
            {
               i++;
            }
            info = info + ("\n    num weak reference uids:  " + i);
         }
         return info;
      }
      
      function getManagedItems(items:Array) : Array
      {
         var mItems:Array = new Array(items.length);
         for(var i:int = 0; i < mItems.length; i++)
         {
            if(items[i] == null)
            {
               mItems[i] = null;
            }
            else
            {
               mItems[i] = this.getLocalItem(items[i]);
            }
         }
         return mItems;
      }
      
      function hasPendingUpdateCollections(collectionId:Object) : Boolean
      {
         return this.dataStore.messageCache.hasCommittedUpdateCollections(this.destination,collectionId) || this.dataStore.hasUnmergedUpdateCollectionMessages(this.destination,collectionId);
      }
      
      function isTransient(item:Object, propName:String) : Boolean
      {
         if(item is ObjectProxy)
         {
            return false;
         }
         return ObjectUtil.hasMetadata(item,propName,"Transient");
      }
      
      function logStatus(operationName:String) : void
      {
         if(Log.isDebug())
         {
            this._log.debug(operationName + ":" + this.getStatusInfo(false));
         }
      }
      
      function mergeMessage(msg:DataMessage) : void
      {
         var ucmsg:UpdateCollectionMessage = null;
         var dataList:DataList = null;
         this.disableLogging();
         this.enableDelayedReleases();
         try
         {
            this.dataStore.processingServerChanges = true;
            if(msg.operation == DataMessage.CREATE_OPERATION)
            {
               this.mergeCreate(msg);
            }
            else if(msg.operation == DataMessage.DELETE_OPERATION)
            {
               this.mergeDelete(msg);
            }
            else if(msg.operation == DataMessage.UPDATE_OPERATION)
            {
               this.mergeUpdate(msg);
            }
            else if(msg.operation == DataMessage.UPDATE_COLLECTION_OPERATION)
            {
               ucmsg = UpdateCollectionMessage(msg);
               this.processUpdateCollection(ucmsg.collectionId,ucmsg,null,null);
               dataList = this.getDataListWithCollectionId(ucmsg.collectionId);
               if(dataList != null)
               {
                  dataList.releaseItemsFromUpdateCollection(ucmsg,false);
               }
            }
            if(this.autoSaveCache)
            {
               this.dataStore.saveCache(null,true);
            }
         }
         finally
         {
            this.dataStore.processingServerChanges = false;
            this.disableDelayedReleases();
            this.enableLogging();
         }
      }
      
      function processPendingRequests() : void
      {
         for(var i:int = 0; i < this._dataLists.length; i++)
         {
            DataList(this._dataLists.getItemAt(i)).processPendingRequests();
         }
      }
      
      function restoreItemCache(items:Object) : Array
      {
         var deletedItems:Array = null;
         var persistingAtLeaf:Boolean = this.offlineAdapter.isQuerySupported();
         var ds:ConcreteDataService = !!persistingAtLeaf?this:this.rootDataService;
         var oldOfflineDirtyList:Dictionary = ds.offlineDirtyList;
         var oldRequiresSave:Boolean = ds.requiresSave;
         try
         {
            ds.offlineDirtyList = null;
            ds.requiresSave = false;
            deletedItems = ds.restoreItemCacheInternal(items);
            if(oldOfflineDirtyList == null)
            {
               oldOfflineDirtyList = new Dictionary();
               oldRequiresSave = false;
            }
         }
         finally
         {
            ds.offlineDirtyList = oldOfflineDirtyList;
            ds.requiresSave = oldRequiresSave;
         }
         return deletedItems;
      }
      
      private function restoreItemCacheInternal(items:Object) : Array
      {
         var itemAdapter:Object = null;
         var item:Object = null;
         var messages:Array = null;
         var msg:DataMessage = null;
         var extra:Array = null;
         var uc:Boolean = false;
         var ps:PropertySpecifier = null;
         var i:* = null;
         var j:uint = 0;
         var itemDest:ConcreteDataService = null;
         var allPending:Array = null;
         var k:int = 0;
         var deletedItems:Array = null;
         for(i in items)
         {
            uc = true;
            itemAdapter = items[i];
            item = DataMessage.unwrapItem(itemAdapter.item);
            item = this.normalize(item);
            Managed.setDestination(item,itemAdapter.destination);
            extra = itemAdapter.extra;
            if(extra == null)
            {
               ps = this.includeDefaultSpecifier;
            }
            else
            {
               ps = PropertySpecifier.getPropertySpecifier(this,extra,true);
            }
            this.getItemMetadata(item).configureItem(this,item,item,ps,null,itemAdapter.referencedIds,false,false,null,false,false,false,true);
            item.uid = itemAdapter.uid;
            messages = this.getPendingMessages(item.uid);
            for(j = 0; j < messages.length; j++)
            {
               msg = DataMessage(messages[j]);
               uc = uc && msg.operation != DataMessage.DELETE_OPERATION;
               itemDest = this.getItemDestination(item);
               allPending = this.dataStore.messageCache.pending;
               for(k = 0; k < allPending.length; k++)
               {
                  allPending[k].registerItemWithMessageCache(itemDest,item,msg);
               }
            }
            if(uc)
            {
               this.internalUpdateCache(itemAdapter.uid,null,item);
            }
            else
            {
               if(deletedItems == null)
               {
                  deletedItems = new Array();
               }
               deletedItems.push(item);
            }
         }
         if(Log.isDebug() && items.length > 0)
         {
            this._log.debug("Restored items: " + itemToString(items));
         }
         if(deletedItems != null)
         {
            this._log.debug("Skipping restore of cached items that are deleted locally on the client: " + itemToString(deletedItems));
         }
         return deletedItems;
      }
      
      function getFetchedProperties(item:Object) : Array
      {
         var dataList:DataList = null;
         var i:int = 0;
         var propName:String = null;
         var assoc:ManagedAssociation = null;
         var cds:ConcreteDataService = this.getItemDestination(item);
         var lods:Array = cds.metadata.loadOnDemandProperties;
         var fetched:Array = null;
         if(lods != null)
         {
            for(i = 0; i < lods.length; i++)
            {
               propName = lods[i];
               assoc = cds.metadata.associations[propName];
               if(assoc != null)
               {
                  dataList = cds.getDataListForAssociation(item,assoc);
                  if(dataList != null && dataList.fetched && !dataList.association.pagedUpdates)
                  {
                     if(fetched == null)
                     {
                        fetched = new Array();
                     }
                     fetched.push(propName);
                  }
               }
            }
         }
         return fetched;
      }
      
      function normalize(item:Object) : IManaged
      {
         item = Managed.normalize(item);
         if(!(item is IManaged))
         {
            throw new ArgumentError(resourceManager.getString("data","itemNotIManaged",[itemToString(item,this.destination)]));
         }
         return IManaged(item);
      }
      
      function processCommitMessage(message:DataMessage, orgMsg:DataMessage, messages:Array, pendingServerChanges:Object) : void
      {
         var oldId:String = null;
         var newId:String = null;
         var uid:String = null;
         var serverChanges:Array = null;
         var ps:PropertySpecifier = null;
         var itemM:IManaged = null;
         var proxyInfo:Object = null;
         var overridden:Boolean = false;
         var newItem:Object = null;
         var newIdentity:Object = null;
         var leafDS:ConcreteDataService = null;
         var itemObj:Object = null;
         var pendingMessages:Array = null;
         var ent:Object = null;
         var i:int = 0;
         var item:Object = null;
         if(message.isCreate())
         {
            oldId = orgMsg.messageId;
            itemM = IManaged(this._itemCache[oldId]);
            if(itemM == null)
            {
               oldId = this.metadata.getUID(orgMsg.unwrapBody());
               itemM = IManaged(this.getItem(oldId));
               if(itemM == null)
               {
                  if(Log.isError())
                  {
                     this._log.error("{0} Could not locate item in cache for create/update operation on item {1}",this._consumer.id,oldId);
                  }
                  return;
               }
            }
            this.disableLogging();
            disablePaging();
            try
            {
               newItem = message.unwrapBody();
               newId = this.metadata.getUID(newItem);
               if(orgMsg.headers.DSoverridden == null)
               {
                  overridden = false;
                  ps = this.getMessagePropertySpecifier(message);
               }
               else
               {
                  overridden = true;
                  pendingServerChanges[newId] = [{
                     "message":message,
                     "orgMsg":orgMsg
                  }];
                  ps = PropertySpecifier.getPropertySpecifier(this,this.metadata.identities,false);
               }
               serverChanges = this.getChangedProperties(newItem,orgMsg.unwrapBody(),ps,null,message.headers.referencedIds,orgMsg.headers.referencedIds);
               newIdentity = this.getIdentityMap(newItem);
               if(newId == null || newId == "")
               {
                  if(Log.isError())
                  {
                     this._log.error("The server returned an item without an identity.  Either the server did not set the id properties, the id properties are misconfigured or id properties toString method returned nothing.  id properties: \'{0}\',  returned item: \'{1}\'",itemToString(this.metadata.identities),itemToString(newItem,this.destination));
                  }
               }
               leafDS = this.getItemDestination(itemM);
               if(oldId != newId)
               {
                  leafDS.replaceDataListReferencesTo(oldId,newId,itemM,newIdentity);
               }
               if(serverChanges != null)
               {
                  this.updateCache(oldId,newId,itemM,message.unwrapBody(),serverChanges,null,message.headers.referencedIds,false,false);
               }
               if(oldId != newId)
               {
                  leafDS.removeItemFromCache(oldId,true);
                  itemM.uid = newId;
                  leafDS.putItemInCache(newId,itemM);
                  if(Log.isDebug())
                  {
                     this._log.debug("Changing id of item in cache from: " + oldId + " to: " + newId + " destination: " + this.destination);
                  }
               }
            }
            finally
            {
               this.enableLogging();
               enablePaging();
            }
            proxyInfo = message.headers.sequenceProxy;
            if(proxyInfo != null && message.operation == DataMessage.CREATE_OPERATION)
            {
               this.getItemMetadata(itemM).configureItem(this,itemM,itemM,this.includeAllSpecifier,proxyInfo,message.headers.referencedIds,true,false,null,false,false,overridden);
            }
         }
         else if(message.operation == DataMessage.UPDATE_OPERATION)
         {
            itemObj = DataMessage.unwrapItem(message.body[DataMessage.UPDATE_BODY_NEW]);
            uid = this.metadata.getUID(itemObj);
            this.disableLogging();
            try
            {
               pendingMessages = pendingServerChanges[uid];
               ent = {
                  "message":message,
                  "orgMsg":orgMsg
               };
               if(pendingMessages == null)
               {
                  pendingMessages = [ent];
                  if(orgMsg.headers.DSoverridden != null)
                  {
                     pendingServerChanges[uid] = pendingMessages;
                  }
               }
               else
               {
                  pendingMessages.push(ent);
               }
               if(orgMsg.headers.DSoverridden == null)
               {
                  for(i = pendingMessages.length - 1; i >= 0; i--)
                  {
                     ent = pendingMessages[i];
                     serverChanges = this.applyServerChanges(uid,ent.message,ent.orgMsg,serverChanges);
                  }
               }
            }
            finally
            {
               this.enableLogging();
            }
         }
         else if(message.operation == DataMessage.DELETE_OPERATION)
         {
            uid = this.metadata.getUID(message.identity);
            item = this._itemCache[uid];
            leafDS = this.getItemDestination(item);
            leafDS.clearResultForSMO(uid);
         }
      }
      
      private function applyServerChanges(uid:String, message:DataMessage, orgMsg:DataMessage, alreadyChanged:Array) : Array
      {
         var newItem:Object = null;
         var orgItem:Object = null;
         var changes:Array = null;
         var newReferencedIds:Object = null;
         var orgReferencedIds:Object = null;
         var ps:PropertySpecifier = null;
         var i:int = 0;
         if(message.operation == DataMessage.UPDATE_OPERATION)
         {
            newItem = message.body[DataMessage.UPDATE_BODY_NEW];
            orgItem = orgMsg.body[DataMessage.UPDATE_BODY_NEW];
            changes = message.body[DataMessage.UPDATE_BODY_CHANGES];
            newReferencedIds = DataMessage.unwrapItem(message.headers.newReferencedIds);
            orgReferencedIds = DataMessage.unwrapItem(orgMsg.headers.newReferencedIds);
            ps = PropertySpecifier.getPropertySpecifier(this,changes,false);
         }
         else
         {
            newItem = message.body;
            orgItem = orgMsg.body;
            changes = null;
            newReferencedIds = DataMessage.unwrapItem(message.headers.referencedIds);
            orgReferencedIds = DataMessage.unwrapItem(orgMsg.headers.referencedIds);
            ps = this.includeDefaultSpecifier;
         }
         newItem = DataMessage.unwrapItem(newItem);
         orgItem = DataMessage.unwrapItem(orgItem);
         var serverChanges:Array = null;
         if(newItem != null)
         {
            serverChanges = this.getChangedProperties(newItem,orgItem,ps,null,newReferencedIds,orgReferencedIds);
            if(serverChanges != null)
            {
               this.updateCacheWithId(uid,newItem,serverChanges,alreadyChanged,newReferencedIds,true,false);
               if(alreadyChanged != null)
               {
                  for(i = 0; i < alreadyChanged.length; i++)
                  {
                     if(serverChanges.indexOf(alreadyChanged[i]) == -1)
                     {
                        serverChanges.push(alreadyChanged[i]);
                     }
                  }
               }
            }
         }
         return serverChanges == null?alreadyChanged:serverChanges;
      }
      
      function clearResultForSMO(uid:String) : void
      {
         var i:int = 0;
         var dls:Array = this.getDataListsForUID(uid);
         if(dls != null)
         {
            dls = this.shallowCopyArray(dls);
            for(i = 0; i < dls.length; i++)
            {
               if(dls[i].smo)
               {
                  this.removeDataList(dls[i]);
                  if(dls[i].itemReference != null)
                  {
                     dls[i].itemReference.setResult(null);
                  }
               }
            }
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).clearResultForSMO(uid);
            }
         }
      }
      
      function getUIDFromReferencedId(refId:Object) : String
      {
         if(refId is String)
         {
            return refId as String;
         }
         return this.getItemCacheId(refId);
      }
      
      function getUIDFromIdentity(refId:Object) : String
      {
         if(refId is String)
         {
            return refId as String;
         }
         return this.metadata.getUID(refId);
      }
      
      function hasManagedData() : Boolean
      {
         return this._dataLists.length > 0;
      }
      
      function processUpdateCollection(collectionId:Object, newucmsg:UpdateCollectionMessage, origucmsg:UpdateCollectionMessage, serverOverride:UpdateCollectionMessage) : void
      {
         if(origucmsg != null && newucmsg != null && newucmsg.updateMode == origucmsg.updateMode && newucmsg.isSameUpdate(origucmsg))
         {
            return;
         }
         var dataList:DataList = this.getDataListWithCollectionId(collectionId);
         if(dataList != null)
         {
            dataList.processUpdateCollection(newucmsg,origucmsg,serverOverride);
         }
         else if(Log.isDebug())
         {
            this._log.debug("Unable to find managed fill with parameters: " + itemToString(collectionId) + " for updateCollection message: " + itemToString(newucmsg));
         }
      }
      
      function processPageRequest(request:PageRequest, dataList:DataList, fetch:Boolean = false) : AsyncToken
      {
         var msg:DataMessage = request.createDataMessage();
         request.messageSent = true;
         if(dataList.dynamicSizing)
         {
            msg.headers.dynamicSizing = dataList.dynamicSizing;
         }
         if(!request.sync)
         {
            msg.headers.sync = false;
         }
         if(dataList.sequenceId < 0 || dataList.sequenceIdStale)
         {
            msg.body = dataList.collectionId;
            if(request.sync)
            {
               this.addAssociationClientIdsToMessage(msg);
            }
         }
         else
         {
            msg.headers.sequenceId = dataList.sequenceId;
         }
         if(Log.isDebug())
         {
            if(request.idList == null)
            {
               this._log.debug("Requesting page for {0}.{1}({2}) from index: {3} to: {4}",this.destination,dataList.itemReference == null?"fill":"getItem",Managed.toString(dataList.collectionId,null,null,2),request.lowerBound,request.upperBound);
            }
            else
            {
               this._log.debug("Requesting items with ids: {3} for {0}.{1}({2}, properties: {4})",this.destination,dataList.association != null?"association":dataList.itemReference == null?"fill":"getItem",Managed.toString(dataList.collectionId,null,null,2),Managed.toString(request.idList,null,null,2),Managed.toString(request.propList,null,null,2));
            }
         }
         msg.destination = this.destination;
         msg.clientId = this._consumer.clientId;
         var token:AsyncToken = new AsyncToken(msg);
         token.request = request;
         if(fetch)
         {
            msg.headers.DSfetch = true;
         }
         this.dataStore.processPageRequest(dataList,this,msg,this.createDLResponder(dataList,token),token);
         return token;
      }
      
      function reconnect(token:AsyncToken = null) : void
      {
         var event:DataServiceResultEvent = null;
         var names:Array = null;
         var associations:Object = null;
         var n:int = 0;
         var i:int = 0;
         var association:ManagedAssociation = null;
         if(this.connected && token)
         {
            event = DataServiceResultEvent.createEvent(this.connected,token,null);
            new AsyncDispatcher(this.dispatchResultEvent,[event,token,this.connected],1);
         }
         if(!this.connected && !this._connecting && this.autoConnect)
         {
            this._disconnectBarrier = false;
            this._connecting = true;
            this._shouldBeConnected = true;
            this.dataStore.internalConnect(this,token);
            names = this.metadata.associationNames;
            if(names != null && names.length > 0)
            {
               associations = this.metadata.associations;
               n = names.length;
               for(i = 0; i < n; i++)
               {
                  association = ManagedAssociation(associations[names[i]]);
                  if(association.validate())
                  {
                     association.service.reconnect();
                  }
               }
            }
            if(this._subTypes != null)
            {
               for(i = 0; i < this._subTypes.length; i++)
               {
                  ConcreteDataService(this._subTypes[i]).reconnect();
               }
            }
         }
         else if(this.connected)
         {
            this.reconnectSequences();
         }
      }
      
      function releaseAssociations(item:Object, replaceData:Boolean, clear:Boolean, clonedObjs:Dictionary, referencedCache:Object = null, trackItems:Boolean = false, clearAssociatedMessages:Boolean = false) : void
      {
         var assoc:ManagedAssociation = null;
         var prop:* = null;
         var subList:DataList = null;
         var subItems:Array = null;
         for(prop in this.metadata.associations)
         {
            assoc = ManagedAssociation(this.metadata.associations[prop]);
            subList = this.getDataListForAssociation(item,assoc);
            if(subList != null)
            {
               subItems = assoc.service.releaseDataList(subList,replaceData,clear,clonedObjs,referencedCache,trackItems,clearAssociatedMessages);
               if(assoc.typeCode == ManagedAssociation.MANY)
               {
                  if(replaceData)
                  {
                     ListCollectionView(item[prop]).list = new ArrayList(!!clear?[]:subItems);
                  }
               }
               else if(assoc.typeCode == ManagedAssociation.ONE)
               {
                  if(replaceData)
                  {
                     if(subItems.length == 1)
                     {
                        item[prop] = subItems[0];
                     }
                     else
                     {
                        item[prop] = null;
                     }
                  }
               }
            }
         }
      }
      
      function releaseDataList(dataList:DataList, replaceData:Boolean, clear:Boolean, clonedObjs:Dictionary, referencedCache:Object = null, trackItems:Boolean = false, clearAssociatedMessages:Boolean = false) : Array
      {
         var items:Array = null;
         var item:IManaged = null;
         var releaseMessage:DataMessage = null;
         var i:int = 0;
         var leafDS:ConcreteDataService = null;
         var clonedItem:Object = null;
         var noOp:Function = null;
         var refs:int = dataList.referenceCount;
         if(refs == 0)
         {
            return dataList.localItems;
         }
         if(dataList.cacheStale && refs == 1 && (this.dataStore.autoSaveCache || dataList.inCache))
         {
            this.dataStore.saveDataList(dataList);
         }
         this.removeDataList(dataList);
         if(refs == dataList.referenceCount)
         {
            throw new DataServiceError(resourceManager.getString("data","invalidReleaseCollection",[this.destination]));
         }
         try
         {
            disablePaging();
            items = dataList.localItems;
            if(referencedCache == null)
            {
               var referencedCache:Object = new Object();
            }
            if(clearAssociatedMessages)
            {
               this.releaseUncommittedDeletes(dataList);
               this.releaseUncommittedCreates(dataList);
            }
            releaseMessage = this.getReleaseMessage(dataList);
            for(i = 0; i < items.length; i++)
            {
               item = IManaged(items[i]);
               leafDS = this.getItemDestination(item);
               if(!leafDS.isItemReferenced(item,new Dictionary(),referencedCache,!clearAssociatedMessages))
               {
                  if(leafDS.getItem(item.uid) != null)
                  {
                     leafDS.internalReleaseItem(item,clearAssociatedMessages,false,trackItems);
                     leafDS.releaseAssociations(item,replaceData,clear,clonedObjs,referencedCache,trackItems,clearAssociatedMessages);
                  }
                  else if(Log.isDebug())
                  {
                     this._log.debug("skipping release item for item removed from cache during its child release: " + item.uid);
                  }
               }
               else if(!clear && replaceData)
               {
                  clonedItem = clonedObjs[item];
                  if(clonedItem == null)
                  {
                     clonedItem = this.normalize(this.copyCurrentItemState(item));
                     clonedObjs[item] = clonedItem;
                  }
                  items[i] = clonedItem;
               }
            }
            if(dataList.referenceCount == 0 && dataList.sequenceAutoSubscribed)
            {
               this.autoUnsubscribe();
               dataList.sequenceAutoSubscribed = false;
            }
            if(releaseMessage != null)
            {
               noOp = function(x:Object, y:AsyncToken):void
               {
               };
               this.dataStore.invoke(releaseMessage,new AsyncResponder(noOp,noOp));
            }
            if(dataList.smo && dataList.itemReference != null)
            {
               if(items.length == 1)
               {
                  dataList.itemReference.setResult(items[0]);
               }
               else
               {
                  dataList.itemReference.setResult(null);
               }
            }
         }
         finally
         {
            enablePaging();
         }
         return items;
      }
      
      function removeAll(dataList:DataList) : Array
      {
         var uid:String = null;
         var item:Object = null;
         var leafDS:ConcreteDataService = null;
         try
         {
            dataList.getItemAt(0,dataList.length);
         }
         catch(e:ItemPendingError)
         {
            e.addResponder(new AsyncResponder(removeAllHandler,dispatchFaultEvent,dataList));
            throw e;
         }
         var refs:Array = dataList.references;
         var result:Array = [];
         var i:int = 0;
         while(refs.length > i)
         {
            uid = refs[i];
            if(uid != null)
            {
               item = this._itemCache[uid];
               if(item != null)
               {
                  leafDS = this.getItemDestination(item);
                  leafDS.removeChangeListener(IManaged(item));
                  result.push(item);
                  leafDS.removeReferencesTo(uid,item,true,false);
                  if(this.logChanges == 0)
                  {
                     this.dataStore.logRemove(leafDS,item);
                  }
                  leafDS.removeItemFromCache(uid,false);
               }
            }
            else
            {
               i++;
            }
         }
         this.dataStore.doAutoCommit(DeleteItemCommitResponder);
         return result;
      }
      
      function removeReferencesTo(uid:String, item:Object, removeSMOs:Boolean, remote:Boolean) : void
      {
         var dl:DataList = null;
         var location:int = 0;
         var i:uint = 0;
         var dls:Array = this.getDataListsForUID(uid);
         if(dls != null)
         {
            dls = this.shallowCopyArray(dls);
            for(i = 0; i < dls.length; i++)
            {
               dl = DataList(dls[i]);
               if(!dl.smo)
               {
                  if(dl.association != null && !dl.association.pagedUpdates && this.logChanges == 0)
                  {
                     if((location = dl.getUIDIndex(uid)) != -1)
                     {
                        dl.internalRemoveItemAt(location,removeSMOs,remote);
                     }
                  }
                  else
                  {
                     location = dl.removeReference(uid,true,false,remote);
                     if(location != -1)
                     {
                        if(this.logChanges == 0)
                        {
                           this.dataStore.logCollectionUpdate(this,dl,UpdateCollectionRange.DELETE_FROM_COLLECTION,location,this.getItemIdentifier(item),null);
                        }
                        if(dl.itemReference != null)
                        {
                           dl.itemReference.setResult(null);
                        }
                     }
                  }
               }
               else if(!removeSMOs && dl.references.length == 1 && dl.references[0] == uid)
               {
                  if(dl.itemReference != null)
                  {
                     dl.itemReference.setResult(null);
                  }
               }
            }
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).removeReferencesTo(uid,item,removeSMOs,remote);
            }
         }
      }
      
      function removeDataList(dataList:DataList) : Boolean
      {
         var i:int = 0;
         var p:* = null;
         var index:int = this._dataLists.getItemIndex(dataList);
         if(index == -1)
         {
            if(Log.isError())
            {
               this._log.error(resourceManager.getString("data","invalidRemoveDataList"),this.destination,dataList.collectionId);
            }
         }
         else if(--dataList.referenceCount == 0)
         {
            if(dataList.parentItem != null)
            {
               dataList.parentDataService.removeFromChildDataListIndex(dataList);
            }
            for(i = 0; i < dataList.references.length; i++)
            {
               this.removeDataListIndexEntry(dataList,dataList.references[i]);
            }
            this._dataLists.removeItemAt(index);
            if(_indexReferences && this._dataLists.length == 0)
            {
               for(p in this._itemDataListIndex)
               {
                  throw new DataServiceError("No data lists but do have items in itemDataListIndex: " + p);
               }
            }
            if(this._dataLists.length == 0)
            {
               this.clientIdsAdded = false;
            }
            return true;
         }
         return false;
      }
      
      function removeItem(uid:String, returnToken:Boolean = false, remote:Boolean = false) : Object
      {
         var msg:DataMessage = null;
         var token:AsyncToken = null;
         var leafDS:ConcreteDataService = null;
         var event:MessageEvent = null;
         var item:Object = this._itemCache[uid];
         var result:Object = item;
         if(result != null)
         {
            leafDS = this.getItemDestination(item);
            leafDS.removeChangeListener(IManaged(item));
            leafDS.removeReferencesTo(uid,item,false,remote);
            if(this.logChanges == 0)
            {
               msg = this.dataStore.logRemove(leafDS,item);
               token = this.dataStore.doAutoCommit(DeleteItemCommitResponder,returnToken);
               if(returnToken && token != null)
               {
                  token.setMessage(msg);
                  result = token;
               }
            }
            else if(returnToken)
            {
               msg = new DataMessage();
               msg.operation = DataMessage.DELETE_OPERATION;
               this.addMaxFrequencyHeaderIfNecessary(msg);
               msg.body = item;
               token = new AsyncToken(msg);
               event = MessageEvent.createEvent(MessageEvent.RESULT,msg);
               new AsyncDispatcher(this.dispatchResultEvent,[event,token,item],10);
               result = token;
            }
            leafDS.removeItemFromCache(uid,true);
            leafDS.releaseAssociations(item,false,false,null,null,true,false);
         }
         return result;
      }
      
      function replaceDataListReferencesTo(oldId:String, newId:String, item:Object, newIdentity:Object) : void
      {
         var i:int = 0;
         var dataList:DataList = null;
         var idx:int = 0;
         var referencedIdTable:Object = null;
         var referencedIds:Object = null;
         var pendingUCs:Array = null;
         var j:int = 0;
         var uc:UpdateCollectionMessage = null;
         var ucmsg:UpdateCollectionMessage = null;
         var dls:Array = this.getDataListsForUID(oldId);
         if(dls != null)
         {
            dls = this.shallowCopyArray(dls);
            for(i = 0; i < dls.length; i++)
            {
               dataList = DataList(dls[i]);
               idx = dataList.getUIDIndex(oldId);
               if(idx != -1)
               {
                  dataList.replaceReferenceAt(newId,idx);
                  if(dataList.association != null)
                  {
                     referencedIdTable = dataList.parentItem.referencedIds;
                     if(referencedIdTable != null)
                     {
                        if(dataList.association.typeCode == ManagedAssociation.MANY)
                        {
                           referencedIds = referencedIdTable[dataList.association.property];
                           if(referencedIds != null && referencedIds.length > idx)
                           {
                              referencedIds[idx] = newIdentity;
                           }
                        }
                        else if(idx == 0)
                        {
                           referencedIdTable[dataList.association.property] = newIdentity;
                        }
                     }
                  }
               }
               if(!dataList.smo && (dataList.association == null || dataList.association.pagedUpdates))
               {
                  pendingUCs = this.dataStore.messageCache.getPendingUpdateCollections(this.destination,dataList.collectionId,true);
                  for(j = 0; j < pendingUCs.length; j++)
                  {
                     uc = pendingUCs[j];
                     uc.replaceIdentity(oldId,newIdentity);
                  }
               }
            }
         }
         pendingUCs = this.dataStore.messageCache.getPendingUpdateCollections(this.destination,oldId,true);
         if(pendingUCs != null)
         {
            for(i = 0; i < pendingUCs.length; i++)
            {
               ucmsg = UpdateCollectionMessage(pendingUCs[i]);
               ucmsg.collectionId = {
                  "prop":ucmsg.collectionId.prop,
                  "parent":ucmsg.collectionId.parent,
                  "id":this.getItemIdentifier(item)
               };
               this.dataStore.messageCache.updateUIDItemIndex(ucmsg);
            }
         }
         pendingUCs = this.dataStore.messageCache.getPendingUpdateCollectionReferences(this.destination,oldId);
         if(pendingUCs != null)
         {
            for(i = 0; i < pendingUCs.length; i++)
            {
               pendingUCs[i].replaceIdentity(oldId,newIdentity);
            }
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).replaceDataListReferencesTo(oldId,newId,item,newIdentity);
            }
         }
      }
      
      function revertMessage(message:DataMessage) : Boolean
      {
         var id:String = null;
         var dataList:DataList = null;
         var deletedItem:Object = null;
         var ucMsg:UpdateCollectionMessage = null;
         if(Log.isDebug())
         {
            this._log.debug("DataService.revertMessage called for destination: {0} message:\n  {1}",this.destination,message);
         }
         this.disableLogging();
         var result:Boolean = false;
         try
         {
            if(message.operation == DataMessage.DELETE_OPERATION)
            {
               deletedItem = message.unwrapBody();
               id = this.metadata.getUID(message.identity);
               this.reAddItem(id,IManaged(this.normalize(deletedItem)));
               result = true;
            }
            else if(message.isCreate())
            {
               if(this.getItem(message.messageId) != null)
               {
                  id = message.messageId;
               }
               else
               {
                  id = this.metadata.getUID(message.identity);
               }
               this.removeItem(id);
               result = true;
            }
            else if(message.operation == DataMessage.UPDATE_OPERATION)
            {
               result = this.updateItemWithId(message.identity,DataMessage.unwrapItem(message.body[DataMessage.UPDATE_BODY_PREV]),message.body[DataMessage.UPDATE_BODY_CHANGES],DataMessage.unwrapItem(message.headers.prevReferencedIds),true);
            }
            else if(message.operation == DataMessage.UPDATE_COLLECTION_OPERATION)
            {
               ucMsg = UpdateCollectionMessage(message);
               dataList = this.getDataListWithCollectionId(ucMsg.collectionId);
               if(dataList != null)
               {
                  dataList.applyUpdateCollection(ucMsg,true,true,false,true);
                  result = true;
               }
            }
         }
         finally
         {
            this.enableLogging();
         }
         return result;
      }
      
      private function reAddItem(uid:String, item:IManaged) : void
      {
         if(Log.isDebug())
         {
            this._log.debug("Item with uid: " + uid + " is being added back under management");
         }
         var refIds:Object = null;
         if(this.metadata.needsReferencedIds)
         {
            refIds = Managed.getReferencedIds(item);
            Managed.setReferencedIds(item,new Object());
         }
         this.addItem(item,DataMessage.CREATE_OPERATION,false,true,refIds,null,true);
         this.restoreSMOReferences(uid);
      }
      
      private function restoreSMOReferences(id:String) : void
      {
         var dataList:DataList = null;
         var i:int = 0;
         var dls:Array = this.getDataListsForUID(id);
         if(dls != null)
         {
            for(i = 0; i < dls.length; i++)
            {
               dataList = dls[i];
               if(dataList.itemReference != null)
               {
                  dataList.itemReference.setResult(this.getItem(id));
               }
            }
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).restoreSMOReferences(id);
            }
         }
      }
      
      function updateArrayCollectionItems(acTo:ArrayCollection, acToIds:Array, acFrom:Array, lazy:Boolean, referencedIds:Object = null, pendingItems:Object = null, updateToIds:Boolean = false) : void
      {
         var fromUID:String = null;
         var newUID:String = null;
         var acToIdObj:Object = null;
         var acToIdObjRID:Object = null;
         var k:int = 0;
         var identity:Object = null;
         var uid:String = null;
         var newItem:Object = null;
         var event:CollectionEvent = null;
         if(acToIds == acFrom)
         {
            return;
         }
         var acFromUIDs:Array = new Array(acFrom.length);
         var acFromIndex:Object = {};
         for(var i:int = 0; i < acFrom.length; i++)
         {
            fromUID = acFromUIDs[i] = this.getUIDFromReferencedId(acFrom[i]);
            acFromIndex[fromUID] = i;
         }
         for(i = 0; i < acFrom.length; i++)
         {
            newUID = acFromUIDs[i];
            acToIdObj = null;
            acToIdObjRID = null;
            if(i < acTo.list.length)
            {
               if(!lazy)
               {
                  acToIdObj = acTo.list.getItemAt(i);
               }
               else
               {
                  acToIdObj = acToIds[i];
               }
               acToIdObjRID = this.getUIDFromReferencedId(acToIdObj);
            }
            if(i >= acTo.list.length || acToIdObjRID != newUID)
            {
               if(i < acTo.list.length)
               {
                  if(acFromIndex[acToIdObjRID] == null)
                  {
                     acTo.list.removeItemAt(i);
                     if(lazy && updateToIds)
                     {
                        acToIds.splice(i,1);
                     }
                  }
               }
               for(k = i; k < acTo.list.length; k++)
               {
                  if(!lazy)
                  {
                     acToIdObj = acTo.list.getItemAt(k);
                  }
                  else
                  {
                     acToIdObj = acToIds[k];
                  }
                  if(!(acToIdObj is String) && this.getUIDFromReferencedId(acToIdObj) == newUID)
                  {
                     break;
                  }
               }
               if(k != i || k >= acTo.list.length)
               {
                  if(k < acTo.list.length)
                  {
                     acTo.list.removeItemAt(k);
                     if(lazy && updateToIds)
                     {
                        acToIds.splice(k,1);
                     }
                  }
                  if(lazy)
                  {
                     identity = acFrom[i];
                     uid = acFromUIDs[i];
                     newItem = this.getItemForReference(uid);
                     if(updateToIds)
                     {
                        if(i == acToIds.length)
                        {
                           acToIds.push(identity);
                        }
                        else
                        {
                           acToIds.splice(i,0,identity);
                        }
                     }
                     if(acTo.list is DataList)
                     {
                        DataList(acTo.list).addReferenceAt(uid,identity,i,false);
                     }
                     else
                     {
                        acTo.list.addItemAt(newItem,i);
                     }
                     event = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                     event.kind = CollectionEventKind.ADD;
                     event.location = i;
                     event.items.push(newItem);
                     acTo.list.dispatchEvent(event);
                  }
                  else if(acTo.list is DataList)
                  {
                     DataList(acTo.list).doAddItemAt(acFrom[i],i,referencedIds == null?null:referencedIds[i],pendingItems);
                  }
                  else
                  {
                     acTo.list.addItemAt(acFrom[i],i);
                  }
               }
            }
         }
         while(acTo.list.length > acFrom.length)
         {
            acTo.list.removeItemAt(acTo.list.length - 1);
            if(lazy && updateToIds)
            {
               acToIds.splice(acToIds.length - 1,1);
            }
         }
      }
      
      function updateCacheWithId(uid:String, item:Object, includes:Array, excludes:Array, referencedIds:Object, skipId:Boolean = true, checkConflicts:Boolean = true, pendingItems:Object = null) : Boolean
      {
         if(uid == "")
         {
            return false;
         }
         var cacheItem:IManaged = IManaged(this._itemCache[uid]);
         return this.updateCache(uid,uid,cacheItem,item,includes,excludes,referencedIds,skipId,checkConflicts,pendingItems);
      }
      
      function updateCache(oldUID:String, newUID:String, cacheItem:IManaged, item:Object, includes:Array, excludes:Array, referencedIds:Object, skipId:Boolean = true, checkConflicts:Boolean = true, pendingItems:Object = null) : Boolean
      {
         var msg:DataMessage = null;
         var pendingState:int = 0;
         var md:Metadata = null;
         var oldOverriddenProperties:Array = null;
         var i:int = 0;
         var oldestMessage:DataMessage = null;
         var origItem:Object = null;
         var origRefIds:Object = null;
         var rawItem:Object = null;
         var changes:Array = null;
         var fakeUpdate:DataMessage = null;
         var remoteChange:IChangeObject = null;
         var localChange:IChangeObject = null;
         var conflict:DataErrorMessage = null;
         var changedProperties:Array = null;
         var assocIncludes:Array = null;
         var toCopy:Array = null;
         var result:Boolean = true;
         if(pendingItems != null)
         {
            pendingState = int(pendingItems[newUID]);
            if(pendingState & PENDING_STATE_CACHED)
            {
               return true;
            }
            pendingItems[newUID] = pendingState | PENDING_STATE_CACHED;
         }
         var messages:Array = this.getPendingMessages(oldUID);
         var overriddenProperties:Array = excludes == null?[]:excludes;
         if(cacheItem != null)
         {
            if(Log.isDebug())
            {
               this.log.debug("Updating cached item for: " + newUID + " excluding properties: " + itemToString(excludes) + (includes == null?"":" updating only: " + itemToString(includes)));
            }
         }
         this.disableLogging();
         try
         {
            if(messages.length > 0)
            {
               md = this.getItemMetadata(item);
               if(md.needsReferencedIds && referencedIds != null)
               {
                  md.convertServerToClientReferencedIds(item,referencedIds,this.includeAllSpecifier);
               }
               if(checkConflicts)
               {
                  oldestMessage = this.dataStore.messageCache.getOldestMessage(this,oldUID);
                  if(oldestMessage != null && (oldestMessage.operation == DataMessage.UPDATE_OPERATION || oldestMessage.operation == DataMessage.DELETE_OPERATION))
                  {
                     rawItem = unnormalize(item);
                     if(oldestMessage.operation == DataMessage.UPDATE_OPERATION)
                     {
                        origItem = DataMessage.unwrapItem(oldestMessage.body[DataMessage.UPDATE_BODY_PREV]);
                        origRefIds = DataMessage.unwrapItem(oldestMessage.headers.prevReferencedIds);
                     }
                     else
                     {
                        origItem = oldestMessage.unwrapBody();
                        origRefIds = DataMessage.unwrapItem(oldestMessage.headers.referencedIds);
                     }
                     changes = this.getChangedProperties(rawItem,origItem,includes == null?this.includeDefaultSpecifier:PropertySpecifier.getPropertySpecifier(this,includes,false),excludes,referencedIds,origRefIds);
                     if(changes != null && changes.length > 0)
                     {
                        fakeUpdate = new DataMessage();
                        fakeUpdate.operation = DataMessage.UPDATE_OPERATION;
                        fakeUpdate.destination = this.destination;
                        fakeUpdate.identity = this.getItemIdentifier(rawItem);
                        fakeUpdate.body = new Array(3);
                        fakeUpdate.body[DataMessage.UPDATE_BODY_PREV] = DataMessage.wrapItem(origItem,this.destination);
                        fakeUpdate.headers.prevReferencedIds = this.dataStore.messageCache.wrapReferencedIds(this,origRefIds,false);
                        fakeUpdate.body[DataMessage.UPDATE_BODY_NEW] = DataMessage.wrapItem(rawItem,this.destination);
                        fakeUpdate.headers.newReferencedIds = this.dataStore.messageCache.wrapReferencedIds(this,referencedIds,false);
                        fakeUpdate.body[DataMessage.UPDATE_BODY_CHANGES] = changes;
                        remoteChange = new ChangeObject(fakeUpdate,item,this);
                        localChange = this.getLocalChange(oldUID,item);
                        this.conflictDetector.checkUpdate(remoteChange,localChange);
                        conflict = remoteChange.getConflict();
                        if(conflict != null)
                        {
                           this.dataStore.processConflict(this,conflict,null);
                           return oldestMessage.operation != DataMessage.DELETE_OPERATION;
                        }
                     }
                  }
               }
               for(i = messages.length - 1; i >= 0; i--)
               {
                  msg = DataMessage(messages[i]);
                  if(msg.operation == DataMessage.UPDATE_OPERATION)
                  {
                     changedProperties = msg.body[DataMessage.UPDATE_BODY_CHANGES] as Array;
                     if(oldUID != newUID)
                     {
                        msg.identity = this.getIdentityMap(item);
                        this.dataStore.messageCache.updateUIDItemIndex(msg);
                     }
                     copyValues(msg.body[DataMessage.UPDATE_BODY_PREV],item,includes,overriddenProperties.concat(md.associationNames));
                     oldOverriddenProperties = overriddenProperties;
                     overriddenProperties = overriddenProperties.concat(changedProperties);
                     copyValues(msg.body[DataMessage.UPDATE_BODY_NEW],item,includes,overriddenProperties.concat(md.associationNames));
                     if(md.needsReferencedIds && referencedIds != null)
                     {
                        assocIncludes = intersectArrays(includes,md.associationNames);
                        copyValues(DataMessage.unwrapItem(msg.headers.prevReferencedIds),referencedIds,assocIncludes,oldOverriddenProperties);
                        copyValues(DataMessage.unwrapItem(msg.headers.newReferencedIds),referencedIds,assocIncludes,overriddenProperties);
                     }
                     if(i == 0 && cacheItem != null)
                     {
                        this.updateItemInCache(cacheItem,item,includes,overriddenProperties,referencedIds,skipId,false,pendingItems);
                     }
                  }
                  else if(msg.operation == DataMessage.DELETE_OPERATION)
                  {
                     if(md.associationNames == null)
                     {
                        toCopy = ["uid"];
                     }
                     else
                     {
                        toCopy = md.associationNames.concat("uid");
                     }
                     copyValues(msg.unwrapBody(),item,includes,toCopy);
                     if(md.needsReferencedIds && referencedIds != null)
                     {
                        toCopy = intersectArrays(includes,md.associationNames);
                        copyValues(DataMessage.unwrapItem(msg.headers.referencedIds),referencedIds,toCopy);
                     }
                     result = false;
                  }
                  else if(msg.operation == DataMessage.CREATE_OPERATION && cacheItem != null)
                  {
                     if(Log.isError())
                     {
                        this._log.error("{0} A fill() returned an item that we have pending as a create this is a local conflict",this._consumer.id);
                     }
                  }
               }
            }
            else if(cacheItem != null)
            {
               this.updateItemInCache(cacheItem,item,includes,overriddenProperties,referencedIds,skipId,false,pendingItems);
            }
            if(result)
            {
               this.addItemToOffline(newUID,cacheItem);
               this.internalUpdateCache(newUID,cacheItem,item);
            }
         }
         finally
         {
            while(true)
            {
               this.enableLogging();
            }
         }
         break loop1;
      }
      
      function setAssociationsFromIds(item:Object, refIds:Object) : void
      {
         var propName:* = null;
         var association:ManagedAssociation = null;
         var ids:Array = null;
         var ac:ArrayCollection = null;
         var i:int = 0;
         var refItem:Object = null;
         if(!this.metadata.needsReferencedIds)
         {
            return;
         }
         for(propName in this.metadata.associations)
         {
            association = ManagedAssociation(this.metadata.associations[propName]);
            if(association.typeCode == ManagedAssociation.MANY)
            {
               ids = refIds[propName];
               if(ids != null)
               {
                  ac = item[propName];
                  if(ac == null)
                  {
                     ac = item[propName] = new ArrayCollection();
                  }
                  else
                  {
                     ac.removeAll();
                  }
                  for(i = 0; i < ids.length; i++)
                  {
                     refItem = association.service.getItemForReferenceFromIdentity(ids[i],false);
                     ac.addItem(refItem);
                  }
               }
            }
            else
            {
               item[propName] = association.service.getItemForReferenceFromIdentity(refIds[propName],false);
            }
         }
      }
      
      function updateItemWithId(identity:Object, values:Object, includes:Array, fromReferencedIds:Object, useReferencedIds:Boolean = false) : Boolean
      {
         var uid:String = this.getUIDFromIdentity(identity);
         var item:Object = this.getItemForReference(uid,false);
         var itemUpdated:Boolean = false;
         if(item != null)
         {
            this.updateItemInCache(item,values,includes,null,fromReferencedIds,true,useReferencedIds);
            itemUpdated = true;
         }
         return itemUpdated;
      }
      
      function updateItemInCache(item:Object, values:Object, includes:Array, excludes:Array, fromReferencedIds:Object, skipId:Boolean = true, useReferencedIds:Boolean = false, pendingItems:Object = null) : void
      {
         var properties:Array = null;
         var propName:String = null;
         item = DataMessage.unwrapItem(item);
         values = DataMessage.unwrapItem(values);
         if(item == values)
         {
            return;
         }
         if(includes != null)
         {
            properties = includes;
         }
         else
         {
            properties = getObjectProperties(values);
         }
         for(var i:uint = 0; i < properties.length; i++)
         {
            propName = properties[i];
            if(excludes == null || ArrayUtil.getItemIndex(propName,excludes) == -1)
            {
               if(propName != "uid" || !skipId)
               {
                  this.updateManagedProperty(item,values,propName,fromReferencedIds,useReferencedIds,pendingItems);
               }
            }
         }
      }
      
      function releaseItemIfNoDataListReferences(item:IManaged) : void
      {
         var leafDS:ConcreteDataService = this.getItemDestination(item);
         if(leafDS != this)
         {
            leafDS.releaseItemIfNoDataListReferences(item);
            return;
         }
         if(this._delayedReleases > 0)
         {
            if(this._toRelease == null)
            {
               this._toRelease = new Array();
            }
            this._toRelease.push(item);
         }
         else if(this.getAllDataLists(item.uid,true) == null)
         {
            this.internalReleaseItem(item,false,false,true);
            this.releaseAssociations(item,false,false,null,null,true);
         }
         else
         {
            this.queueReferenceCheck(item);
         }
      }
      
      private function queueReferenceCheck(item:IManaged, checkTime:int = 0) : void
      {
         var refEnt:ReferenceCheckEntry = new ReferenceCheckEntry(item,checkTime);
         this._referenceCheckItems.push(refEnt);
         if(this._referenceCheckTimer == null)
         {
            this._referenceCheckTimer = new Timer(this.REFERENCE_CHECK_INTERVAL);
            this._referenceCheckTimer.addEventListener(TimerEvent.TIMER,this.checkReferences);
            this._referenceCheckTimer.start();
         }
      }
      
      private function checkReferences(event:TimerEvent) : void
      {
         var refEnt:ReferenceCheckEntry = null;
         var item:IManaged = null;
         var nowTime:int = getTimer();
         var deleteCount:int = 0;
         var releasedCount:int = 0;
         var referencedCache:Object = new Object();
         for(var i:int = 0; i < this._referenceCheckItems.length; )
         {
            refEnt = ReferenceCheckEntry(this._referenceCheckItems[i]);
            item = refEnt.item;
            if(refEnt.checkTime <= nowTime)
            {
               if(this._itemCache[item.uid] != null && !this.isItemReferenced(item,new Dictionary(),referencedCache))
               {
                  this.internalReleaseItem(item,false,false,true);
                  this.releaseAssociations(item,false,false,null,referencedCache,true);
                  releasedCount++;
               }
               deleteCount++;
               i++;
               continue;
            }
            break;
         }
         if(deleteCount > 0)
         {
            this._referenceCheckItems.splice(0,deleteCount);
            if(this._referenceCheckItems.length == 0)
            {
               this._referenceCheckTimer.stop();
               this._referenceCheckTimer = null;
            }
         }
         if(Log.isDebug())
         {
            this._log.debug("checkReferences - processed: " + deleteCount + " released: " + releasedCount + " remaining: " + this._referenceCheckItems.length);
         }
      }
      
      function removeItemIfNoDataListReferences(item:IManaged) : void
      {
         var leafDS:ConcreteDataService = this.getItemDestination(item);
         if(leafDS.getAllDataLists(item.uid,true) == null)
         {
            leafDS.removeItem(item.uid);
         }
      }
      
      function enableDelayedReleases() : void
      {
         this._delayedReleases++;
      }
      
      function disableDelayedReleases() : void
      {
         var i:int = 0;
         if(--this._delayedReleases == 0)
         {
            if(this._toRelease != null)
            {
               for(i = 0; i < this._toRelease.length; i++)
               {
                  this.releaseItemIfNoDataListReferences(this._toRelease[i]);
               }
               this._toRelease = null;
            }
         }
      }
      
      function enableDelayedCollectionEvents() : void
      {
         this._delayedCollectionEvents++;
      }
      
      function disableDelayedCollectionEvents() : void
      {
         var i:int = 0;
         if(--this._delayedCollectionEvents == 0)
         {
            if(this._pendingCollectionEvents != null)
            {
               for(i = 0; i < this._pendingCollectionEvents.length; i++)
               {
                  this.dispatchLeafCollectionEvent(CollectionEvent(this._pendingCollectionEvents[i]));
               }
               this._pendingCollectionEvents = null;
            }
         }
      }
      
      private function addAssociationClientIds(assocClients:Object) : void
      {
         var propName:* = null;
         var association:ManagedAssociation = null;
         var i:int = 0;
         var stDS:ConcreteDataService = null;
         for(propName in this.metadata.associations)
         {
            association = ManagedAssociation(this.metadata.associations[propName]);
            if(assocClients[association.service.destination] == null)
            {
               assocClients[association.service.destination] = association.service._consumer.clientId;
               association.service.addAssociationClientIds(assocClients);
            }
         }
         if(this._subTypes != null)
         {
            for(i = 0; i < this._subTypes.length; i++)
            {
               stDS = ConcreteDataService(this._subTypes[i]);
               if(assocClients[stDS.destination] == null)
               {
                  assocClients[stDS.destination] = stDS._consumer.clientId;
                  stDS.addAssociationClientIds(assocClients);
               }
            }
         }
      }
      
      private function addAssociationClientIdsToMessage(msg:DataMessage) : void
      {
         var assocClients:Object = null;
         if(!this.clientIdsAdded)
         {
            this.clientIdsAdded = true;
            if(this.metadata.needsReferencedIds)
            {
               assocClients = new Object();
               msg.headers.destClientIds = assocClients;
               this.addAssociationClientIds(assocClients);
            }
         }
      }
      
      private function addChangeListener(item:IManaged) : void
      {
         if(item)
         {
            item.addEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.itemUpdateHandler,false,EventPriority.BINDING + 200,true);
         }
      }
      
      private function asyncDispatchFaultEvent(event:MessageFaultEvent, token:AsyncToken, id:Object = null) : void
      {
         new AsyncDispatcher(this.dispatchFaultEvent,[event,token,id],10);
      }
      
      private function isItemReferenced(item:IManaged, visited:Dictionary, referencedCache:Object, checkPendingMessages:Boolean = true) : Boolean
      {
         var i:int = 0;
         var uid:String = item.uid;
         var cacheEnt:* = referencedCache[uid];
         if(cacheEnt !== undefined)
         {
            return Boolean(cacheEnt);
         }
         if(visited[item] != null)
         {
            return false;
         }
         visited[item] = true;
         if(this.isItemReferencedInternal(item,visited,referencedCache,checkPendingMessages))
         {
            referencedCache[uid] = true;
            return true;
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               if(ConcreteDataService(this.extendsDestinations[i]).isItemReferencedInternal(item,visited,referencedCache,checkPendingMessages))
               {
                  referencedCache[uid] = true;
                  return true;
               }
            }
         }
         referencedCache[uid] = false;
         return false;
      }
      
      private function isItemReferencedInternal(item:IManaged, visited:Dictionary, referencedCache:Object, checkPendingMessages:Boolean) : Boolean
      {
         var i:int = 0;
         var referencingItem:IManaged = null;
         var lists:Array = this.getDataListsForUID(item.uid);
         if(lists != null)
         {
            for(i = 0; i < lists.length; i++)
            {
               if(lists[i].association == null)
               {
                  return true;
               }
               referencingItem = IManaged(lists[i].parentItem);
               if(lists[i].parentDataService.isItemReferenced(referencingItem,visited,referencedCache,checkPendingMessages))
               {
                  return true;
               }
            }
         }
         if(checkPendingMessages && this.getPendingMessages(item.uid).length > 0)
         {
            return true;
         }
         return false;
      }
      
      private function checkInitialized() : void
      {
         if(!this.initialized)
         {
            throw new DataServiceError("Dataservice is not initialized. Operation can\'t be performed.");
         }
      }
      
      private function checkIdentitySpecified(identity:Object) : ErrorMessage
      {
         var unspecifiedProps:Array = null;
         var uidProps:Array = null;
         var i:int = 0;
         var prop:String = null;
         if(identity is ObjectProxy)
         {
            identity = ObjectProxy(identity).object_proxy::object;
         }
         if(identity == null)
         {
            return this.createLocalCallError(resourceManager.getString("data","nullIdentity"));
         }
         unspecifiedProps = null;
         uidProps = this.metadata.identities;
         for(i = 0; i < uidProps.length; i++)
         {
            prop = uidProps[i];
            if(!identity.hasOwnProperty(prop))
            {
               if(unspecifiedProps == null)
               {
                  unspecifiedProps = [];
               }
               unspecifiedProps.push(prop);
            }
         }
         if(unspecifiedProps != null)
         {
            return this.createLocalCallError(resourceManager.getString("data","missingIdProperty",unspecifiedProps));
         }
         return null;
      }
      
      private function createLocalCallError(faultString:String) : ErrorMessage
      {
         var result:ErrorMessage = new ErrorMessage();
         result.faultCode = "Local.Call.Failed";
         result.faultString = faultString;
         return result;
      }
      
      function autoSubscribe(clientId:String = null) : void
      {
         this._autoSyncCount++;
         if(this._autoSyncCount == 1)
         {
            if(!this._manuallySubscribed)
            {
               this.doSubscribe(clientId);
            }
         }
      }
      
      private function doSubscribe(clientId:String = null) : void
      {
         var i:int = 0;
         var stDS:ConcreteDataService = null;
         this.reconnect();
         this._consumer.subscribe(clientId);
         if(this._subTypes != null)
         {
            for(i = 0; i < this._subTypes.length; i++)
            {
               stDS = ConcreteDataService(this._subTypes[i]);
               stDS.autoSubscribe();
            }
         }
         if(this._consumer.channelSet != null && this._consumer.channelSet.connected && this._consumer.channelSet.currentChannel != null && this._consumer.channelSet.currentChannel is PollingChannel)
         {
            PollingChannel(this._consumer.channelSet.currentChannel).enablePolling();
         }
      }
      
      private function doUnsubscribe() : void
      {
         var i:int = 0;
         var stDS:ConcreteDataService = null;
         if(this._consumer.channelSet != null && this._consumer.channelSet.currentChannel != null && this._consumer.channelSet.currentChannel is PollingChannel)
         {
            PollingChannel(this._consumer.channelSet.currentChannel).disablePolling();
         }
         if(this._subTypes != null)
         {
            for(i = 0; i < this._subTypes.length; i++)
            {
               stDS = ConcreteDataService(this._subTypes[i]);
               stDS.autoUnsubscribe();
            }
         }
         this._consumer.unsubscribe();
      }
      
      function autoUnsubscribe() : void
      {
         if(--this._autoSyncCount == 0)
         {
            if(!this._manuallySubscribed)
            {
               this.doUnsubscribe();
            }
         }
      }
      
      function manualSubscribe(clientId:String = null) : void
      {
         if(!this._manuallySubscribed)
         {
            if(this._autoSyncCount == 0)
            {
               this.doSubscribe(clientId);
            }
            this._manuallySubscribed = true;
         }
      }
      
      function manualUnsubscribe() : void
      {
         if(this._manuallySubscribed)
         {
            this._manuallySubscribed = false;
            if(this._autoSyncCount == 0)
            {
               this.doUnsubscribe();
            }
         }
      }
      
      function addMessageRoutingHeaders(msg:DataMessage) : void
      {
         var header:* = null;
         if(this._manualSync != null)
         {
            if(this._manualSync.producerSubtopics != null && this._manualSync.producerSubtopics.length > 0)
            {
               msg.headers[AsyncMessage.SUBTOPIC_HEADER] = this._manualSync.producerSubtopics;
            }
            if(this._manualSync.producerDefaultHeaders != null)
            {
               for(header in this._manualSync.producerDefaultHeaders)
               {
                  if(!msg.headers.hasOwnProperty(header))
                  {
                     msg.headers[header] = this._manualSync.producerDefaultHeaders[header];
                  }
               }
            }
         }
      }
      
      function getDataListsForUID(uid:String) : Array
      {
         var dls:Array = null;
         var i:int = 0;
         if(_indexReferences)
         {
            return this._itemDataListIndex[uid];
         }
         if(uid == null)
         {
            return null;
         }
         dls = [];
         for(i = 0; i < this._dataLists.length; i++)
         {
            if(DataList(this._dataLists.getItemAt(i)).getUIDIndex(uid) != -1)
            {
               dls.push(this.dataLists.getItemAt(i));
            }
         }
         return dls;
      }
      
      function addDataListIndexEntry(dataList:DataList, uid:String) : void
      {
         if(!_indexReferences)
         {
            return;
         }
         if(uid == null)
         {
            return;
         }
         var dataLists:Array = this._itemDataListIndex[uid];
         if(dataLists == null)
         {
            this._itemDataListIndex[uid] = dataLists = [];
         }
         dataLists.push(dataList);
      }
      
      function removeDataListIndexEntry(dataList:DataList, uid:String) : void
      {
         var ix:int = 0;
         if(!_indexReferences)
         {
            return;
         }
         if(uid == null)
         {
            return;
         }
         var dataLists:Array = this._itemDataListIndex[uid];
         if(dataLists == null)
         {
            throw new DataServiceError("Unable to find data list entry to remove: " + uid);
         }
         if(dataLists != null)
         {
            ix = ArrayUtil.getItemIndex(dataList,dataLists);
            if(ix == -1)
            {
               throw new DataServiceError("Unable to find data list entry to remove: " + uid);
            }
            if(ix != -1)
            {
               dataLists.splice(ix,1);
               if(dataLists.length == 0)
               {
                  delete this._itemDataListIndex[uid];
               }
            }
         }
      }
      
      function addSubtype(otherType:ConcreteDataService) : void
      {
         if(this._classToSubDest == null)
         {
            this._classToSubDest = {};
            this._classToSubDest[this.metadata.itemClass] = this;
            this._subTypes = [];
         }
         this._classToSubDest[otherType.metadata.itemClass] = otherType;
         this._subTypes.push(otherType);
      }
      
      function getItemMetadata(inst:Object) : Metadata
      {
         return this.getItemDestination(inst).metadata;
      }
      
      function getItemDestination(inst:Object) : ConcreteDataService
      {
         var dest:String = null;
         var cds:ConcreteDataService = null;
         if(inst == null)
         {
            return this;
         }
         if(this.metadata.typeProperty != null && inst.hasOwnProperty(this.metadata.typeProperty))
         {
            dest = inst[this.metadata.typeProperty];
            if(dest == null)
            {
               return this;
            }
            cds = lookupService(dest);
            if(cds == null)
            {
               throw new ArgumentError("Unable to find destination: " + dest + " Value of typeProperty: " + this.metadata.typeProperty + " refers to a non-existent type");
            }
            return cds;
         }
         if(inst is ManagedObjectProxy)
         {
            return this;
         }
         return this.getDestinationForInstance(inst);
      }
      
      function getDestinationForInstance(inst:Object) : ConcreteDataService
      {
         var actualInst:Object = inst;
         if(inst is SerializationProxy)
         {
            actualInst = inst.instance;
         }
         var cl:Class = inst.constructor as Class;
         if(this._classToSubDest == null)
         {
            return this;
         }
         var cds:ConcreteDataService = this._classToSubDest[cl];
         if(cds != null)
         {
            return cds;
         }
         cds = this.findInstanceDestination(actualInst);
         if(cds != null)
         {
            this._classToSubDest[cl] = cds;
            return cds;
         }
         throw new DataServiceError("Destination: " + this.destination + " received an instance of class: " + getQualifiedClassName(inst) + " but we could not find a destination in the list of sub-types: " + this.getSubTypesString() + " which extends this destination.");
      }
      
      function getSubTypesString() : String
      {
         var cds:ConcreteDataService = null;
         var subSubTypesString:String = null;
         if(this._subTypes == null)
         {
            return "";
         }
         var subTypesString:String = "";
         for(var i:int = 0; i < this._subTypes.length; i++)
         {
            cds = ConcreteDataService(this._subTypes[i]);
            if(i != 0)
            {
               subTypesString = subTypesString + ",";
            }
            subTypesString = subTypesString + cds.destination;
            subSubTypesString = cds.getSubTypesString();
            if(subSubTypesString != "")
            {
               subTypesString = subTypesString + ("(" + subSubTypesString + ")");
            }
         }
         return subTypesString;
      }
      
      function findInstanceDestination(inst:Object) : ConcreteDataService
      {
         var cds:ConcreteDataService = null;
         if(this.metadata.itemClass != null && !(inst is this.metadata.itemClass))
         {
            return null;
         }
         var cl:Class = inst.constructor as Class;
         if(this.metadata.itemClass == cl)
         {
            return this;
         }
         if(this._classToSubDest == null)
         {
            return null;
         }
         for(var i:int = 0; i < this._subTypes.length; i++)
         {
            cds = ConcreteDataService(this._subTypes[i]);
            cds = cds.findInstanceDestination(inst);
            if(cds != null)
            {
               return cds;
            }
         }
         return null;
      }
      
      function isSubtypeOf(other:ConcreteDataService) : Boolean
      {
         var i:int = 0;
         if(other == this)
         {
            return true;
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               if(ConcreteDataService(this.extendsDestinations[i]).isSubtypeOf(other))
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      private function get rootDataService() : ConcreteDataService
      {
         if(this.extendsDestinations == null || this.extendsDestinations.length == 0)
         {
            return this;
         }
         var parentDataService:ConcreteDataService = this.extendsDestinations[0];
         return parentDataService.rootDataService;
      }
      
      private function addMaxFrequencyHeaderIfNecessary(msg:DataMessage) : void
      {
         if(this.maxFrequency > 0 && !this._maxFrequencySent)
         {
            this._maxFrequencySent = true;
            msg.headers[CommandMessage.MAX_FREQUENCY_HEADER] = this.maxFrequency;
         }
      }
      
      private function checkCacheId() : void
      {
         if(this.cacheID == null || this.cacheID.length == 0)
         {
            throw new DataServiceError("A cache identifier must be set before performing this operation.");
         }
      }
      
      private function countResultHandler(event:MessageEvent, token:AsyncToken) : void
      {
         this.dispatchResultEvent(event,token,event.message.body);
      }
      
      private function dataStorePropertyChangeHandler(event:PropertyChangeEvent) : void
      {
         if(event.property == "connected")
         {
            this._connecting = false;
            this._disconnectBarrier = false;
            if(!event.newValue)
            {
               this._shouldBeConnected = false;
               this.markSequencesAsStale();
               if(this._consumer.connected)
               {
                  return;
               }
            }
            else
            {
               if(this.metadata.autoSyncEnabled && !this._dataStore.channelSet.currentChannel.realtime)
               {
                  this._log.warn("{0} DataService is configured for auto-sync but has connected over a non-realtime channel, \'{1}\', and will not receive realtime data.",this.id,this._dataStore.channelSet.currentChannel.id);
               }
               this._shouldBeConnected = true;
               this.reconnectSequences();
               if(this._consumer.subscribed && this._consumer.channelSet != null && this._consumer.channelSet.currentChannel != null && this._consumer.channelSet.currentChannel is PollingChannel)
               {
                  PollingChannel(this._consumer.channelSet.currentChannel).enablePolling();
               }
            }
            dispatchEvent(event);
         }
         else if(event.property == "isInitialized")
         {
            dispatchEvent(event);
         }
      }
      
      private function consumerPropertyChangeHandler(event:PropertyChangeEvent) : void
      {
         if(event.property == "subscribed")
         {
            if(!event.newValue)
            {
               this.markSequencesAsStale();
            }
            this._manuallySubscribed = false;
            dispatchEvent(event);
         }
      }
      
      private function consumerFaultHandler(event:MessageFaultEvent) : void
      {
         this.dispatchFaultEvent(event,new AsyncToken(event.message));
      }
      
      private function dispatchCollectionEvent(colEvent:CollectionEvent) : void
      {
         var index:int = 0;
         var dataList:DataList = null;
         var i:uint = 0;
         var parentItem:IManaged = null;
         var property:String = null;
         var changeEvent:PropertyChangeEvent = colEvent.items[0];
         var uid:String = IManaged(changeEvent.target).uid;
         var dls:Array = this.getDataListsForUID(uid);
         if(dls != null)
         {
            dls = !_indexReferences?dls:this.shallowCopyArray(dls);
            for(i = 0; i < dls.length; i++)
            {
               dataList = DataList(dls[i]);
               index = dataList.getUIDIndex(uid);
               if(index > -1)
               {
                  dataList.dispatchEvent(colEvent);
                  if(dataList.association != null && dataList.association.hierarchicalEvents)
                  {
                     parentItem = dataList.parentItem as IManaged;
                     if(parentItem.hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE))
                     {
                        if(!Managed.reachableFrom(parentItem,changeEvent.property,changeEvent.target))
                        {
                           if(dataList.association.typeCode == ManagedAssociation.MANY)
                           {
                              property = dataList.association.property + "." + index;
                           }
                           else
                           {
                              property = dataList.association.property;
                           }
                           if(Log.isDebug())
                           {
                              this._log.debug("Sending hierarchical PropertyChangeEvent: destination: {0}, property: {1}, oldValue: {2}, newValue: {3}",dataList.parentDataService.destination,property + "." + changeEvent.property,this.itemToIdString(changeEvent.oldValue),this.itemToIdString(changeEvent.newValue));
                           }
                           parentItem.dispatchEvent(Managed.createUpdateEvent(parentItem as IManaged,property,changeEvent));
                        }
                        else if(Log.isDebug())
                        {
                           this._log.debug("Not sending hierarchical PropertyChangeEvent for association: " + dataList.association.property + " of item: " + itemToString(parentItem) + " as this item was already found in the property expression: " + changeEvent.property + " from the event target: " + itemToString(changeEvent.target));
                        }
                     }
                  }
               }
            }
         }
      }
      
      private function markSequencesAsStale() : void
      {
         var dataList:DataList = null;
         for(var i:int = 0; i < this._dataLists.length; i++)
         {
            dataList = DataList(this._dataLists.getItemAt(i));
            if(dataList.sequenceId >= 0)
            {
               if(!dataList.sequenceIdStale)
               {
                  dataList.sequenceIdStale = true;
                  this.staleSequencesCount++;
               }
            }
            if(dataList.sequenceAutoSubscribed)
            {
               dataList.sequenceAutoSubscribed = false;
               this._autoSyncCount--;
            }
         }
      }
      
      function getChangedProperties(item:Object, orgItem:Object, ps:PropertySpecifier, excludes:Array, referencedIds:Object, orgReferencedIds:Object) : Array
      {
         var includes:Array = null;
         var changes:Array = null;
         var prop:String = null;
         var md:Metadata = null;
         var assoc:ManagedAssociation = null;
         var diff:Boolean = false;
         if(ps.includeMode != PropertySpecifier.INCLUDE_LIST)
         {
            includes = getObjectProperties(item);
         }
         else
         {
            includes = ps.extraProperties;
         }
         for(var i:int = 0; i < includes.length; i++)
         {
            prop = includes[i];
            if(!(!ps.includeProperty(prop) || excludes != null && ArrayUtil.getItemIndex(prop,excludes) != -1))
            {
               md = this.getItemMetadata(item);
               assoc = ManagedAssociation(md.associations[prop]);
               if(assoc == null)
               {
                  diff = Managed.compare(item[prop],orgItem[prop],-1,["uid"]) != 0;
               }
               else if(assoc.lazy)
               {
                  diff = !assoc.service.metadata.compareReferencedIds(referencedIds[prop],orgReferencedIds[prop]);
               }
               else
               {
                  diff = !md.compareReferencedIdsForAssoc(assoc,item[prop],orgReferencedIds[prop]);
               }
               if(diff)
               {
                  if(changes == null)
                  {
                     changes = [];
                  }
                  changes.push(prop);
               }
            }
         }
         return changes;
      }
      
      function getAllDataLists(uid:String, exitOnFirst:Boolean = false, includeSuperTypes:Boolean = true) : Array
      {
         var dataList:DataList = null;
         var dls:Array = null;
         var i:int = 0;
         var newResult:Array = null;
         var result:Array = null;
         if(_indexReferences)
         {
            dls = this._itemDataListIndex[uid];
         }
         else
         {
            dls = this._dataLists.toArray();
         }
         if(dls != null)
         {
            for(i = 0; i < dls.length; i++)
            {
               dataList = DataList(dls[i]);
               if(dataList.referenceCount == 0)
               {
                  throw new DataServiceError("DataList with no references found in the index.  destination: " + this.destination + " uid: " + uid + " list: " + itemToString(dataList.collectionId));
               }
               if(_indexReferences || dataList.getUIDIndex(uid) != -1)
               {
                  if(result == null)
                  {
                     result = [];
                  }
                  result.push(dataList);
                  if(exitOnFirst)
                  {
                     return result;
                  }
               }
            }
         }
         if(includeSuperTypes && this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               newResult = ConcreteDataService(this.extendsDestinations[i]).getAllDataLists(uid,exitOnFirst);
               if(newResult != null)
               {
                  if(exitOnFirst)
                  {
                     return newResult;
                  }
                  if(result == null)
                  {
                     result = newResult;
                  }
                  else
                  {
                     result.concat(newResult);
                  }
               }
            }
         }
         return result;
      }
      
      private function getFailedInitializationFault(details:String) : MessageFaultEvent
      {
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = "Client.Initialization.Failed";
         errMsg.faultString = "Could not initialize DataService.";
         errMsg.faultDetail = details;
         var msgFaultEvent:MessageFaultEvent = MessageFaultEvent.createEvent(errMsg);
         return msgFaultEvent;
      }
      
      function getLocalChange(uid:String, item:Object) : IChangeObject
      {
         var result:IChangeObject = null;
         var dmsg:DataMessage = this.dataStore.messageCache.getOldestMessage(this,uid);
         if(dmsg != null)
         {
            result = new ChangeObject(dmsg,item,this);
         }
         return result;
      }
      
      private function getUncommittedUpdateCollections(collectionId:Object, identity:Object) : Array
      {
         return this.dataStore.messageCache.getUncommittedUpdateCollections(this.destination,collectionId,identity);
      }
      
      private function getPendingMessages(uid:String) : Array
      {
         return this.dataStore.messageCache.getPendingMessages(this,uid,false);
      }
      
      private function getSMODataList(value:IManaged) : DataList
      {
         var lists:Array = null;
         var i:int = 0;
         var result:DataList = null;
         if(value != null)
         {
            lists = this.getAllDataLists(value.uid,false,false);
            if(lists)
            {
               for(i = 0; i < lists.length; i++)
               {
                  result = DataList(lists[i]);
                  if(result.smo)
                  {
                     return result;
                  }
               }
            }
         }
         return null;
      }
      
      private function getUncommittedMessages(uid:String = null) : Array
      {
         return this.dataStore.messageCache.getUncommittedMessages(this,uid);
      }
      
      private function internalCount(token:AsyncToken) : void
      {
         var errMsg:ErrorMessage = null;
         var event:MessageFaultEvent = null;
         this.reconnect();
         if(this.autoConnect || this.connected)
         {
            this.dataStore.count(token.message,new AsyncResponder(this.countResultHandler,this.dispatchFaultEvent,token),token);
         }
         else
         {
            errMsg = new ErrorMessage();
            errMsg.faultCode = "Client.Connect.Failed";
            errMsg.faultDetail = "Connect to remote destination failed during count()";
            errMsg.faultString = "error";
            event = MessageFaultEvent.createEvent(errMsg);
            this.asyncDispatchFaultEvent(event,token);
         }
      }
      
      private function internalCreateItem(item:Object, token:ItemReference) : void
      {
         var msg:DataMessage = null;
         var event:MessageEvent = null;
         var error:ErrorMessage = null;
         var fault:MessageFaultEvent = null;
         this.reconnect();
         var addItemResult:Object = this.addItem(item,DataMessage.CREATE_AND_SEQUENCE_OPERATION,false,true);
         if(addItemResult.added)
         {
            if(addItemResult.message == null)
            {
               msg = new DataMessage();
               msg.operation = DataMessage.CREATE_OPERATION;
               msg.body = item;
               this.addMaxFrequencyHeaderIfNecessary(msg);
               token.setMessage(msg);
               event = MessageEvent.createEvent(MessageEvent.RESULT,msg);
               new AsyncDispatcher(this.dispatchResultEvent,[event,token,item],10);
            }
            else
            {
               this.dataStore.doAutoCommit(CreateItemCommitResponder,false,false,token);
               token.setMessage(addItemResult.message);
            }
         }
         else
         {
            error = this.createLocalCallError(resourceManager.getString("data","itemAlreadyExists",[addItemResult.uid,this.destination]));
            fault = MessageFaultEvent.createEvent(error);
            token.setMessage(error);
            token.invalid = true;
            this.asyncDispatchFaultEvent(fault,token,this.getIdentityMap(item));
         }
      }
      
      private function internalFill(view:ListCollectionView, includeSpecifier:PropertySpecifier, args:Array, token:AsyncToken, singleResult:Boolean, localFill:Boolean) : void
      {
         this.reconnect();
         var dataList:DataList = null;
         if(args == null)
         {
            args = [];
         }
         if(view.list is DataList)
         {
            dataList = DataList(view.list);
            if(this._dataLists.getItemIndex(dataList) == -1 && dataList.referenceCount > 0)
            {
               throw new DataServiceError(resourceManager.getString("data","collectionManagedByAnother"));
            }
            if(dataList.referenceCount == 0 || Managed.compare(dataList.fillParameters,args,-1,["uid"]) != 0)
            {
               if(dataList.referenceCount > 0)
               {
                  this.releaseDataList(dataList,false,false,null,null,true,false);
               }
               dataList = null;
            }
         }
         if(dataList == null)
         {
            dataList = this.getDataListWithFillParams(args);
            if(dataList == null)
            {
               dataList = new DataList(this);
               dataList.singleResult = singleResult;
            }
            else
            {
               if(dataList.singleResult != singleResult)
               {
                  throw new ArgumentError("findItem and fill used with the same fill parameters: " + itemToString(dataList.fillParameters));
               }
               dataList.referenceCount++;
            }
            view.list = dataList;
         }
         if(dataList.referenceCount <= 1)
         {
            dataList.fillParameters = this.copyFillArgs(args);
         }
         dataList.view = view;
         var fillMsg:DataMessage = this.createFillMessage(dataList,!this.resetCollectionOnFill,singleResult);
         if(includeSpecifier != this.includeDefaultSpecifier)
         {
            fillMsg.headers.DSincludeSpec = includeSpecifier.includeSpecifierString;
         }
         token.setMessage(fillMsg);
         token.dataMessage = fillMsg;
         this.dataStore.fill(dataList,this,fillMsg,this.createDLResponder(dataList,token),token,localFill);
      }
      
      private function internalSyncFill(fillArgs:Array, token:AsyncToken) : void
      {
         this.reconnect();
         if(!fillArgs)
         {
            fillArgs = [];
         }
         var lastFillTimestamp:Date = null;
         var dataList:DataList = this.getDataListWithFillParams(fillArgs);
         if(!dataList)
         {
            fillArgs = this.copyFillArgs(fillArgs);
         }
         else
         {
            lastFillTimestamp = dataList.fillTimestamp;
            fillArgs = dataList.fillParameters as Array;
            dataList.ensureSynchronizeSupported();
         }
         var syncMsg:DataMessage = this.createSynchronizeFillMessage(lastFillTimestamp,fillArgs);
         token.setMessage(syncMsg);
         var responder:IResponder = new AsyncTokenResponder(this.onSyncResult,this.reportSyncError,token);
         this.dataStore.invoke(syncMsg,responder);
      }
      
      private function onSyncResult(result:Object, token:AsyncToken) : void
      {
         var changedItems:ChangedItems = null;
         var applyResult:Function = null;
         var error:ErrorMessage = null;
         var fault:MessageFaultEvent = null;
         var applyToken:AsyncToken = null;
         var applyResponder:IResponder = null;
         applyResult = function(event:ResultEvent, subToken:AsyncToken):void
         {
            dispatchResultEvent(event,token,changedItems);
         };
         var event:MessageEvent = MessageEvent(result);
         changedItems = event.message.body as ChangedItems;
         if(!changedItems)
         {
            error = new ErrorMessage();
            error.faultCode = "SyncResult.Type.Mismatch";
            error.faultString = "result is not a ChangedItem instance";
            error.faultDetail = getQualifiedClassName(event.message.body);
            fault = MessageFaultEvent.createEvent(error);
            token.setMessage(error);
            this.dispatchFaultEvent(fault,token);
         }
         else
         {
            applyToken = this.applyChangedItems(changedItems);
            applyResponder = new AsyncTokenResponder(applyResult,this.reportSyncError,token);
            applyToken.addResponder(applyResponder);
         }
      }
      
      private function reportSyncError(faultEventObj:Object, token:AsyncToken = null) : void
      {
         this.log.error("synchronizeFill error: " + faultEventObj);
         var faultEvent:FaultEvent = faultEventObj as FaultEvent;
         var msgFaultEvent:MessageFaultEvent = faultEventObj as MessageFaultEvent;
         if(msgFaultEvent)
         {
            faultEvent = FaultEvent.createEventFromMessageFault(msgFaultEvent);
         }
         if(faultEvent)
         {
            dispatchEvent(faultEvent);
            if(token)
            {
               token.applyFault(faultEvent);
            }
         }
      }
      
      private function copyFillArgs(fillArgs:Array) : Array
      {
         var fillArg:Object = null;
         var copiedFillArg:Object = null;
         var cds:ConcreteDataService = null;
         var copiedFillArgs:Array = [];
         if(fillArgs)
         {
            for each(fillArg in fillArgs)
            {
               if(fillArg is IManaged)
               {
                  cds = this;
                  try
                  {
                     cds = this.dataStore.getDataServiceForValue(fillArg);
                  }
                  catch(dse:DataServiceError)
                  {
                  }
                  copiedFillArg = cds.copyItem(fillArg);
               }
               else
               {
                  copiedFillArg = ObjectUtil.copy(fillArg);
               }
               copiedFillArgs.push(copiedFillArg);
            }
         }
         return copiedFillArgs;
      }
      
      private function internalGetItem(identity:Object, defaultValue:Object, token:ItemReference) : void
      {
         var error:ErrorMessage = null;
         var msg:DataMessage = null;
         var dataList:DataList = null;
         var fault:MessageFaultEvent = null;
         error = this.checkIdentitySpecified(identity);
         if(error == null)
         {
            if(defaultValue != null)
            {
               if(!(defaultValue is IManaged) && defaultValue.constructor != Object)
               {
                  error = this.createLocalCallError(resourceManager.getString("data","defaultValueNotIManaged"));
               }
            }
         }
         if(error == null)
         {
            this.reconnect();
            if(defaultValue != null)
            {
               msg = this.createMessage(identity,DataMessage.GET_OR_CREATE_OPERATION);
               msg.body = DataMessage.wrapItem(defaultValue,this.destination);
               msg.headers.referencedIds = this.getItemMetadata(defaultValue).getReferencedIds(defaultValue);
            }
            else
            {
               msg = this.createMessage(identity,DataMessage.GET_OPERATION);
               msg.body = null;
            }
            if(this.autoSyncEnabled)
            {
               this.addAssociationClientIdsToMessage(msg);
            }
            token.setMessage(msg);
            dataList = new DataList(this);
            dataList.fillParameters = this.getIdentityMap(identity);
            dataList.itemReference = token;
            dataList.smo = true;
            this.dataStore.fill(dataList,this,msg,this.createDLResponder(dataList,token),token);
         }
         else
         {
            fault = MessageFaultEvent.createEvent(error);
            token.setMessage(error);
            token.invalid = true;
            this.asyncDispatchFaultEvent(fault,token);
         }
      }
      
      private function internalRelease(clear:Boolean = true, copyStillManagedItems:Boolean = true) : void
      {
         var removedAny:Boolean = false;
         var i:int = 0;
         var dataList:DataList = null;
         var item:IManaged = null;
         if(this._releaseBarrier)
         {
            return;
         }
         this._releaseBarrier = true;
         try
         {
            disablePaging();
            do
            {
               removedAny = false;
               for(i = 0; i < this._dataLists.length; i++)
               {
                  dataList = DataList(this._dataLists.getItemAt(i));
                  dataList.referenceCount = 1 + dataList.updateCollectionReferences;
                  if(dataList.smo)
                  {
                     item = dataList.getItemAt(0) as IManaged;
                     if(item != null)
                     {
                        if(this.releaseItem(item) != null)
                        {
                           removedAny = true;
                        }
                     }
                     else if(Log.isWarn())
                     {
                        this._log.warn("{0} DataService.release() encountered a null single managed object to release that does not implement IManaged. This item will be ignored.",this.id);
                     }
                  }
                  else if(dataList.view != null)
                  {
                     if(dataList.view.list == dataList && dataList.fillParameters != null)
                     {
                        this.releaseCollection(dataList.view,clear,copyStillManagedItems);
                        removedAny = true;
                     }
                  }
               }
            }
            while(removedAny);
            
         }
         finally
         {
            this._releaseBarrier = false;
            enablePaging();
         }
      }
      
      private function internalReleaseItem(item:IManaged, clearAssociatedMessages:Boolean = true, clearCreateMessages:Boolean = false, trackItem:Boolean = false) : void
      {
         var messages:Array = null;
         var message:DataMessage = null;
         var ucMsgs:Array = null;
         var ucMsg:UpdateCollectionMessage = null;
         var i:int = 0;
         var j:int = 0;
         if(Log.isDebug())
         {
            this._log.debug((!!trackItem?"Releasing item reference ":"Deleting item ") + item.uid);
         }
         if(trackItem)
         {
            this._releasedItems[item] = true;
            if(this._releasedUIDs == null)
            {
               this._releasedUIDs = new Object();
            }
            this._releasedUIDs[item.uid] = true;
         }
         this.removeItemFromCache(item.uid);
         if(!trackItem)
         {
            this.removeChangeListener(item);
         }
         if(clearAssociatedMessages || clearCreateMessages)
         {
            messages = this.getUncommittedMessages(item.uid);
            for(i = 0; i < messages.length; i++)
            {
               message = DataMessage(messages[i]);
               if(!(clearCreateMessages && !message.isCreate()))
               {
                  this.dataStore.messageCache.removeMessage(message);
                  ucMsgs = this.getUncommittedUpdateCollections(null,message.identity);
                  for(j = 0; j < ucMsgs.length; j++)
                  {
                     ucMsg = UpdateCollectionMessage(ucMsgs[j]);
                     ucMsg.removeRanges(ucMsg.getRangeInfoForIdentity(message.identity));
                     if(ucMsg.body == null)
                     {
                        this.dataStore.messageCache.removeMessage(ucMsg);
                     }
                  }
               }
            }
         }
         this.dataStore.removeConflicts(this,item);
      }
      
      private function internalUpdateCache(newUID:String, cacheItem:IManaged, item:Object) : void
      {
         var leafDS:ConcreteDataService = null;
         this.disableLogging();
         try
         {
            if(cacheItem == null)
            {
               var cacheItem:IManaged = this.normalize(item);
               leafDS = this.getItemDestination(cacheItem);
               leafDS.addChangeListener(cacheItem);
               leafDS.putItemInCache(newUID,cacheItem);
               if(Log.isDebug())
               {
                  this._log.debug("Adding item to cache: " + newUID + " destination: " + this.destination);
               }
            }
            cacheItem.uid = newUID;
         }
         finally
         {
            this.enableLogging();
         }
      }
      
      private function itemUpdateHandler(event:PropertyChangeEvent) : void
      {
         var colEvent:CollectionEvent = null;
         var topLevelProperty:String = null;
         var association:ManagedAssociation = null;
         var changeEvent:PropertyChangeEvent = null;
         var uid:String = null;
         if(this.dataStore.logChanges == 0)
         {
            if(Log.isDebug())
            {
               this._log.debug("Received PropertyChangeEvent: destination: {0}, property: {1}, oldValue: {2}, newValue: {3}",this.destination,event.property,this.itemToIdString(event.oldValue),this.itemToIdString(event.newValue));
            }
            topLevelProperty = event.property.toString();
            if(topLevelProperty.indexOf(".") != -1)
            {
               topLevelProperty = topLevelProperty.split(".")[0];
            }
            association = this.getItemMetadata(event.target).associations[topLevelProperty];
            if(association != null)
            {
               if(event.target == event.source)
               {
                  this.updateAssociation(association,event);
               }
            }
            else
            {
               this.dataStore.logUpdate(this,event.target,event.property,event.oldValue,event.newValue,null,event.target != event.source,null);
            }
            if(this.dataStore.autoCommitPropertyChanges)
            {
               this.dataStore.doAutoCommit(CommitResponder);
            }
         }
         colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         colEvent.kind = CollectionEventKind.UPDATE;
         colEvent.items.push(event);
         if(this._delayedCollectionEvents)
         {
            changeEvent = colEvent.items[0];
            uid = IManaged(changeEvent.target).uid;
            if(this.getDataListsForUID(uid) != null)
            {
               if(this._pendingCollectionEvents == null)
               {
                  this._pendingCollectionEvents = new Array();
               }
               this._pendingCollectionEvents.push(colEvent);
            }
         }
         else
         {
            this.dispatchLeafCollectionEvent(colEvent);
         }
      }
      
      private function dispatchLeafCollectionEvent(colEvent:CollectionEvent) : void
      {
         var i:int = 0;
         this.dispatchCollectionEvent(colEvent);
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).dispatchLeafCollectionEvent(colEvent);
            }
         }
      }
      
      private function loadDataStoreProperties() : void
      {
         if(!this._defaultAutoCommit)
         {
            this._dataStore.autoCommit = this._defaultAutoCommit;
         }
         if(!this._defaultAutoConnect)
         {
            this._dataStore.autoConnect = this._defaultAutoConnect;
         }
         if(!this._defaultAutoMerge)
         {
            this._dataStore.autoMerge = this._defaultAutoMerge;
         }
         if(this._defaultAutoSaveCache)
         {
            this._dataStore.autoSaveCache = this._defaultAutoSaveCache;
         }
      }
      
      private function manageNewItem(item:Object) : Object
      {
         var uid:String = null;
         var newMsg:DataMessage = null;
         uid = this.metadata.getUID(item);
         if(this._itemCache[uid] == null)
         {
            newMsg = this.dataStore.messageCache.getCreateMessage(this,item);
            if(newMsg != null)
            {
               return this._itemCache[newMsg.messageId];
            }
            this.addItem(item,DataMessage.CREATE_OPERATION,true,true);
            if(this._itemCache[uid] != null)
            {
               item = this._itemCache[uid];
            }
         }
         return item;
      }
      
      private function mergeCreate(msg:DataMessage) : void
      {
         var item:Object = null;
         var leafDS:ConcreteDataService = null;
         var uid:String = null;
         var localChange:IChangeObject = null;
         var remoteChange:IChangeObject = null;
         var conflict:DataErrorMessage = null;
         item = msg.unwrapBody();
         leafDS = this.getItemDestination(item);
         if(leafDS != this)
         {
            leafDS.mergeCreate(msg);
            return;
         }
         uid = this.metadata.getUID(item);
         if(uid.length > 0)
         {
            if(Log.isDebug())
            {
               this._log.debug("Merging create for destination: {0}\n  {1}",this.destination,msg.toString());
            }
            localChange = this.getLocalChange(uid,null);
            remoteChange = new ChangeObject(msg,item,this);
            this.conflictDetector.checkCreate(remoteChange,localChange);
            conflict = remoteChange.getConflict();
            if(conflict == null)
            {
               if(this._itemCache[uid] == null)
               {
                  this.addItem(item);
                  item = this._itemCache[uid];
                  this.getItemMetadata(item).configureItem(this,item,item,this.getOperationPropertySpecifier(msg),msg.headers.sequenceProxy,msg.headers.referencedIds,false,false);
                  this.queueReferenceCheck(IManaged(item),getTimer() + this.KEEP_REFERENCE_INTERVAL);
               }
               else if(this.getItemMetadata(item).needsReferencedIds)
               {
                  item = this.normalize(item);
                  item.referencedIds = msg.headers.referencedIds;
               }
            }
            else
            {
               this.dataStore.processConflict(this,conflict,null);
            }
         }
         else if(Log.isError())
         {
            this._log.error("Received CREATE message for destination: {0} with an item who\'s uid is empty!\n{1}",this.destination,msg);
         }
      }
      
      private function mergeDelete(msg:DataMessage) : void
      {
         var uid:String = null;
         var item:IManaged = null;
         var leafDS:ConcreteDataService = null;
         var localChange:IChangeObject = null;
         var remoteChange:IChangeObject = null;
         var conflict:DataErrorMessage = null;
         uid = this.metadata.getUID(msg.identity);
         item = IManaged(this.getItemForReference(uid));
         leafDS = this.getItemDestination(item);
         if(leafDS != this)
         {
            leafDS.mergeDelete(msg);
            return;
         }
         if(Log.isDebug())
         {
            this._log.debug("Merging delete for destination: {0} message:\n  {1}",this.destination,msg.toString());
         }
         if(item != null)
         {
            localChange = this.getLocalChange(uid,item);
            remoteChange = new ChangeObject(msg,item,this);
            this.conflictDetector.checkDelete(remoteChange,localChange);
            conflict = remoteChange.getConflict();
            if(conflict == null)
            {
               this.removeItem(uid,false,true);
            }
            else
            {
               conflict.serverObject = null;
               this.dataStore.processConflict(this,conflict,null);
            }
         }
         else
         {
            this.removeReferencesToUID(uid);
         }
      }
      
      private function removeReferencesToUID(uid:String) : void
      {
         var dataList:DataList = null;
         var dls:Array = null;
         var i:uint = 0;
         dls = this.getDataListsForUID(uid);
         if(dls != null)
         {
            dls = this.shallowCopyArray(dls);
            for(i = 0; i < dls.length; i++)
            {
               dataList = DataList(dls[i]);
               if(dataList.removeReference(uid,true) != -1 && dataList.smo && dataList.itemReference != null)
               {
                  dataList.itemReference.setResult(null);
               }
            }
         }
         if(this.extendsDestinations != null)
         {
            for(i = 0; i < this.extendsDestinations.length; i++)
            {
               ConcreteDataService(this.extendsDestinations[i]).removeReferencesToUID(uid);
            }
         }
      }
      
      private function mergeUpdate(msg:DataMessage) : void
      {
         var uid:String = null;
         var item:IManaged = null;
         var leafDS:ConcreteDataService = null;
         var remoteChange:IChangeObject = null;
         var localChange:IChangeObject = null;
         var conflict:DataErrorMessage = null;
         var origItem:Object = null;
         var origReferencedIds:Object = null;
         uid = this.metadata.getUID(msg.identity);
         item = IManaged(this.getItemForReference(uid,false));
         leafDS = this.getItemDestination(item);
         if(leafDS != this)
         {
            leafDS.mergeUpdate(msg);
            return;
         }
         remoteChange = new ChangeObject(msg,item,this);
         localChange = this.getLocalChange(uid,item);
         if(Log.isDebug())
         {
            this._log.debug("Merging update for destination: {0} message:\n  {1}",this.destination,msg.toString());
            if(item == null)
            {
               this._log.debug("No item in cache with uid: " + uid);
            }
         }
         this.conflictDetector.checkUpdate(remoteChange,localChange);
         conflict = remoteChange.getConflict();
         if(conflict == null)
         {
            if(item != null)
            {
               origItem = null;
               origReferencedIds = null;
               if(localChange != null)
               {
                  if(localChange.isUpdate())
                  {
                     origItem = localChange.previousVersion;
                     origReferencedIds = DataMessage.unwrapItem(localChange.message.headers.prevReferencedIds);
                  }
                  else if(localChange.isDelete())
                  {
                     origItem = localChange.previousVersion;
                     origReferencedIds = DataMessage.unwrapItem(localChange.message.headers.referencedIds);
                  }
               }
               this.updateMergedItem(remoteChange.changedPropertyNames,origReferencedIds,item,remoteChange.newVersion,origItem,DataMessage.unwrapItem(msg.headers.newReferencedIds));
               if(localChange != null)
               {
                  if(localChange.isUpdate())
                  {
                     localChange.message.body[DataMessage.UPDATE_BODY_NEW] = DataMessage.wrapItem(this.copyItem(item),this.destination);
                  }
                  else if(localChange.isCreate() || localChange.isDelete())
                  {
                     localChange.message.body = this.copyItem(item);
                  }
               }
            }
         }
         else
         {
            this.dataStore.processConflict(this,conflict,null);
         }
      }
      
      private function messageHandler(event:MessageEvent) : void
      {
         var msg:DataMessage = null;
         msg = DataMessage(event.message);
         this.processPushMessage(msg);
         dispatchEvent(event);
      }
      
      function processPushMessage(msg:DataMessage) : void
      {
         if(!this.dataStore.autoMerge)
         {
            if(Log.isDebug())
            {
               this._log.debug("Adding unmerged message for destination: {0} autoMerge: {1} message:\n  {2}",this.destination,this.dataStore.autoMerge,msg);
            }
            this.dataStore.addUnmergedMessage(this,msg);
         }
         else
         {
            this.mergeMessage(msg);
         }
      }
      
      private function reconnectSequences() : void
      {
         var staleReferences:Object = null;
         var tokens:Array = null;
         var i:int = 0;
         var dataList:DataList = null;
         var msg:DataMessage = null;
         var token:AsyncToken = null;
         var lastToken:AsyncToken = null;
         var resultToken:AsyncToken = null;
         if(!this.staleSequencesCount || this._reconnecting)
         {
            return;
         }
         staleReferences = new Object();
         tokens = new Array();
         this.clientIdsAdded = false;
         this._reconnecting = true;
         try
         {
            for(i = 0; i < this._dataLists.length; i++)
            {
               dataList = DataList(this._dataLists.getItemAt(i));
               if(dataList.sequenceIdStale)
               {
                  if(dataList.association == null || dataList.association.paged || dataList.association.loadOnDemand)
                  {
                     if(this.metadata.reconnectPolicy == Metadata.FETCH_IDENTITY)
                     {
                        if(dataList.pagingEnabled)
                        {
                           dataList.requestItemAt(0,dataList.length,null,true,tokens,staleReferences);
                        }
                        else if(dataList.association == null)
                        {
                           msg = new DataMessage();
                           msg.destination = this.destination;
                           msg.operation = DataMessage.GET_SEQUENCE_ID_OPERATION;
                           msg.clientId = this._consumer.clientId;
                           if(dataList.smo)
                           {
                              msg.identity = dataList.fillParameters;
                           }
                           else
                           {
                              msg.body = dataList.collectionId;
                           }
                           msg.headers.pageSize = dataList.pagedInSize;
                           this.addAssociationClientIdsToMessage(msg);
                           token = new AsyncToken(msg);
                           this.dataStore.invoke(msg,this.createDLResponder(dataList,token));
                           tokens.push(token);
                        }
                     }
                     else if(this.metadata.reconnectPolicy == Metadata.FETCH_INSTANCE)
                     {
                        this.refreshDataList(dataList,tokens,staleReferences);
                     }
                  }
                  else
                  {
                     dataList.sequenceIdStale = false;
                     dataList.service.staleSequencesCount--;
                     if(dataList.association != null && dataList.association.lazy)
                     {
                        this.refreshDataList(dataList,tokens,staleReferences);
                     }
                  }
               }
            }
         }
         catch(e:Error)
         {
            _reconnecting = false;
            throw e;
         }
         if(tokens.length > 0)
         {
            lastToken = tokens[tokens.length - 1];
            resultToken = new AsyncToken(null);
            resultToken.staleReferences = staleReferences;
            lastToken.addResponder(new AsyncResponder(this.doRefreshStaleReferences,this.sendRefreshFault,resultToken));
            return;
         }
         this._reconnecting = false;
         this.refreshStaleReferences(staleReferences,tokens);
      }
      
      private function refreshDataList(dataList:DataList, tokens:Array, staleReferences:Object = null) : void
      {
         var msg:DataMessage = null;
         var token:AsyncToken = null;
         if(tokens == null)
         {
            tokens = [];
         }
         if(dataList.smo)
         {
            msg = this.createMessage(dataList.fillParameters,DataMessage.GET_OPERATION);
         }
         else
         {
            if(dataList.pagingEnabled || dataList.association != null)
            {
               if(dataList.fetched)
               {
                  dataList.requestItemAt(0,dataList.length,null,true,tokens,staleReferences);
               }
               return;
            }
            msg = this.createFillMessage(dataList,true,dataList.singleResult);
         }
         msg.clientId = this._consumer.clientId;
         token = new AsyncToken(msg);
         this.dataStore.invoke(msg,this.createDLResponder(dataList,token));
         tokens.push(token);
      }
      
      private function releaseUncommittedDeletes(dataList:DataList) : void
      {
         var messages:Array = null;
         var message:DataMessage = null;
         var ucMsgs:Array = null;
         var ucMsg:UpdateCollectionMessage = null;
         var i:int = 0;
         if(dataList.referenceCount < dataList.updateCollectionReferences && Log.isError())
         {
            this._log.error("Update collection reference count is out of sync with data list ref cnt!");
         }
         if(dataList.referenceCount == dataList.updateCollectionReferences && dataList.association == null)
         {
            messages = this.getUncommittedMessages();
            for(i = 0; i < messages.length; i++)
            {
               message = DataMessage(messages[i]);
               if(message.operation == DataMessage.DELETE_OPERATION)
               {
                  ucMsgs = this.getUncommittedUpdateCollections(null,message.identity);
                  if(ucMsgs.length == 1)
                  {
                     ucMsg = UpdateCollectionMessage(ucMsgs[0]);
                     if(Managed.compare(ucMsg.collectionId,dataList.collectionId,-1,["uid"]) == 0)
                     {
                        this.dataStore.messageCache.removeMessage(message);
                        ucMsg.removeRanges(ucMsg.getRangeInfoForIdentity(message.identity));
                        if(ucMsg.body == null)
                        {
                           this.dataStore.messageCache.removeMessage(ucMsg);
                        }
                     }
                  }
               }
            }
         }
      }
      
      private function releaseUncommittedCreates(dataList:DataList) : void
      {
         var messages:Array = null;
         var message:DataMessage = null;
         var i:int = 0;
         var ucMsgs:Array = null;
         var j:int = 0;
         var ucMsg:UpdateCollectionMessage = null;
         if(dataList.referenceCount < dataList.updateCollectionReferences && Log.isError())
         {
            this._log.error("Update collection reference count is out of sync with data list ref cnt!");
         }
         if(dataList.referenceCount == dataList.updateCollectionReferences && dataList.association == null)
         {
            messages = this.getUncommittedMessages();
            for(i = 0; i < messages.length; i++)
            {
               message = DataMessage(messages[i]);
               if(message.operation == DataMessage.CREATE_OPERATION)
               {
                  ucMsgs = this.getUncommittedUpdateCollections(dataList.collectionId,null);
                  for(j = 0; j < ucMsgs.length; j++)
                  {
                     ucMsg = UpdateCollectionMessage(ucMsgs[j]);
                     if(Managed.compare(ucMsg.collectionId,dataList.collectionId,-1,["uid"]) == 0 && (ucMsg.body == null || ucMsg.body.length == 0 || ucMsg.body[0].updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION))
                     {
                        this.dataStore.messageCache.removeMessage(ucMsg);
                     }
                  }
                  this.dataStore.messageCache.removeMessage(message);
               }
            }
         }
      }
      
      private function removeAllHandler(data:Object, token:Object) : void
      {
         DataList(token).removeAll();
      }
      
      private function removeChangeListener(item:IManaged) : void
      {
         if(item)
         {
            item.removeEventListener(PropertyChangeEvent.PROPERTY_CHANGE,this.itemUpdateHandler);
         }
      }
      
      private function updateAssociation(association:ManagedAssociation, event:PropertyChangeEvent) : void
      {
         var updateLogged:Boolean = false;
         var oldItemOrId:Object = null;
         var newItemOrId:Object = null;
         var childSequence:DataList = null;
         var newerValue:Object = null;
         var childMessage:DataMessage = null;
         var theList:IList = null;
         var dataList:DataList = null;
         updateLogged = false;
         if(association.typeCode == ManagedAssociation.ONE)
         {
            childSequence = this.getDataListForAssociation(event.target,association);
            if(event.oldValue != null)
            {
               if(childSequence != null && childSequence.fetched && childSequence.length == 1)
               {
                  childSequence.removeAllItemReferences();
               }
               if(event.oldValue is IManaged)
               {
                  association.service.releaseItemIfNoDataListReferences(IManaged(event.oldValue));
               }
            }
            if(event.oldValue == null)
            {
               oldItemOrId = null;
            }
            else
            {
               oldItemOrId = association.service.getItemIdentifier(event.oldValue);
            }
            if(event.newValue == null)
            {
               newItemOrId = null;
            }
            if(event.newValue != null)
            {
               newerValue = association.service.manageNewItem(event.newValue);
               if(newerValue !== event.newValue)
               {
                  event.target[event.property] = newerValue;
               }
               newItemOrId = association.service.getItemIdentifier(event.newValue);
               childMessage = this.dataStore.messageCache.getLastUncommittedMessage(association.service,IManaged(newerValue).uid);
               if(childMessage != null && (childMessage.operation != DataMessage.CREATE_OPERATION && childMessage.operation != DataMessage.CREATE_AND_SEQUENCE_OPERATION))
               {
                  childMessage = null;
               }
               this.dataStore.logUpdate(this,event.target,event.property,oldItemOrId,newItemOrId,childMessage,false,association);
               updateLogged = true;
               if(childSequence != null)
               {
                  childSequence.setOneReference(IManaged(newerValue).uid);
               }
            }
            if(!updateLogged)
            {
               this.dataStore.logUpdate(this,event.target,event.property,oldItemOrId,newItemOrId,null,false,association);
            }
         }
         else
         {
            if(event.oldValue != null && event.oldValue != event.newValue)
            {
               throw new DataServiceError(resourceManager.getString("data","cannotModifyManagedCollection",[association.property,itemToString(event.target)]));
            }
            if(event.newValue is ListCollectionView)
            {
               theList = ListCollectionView(event.newValue).list;
               if(theList is DataList)
               {
                  dataList = DataList(theList);
                  if(dataList.parentDataService != this || dataList.association == null || dataList.association.property != event.property || !equalItems(dataList.parentItem,event.target))
                  {
                     throw new DataServiceError("Attempt to assign one managed association collection for property: " + event.property + " on item: " + itemToString(event.target) + " This collection is already managed by " + (dataList.parentItem == null?" by the fill with parameters " + itemToString(dataList.fillParameters):" by association property on item: " + itemToString(dataList.parentItem)));
                  }
               }
            }
         }
      }
      
      private function updateManagedProperty(item:Object, newItem:Object, prop:Object, newReferencedIds:Object, useReferencedIds:Boolean = false, pendingItems:Object = null, checkConflicts:Boolean = true) : void
      {
         var leafDS:ConcreteDataService = null;
         var metadata:Metadata = null;
         var association:ManagedAssociation = null;
         var itemM:IManaged = null;
         var nestedDS:ConcreteDataService = null;
         var fromValue:Array = null;
         var toIds:Array = null;
         var newIdentity:Object = null;
         var newUID:String = null;
         var dataList:DataList = null;
         var refItem:Object = null;
         var newPropValue:Object = null;
         var oldValue:* = undefined;
         var newId:String = null;
         leafDS = this.getItemDestination(item);
         metadata = leafDS.metadata;
         association = ManagedAssociation(metadata.associations[prop]);
         if(association != null)
         {
            nestedDS = association.service;
            nestedDS.disableLogging();
            ConcreteDataService.disablePaging();
            try
            {
               if(association.lazy && newReferencedIds == null)
               {
                  if(Log.isError())
                  {
                     this._log.error("{0} newReferencedIds is null in update of item: {1} for property: {2}",this._consumer.id,itemToString(item),prop);
                  }
                  return;
               }
               if(association.typeCode == ManagedAssociation.MANY)
               {
                  if(association.lazy || useReferencedIds)
                  {
                     fromValue = newReferencedIds[prop];
                     toIds = item.referencedIds[prop] as Array;
                     if(toIds == null)
                     {
                        toIds = [];
                        item.referencedIds[prop] = toIds;
                     }
                  }
                  else
                  {
                     if(newItem[prop] == null)
                     {
                        fromValue = [];
                     }
                     else
                     {
                        fromValue = ArrayCollection(newItem[prop]).toArray();
                     }
                     toIds = null;
                  }
                  if(item[prop] == null)
                  {
                     if(Log.isError())
                     {
                        this.log.error("Found null value for collection property: " + prop + " on multi-valued collection property for item: " + itemToString(item,this.destination));
                        this.log.error("  call stack: " + new DataServiceError("to get stack trace").getStackTrace());
                     }
                  }
                  else if(fromValue == null)
                  {
                     if(Log.isError())
                     {
                        this.log.error("Found null value for from-value: " + prop + " on multi-valued collection property for item: " + itemToString(item,this.destination));
                        this.log.error("  call stack: " + new DataServiceError("to get stack trace").getStackTrace());
                     }
                  }
                  else
                  {
                     nestedDS.updateArrayCollectionItems(ArrayCollection(item[prop]),toIds,fromValue,association.lazy || useReferencedIds,newReferencedIds != null?newReferencedIds[prop]:null,pendingItems);
                  }
               }
               else
               {
                  dataList = leafDS.getDataListForAssociation(item,association);
                  if(association.lazy || useReferencedIds)
                  {
                     newIdentity = newReferencedIds[prop];
                     item.referencedIds[prop] = newIdentity;
                  }
                  else
                  {
                     newIdentity = newItem[prop];
                  }
                  if(newIdentity == null)
                  {
                     if(dataList != null)
                     {
                        dataList.setOneReference(null);
                     }
                     item[prop] = null;
                  }
                  else
                  {
                     newUID = nestedDS.metadata.getUID(newIdentity);
                     if(dataList != null)
                     {
                        dataList.setOneReference(newUID);
                     }
                     refItem = nestedDS.getCreatedOrCachedItem(newUID);
                     if(refItem == null && !association.lazy && !useReferencedIds)
                     {
                        newPropValue = newItem[prop];
                        if(Log.isDebug())
                        {
                           this.log.debug("Creating new item for a pushed lazy=false association: " + itemToString(newPropValue,nestedDS.destination));
                        }
                        nestedDS.getItemMetadata(newItem[prop]).configureItem(nestedDS,newPropValue,newPropValue,nestedDS.includeDefaultSpecifier,null,newReferencedIds != null?newReferencedIds[prop]:null,false,false,pendingItems);
                        nestedDS.updateCacheWithId(newUID,newItem[prop],null,null,null,true,checkConflicts,pendingItems);
                        refItem = nestedDS.getItem(newUID);
                     }
                     item[prop] = refItem;
                  }
               }
               if(!association.lazy && !association.paged && !useReferencedIds)
               {
                  item.referencedIds[prop] = metadata.getReferencedIdsForAssoc(association,item[prop]);
               }
            }
            finally
            {
               while(true)
               {
                  ConcreteDataService.enablePaging();
                  nestedDS.enableLogging();
               }
            }
            break loop1;
         }
         if(item is ObjectProxy)
         {
            if(prop == "uid")
            {
               ObjectProxy(item).object_proxy::object.uid = newItem.uid;
               oldValue = item[prop];
               item[prop] = newItem[prop];
               Managed.setProperty(IManaged(item),"uid",oldValue,newItem[prop]);
            }
            else
            {
               newId = metadata.getUID(newItem);
               if(ObjectProxy(item).uid != newId)
               {
                  ObjectProxy(item).uid = newId;
               }
               item[prop] = newItem[prop];
            }
         }
         else
         {
            item[prop] = newItem[prop];
         }
         itemM = IManaged(item);
         if(itemM)
         {
            this.addItemToOffline(itemM.uid,itemM,prop.toString());
         }
      }
      
      private function updateMergedItem(changes:Array, origReferencedIds:Object, item:Object, newItem:Object, origItem:Object, newReferencedIds:Object) : void
      {
         var i:int = 0;
         var prop:Object = null;
         var association:ManagedAssociation = null;
         for(i = 0; i < changes.length; i++)
         {
            prop = changes[i];
            association = this.getItemMetadata(item).associations[prop];
            if(prop.toString() != "uid")
            {
               this.updateManagedProperty(item,newItem,prop,newReferencedIds);
               if(association != null && origReferencedIds != null)
               {
                  origReferencedIds[prop] = newReferencedIds[prop];
               }
               if(origItem != null)
               {
                  origItem[prop] = newItem[prop];
               }
            }
         }
      }
      
      private function shallowCopyArray(arr:Array) : Array
      {
         var res:Array = null;
         var i:int = 0;
         res = new Array(arr.length);
         for(i = 0; i < arr.length; i++)
         {
            res[i] = arr[i];
         }
         return res;
      }
   }
}

import mx.collections.errors.ItemPendingError;
import mx.data.ConcreteDataService;
import mx.rpc.IResponder;

[ResourceBundle("data")]
class ResolveReferenceResponder implements IResponder
{
    
   
   private var _item:Object;
   
   private var _prop:String;
   
   private var _uid:String;
   
   private var _childDataService:ConcreteDataService;
   
   private var _parentDataService:ConcreteDataService;
   
   private var _userPendingError:ItemPendingError;
   
   function ResolveReferenceResponder(item:Object, prop:String, uid:String, parentDataService:ConcreteDataService, childDataService:ConcreteDataService, ipe:ItemPendingError)
   {
      super();
      this._item = item;
      this._userPendingError = ipe;
      this._uid = uid;
      this._parentDataService = parentDataService;
      this._childDataService = childDataService;
      this._prop = prop;
   }
   
   public function result(message:Object) : void
   {
      var value:Object = null;
      var responders:Array = null;
      var responder:IResponder = null;
      var i:uint = 0;
      value = this._childDataService.getItem(this._uid);
      if(value != null)
      {
         this._parentDataService.disableLogging();
         try
         {
            this._item[this._prop] = value;
            if(this._parentDataService.autoSaveCache)
            {
               this._parentDataService.dataStore.saveCache(null,true);
            }
         }
         finally
         {
            this._parentDataService.enableLogging();
         }
      }
      if(this._userPendingError.responders != null)
      {
         responders = this._userPendingError.responders;
         for(i = 0; i < responders.length; i++)
         {
            this._userPendingError.responders[i];
            responder = responders[i];
            if(responder)
            {
               responder.result(message);
            }
         }
      }
   }
   
   public function fault(message:Object) : void
   {
      var responders:Array = null;
      var responder:IResponder = null;
      var i:uint = 0;
      if(this._userPendingError.responders != null)
      {
         responders = this._userPendingError.responders;
         for(i = 0; i < responders.length; i++)
         {
            this._userPendingError.responders[i];
            responder = responders[i];
            if(responder)
            {
               responder.fault(message);
            }
         }
      }
   }
}

import mx.data.CommitResponder;
import mx.data.ConcreteDataService;
import mx.data.DataStore;
import mx.data.messages.DataMessage;
import mx.data.messages.SequencedMessage;
import mx.messaging.messages.IMessage;
import mx.rpc.AsyncToken;
import mx.rpc.events.ResultEvent;

class DeleteItemCommitResponder extends CommitResponder
{
    
   
   function DeleteItemCommitResponder(store:DataStore, token:AsyncToken)
   {
      super(store,token);
   }
   
   override protected function createResultEvent(msg:IMessage, token:AsyncToken) : ResultEvent
   {
      var i:int = 0;
      var dlmsg:IMessage = null;
      var dest:String = null;
      var dmsg:DataMessage = null;
      var dlds:ConcreteDataService = null;
      var result:Object = null;
      var seqMsg:SequencedMessage = null;
      i = 0;
      do
      {
         dlmsg = msg.body[i++];
      }
      while(i < msg.body.length && dlmsg.messageId != token.message.messageId);
      
      if(dlmsg is SequencedMessage)
      {
         seqMsg = SequencedMessage(dlmsg);
         dest = seqMsg.destination;
         dmsg = seqMsg.dataMessage;
      }
      else
      {
         dmsg = DataMessage(dlmsg);
         dest = dmsg.destination;
      }
      dlds = _store.getDataService(dest);
      result = dlds.getItem(dlds.metadata.getUID(dmsg.identity));
      return ResultEvent.createEvent(result,token,dlmsg);
   }
}

import mx.data.CommitResponder;
import mx.data.ConcreteDataService;
import mx.data.DataStore;
import mx.data.messages.DataMessage;
import mx.data.messages.SequencedMessage;
import mx.messaging.messages.IMessage;
import mx.rpc.AsyncToken;
import mx.rpc.events.ResultEvent;

class CreateItemCommitResponder extends CommitResponder
{
    
   
   function CreateItemCommitResponder(store:DataStore, token:AsyncToken)
   {
      super(store,token);
   }
   
   override protected function createResultEvent(msg:IMessage, token:AsyncToken) : ResultEvent
   {
      var i:int = 0;
      var crmsg:IMessage = null;
      var dest:String = null;
      var dmsg:DataMessage = null;
      var cds:ConcreteDataService = null;
      var result:Object = null;
      var seqMsg:SequencedMessage = null;
      i = 0;
      do
      {
         crmsg = msg.body[i++];
      }
      while(i < msg.body.length && crmsg.messageId != token.message.messageId);
      
      if(crmsg is SequencedMessage)
      {
         seqMsg = SequencedMessage(crmsg);
         dest = seqMsg.destination;
         dmsg = seqMsg.dataMessage;
      }
      else
      {
         dmsg = DataMessage(crmsg);
         dest = dmsg.destination;
      }
      cds = _store.getDataService(dest);
      result = cds.getItem(cds.metadata.getUID(dmsg.identity));
      return ResultEvent.createEvent(result,token,crmsg);
   }
}

import flash.utils.getTimer;
import mx.data.IManaged;

class ReferenceCheckEntry
{
    
   
   public var item:IManaged;
   
   public var checkTime:int;
   
   function ReferenceCheckEntry(im:IManaged, ct:int = 0)
   {
      super();
      if(ct == 0)
      {
         this.checkTime = getTimer();
      }
      else
      {
         this.checkTime = ct;
      }
      this.item = im;
   }
}
