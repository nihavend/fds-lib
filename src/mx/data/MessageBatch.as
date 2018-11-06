package mx.data
{
   import flash.events.EventDispatcher;
   import flash.utils.Dictionary;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import mx.collections.ArrayCollection;
   import mx.collections.ArrayList;
   import mx.collections.IList;
   import mx.collections.ListCollectionView;
   import mx.data.errors.DataServiceError;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.Managed;
   import mx.events.PropertyChangeEvent;
   import mx.logging.Log;
   import mx.rpc.AsyncToken;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   
   [RemoteClass]
   public class MessageBatch extends EventDispatcher implements IExternalizable
   {
      
      private static const VERSION:uint = 2;
       
      
      public var properties:Object = null;
      
      public var batchMessage:DataMessage;
      
      private var _items:ArrayList;
      
      public const items:ArrayCollection = new ArrayCollection();
      
      private var _createdItems:Dictionary;
      
      private var _uidItemIndex:Object;
      
      private var _id:String;
      
      private var _updateCollectionMessages:Array;
      
      private var _messageIdCacheItemIndex:Object;
      
      private var _newUIDToMessageIdIndex:Object;
      
      var updateCollectionReferenceIndex:Object;
      
      var commitComplete:Boolean = false;
      
      var commitResponder:CommitResponder;
      
      var hasCreates:Boolean;
      
      var dataStore:DataStore;
      
      var batchSequence:int = -1;
      
      var tokenCache:Array;
      
      var tokenCacheIndex:Object;
      
      public function MessageBatch()
      {
         this.batchMessage = new DataMessage();
         this._items = new ArrayList();
         this.tokenCache = [];
         this.tokenCacheIndex = {};
         super();
         this.items.list = this._items;
         this.clear();
      }
      
      public function get id() : String
      {
         return this.batchMessage.messageId;
      }
      
      public function commit(itemsOrCollections:Array = null, cascadeCommit:Boolean = false) : AsyncToken
      {
         return this.dataStore.internalCommit(null,itemsOrCollections,cascadeCommit,this);
      }
      
      public function revertChanges(item:IManaged = null) : Boolean
      {
         return this.doRevertChanges(null,item);
      }
      
      function doRevertChanges(ds:ConcreteDataService, item:IManaged) : Boolean
      {
         return this.dataStore.doRevertChanges(ds,item,null,this);
      }
      
      public function revertChangesForCollection(collection:ListCollectionView) : Boolean
      {
         var cds:ConcreteDataService = null;
         if(collection.list is DataList)
         {
            cds = DataList(collection.list).service;
            return this.dataStore.doRevertChanges(cds,null,collection,this);
         }
         throw new ArgumentError("revertChangesForCollection called on collection which is not managed");
      }
      
      [Bindable(event="propertyChange")]
      public function get commitRequired() : Boolean
      {
         return this.length > 0;
      }
      
      public function commitRequiredOn(item:Object) : Boolean
      {
         if(this.length <= 0)
         {
            return false;
         }
         return this.dataStore.commitRequiredOn(item);
      }
      
      function addCacheItem(dataService:ConcreteDataService, msg:DataMessage, item:Object = null) : void
      {
         var i:int = 0;
         var messageOp:int = 0;
         var cacheItem:MessageCacheItem = new MessageCacheItem();
         cacheItem.message = msg;
         this.setCacheItem(cacheItem,item);
         cacheItem.dataService = dataService.getItemDestination(item);
         if(msg.isCreate())
         {
            for(i = this._items.length - 1; i >= 0; i--)
            {
               messageOp = MessageCacheItem(this._items.getItemAt(i)).message.operation;
               if(messageOp != DataMessage.UPDATE_OPERATION && messageOp != DataMessage.UPDATE_COLLECTION_OPERATION && messageOp != DataMessage.DELETE_OPERATION)
               {
                  break;
               }
            }
            this._items.addItemAt(cacheItem,i + 1);
            this._createdItems[ConcreteDataService.unnormalize(cacheItem.item)] = cacheItem;
         }
         else
         {
            this._items.addItem(cacheItem);
         }
         this.addToUIDItemIndex(cacheItem);
         this.addToMessageIdCacheItemIndex(cacheItem);
         this.sendCommitRequiredChange(true);
      }
      
      private function sendCommitRequiredChange(val:Boolean) : void
      {
         dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"commitRequired",!val,val));
      }
      
      function registerItemWithMessageCache(ds:ConcreteDataService, item:Object, message:DataMessage) : void
      {
         var cacheItem:MessageCacheItem = null;
         if(!(message is UpdateCollectionMessage))
         {
            cacheItem = this.getCacheItem(message.messageId);
            if(cacheItem != null)
            {
               cacheItem.dataService = ds;
               if(item != null)
               {
                  this.setCacheItem(cacheItem,item);
               }
            }
         }
      }
      
      private function removeFromIndex(cacheItem:MessageCacheItem) : void
      {
         var body:Object = null;
         this.removeFromUIDItemIndex(cacheItem);
         this.removeFromMessageIdCacheItemIndex(cacheItem);
         if(cacheItem.message.isCreate())
         {
            body = ConcreteDataService.unnormalize(cacheItem.item);
            if(this._createdItems[body] != cacheItem)
            {
               throw new DataServiceError("Failed to find proper item to remove in data message cache index");
            }
            delete this._createdItems[body];
         }
      }
      
      private function addToIndex(cacheItem:MessageCacheItem, uid:String = null) : void
      {
         this.addToUIDItemIndex(cacheItem,uid);
         if(cacheItem.message.isCreate())
         {
            this.hasCreates = true;
            if(cacheItem.item != null)
            {
               this._createdItems[ConcreteDataService.unnormalize(cacheItem.item)] = cacheItem;
            }
         }
         this.addToMessageIdCacheItemIndex(cacheItem);
      }
      
      function addToUIDItemIndex(cacheItem:MessageCacheItem, uid:String = null) : void
      {
         if(uid == null)
         {
            uid = cacheItem.uid;
         }
         if(uid != null)
         {
            if(this._uidItemIndex[uid] == null)
            {
               this._uidItemIndex[uid] = [cacheItem];
            }
            else
            {
               (this._uidItemIndex[uid] as Array).push(cacheItem);
            }
         }
      }
      
      private function addToMessageIdCacheItemIndex(cacheItem:MessageCacheItem) : void
      {
         this._messageIdCacheItemIndex[cacheItem.message.messageId] = cacheItem;
      }
      
      private function removeFromMessageIdCacheItemIndex(cacheItem:MessageCacheItem) : void
      {
         delete this._messageIdCacheItemIndex[cacheItem.message.messageId];
      }
      
      private function removeFromUIDItemIndex(cacheItem:MessageCacheItem) : void
      {
         var uid:String = cacheItem.uid;
         if(uid == null)
         {
            return;
         }
         var cil:Array = this._uidItemIndex[uid];
         if(cil == null)
         {
            throw new DataServiceError("Unable to find uid index entry for cache item");
         }
         var ix:int = ArrayUtil.getItemIndex(cacheItem,cil);
         if(ix == -1)
         {
            throw new DataServiceError("Unable to find uid index entry for cache item");
         }
         cil.splice(ix,1);
         if(cil.length == 0)
         {
            delete this._uidItemIndex[uid];
         }
      }
      
      private function addUpdateCollectionMessage(ucmsg:UpdateCollectionMessage) : void
      {
         if(this._updateCollectionMessages == null)
         {
            this._updateCollectionMessages = [];
         }
         this._updateCollectionMessages.push(ucmsg);
      }
      
      function addUpdateCollectionMessages(messages:Array, batchId:String) : void
      {
         var ucmsg:UpdateCollectionMessage = null;
         if(this._updateCollectionMessages == null)
         {
            return;
         }
         for(var i:int = 0; i < this._updateCollectionMessages.length; i++)
         {
            ucmsg = this._updateCollectionMessages[i];
            ucmsg.correlationId = batchId;
            if(ucmsg.clientId == null)
            {
               ucmsg.clientId = ConcreteDataService.getService(ucmsg.destination).consumer.clientId;
            }
            messages.push(ucmsg);
         }
      }
      
      function releaseBatch() : void
      {
         var i:int = 0;
         if(this._updateCollectionMessages != null)
         {
            for(i = 0; i < this._updateCollectionMessages.length; i++)
            {
               this.releaseDataListForUpdateCollection(this._updateCollectionMessages[i]);
            }
         }
         for(i = 0; i < this._items.length; i++)
         {
            if(this._items.getItemAt(i).message is UpdateCollectionMessage)
            {
               this.releaseDataListForUpdateCollection(this._items.getItemAt(i).message);
            }
         }
      }
      
      public function clear() : void
      {
         this.releaseBatch();
         this._items.removeAll();
         this._updateCollectionMessages = null;
         this._uidItemIndex = {};
         this._createdItems = new Dictionary();
         this._messageIdCacheItemIndex = {};
      }
      
      function getCreateCacheItem(dataService:ConcreteDataService, item:Object) : MessageCacheItem
      {
         return this._createdItems[ConcreteDataService.unnormalize(item)];
      }
      
      function getCreateMessage(dataService:ConcreteDataService, item:Object) : DataMessage
      {
         var ci:MessageCacheItem = this.getCreateCacheItem(dataService,item);
         return ci == null?null:ci.message;
      }
      
      public function getMessage(messageId:String) : DataMessage
      {
         var cacheItem:MessageCacheItem = this.getCacheItem(messageId);
         if(cacheItem != null)
         {
            return cacheItem.message;
         }
         return null;
      }
      
      function getItem(msgId:String) : Object
      {
         var ci:MessageCacheItem = this.getCacheItem(msgId);
         if(ci == null)
         {
            return null;
         }
         return ci.item;
      }
      
      function getDataService(msg:DataMessage) : ConcreteDataService
      {
         var ci:MessageCacheItem = this.getCacheItem(msg.messageId);
         if(ci == null)
         {
            return null;
         }
         return ci.dataService;
      }
      
      function getLastCacheItem(dataService:ConcreteDataService, uid:String, stopAtMessage:DataMessage) : MessageCacheItem
      {
         var result:MessageCacheItem = null;
         var i:int = 0;
         var list:Array = this._uidItemIndex[uid] as Array;
         if(list == null)
         {
            return null;
         }
         if(stopAtMessage == null)
         {
            i = list.length - 1;
            while(i >= 0 && MessageCacheItem(list[i]).message.operation == DataMessage.UPDATE_COLLECTION_OPERATION)
            {
               i--;
            }
            if(i < 0)
            {
               return null;
            }
            return list[i];
         }
         for(i = this._items.length - 1; i >= 0; i--)
         {
            result = MessageCacheItem(this._items.getItemAt(i));
            if(result.message == stopAtMessage)
            {
               return null;
            }
            if(result.dataService == dataService && result.message.operation != DataMessage.UPDATE_COLLECTION_OPERATION && IManaged(result.item).uid == uid)
            {
               return result;
            }
         }
         return null;
      }
      
      function getLastOperation(dataService:ConcreteDataService, uid:String) : uint
      {
         var cacheItem:MessageCacheItem = null;
         var result:uint = DataMessage.UNKNOWN_OPERATION;
         if(uid)
         {
            cacheItem = this.getLastCacheItem(dataService,uid,null);
            if(cacheItem)
            {
               result = cacheItem.message.operation;
            }
         }
         return result;
      }
      
      function getCacheItem(msgId:String) : MessageCacheItem
      {
         return this._messageIdCacheItemIndex[msgId];
      }
      
      function getCacheItems() : Array
      {
         return this._items.source;
      }
      
      function getMessages(dataService:ConcreteDataService, uid:String, batchId:String = null, includeUCs:Boolean = false, collection:ListCollectionView = null, destination:String = null) : Array
      {
         var messages:Array = null;
         var cacheItem:MessageCacheItem = null;
         var msg:DataMessage = null;
         var i:int = 0;
         var list:Array = null;
         if(uid != null)
         {
            list = this._uidItemIndex[uid] as Array;
            if(list == null)
            {
               return [];
            }
            messages = new Array();
            for(i = 0; i < list.length; i++)
            {
               msg = list[i].message;
               if(!(!includeUCs && msg.operation == DataMessage.UPDATE_COLLECTION_OPERATION))
               {
                  if(batchId != null)
                  {
                     msg.correlationId = batchId;
                  }
                  if(msg.clientId == null)
                  {
                     msg.clientId = dataService.consumer.clientId;
                  }
                  messages.push(msg);
               }
            }
            return messages;
         }
         messages = new Array();
         for(i = 0; i < this._items.length; i++)
         {
            cacheItem = MessageCacheItem(this._items.getItemAt(i));
            if(!(!includeUCs && cacheItem.message.operation == DataMessage.UPDATE_COLLECTION_OPERATION))
            {
               if(batchId != null)
               {
                  cacheItem.message.correlationId = batchId;
               }
               if((dataService == null || cacheItem.dataService.isSubtypeOf(dataService)) && (collection == null || collection.getItemIndex(cacheItem.item) != -1))
               {
                  msg = cacheItem.message;
                  if(msg.clientId == null && cacheItem.dataService != null)
                  {
                     msg.clientId = cacheItem.dataService.consumer.clientId;
                  }
                  if(uid !== null)
                  {
                     if(uid === cacheItem.uid)
                     {
                        messages.push(msg);
                     }
                  }
                  else
                  {
                     messages.push(msg);
                  }
               }
            }
         }
         return messages;
      }
      
      function extractMessages(messages:Array, itemsOrCollections:Array = null, cascadeCommit:Boolean = false) : MessageBatch
      {
         var cacheItem:MessageCacheItem = null;
         var msg:DataMessage = null;
         var localMsg:DataMessage = null;
         var ucmsg:UpdateCollectionMessage = null;
         var j:int = 0;
         var commitObj:Object = null;
         var dataList:DataList = null;
         var token:AsyncToken = null;
         var batch:MessageBatch = new MessageBatch();
         batch.dataStore = this.dataStore;
         var messageIds:Object = this.getMessageIdsForItems(itemsOrCollections,cascadeCommit);
         for(var i:uint = 0; i < this._items.length; i++)
         {
            cacheItem = MessageCacheItem(this._items.getItemAt(i));
            msg = cacheItem.message;
            if(messageIds[msg.messageId] != null)
            {
               msg.correlationId = this.id;
               messages.push(msg);
               this.removeFromIndex(cacheItem);
               this._items.removeItemAt(i);
               i--;
               this.sendCommitRequiredChange(this._items.length == 0);
               if(msg.clientId == null)
               {
                  msg.clientId = cacheItem.dataService.consumer.clientId;
               }
               batch.addCacheItem(cacheItem.dataService,msg,cacheItem.item);
            }
         }
         if(this._updateCollectionMessages != null)
         {
            for(i = 0; i < this._updateCollectionMessages.length; i++)
            {
               ucmsg = this._updateCollectionMessages[i];
               for(j = 0; j < itemsOrCollections.length; j++)
               {
                  commitObj = itemsOrCollections[j];
                  if(commitObj is ListCollectionView)
                  {
                     dataList = DataList(ListCollectionView(commitObj).list);
                     if(ucmsg.destination == dataList.service.destination && Managed.compare(ucmsg.collectionId,dataList.collectionId,-1,["uid"]) == 0)
                     {
                        ucmsg.correlationId = this.id;
                        messages.push(ucmsg);
                        this._updateCollectionMessages.splice(i,1);
                        i--;
                        if(ucmsg.clientId == null)
                        {
                           ucmsg.clientId = dataList.service.consumer.clientId;
                        }
                        batch.addUpdateCollectionMessage(ucmsg);
                        break;
                     }
                  }
               }
            }
         }
         for each(localMsg in messages)
         {
            for each(token in this.tokenCache)
            {
               if(token.message && token.message.messageId == localMsg.messageId)
               {
                  batch.tokenCache.push(token);
                  batch.tokenCacheIndex[token.message.messageId] = token;
               }
            }
         }
         if(batch.length > 0 || batch.updateCollectionMessages && batch.updateCollectionMessages.length > 0)
         {
            this.dataStore.messageCache.addBatch(batch,false);
            return batch;
         }
         return null;
      }
      
      function getMessageIdsForItems(itemsOrCollections:Array, cascadeCommit:Boolean) : Object
      {
         var commitObj:Object = null;
         var dataList:DataList = null;
         var list:IList = null;
         var arrItems:Array = null;
         var it:int = 0;
         var cds:ConcreteDataService = null;
         var messageIds:Object = {};
         var visited:Dictionary = new Dictionary();
         for(var cc:int = 0; cc < itemsOrCollections.length; cc++)
         {
            commitObj = itemsOrCollections[cc];
            dataList = null;
            if(commitObj is ListCollectionView)
            {
               list = ListCollectionView(commitObj).list;
               if(list is DataList && DataList(list).referenceCount > 0)
               {
                  dataList = DataList(list);
                  arrItems = dataList.localItems;
                  for(it = 0; it < arrItems.length; it++)
                  {
                     this.addMessageIdsForItem(dataList.service,arrItems[it],cascadeCommit,messageIds,visited);
                  }
               }
               if(dataList == null)
               {
                  throw new DataServiceError("Commit called with a collection at array location: " + cc + " which is not a managed collection in the data service: " + ObjectUtil.toString(commitObj));
               }
            }
            else
            {
               cds = null;
               if(commitObj is IManaged)
               {
                  cds = this.dataStore.getDataServiceForValue(commitObj);
               }
               if(cds == null)
               {
                  throw new DataServiceError("Commit called with an item at array location: " + cc + " which is not a managed item in this dataStore: " + ObjectUtil.toString(commitObj));
               }
               this.addMessageIdsForItem(cds,commitObj,cascadeCommit,messageIds,visited);
            }
         }
         return messageIds;
      }
      
      function updateNewIdentities(messages:Array) : void
      {
         var msg:Object = null;
         var dmsg:DataMessage = null;
         var oldCacheItem:MessageCacheItem = null;
         var cds:ConcreteDataService = null;
         var oldMsg:DataMessage = null;
         var updatedAny:Boolean = false;
         for(var i:int = 0; i < messages.length; i++)
         {
            msg = messages[i];
            if(msg is SequencedMessage)
            {
               dmsg = SequencedMessage(msg).dataMessage;
               addr69:
               if(dmsg.isCreate())
               {
                  oldCacheItem = this.getCacheItem(dmsg.messageId);
                  if(oldCacheItem != null)
                  {
                     cds = this.dataStore.getDataService(dmsg.destination);
                     oldMsg = oldCacheItem.message;
                     oldCacheItem.newIdentity = cds.getIdentityMap(dmsg.unwrapBody());
                     if(this._newUIDToMessageIdIndex == null)
                     {
                        this._newUIDToMessageIdIndex = {};
                     }
                     this._newUIDToMessageIdIndex[cds.metadata.getUID(oldCacheItem.newIdentity)] = oldMsg.messageId;
                     updatedAny = true;
                  }
               }
            }
            else if(msg is DataMessage)
            {
               dmsg = DataMessage(msg);
               §§goto(addr69);
            }
         }
         if(updatedAny)
         {
            this.dataStore.messageCache.replaceMessageIdsForNewItems();
         }
      }
      
      private function addMessageIdsForItem(cds:ConcreteDataService, commitItem:Object, cascadeCommit:Boolean, messageIds:Object, visited:Dictionary) : void
      {
         var cj:int = 0;
         var md:Metadata = null;
         var propName:* = null;
         var assoc:ManagedAssociation = null;
         var subList:DataList = null;
         var itemList:Array = null;
         var j:int = 0;
         var uid:String = IManaged(commitItem).uid;
         var cis:Array = this._uidItemIndex[uid] as Array;
         if(cis != null)
         {
            for(cj = 0; cj < cis.length; cj++)
            {
               messageIds[cis[cj].message.messageId] = true;
            }
         }
         if(visited[commitItem] != null)
         {
            return;
         }
         visited[commitItem] = true;
         if(cascadeCommit)
         {
            md = cds.getItemMetadata(commitItem);
            for(propName in md.associations)
            {
               assoc = ManagedAssociation(md.associations[propName]);
               subList = cds.getDataListForAssociation(commitItem,assoc);
               if(subList != null)
               {
                  itemList = subList.localItems;
                  for(j = 0; j < itemList.length; j++)
                  {
                     this.addMessageIdsForItem(assoc.service,itemList[j],cascadeCommit,messageIds,visited);
                  }
                  continue;
               }
            }
         }
      }
      
      public function get length() : uint
      {
         if(this._items != null)
         {
            return this._items.length;
         }
         return 0;
      }
      
      public function readExternal(input:IDataInput) : void
      {
         var cacheItem:MessageCacheItem = null;
         var destination:String = null;
         var uid:String = null;
         var ds:ConcreteDataService = null;
         var version:uint = input.readUnsignedInt();
         var len:uint = input.readUnsignedInt();
         for(var i:int = 0; i < len; i++)
         {
            destination = input.readUTF();
            uid = input.readUTF();
            ds = ConcreteDataService.lookupService(destination);
            cacheItem = new MessageCacheItem();
            cacheItem.dataService = ds;
            cacheItem.uid = uid;
            cacheItem.message = input.readObject();
            if(uid != "" && !(cacheItem.message is UpdateCollectionMessage))
            {
               if(ds != null)
               {
                  this.setCacheItem(cacheItem,ds.getItem(uid));
               }
            }
            cacheItem.message.clientId = null;
            this._items.addItem(cacheItem);
            this.addToIndex(cacheItem,uid);
         }
         this._updateCollectionMessages = input.readObject();
         if(this._updateCollectionMessages != null)
         {
            for(i = 0; i < this._updateCollectionMessages.length; i++)
            {
               this._updateCollectionMessages[i].clientId = null;
            }
         }
         if(version > 1)
         {
            this._id = input.readObject() as String;
            this.batchMessage = input.readObject() as DataMessage;
            this.properties = input.readObject();
         }
      }
      
      public function removeMessage(msg:DataMessage) : void
      {
         var ucmsg:UpdateCollectionMessage = null;
         var i:int = 0;
         var cacheItem:MessageCacheItem = null;
         var p:* = null;
         if(msg is UpdateCollectionMessage && UpdateCollectionMessage(msg).collectionId is Array)
         {
            if(this._updateCollectionMessages != null)
            {
               for(i = 0; i < this._updateCollectionMessages.length; i++)
               {
                  ucmsg = UpdateCollectionMessage(this._updateCollectionMessages[i]);
                  if(ucmsg.messageId === msg.messageId)
                  {
                     this._updateCollectionMessages.splice(i,1);
                     this.releaseDataListForUpdateCollection(ucmsg);
                     return;
                  }
               }
            }
         }
         else
         {
            for(i = 0; i < this._items.length; i++)
            {
               cacheItem = MessageCacheItem(this._items.getItemAt(i));
               if(cacheItem.message.messageId == msg.messageId)
               {
                  this.removeFromIndex(cacheItem);
                  this._items.removeItemAt(i);
                  this.sendCommitRequiredChange(this._items.length == 0);
                  if(this._items.length == 0)
                  {
                     for(p in this._uidItemIndex)
                     {
                        throw new DataServiceError("UIDItemIndex not empty even though items are empty: " + p);
                     }
                     var _loc6_:int = 0;
                     var _loc7_:* = this._createdItems;
                     for(p in this._createdItems)
                     {
                        throw new DataServiceError("createdItems index not empty even though items are empty " + p);
                     }
                  }
                  if(msg is UpdateCollectionMessage)
                  {
                     this.releaseDataListForUpdateCollection(msg as UpdateCollectionMessage);
                  }
                  return;
               }
            }
         }
      }
      
      private function releaseDataListForUpdateCollection(ucmsg:UpdateCollectionMessage) : void
      {
         var dataService:ConcreteDataService = this.dataStore.getDataService(ucmsg.destination);
         var dataList:DataList = dataService.getDataListWithCollectionId(ucmsg.collectionId);
         if(dataList != null)
         {
            if(dataList.updateCollectionReferences <= 0)
            {
               if(Log.isError())
               {
                  this.dataStore.log.error("Invalid releaseDataListForUpdateCollection - data list not referenced by an update collection");
               }
            }
            else
            {
               dataList.updateCollectionReferences--;
               dataService.releaseDataList(dataList,false,false,null,null,true,false);
            }
         }
      }
      
      function replace(oldMessageId:String, newMessage:DataMessage) : void
      {
         var cacheItem:MessageCacheItem = null;
         for(var i:uint = 0; i < this._items.length; i++)
         {
            cacheItem = MessageCacheItem(this._items.getItemAt(i));
            if(cacheItem.message.messageId == oldMessageId)
            {
               this.removeFromIndex(cacheItem);
               cacheItem.message = newMessage;
               this.addToIndex(cacheItem);
               break;
            }
         }
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         var cacheItem:MessageCacheItem = null;
         var uid:String = null;
         output.writeUnsignedInt(MessageBatch.VERSION);
         output.writeUnsignedInt(this.length);
         for(var i:int = 0; i < this.length; i++)
         {
            cacheItem = MessageCacheItem(this._items.getItemAt(i));
            output.writeUTF(cacheItem.dataService.destination);
            uid = cacheItem.uid;
            if(uid == null)
            {
               uid = "";
            }
            output.writeUTF(uid);
            output.writeObject(cacheItem.message);
         }
         output.writeObject(this._updateCollectionMessages);
         output.writeObject(this._id);
         output.writeObject(this.batchMessage);
         output.writeObject(this.properties);
      }
      
      function getMessageIdForNewUID(newUID:String) : String
      {
         if(this._newUIDToMessageIdIndex == null)
         {
            return null;
         }
         return this._newUIDToMessageIdIndex[newUID];
      }
      
      function getUpdateCollectionMessages(destination:String, collectionId:Object, identity:Object = null) : Array
      {
         var list:Array = null;
         var uid:String = null;
         var ci:MessageCacheItem = null;
         var ucmsg:UpdateCollectionMessage = null;
         var i:int = 0;
         var result:Array = [];
         var preserveOrder:Boolean = collectionId is String || !(collectionId is Array);
         if(preserveOrder || collectionId == null)
         {
            if(collectionId != null)
            {
               if(collectionId is String)
               {
                  uid = collectionId as String;
                  list = this._uidItemIndex[uid] as Array;
               }
               else if(collectionId["parent"] != null)
               {
                  uid = this.dataStore.getDataService(collectionId["parent"]).getUIDFromReferencedId(collectionId["id"]);
                  list = this._uidItemIndex[uid] as Array;
               }
               else
               {
                  list = this._items.source;
               }
            }
            else
            {
               list = this._items.source;
            }
            if(list != null)
            {
               for(i = 0; i < list.length; i++)
               {
                  ci = MessageCacheItem(list[i]);
                  if(ci.message.operation == DataMessage.UPDATE_COLLECTION_OPERATION)
                  {
                     ucmsg = UpdateCollectionMessage(ci.message);
                     if(collectionId == null || collectionId is String || Managed.compare(ucmsg.collectionId,collectionId,-1,["uid"]) == 0 && (identity == null || ucmsg.containsIdentity(identity)))
                     {
                        result.push(ucmsg);
                     }
                  }
               }
            }
         }
         if(!preserveOrder || collectionId == null)
         {
            if(this._updateCollectionMessages != null)
            {
               for(i = 0; i < this._updateCollectionMessages.length; i++)
               {
                  ucmsg = this._updateCollectionMessages[i];
                  if(destination == null || ucmsg.destination == destination && (collectionId == null || Managed.compare(ucmsg.collectionId,collectionId,-1,["uid"]) == 0) && (identity == null || ucmsg.containsIdentity(identity)))
                  {
                     result.push(ucmsg);
                  }
               }
            }
         }
         return result;
      }
      
      function hasUpdateCollectionMessages(destination:String, collectionId:Object) : Boolean
      {
         var ucmsg:UpdateCollectionMessage = null;
         var i:int = 0;
         var preserveOrder:Boolean = !(collectionId is Array);
         if(preserveOrder)
         {
            return this.getUpdateCollectionMessages(destination,collectionId,null).length > 0;
         }
         if(this._updateCollectionMessages != null)
         {
            for(i = 0; i < this._updateCollectionMessages.length; i++)
            {
               ucmsg = this._updateCollectionMessages[i];
               if(ucmsg.destination == destination && Managed.compare(ucmsg.collectionId,collectionId,-1,["uid"]) == 0)
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      function restoreUpdateCollections(newMsgs:Array) : void
      {
         var i:int = 0;
         var destination:String = null;
         var collectionId:Object = null;
         var dataList:DataList = null;
         var ucMsgs:Array = null;
         if(newMsgs == null || newMsgs.length == 0)
         {
            return;
         }
         var orig:Array = this._updateCollectionMessages;
         this._updateCollectionMessages = newMsgs;
         if(newMsgs != null)
         {
            for(i = 0; i < newMsgs.length; i++)
            {
               destination = newMsgs[i].destination;
               collectionId = newMsgs[i].collectionId;
               dataList = this.dataStore.getDataService(destination).getDataListWithCollectionId(collectionId);
               if(dataList != null)
               {
                  dataList.referenceCount++;
                  dataList.updateCollectionReferences++;
               }
            }
         }
         if(orig != null)
         {
            for(i = 0; i < orig.length; i++)
            {
               destination = orig[i].destination;
               collectionId = orig[i].collectionId;
               ucMsgs = this.getUpdateCollectionMessages(destination,collectionId);
               if(ucMsgs.length == 0)
               {
                  if(newMsgs == null)
                  {
                     this._updateCollectionMessages = newMsgs = new Array();
                  }
                  newMsgs.push(orig[i]);
               }
               else
               {
                  ucMsgs[0].appendUpdateCollectionMessage(orig[i]);
                  this.releaseDataListForUpdateCollection(orig[i]);
               }
            }
         }
      }
      
      function get updateCollectionMessages() : Array
      {
         return this._updateCollectionMessages;
      }
      
      function getOrCreateUpdateCollectionMessage(dataService:ConcreteDataService, dataList:DataList, stopAtItem:Object) : UpdateCollectionMessage
      {
         var cacheItem:MessageCacheItem = null;
         var i:int = 0;
         var ucmsg:UpdateCollectionMessage = null;
         var ucMsgs:Array = null;
         var result:UpdateCollectionMessage = null;
         var collectionId:Object = dataList.collectionId;
         var preserveOrder:Boolean = !(collectionId is Array);
         if(preserveOrder)
         {
            for(i = this._items.length - 1; i >= 0; i--)
            {
               cacheItem = MessageCacheItem(this._items.getItemAt(i));
               if(stopAtItem != null && cacheItem.message.isCreate() && stopAtItem == cacheItem.message.unwrapBody())
               {
                  break;
               }
               if(!(cacheItem.dataService != dataService || cacheItem.message.operation != DataMessage.UPDATE_COLLECTION_OPERATION))
               {
                  ucmsg = UpdateCollectionMessage(cacheItem.message);
                  if(Managed.compare(ucmsg.collectionId,collectionId,-1,["uid"]) == 0)
                  {
                     result = ucmsg;
                     break;
                  }
               }
            }
         }
         else
         {
            ucMsgs = this.getUpdateCollectionMessages(dataService.destination,collectionId);
            if(ucMsgs.length > 0)
            {
               result = ucMsgs[0];
            }
         }
         if(result == null)
         {
            result = new UpdateCollectionMessage();
            result.updateMode = UpdateCollectionMessage.CLIENT_UPDATE;
            result.destination = dataService.destination;
            result.collectionId = collectionId;
            result.clientId = dataService.consumer.clientId;
            if(dataList.referenceCount > 0)
            {
               dataList.referenceCount++;
               dataList.updateCollectionReferences++;
               dataService.addMessageRoutingHeaders(result);
               if(!preserveOrder)
               {
                  if(this._updateCollectionMessages == null)
                  {
                     this._updateCollectionMessages = new Array();
                  }
                  this._updateCollectionMessages.push(result);
               }
               else
               {
                  this.addCacheItem(dataService,result,null);
               }
            }
            else
            {
               throw DataServiceError("Collection update logged for released collection");
            }
         }
         return result;
      }
      
      function restoreMessageCacheItems(messages:Array) : void
      {
         var i:int = 0;
         if(messages != null && messages.length > 0)
         {
            for(i = 0; i < messages.length; i++)
            {
               this.addToIndex(messages[i]);
            }
            this._items.source = messages.concat(this._items.source);
            if(Log.isDebug())
            {
               this.dataStore.log.debug("Restored messages: 0 to " + messages.length + " in batch: " + this.toString());
            }
         }
      }
      
      function setCacheItem(cacheItem:MessageCacheItem, item:Object) : void
      {
         cacheItem.item = item;
         if(cacheItem.message.isCreate() && item != null)
         {
            this._createdItems[ConcreteDataService.unnormalize(cacheItem.item)] = cacheItem;
         }
      }
      
      function applyTokenChain(token:AsyncToken) : void
      {
         var subtoken:AsyncToken = null;
         var tokenChain:Object = this.tokenCache.length > 0?{}:null;
         token[DataStore.TOKEN_CHAIN] = tokenChain;
         if(this.tokenCache.length == 0)
         {
            trace("MessageBatch.applyTokenChain : emtpy token cache");
         }
         else
         {
            trace("MessageBatch.applyTokenChain : token cache len=" + this.tokenCache.length);
         }
         for(var i:int = 0; i < this.tokenCache.length; i++)
         {
            subtoken = AsyncToken(this.tokenCache[i]);
            if(subtoken.message != null)
            {
               tokenChain[subtoken.message.messageId] = subtoken;
            }
            else
            {
               trace("MessageBatch.applyTokenChain missing message");
            }
         }
      }
      
      override public function toString() : String
      {
         var cacheItem:MessageCacheItem = null;
         var uid:String = null;
         var s:String = "Batch[id=" + this.id + " items=[";
         for(var i:int = 0; i < this._items.length; i++)
         {
            cacheItem = MessageCacheItem(this._items.getItemAt(i));
            uid = cacheItem.uid;
            if(i != 0)
            {
               s = s + ", ";
            }
            s = s + DataMessage.getOperationAsString(cacheItem.message.operation);
            s = s + (" " + cacheItem.dataService.destination);
            s = s + (uid != null?": uid=" + uid:"");
            s = s + (": messageId=" + cacheItem.message.messageId);
         }
         s = s + "]";
         return s;
      }
   }
}
