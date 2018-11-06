package mx.data
{
   import flash.events.EventDispatcher;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import flash.utils.Timer;
   import mx.collections.ArrayCollection;
   import mx.collections.IList;
   import mx.collections.ListCollectionView;
   import mx.collections.errors.ItemPendingError;
   import mx.data.errors.DataListError;
   import mx.data.errors.DataServiceError;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.Managed;
   import mx.events.CollectionEvent;
   import mx.events.CollectionEventKind;
   import mx.events.PropertyChangeEvent;
   import mx.events.PropertyChangeEventKind;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectProxy;
   import mx.utils.ObjectUtil;
   import mx.utils.UIDUtil;
   import mx.utils.object_proxy;
   
   [ExcludeClass]
   [ResourceBundle("data")]
   public class DataList extends EventDispatcher implements IList, IExternalizable
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      public var fillParameters:Object;
      
      public var fillTimestamp:Date;
      
      public var view:ListCollectionView;
      
      var sequenceIdStale:Boolean;
      
      var sequenceAutoSubscribed:Boolean;
      
      var referenceCount:int = 1;
      
      var updateCollectionReferences:int = 0;
      
      private var _association:ManagedAssociation;
      
      private var _collectionId:Object;
      
      private var _dataService:ConcreteDataService;
      
      private var _deletedUIDs:Object;
      
      var fetched:Boolean;
      
      var cacheStale:Boolean;
      
      var cacheRestored:Boolean = false;
      
      var cacheRestoreAttempted:Boolean = false;
      
      var inCache:Boolean = false;
      
      private var _items:Array;
      
      private var _itemsSize:int = 0;
      
      private var _itemReference:ItemReference = null;
      
      private var _itemRequests:Array;
      
      private var _log:ILogger;
      
      private var _nested:Boolean;
      
      private var _dynamicSizing:Boolean;
      
      private var _pagedList:IPagedList;
      
      private var _pagedMax:int;
      
      private var _pageSize:int = 0;
      
      private var _pageFilled:Boolean = false;
      
      private var _pagingEnabled:Boolean = false;
      
      private var _pageManager:PageManager;
      
      private var _parentItem:Object = null;
      
      private var _parentDataService:ConcreteDataService = null;
      
      private var _queuedUpdateCollections:Array;
      
      private var _sequenceId:int;
      
      private var _smo:Boolean = false;
      
      var singleResult:Boolean = false;
      
      private var _uid:String;
      
      private var _flushPageRequestTimer:Timer = null;
      
      public function DataList(dataService:ConcreteDataService, seqId:int = -1, association:ManagedAssociation = null, parentDataService:ConcreteDataService = null, parentItem:Object = null, subscribed:Boolean = true, transientItem:Boolean = false, fetched:Boolean = true)
      {
         this._items = [];
         super();
         this._uid = null;
         this._dataService = dataService;
         if(!transientItem)
         {
            this._dataService.addDataList(this);
         }
         if(!subscribed)
         {
            this._sequenceId = this._dataService.getNewClientSequenceId();
         }
         else
         {
            this._sequenceId = seqId;
            if(seqId >= 0)
            {
               this.sequenceAutoSubscribed = true;
               this._dataService.autoSubscribe();
            }
         }
         this._nested = association != null;
         this._association = association;
         this._parentItem = parentItem;
         this._parentDataService = parentDataService;
         if(parentItem != null)
         {
            this._parentDataService.addToChildDataListIndex(this);
         }
         this._log = Log.getLogger("mx.data.DataList");
         this.fetched = fetched;
         this.listChanged();
      }
      
      static function objectGetItemIndex(obj:Object, arr:Array) : int
      {
         var n:int = arr.length;
         for(var i:int = 0; i < n; i++)
         {
            if(Managed.compare(arr[i],obj) == 0)
            {
               return i;
            }
         }
         return -1;
      }
      
      public function get length() : int
      {
         if(!this.fetched)
         {
            this.fetchValue();
         }
         return this._itemsSize;
      }
      
      public function get localItems() : Array
      {
         var uid:String = null;
         var item:Object = null;
         var result:Array = [];
         for(var i:int = 0; i < this._items.length; i++)
         {
            uid = this._items[i];
            if(uid != null)
            {
               item = this._dataService.getItem(uid);
               if(item != null)
               {
                  result.push(item);
               }
            }
         }
         return result;
      }
      
      public function hasUnpagedItems() : Boolean
      {
         var uid:String = null;
         if(this._queuedUpdateCollections != null || this._items.length != this._itemsSize)
         {
            return true;
         }
         for(var i:int = 0; i < this._items.length; i++)
         {
            uid = this._items[i];
            if(uid != null)
            {
               if(this._dataService.getItem(uid) == null)
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      public function get uid() : String
      {
         if(this._uid == null)
         {
            this._uid = UIDUtil.createUID();
         }
         return this._uid;
      }
      
      public function set uid(value:String) : void
      {
         this._uid = value;
      }
      
      public function addItem(item:Object) : void
      {
         if(this.incompleteDynamicSizing)
         {
            this.doAddItemAt(item,this._itemsSize - 1,null,null);
         }
         else
         {
            this.doAddItemAt(item,this._itemsSize,null,null);
         }
      }
      
      public function addItemAt(item:Object, index:int) : void
      {
         this.doAddItemAt(item,index,null,null);
      }
      
      public function getItemAt(index:int, prefetch:int = 0) : Object
      {
         var newItems:Array = null;
         var insertLocation:int = 0;
         var i:int = 0;
         this.checkIndex(index);
         if(this._pagedList != null)
         {
            if(index >= this._pagedMax && index < this._pagedList.length)
            {
               newItems = new Array();
               insertLocation = this._pagedMax;
               try
               {
                  for(i = insertLocation; i <= index; i++)
                  {
                     this._pagedMax = i + 1;
                     newItems.push(this._pagedList.getItemAt(i));
                  }
               }
               finally
               {
                  if(newItems.length > 0)
                  {
                     this.processSequence(newItems,this._dataService.includeDefaultSpecifier,insertLocation,null,null,null,false,true,null,null);
                  }
               }
            }
         }
         var item:Object = this.length > 0?this.requestItemAt(index,prefetch):null;
         return item;
      }
      
      public function getItemIndex(item:Object) : int
      {
         var uid:String = IManaged(item).uid;
         return this.getUIDIndex(uid);
      }
      
      public function getUIDIndex(uid:String) : int
      {
         return ArrayUtil.getItemIndex(uid,this._items);
      }
      
      public function itemUpdated(item:Object, property:Object = null, oldValue:Object = null, newValue:Object = null) : void
      {
      }
      
      public function readExternal(input:IDataInput) : void
      {
         this.processSequence(input.readObject() as Array,this._dataService == null?PropertySpecifier.DEFAULT:this._dataService.includeAllSpecifier,0,null);
      }
      
      public function removeAll() : void
      {
         var removedItems:Array = null;
         var oldProperty:Object = null;
         var newProperty:Object = null;
         var colEvent:CollectionEvent = null;
         this.listChanged();
         if(this._association != null && !this._association.pagedUpdates)
         {
            oldProperty = null;
            newProperty = null;
            if(this.referenceCount > 0 && this._parentDataService.logChanges == 0)
            {
               oldProperty = this._parentItem.referencedIds[this._association.property];
               if(oldProperty == null)
               {
                  oldProperty = [];
               }
               removedItems = this.localItems;
               newProperty = [];
               this._parentDataService.dataStore.logUpdate(this._parentDataService,this._parentItem,this._association.property,oldProperty,newProperty,null,false,this._association);
            }
            if(this._parentDataService.dataStore.autoCommitCollectionChanges)
            {
               this._parentDataService.dataStore.doAutoCommit(CommitResponder);
            }
         }
         else
         {
            if(this.referenceCount == 0)
            {
               this._items = [];
               this._itemsSize = 0;
               colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
               colEvent.kind = CollectionEventKind.RESET;
               dispatchEvent(colEvent);
               return;
            }
            removedItems = this._dataService.removeAll(this);
         }
         this.removeAllItemReferences();
         var event:CollectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         event.kind = CollectionEventKind.REMOVE;
         event.items = removedItems;
         event.location = 0;
         dispatchEvent(event);
      }
      
      public function removeItemAt(index:int) : Object
      {
         if(this.length > 0)
         {
            if(this._association != null && !this._association.paged)
            {
               this.requestItemAt(0,this.length);
            }
            else
            {
               this.requestItemAt(index);
            }
         }
         var result:IManaged = this.internalRemoveItemAt(index);
         if(this._dataService.logChanges == 0)
         {
            if(this._dataService.dataStore.autoCommitCollectionChanges)
            {
               this._dataService.dataStore.doAutoCommit(CommitResponder);
            }
         }
         if(result != null)
         {
            if(this._association != null || !this._dataService.deleteItemOnRemoveFromFill)
            {
               this._dataService.releaseItemIfNoDataListReferences(result);
            }
         }
         return result;
      }
      
      function internalRemoveItemAt(index:int, removeSMOs:Boolean = true, remote:Boolean = false) : IManaged
      {
         var result:IManaged = null;
         var oldProperty:Object = null;
         var newProperty:Object = null;
         var useUpdateCollection:Boolean = false;
         var referencedIds:Object = null;
         this.checkIndex(index);
         if(index >= this._items.length)
         {
            if(index >= this._itemsSize)
            {
               throw new DataServiceError("removeItemAt called with out of range index: " + index + " > length: " + this._itemsSize);
            }
            this._itemsSize--;
            return null;
         }
         var uid:String = this._items[index];
         if(this._association != null && !this._association.pagedUpdates)
         {
            oldProperty = null;
            newProperty = null;
            useUpdateCollection = false;
            if(this.referenceCount > 0 && this._parentDataService.logChanges == 0)
            {
               useUpdateCollection = true;
               referencedIds = this._parentItem.referencedIds;
               if(referencedIds == null)
               {
                  oldProperty = [];
               }
               else
               {
                  oldProperty = referencedIds[this._association.property];
               }
               if(oldProperty is Array)
               {
                  newProperty = ObjectUtil.copy(oldProperty);
                  newProperty.splice(index,1);
               }
               else
               {
                  newProperty = null;
               }
            }
            result = this._dataService.getItem(uid);
            this.removeReference(uid,!useUpdateCollection,removeSMOs,remote);
            if(useUpdateCollection)
            {
               this._parentDataService.dataStore.logUpdate(this._parentDataService,this._parentItem,this._association.property,oldProperty,newProperty,null,false,this._association);
            }
         }
         else
         {
            if(uid == null || (result = this._dataService.getItem(uid)) == null)
            {
               result = this.requestItemAt(index);
            }
            if(this._association != null || !this._dataService.deleteItemOnRemoveFromFill)
            {
               this.removeReference(uid,true,removeSMOs,remote);
               if(this.referenceCount > 0 && this._dataService.logChanges == 0)
               {
                  this._dataService.dataStore.logCollectionUpdate(this._dataService,this,UpdateCollectionRange.DELETE_FROM_COLLECTION,index,this._dataService.getItemIdentifier(result),null);
               }
            }
            else
            {
               result = IManaged(this._dataService.removeItem(uid));
            }
         }
         return result;
      }
      
      public function setItemAt(item:Object, index:int) : Object
      {
         if(item == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullItemForSetItemAt"));
         }
         var result:Object = this.removeItemAt(index);
         this.addItemAt(item,index);
         return result;
      }
      
      public function toArray() : Array
      {
         var result:Array = [];
         for(var i:uint = 0; i < this._itemsSize; i++)
         {
            result.push(this.getItemAt(i,i == 0?int(this._itemsSize):int(0)));
         }
         return result;
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         var uid:String = null;
         var items:Array = [];
         for(var i:uint = 0; i < this._items.length; i++)
         {
            uid = this._items[i];
            if(uid != null)
            {
               items.push(this._dataService.getItemForReference(uid,false));
            }
         }
         output.writeObject(items);
      }
      
      function get association() : ManagedAssociation
      {
         return this._association;
      }
      
      function get collectionId() : Object
      {
         var newIdentity:Object = null;
         var cacheId:Boolean = false;
         var collId:Object = null;
         if(this._nested)
         {
            if(this._collectionId == null)
            {
               newIdentity = this._parentDataService.dataStore.messageCache.getCreateMessageIdentity(this._parentDataService,this._parentItem);
               cacheId = true;
               if(newIdentity != null)
               {
                  cacheId = false;
               }
               else
               {
                  newIdentity = this._parentDataService.getIdentityMap(this._parentItem);
               }
               collId = {
                  "parent":this._parentDataService.destination,
                  "id":this._parentDataService.getItemIdentifier(this._parentItem),
                  "prop":this.association.property
               };
               if(cacheId)
               {
                  this._collectionId = collId;
               }
               return collId;
            }
            return this._collectionId;
         }
         return this.fillParameters;
      }
      
      function get dynamicSizing() : Boolean
      {
         return this._dynamicSizing;
      }
      
      function get incompleteDynamicSizing() : Boolean
      {
         return this._dynamicSizing && (this._itemsSize != this._items.length || this._items.length > 0 && this._items[this._items.length - 1] == null);
      }
      
      function set dynamicSizing(value:Boolean) : void
      {
         this._dynamicSizing = value;
      }
      
      function set itemReference(value:ItemReference) : void
      {
         this._itemReference = value;
         value._dataList = this;
      }
      
      function get itemReference() : ItemReference
      {
         return this._itemReference;
      }
      
      public function set pagedList(pl:IPagedList) : void
      {
         this._pagedList = pl;
         this.setSequenceSize(pl.length);
         this._pagedMax = 0;
         this.fetched = true;
         var colEvent:CollectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         colEvent.kind = CollectionEventKind.RESET;
         dispatchEvent(colEvent);
      }
      
      public function get pagedList() : IPagedList
      {
         return this._pagedList;
      }
      
      function get pageSize() : int
      {
         if(this._pageSize != 0)
         {
            return this._pageSize;
         }
         if(this._association != null)
         {
            return this._association.pageSize;
         }
         return this._dataService.pageSize;
      }
      
      function set pageSize(ps:int) : void
      {
         this._pageSize = ps;
      }
      
      function get pagedInSize() : int
      {
         for(var i:int = this._items.length - 1; i >= 0; i--)
         {
            if(this._items[i] != null)
            {
               return i + 1;
            }
         }
         return 0;
      }
      
      function get parentDataService() : ConcreteDataService
      {
         return this._parentDataService;
      }
      
      function get parentItem() : Object
      {
         return this._parentItem;
      }
      
      function get localReferences() : Array
      {
         var uid:String = null;
         var result:Array = [];
         for(var i:int = 0; i < this._items.length; i++)
         {
            uid = this._items[i];
            if(uid != null)
            {
               result.push(uid);
            }
         }
         return result;
      }
      
      function get isSynchronizeSupported() : Boolean
      {
         return this.ensureSynchronizeSupported(false);
      }
      
      function ensureSynchronizeSupported(throwErrorIfUnSupported:Boolean = true) : Boolean
      {
         var error:String = null;
         if(this.association || this._pagingEnabled || this.smo || this._nested || !(this.fillParameters is Array))
         {
            error = resourceManager.getString("data","cannotSynchronizeFill");
         }
         else if(this.view == null)
         {
            error = resourceManager.getString("data","nullViewInputForFill");
         }
         if(error)
         {
            if(throwErrorIfUnSupported)
            {
               throw new Error(error);
            }
            return false;
         }
         return true;
      }
      
      function get references() : Array
      {
         return this._items;
      }
      
      function set references(value:Array) : void
      {
         this.setReferences(value,true);
      }
      
      function setReferences(value:Array, applyPending:Boolean = false) : void
      {
         this.fetched = true;
         this.listChanged();
         this.removeAllItemReferences();
         this._items = value;
         this._itemsSize = this._items.length;
         for(var i:int = 0; i < value.length; i++)
         {
            if(value[i] != null)
            {
               this._dataService.addDataListIndexEntry(this,value[i]);
            }
         }
         if(applyPending)
         {
            this.applyPendingUpdateCollections(false,false,false);
         }
         var colEvent:CollectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         colEvent.kind = CollectionEventKind.RESET;
         dispatchEvent(colEvent);
      }
      
      function releaseDataList(replaceData:Boolean, clear:Boolean) : Array
      {
         return this._dataService.releaseDataList(this,replaceData,clear,new Dictionary(),null,false,true);
      }
      
      function requestItemAt(index:uint, prefetch:int = 0, prevError:ItemPendingError = null, refresh:Boolean = false, tokens:Array = null, staleReferences:Object = null) : IManaged
      {
         var request:PageRequest = null;
         var result:IManaged = null;
         var newRequests:Array = null;
         var lowerBound:int = 0;
         var upperBound:int = 0;
         var tmpPageSize:uint = 0;
         var bounds:Object = null;
         var i:int = 0;
         var requests:Array = null;
         var resident:Boolean = false;
         var created:Boolean = false;
         var pageIndex:int = 0;
         var newRequest:PageRequest = null;
         var j:int = 0;
         var token:AsyncToken = null;
         var usePageSize:int = 0;
         var identity:Object = null;
         var neededIds:Array = null;
         var itemUID:String = null;
         var itemResident:Boolean = false;
         var error:ItemPendingError = prevError;
         var tempIndex:uint = index;
         var uid:String = this._items[tempIndex];
         if(!refresh && uid != null && (prefetch == 0 || !this.pagingEnabled || ConcreteDataService.pagingDisabled > 0))
         {
            result = this._dataService.getCreatedOrCachedItem(uid);
            if(result != null)
            {
               return result;
            }
         }
         if(ConcreteDataService.pagingDisabled > 0)
         {
            return null;
         }
         if(this.referenceCount == 0)
         {
            if(Log.isDebug())
            {
               this._log.debug("Attempt to access a non-resident item through a released/deleted managed reference of type " + (this.association != null?"association":this.itemReference == null?"fill":"getItem") + " with detail \'" + Managed.toString(this.collectionId) + "\' on destination " + this._dataService.destination + "  Call stack where invalid reference was made: " + new DataServiceError("to get stack trace").getStackTrace());
            }
            return null;
         }
         this.enablePaging();
         if(this.pagingEnabled)
         {
            newRequests = [];
            if(prevError == null)
            {
               if(!refresh && !this.checkRequestIntegrity(index,prefetch))
               {
                  return null;
               }
            }
            tmpPageSize = this.pageSize;
            if(tmpPageSize == 0)
            {
               tmpPageSize = 20;
               prefetch = this._itemsSize;
               tempIndex = 0;
            }
            bounds = this.getPrefetchBounds(tempIndex,prefetch);
            lowerBound = bounds.lowerBound;
            upperBound = bounds.upperBound;
            i = lowerBound;
            while(i < upperBound)
            {
               uid = i < this._items.length?this._items[i]:null;
               created = false;
               if(uid != null)
               {
                  if(this._dataService.getItemForReference(uid) != null)
                  {
                     resident = true;
                  }
                  else if(this._dataService.dataStore.messageCache.getCreatedItem(this._dataService,uid) != null)
                  {
                     resident = true;
                     created = true;
                  }
               }
               else
               {
                  resident = false;
               }
               if(refresh && resident && !created || !refresh && !resident)
               {
                  pageIndex = this.calculateIndex(i);
                  if(pageIndex >= 0)
                  {
                     request = new PageRequest(this._sequenceId >= 0,pageIndex,tmpPageSize,null);
                     newRequests.push(request);
                  }
                  i = Math.floor(i / tmpPageSize) * tmpPageSize + tmpPageSize;
               }
               else
               {
                  i++;
               }
            }
            if(this._itemsSize == 0 && refresh)
            {
               request = new PageRequest(this._sequenceId >= 0,0,tmpPageSize,null);
               newRequests.push(request);
            }
            requests = this._pageManager.requests;
            if(requests.length > 0)
            {
               for(i = 0; i < newRequests.length; i++)
               {
                  newRequest = PageRequest(newRequests[i]);
                  for(j = 0; j < requests.length; j++)
                  {
                     request = requests[j];
                     if(!request.released)
                     {
                        if(request.includesPageRequest(newRequest))
                        {
                           break;
                        }
                     }
                  }
                  if(j != requests.length)
                  {
                     newRequests.splice(i,1);
                     i--;
                     if(i == newRequests.length - 1)
                     {
                        if(error == null)
                        {
                           error = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
                        }
                        request.addPendingError(error);
                     }
                  }
               }
            }
            for(i = 0; i < newRequests.length; i++)
            {
               request = PageRequest(newRequests[i]);
               requests.push(request);
               token = this._dataService.processPageRequest(request,this);
               if(tokens != null)
               {
                  tokens.push(token);
               }
            }
            if(newRequests.length > 0)
            {
               if(error == null)
               {
                  error = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
               }
               request.addPendingError(error);
            }
            if(prevError == null)
            {
               if(error != null)
               {
                  if(this._dataService.throwItemPendingErrors && !refresh)
                  {
                     throw error;
                  }
                  return null;
               }
               return this._dataService.getItem(this._items[index]);
            }
            return null;
         }
         if(this._nested)
         {
            if(!this.fetched)
            {
               if(!refresh)
               {
                  this.fetchValue(tokens);
               }
               return null;
            }
            if(staleReferences != null && !this.association.lazy)
            {
               return null;
            }
            usePageSize = this._dataService.pageSize;
            if(usePageSize == 0)
            {
               usePageSize = this._itemsSize;
            }
            identity = this.getIdentityForIndex(index);
            error = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
            if((request = this._pageManager.getPendingRequest(identity)) != null)
            {
               if(this._dataService.throwItemPendingErrors && !refresh)
               {
                  request.addPendingError(error);
                  throw error;
               }
               return null;
            }
            lowerBound = Math.floor(index / usePageSize) * usePageSize;
            upperBound = lowerBound + usePageSize;
            if(upperBound > this._itemsSize)
            {
               upperBound = this._itemsSize;
            }
            if(staleReferences != null)
            {
               staleReferences[this._items[i]] = true;
               neededIds = null;
            }
            else
            {
               neededIds = [identity];
            }
            i = lowerBound;
            while(i < upperBound && (neededIds == null || neededIds.length < usePageSize))
            {
               itemUID = this._items[i];
               if(!(itemUID == null || i == index))
               {
                  itemResident = this._dataService.getItemForReference(itemUID) != null;
                  if(refresh && itemResident || !refresh && !itemResident)
                  {
                     identity = this.getIdentityForIndex(i);
                     if(this._pageManager.getPendingRequest(identity) == null)
                     {
                        if(staleReferences != null)
                        {
                           staleReferences[this._items[i]] = true;
                        }
                        else
                        {
                           neededIds.push(identity);
                        }
                     }
                  }
               }
               i++;
            }
            if(neededIds != null)
            {
               request = new PageRequest(this._sequenceId >= 0,0,0,neededIds);
               this._pageManager.requests.push(request);
               token = this._dataService.processPageRequest(request,this);
               if(tokens != null)
               {
                  tokens.push(token);
               }
            }
            if(this._dataService.throwItemPendingErrors && !refresh)
            {
               request.addPendingError(error);
               throw error;
            }
            return null;
         }
         if(refresh)
         {
            return null;
         }
         if(this._pageManager != null && (request = this._pageManager.getPendingRequestForUID(this._dataService,uid)) != null)
         {
            if(this._dataService.throwItemPendingErrors)
            {
               error = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
               request.addPendingError(error);
               throw error;
            }
         }
         return null;
      }
      
      function get pagingEnabled() : Boolean
      {
         return this._association == null?!this.smo && this._pagingEnabled:Boolean(this._association.paged);
      }
      
      function get sequenceId() : int
      {
         return this._sequenceId;
      }
      
      function set sequenceId(value:int) : void
      {
         this._sequenceId = value;
      }
      
      function get service() : ConcreteDataService
      {
         return this._dataService;
      }
      
      function get smo() : Boolean
      {
         return this._smo;
      }
      
      function set smo(value:Boolean) : void
      {
         this._smo = value;
      }
      
      function addReferenceAt(uid:String, identity:Object, index:uint, doRefIds:Boolean = true) : uint
      {
         var referencedIdTable:Object = null;
         var referencedIds:Object = null;
         if(this._association != null && !this._association.paged && doRefIds)
         {
            referencedIdTable = this._parentItem.referencedIds;
            if(referencedIdTable != null)
            {
               referencedIds = referencedIdTable[this._association.property];
            }
            if(referencedIds != null && identity == null)
            {
               throw new DataServiceError(resourceManager.getString("data","noIdentityInAddReferenceAt",[uid]));
            }
         }
         this.addItemReferenceAt(uid,index);
         if(index == this.length)
         {
            if(doRefIds && referencedIds != null)
            {
               if(this._association.typeCode == ManagedAssociation.ONE)
               {
                  referencedIdTable[this._association.property] = identity;
               }
               else
               {
                  referencedIds.push(identity);
               }
            }
         }
         else if(doRefIds && referencedIds != null)
         {
            if(this._association.typeCode == ManagedAssociation.ONE)
            {
               referencedIdTable[this._association.property] = identity;
            }
            else
            {
               referencedIds.splice(index,0,identity);
            }
         }
         return index;
      }
      
      function applyPendingUpdateCollections(revert:Boolean, sendEvents:Boolean, doMerge:Boolean) : void
      {
         var updateCollections:Array = null;
         var i:int = 0;
         if(!this.smo && (this._association == null || this._association.pagedUpdates))
         {
            updateCollections = this._dataService.dataStore.messageCache.getPendingUpdateCollections(this._dataService.destination,this.collectionId);
            if(revert)
            {
               for(i = updateCollections.length - 1; i >= 0; i--)
               {
                  this.applyUpdateCollection(updateCollections[i],true,sendEvents,true);
               }
            }
            else
            {
               for(i = 0; i < updateCollections.length; i++)
               {
                  this.applyUpdateCollection(updateCollections[i],false,sendEvents,true);
               }
            }
            if(doMerge)
            {
               updateCollections = this._dataService.dataStore.getUnmergedUpdateCollectionMessages(this._dataService.destination,this.collectionId);
               if(revert)
               {
                  for(i = 0; i < updateCollections.length; i++)
                  {
                     this.applyUpdateCollection(updateCollections[i],false,sendEvents);
                  }
               }
               else
               {
                  for(i = updateCollections.length - 1; i >= 0; i--)
                  {
                     this.applyUpdateCollection(updateCollections[i],true,sendEvents);
                  }
               }
            }
         }
      }
      
      private function get prefetchUpdateCollections() : Boolean
      {
         return !this.pagingEnabled && (this._association == null || !this._association.lazy);
      }
      
      private function prefetchUpdateCollection(ucmsg:UpdateCollectionMessage, fetch:Boolean) : Boolean
      {
         var uid:String = null;
         var range:UpdateCollectionRange = null;
         var idx:int = 0;
         var identity:Object = null;
         var token:AsyncToken = null;
         var rangeArray:Array = ucmsg.body as Array;
         var missing:Array = null;
         for(var r:int = 0; r < rangeArray.length; r++)
         {
            range = UpdateCollectionRange(rangeArray[r]);
            if(range.updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
            {
               for(idx = 0; idx < range.identities.length; idx++)
               {
                  identity = range.identities[idx];
                  if(identity is String)
                  {
                     uid = identity as String;
                  }
                  else
                  {
                     uid = this._dataService.metadata.getUID(identity);
                  }
                  if(!(this._deletedUIDs != null && this._deletedUIDs[uid]))
                  {
                     if(this._dataService.getPendingItem(uid,false) == null)
                     {
                        if(missing == null)
                        {
                           missing = new Array();
                        }
                        missing.push(identity);
                     }
                  }
               }
            }
         }
         if(missing != null)
         {
            if(fetch)
            {
               token = this.pageIn(missing);
               token.addResponder(new AsyncResponder(this.pendingUCResult,this.pendingUCFault,null));
            }
            return false;
         }
         return true;
      }
      
      private function pendingUCResult(data:Object, token:Object) : void
      {
         this.checkPendingUCs(false);
      }
      
      private function pendingUCFault(data:Object, token:Object) : void
      {
         var timer:Timer = null;
         if(this.referenceCount > 0)
         {
            timer = new Timer(5000);
            timer.addEventListener(TimerEvent.TIMER,this.refetchPendingUCs);
            timer.start();
         }
      }
      
      private function refetchPendingUCs(timerEvent:TimerEvent) : void
      {
         if(this.referenceCount > 0)
         {
            this.checkPendingUCs(true);
         }
      }
      
      private function checkPendingUCs(fetch:Boolean) : void
      {
         var ucmsg:UpdateCollectionMessage = null;
         while(this._queuedUpdateCollections != null && this._queuedUpdateCollections.length > 0)
         {
            ucmsg = this._queuedUpdateCollections[0];
            if(this.prefetchUpdateCollection(ucmsg,fetch))
            {
               if(Log.isDebug())
               {
                  this._log.debug("Processed and applied a queued update collection: " + ucmsg.messageId);
               }
               this._queuedUpdateCollections.splice(0,1);
               if(this._queuedUpdateCollections.length == 0)
               {
                  this._queuedUpdateCollections = null;
               }
               this.processUpdateCollection(ucmsg,null,null,false);
               continue;
            }
            return;
         }
         this._queuedUpdateCollections = null;
      }
      
      function processUpdateCollection(newucmsg:UpdateCollectionMessage, origucmsg:UpdateCollectionMessage, serverOverride:UpdateCollectionMessage, queuePending:Boolean = true) : void
      {
         if(queuePending && this.prefetchUpdateCollections && newucmsg != null && (!this.prefetchUpdateCollection(newucmsg,true) || this._queuedUpdateCollections != null))
         {
            if(this._queuedUpdateCollections == null)
            {
               this._queuedUpdateCollections = new Array();
            }
            this._queuedUpdateCollections.push(newucmsg);
            if(Log.isDebug())
            {
               this._log.debug("Update collection refers to pending items on a lazy=false collection.  Fetching those items and queuing the collection: " + newucmsg.messageId);
            }
            return;
         }
         this.applyPendingUpdateCollections(true,true,false);
         if(serverOverride != null)
         {
            this.applyUpdateCollection(serverOverride,true,true);
         }
         if(newucmsg != null)
         {
            this.applyUpdateCollection(newucmsg,false,true,false,true);
         }
         this.applyPendingUpdateCollections(false,true,false);
      }
      
      function applyUpdateCollection(ucmsg:UpdateCollectionMessage, revert:Boolean = false, sendChangeEvents:Boolean = false, localChange:Boolean = false, isServerPush:Boolean = false) : void
      {
         var colEvent:CollectionEvent = null;
         var rangeArray:Array = null;
         var r:int = 0;
         var range:UpdateCollectionRange = null;
         var idx:int = 0;
         var newItemsSize:int = 0;
         var i:int = 0;
         var j:int = 0;
         var ignoreRemoveFromFillConflicts:Boolean = false;
         var oldItemsSize:int = 0;
         var sizeDiff:int = 0;
         var cp2:int = 0;
         var cp3:int = 0;
         if(!this.fetched)
         {
            return;
         }
         this.listChanged();
         this._dataService.disableLogging();
         try
         {
            rangeArray = ucmsg.body as Array;
            newItemsSize = -100;
            for(i = 0; i < rangeArray.length; i++)
            {
               if(revert)
               {
                  r = rangeArray.length - i - 1;
               }
               else
               {
                  r = i;
               }
               range = UpdateCollectionRange(rangeArray[r]);
               if(range.updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION || range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION)
               {
                  for(j = 0; j < range.identities.length; j++)
                  {
                     if(revert)
                     {
                        idx = range.identities.length - j - 1;
                     }
                     else
                     {
                        idx = j;
                     }
                     ignoreRemoveFromFillConflicts = this._dataService.consumer.clientId == ucmsg.clientId;
                     this.applyUpdateCollectionRangeIndex(range,idx,revert,sendChangeEvents,localChange,ignoreRemoveFromFillConflicts);
                  }
               }
               else if(range.updateType == UpdateCollectionRange.INCREMENT_COLLECTION_SIZE)
               {
                  if(!this.dynamicSizing)
                  {
                     this._itemsSize = this._itemsSize + range.size;
                     if(sendChangeEvents)
                     {
                        this.internalDispatchOneAddRemoveEvent(CollectionEventKind.ADD,null,this.length);
                     }
                  }
               }
               else if(range.updateType == UpdateCollectionRange.DECREMENT_COLLECTION_SIZE)
               {
                  if(!this.dynamicSizing)
                  {
                     this._itemsSize = this._itemsSize - range.size;
                     if(sendChangeEvents)
                     {
                        colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                        colEvent.items.push(null);
                        colEvent.kind = CollectionEventKind.REMOVE;
                        colEvent.location = this.length;
                        dispatchEvent(colEvent);
                     }
                  }
               }
               else if(range.updateType == UpdateCollectionRange.UPDATE_COLLECTION_SIZE)
               {
                  newItemsSize = range.size;
               }
               else
               {
                  if(Log.isError())
                  {
                     this._log.error("Unsupported Collection Range Type Received: " + range.updateType);
                  }
                  throw new DataServiceError("Unsupported Collection Range Type Received: " + range.updateType);
               }
            }
            if(newItemsSize != -100)
            {
               oldItemsSize = this._itemsSize;
               this._itemsSize = newItemsSize;
               sizeDiff = oldItemsSize - this._itemsSize;
               if(sendChangeEvents && sizeDiff != 0)
               {
                  colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                  if(sizeDiff > 0)
                  {
                     for(cp2 = 0; cp2 < sizeDiff; cp2++)
                     {
                        colEvent.items.push(null);
                     }
                     colEvent.kind = CollectionEventKind.REMOVE;
                     colEvent.location = this._itemsSize;
                  }
                  else
                  {
                     for(cp3 = 0; cp3 < -sizeDiff; cp3++)
                     {
                        colEvent.items.push(null);
                     }
                     colEvent.kind = CollectionEventKind.ADD;
                     colEvent.location = oldItemsSize;
                  }
                  this.internalDispatchCollectionEvent(colEvent);
               }
            }
         }
         finally
         {
            this._dataService.enableLogging();
         }
      }
      
      function applyUpdateCollectionRangeIndex(range:UpdateCollectionRange, idx:int, revert:Boolean, sendChangeEvents:Boolean, localChange:Boolean, ignoreRemoveFromFillConflict:Boolean = false) : void
      {
         var colEvent:CollectionEvent = null;
         var identity:Object = null;
         var uid:String = null;
         var item:Object = null;
         var position:int = 0;
         var currentIdx:int = 0;
         var olen:int = 0;
         var cp:int = 0;
         var localChangeObject:IChangeObject = null;
         var conflict:DataErrorMessage = null;
         var callBackArgs:Array = null;
         var conflictDetails:RemoveFromFillConflictDetails = null;
         var res:Object = null;
         var newUID:String = null;
         identity = range.identities[idx];
         var isInsert:Boolean = !revert && range.updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION || revert && range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION;
         if(identity is String)
         {
            uid = identity as String;
         }
         else
         {
            uid = this._dataService.metadata.getUID(identity);
         }
         if(this._deletedUIDs != null && this._deletedUIDs[uid])
         {
            delete this._deletedUIDs[uid];
            return;
         }
         item = this._dataService.getItem(uid);
         position = range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION?int(range.position):int(range.position + idx);
         currentIdx = this.getUIDIndex(uid);
         if(currentIdx != -1 && position != currentIdx && Log.isDebug())
         {
            this._log.debug("Warning: " + (!!revert?"reverting":"applying") + " update collection with mismatch positions.  range position: " + position + " != " + currentIdx);
         }
         if(isInsert)
         {
            if(currentIdx == -1)
            {
               if(position > this.length)
               {
                  if(this.dynamicSizing)
                  {
                     return;
                  }
                  if(localChange)
                  {
                     position = this.length;
                  }
                  if(sendChangeEvents)
                  {
                     this._pagingEnabled = true;
                     olen = this.length;
                     colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                     for(cp = olen; cp < position; cp++)
                     {
                        this.addReferenceAt(uid,item,cp);
                        colEvent.items.push(item);
                     }
                     colEvent.kind = CollectionEventKind.ADD;
                     colEvent.location = olen;
                     this.internalDispatchCollectionEvent(colEvent);
                  }
               }
               else
               {
                  if(position > this._items.length && !this.dynamicSizing)
                  {
                     this._itemsSize++;
                     if(sendChangeEvents)
                     {
                        this.internalDispatchOneAddRemoveEvent(CollectionEventKind.ADD,null,this.length);
                     }
                     return;
                  }
                  if(position > 0 && this._items[position - 1] == null && position < this._items.length && this._items[position + 1] == null)
                  {
                     this.addReferenceAt(uid,item,position);
                     if(sendChangeEvents)
                     {
                        this.internalDispatchOneAddRemoveEvent(CollectionEventKind.ADD,item,position);
                     }
                     return;
                  }
                  if(this.incompleteDynamicSizing && position >= this._itemsSize - 1)
                  {
                     return;
                  }
               }
               this.addReferenceAt(uid,identity,position);
               if(item == null && !revert && !(identity is String))
               {
                  this.pageIn([identity]);
               }
               if(sendChangeEvents)
               {
                  this.internalDispatchOneAddRemoveEvent(CollectionEventKind.ADD,item,position);
               }
            }
         }
         else
         {
            if(item != null)
            {
               localChangeObject = this._dataService.getLocalChange(uid,item);
               if(!ignoreRemoveFromFillConflict && localChangeObject != null && this._dataService.conflicts.getConflict(item) == null)
               {
                  this._dataService.conflictDetector.checkRemoveFromFill(localChangeObject,this.fillParameters);
                  conflict = localChangeObject.getConflict();
                  if(conflict != null)
                  {
                     conflict.serverObject = null;
                     callBackArgs = new Array();
                     callBackArgs.push(range);
                     callBackArgs.push(idx);
                     callBackArgs.push(revert);
                     callBackArgs.push(sendChangeEvents);
                     callBackArgs.push(localChange);
                     callBackArgs.push(true);
                     conflictDetails = new RemoveFromFillConflictDetails(this.applyUpdateCollectionRangeIndex,callBackArgs,this);
                     conflict.removeFromFillConflictDetails = conflictDetails;
                     this._dataService.dataStore.processConflict(this._dataService,conflict,null);
                     return;
                  }
               }
            }
            if(currentIdx == -1 && uid is String)
            {
               res = this.service.dataStore.messageCache.getCreatedItem(this.service,uid);
               if(res != null)
               {
                  newUID = this._dataService.metadata.getUID(res);
                  currentIdx = this.getUIDIndex(uid);
               }
            }
            if(position >= this._items.length && this._pageFilled)
            {
               if(this.incompleteDynamicSizing || position >= this._itemsSize)
               {
                  return;
               }
               this._itemsSize--;
               if(sendChangeEvents)
               {
                  colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                  colEvent.items.push(null);
                  colEvent.location = this.length;
                  colEvent.kind = CollectionEventKind.REMOVE;
                  dispatchEvent(colEvent);
               }
            }
            else if(currentIdx != -1 || this._items[position] == null)
            {
               if(currentIdx == -1)
               {
                  currentIdx = position;
               }
               if(currentIdx < this._items.length || !this.incompleteDynamicSizing)
               {
                  this.removeReferenceAt(currentIdx,true,true);
                  if(sendChangeEvents)
                  {
                     colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                     colEvent.kind = CollectionEventKind.REMOVE;
                     colEvent.location = currentIdx;
                     colEvent.items.push(item);
                     dispatchEvent(colEvent);
                  }
               }
            }
         }
      }
      
      function releaseItemsFromUpdateCollection(ucmsg:UpdateCollectionMessage, revert:Boolean) : void
      {
         var range:UpdateCollectionRange = null;
         var identity:Object = null;
         var item:Object = null;
         var uid:String = null;
         var j:int = 0;
         var rangeArray:Array = ucmsg.body as Array;
         for(var r:int = 0; r < rangeArray.length; r++)
         {
            range = UpdateCollectionRange(rangeArray[r]);
            if(!revert && range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION || revert && range.updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
            {
               for(j = 0; j < range.identities.length; j++)
               {
                  identity = range.identities[j];
                  if(identity is String)
                  {
                     uid = identity as String;
                  }
                  else
                  {
                     uid = this._dataService.metadata.getUID(identity);
                  }
                  item = this._dataService.getItem(uid);
                  if(item != null)
                  {
                     this._dataService.releaseItemIfNoDataListReferences(IManaged(item));
                  }
               }
            }
         }
      }
      
      function releaseItemsFromCollection(startIndex:int, numberOfRows:int) : int
      {
         var item:IManaged = null;
         if(this._association != null && !this._association.paged && (startIndex != 0 || numberOfRows != this.length))
         {
            throw new DataServiceError("Can\'t release a subset of items from a collection association property where paging is not enabled: " + this._dataService.destination + "." + this._association.property);
         }
         var max:int = startIndex + numberOfRows;
         var ct:int = 0;
         var i:int = startIndex;
         while(i < max && i < this._items.length)
         {
            if(this._items[i] != null)
            {
               item = this._dataService.getItem(this._items[i]);
               if(this._association == null || this._association.paged)
               {
                  this.replaceReferenceAt(null,i);
                  if(item != null)
                  {
                     ct++;
                     this._dataService.releaseItemIfNoDataListReferences(item);
                  }
               }
               else
               {
                  ct++;
                  this._dataService.removeItemFromCache(item.uid);
               }
            }
            i++;
         }
         if(this._pageManager != null)
         {
            this._pageManager.releaseRequests(startIndex,numberOfRows);
         }
         return ct;
      }
      
      function clear() : void
      {
         this.removeAllItemReferences();
      }
      
      function compareIndexes(remoteIndex:int, localIndex:int) : int
      {
         return remoteIndex - localIndex;
      }
      
      function doAddItemAt(item:Object, index:int, referencedIds:Object, pendingItems:Object) : void
      {
         var id:Object = null;
         var oldProperty:Object = null;
         var newProperty:Object = null;
         var childMessage:DataMessage = null;
         this.checkIndex(index);
         if(item == null)
         {
            throw new ArgumentError(resourceManager.getString("data","nullItemForDoAddItemAt"));
         }
         var info:Object = this._dataService.addItem(item,DataMessage.CREATE_OPERATION,false,true,referencedIds,pendingItems);
         var uid:String = info.uid;
         if(this.getUIDIndex(uid) != -1)
         {
            throw new DataListError(resourceManager.getString("data","identityNotUnique",[uid]));
         }
         var item:Object = this._dataService.getItem(uid);
         if(this._association != null && !this._association.pagedUpdates)
         {
            if(this._association.paged && this.length > 0)
            {
               this.requestItemAt(0,this.length);
            }
            oldProperty = null;
            newProperty = null;
            if(this._parentDataService.logChanges == 0)
            {
               oldProperty = this._parentItem.referencedIds[this._association.property];
               newProperty = ObjectUtil.copy(oldProperty);
               if(newProperty == null)
               {
                  newProperty = [];
               }
            }
            this.addItemReferenceAt(uid,index);
            if(index == this.length)
            {
               if(this._parentDataService.logChanges == 0)
               {
                  id = this._dataService.getItemIdentifier(item);
                  if(this._association.typeCode == ManagedAssociation.MANY)
                  {
                     newProperty.push(id);
                  }
                  else
                  {
                     newProperty = id;
                  }
               }
            }
            else if(this._parentDataService.logChanges == 0)
            {
               newProperty.splice(index,0,this._dataService.getItemIdentifier(item));
            }
            if(this.referenceCount > 0 && this._parentDataService.logChanges == 0)
            {
               childMessage = !!this.association.readOnly?null:this._parentDataService.dataStore.messageCache.getLastUncommittedMessage(this.association.service,uid);
               if(childMessage != null && (childMessage.operation != DataMessage.CREATE_OPERATION && childMessage.operation != DataMessage.CREATE_AND_SEQUENCE_OPERATION))
               {
                  childMessage = null;
               }
               this._parentDataService.dataStore.logUpdate(this._parentDataService,this._parentItem,this._association.property,oldProperty,newProperty,childMessage,false,this._association);
               if(this._parentDataService.dataStore.autoCommitCollectionChanges)
               {
                  this._parentDataService.dataStore.doAutoCommit(CommitResponder);
               }
            }
            if(index == 0 && this._association.typeCode == ManagedAssociation.ONE && this._parentItem != null && item != null)
            {
               this._parentDataService.disableLogging();
               try
               {
                  if(this._association.lazy)
                  {
                     this._parentItem.referencedIds[this._association.property] = newProperty;
                  }
                  this._parentItem[this._association.property] = item;
               }
               finally
               {
                  this._parentDataService.enableLogging();
               }
            }
         }
         else
         {
            if(this._association == null || this._association.paged)
            {
               if(this._dataService.logChanges == 0)
               {
                  id = this._dataService.getItemIdentifier(item);
               }
               this.addItemReferenceAt(uid,index);
            }
            else
            {
               id = this._dataService.getItemIdentifier(item);
               this.addReferenceAt(uid,id,index);
            }
            if(this._dataService.logChanges == 0)
            {
               this._dataService.dataStore.logCollectionUpdate(this._dataService,this,UpdateCollectionRange.INSERT_INTO_COLLECTION,index,id,item);
               if(this._dataService.dataStore.autoCommitCollectionChanges)
               {
                  this._dataService.dataStore.doAutoCommit(CommitResponder);
               }
            }
         }
         this.internalDispatchOneAddRemoveEvent(CollectionEventKind.ADD,item,index);
         this.updatePendingRequests(index,CollectionEventKind.ADD);
      }
      
      private function internalDispatchOneAddRemoveEvent(kind:String, item:Object = null, location:int = -1) : void
      {
         var colEvent:CollectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         colEvent.items.push(item);
         colEvent.location = location;
         colEvent.kind = kind;
         this.internalDispatchCollectionEvent(colEvent);
      }
      
      private function internalDispatchCollectionEvent(event:CollectionEvent) : void
      {
         var i:int = 0;
         var item:Object = null;
         var updEvent:PropertyChangeEvent = null;
         var objEvent:PropertyChangeEvent = null;
         if(Log.isDebug())
         {
            this._log.debug("Sending managed CollectionEvent: destination: {0}, collectionId: {1}, kind: {2}, location: {3}, oldLocation: {4}, items: {5}",this.service.destination,Managed.toString(this.collectionId),event.kind,event.location,event.oldLocation,this._dataService.itemToIdString(event.items));
         }
         dispatchEvent(event);
         if(this._association != null && this._association.hierarchicalEvents && hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE))
         {
            if(event.kind == CollectionEventKind.RESET)
            {
               for(i = 0; i < this._items.length; i++)
               {
                  if(this._items[i] != null)
                  {
                     item = this._dataService.getItem(this._items[i]);
                     if(item != null)
                     {
                        this.dispatchPropertyChangeEvent(CollectionEventKind.ADD,item,i);
                     }
                  }
               }
            }
            else if(event.kind == CollectionEventKind.UPDATE || event.kind == CollectionEventKind.REPLACE)
            {
               for(i = 0; i < event.items.length; i++)
               {
                  updEvent = PropertyChangeEvent(event.items[i]);
                  objEvent = new PropertyChangeEvent(PropertyChangeEvent.PROPERTY_CHANGE);
                  objEvent.property = this._association.property + "." + updEvent.property;
                  objEvent.newValue = updEvent.newValue;
                  objEvent.oldValue = updEvent.oldValue;
                  if(Log.isDebug())
                  {
                     this._log.debug("Sending hierarchical PropertyChangeEvent: destination: {0}, property: {1}, oldValue: {2}, newValue: {3}",this.parentDataService.destination,objEvent.property,this._dataService.itemToIdString(objEvent.oldValue),this._dataService.itemToIdString(objEvent.newValue));
                  }
                  this._parentItem.dispatchEvent(objEvent);
               }
            }
            else if(event.kind == CollectionEventKind.ADD)
            {
               for(i = 0; i < event.items.length; i++)
               {
                  this.dispatchPropertyChangeEvent(event.kind,event.items[i],event.location + i);
               }
            }
            else if(event.kind == CollectionEventKind.REMOVE)
            {
               for(i = event.items.length - 1; i >= 0; i--)
               {
                  this.dispatchPropertyChangeEvent(event.kind,event.items[i],event.location + i);
               }
            }
         }
      }
      
      private function dispatchPropertyChangeEvent(kind:String, item:Object, location:int) : void
      {
         var objEvent:PropertyChangeEvent = new PropertyChangeEvent(PropertyChangeEvent.PROPERTY_CHANGE);
         objEvent.property = this._association.property + "." + location;
         if(kind == CollectionEventKind.ADD)
         {
            objEvent.newValue = item;
         }
         else
         {
            objEvent.oldValue = item;
         }
         if(Log.isDebug())
         {
            this._log.debug("Sending hierarchical PropertyChangeEvent: destination: {0}, property: {1}, oldValue: {2}, newValue: {3}",this.parentDataService.destination,objEvent.property,ConcreteDataService.itemToString(objEvent.oldValue),ConcreteDataService.itemToString(objEvent.newValue));
         }
         this._parentItem.dispatchEvent(objEvent);
      }
      
      function enablePaging() : void
      {
         if(this._pageManager == null)
         {
            this._pageManager = new PageManager();
         }
      }
      
      function getIdentityForIndex(i:int) : Object
      {
         var referencedIds:Object = Managed.getReferencedIds(this._parentItem);
         if(referencedIds == null)
         {
            return null;
         }
         referencedIds = referencedIds[this._association.property];
         if(referencedIds == null)
         {
            return null;
         }
         if(this._association.typeCode == ManagedAssociation.ONE)
         {
            if(i == 0)
            {
               return referencedIds;
            }
            return null;
         }
         return (referencedIds as Array)[i];
      }
      
      function getUIDForIndex(index:int) : String
      {
         return this._items[index];
      }
      
      function inSequenceIdList(seqIds:String) : Boolean
      {
         if(seqIds == null)
         {
            return false;
         }
         return seqIds.indexOf("*" + this._sequenceId.toString() + "*") != -1;
      }
      
      function processPendingRequests() : void
      {
         var args:Object = null;
         if(this._itemRequests != null && !this.hasOutstandingUpdates())
         {
            while(this._itemRequests.length > 0)
            {
               args = this._itemRequests.pop();
               this.requestItemAt(args.index,args.prefetch,args.error);
            }
            this._itemRequests = null;
         }
      }
      
      function listChanged() : void
      {
         this.cacheStale = true;
         if(this._association == null || this._association.pagedUpdates)
         {
            this._dataService.requiresSave = true;
         }
         else
         {
            this._parentDataService.requiresSave = true;
         }
      }
      
      function processSequence(items:Array, ps:PropertySpecifier, insertLocation:uint = 0, proxies:Array = null, referencedIdsList:Array = null, idList:Array = null, isNewSequence:Boolean = true, updateCache:Boolean = true, pendingItems:Object = null, token:AsyncToken = null, createdOnThisClient:Boolean = false, configureItem:Boolean = true) : Object
      {
         var item:Object = null;
         var referencedIds:Object = null;
         var proxy:Object = null;
         var uid:String = null;
         var idx:int = 0;
         var cacheItem:Object = null;
         var itemAdded:Boolean = false;
         var itemM:Object = null;
         var removedId:Object = null;
         var errMsg:ErrorMessage = null;
         var fltEvent:MessageFaultEvent = null;
         var includes:Array = null;
         var excludes:Array = null;
         var itemps:PropertySpecifier = null;
         var replacedItemIdx:int = 0;
         var oldUID:String = null;
         var oldValue:Object = null;
         var errorMsg:String = null;
         var leafDS:ConcreteDataService = null;
         var processedItems:Array = [];
         var currentItemIdx:int = 0;
         var replacedItems:Array = null;
         var oldValues:Object = null;
         if(pendingItems == null)
         {
            pendingItems = new Object();
         }
         if(!this.fetched)
         {
            isNewSequence = true;
         }
         this.fetched = true;
         this.listChanged();
         for(var i:int = 0; i < items.length; i++)
         {
            if(!isNewSequence && (items[i] == null && idList != null))
            {
               removedId = idList[i];
               this.removeReference(this._dataService.metadata.getUID(removedId),true);
            }
            else
            {
               item = DataMessage.unwrapItem(items[i]);
               if(item == null)
               {
                  if(Log.isError())
                  {
                     this._log.error("Item retrieved from fill/page response from server is null - position: " + i + " for collection: " + ConcreteDataService.itemToString(this.collectionId));
                  }
               }
               else
               {
                  item = this._dataService.normalize(item);
                  if(referencedIdsList != null)
                  {
                     referencedIds = referencedIdsList[i];
                  }
                  else
                  {
                     referencedIds = null;
                  }
                  proxy = Boolean(proxies)?proxies[i]:null;
                  uid = this._dataService.getItemCacheId(item);
                  cacheItem = this._dataService.getItem(uid);
                  if(configureItem && (ps.includeMode != PropertySpecifier.INCLUDE_DEFAULT || cacheItem == null || proxy != null) && item != cacheItem)
                  {
                     this._dataService.getItemMetadata(item).configureItem(this._dataService,cacheItem == null?item:cacheItem,item,ps,proxy,referencedIds,false,createdOnThisClient,pendingItems);
                  }
                  idx = insertLocation + i;
                  if(uid == "")
                  {
                     if(Log.isError())
                     {
                        this._log.error("Item retrieved from fill/page response from server is missing an id.  Item=" + ConcreteDataService.itemToString(item));
                     }
                     if(token != null)
                     {
                        errMsg = new ErrorMessage();
                        errMsg.faultCode = "Client.Processing.NoIdentifier";
                        errMsg.faultDetail = "No Identifier was found when processing a fill or page response - can\'t find id properties: " + Managed.toString(this._dataService.metadata.identities) + " on item: " + ConcreteDataService.itemToString(item,this._dataService.destination);
                        errMsg.faultString = "No identifier found.";
                        fltEvent = MessageFaultEvent.createEvent(errMsg);
                        this._dataService.dispatchFaultEvent(fltEvent,token);
                        if(replacedItems == null)
                        {
                           return {"processedItems":processedItems};
                        }
                        return {
                           "processedItems":processedItems,
                           "replacedItems":replacedItems
                        };
                     }
                  }
                  if(updateCache)
                  {
                     itemps = ps.getSubclassSpecifier(this._dataService.getItemDestination(item));
                     if(itemps.includeMode == PropertySpecifier.INCLUDE_LIST)
                     {
                        includes = itemps.extraProperties;
                        excludes = null;
                     }
                     else
                     {
                        includes = null;
                        excludes = itemps.excludes;
                     }
                     itemAdded = this._dataService.updateCacheWithId(uid,item,includes,excludes,referencedIds,true,this._dataService.dataStore.detectConflictsOnRefresh,pendingItems);
                  }
                  else
                  {
                     itemAdded = false;
                  }
                  itemM = this._dataService.getItem(uid);
                  if(idList == null || isNewSequence)
                  {
                     if(idx < this._items.length)
                     {
                        oldUID = this._items[idx];
                        if(oldUID != null && oldUID != uid)
                        {
                           this.replaceReferenceAt(null,idx);
                           if(!isNewSequence)
                           {
                              oldValue = this._dataService.getItem(oldUID);
                              if(oldValue != null && itemAdded && itemM != null)
                              {
                                 if(oldValues == null)
                                 {
                                    oldValues = {};
                                 }
                                 if(oldValues[currentItemIdx] == null)
                                 {
                                    oldValues[currentItemIdx] = oldValue;
                                 }
                              }
                           }
                        }
                        else if(!isNewSequence && itemAdded && itemM != null)
                        {
                           if(oldValues == null)
                           {
                              oldValues = {};
                           }
                           if(oldValues[currentItemIdx] == null)
                           {
                              oldValues[currentItemIdx] = itemM;
                           }
                        }
                     }
                     replacedItemIdx = this.addItemReferenceAt(uid,idx,idx >= this.length);
                     if(replacedItemIdx != -1 && replacedItemIdx != idx)
                     {
                        if(replacedItemIdx >= insertLocation + items.length || replacedItemIdx < insertLocation)
                        {
                           if(replacedItems == null)
                           {
                              replacedItems = [];
                           }
                           replacedItems.push({
                              "idx":replacedItemIdx,
                              "item":itemM
                           });
                        }
                        else
                        {
                           if(replacedItemIdx < idx)
                           {
                              errorMsg = "Collection result contains a duplicate item: " + uid + " exists at both position: " + replacedItemIdx + " and " + idx;
                              if(Log.isError())
                              {
                                 this._log.error(errorMsg);
                              }
                              throw new DataServiceError(errorMsg);
                           }
                           if(oldValues == null)
                           {
                              oldValues = {};
                           }
                           oldValues[replacedItemIdx] = itemM;
                        }
                     }
                  }
                  else if(itemAdded && itemM != null && cacheItem != null)
                  {
                     if(oldValues == null)
                     {
                        oldValues = {};
                     }
                     oldValues[currentItemIdx] = itemM;
                  }
                  if(!itemAdded && updateCache && idList == null)
                  {
                     if(oldUID == null)
                     {
                        this.logDeleteFromCollectionForDeletedItem(item,idx);
                     }
                     leafDS = this._dataService.getItemDestination(item);
                     leafDS.releaseAssociations(item,false,false,null,null,false);
                  }
                  if(itemAdded && itemM != null)
                  {
                     processedItems.push(itemM);
                     currentItemIdx++;
                  }
               }
            }
         }
         if(this._dataService.dataStore.autoSaveCache)
         {
            this._dataService.dataStore.saveCache(null,true);
         }
         if(replacedItems == null)
         {
            return {
               "processedItems":processedItems,
               "oldValues":oldValues
            };
         }
         return {
            "processedItems":processedItems,
            "replacedItems":replacedItems,
            "oldValues":oldValues
         };
      }
      
      function logDeleteFromCollectionForDeletedItem(item:Object, idx:int) : void
      {
         var identity:Object = this._dataService.getItemIdentifier(item);
         if(this._dataService.dataStore.messageCache.getUncommittedUpdateCollections(this._dataService.destination,this.collectionId,identity).length == 0)
         {
            if(Log.isDebug())
            {
               this._log.debug("Adding update collection for item paged in after it was deleted locally - " + ConcreteDataService.itemToString(identity));
            }
            this._dataService.dataStore.logCollectionUpdate(this._dataService,this,UpdateCollectionRange.DELETE_FROM_COLLECTION,this.calculateIndex(idx,false),identity,null);
         }
      }
      
      function processSequenceIds(event:MessageEvent, token:AsyncToken, isNewSequence:Boolean = true) : void
      {
         var idx:int = 0;
         var uid:String = null;
         var msg:SequencedMessage = SequencedMessage(event.message);
         var itemIds:Array = msg.body as Array;
         var insertLocation:uint = !!isNewSequence?uint(0):uint(token.request.lowerBound);
         var metadata:Metadata = this._dataService.metadata;
         if(isNewSequence)
         {
            this._sequenceId = msg.sequenceId;
            this.setSequenceSize(msg.sequenceSize);
            if(this.pagingEnabled)
            {
               this.enablePaging();
            }
         }
         for(var i:int = 0; i < itemIds.length; i++)
         {
            idx = insertLocation + i;
            uid = metadata.getUID(itemIds[i]);
            if(idx > this._items.length)
            {
               this.padItems(idx - this._items.length);
            }
            this._items[idx] = uid;
         }
         if(this._association != null && !this._association.pagedUpdates)
         {
            if(msg.sequenceSize != -1)
            {
               this.setSequenceSize(msg.sequenceSize);
            }
            this.applyPendingUpdateCollections(false,false,true);
         }
         var colEvent:CollectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
         colEvent.kind = CollectionEventKind.RESET;
         dispatchEvent(colEvent);
      }
      
      function processSequenceResult(event:MessageEvent, token:AsyncToken, isFillOrGet:Boolean = true, isPageItems:Boolean = false, isRefresh:Boolean = false) : void
      {
         var insertLocation:uint = 0;
         var trimmedItems:Array = null;
         var colEvent:CollectionEvent = null;
         var ps:PropertySpecifier = null;
         var replaceEvents:Array = null;
         var sequenceResult:Object = null;
         var dynamicDecremented:Boolean = false;
         var startEvent:int = 0;
         var objEvents:Array = null;
         var objEvent:PropertyChangeEvent = null;
         var i:int = 0;
         var sr:int = 0;
         var replaceInfo:Object = null;
         var replaceEvent:CollectionEvent = null;
         var szEvent:CollectionEvent = null;
         var eventItem:Object = null;
         var re:int = 0;
         var msg:SequencedMessage = SequencedMessage(event.message);
         var items:Array = msg.body as Array;
         var sizeDiff:int = 0;
         var isNewSequence:Boolean = !this.fetched || isFillOrGet && !isRefresh;
         var isPageMessage:Boolean = !isPageItems && !isFillOrGet;
         if(isFillOrGet)
         {
            insertLocation = 0;
            this._queuedUpdateCollections = null;
            this._pagingEnabled = this._dataService.pagingEnabled || msg.headers.paged != null;
         }
         else
         {
            insertLocation = token.request.lowerBound;
         }
         try
         {
            this._dataService.enableDelayedCollectionEvents();
            if(!isNewSequence)
            {
               this.applyPendingUpdateCollections(true,false,true);
            }
            if(this._association == null || this._association.paged)
            {
               dynamicDecremented = isPageMessage && this.incompleteDynamicSizing && msg.sequenceSize < this.length;
               if(msg.sequenceSize != -1 && !isPageItems && !dynamicDecremented)
               {
                  sizeDiff = msg.sequenceSize - this._itemsSize;
                  trimmedItems = this.setSequenceSize(msg.sequenceSize);
               }
               else
               {
                  trimmedItems = null;
                  sizeDiff = 0;
               }
               if(isNewSequence)
               {
                  sizeDiff = 0;
               }
            }
            else
            {
               sizeDiff = 0;
            }
            colEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
            ps = token != null?this._dataService.getMessagePropertySpecifier(DataMessage(token.message)):this._dataService.includeDefaultSpecifier;
            replaceEvents = null;
            sequenceResult = this.processSequence(items,ps,insertLocation,msg.sequenceProxies,msg.headers.referencedIds,token.request == null?null:token.request.idList,isNewSequence,true,null,token);
            if((this._sequenceId < 0 || this.sequenceIdStale) && msg.sequenceId != -1)
            {
               this._sequenceId = msg.sequenceId;
               if(this.sequenceIdStale)
               {
                  this.sequenceIdStale = false;
                  this._dataService.staleSequencesCount--;
               }
            }
            if(this._sequenceId >= 0 && !this.sequenceAutoSubscribed)
            {
               this._dataService.autoSubscribe();
               this.sequenceAutoSubscribed = true;
            }
            if(isNewSequence)
            {
               if(this._pagingEnabled)
               {
                  this.enablePaging();
               }
               this._dynamicSizing = msg.dynamicSizing == 1;
               if(msg.headers.pageSize != null)
               {
                  this._pageSize = msg.headers.pageSize;
               }
               if(msg.headers["pageFill"] != null)
               {
                  this._pageFilled = true;
               }
               if(Log.isDebug())
               {
                  if(DataMessage(token.message).operation == DataMessage.GET_OR_CREATE_OPERATION)
                  {
                     this._log.debug("Result for {0}.{1}({2},{3}) ->: {4} {5} {6}",this._dataService.destination,this.dataListTypeName(),Managed.toString(this.collectionId,null,null,2),ConcreteDataService.itemToString(this._dataService.getManagedItems(items),this._dataService.destination,2),ConcreteDataService.itemToString(DataMessage(token.message).body,this._dataService.destination,2),this._sequenceId >= 0?"(synced)":"(not synced)",ps);
                  }
                  else
                  {
                     this._log.debug("Result for {0}.{1}({2}) ->: {3} {4} {5}",this._dataService.destination,this.dataListTypeName(),Managed.toString(this.collectionId,null,null,2),ConcreteDataService.itemToString(this._dataService.getManagedItems(items),this._dataService.destination,2),this._sequenceId >= 0?"(synced)":"(not synced)",ps);
                  }
               }
            }
            else if(Log.isDebug())
            {
               this._log.debug("Result for page {0}.{1}({2}) -> {3} for index: {4} {5}",this._dataService.destination,this.dataListTypeName(),Managed.toString(this.collectionId,null,null,2),ConcreteDataService.itemToString(sequenceResult.processedItems,this._dataService.destination,2),insertLocation,ps);
            }
            if(isNewSequence)
            {
               colEvent.kind = CollectionEventKind.RESET;
            }
            else
            {
               colEvent.kind = CollectionEventKind.REPLACE;
               colEvent.location = this.calculateIndex(insertLocation,false);
               if(colEvent.location < 0)
               {
                  startEvent = -colEvent.location;
                  colEvent.location = 0;
               }
               else
               {
                  startEvent = 0;
               }
               objEvents = [];
               i = startEvent;
               while(i < sequenceResult.processedItems.length && i + colEvent.location < this._itemsSize)
               {
                  objEvent = new PropertyChangeEvent(PropertyChangeEventKind.UPDATE);
                  if(sequenceResult.oldValues != null)
                  {
                     objEvent.oldValue = sequenceResult.oldValues[i];
                  }
                  objEvent.newValue = sequenceResult.processedItems[i];
                  objEvent.property = i + colEvent.location;
                  objEvents.push(objEvent);
                  i++;
               }
               colEvent.items = objEvents;
               if(sequenceResult.replacedItems != null)
               {
                  replaceEvents = [];
                  for(sr = 0; sr < sequenceResult.replacedItems.length; sr++)
                  {
                     replaceInfo = sequenceResult.replacedItems[sr];
                     replaceEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                     replaceEvent.kind = CollectionEventKind.REPLACE;
                     replaceEvent.location = this.calculateIndex(replaceInfo.idx,false);
                     if(replaceEvent.location >= 0 && replaceEvent.location < this._itemsSize)
                     {
                        objEvent = new PropertyChangeEvent(PropertyChangeEventKind.UPDATE);
                        objEvent.oldValue = replaceInfo.item;
                        objEvent.newValue = null;
                        objEvent.property = replaceEvent.location;
                        replaceEvent.items = [objEvent];
                        replaceEvents.push(replaceEvent);
                     }
                  }
               }
            }
            this.applyPendingUpdateCollections(false,false,true);
            if(sizeDiff != 0)
            {
               szEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
               for(i = 0; i < Math.abs(sizeDiff); i++)
               {
                  if(sizeDiff < 0)
                  {
                     eventItem = trimmedItems != null && i < trimmedItems.length?trimmedItems[i]:null;
                     szEvent.items.push(eventItem);
                     szEvent.kind = CollectionEventKind.REMOVE;
                  }
                  else
                  {
                     eventItem = null;
                     szEvent.items.push(null);
                     szEvent.kind = CollectionEventKind.ADD;
                  }
               }
               szEvent.location = this._itemsSize;
               this.internalDispatchCollectionEvent(szEvent);
            }
            this.internalDispatchCollectionEvent(colEvent);
            if(replaceEvents != null)
            {
               for(re = 0; re < replaceEvents.length; re++)
               {
                  this.internalDispatchCollectionEvent(replaceEvents[re]);
               }
            }
         }
         catch(e:Error)
         {
            _dataService.disableDelayedCollectionEvents();
            throw e;
         }
         this._dataService.disableDelayedCollectionEvents();
         if(!isFillOrGet)
         {
            this.removeRequest(token.request,event.message);
         }
         if(this._dataService.dataStore.autoSaveCache)
         {
            this._dataService.dataStore.saveCache(this._dataService,true,null,null,false);
         }
      }
      
      private function dataListTypeName() : String
      {
         return this._association != null?"association":this.itemReference == null?"fill":"getItem";
      }
      
      function updateSequenceIds(seqId:int, size:int, proxies:Array) : void
      {
         var i:int = 0;
         var item:Object = null;
         var proxy:Object = null;
         var md:Metadata = null;
         var propName:* = null;
         var association:ManagedAssociation = null;
         var propInfo:Object = null;
         var subList:DataList = null;
         this.sequenceIdStale = false;
         this.sequenceId = seqId;
         if(this.sequenceId >= 0 && !this.sequenceAutoSubscribed)
         {
            this._dataService.autoSubscribe();
            this.sequenceAutoSubscribed = true;
         }
         if(proxies != null)
         {
            if(Log.isWarn() && size != this._itemsSize)
            {
               this._log.warn("Sequence on server has changed while disconnected.  oldSize={0}, newSize={1}",this._items.length,size);
            }
            for(i = 0; i < this._itemsSize; i++)
            {
               item = this._dataService.getItem(this._items[i]);
               if(i < proxies.length)
               {
                  proxy = proxies[i];
               }
               else
               {
                  proxy = null;
               }
               if(item != null && proxy != null)
               {
                  md = this._dataService.getItemMetadata(item);
                  for(propName in md.associations)
                  {
                     association = ManagedAssociation(md.associations[propName]);
                     propInfo = proxy[propName];
                     subList = this._dataService.getDataListForAssociation(item,association);
                     if(subList != null && propInfo != null && propInfo.processed == null)
                     {
                        propInfo.processed = true;
                        subList.updateSequenceIds(propInfo.sequenceId,propInfo.sequenceSize,propInfo.subs);
                     }
                  }
               }
            }
         }
      }
      
      function removeReference(uid:String, updateReferencedIds:Boolean = false, removeSMOs:Boolean = true, remote:Boolean = false) : int
      {
         var index:int = this.getUIDIndex(uid);
         if(index != -1)
         {
            if(remote && this._pagingEnabled)
            {
               if(this._deletedUIDs == null)
               {
                  this._deletedUIDs = {};
               }
               this._deletedUIDs[uid] = true;
            }
            this.removeReferenceAt(index,removeSMOs,updateReferencedIds);
            this.internalDispatchOneAddRemoveEvent(CollectionEventKind.REMOVE,this._dataService.getItem(uid),index);
         }
         return index;
      }
      
      function removeReferenceAt(index:uint, removeSMOs:Boolean = true, updateReferencedIds:Boolean = false) : void
      {
         this.listChanged();
         var uid:String = this._items[index];
         this._items.splice(index,1);
         if(index < this._itemsSize)
         {
            this._itemsSize--;
         }
         if(this.referenceCount > 0)
         {
            this._dataService.removeDataListIndexEntry(this,uid);
            if(this._smo && removeSMOs)
            {
               this._dataService.removeDataList(this);
            }
         }
         if(this._association != null && this._association.typeCode == ManagedAssociation.ONE && this._parentItem != null && this._items.length == 0)
         {
            this._parentDataService.disableLogging();
            try
            {
               this._parentItem.referencedIds[this._association.property] = null;
               this._parentItem[this._association.property] = null;
            }
            finally
            {
               this._parentDataService.enableLogging();
            }
         }
         this.updatePendingRequests(index,CollectionEventKind.REMOVE);
         if(updateReferencedIds && this._association != null && !this._association.paged)
         {
            if(this._association.typeCode == ManagedAssociation.ONE)
            {
               this._parentItem.referencedIds[this._association.property] = null;
            }
            else
            {
               this._parentItem.referencedIds[this._association.property].splice(index,1);
            }
         }
      }
      
      function replaceReferenceAt(uid:String, index:int) : void
      {
         if(index >= this._itemsSize)
         {
            throw new DataServiceError("ReplaceReferenceAt index out of range");
         }
         this.listChanged();
         if(index > this._items.length)
         {
            this.padItems(index - this._items.length);
         }
         this._dataService.removeDataListIndexEntry(this,this._items[index]);
         this._items[index] = uid;
         this._dataService.addDataListIndexEntry(this,uid);
      }
      
      function setOneReference(uid:String) : void
      {
         this.listChanged();
         this.fetched = true;
         if(uid == null)
         {
            if(this._itemsSize == 1)
            {
               this.removeReferenceAt(0);
            }
         }
         else if(this._itemsSize == 0)
         {
            this.addItemReferenceAt(uid,0,true);
         }
         else
         {
            this.replaceReferenceAt(uid,0);
         }
      }
      
      function addItemReferenceAt(uid:String, index:int, increaseSize:Boolean = true) : int
      {
         var dls:Array = null;
         var oldUID:String = null;
         var oldIdx:int = -1;
         if(!increaseSize && index >= this._itemsSize)
         {
            throw new DataServiceError("AddItemToReference out of range");
         }
         this.listChanged();
         if((dls = this._dataService.getDataListsForUID(uid)) != null && ArrayUtil.getItemIndex(this,dls) != -1)
         {
            oldIdx = this.getUIDIndex(uid);
            if(oldIdx == -1)
            {
               throw new Error("Can\'t find the uid but there is an entry in the index!");
            }
            this._items[oldIdx] = null;
         }
         else
         {
            this._dataService.addDataListIndexEntry(this,uid);
         }
         if(index > this._items.length)
         {
            this.padItems(index - this._items.length);
         }
         if(increaseSize)
         {
            this._itemsSize++;
            if(index == this.length)
            {
               this._items.push(uid);
            }
            else
            {
               this._items.splice(index,0,uid);
            }
         }
         else
         {
            oldUID = this._items[index];
            if(oldUID != null && oldUID != uid)
            {
               this._dataService.removeDataListIndexEntry(this,oldUID);
            }
            this._items[index] = uid;
         }
         return oldIdx;
      }
      
      function removeAllItemReferences() : void
      {
         for(var i:int = 0; i < this._items.length; i++)
         {
            this._dataService.removeDataListIndexEntry(this,this._items[i]);
         }
         this._items = [];
         this._itemsSize = 0;
      }
      
      function removeRequest(request:PageRequest, message:IMessage) : void
      {
         var found:Boolean = false;
         var i:uint = 0;
         while(!found && i < this._pageManager.requests.length)
         {
            found = request == this._pageManager.requests[i];
            i++;
         }
         if(found)
         {
            this._pageManager.requests.splice(i - 1,1);
            request.sendResponderNotification(message);
         }
      }
      
      function setSequenceSize(value:int) : Array
      {
         var i:int = 0;
         var j:int = 0;
         var trimmedItems:Array = null;
         if(value == -1)
         {
            return null;
         }
         this._itemsSize = value;
         this.listChanged();
         if(value < this._items.length)
         {
            trimmedItems = [];
            for(i = this._items.length - 1; i >= value; i--)
            {
               trimmedItems[_loc5_] = this._dataService.getItemForReference(this._items[i],false);
               if(this._items[i] != null)
               {
                  this._dataService.removeDataListIndexEntry(this,this._items[i]);
               }
            }
            this._items.splice(value);
         }
         return trimmedItems;
      }
      
      private function calculateIndex(index:int, inverse:Boolean = true) : int
      {
         var ucm:UpdateCollectionMessage = null;
         var ranges:Array = null;
         var range:UpdateCollectionRange = null;
         var offset:int = 0;
         var j:int = 0;
         var idx:int = 0;
         var result:int = index;
         var ucMsgs:Array = this._dataService.dataStore.messageCache.getPendingUpdateCollections(this._dataService.destination,this.collectionId);
         for(var i:int = 0; i < ucMsgs.length; i++)
         {
            ucm = UpdateCollectionMessage(ucMsgs[i]);
            ranges = ucm.body as Array;
            if(ranges != null)
            {
               for(j = 0; j < ranges.length; j++)
               {
                  idx = j;
                  if(inverse)
                  {
                     idx = ranges.length - idx - 1;
                  }
                  range = UpdateCollectionRange(ranges[idx]);
                  if(result >= range.position)
                  {
                     offset = range.identities.length;
                     if(range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION)
                     {
                        result = !!inverse?int(result + offset):int(result - offset);
                     }
                     else
                     {
                        result = !!inverse?int(result - offset):int(result + offset);
                     }
                  }
               }
            }
         }
         return result;
      }
      
      function copyListToArrayCollection(from:IList) : ArrayCollection
      {
         var item:Object = null;
         var to:ArrayCollection = new ArrayCollection();
         for(var i:int = 0; i < from.length; i++)
         {
            item = from.getItemAt(i);
            if(item is ObjectProxy)
            {
               item = ObjectProxy(item).object_proxy::object;
            }
            to.addItem(item);
         }
         return to;
      }
      
      function fetchValue(tokens:Array = null) : void
      {
         var pageRequest:PageRequest = null;
         var pds:ConcreteDataService = null;
         var pm:PageManager = null;
         if(this.fetched)
         {
            return;
         }
         if(ConcreteDataService.pagingDisabled > 0)
         {
            return;
         }
         var parentUID:String = IManaged(this._parentItem).uid;
         var refs:Array = this._parentDataService.getAllDataLists(parentUID,false);
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
         var error:ItemPendingError = new ItemPendingError("Requesting : " + this._parentDataService.destination + ":" + IManaged(this._parentItem).uid + "." + this._association.property);
         var parentIdentity:Object = this._parentDataService.getIdentityMap(this._parentItem);
         if(this._association.paged)
         {
            this.enablePaging();
            pm = this._pageManager;
            pds = this._dataService;
            pageRequest = new PageRequest(refDataList.sequenceId >= 0,0,this.pageSize,null,null);
         }
         else
         {
            refDataList.enablePaging();
            pm = refDataList._pageManager;
            pds = this._parentDataService;
            pageRequest = new PageRequest(refDataList.sequenceId >= 0,0,0,[parentIdentity],[this._association.property]);
         }
         var existingPageRequest:PageRequest = pm.getPendingMatchingRequest(pageRequest);
         if(existingPageRequest != null)
         {
            existingPageRequest.addPendingError(error);
            if(pds.throwItemPendingErrors)
            {
               throw error;
            }
            return;
         }
         var token:AsyncToken = pds.processPageRequest(pageRequest,!!this._association.paged?this:refDataList,true);
         if(tokens != null)
         {
            tokens.push(token);
         }
         pm.requests.push(pageRequest);
         if(pds.throwItemPendingErrors)
         {
            pageRequest.addPendingError(error);
            throw error;
         }
      }
      
      function fetchItemProperty(item:Object, prop:String) : void
      {
         var pageRequest:PageRequest = null;
         var pds:ConcreteDataService = this._dataService;
         var error:ItemPendingError = new ItemPendingError("Requesting : " + pds.destination + ":" + IManaged(item).uid + "." + prop);
         var parentIdentity:Object = pds.getIdentityMap(item);
         this.enablePaging();
         pageRequest = new PageRequest(this._sequenceId >= 0,0,0,[parentIdentity],[prop]);
         var existingPageRequest:PageRequest = this._pageManager.getPendingMatchingRequest(pageRequest);
         if(existingPageRequest != null)
         {
            existingPageRequest.addPendingError(error);
            if(pds.throwItemPendingErrors)
            {
               throw error;
            }
            return;
         }
         if(Log.isDebug())
         {
            this._log.debug("Queuing page request for: " + IManaged(item).uid + " for property: " + prop);
         }
         this.queuePageRequest(pageRequest);
         if(pds.throwItemPendingErrors)
         {
            pageRequest.addPendingError(error);
            throw error;
         }
      }
      
      private function queuePageRequest(request:PageRequest) : void
      {
         if(this._flushPageRequestTimer == null)
         {
            this._flushPageRequestTimer = new Timer(1);
            this._flushPageRequestTimer.addEventListener(TimerEvent.TIMER,this.flushPageRequests);
            this._flushPageRequestTimer.start();
         }
         this._pageManager.requests.push(request);
      }
      
      private function flushPageRequests(timerEvent:TimerEvent) : void
      {
         var pageRequest:PageRequest = null;
         this._flushPageRequestTimer = null;
         for(var p:int = 0; p < this._pageManager.requests.length; p++)
         {
            pageRequest = PageRequest(this._pageManager.requests[p]);
            if(!pageRequest.messageSent)
            {
               this._dataService.processPageRequest(pageRequest,this);
            }
         }
      }
      
      private function checkIndex(index:int) : void
      {
         if(index < 0 || index > this.length)
         {
            throw new RangeError(resourceManager.getString("data","indexOutOfBounds",[index]));
         }
      }
      
      private function checkRequestIntegrity(index:int, prefetch:int) : Boolean
      {
         var ipe:ItemPendingError = null;
         if(this.hasOutstandingUpdates())
         {
            ipe = new ItemPendingError(resourceManager.getString("data","pendingRequestedItem"));
            if(this._itemRequests == null)
            {
               this._itemRequests = [];
            }
            this._itemRequests.push({
               "index":index,
               "prefetch":prefetch,
               "error":ipe
            });
            if(this._dataService.throwItemPendingErrors)
            {
               throw ipe;
            }
            return false;
         }
         return true;
      }
      
      private function getPrefetchBounds(index:int, prefetch:int) : Object
      {
         var lowerBound:int = 0;
         var upperBound:int = 0;
         if(prefetch < 0)
         {
            lowerBound = Math.max(index + prefetch,0);
            upperBound = index + 1;
         }
         else if(prefetch > 0)
         {
            lowerBound = index;
            upperBound = Math.min(index + prefetch,this._itemsSize);
         }
         else
         {
            lowerBound = index;
            upperBound = index + 1;
         }
         return {
            "upperBound":upperBound,
            "lowerBound":lowerBound
         };
      }
      
      private function hasOutstandingUpdates() : Boolean
      {
         return this._dataService.hasPendingUpdateCollections(this.collectionId);
      }
      
      private function pageIn(neededIds:Array) : AsyncToken
      {
         this.enablePaging();
         var request:PageRequest = new PageRequest(this._sequenceId >= 0,1,1,neededIds);
         this._pageManager.requests.push(request);
         return this._dataService.processPageRequest(request,this);
      }
      
      private function updatePendingRequests(index:int, kind:String) : void
      {
         var request:Object = null;
         var i:int = 0;
         if(this._itemRequests != null)
         {
            for(i = 0; i < this._itemRequests.length; i++)
            {
               request = this._itemRequests[i];
               if(index <= request.index)
               {
                  if(kind == CollectionEventKind.ADD)
                  {
                     request.index++;
                  }
                  else if(request.index > 0)
                  {
                     request.index--;
                  }
               }
            }
         }
      }
      
      private function padItems(amount:int) : void
      {
         for(var i:uint = 0; i < amount; i++)
         {
            this._items.push(null);
         }
      }
   }
}

import mx.data.ConcreteDataService;
import mx.data.PageRequest;
import mx.utils.ObjectUtil;

class PageManager
{
    
   
   public var requests:Array;
   
   public var queuedRequests:Boolean = false;
   
   function PageManager()
   {
      this.requests = [];
      super();
   }
   
   public function getPendingRequest(identity:Object) : PageRequest
   {
      var request:PageRequest = null;
      var ids:Array = null;
      var j:int = 0;
      for(var i:int = 0; i < this.requests.length; i++)
      {
         request = PageRequest(this.requests[i]);
         if(request.idList != null)
         {
            ids = request.idList;
            for(j = 0; j < ids.length; j++)
            {
               if(ObjectUtil.compare(ids[j],identity) == 0)
               {
                  return request;
               }
            }
         }
      }
      return null;
   }
   
   public function getPendingRequestForUID(ds:ConcreteDataService, uid:String) : PageRequest
   {
      var request:PageRequest = null;
      var ids:Array = null;
      var j:int = 0;
      for(var i:int = 0; i < this.requests.length; i++)
      {
         request = PageRequest(this.requests[i]);
         if(request.idList != null)
         {
            ids = request.idList;
            for(j = 0; j < ids.length; j++)
            {
               if(ds.metadata.getUID(ids[j]) == uid)
               {
                  return request;
               }
            }
         }
      }
      return null;
   }
   
   public function getPendingMatchingRequest(pr:PageRequest) : PageRequest
   {
      var p:int = 0;
      var pageRequest:PageRequest = null;
      if(this.requests.length > 0)
      {
         for(p = 0; p < this.requests.length; p++)
         {
            pageRequest = PageRequest(this.requests[p]);
            if(pageRequest.includesPageRequest(pr))
            {
               return pageRequest;
            }
         }
      }
      return null;
   }
   
   public function releaseRequests(startIndex:int, num:int) : void
   {
      var pageRequest:PageRequest = null;
      var last:int = startIndex + num;
      for(var p:int = 0; p < this.requests.length; p++)
      {
         pageRequest = PageRequest(this.requests[p]);
         if(pageRequest.upperBound > startIndex && pageRequest.lowerBound < last)
         {
            pageRequest.released = true;
         }
      }
   }
}
