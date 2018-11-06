package mx.data
{
   import flash.events.EventDispatcher;
   import flash.utils.Dictionary;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import mx.collections.ArrayCollection;
   import mx.collections.IList;
   import mx.data.errors.DataServiceError;
   import mx.data.messages.DataMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.Managed;
   import mx.data.utils.SerializationDescriptor;
   import mx.data.utils.SerializationProxy;
   import mx.events.PropertyChangeEvent;
   import mx.logging.Log;
   import mx.utils.ObjectUtil;
   import mx.utils.UIDUtil;
   
   [RemoteClass]
   [ExcludeClass]
   public class DataMessageCache extends EventDispatcher implements IExternalizable
   {
      
      private static const VERSION:uint = 3;
      
      static var currentBatchSequence:int = 0;
       
      
      private var _committedAndSent:Array;
      
      private var _committedUnsent:Array;
      
      private var _batchIndex:Object;
      
      private var _commitRequired:Boolean;
      
      private var _forwardRefs:Dictionary;
      
      private var _forwardRefsById:Object;
      
      private var _currentBatch:MessageBatch;
      
      var uncommittedBatches:ArrayCollection;
      
      var commitQueueMode:int;
      
      var currentCommitResult:MessageBatch = null;
      
      var requiresSave:Boolean = false;
      
      var dataStore:DataStore;
      
      var restoredConflicts:Array;
      
      public function DataMessageCache()
      {
         this._committedAndSent = [];
         this._committedUnsent = [];
         this._batchIndex = {};
         this._forwardRefs = new Dictionary();
         this._forwardRefsById = new Object();
         this.uncommittedBatches = new ArrayCollection();
         this.commitQueueMode = DataStore.CQ_AUTO;
         super();
         this._currentBatch = new MessageBatch();
         this.addBatch(this._currentBatch,true);
         this.uncommittedBatches.addItem(this._currentBatch);
      }
      
      public function clearForwardRefs() : void
      {
         var k:* = undefined;
         for(k in this._forwardRefs)
         {
            delete this._forwardRefs[k];
         }
         for(k in this._forwardRefsById)
         {
            delete this._forwardRefsById[k];
         }
      }
      
      public function get commitRequired() : Boolean
      {
         return this._commitRequired;
      }
      
      public function commitRequiredOn(item:Object) : Boolean
      {
         var uncommittedItem:Object = null;
         if(item == null)
         {
            return false;
         }
         if(item.uid == null)
         {
            return true;
         }
         var foundObjectInUncommited:Boolean = false;
         var items:ArrayCollection = this._currentBatch.items;
         var j:int = 0;
         while(!foundObjectInUncommited && j < items.length)
         {
            uncommittedItem = items[j];
            if(item.uid == uncommittedItem.uid)
            {
               foundObjectInUncommited = true;
            }
            j++;
         }
         return foundObjectInUncommited;
      }
      
      public function get committed() : Array
      {
         if(this._committedUnsent.length == 0)
         {
            return this._committedAndSent;
         }
         return this._committedAndSent.concat(this._committedUnsent);
      }
      
      public function get currentBatch() : MessageBatch
      {
         return this._currentBatch;
      }
      
      public function get pending() : Array
      {
         if(this._committedUnsent.length == 0 && this._committedAndSent.length == 0)
         {
            return this.uncommittedBatches.source;
         }
         return this._committedAndSent.concat(this._committedUnsent,this.uncommittedBatches.source);
      }
      
      public function get unsent() : Array
      {
         return this._committedUnsent.concat(this.uncommittedBatches.source);
      }
      
      public function addMessage(dataService:ConcreteDataService, msg:DataMessage, item:Object = null) : void
      {
         if(Log.isDebug())
         {
            dataService.log.debug("Queuing message for server:\n{0}",msg.toString());
         }
         if(dataService.autoCommit)
         {
            dataService.reconnect();
         }
         dataService.addMessageRoutingHeaders(msg);
         this._currentBatch.addCacheItem(dataService,msg,item);
      }
      
      public function clear() : void
      {
         this._currentBatch.clear();
         this._committedAndSent = [];
         this._committedUnsent = [];
         this.uncommittedBatches.removeAll();
         this.uncommittedBatches.addItem(this._currentBatch);
         this.checkCommitRequired();
      }
      
      public function addForwardReference(item:Object) : String
      {
         item = ConcreteDataService.unnormalize(item);
         var msgId:String = this._forwardRefs[item];
         if(msgId == null)
         {
            msgId = UIDUtil.createUID();
            this._forwardRefs[item] = msgId;
            this._forwardRefsById[msgId] = item;
         }
         return msgId;
      }
      
      public function getCreatedItem(dataService:ConcreteDataService, msgIdOrUID:String) : Object
      {
         var msgId:String = null;
         var msgs:Array = null;
         var i:int = 0;
         var dmsg:DataMessage = null;
         var result:Object = this._forwardRefsById[msgIdOrUID];
         if(result == null)
         {
            if(this.currentCommitResult != null)
            {
               msgId = this.currentCommitResult.getMessageIdForNewUID(msgIdOrUID);
               if(msgId != null)
               {
                  result = dataService.getItem(msgId);
               }
            }
            if(result == null)
            {
               msgs = this.getPendingMessages(dataService,msgIdOrUID);
               for(i = 0; i < msgs.length; i++)
               {
                  dmsg = DataMessage(msgs[i]);
                  if(dmsg.operation == DataMessage.CREATE_OPERATION)
                  {
                     return dmsg.unwrapBody();
                  }
               }
            }
         }
         return result;
      }
      
      public function getCreateMessageIdentity(dataService:ConcreteDataService, item:Object) : Object
      {
         var rawItem:Object = ConcreteDataService.unnormalize(item);
         var msgId:Object = this._forwardRefs[rawItem];
         if(msgId != null)
         {
            return String(msgId);
         }
         var cacheItem:MessageCacheItem = this.getCreateCacheItem(dataService,item);
         if(cacheItem != null)
         {
            if(cacheItem.newIdentity != null)
            {
               return cacheItem.newIdentity;
            }
            return cacheItem.message.messageId;
         }
         return null;
      }
      
      public function getCreateMessage(dataService:ConcreteDataService, item:Object) : DataMessage
      {
         var ci:MessageCacheItem = this.getCreateCacheItem(dataService,item);
         return ci == null?null:ci.message;
      }
      
      public function getCreateCacheItem(dataService:ConcreteDataService, item:Object) : MessageCacheItem
      {
         var ci:MessageCacheItem = null;
         var batch:MessageBatch = null;
         if((ci = this._currentBatch.getCreateCacheItem(dataService,item)) != null)
         {
            return ci;
         }
         var allPending:Array = this.pending;
         for(var i:int = 0; i < allPending.length; i++)
         {
            batch = allPending[i];
            if((ci = batch.getCreateCacheItem(dataService,item)) != null)
            {
               return ci;
            }
         }
         return null;
      }
      
      public function commitUncommitted() : Boolean
      {
         var sendCommit:Boolean = this.commitNewBatch(this._currentBatch);
         var oldUC:MessageBatch = this._currentBatch;
         this._currentBatch = new MessageBatch();
         this._currentBatch.dataStore = this.dataStore;
         this.addBatch(this._currentBatch,true);
         this.uncommittedBatches.addItem(this._currentBatch);
         this.checkCommitRequired();
         this.dataStore.sendCurrentBatchChange(oldUC,this._currentBatch);
         return sendCommit;
      }
      
      public function commitNewBatch(batch:MessageBatch) : Boolean
      {
         var send:Boolean = false;
         var ix:int = this.uncommittedBatches.getItemIndex(batch);
         if(ix != -1)
         {
            this.uncommittedBatches.removeItemAt(ix);
         }
         if(this.allowedToSend(batch))
         {
            this._committedAndSent.push(batch);
            send = true;
         }
         else
         {
            this._committedUnsent.push(batch);
            send = false;
         }
         this.checkCommitRequired();
         return send;
      }
      
      public function allowedToSend(batch:MessageBatch) : Boolean
      {
         if(this._committedAndSent.length == 0)
         {
            return true;
         }
         if(this.commitQueueMode == DataStore.CQ_NOWAIT)
         {
            return true;
         }
         if(this.commitQueueMode == DataStore.CQ_ONE_AT_A_TIME)
         {
            return false;
         }
         return !MessageBatch(this._committedAndSent[this._committedAndSent.length - 1]).hasCreates;
      }
      
      public function getBatch(batchId:String) : MessageBatch
      {
         return this._batchIndex[batchId];
      }
      
      public function getItem(msgId:String, batchId:String) : Object
      {
         var bmc:MessageBatch = null;
         if(batchId)
         {
            bmc = this._batchIndex[batchId];
            if(bmc)
            {
               return bmc.getItem(msgId);
            }
            return null;
         }
         return this._currentBatch.getItem(msgId);
      }
      
      public function createBatch(itemsOrCollection:Array = null, cascadeCommit:Boolean = true, properties:Object = null) : MessageBatch
      {
         var batch:MessageBatch = null;
         if(itemsOrCollection == null)
         {
            batch = this.currentBatch;
            this._currentBatch = new MessageBatch();
            this._currentBatch.dataStore = this.dataStore;
            this.addBatch(this._currentBatch,true);
            this.uncommittedBatches.addItem(this._currentBatch);
            this.dataStore.sendCurrentBatchChange(batch,this._currentBatch);
         }
         else
         {
            batch = this.currentBatch.extractMessages([],itemsOrCollection,cascadeCommit);
            this.uncommittedBatches.addItemAt(batch,this.uncommittedBatches.length - 1);
            this.addBatch(batch,true);
         }
         if(properties != null)
         {
            batch.properties = properties;
         }
         this.requiresSave = true;
         return batch;
      }
      
      public function getAnyCacheItem(msgId:String) : MessageCacheItem
      {
         var batch:MessageBatch = null;
         var mci:MessageCacheItem = this._currentBatch.getCacheItem(msgId);
         if(mci != null)
         {
            return mci;
         }
         var allCommitted:Array = this.committed;
         for(var i:int = 0; i < allCommitted.length; i++)
         {
            batch = allCommitted[i];
            mci = batch.getCacheItem(msgId);
            if(mci != null)
            {
               return mci;
            }
         }
         return null;
      }
      
      public function getOldestMessage(dataService:ConcreteDataService, uid:String) : DataMessage
      {
         var batch:MessageBatch = null;
         var item:MessageCacheItem = null;
         var lastItem:MessageCacheItem = null;
         var allPending:Array = this.pending;
         for(var i:int = 0; i < allPending.length; i++)
         {
            batch = allPending[i];
            item = batch.getLastCacheItem(dataService,uid,null);
            if(item != null)
            {
               if(lastItem == null || lastItem.message.timestamp > item.message.timestamp)
               {
                  lastItem = item;
               }
            }
         }
         if(lastItem != null)
         {
            return lastItem.message;
         }
         return null;
      }
      
      public function getLastUncommittedMessage(dataService:ConcreteDataService, uid:String) : DataMessage
      {
         var ci:MessageCacheItem = this._currentBatch.getLastCacheItem(dataService,uid,null);
         if(ci != null)
         {
            return ci.message;
         }
         return null;
      }
      
      public function getLastUncommittedOperation(dataService:ConcreteDataService, uid:String) : uint
      {
         return this._currentBatch.getLastOperation(dataService,uid);
      }
      
      public function getUncommittedMessages(dataService:ConcreteDataService, uid:String = null, batchId:String = null, includeUC:Boolean = false) : Array
      {
         return this._currentBatch.getMessages(dataService,uid,batchId,includeUC);
      }
      
      public function getPendingMessages(dataService:ConcreteDataService, uid:String = null, includeUC:Boolean = false) : Array
      {
         var batch:MessageBatch = null;
         var toAdd:Array = null;
         var allPending:Array = this.pending;
         var messages:Array = new Array();
         for(var i:int = allPending.length - 1; i >= 0; i--)
         {
            batch = allPending[i];
            if(!batch.commitComplete)
            {
               toAdd = batch.getMessages(dataService,uid,null,includeUC);
               if(toAdd != null && toAdd.length > 0)
               {
                  messages = messages.concat(toAdd);
               }
            }
         }
         return messages;
      }
      
      function getPendingDeleteMessage(dataService:ConcreteDataService, uid:String) : DataMessage
      {
         var messages:Array = this.getPendingMessages(dataService,uid,false);
         for(var i:int = 0; i < messages.length; i++)
         {
            if(messages[i].operation == DataMessage.DELETE_OPERATION)
            {
               return messages[i] as DataMessage;
            }
         }
         return null;
      }
      
      public function getUnsentMessages(dataService:ConcreteDataService, uid:String = null, includeUC:Boolean = false) : Array
      {
         var batch:MessageBatch = null;
         var toAdd:Array = null;
         var allUnsent:Array = this.unsent;
         var messages:Array = new Array();
         for(var i:int = allUnsent.length - 1; i >= 0; i--)
         {
            batch = allUnsent[i];
            toAdd = batch.getMessages(dataService,uid,null,includeUC);
            if(toAdd != null && toAdd.length > 0)
            {
               messages = messages.concat(toAdd);
            }
         }
         return messages;
      }
      
      public function getUnsentUpdateCollections(destination:String, collectionId:Object, includeCurrent:Boolean = false, identity:Object = null) : Array
      {
         var ucMsgs:Array = null;
         var batch:MessageBatch = null;
         var result:Array = new Array();
         var allUnsent:Array = this.unsent;
         for(var i:int = allUnsent.length - 1; i >= 0; i--)
         {
            batch = allUnsent[i];
            ucMsgs = batch.getUpdateCollectionMessages(destination,collectionId,identity);
            result = result.concat(ucMsgs);
         }
         return result;
      }
      
      public function getPendingUpdateCollections(destination:String, collectionId:Object, includeCurrent:Boolean = false, identity:Object = null) : Array
      {
         var ucMsgs:Array = null;
         var batch:MessageBatch = null;
         var j:int = 0;
         var result:Array = new Array();
         var allPending:Array = this.pending;
         for(var i:int = allPending.length - 1; i >= 0; i--)
         {
            batch = allPending[i];
            if(includeCurrent || !batch.commitComplete)
            {
               ucMsgs = batch.getUpdateCollectionMessages(destination,collectionId,identity);
               for(j = 0; j < ucMsgs.length; j++)
               {
                  result.push(ucMsgs[j]);
               }
            }
         }
         return result;
      }
      
      public function getUncommittedUpdateCollections(destination:String, collectionId:Object, identity:Object = null) : Array
      {
         var result:Array = this._currentBatch.getUpdateCollectionMessages(destination,collectionId,identity);
         return result;
      }
      
      public function getPendingUpdateCollectionReferences(destination:String, oldId:Object) : Array
      {
         var ucMsgs:Array = null;
         var batch:MessageBatch = null;
         var j:int = 0;
         var allPending:Array = this.pending;
         var result:Array = null;
         for(var i:int = allPending.length - 1; i >= 0; i--)
         {
            batch = allPending[i];
            if(!batch.commitComplete && batch.updateCollectionReferenceIndex != null)
            {
               ucMsgs = batch.updateCollectionReferenceIndex[oldId];
               if(ucMsgs != null)
               {
                  for(j = 0; j < ucMsgs.length; j++)
                  {
                     if(result == null)
                     {
                        result = new Array();
                     }
                     result.push(ucMsgs[j]);
                  }
               }
            }
         }
         return result;
      }
      
      public function hasCommittedUpdateCollections(destination:String, collectionId:Object) : Boolean
      {
         var batch:MessageBatch = null;
         var allCommitted:Array = this.committed;
         for(var i:int = 0; i < allCommitted.length; i++)
         {
            batch = allCommitted[i];
            if(!batch.commitComplete)
            {
               if(batch.hasUpdateCollectionMessages(destination,collectionId))
               {
                  return true;
               }
            }
         }
         return false;
      }
      
      public function isCommittedBatchId(correlationId:String) : Boolean
      {
         var batch:MessageBatch = null;
         var allCommitted:Array = this.committed;
         for(var i:int = 0; i < allCommitted.length; i++)
         {
            batch = allCommitted[i];
            if(correlationId == batch.id)
            {
               return true;
            }
         }
         return false;
      }
      
      public function logCollectionUpdate(dataService:ConcreteDataService, dataList:DataList, changeType:int, position:int, identity:Object, item:Object) : void
      {
         var ucmsg:UpdateCollectionMessage = null;
         var strIdentity:String = null;
         var mci:MessageCacheItem = null;
         var ucl:Array = null;
         var collectionId:Object = dataList.collectionId;
         var parentItem:IManaged = IManaged(dataList.parentItem);
         var association:ManagedAssociation = dataList.association;
         if(association != null && !association.loadOnDemand)
         {
            mci = this.getLastUnsentCacheItem(dataService,parentItem.uid);
            if(mci != null && mci.message.isCreate())
            {
               mci.message.headers.DSoverridden = true;
            }
         }
         ucmsg = this._currentBatch.getOrCreateUpdateCollectionMessage(dataService,dataList,item);
         if(ucmsg.addItemIdentityChange(changeType,position,identity) && changeType == UpdateCollectionRange.DELETE_FROM_COLLECTION && identity is String && this._currentBatch.getCacheItem(strIdentity = identity as String) == null)
         {
            if(this._currentBatch.updateCollectionReferenceIndex == null)
            {
               this._currentBatch.updateCollectionReferenceIndex = new Object();
            }
            if((ucl = this._currentBatch.updateCollectionReferenceIndex[strIdentity]) == null)
            {
               ucl = this._currentBatch.updateCollectionReferenceIndex[strIdentity] = new Array();
            }
            ucl.push(ucmsg);
         }
         if(Log.isDebug())
         {
            dataService.log.debug((changeType == UpdateCollectionRange.INSERT_INTO_COLLECTION?"addTo":"removeFrom") + "Collection(" + ConcreteDataService.itemToString(collectionId) + ", pos=" + position + ", id=" + dataService.itemToIdString(item) + ")");
         }
         if(ucmsg.body == null)
         {
            this._currentBatch.removeMessage(ucmsg);
         }
         this.checkCommitRequired();
      }
      
      public function logCreate(dataService:ConcreteDataService, item:Object, op:uint) : DataMessage
      {
         var msg:DataMessage = null;
         var md:Metadata = null;
         var propName:String = null;
         var association:ManagedAssociation = null;
         var rawItem:Object = ConcreteDataService.unnormalize(item);
         var msgId:String = this._forwardRefs[rawItem] as String;
         if(msgId != null)
         {
            delete this._forwardRefsById[msgId];
         }
         delete this._forwardRefs[rawItem];
         var uid:String = IManaged(item).uid;
         var lastItem:MessageCacheItem = this._currentBatch.getLastCacheItem(dataService,uid,null);
         if(lastItem && lastItem.message.operation == DataMessage.DELETE_OPERATION)
         {
            this._currentBatch.removeMessage(lastItem.message);
            msg = lastItem.message;
         }
         else
         {
            msg = dataService.createMessage(item,op);
            msg.messageId = msgId == null?UIDUtil.createUID():msgId;
            msg.body = DataMessage.wrapItem(msg.body,dataService.destination);
            if(dataService.getItemMetadata(item).needsReferencedIds)
            {
               msg.headers.referencedIds = item.referencedIds;
               try
               {
                  ConcreteDataService.disablePaging();
                  md = dataService.getItemMetadata(item);
                  for(propName in md.associations)
                  {
                     association = ManagedAssociation(md.associations[propName]);
                     if(association.paged)
                     {
                        msg.headers.referencedIds[propName] = md.getReferencedIdsForAssoc(association,item[propName]);
                     }
                  }
               }
               finally
               {
                  ConcreteDataService.enablePaging();
               }
            }
            this.addMessage(dataService,msg,item);
            this._currentBatch.hasCreates = true;
         }
         this.checkCommitRequired();
         return msg;
      }
      
      public function logRemove(dataService:ConcreteDataService, item:Object) : DataMessage
      {
         var msg:DataMessage = null;
         var uid:String = IManaged(item).uid;
         var lastItem:MessageCacheItem = this._currentBatch.getLastCacheItem(dataService,uid,null);
         if(lastItem)
         {
            if(lastItem.message.operation == DataMessage.CREATE_OPERATION || lastItem.message.operation == DataMessage.CREATE_AND_SEQUENCE_OPERATION)
            {
               this._currentBatch.removeMessage(lastItem.message);
               this.checkCommitRequired();
               return null;
            }
         }
         msg = dataService.createMessage(item,DataMessage.DELETE_OPERATION);
         if(dataService.getItemMetadata(item).needsReferencedIds)
         {
            msg.headers.referencedIds = this.wrapReferencedIds(dataService,item.referencedIds,true);
         }
         msg.body = DataMessage.wrapItem(msg.body,dataService.destination);
         this.addMessage(dataService,msg,dataService.normalize(item));
         this.checkCommitRequired();
         return msg;
      }
      
      public function logUpdate(dataService:ConcreteDataService, item:Object, propName:Object, oldValue:Object, newValue:Object, stopAtItem:DataMessage, leafChange:Boolean, assoc:ManagedAssociation) : void
      {
         var uid:String = null;
         var msg:DataMessage = null;
         var propList:Array = null;
         var property:String = null;
         var changes:Array = null;
         var tobj:Object = null;
         var p:int = 0;
         var ix:Number = NaN;
         var tlist:IList = null;
         var anyPendingItem:MessageCacheItem = null;
         var em:String = null;
         var oldItem:Object = null;
         var valuesEqual:Boolean = false;
         var i:int = 0;
         var prev:Object = null;
         var prevRefIds:Object = null;
         var lastMsg:DataMessage = null;
         var currentBatchItem:MessageCacheItem = null;
         var currentValue:Object = null;
         var itemM:IManaged = IManaged(item);
         uid = itemM.uid;
         var lastItem:MessageCacheItem = this._currentBatch.getLastCacheItem(dataService,uid,stopAtItem);
         propList = propName.toString().split(".");
         property = propList[0];
         if(assoc == null)
         {
            tobj = item;
            for(p = 0; p < propList.length; p++)
            {
               if(tobj == null)
               {
                  return;
               }
               if(dataService.isTransient(tobj,propList[p]))
               {
                  return;
               }
               try
               {
                  if(tobj is IList)
                  {
                     ix = Number(propList[p]);
                     tlist = IList(tobj);
                     if(ix < tlist.length)
                     {
                        tobj = tlist.getItemAt(ix);
                     }
                     else
                     {
                        break;
                     }
                  }
                  else
                  {
                     tobj = tobj[propList[p]];
                  }
               }
               catch(e:Error)
               {
                  if(Log.isError())
                  {
                     dataService.log.error("Error trying to get property: " + p + " to log PropertyChangeEvent on item: " + uid + " for property: " + propName + " exception: " + e);
                     dataService.log.error(e.getStackTrace());
                  }
                  return;
               }
            }
         }
         if(oldValue === newValue || Managed.compare(oldValue,newValue) == 0)
         {
            return;
         }
         var md:Metadata = dataService.getItemMetadata(item);
         var isUIDProperty:Boolean = md.isUIDProperty(property);
         if(isUIDProperty && (lastItem == null || !lastItem.message.isCreate()))
         {
            anyPendingItem = this.getLastCommittedAndSent(dataService,uid);
            if(anyPendingItem == null || !anyPendingItem.message.isCreate())
            {
               em = "Attempting to update a UID property \'" + property + "\' which is not supported.";
               if(Log.isError())
               {
                  dataService.log.error(em);
               }
               if(this.dataStore.throwErrorOnIDChange)
               {
                  throw new DataServiceError(em);
               }
            }
         }
         if(assoc != null)
         {
            item.referencedIds[property] = newValue;
         }
         dataService.addItemToOffline(uid,itemM,property);
         if(lastItem)
         {
            msg = lastItem.message;
            if(msg.operation == DataMessage.UPDATE_OPERATION)
            {
               oldItem = DataMessage.unwrapItem(msg.body[DataMessage.UPDATE_BODY_PREV]);
               if(leafChange)
               {
                  valuesEqual = ObjectUtil.compare(oldItem[property],item[property]) == 0;
               }
               else if(assoc != null)
               {
                  valuesEqual = ObjectUtil.compare(DataMessage.unwrapItem(msg.headers.prevReferencedIds)[property],newValue) == 0;
               }
               else
               {
                  valuesEqual = ObjectUtil.compare(oldItem[property],newValue) == 0;
               }
               if(valuesEqual)
               {
                  changes = msg.body[DataMessage.UPDATE_BODY_CHANGES];
                  for(i = 0; i < changes.length; i++)
                  {
                     if(changes[i] == property)
                     {
                        break;
                     }
                  }
                  if(i != changes.length)
                  {
                     changes.splice(i,1);
                  }
                  if(msg.isEmptyUpdate())
                  {
                     this._currentBatch.removeMessage(msg);
                     if(Log.isDebug())
                     {
                        dataService.log.debug("Property: " + property + " changed back to original value - unqueuing message");
                     }
                  }
                  else if(Log.isDebug())
                  {
                     dataService.log.debug("Property: " + property + " changed back to original value");
                  }
               }
               else
               {
                  changes = msg.body[DataMessage.UPDATE_BODY_CHANGES];
                  for(i = 0; i < changes.length; i++)
                  {
                     if(changes[i] == property)
                     {
                        break;
                     }
                  }
                  if(i == changes.length)
                  {
                     msg.body[DataMessage.UPDATE_BODY_CHANGES].push(property);
                  }
               }
               msg.body[DataMessage.UPDATE_BODY_NEW] = DataMessage.wrapItem(ConcreteDataService.unnormalize(item),dataService.destination);
               if(dataService.getItemMetadata(item).needsReferencedIds)
               {
                  msg.headers.newReferencedIds = this.wrapReferencedIds(dataService,item.referencedIds,false);
               }
            }
            else if(msg.operation == DataMessage.CREATE_OPERATION || msg.operation == DataMessage.CREATE_AND_SEQUENCE_OPERATION)
            {
               msg.body = DataMessage.wrapItem(item,dataService.destination);
               if(assoc != null)
               {
                  msg.headers.referencedIds = item.referencedIds;
               }
            }
         }
         else
         {
            msg = dataService.createMessage(item,DataMessage.UPDATE_OPERATION);
            msg.body = [];
            if((stopAtItem != null || this._committedUnsent.length > 0 || this.uncommittedBatches.length > 1) && (lastItem = this.getLastUnsentCacheItem(dataService,uid)) != null)
            {
               lastMsg = lastItem.message;
               currentBatchItem = this._currentBatch.getLastCacheItem(dataService,uid,null);
               if(currentBatchItem != null)
               {
                  msg.headers.DSprevMessageId = currentBatchItem.message.messageId;
                  currentBatchItem.message.headers.DSoverridden = true;
               }
               if(lastMsg.operation == DataMessage.UPDATE_OPERATION)
               {
                  prev = DataMessage.unwrapItem(lastMsg.body[DataMessage.UPDATE_BODY_NEW]);
                  prev = lastMsg.body[DataMessage.UPDATE_BODY_NEW] = DataMessage.wrapItem(dataService.copyItem(prev),dataService.destination);
                  if(dataService.getItemMetadata(prev).needsReferencedIds)
                  {
                     prevRefIds = DataMessage.unwrapItem(lastMsg.headers.newReferencedIds);
                     prevRefIds = ObjectUtil.copy(prevRefIds);
                     lastMsg.headers.newReferencedIds = this.wrapReferencedIds(dataService,prevRefIds,false);
                  }
               }
               else
               {
                  prev = DataMessage.unwrapItem(lastMsg.body);
                  lastMsg.body = DataMessage.wrapItem(dataService.copyItem(prev),dataService.destination);
                  prev = lastMsg.body;
                  if(dataService.getItemMetadata(prev).needsReferencedIds)
                  {
                     prevRefIds = lastMsg.headers.referencedIds;
                     prevRefIds = lastMsg.headers.referencedIds = ObjectUtil.copy(prevRefIds);
                  }
               }
            }
            else
            {
               prev = DataMessage.wrapItem(dataService.copyItem(item),dataService.destination);
               if(dataService.getItemMetadata(item).needsReferencedIds)
               {
                  prevRefIds = ObjectUtil.copy(item.referencedIds);
               }
            }
            msg.body[DataMessage.UPDATE_BODY_PREV] = prev;
            prev = DataMessage.unwrapItem(prev);
            if(leafChange)
            {
               currentValue = prev;
               for(i = 0; i < propList.length - 1; i++)
               {
                  currentValue = currentValue[propList[i]];
               }
               if(currentValue is IList)
               {
                  if(oldValue == null)
                  {
                     IList(currentValue).removeItemAt(parseInt(propList[i]));
                  }
                  else if(newValue == null)
                  {
                     IList(currentValue).addItemAt(oldValue,parseInt(propList[i]));
                  }
                  else
                  {
                     IList(currentValue).setItemAt(oldValue,parseInt(propList[i]));
                  }
               }
               else
               {
                  try
                  {
                     currentValue[propList[i]] = oldValue;
                  }
                  catch(e:Error)
                  {
                     if(Log.isDebug())
                     {
                        dataService.log.debug("Unable to restore old property value in hierarchical change event: " + propList[i] + " is not settable processing hierarchical property change event for: " + propName);
                        dataService.log.debug(e.getStackTrace());
                     }
                     return;
                  }
               }
            }
            else if(assoc == null)
            {
               try
               {
                  prev[property] = oldValue;
               }
               catch(e:Error)
               {
                  if(Log.isDebug())
                  {
                     dataService.log.debug("Unable to restore old property value in property change event: " + property);
                     dataService.log.debug(e.getStackTrace());
                  }
                  return;
               }
            }
            msg.body[DataMessage.UPDATE_BODY_CHANGES] = [];
            msg.body[DataMessage.UPDATE_BODY_CHANGES].push(property);
            msg.body[DataMessage.UPDATE_BODY_NEW] = DataMessage.wrapItem(ConcreteDataService.unnormalize(item),dataService.destination);
            if(dataService.getItemMetadata(item).needsReferencedIds)
            {
               msg.headers.prevReferencedIds = this.wrapReferencedIds(dataService,prevRefIds,false);
               if(assoc != null)
               {
                  prevRefIds[property] = oldValue;
               }
               msg.headers.newReferencedIds = this.wrapReferencedIds(dataService,item.referencedIds,false);
            }
            this.addMessage(dataService,msg,item);
         }
         this.checkCommitRequired();
      }
      
      function wrapReferencedIds(dataService:ConcreteDataService, refIds:Object, isDelete:Boolean) : Object
      {
         var sd:SerializationDescriptor = dataService.metadata.getReferencedIdsSerializationDescriptor(isDelete);
         if(sd != null)
         {
            return new SerializationProxy(refIds,sd);
         }
         return refIds;
      }
      
      protected function getLastUnsentCacheItem(dataService:ConcreteDataService, uid:String) : MessageCacheItem
      {
         var lastMCI:MessageCacheItem = null;
         var batch:MessageBatch = null;
         var allUnsent:Array = this.unsent;
         for(var i:int = allUnsent.length - 1; i >= 0; i--)
         {
            batch = MessageBatch(allUnsent[i]);
            lastMCI = batch.getLastCacheItem(dataService,uid,null);
            if(lastMCI != null)
            {
               return lastMCI;
            }
         }
         return null;
      }
      
      function getLastCacheItem(dataService:ConcreteDataService, uid:String) : MessageCacheItem
      {
         var lastMCI:MessageCacheItem = null;
         var batch:MessageBatch = null;
         var allPending:Array = this.pending;
         for(var i:int = allPending.length - 1; i >= 0; i--)
         {
            batch = MessageBatch(allPending[i]);
            lastMCI = batch.getLastCacheItem(dataService,uid,null);
            if(lastMCI != null)
            {
               return lastMCI;
            }
         }
         return null;
      }
      
      private function getLastCommittedAndSent(dataService:ConcreteDataService, uid:String) : MessageCacheItem
      {
         var lastMCI:MessageCacheItem = null;
         var batch:MessageBatch = null;
         for(var i:int = this._committedAndSent.length - 1; i >= 0; i--)
         {
            batch = MessageBatch(this._committedAndSent[i]);
            lastMCI = batch.getLastCacheItem(dataService,uid,null);
            if(lastMCI != null)
            {
               return lastMCI;
            }
         }
         return null;
      }
      
      public function readExternal(input:IDataInput) : void
      {
         var oid:* = null;
         var old:ArrayCollection = null;
         var i:int = 0;
         var conflictArray:Array = null;
         var c:int = 0;
         var version:uint = input.readUnsignedInt();
         if(version == 1)
         {
            this._currentBatch = input.readObject();
         }
         this._committedAndSent = input.readObject();
         this._committedUnsent = input.readObject();
         var oldBatch:Object = this._batchIndex;
         this._batchIndex = input.readObject();
         for(oid in oldBatch)
         {
            this._batchIndex[oid] = oldBatch[oid];
         }
         if(version > 1)
         {
            old = this.uncommittedBatches;
            this.uncommittedBatches = new ArrayCollection(input.readObject());
            if(this.uncommittedBatches.length > 0)
            {
               this._currentBatch = this.uncommittedBatches[this.uncommittedBatches.length - 1];
               for(i = 0; i < this.uncommittedBatches.length; i++)
               {
                  MessageBatch(this.uncommittedBatches[i]).batchSequence = currentBatchSequence++;
               }
            }
            else
            {
               this.uncommittedBatches = old;
            }
         }
         if(version > 2)
         {
            conflictArray = input.readObject();
            if(conflictArray != null && conflictArray.length > 0)
            {
               this.restoredConflicts = new Array();
               for(c = 0; c < conflictArray.length; c++)
               {
                  this.restoredConflicts.push(conflictArray[c]);
               }
            }
         }
         this.checkCommitRequired();
      }
      
      public function removeMessage(msg:DataMessage, batchId:String = null) : void
      {
         var bmc:MessageBatch = null;
         if(batchId)
         {
            bmc = this._batchIndex[batchId];
            if(bmc != null)
            {
               bmc.removeMessage(msg);
            }
         }
         else
         {
            this._currentBatch.removeMessage(msg);
         }
         this.checkCommitRequired();
      }
      
      public function removeBatch(batchId:String) : MessageBatch
      {
         var i:int = 0;
         var cache:MessageBatch = this._batchIndex[batchId];
         if(cache != null)
         {
            delete this._batchIndex[batchId];
            for(i = 0; i < this._committedAndSent.length; i++)
            {
               if(this._committedAndSent[i] == cache)
               {
                  this._committedAndSent.splice(i,1);
                  this.requiresSave = true;
                  return cache;
               }
            }
            for(i = 0; i < this._committedUnsent.length; i++)
            {
               if(this._committedUnsent[i] == cache)
               {
                  this._committedUnsent.splice(i,1);
                  this.requiresSave = true;
                  return cache;
               }
            }
            for(i = 0; i < this.uncommittedBatches.length; i++)
            {
               if(this.uncommittedBatches[i] == cache)
               {
                  this.uncommittedBatches.removeItemAt(i);
                  if(this.currentBatch == cache && this.uncommittedBatches.length == 0)
                  {
                     this.createBatch();
                  }
                  else
                  {
                     this._currentBatch = MessageBatch(this.uncommittedBatches.getItemAt(this.uncommittedBatches.length - 1));
                  }
                  this.checkCommitRequired();
                  return cache;
               }
            }
         }
         return cache;
      }
      
      function addBatch(batch:MessageBatch, updateSequence:Boolean) : void
      {
         this._batchIndex[batch.id] = batch;
         if(updateSequence)
         {
            batch.batchSequence = currentBatchSequence++;
         }
      }
      
      public function replaceMessage(oldMessageId:String, newMsg:DataMessage) : void
      {
         var batch:MessageBatch = null;
         for(var i:int = 0; i < this.uncommittedBatches.length; i++)
         {
            batch = MessageBatch(this.uncommittedBatches.getItemAt(i));
            batch.replace(oldMessageId,newMsg);
         }
      }
      
      public function restoreBatch(batch:MessageBatch) : void
      {
         var oldCurrent:MessageBatch = null;
         this.addBatch(batch,false);
         for(var i:int = 0; i < this.uncommittedBatches.length; i++)
         {
            if(MessageBatch(this.uncommittedBatches.getItemAt(i)).batchSequence > batch.batchSequence)
            {
               break;
            }
         }
         this.uncommittedBatches.addItemAt(batch,i);
         if(i == this.uncommittedBatches.length - 1)
         {
            oldCurrent = this._currentBatch;
            this._currentBatch = batch;
            this.dataStore.sendCurrentBatchChange(oldCurrent,this._currentBatch);
         }
         this.checkCommitRequired();
      }
      
      public function restoreMessageCacheItems(items:Array) : void
      {
         this._currentBatch.restoreMessageCacheItems(items);
         this.checkCommitRequired();
      }
      
      public function restoreCommittedUnsentBatches() : void
      {
         if(!this.dataStore.restoreCommittedUnsentBatchesOnFault)
         {
            return;
         }
         for(var i:int = 0; i < this._committedUnsent.length; i++)
         {
            this.restoreBatch(this._committedUnsent[i]);
         }
         this._committedUnsent = [];
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         output.writeUnsignedInt(DataMessageCache.VERSION);
         output.writeObject(this._committedAndSent);
         output.writeObject(this._committedUnsent);
         output.writeObject(this._batchIndex);
         output.writeObject(this.uncommittedBatches.source);
         if(this.dataStore == null)
         {
            if(this.restoredConflicts != null)
            {
               output.writeObject(this.restoredConflicts);
            }
            else
            {
               output.writeObject([]);
            }
         }
         else
         {
            output.writeObject(this.dataStore.conflicts.source);
         }
      }
      
      private function checkCommitRequired() : void
      {
         this.requiresSave = true;
         var commitNeeded:Boolean = this._currentBatch.length > 0 || this._currentBatch.updateCollectionMessages != null && this._currentBatch.updateCollectionMessages.length > 0 || this.uncommittedBatches.length > 1;
         if(this._commitRequired != commitNeeded)
         {
            this._commitRequired = commitNeeded;
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"commitRequired",!this._commitRequired,this._commitRequired));
         }
      }
      
      function get committedUnsent() : Array
      {
         return this._committedUnsent;
      }
      
      function replaceMessageIdsForNewItems() : void
      {
         var batch:MessageBatch = null;
         var cacheItems:Array = null;
         var j:int = 0;
         var mci:MessageCacheItem = null;
         var msg:DataMessage = null;
         var cds:ConcreteDataService = null;
         var md:Metadata = null;
         var allUnsent:Array = this.unsent;
         for(var i:int = 0; i < allUnsent.length; i++)
         {
            batch = allUnsent[i];
            cacheItems = batch.getCacheItems();
            for(j = 0; j < cacheItems.length; j++)
            {
               mci = cacheItems[j];
               msg = mci.message;
               cds = mci.dataService;
               md = cds.getItemMetadata(mci.item);
               if(md.needsReferencedIds)
               {
                  if(msg.operation == DataMessage.UPDATE_OPERATION)
                  {
                     md.replaceMessageIdsWithIdentities(this,DataMessage.unwrapItem(msg.headers.prevReferencedIds));
                     md.replaceMessageIdsWithIdentities(this,DataMessage.unwrapItem(msg.headers.newReferencedIds));
                  }
                  else if(msg.operation == DataMessage.DELETE_OPERATION || msg.isCreate())
                  {
                     md.replaceMessageIdsWithIdentities(this,DataMessage.unwrapItem(msg.headers.referencedIds));
                  }
               }
            }
         }
      }
      
      function updateUIDItemIndex(msg:DataMessage) : void
      {
         var batch:MessageBatch = null;
         var cacheItem:MessageCacheItem = null;
         var allPending:Array = null;
         var i:int = 0;
         if((cacheItem = this._currentBatch.getCacheItem(msg.messageId)) != null)
         {
            batch = this._currentBatch;
         }
         else
         {
            allPending = this.pending;
            for(i = 0; i < allPending.length; i++)
            {
               batch = MessageBatch(allPending[i]);
               if((cacheItem = batch.getCacheItem(msg.messageId)) != null)
               {
                  break;
               }
            }
         }
         if(cacheItem != null)
         {
            batch.addToUIDItemIndex(cacheItem);
         }
      }
      
      override public function toString() : String
      {
         var s:String = null;
         if(this._committedAndSent.length > 0)
         {
            s = "committed and sent batches: " + this.batchListToString(this._committedAndSent) + "\n";
         }
         else
         {
            s = "";
         }
         if(this._committedUnsent.length > 0)
         {
            s = s + ("committed unsent batches: " + this.batchListToString(this._committedUnsent) + "\n");
         }
         if(this.uncommittedBatches.length > 0)
         {
            s = s + ("uncommitted batches: " + this.batchListToString(this.uncommittedBatches.source) + "\n");
         }
         if(this.dataStore != null && this.dataStore.conflicts.length > 0)
         {
            s = s + ("conflicts : " + this.dataStore.conflicts.toString() + "\n");
         }
         return s;
      }
      
      private function batchListToString(arr:Array) : String
      {
         var s:String = "[";
         for(var i:int = 0; i < arr.length; i++)
         {
            if(i != 0)
            {
               s = s + ",\n ";
            }
            s = s + MessageBatch(arr[i]).toString();
         }
         s = s + "]";
         return s;
      }
   }
}
