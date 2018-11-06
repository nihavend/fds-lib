package mx.data
{
   import flash.net.getClassByAlias;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import mx.collections.ArrayCollection;
   import mx.collections.Sort;
   import mx.collections.SortField;
   import mx.collections.errors.ItemPendingError;
   import mx.data.errors.DataServiceError;
   import mx.data.utils.Managed;
   import mx.data.utils.SerializationDescriptor;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.config.ServerConfig;
   import mx.messaging.errors.InvalidDestinationError;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncResponder;
   import mx.utils.ObjectProxy;
   import mx.utils.ObjectUtil;
   import mx.utils.StringUtil;
   import mx.utils.object_proxy;
   
   [RemoteClass]
   [ExcludeClass]
   [ResourceBundle("data")]
   public class Metadata implements IExternalizable
   {
      
      static const FETCH_IDENTITY:String = "IDENTITY";
      
      static const FETCH_INSTANCE:String = "INSTANCE";
      
      static const CONFIG_KEY:String = "_config_";
      
      static var inverseAssociations:Object = null;
      
      static var subTypeGraph:Object = null;
      
      static const DEFAULT_PAGE_SIZE:int = 10;
      
      private static const VERSION:uint = 0;
      
      static const UID_TYPE_SEPARATOR:String = ":#:";
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      public var destination:String;
      
      public var adapter:DataServiceAdapter;
      
      private var _autoSyncEnabled:Boolean = true;
      
      private var _associations:Object;
      
      private var _associationNames:Array = null;
      
      private var _id:String;
      
      private var _rootDestination:String;
      
      private var _hasAssociations:Boolean = false;
      
      private var _hierarchicalEventsDefault:Boolean = false;
      
      private var _idIsUID:Boolean = false;
      
      private var _initialized:Boolean = false;
      
      private var _lazyAssociations:Array;
      
      private var _associationInfoSet:Boolean = false;
      
      private var _pagingEnabled:Boolean = false;
      
      private var _pageSize:int = 10;
      
      private var _pageSizeSet:Boolean = false;
      
      private var _propertyNames:Array;
      
      private var _reconnectPolicy:String;
      
      private var _serializationDescriptor:SerializationDescriptor;
      
      private var _updateRefIdsDescriptor:SerializationDescriptor;
      
      private var _deleteRefIdsDescriptor:SerializationDescriptor;
      
      private var _identities:Array;
      
      private var _uidUndefinedValues:Array;
      
      private var _useTransactions:Boolean = true;
      
      var validated:Boolean = false;
      
      private var _validatePending:Boolean = false;
      
      private var _loadOnDemandProperties:Array;
      
      private var _allLazyProperties:Array;
      
      var extendsNames:Array = null;
      
      private var _itemClass:Class = null;
      
      private var _itemClassDynamicProperties:Array = null;
      
      private var _createMethodNames:Array;
      
      private var _updateMethodNames:Array;
      
      private var _deleteMethodNames:Array;
      
      private var _fillMethodNames:Array;
      
      private var _getMethodNames:Array;
      
      private var _findItemMethodNames:Array;
      
      private var _managedEntities:Array;
      
      private var _methodNameToReturnType:Object;
      
      private var _methodNameToPageSize:Object;
      
      public var typeProperty:String;
      
      var serverConfigChanged:Boolean = false;
      
      var offlineSchema:Object;
      
      public function Metadata(adapter:DataServiceAdapter = null, destination:String = null, id:String = null)
      {
         this._associations = {};
         this._identities = [];
         this._uidUndefinedValues = [];
         this._createMethodNames = [];
         this._updateMethodNames = [];
         this._deleteMethodNames = [];
         this._fillMethodNames = [];
         this._getMethodNames = [];
         this._findItemMethodNames = [];
         this._managedEntities = [];
         this._methodNameToReturnType = {};
         this._methodNameToPageSize = {};
         super();
         this.adapter = adapter;
         this.destination = destination;
         this._rootDestination = destination;
         if(id == null)
         {
            this._id = this.destination;
         }
         else if(destination == null)
         {
            this._rootDestination = id;
            this._id = id;
         }
      }
      
      static function validateDynamicProperties(properties:Array) : void
      {
         var property:DynamicProperty = null;
         var typeName:String = null;
         if(properties)
         {
            for each(property in properties)
            {
               if(!property)
               {
                  throw new Error("null property found");
               }
               typeName = Boolean(property.type)?getQualifiedClassName(property.type):"null";
               if(!property.name)
               {
                  throw new Error("name not specified for property with type " + typeName);
               }
               if(!property.type)
               {
                  property.type = Object;
               }
            }
         }
      }
      
      public static function getMetadata(destination:String) : Metadata
      {
         return ConcreteDataService.getService(destination).metadata;
      }
      
      public static function isLazyAssociation(obj:Object, prop:String) : Boolean
      {
         var mop:ManagedObjectProxy = null;
         var metadata:Metadata = null;
         var association:ManagedAssociation = null;
         var destination:String = null;
         if(obj is ManagedObjectProxy)
         {
            mop = obj as ManagedObjectProxy;
            destination = mop.destination;
         }
         if(destination != null)
         {
            metadata = Metadata.getMetadata(destination);
            if(metadata != null)
            {
               association = metadata._associations[prop] as ManagedAssociation;
               if(association != null && association.lazy)
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      static function checkInverseAssociations() : void
      {
         var metadata:XMLList = null;
         var children:XMLList = null;
         var i:int = 0;
         var tag:XML = null;
         var tagName:String = null;
         var destName:String = null;
         if(inverseAssociations == null)
         {
            inverseAssociations = new Object();
            metadata = ServerConfig.xml..metadata;
            children = metadata.children();
            for(i = 0; i < children.length(); i++)
            {
               tag = children[i];
               tagName = tag.name().toString();
               if(tagName.indexOf("-to-") != -1)
               {
                  destName = tag.attribute("destination").toString();
                  inverseAssociations[destName] = true;
               }
            }
         }
      }
      
      static function initSubTypeGraph() : void
      {
         var destinations:XMLList = null;
         var i:int = 0;
         var destination:XML = null;
         var metadata:XMLList = null;
         var extendsArr:Array = null;
         var j:int = 0;
         var typeNames:Array = null;
         if(subTypeGraph == null)
         {
            subTypeGraph = new Object();
            destinations = ServerConfig.xml..destination;
            for(i = 0; i < destinations.length(); i++)
            {
               destination = destinations[i];
               metadata = destination.properties == null?null:destination.properties.metadata;
               if(metadata != null && metadata.length() > 0)
               {
                  extendsArr = parseExtendsStr(metadata);
                  if(extendsArr != null)
                  {
                     for(j = 0; j < extendsArr.length; j++)
                     {
                        typeNames = subTypeGraph[extendsArr[j]];
                        if(typeNames == null)
                        {
                           subTypeGraph[extendsArr[j]] = [destination.@id.toString()];
                        }
                        else
                        {
                           typeNames.push(destination.@id.toString());
                        }
                     }
                  }
               }
            }
         }
      }
      
      static function clearSubTypeGraph() : void
      {
         subTypeGraph = null;
      }
      
      private static function parseExtendsStr(metadata:XMLList) : Array
      {
         var extNames:Array = null;
         var i:int = 0;
         var extendsStr:String = metadata["extends"];
         if(extendsStr == null || extendsStr.length == 0)
         {
            extendsStr = metadata.attribute("extends");
         }
         if(extendsStr != null && extendsStr.length > 0)
         {
            extNames = extendsStr.split(",");
            for(i = 0; i < extNames.length; i++)
            {
               extNames[i] = StringUtil.trim(extNames[i]);
            }
            return extNames;
         }
         return null;
      }
      
      public function initialize(success:Function = null, failed:Function = null, configData:Object = null, initLocal:Boolean = false) : Boolean
      {
         var properties:XMLList = null;
         var otherMetadata:Metadata = null;
         var serverConfig:Boolean = false;
         var configSuccess:Function = null;
         var configFailed:Function = null;
         otherMetadata = null;
         serverConfig = false;
         configSuccess = function(a:Object, b:Object):void
         {
            if(otherMetadata != null)
            {
               applyConfigMetadata(otherMetadata);
            }
            else
            {
               applyConfigSettings(properties);
            }
            if(isInitialized && serverConfig)
            {
               serverConfigChanged = true;
            }
            if(isInitialized)
            {
               if(success != null)
               {
                  if(a == null)
                  {
                     new AsyncDispatcher(success,[],1);
                  }
                  else
                  {
                     success();
                  }
               }
            }
            else if(failed != null)
            {
               failed("No identity properties for destination: " + destination);
            }
         };
         configFailed = function(info:Object):void
         {
            failed(info.details);
         };
         if(this.isInitialized)
         {
            if(success != null)
            {
               new AsyncDispatcher(success,[],1);
            }
            return true;
         }
         try
         {
            if(this.destination != null)
            {
               try
               {
                  if(configData is String)
                  {
                     properties = XMLList(configData);
                  }
                  else if(configData is Metadata)
                  {
                     otherMetadata = Metadata(configData);
                  }
                  else if(configData != null)
                  {
                     throw new DataServiceError("Unexpected type for config key: " + configData);
                  }
                  if(otherMetadata == null && (properties == null || properties.length() == 0) && this.destination != null)
                  {
                     properties = ServerConfig.getProperties(this.destination);
                     serverConfig = true;
                  }
                  configSuccess(null,null);
               }
               catch(e:ItemPendingError)
               {
                  e.addResponder(new AsyncResponder(configSuccess,configFailed));
                  return false;
               }
            }
            else
            {
               if(this.destination != null)
               {
                  this.applyConfigSettings(ServerConfig.getProperties(this.destination));
                  if(this.isInitialized)
                  {
                     this.serverConfigChanged = true;
                  }
               }
               else if(initLocal)
               {
                  this.initLocalConfig();
               }
               if(success != null)
               {
                  new AsyncDispatcher(success,[],1);
               }
            }
         }
         catch(ide:InvalidDestinationError)
         {
            return false;
         }
         if(this.isInitialized && serverConfig)
         {
            this.serverConfigChanged = true;
         }
         return this.isInitialized;
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         var property:DynamicProperty = null;
         output.writeUnsignedInt(Metadata.VERSION);
         output.writeUTF(this.destination == null?"":this.destination);
         output.writeObject(this._identities);
         output.writeObject(this._uidUndefinedValues);
         output.writeBoolean(this._useTransactions);
         output.writeObject(this.extendsNames);
         output.writeObject(this.typeProperty);
         output.writeObject(this._propertyNames);
         output.writeObject(this._associations);
         output.writeUTF(this._reconnectPolicy == null?"":this._reconnectPolicy);
         output.writeUTF(Boolean(this.itemClass)?getQualifiedClassName(this.itemClass):"");
         output.writeInt(this._pageSize);
         output.writeBoolean(this._pagingEnabled);
         output.writeBoolean(this._hierarchicalEventsDefault);
         output.writeBoolean(this._autoSyncEnabled);
         output.writeObject(this.offlineSchema);
         var dynamicProperties:Array = [];
         for each(property in this.itemClassDynamicProperties)
         {
            dynamicProperties.push(property.name);
            dynamicProperties.push(getQualifiedClassName(property.type));
         }
         output.writeObject(dynamicProperties);
      }
      
      public function readExternal(input:IDataInput) : void
      {
         var dynamicProperties:Array = null;
         var i:int = 0;
         var property:DynamicProperty = null;
         var typeName:String = null;
         var version:uint = input.readUnsignedInt();
         this.destination = input.readUTF();
         if(this.destination == "")
         {
            this.destination = null;
         }
         this._identities = input.readObject();
         this._uidUndefinedValues = input.readObject();
         this._useTransactions = input.readBoolean();
         this.extendsNames = input.readObject();
         this.typeProperty = input.readObject();
         this._propertyNames = input.readObject();
         this._associations = input.readObject();
         this._reconnectPolicy = input.readUTF();
         if(this._reconnectPolicy == "")
         {
            this._reconnectPolicy = null;
         }
         this.itemClass = null;
         var itemClassName:String = input.readUTF();
         if(itemClassName)
         {
            this.itemClass = getDefinitionByName(itemClassName) as Class;
            if(!this.itemClass)
            {
               throw new Error("item class not found: " + itemClassName);
            }
         }
         this._pageSize = input.readInt();
         this._pagingEnabled = input.readBoolean();
         this._hierarchicalEventsDefault = input.readBoolean();
         this._autoSyncEnabled = input.readBoolean();
         if(input.bytesAvailable > 0)
         {
            this.offlineSchema = input.readObject();
         }
         var newProperties:Array = null;
         if(input.bytesAvailable > 0)
         {
            newProperties = [];
            dynamicProperties = input.readObject() as Array;
            if(dynamicProperties)
            {
               for(i = 0; i < dynamicProperties.length; i = i + 2)
               {
                  property = new DynamicProperty();
                  property.name = dynamicProperties[i];
                  typeName = dynamicProperties[i + 1];
                  property.type = getDefinitionByName(typeName) as Class;
                  if(!property.type)
                  {
                     throw new Error("property type not found: " + typeName);
                  }
                  newProperties.push(property);
               }
            }
         }
         this.itemClassDynamicProperties = newProperties;
      }
      
      private function initLocalConfig() : void
      {
         this._initialized = true;
      }
      
      function get hasChangedItemClassDynamicProperties() : Boolean
      {
         return this._itemClassDynamicProperties != null;
      }
      
      function get itemClassDynamicProperties() : Array
      {
         return Boolean(this._itemClassDynamicProperties)?this._itemClassDynamicProperties:[];
      }
      
      function set itemClassDynamicProperties(newProperties:Array) : void
      {
         validateDynamicProperties(newProperties);
         this._itemClassDynamicProperties = newProperties;
      }
      
      public function hasMatchingDynamicProperties(properties:Array) : Boolean
      {
         var newProperties:Array = properties.concat();
         var thisProperties:Array = this.itemClassDynamicProperties.concat();
         var sort:Sort = new Sort();
         var caseInsensitive:Boolean = true;
         sort.fields = [new SortField("name",caseInsensitive)];
         sort.sort(newProperties);
         sort.sort(thisProperties);
         return ObjectUtil.compare(thisProperties,newProperties) == 0;
      }
      
      function validate(store:DataStore, dataService:ConcreteDataService) : void
      {
         var assocName:String = null;
         var i:int = 0;
         var extDS:ConcreteDataService = null;
         var propName:String = null;
         if(this.validated)
         {
            return;
         }
         if(this._validatePending)
         {
            throw new DataServiceError("Cycle in extends classes - includes destination: " + this.destination);
         }
         this._validatePending = true;
         for(assocName in this.associations)
         {
            ManagedAssociation(this._associations[assocName]).validate();
         }
         try
         {
            if(this.extendsNames != null && this.extendsNames.length > 0)
            {
               dataService.extendsDestinations = new Array(this.extendsNames.length);
               for(i = 0; i < this.extendsNames.length; i++)
               {
                  extDS = store.getDataService(this.extendsNames[i]);
                  dataService.extendsDestinations[i] = extDS;
                  extDS.metadata.validate(store,extDS);
                  if(i == 0)
                  {
                     this._rootDestination = extDS.metadata._rootDestination;
                  }
                  extDS.addSubtype(dataService);
                  if(i == 0 && (this._identities == null || this._identities.length == 0))
                  {
                     this._identities = extDS.metadata._identities;
                     this._uidUndefinedValues = extDS.metadata._uidUndefinedValues;
                  }
               }
               for(i = 0; i < this.extendsNames.length; i++)
               {
                  extDS = ConcreteDataService(dataService.extendsDestinations[i]);
                  for(propName in extDS.metadata.associations)
                  {
                     if(this._associations[propName] == null)
                     {
                        this.addAssociation(extDS.metadata.associations[propName]);
                     }
                  }
               }
            }
            if(Log.isDebug())
            {
               dataService.log.debug("Finished validating metadata for: " + this._id + " loadOnDemand/paged associations: " + ConcreteDataService.itemToString(this.loadOnDemandProperties) + " sub-types: " + dataService.getSubTypesString());
            }
         }
         finally
         {
            this._validatePending = false;
         }
         if(this._identities.length == 1 && this._identities[0] == "uid")
         {
            this._idIsUID = true;
         }
         if(this._identities == null || this._identities.length == 0)
         {
            throw new DataServiceError("DataManager: " + this._id + " has no identity properties defined.");
         }
         this.validated = true;
      }
      
      public function addAssociation(assoc:ManagedAssociation) : void
      {
         assoc.metadata = this;
         this._associations[assoc.property] = assoc;
         this._associationInfoSet = false;
         this._hasAssociations = true;
         if(!assoc.hierarchicalEventsSet)
         {
            assoc._hierarchicalEvents = this._hierarchicalEventsDefault;
         }
      }
      
      public function configureItem(parentDataService:ConcreteDataService, cacheItem:Object, item:Object, ps:PropertySpecifier, proxy:Object, referencedIds:Object, itemInCache:Boolean, createdOnThisClient:Boolean, pendingItems:Object = null, transientItem:Boolean = false, clientReferencedIds:Boolean = false, overridden:Boolean = false, allLazy:Boolean = false) : void
      {
         var collection:ArrayCollection = null;
         var dataList:DataList = null;
         var association:ManagedAssociation = null;
         var propInfo:Object = null;
         var prop:Object = null;
         var oldReferencedIds:Object = null;
         var precomputedClientReferencedIds:Object = null;
         var oldArray:Array = null;
         var propList:Array = null;
         var i:int = 0;
         var propName:String = null;
         var processedSequence:Boolean = false;
         var havePropertyValue:Boolean = false;
         var associationLazy:Boolean = false;
         var newList:Boolean = false;
         var error:Boolean = false;
         var toIds:Array = null;
         var updateToIds:Boolean = false;
         var fromIds:Array = null;
         var assocUID:String = null;
         var uid:String = null;
         var canonicalItem:Object = null;
         var assocIdentity:Object = null;
         var currentRefIds:Object = null;
         var e:int = 0;
         var pp:String = null;
         var excludes:Array = null;
         var ex:int = 0;
         var exProp:String = null;
         var rid:String = null;
         var leafDS:ConcreteDataService = parentDataService.getItemDestination(cacheItem);
         if(leafDS != parentDataService)
         {
            leafDS.metadata.configureItem(leafDS,cacheItem,item,ps.getSubclassSpecifier(leafDS),proxy,referencedIds,itemInCache,createdOnThisClient,pendingItems,transientItem,clientReferencedIds,overridden);
            return;
         }
         if(!this.isInitialized)
         {
            throw new DataServiceError("DataService error. Configuration not present.");
         }
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         if(pendingItems == null)
         {
            var pendingItems:Object = new Object();
         }
         var itemId:String = parentDataService.getItemCacheId(cacheItem);
         var pendingState:int = int(pendingItems[itemId]);
         if(pendingState & ConcreteDataService.PENDING_STATE_CONFIGURED)
         {
            return;
         }
         pendingItems[itemId] = pendingState | ConcreteDataService.PENDING_STATE_CONFIGURED;
         if(this._hasAssociations || ps.includeMode != PropertySpecifier.INCLUDE_DEFAULT)
         {
            Managed.setDestination(item,parentDataService.destination);
         }
         parentDataService.disableLogging();
         ConcreteDataService.disablePaging();
         try
         {
            if(this._hasAssociations)
            {
               leafDS.checkAssociations(item);
            }
            if(this.needsReferencedIds)
            {
               oldReferencedIds = item.referencedIds;
               if(referencedIds == null)
               {
                  var referencedIds:Object = this.getReferencedIds(item);
                  var clientReferencedIds:Boolean = true;
               }
            }
            else
            {
               oldReferencedIds = null;
            }
            if(allLazy)
            {
               clientReferencedIds = true;
            }
            propList = ps.includeMode == PropertySpecifier.INCLUDE_LIST?ps.extraProperties:this.associationNames;
            if(propList == null)
            {
               propList = [];
            }
            if(cacheItem == item && ps.includeMode == PropertySpecifier.INCLUDE_LIST)
            {
               propList = ConcreteDataService.concatArrays(propList,this.associationNames);
            }
            if(transientItem)
            {
               precomputedClientReferencedIds = ObjectUtil.copy(referencedIds);
               this.convertServerToClientReferencedIds(item,precomputedClientReferencedIds,ps);
            }
            else
            {
               precomputedClientReferencedIds = null;
            }
            i = 0;
            while(true)
            {
               if(i >= propList.length)
               {
                  if(referencedIds != null)
                  {
                     if(precomputedClientReferencedIds != null)
                     {
                        referencedIds = precomputedClientReferencedIds;
                     }
                     else if(!clientReferencedIds)
                     {
                        this.convertServerToClientReferencedIds(item,referencedIds,ps);
                     }
                     if(ps.includeMode == PropertySpecifier.INCLUDE_LIST)
                     {
                        currentRefIds = Managed.getReferencedIds(cacheItem);
                        for(e = 0; e < ps.extraProperties.length; e++)
                        {
                           pp = ps.extraProperties[e];
                           if(referencedIds[pp] != null)
                           {
                              currentRefIds[pp] = referencedIds[pp];
                           }
                        }
                        referencedIds = currentRefIds;
                     }
                     else
                     {
                        Managed.setReferencedIds(cacheItem,referencedIds);
                     }
                  }
                  if(item == cacheItem)
                  {
                     excludes = ps.getExcluded(item);
                     if(excludes != null && excludes.length > 0)
                     {
                        if(referencedIds == null)
                        {
                           referencedIds = Managed.getReferencedIds(cacheItem);
                        }
                        for(ex = 0; ex < excludes.length; ex++)
                        {
                           exProp = excludes[ex];
                           association = ManagedAssociation(this._associations[exProp]);
                           if(!(association != null && association.loadOnDemand))
                           {
                              referencedIds[exProp] = Managed.UNSET_PROPERTY;
                              if(Log.isDebug())
                              {
                                 parentDataService.log.debug("Marking property: " + exProp + " unfetched for: " + item.uid);
                              }
                           }
                        }
                     }
                  }
                  else
                  {
                     if(referencedIds == null)
                     {
                        try
                        {
                           referencedIds = cacheItem.referencedIds;
                        }
                        catch(e:ReferenceError)
                        {
                        }
                     }
                     if(referencedIds != null)
                     {
                        for(rid in referencedIds)
                        {
                           if(referencedIds[rid] == Managed.UNSET_PROPERTY && ps.includeProperty(rid))
                           {
                              delete referencedIds[rid];
                              if(Log.isDebug())
                              {
                                 parentDataService.log.debug("Marking property: " + rid + " fetched for: " + item.uid);
                              }
                           }
                        }
                     }
                  }
               }
               else
               {
                  propName = propList[i];
                  processedSequence = false;
                  association = ManagedAssociation(this._associations[propName]);
                  if(association != null)
                  {
                     havePropertyValue = ps.includeProperty(propName) && (referencedIds == null || referencedIds[propName] != Managed.UNSET_PROPERTY);
                     associationLazy = !!allLazy?Boolean(true):Boolean(association.lazy);
                     if(proxy != null)
                     {
                        propInfo = proxy[propName];
                     }
                     else
                     {
                        propInfo = null;
                     }
                     prop = item[propName];
                     association.service.reconnect();
                     newList = false;
                     if(transientItem)
                     {
                        dataList = null;
                     }
                     else
                     {
                        dataList = parentDataService.getDataListForAssociation(cacheItem,association);
                        if(dataList != null && propInfo != null)
                        {
                           dataList.sequenceId = propInfo.sequenceId;
                           if(propInfo.sequenceId >= 0 && !dataList.sequenceAutoSubscribed)
                           {
                              association.service.autoSubscribe();
                              dataList.sequenceAutoSubscribed = true;
                           }
                        }
                     }
                     if(dataList == null)
                     {
                        dataList = new DataList(association.service,propInfo == null || !havePropertyValue?int(-1):int(propInfo.sequenceId),association,parentDataService,cacheItem,propInfo != null,transientItem,havePropertyValue);
                        newList = true;
                     }
                     if(association.lazy)
                     {
                        dataList.enablePaging();
                     }
                     if(propInfo != null)
                     {
                        if(!association.lazy && !overridden)
                        {
                           dataList.setSequenceSize(propInfo.sequenceSize);
                        }
                     }
                     if(association.typeCode == ManagedAssociation.MANY)
                     {
                        if(prop == null)
                        {
                           error = false;
                           try
                           {
                              prop = item[propName] = new ArrayCollection();
                           }
                           catch(e:Error)
                           {
                              if(Log.isDebug())
                              {
                                 parentDataService.log.debug("Exception in property accessor for item of type: " + getQualifiedClassName(item) + " for property: " + propName + " exception: " + e.getStackTrace());
                              }
                              error = true;
                           }
                           if(prop == null || !(prop is ArrayCollection))
                           {
                              break;
                           }
                        }
                        collection = ArrayCollection(prop);
                        if(collection.list != dataList)
                        {
                           if(collection.list is IPagedList)
                           {
                              dataList.pagedList = IPagedList(collection.list);
                           }
                           else if(!(collection.list is DataList))
                           {
                              if(collection.source == null)
                              {
                                 collection.source = new Array();
                              }
                              if(!associationLazy && havePropertyValue || createdOnThisClient)
                              {
                                 processedSequence = true;
                                 dataList.processSequence(collection.source,ps.getSubSpecifier(cacheItem,propName),0,propInfo == null?null:propInfo.subs,referencedIds == null || clientReferencedIds?null:referencedIds[association.property],null,newList,!createdOnThisClient && !transientItem,pendingItems,null,createdOnThisClient);
                              }
                           }
                           collection.list = dataList;
                           if((newList || !dataList.fetched) && !createdOnThisClient && havePropertyValue && !processedSequence)
                           {
                              if(associationLazy)
                              {
                                 if(oldReferencedIds == null || oldReferencedIds[propName] == null)
                                 {
                                    toIds = new Array();
                                    updateToIds = true;
                                 }
                                 else
                                 {
                                    toIds = oldReferencedIds[propName];
                                    updateToIds = oldReferencedIds != item.referencedIds;
                                 }
                                 if(referencedIds == null || referencedIds[propName] == null)
                                 {
                                    fromIds = new Array();
                                 }
                                 else
                                 {
                                    fromIds = referencedIds[propName];
                                 }
                                 if(newList)
                                 {
                                    dataList.references = ObjectUtil.copy(toIds) as Array;
                                 }
                                 association.service.updateArrayCollectionItems(collection,toIds,fromIds,true,null,pendingItems,updateToIds);
                                 dataList.fetched = true;
                              }
                              else
                              {
                                 oldArray = collection.toArray();
                                 association.service.updateArrayCollectionItems(collection,null,oldArray,false,null,pendingItems);
                              }
                           }
                        }
                        else if(oldReferencedIds != null && itemInCache)
                        {
                           referencedIds[association.property] = oldReferencedIds[association.property];
                        }
                     }
                     else if(havePropertyValue)
                     {
                        assocUID = null;
                        if(newList)
                        {
                           if(prop != null)
                           {
                              uid = association.service.metadata.getUID(prop);
                              if(uid != "")
                              {
                                 canonicalItem = association.service.getItem(uid);
                                 if(canonicalItem != null)
                                 {
                                    prop = canonicalItem;
                                    cacheItem[propName] = prop;
                                 }
                              }
                              if(createdOnThisClient || !associationLazy)
                              {
                                 dataList.processSequence([prop],ps.getSubSpecifier(cacheItem,propName),0,propInfo == null?null:propInfo.subs,referencedIds == null || clientReferencedIds || referencedIds[association.property] == null?null:[referencedIds[association.property]],null,newList,!createdOnThisClient && !transientItem,pendingItems,null,createdOnThisClient);
                              }
                           }
                        }
                        if(newList && !createdOnThisClient)
                        {
                           if(associationLazy)
                           {
                              assocIdentity = referencedIds[propName];
                              assocUID = association.service.getUIDFromIdentity(assocIdentity);
                              if(assocIdentity != null)
                              {
                                 if(dataList.length > 0)
                                 {
                                    dataList.removeItemAt(0);
                                 }
                                 dataList.addReferenceAt(assocUID,assocIdentity,0);
                              }
                           }
                        }
                        else if(associationLazy)
                        {
                           if(oldReferencedIds != null && itemInCache)
                           {
                              referencedIds[association.property] = oldReferencedIds[association.property];
                           }
                           assocUID = association.service.getUIDFromIdentity(referencedIds[association.property]);
                        }
                        if(dataList.length > 0 && assocUID != null && association.service.getItem(assocUID) != null)
                        {
                           cacheItem[propName] = dataList.getItemAt(0);
                        }
                     }
                  }
                  i++;
                  continue;
               }
            }
            throw new DataServiceError(resourceManager.getString("data",!error?"itemNotArrayCollection":"errorGettingAssociation",[propName,prop == null?"null":getQualifiedClassName(prop),this.getUID(cacheItem),getQualifiedClassName(cacheItem)]));
         }
         catch(e:Error)
         {
            ConcreteDataService.enablePaging();
            parentDataService.enableLogging();
            throw e;
         }
         ConcreteDataService.enablePaging();
         parentDataService.enableLogging();
      }
      
      public function get associations() : Object
      {
         return this._associations;
      }
      
      public function get associationNames() : Array
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._associationNames;
      }
      
      public function get associatedDestinationNames() : Array
      {
         var p:* = null;
         var association:ManagedAssociation = null;
         if(this._associations == null)
         {
            return null;
         }
         var arr:Array = [];
         for(p in this._associations)
         {
            association = ManagedAssociation(this._associations[p]);
            arr.push(association.destination);
         }
         return arr;
      }
      
      public function getMappedAssociationProperty(dest:String) : String
      {
         var p:* = null;
         var association:ManagedAssociation = null;
         if(this._associations == null)
         {
            return null;
         }
         for(p in this._associations)
         {
            association = ManagedAssociation(this._associations[p]);
            if(association.destination == dest)
            {
               return association.property;
            }
         }
         return null;
      }
      
      public function getMappedAssociation(dest:String) : ManagedAssociation
      {
         var p:* = null;
         var association:ManagedAssociation = null;
         if(this._associations == null)
         {
            return null;
         }
         for(p in this._associations)
         {
            association = ManagedAssociation(this._associations[p]);
            if(association.destination == dest)
            {
               return association;
            }
         }
         return null;
      }
      
      public function set autoSyncEnabled(v:Boolean) : void
      {
         this._autoSyncEnabled = v;
      }
      
      public function get autoSyncEnabled() : Boolean
      {
         return this._autoSyncEnabled;
      }
      
      public function get isInitialized() : Boolean
      {
         return this._initialized;
      }
      
      public function get lazyAssociations() : Array
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._lazyAssociations;
      }
      
      private function validateAssociationInfo() : void
      {
         var lazyAssocs:Array = null;
         var p:* = null;
         var association:ManagedAssociation = null;
         var propName:String = null;
         this._allLazyProperties = new Array();
         this._loadOnDemandProperties = new Array();
         this._associationNames = [];
         for(p in this._associations)
         {
            association = ManagedAssociation(this._associations[p]);
            propName = association.property;
            this._associationNames.push(propName);
            if(association.lazy)
            {
               if(lazyAssocs == null)
               {
                  lazyAssocs = new Array();
               }
               lazyAssocs.push(propName);
               this._allLazyProperties.push(propName);
            }
            if(association.loadOnDemand)
            {
               this._loadOnDemandProperties.push(propName);
               this._allLazyProperties.push(propName);
            }
         }
         this._lazyAssociations = lazyAssocs;
         this.initSerializationDescriptors();
         this._associationInfoSet = true;
      }
      
      public function get pagingEnabled() : Boolean
      {
         return this._pagingEnabled;
      }
      
      public function set pagingEnabled(pe:Boolean) : void
      {
         this._pagingEnabled = pe;
      }
      
      public function get pageSize() : int
      {
         return this._pageSize;
      }
      
      public function set pageSize(value:int) : void
      {
         this._pageSize = value;
         this._pageSizeSet = true;
      }
      
      public function set propertyNames(pn:Array) : void
      {
         this._propertyNames = pn;
      }
      
      public function get propertyNames() : Array
      {
         var result:Array = null;
         var dynamicProperty:DynamicProperty = null;
         var found:Boolean = false;
         var existingProperty:String = null;
         if(this._propertyNames != null)
         {
            return this._propertyNames;
         }
         if(this.itemClass != null)
         {
            result = ConcreteDataService.getObjectProperties(this.itemClass);
            for each(dynamicProperty in this.itemClassDynamicProperties)
            {
               found = false;
               for each(existingProperty in result)
               {
                  if(existingProperty == dynamicProperty.name)
                  {
                     found = true;
                     break;
                  }
               }
               if(!found)
               {
                  result.push(new QName("",dynamicProperty.name));
               }
            }
            return result;
         }
         return this.identities.concat(this.associationNames);
      }
      
      public function get createMethodNames() : Array
      {
         return this._createMethodNames;
      }
      
      public function get updateMethodNames() : Array
      {
         return this._updateMethodNames;
      }
      
      public function get deleteMethodNames() : Array
      {
         return this._deleteMethodNames;
      }
      
      public function get fillMethodNames() : Array
      {
         return this._fillMethodNames;
      }
      
      public function get getMethodNames() : Array
      {
         return this._getMethodNames;
      }
      
      public function get findItemMethodNames() : Array
      {
         return this._findItemMethodNames;
      }
      
      public function get managedEntites() : Array
      {
         return this._managedEntities;
      }
      
      public function lookupMethodReturnValue(fillName:String) : Class
      {
         var cl:Class = null;
         var name:String = this._methodNameToReturnType[fillName];
         if(name != null)
         {
            cl = getClassByAlias(name);
            return cl;
         }
         return null;
      }
      
      public function lookupFillMethodPageSize(fillName:String) : int
      {
         var pageSize:int = this._methodNameToPageSize[fillName];
         return pageSize;
      }
      
      public function get identities() : Array
      {
         return this._identities;
      }
      
      public function set identities(arr:Array) : void
      {
         this._identities = arr;
      }
      
      public function get itemClass() : Class
      {
         return this._itemClass;
      }
      
      public function set itemClass(value:Class) : void
      {
         this._itemClass = value;
      }
      
      public function get useTransactions() : Boolean
      {
         return this._useTransactions;
      }
      
      public function set useTransactions(ut:Boolean) : void
      {
         this._useTransactions = ut;
      }
      
      public function get reconnectPolicy() : String
      {
         return this._reconnectPolicy;
      }
      
      public function get loadOnDemandProperties() : Array
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._loadOnDemandProperties;
      }
      
      public function get allLazyProperties() : Array
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._allLazyProperties;
      }
      
      public function get serializationDescriptor() : SerializationDescriptor
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._serializationDescriptor;
      }
      
      private function initSerializationDescriptors() : void
      {
         var p:* = null;
         var association:ManagedAssociation = null;
         if(this.adapter != null && this.adapter.serializeAssociations)
         {
            return;
         }
         var excludes:Array = new Array();
         var desc:SerializationDescriptor = new SerializationDescriptor();
         var hasExcludes:Boolean = false;
         var updateRefIdsExcludes:Array = null;
         var deleteRefIdsExcludes:Array = null;
         for(p in this._associations)
         {
            association = ManagedAssociation(this._associations[p]);
            hasExcludes = true;
            excludes.push(p);
            if(association.loadOnDemand)
            {
               if(deleteRefIdsExcludes == null)
               {
                  deleteRefIdsExcludes = new Array();
                  deleteRefIdsExcludes.push(Managed.LISTENER_TABLE_KEY);
               }
               deleteRefIdsExcludes.push(p);
            }
            if(association.pagedUpdates && !association.paged)
            {
               if(updateRefIdsExcludes == null)
               {
                  updateRefIdsExcludes = new Array();
                  updateRefIdsExcludes.push(Managed.LISTENER_TABLE_KEY);
               }
               updateRefIdsExcludes.push(p);
            }
         }
         if(updateRefIdsExcludes != null)
         {
            this._updateRefIdsDescriptor = new SerializationDescriptor();
            this._updateRefIdsDescriptor.setExcludes(updateRefIdsExcludes);
         }
         if(deleteRefIdsExcludes != null)
         {
            this._deleteRefIdsDescriptor = new SerializationDescriptor();
            this._deleteRefIdsDescriptor.setExcludes(deleteRefIdsExcludes);
         }
         if(!hasExcludes)
         {
            return;
         }
         excludes.push("referencedIds");
         excludes.push("destination");
         desc.setExcludes(excludes);
         this._serializationDescriptor = desc;
      }
      
      public function getReferencedIdsSerializationDescriptor(isDelete:Boolean) : SerializationDescriptor
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return !!isDelete?this._deleteRefIdsDescriptor:this._updateRefIdsDescriptor;
      }
      
      public function getUID(item:Object) : String
      {
         var prop:String = null;
         var propValue:Object = null;
         var propValueStr:String = null;
         var propValueType:String = null;
         if(!this.isInitialized)
         {
            throw new DataServiceError("DataService error. Configuration not present.");
         }
         var result:String = null;
         if(item == null)
         {
            return result;
         }
         result = "";
         if(item is ObjectProxy)
         {
            item = ObjectProxy(item).object_proxy::object;
         }
         for(var i:int = 0; i < this._identities.length; i++)
         {
            prop = this._identities[i];
            propValue = item[prop];
            if(propValue != null)
            {
               propValueType = typeof propValue;
               switch(propValueType)
               {
                  case "number":
                     if(isNaN(propValue as Number))
                     {
                        propValueStr = null;
                     }
                     else
                     {
                        propValueStr = propValue.toString();
                     }
                     break;
                  case "boolean":
                  case "string":
                  case "xml":
                     propValueStr = propValue.toString();
                     break;
                  default:
                     if(propValue is Date || ((propValueStr = propValue.toString()) == null || propValueStr.indexOf("[object ") == 0))
                     {
                        propValueStr = Managed.toString(propValue);
                     }
               }
               if(this._uidUndefinedValues[i] == propValueStr)
               {
                  result = null;
                  break;
               }
               result = result + propValueStr;
               if(i != this._identities.length - 1)
               {
                  result = result + ",";
               }
            }
         }
         if(!result && "uid" in item)
         {
            return item.uid;
         }
         if(!result)
         {
            return result;
         }
         return !!this._idIsUID?result:this._rootDestination + UID_TYPE_SEPARATOR + result;
      }
      
      public function isUIDProperty(prop:String) : Boolean
      {
         for(var i:int = 0; i < this._identities.length; i++)
         {
            if(this._identities[i] == prop)
            {
               return true;
            }
         }
         return false;
      }
      
      public function isDefaultProperty(propName:String) : Boolean
      {
         var assoc:ManagedAssociation = this._associations[propName] as ManagedAssociation;
         if(assoc == null)
         {
            return true;
         }
         return !assoc.loadOnDemand;
      }
      
      public function isNonAssociatedProperty(propName:String) : Boolean
      {
         var assoc:ManagedAssociation = this._associations[propName] as ManagedAssociation;
         if(assoc == null)
         {
            return true;
         }
         return false;
      }
      
      public function set hierarchicalEventsDefault(hed:Boolean) : void
      {
         var propName:* = null;
         var assoc:ManagedAssociation = null;
         this._hierarchicalEventsDefault = hed;
         for(propName in this._associations)
         {
            assoc = ManagedAssociation(this._associations[propName]);
            if(!assoc.hierarchicalEventsSet)
            {
               assoc.hierarchicalEvents = hed;
            }
         }
      }
      
      public function get hierarchicalEventsDefault() : Boolean
      {
         return this._hierarchicalEventsDefault;
      }
      
      function convertServerToClientReferencedIds(item:Object, referencedIds:Object, ps:PropertySpecifier) : void
      {
         var propName:* = null;
         var assoc:ManagedAssociation = null;
         if(this.needsReferencedIds)
         {
            for(propName in this.associations)
            {
               if(ps.includeProperty(propName))
               {
                  assoc = ManagedAssociation(this._associations[propName]);
                  if(!assoc.lazy && !assoc.paged)
                  {
                     referencedIds[propName] = this.getReferencedIdsForAssoc(assoc,item[propName]);
                  }
               }
            }
         }
      }
      
      function replaceMessageIdsWithIdentities(messageCache:DataMessageCache, refIds:Object) : void
      {
         var propName:* = null;
         var ci:MessageCacheItem = null;
         var assoc:ManagedAssociation = null;
         var ridVal:Object = null;
         var rids:Array = null;
         var i:int = 0;
         if(this.needsReferencedIds)
         {
            for(propName in this.associations)
            {
               assoc = ManagedAssociation(this._associations[propName]);
               ridVal = refIds[assoc.property];
               if(ridVal != null)
               {
                  if(assoc.typeCode == ManagedAssociation.MANY)
                  {
                     rids = ridVal as Array;
                     if(rids != null)
                     {
                        for(i = 0; i < rids.length; i++)
                        {
                           if(rids[i] is String)
                           {
                              ci = messageCache.getAnyCacheItem(rids[i] as String);
                              if(ci != null && ci.newIdentity != null)
                              {
                                 rids[i] = ci.newIdentity;
                              }
                           }
                        }
                     }
                  }
                  else if(ridVal is String)
                  {
                     ci = messageCache.getAnyCacheItem(ridVal as String);
                     if(ci != null && ci.newIdentity != null)
                     {
                        refIds[assoc.property] = ci.newIdentity;
                     }
                  }
               }
            }
         }
      }
      
      function getReferencedIds(item:Object) : Object
      {
         var propName:* = null;
         var assoc:ManagedAssociation = null;
         var propVal:Object = null;
         if(!this.needsReferencedIds)
         {
            return {};
         }
         var referencedIds:Object = new Object();
         for(propName in this.associations)
         {
            assoc = ManagedAssociation(this._associations[propName]);
            propName = assoc.property;
            propVal = item[propName];
            if(!assoc.paged)
            {
               referencedIds[propName] = this.getReferencedIdsForAssoc(assoc,propVal);
            }
         }
         return referencedIds;
      }
      
      function compareReferencedIds(a:Object, b:Object) : Boolean
      {
         var aa:Array = null;
         var ba:Array = null;
         var i:int = 0;
         if(a == b)
         {
            return true;
         }
         if(a == null || b == null)
         {
            return false;
         }
         if(a is Array)
         {
            if(!(b is Array))
            {
               return false;
            }
            aa = a as Array;
            ba = b as Array;
            if(aa.length != ba.length)
            {
               return false;
            }
            for(i = 0; i < aa.length; i++)
            {
               if(!this.compareIdentities(aa[i],ba[i]))
               {
                  return false;
               }
            }
            return true;
         }
         return this.compareIdentities(a,b);
      }
      
      function compareIdentities(a:Object, b:Object) : Boolean
      {
         if(a == b)
         {
            return true;
         }
         if(a is String)
         {
            if(b is String)
            {
               return a == b;
            }
            return false;
         }
         if(b is String)
         {
            return false;
         }
         if(a == null || b == null)
         {
            return false;
         }
         var uids:Array = this.identities;
         for(var i:int = 0; i < uids.length; i++)
         {
            if(a[uids[i]] != b[uids[i]])
            {
               return false;
            }
         }
         return true;
      }
      
      function compareReferencedIdsForAssoc(assoc:ManagedAssociation, propVal1:Object, propRefIds2:Object) : Boolean
      {
         var propAC1:ArrayCollection = null;
         var elem1:Object = null;
         var elem2:Object = null;
         var propArr2:Array = null;
         var j:int = 0;
         if(propVal1 == propRefIds2)
         {
            return true;
         }
         if(propVal1 == null || propRefIds2 == null)
         {
            return false;
         }
         if(assoc.typeCode == ManagedAssociation.MANY)
         {
            propAC1 = ArrayCollection(propVal1);
            if(!propRefIds2 is Array)
            {
               return false;
            }
            propArr2 = propRefIds2 as Array;
            if(propAC1.list.length != propArr2.length)
            {
               return false;
            }
            for(j = 0; j < propAC1.list.length; j++)
            {
               elem1 = propAC1.list.getItemAt(j);
               elem2 = propArr2[j];
               if(!assoc.service.metadata.compareIdentities(elem1,elem2))
               {
                  return false;
               }
            }
            return true;
         }
         return assoc.service.metadata.compareIdentities(propVal1,propRefIds2);
      }
      
      function getReferencedIdsForAssoc(assoc:ManagedAssociation, propVal:Object) : Object
      {
         var propAC:ArrayCollection = null;
         var elem:Object = null;
         var ids:Array = null;
         var propDataList:DataList = null;
         var j:int = 0;
         var idForIndex:Object = null;
         var log:ILogger = null;
         if(assoc.typeCode == ManagedAssociation.MANY)
         {
            propAC = ArrayCollection(propVal);
            ids = [];
            try
            {
               if(propAC)
               {
                  propDataList = propAC.list as DataList;
                  for(j = 0; j < propAC.list.length; j++)
                  {
                     elem = propAC.list.getItemAt(j);
                     if(elem == null)
                     {
                        idForIndex = Boolean(propDataList)?propDataList.getIdentityForIndex(j):null;
                        if(idForIndex)
                        {
                           ids.push(idForIndex);
                        }
                        else
                        {
                           if(Log.isError())
                           {
                              log = Log.getLogger("mx.data.DataService." + this._id);
                              log.error("Collection property: " + assoc.property + " on type: " + this._id + " contains a null element at index: " + j);
                           }
                           ids.push(null);
                        }
                     }
                     else
                     {
                        ids.push(assoc.service.getItemIdentifier(elem));
                     }
                  }
                  return ids;
               }
            }
            catch(ipe:ItemPendingError)
            {
               if(Log.isDebug())
               {
                  assoc.service.log.debug("ItemPendingError trying to get referencedIds from association: " + assoc.property + "[" + j + "]");
               }
            }
            return null;
         }
         if(propVal != null)
         {
            return assoc.service.getItemIdentifier(propVal);
         }
         return null;
      }
      
      function get needsReferencedIds() : Boolean
      {
         if(!this._associationInfoSet)
         {
            this.validateAssociationInfo();
         }
         return this._associationNames != null && this._associationNames.length > 0;
      }
      
      private function applyConfigMetadata(otherMetadata:Metadata) : void
      {
         var log:ILogger = null;
         this._associationInfoSet = false;
         if(Log.isDebug())
         {
            log = Log.getLogger("mx.data.DataService." + this.destination);
            if(otherMetadata != null)
            {
               log.debug("Configuration for destination=\'{0}\':\n\r {1}",this.destination,otherMetadata.toString());
            }
         }
         this._identities = otherMetadata._identities;
         this._uidUndefinedValues = otherMetadata._uidUndefinedValues;
         this.extendsNames = otherMetadata.extendsNames;
         this._associations = otherMetadata._associations;
         this.typeProperty = otherMetadata.typeProperty;
         this._propertyNames = otherMetadata._propertyNames;
         this._associationInfoSet = false;
         this._reconnectPolicy = otherMetadata.reconnectPolicy;
         this._pagingEnabled = otherMetadata._pagingEnabled;
         this._pageSize = otherMetadata._pageSize;
         this._useTransactions = otherMetadata._useTransactions;
         this.itemClass = otherMetadata.itemClass;
         this._createMethodNames = otherMetadata._createMethodNames;
         this._updateMethodNames = otherMetadata._updateMethodNames;
         this._deleteMethodNames = otherMetadata._deleteMethodNames;
         this._fillMethodNames = otherMetadata._fillMethodNames;
         this._getMethodNames = otherMetadata._getMethodNames;
         this._findItemMethodNames = otherMetadata._findItemMethodNames;
         this._methodNameToReturnType = otherMetadata._methodNameToReturnType;
         this._autoSyncEnabled = otherMetadata._autoSyncEnabled;
         this._hierarchicalEventsDefault = otherMetadata._hierarchicalEventsDefault;
         if(this._identities.length != 0 || this.extendsNames != null)
         {
            this._initialized = true;
         }
      }
      
      private function applyConfigSettingsForManagedRemoteService(properties:XMLList) : void
      {
         var entry:XML = null;
         var createMethods:XMLList = null;
         var deleteMethods:XMLList = null;
         var fillMethods:XMLList = null;
         var getMethods:XMLList = null;
         var findItemMethods:XMLList = null;
         var info:XML = null;
         var updateName:String = null;
         var createName:String = null;
         var deleteName:String = null;
         var fillName:String = null;
         var pageSize:String = null;
         var getName:String = null;
         var value:String = null;
         var fiName:String = null;
         var log:ILogger = null;
         var managedEntity:ManagedEntity = null;
         var updateMethods:XMLList = properties.child("update");
         for each(entry in updateMethods)
         {
            updateName = entry.@name.toString();
            this._updateMethodNames.push(updateName);
         }
         createMethods = properties.child("create");
         for each(entry in createMethods)
         {
            createName = entry.@name.toString();
            this._createMethodNames.push(createName);
         }
         deleteMethods = properties.child("deleteMethod");
         for each(entry in deleteMethods)
         {
            deleteName = entry.@name.toString();
            this._deleteMethodNames.push(deleteName);
         }
         fillMethods = properties.child("fill");
         for each(entry in fillMethods)
         {
            fillName = entry.@name.toString();
            this._fillMethodNames.push(fillName);
            this._methodNameToReturnType[fillName] = entry.@returnType.toString();
            pageSize = entry.@pageSize.toString();
            if(pageSize.length > 0)
            {
               this._methodNameToPageSize[fillName] = parseInt(pageSize);
            }
         }
         getMethods = properties.child("get");
         for each(entry in getMethods)
         {
            getName = entry.@name.toString();
            this._getMethodNames.push(getName);
            this._methodNameToReturnType[getName] = entry.@returnType.toString();
            value = entry.@idmap.toString();
            if(value != null && value.length > 0)
            {
               this.identities = value.split(",");
            }
         }
         findItemMethods = properties.child("findItem");
         for each(entry in findItemMethods)
         {
            fiName = entry.@name.toString();
            this._findItemMethodNames.push(fiName);
            this._methodNameToReturnType[fiName] = entry.@returnType.toString();
         }
         this._initialized = true;
         if(Log.isDebug())
         {
            log = Log.getLogger("mx.data.ManagedRemoteService." + this.destination);
            if(properties != null)
            {
               log.debug("Configuration for destination=\'{0}\':\n\r {1}",this.destination,properties);
            }
         }
         var metadata:XMLList = properties.metadata;
         var managedEntites:XMLList = metadata.child("managed-entity");
         for each(info in managedEntites)
         {
            managedEntity = new ManagedEntity(info);
            this._managedEntities.push(managedEntity);
         }
      }
      
      private function applyConfigSettingsForDataService(properties:XMLList) : void
      {
         var info:XML = null;
         var association:ManagedAssociation = null;
         var pageSize:String = null;
         var itemClassName:String = null;
         var uv:XMLList = null;
         var uvs:String = null;
         var log:ILogger = null;
         var paging:XMLList = null;
         var he:String = null;
         var pagedUpdates:String = null;
         var metadata:XMLList = properties.metadata;
         var identities:XMLList = metadata.identity.@property;
         for(var i:uint = 0; i < identities.length(); i++)
         {
            this._identities.push(identities[i].toString());
            uv = metadata.identity[i].attribute("undefined-value");
            if(uv != null)
            {
               uvs = uv.toString();
            }
            else
            {
               uvs = null;
            }
            this._uidUndefinedValues.push(uv.toString());
         }
         this.extendsNames = parseExtendsStr(metadata);
         if(Log.isDebug())
         {
            log = Log.getLogger("mx.data.DataService." + this.destination);
            if(properties != null)
            {
               log.debug("Configuration for destination=\'{0}\':\n\r {1}",this.destination,properties);
            }
         }
         if(identities.length() == 0 && this.extendsNames == null)
         {
            if(Log.isDebug())
            {
               log.debug("No identity properties compiled in - will load config from server");
            }
            return;
         }
         this._initialized = true;
         var associations:XMLList = metadata.children();
         for(i = 0; i < associations.length(); i++)
         {
            info = associations[i];
            if(info.name().toString() != "identity" && info.name().toString() != "extends")
            {
               association = new ManagedAssociation(info);
               he = info.attribute("hierarchical-events").toString();
               if(he.length != 0)
               {
                  association.hierarchicalEvents = he == "true";
               }
               else
               {
                  association.hierarchicalEventsSet = false;
                  association._hierarchicalEvents = this.hierarchicalEventsDefault;
               }
               pageSize = info.attribute("page-size").toString();
               if(pageSize.length != 0)
               {
                  association.pageSize = parseInt(pageSize);
                  if(association.pageSize > 0)
                  {
                     association.loadOnDemand = true;
                  }
               }
               pagedUpdates = info.attribute("paged-updates").toString();
               if(pagedUpdates.length != 0)
               {
                  association.pagedUpdates = pagedUpdates == "true";
               }
               else
               {
                  association.pagedUpdates = association.pageSize > 0;
               }
               if(association.property != null && association.property != "")
               {
                  this._associations[association.property] = association;
               }
               else if(association.destination != null && association.destination != "")
               {
                  this._associations[association.destination] = association;
               }
               else
               {
                  log.debug("Metadata association not properly mapped=\'{0}\'",this.destination);
               }
               if(this._associationNames == null)
               {
                  this._associationNames = [];
               }
               this._associationNames.push(association.property);
               this._hasAssociations = true;
            }
            this._initialized = true;
            paging = properties.network.paging.(@enabled == "true");
            if(paging.length())
            {
               this._pagingEnabled = true;
            }
            if(!this._pageSizeSet)
            {
               pageSize = properties.network.paging.attribute("page-size").toString();
               if(pageSize.length == 0)
               {
                  pageSize = properties.network.paging.attribute("pageSize").toString();
               }
               if(pageSize.length > 0)
               {
                  this._pageSize = parseInt(pageSize);
               }
            }
         }
         itemClassName = properties["item-class"];
         if(!itemClassName)
         {
            itemClassName = properties.attribute("item-class").toString();
         }
         try
         {
            if(!this.itemClass && itemClassName)
            {
               this.itemClass = getClassByAlias(itemClassName);
            }
            if(Log.isDebug())
            {
               log.debug("Mapped server side item-class value: " + itemClassName + " to an AS class: " + this.itemClass);
            }
         }
         catch(re:ReferenceError)
         {
            if(Log.isDebug())
            {
               log.debug("Unable to map server side item-class value: " + itemClassName + " to an AS class.  No AS class with a RemoteClass tag with this value loaded in this SWF?");
            }
         }
      }
      
      private function applyConfigSettings(properties:XMLList) : void
      {
         var isManagedRemoteDestination:Boolean = false;
         var reconnect:XMLList = null;
         var usetrans:XMLList = null;
         var autoSyncEnabled:XMLList = null;
         var serviceUT:XMLList = null;
         if(properties.length() > 0)
         {
            this._associationInfoSet = false;
            isManagedRemoteDestination = properties.@ManagedRemoteDestination == "true";
            if(isManagedRemoteDestination)
            {
               this.applyConfigSettingsForManagedRemoteService(properties);
            }
            else
            {
               this.applyConfigSettingsForDataService(properties);
            }
            reconnect = properties.network.reconnect.@fetch;
            this._reconnectPolicy = Boolean(reconnect.length())?reconnect.toString():FETCH_IDENTITY;
            this.checkReconnect();
            usetrans = properties["use-transactions"];
            if(usetrans.length() == 0)
            {
               try
               {
                  serviceUT = properties.parent().parent().properties["use-transactions"];
                  this._useTransactions = serviceUT.length() == 0 || serviceUT.toString().toLowerCase() != "false";
               }
               catch(e:Error)
               {
                  _useTransactions = true;
               }
            }
            else
            {
               this._useTransactions = usetrans.toString().toLowerCase() != "false";
            }
            autoSyncEnabled = properties["auto-sync-enabled"];
            if(autoSyncEnabled.length() > 0)
            {
               this._autoSyncEnabled = autoSyncEnabled.toString().toLowerCase() != "false";
            }
         }
      }
      
      private function checkReconnect() : void
      {
         var valid:Boolean = false;
         switch(this._reconnectPolicy)
         {
            case FETCH_IDENTITY:
            case FETCH_INSTANCE:
               valid = true;
         }
         if(!valid)
         {
            throw new DataServiceError("Invalid configuration setting for reconnect. Valid options are " + FETCH_IDENTITY + " or " + FETCH_INSTANCE);
         }
      }
      
      function get subTypeNames() : Array
      {
         initSubTypeGraph();
         return subTypeGraph[this.destination];
      }
      
      public function toString() : String
      {
         var i:int = 0;
         var str:String = this.destination;
         if(this.identities == null)
         {
            str = str + " (no identities)";
         }
         else
         {
            str = str + " identities: ";
            for(i = 0; i < this.identities.length; i++)
            {
               if(i != 0)
               {
                  str = str + ",";
               }
               str = str + this.identities[i];
               if(this._uidUndefinedValues != null && this._uidUndefinedValues[i] != null && this._uidUndefinedValues[i].length != 0)
               {
                  str = str + ("(undefined-value=\'" + this._uidUndefinedValues[i] + "\')");
               }
            }
         }
         return str;
      }
      
      public function get id() : String
      {
         return this._id;
      }
   }
}
