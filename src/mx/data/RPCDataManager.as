package mx.data
{
   import flash.utils.getQualifiedClassName;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AbstractService;
   import mx.rpc.AsyncToken;
   
   [DefaultProperty("children")]
   [Event(name="propertyChange",type="mx.events.PropertyChangeEvent")]
   [Event(name="conflict",type="mx.data.events.DataConflictEvent")]
   [Event(name="fault",type="mx.data.events.DataServiceFaultEvent")]
   [Event(name="result",type="mx.rpc.events.ResultEvent")]
   [ResourceBundle("data")]
   public class RPCDataManager extends DataManager
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      private const Adobe_patent_b887:String = "AdobePatentID=\"B887\"";
      
      public var identities:String;
      
      private var _itemClass:Class;
      
      public var propertyNames:String;
      
      public var rpcAdapter:RPCDataServiceAdapter;
      
      [Inspectable(defaultValue="none",enumeration="none,property,object",category="General")]
      public var updateConflictMode:String = "none";
      
      [Inspectable(defaultValue="none",enumeration="none,object",category="General")]
      public var deleteConflictMode:String = "none";
      
      private var _managedOperations:Array;
      
      private var _metadata:Metadata;
      
      public var queries:Object;
      
      public var operationsByName:Object;
      
      var createOperation:ManagedOperation;
      
      var updateOperation:ManagedOperation;
      
      var deleteOperation:ManagedOperation;
      
      var getOperation:ManagedOperation;
      
      private var _destination:String;
      
      var parentManager:RPCDataManager;
      
      var childManagers:Array;
      
      private var _service:AbstractService = null;
      
      public var extendsDestination:String;
      
      public var typeProperty:String;
      
      private var _associations:Array;
      
      private var _children:Array = null;
      
      private var _initialized:Boolean = false;
      
      private var _preInitialized:Boolean = false;
      
      private var _pendingItemClassDynamicProperties:Array = null;
      
      public function RPCDataManager()
      {
         this._managedOperations = new Array();
         this.queries = new Object();
         this.operationsByName = new Object();
         this._associations = new Array();
         super();
      }
      
      public function set itemClass(ic:Class) : void
      {
         this._itemClass = ic;
         if(this._destination == null)
         {
            this.destination = getQualifiedClassName(this.itemClass);
         }
      }
      
      public function get itemClass() : Class
      {
         return this._itemClass;
      }
      
      public function get managedOperations() : Array
      {
         return this._managedOperations;
      }
      
      public function set managedOperations(arr:Array) : void
      {
         var i:int = 0;
         var mop:ManagedOperation = null;
         if(this._managedOperations != null)
         {
            for(i = 0; i < this._managedOperations.length; i++)
            {
               mop = ManagedOperation(this._managedOperations[i]);
               mop.dataManager = null;
            }
         }
         this._managedOperations = arr;
         this.operationsByName = new Object();
         for(i = 0; i < this._managedOperations.length; i++)
         {
            mop = ManagedOperation(this._managedOperations[i]);
            mop.dataManager = this;
            this.operationsByName[mop.name] = mop;
         }
      }
      
      public function addManagedOperation(mop:ManagedOperation) : void
      {
         mop.dataManager = this;
         this.managedOperations.push(mop);
         this.operationsByName[mop.name] = mop;
         if(this._initialized)
         {
            mop.initialize();
         }
      }
      
      public function get identitiesArray() : Array
      {
         if(_implementation == null)
         {
            return null;
         }
         return _implementation.metadata.identities;
      }
      
      public function get destination() : String
      {
         return this._destination;
      }
      
      public function set destination(dest:String) : void
      {
         if(this._destination != null && RPCDataServiceAdapter.dataManagerRegistry[this._destination] == this)
         {
            RPCDataServiceAdapter.dataManagerRegistry[this._destination] = null;
         }
         this._destination = dest;
         if(dest != null)
         {
            RPCDataServiceAdapter.dataManagerRegistry[this._destination] = this;
         }
      }
      
      public function set service(svc:AbstractService) : void
      {
         this._service = svc;
      }
      
      public function get service() : AbstractService
      {
         return this._service;
      }
      
      [ArrayElementType(type="mx.data.ManagedAssociation")]
      public function set associations(a:Array) : void
      {
         var i:int = 0;
         if(a != null)
         {
            for(i = 0; i < a.length; i++)
            {
               if(!(a[i] is ManagedAssociation))
               {
                  throw new ArgumentError(resourceManager.getString("data","associationIsNotManagedAssociation"));
               }
            }
         }
         this._associations = a;
      }
      
      public function get associations() : Array
      {
         return this._associations;
      }
      
      public function set children(c:Array) : void
      {
         this._children = c;
      }
      
      public function get children() : Array
      {
         return this._children;
      }
      
      public function preInitialize() : void
      {
         var d:* = null;
         var i:int = 0;
         var child:Object = null;
         var dmgr:DataManager = null;
         var a:int = 0;
         var assoc:ManagedAssociation = null;
         if(this._preInitialized)
         {
            return;
         }
         this._preInitialized = true;
         if(this._children != null)
         {
            for(i = 0; i < this._children.length; i++)
            {
               child = this._children[i];
               if(child is ManagedAssociation)
               {
                  this._associations.push(child);
               }
               else if(child is ManagedOperation)
               {
                  this.addManagedOperation(child as ManagedOperation);
               }
            }
         }
         for(d in RPCDataServiceAdapter.dataManagerRegistry)
         {
            dmgr = RPCDataServiceAdapter.dataManagerRegistry[d];
            if(dmgr is RPCDataManager)
            {
               RPCDataManager(dmgr).preInitialize();
            }
         }
         if(this._destination == null)
         {
            throw ArgumentError(resourceManager.getString("data","rpcDataManagerDestinatioOrItemClassNull"));
         }
         if(this._service == null)
         {
            throw ArgumentError(resourceManager.getString("data","rpcDataManagerServiceNull",[this.destination]));
         }
         if((this.identities == null || this.identities.length == 0) && this.extendsDestination == null)
         {
            throw ArgumentError(resourceManager.getString("data","destinationHasNoIDs",[this.destination]));
         }
         if(adapter == null)
         {
            adapter = this.rpcAdapter = new RPCDataServiceAdapter();
            this.rpcAdapter.destination = this.service.destination;
         }
         else
         {
            if(!(adapter is RPCDataServiceAdapter))
            {
               throw new ArgumentError(resourceManager.getString("data","rpcDataManagerHasWrongAdapter"));
            }
            this.rpcAdapter = RPCDataServiceAdapter(adapter);
         }
         this._metadata = new Metadata(adapter,null,this.destination);
         if(this.rpcAdapter.manager != null)
         {
            throw new ArgumentError(resourceManager.getString("data","dataManagerSharesAdapter"));
         }
         if(this.extendsDestination != null)
         {
            this._metadata.extendsNames = [this.extendsDestination];
            this.parentManager = RPCDataServiceAdapter.dataManagerRegistry[this.extendsDestination];
            if(this.parentManager == null)
            {
               throw new ArgumentError(resourceManager.getString("data","extendsDestinationNotFound",[this.extendsDestination,this.destination]));
            }
            this.parentManager.addChildManager(this);
         }
         if(this.typeProperty != null)
         {
            this._metadata.typeProperty = this.typeProperty;
         }
         this.rpcAdapter.manager = this;
         var ids:Array = ConcreteDataService.splitAndTrim(this.identities,",");
         this._metadata.identities = ids;
         this._metadata.itemClass = this.itemClass;
         if(this.propertyNames != null)
         {
            this._metadata.propertyNames = ConcreteDataService.splitAndTrim(this.propertyNames,",");
         }
         this._metadata.useTransactions = false;
         this._metadata.autoSyncEnabled = false;
         if(this.updateConflictMode != Conflict.OBJECT && this.updateConflictMode != Conflict.PROPERTY && this.updateConflictMode != Conflict.NONE)
         {
            throw new ArgumentError(resourceManager.getString("data","invalidUpdateConflictMode",[this.updateConflictMode]));
         }
         if(this.deleteConflictMode != Conflict.OBJECT && this.deleteConflictMode != Conflict.NONE)
         {
            throw new ArgumentError(resourceManager.getString("data","invalidDeleteConflictMode",[this.deleteConflictMode]));
         }
         if(this._associations != null)
         {
            for(a = 0; a < this._associations.length; a++)
            {
               assoc = this._associations[a];
               this._metadata.addAssociation(assoc);
            }
         }
         if(this._pendingItemClassDynamicProperties)
         {
            this._metadata.itemClassDynamicProperties = this._pendingItemClassDynamicProperties;
            this._metadata.serverConfigChanged = true;
            this._pendingItemClassDynamicProperties = null;
         }
         var cds:ConcreteDataService = ConcreteDataService.lookupService(this.destination);
         if(cds == null)
         {
            cds = new ConcreteDataService(this.destination,this.destination,adapter,this._metadata);
            cds.deleteItemOnRemoveFromFill = false;
            this._metadata.initialize(null,null,null,true);
         }
         this.setImplementation(cds);
         var ds:DataStore = cds.dataStore;
      }
      
      override public function initialize() : AsyncToken
      {
         var mop:ManagedOperation = null;
         var queryName:* = null;
         if(this._initialized)
         {
            return _implementation.initialize();
         }
         this.preInitialize();
         for(var i:int = 0; i < this._managedOperations.length; i++)
         {
            mop = ManagedOperation(this._managedOperations[i]);
            mop.initialize();
            this.operationsByName[mop.name] = mop;
         }
         if(this.parentManager != null)
         {
            for(i = 0; i < this.parentManager.managedOperations.length; i++)
            {
               mop = this.parentManager.managedOperations[i];
               if(this.operationsByName[mop.name] == null)
               {
                  this.operationsByName[mop.name] = mop;
                  if(mop.operationName != null && this[mop.operationName] == null)
                  {
                     this[mop.operationName] = mop;
                  }
               }
            }
            for(queryName in this.parentManager.queries)
            {
               if(this.queries[queryName] == null)
               {
                  this.queries[queryName] = this.parentManager.queries[queryName];
               }
            }
         }
         this._initialized = true;
         if((this.updateConflictMode != Conflict.NONE || this.deleteConflictMode != Conflict.NONE) && this.getOperation == null && getQualifiedClassName(adapter) == getQualifiedClassName(RPCDataServiceAdapter))
         {
            throw new ArgumentError(resourceManager.getString("data","conflictDetectionRequiresGetOperation",[this.destination]));
         }
         return super.initialize();
      }
      
      function getDataManager(destination:String) : RPCDataManager
      {
         return RPCDataManager(adapter.getDataManager(destination));
      }
      
      override protected function checkImplementation() : void
      {
         if(this.service != null)
         {
            this.service.initialize();
         }
         super.checkImplementation();
      }
      
      override function setImplementation(impl:ConcreteDataService) : void
      {
         super.setImplementation(impl);
         this.applyPendingDynamicProperties();
      }
      
      override public function set dataStore(ds:DataStore) : void
      {
         super.dataStore = ds;
         this.applyPendingDynamicProperties();
      }
      
      private function addChildManager(dmgr:RPCDataManager) : void
      {
         if(this.childManagers == null)
         {
            this.childManagers = new Array();
         }
         this.childManagers.push(dmgr);
      }
      
      override public function get pagingEnabled() : Boolean
      {
         throw new Error("data","pagingEnabledOnManagedQuery");
      }
      
      override public function get autoSyncEnabled() : Boolean
      {
         return false;
      }
      
      override public function set autoSyncEnabled(value:Boolean) : void
      {
         throw new Error("data","autoSyncOnRPCDataManager");
      }
      
      public function get itemClassDynamicProperties() : Array
      {
         var result:Array = Boolean(_implementation)?_implementation.itemClassDynamicProperties:this._pendingItemClassDynamicProperties;
         return Boolean(result)?result:[];
      }
      
      public function setItemClassDynamicProperties(newProperties:Array) : void
      {
         if(_implementation)
         {
            _implementation.setItemClassDynamicProperties(newProperties);
         }
         else
         {
            Metadata.validateDynamicProperties(newProperties);
            this._pendingItemClassDynamicProperties = newProperties;
         }
      }
      
      private function applyPendingDynamicProperties() : void
      {
         if(this._pendingItemClassDynamicProperties)
         {
            this.setItemClassDynamicProperties(this._pendingItemClassDynamicProperties);
         }
      }
      
      public function get allowDynamicPropertyChangesWithCachedData() : Boolean
      {
         return Boolean(_implementation)?Boolean(_implementation.allowDynamicPropertyChangesWithCachedData):Boolean(propertyCache.allowDynamicPropertyChangesWithCachedData);
      }
      
      public function set allowDynamicPropertyChangesWithCachedData(value:Boolean) : void
      {
         if(_implementation)
         {
            _implementation.allowDynamicPropertyChangesWithCachedData = value;
         }
         else
         {
            propertyCache.allowDynamicPropertyChangesWithCachedData = value;
         }
      }
   }
}
