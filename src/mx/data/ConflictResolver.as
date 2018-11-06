package mx.data
{
   import mx.data.messages.DataMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.events.CollectionEvent;
   import mx.events.CollectionEventKind;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   
   [ExcludeClass]
   public class ConflictResolver
   {
       
      
      private var _log:ILogger;
      
      private var _dataStore:DataStore;
      
      public function ConflictResolver(dataStore:DataStore)
      {
         super();
         this._dataStore = dataStore;
         this._log = Log.getLogger("mx.data.ConflictResolver");
      }
      
      public function acceptClient(conflict:Conflict) : void
      {
         var msg:DataMessage = conflict.cause;
         var msgId:String = msg.messageId;
         var dataService:ConcreteDataService = conflict.concreteDataService;
         dataService.disableLogging();
         try
         {
            if(conflict.clientMessage != null)
            {
               if(Log.isDebug())
               {
                  this._log.debug("ConflictResolver: Accepting client for pull conflict DataMessage {0}",msgId);
               }
               this.acceptClientForPullConflict(conflict);
            }
            else
            {
               if(Log.isDebug())
               {
                  this._log.debug("ConflictResolver: Accepting client for push conflict DataMessage {0}",msgId);
               }
               this.acceptClientForPushConflict(conflict);
            }
         }
         finally
         {
            dataService.enableLogging();
         }
      }
      
      public function acceptServer(conflict:Conflict) : void
      {
         var p:uint = 0;
         var pendingMessage:DataMessage = null;
         var ucMsg:UpdateCollectionMessage = null;
         var rangeInfos:Array = null;
         var i:int = 0;
         var propertyNames:Array = null;
         var pendingPrevRefIds:Object = null;
         var up:uint = 0;
         var updateProp:String = null;
         var assoc:ManagedAssociation = null;
         var changes:Array = null;
         var c:int = 0;
         var cause:DataMessage = conflict.cause;
         var dataService:ConcreteDataService = conflict.concreteDataService;
         var clientMsg:DataMessage = conflict.clientMessage;
         var uid:String = dataService.metadata.getUID(cause.identity);
         var messages:Array = this._dataStore.messageCache.getUnsentMessages(dataService,uid);
         var ucMsgs:Array = this._dataStore.messageCache.getUnsentUpdateCollections(dataService.destination,null,false,cause.identity);
         if(Log.isDebug())
         {
            this._log.debug("ConflictResolver: Accepting server for DataMessage {0} ",cause.messageId);
         }
         dataService.disableLogging();
         try
         {
            for(p = 0; p < messages.length; p++)
            {
               pendingMessage = messages[p];
               if(pendingMessage.operation == DataMessage.DELETE_OPERATION)
               {
                  dataService.addItem(DataMessage.unwrapItem(pendingMessage.body),0,false,true,DataMessage.unwrapItem(pendingMessage.headers.referencedIds),null,true);
                  dataService.updateItemWithId(pendingMessage.identity,conflict.serverObject,null,conflict.serverObjectReferencedIds,true);
                  this.restoreItem(uid,cause,ucMsgs,dataService);
               }
               if(cause.operation == DataMessage.DELETE_OPERATION || pendingMessage.operation != DataMessage.UPDATE_OPERATION || conflict.serverObject == null)
               {
                  if(Log.isDebug())
                  {
                     this._log.debug("Cancelling client DataMessage {0} with operation {1} ",pendingMessage.messageId,DataMessage.getOperationAsString(pendingMessage.operation));
                  }
                  this._dataStore.messageCache.removeMessage(pendingMessage);
                  for(i = 0; i < ucMsgs.length; i++)
                  {
                     ucMsg = UpdateCollectionMessage(ucMsgs[i]);
                     if(ucMsg.body != null)
                     {
                        rangeInfos = ucMsg.getRangeInfoForIdentity(cause.identity);
                        ucMsg.removeRanges(rangeInfos);
                        if(ucMsg.body == null)
                        {
                           this._dataStore.messageCache.removeMessage(ucMsg);
                        }
                     }
                  }
                  if(pendingMessage.messageId == cause.messageId)
                  {
                     cause = null;
                  }
               }
               else if(conflict.propertyNames)
               {
                  propertyNames = conflict.propertyNames;
                  pendingPrevRefIds = DataMessage.unwrapItem(pendingMessage.headers.prevReferencedIds);
                  for(up = 0; up < propertyNames.length; up++)
                  {
                     updateProp = propertyNames[up];
                     assoc = dataService.getItemMetadata(conflict.serverObject).associations[updateProp];
                     if(assoc != null)
                     {
                        pendingPrevRefIds[updateProp] = conflict.serverObjectReferencedIds[updateProp];
                     }
                     else
                     {
                        DataMessage.unwrapItem(pendingMessage.body[DataMessage.UPDATE_BODY_PREV])[updateProp] = conflict.serverObject[updateProp];
                     }
                     changes = pendingMessage.body[DataMessage.UPDATE_BODY_CHANGES];
                     for(c = 0; c < changes.length; c++)
                     {
                        if(changes[c] == updateProp)
                        {
                           changes.splice(c,1);
                           c = changes.length;
                        }
                     }
                  }
                  if(pendingMessage.isEmptyUpdate())
                  {
                     this._dataStore.messageCache.removeMessage(pendingMessage);
                  }
               }
            }
            if(clientMsg)
            {
               if(clientMsg.operation == DataMessage.DELETE_OPERATION)
               {
                  clientMsg = null;
               }
               else if(clientMsg.operation == DataMessage.UPDATE_OPERATION && conflict.serverObject != null)
               {
                  dataService.updateItemWithId(clientMsg.identity,conflict.serverObject,null,conflict.serverObjectReferencedIds,true);
                  clientMsg = null;
               }
               else
               {
                  clientMsg.operation = DataMessage.DELETE_OPERATION;
               }
               cause = clientMsg;
            }
            if(cause != null && conflict.removeFromFillConflictDetails == null)
            {
               if(cause.operation == DataMessage.CREATE_OPERATION || cause.operation == DataMessage.CREATE_AND_SEQUENCE_OPERATION)
               {
                  if(Log.isDebug())
                  {
                     this._log.debug("NOT applying server create DataMessage {0} ",cause.messageId);
                  }
               }
               else if(cause.operation == DataMessage.UPDATE_OPERATION)
               {
                  if(Log.isDebug())
                  {
                     this._log.debug("Applying server update DataMessage {0} ",cause.messageId);
                  }
                  dataService.updateItemWithId(cause.identity,cause.body[DataMessage.UPDATE_BODY_NEW],cause.body[DataMessage.UPDATE_BODY_CHANGES],DataMessage.unwrapItem(cause.headers.newReferencedIds));
               }
               else if(cause.operation == DataMessage.DELETE_OPERATION)
               {
                  if(Log.isDebug())
                  {
                     this._log.debug("Applying server delete DataMessage {0} ",cause.messageId);
                  }
                  dataService.removeItem(dataService.metadata.getUID(cause.identity));
               }
               else
               {
                  this._log.error("Unknown DataMessage operation type {0}",cause.operation);
               }
            }
            else if(conflict.removeFromFillConflictDetails != null)
            {
               conflict.removeFromFillConflictDetails.applyServerCallBack();
               dataService.releaseItemIfNoDataListReferences(dataService.getItem(uid));
            }
         }
         finally
         {
            dataService.enableLogging();
         }
      }
      
      private function acceptClientForPullConflict(conflict:Conflict) : void
      {
         var cause:DataMessage = conflict.cause;
         this.updateMessageForAcceptClient(conflict.clientMessage,conflict,cause.messageId,conflict.serverObject == null,conflict.clientMessage.operation == DataMessage.DELETE_OPERATION);
      }
      
      private function acceptClientForPushConflict(conflict:Conflict) : void
      {
         var pendingMessage:DataMessage = null;
         var cause:DataMessage = conflict.cause;
         var dataService:ConcreteDataService = conflict.concreteDataService;
         var uid:String = dataService.metadata.getUID(cause.identity);
         var messages:Array = this._dataStore.messageCache.getUnsentMessages(dataService,uid);
         for(var p:uint = 0; p < messages.length; p++)
         {
            pendingMessage = messages[p];
            this.updateMessageForAcceptClient(pendingMessage,conflict,pendingMessage.messageId,cause.operation == DataMessage.DELETE_OPERATION,pendingMessage.operation == DataMessage.DELETE_OPERATION);
         }
      }
      
      private function restoreItem(uid:String, msg:DataMessage, ucMsgs:Array, dataService:ConcreteDataService) : void
      {
         var ucMsg:UpdateCollectionMessage = null;
         var rangeInfos:Array = null;
         var rangeInfo:Object = null;
         var dataList:DataList = null;
         var collectionEvent:CollectionEvent = null;
         var j:int = 0;
         for(var i:int = 0; i < ucMsgs.length; i++)
         {
            ucMsg = UpdateCollectionMessage(ucMsgs[i]);
            dataList = dataService.getDataListWithCollectionId(ucMsg.collectionId);
            if(dataList != null)
            {
               rangeInfos = ucMsg.getRangeInfoForIdentity(msg.identity);
               for(j = 0; j < rangeInfos.length; j++)
               {
                  rangeInfo = rangeInfos[j];
                  dataList.addReferenceAt(uid,msg.identity,rangeInfo.position);
                  collectionEvent = new CollectionEvent(CollectionEvent.COLLECTION_CHANGE);
                  collectionEvent.kind = CollectionEventKind.ADD;
                  collectionEvent.location = rangeInfo.position;
                  collectionEvent.items = [dataService.getItem(uid)];
                  dataList.dispatchEvent(collectionEvent);
               }
               ucMsg.removeRanges(rangeInfos);
               if(ucMsg.body == null)
               {
                  this._dataStore.messageCache.removeMessage(ucMsg);
               }
            }
         }
      }
      
      private function updateMessageForAcceptClient(pendingMessage:DataMessage, conflict:Conflict, replaceMsgId:String, serverDeleted:Boolean, clientDeleted:Boolean) : void
      {
         var createItem:Object = null;
         var createMsg:DataMessage = null;
         var properties:Array = null;
         var pendingPrev:Object = null;
         var pendingPrevRefIds:Object = null;
         var pp:String = null;
         var i:uint = 0;
         var diff:int = 0;
         var t:* = undefined;
         var assoc:ManagedAssociation = null;
         var changes:Object = null;
         var msg:DataMessage = conflict.cause;
         var dataService:ConcreteDataService = conflict.concreteDataService;
         if(serverDeleted)
         {
            createItem = dataService.getItem(dataService.metadata.getUID(msg.identity));
            if(createItem == null)
            {
               createItem = this._dataStore.messageCache.getItem(replaceMsgId,null);
               if(createItem != null)
               {
                  dataService.addItem(createItem);
               }
            }
            createMsg = dataService.createMessage(createItem,DataMessage.CREATE_OPERATION);
            createMsg.body = DataMessage.wrapItem(createMsg.body,dataService.destination);
            if(dataService.getItemMetadata(createItem).needsReferencedIds)
            {
               createMsg.headers.referencedIds = createItem.referencedIds;
            }
            this._dataStore.messageCache.replaceMessage(replaceMsgId,createMsg);
         }
         else if(clientDeleted)
         {
            ConcreteDataService.copyValues(pendingMessage.unwrapBody(),conflict.serverObject,null,dataService.metadata.lazyAssociations,true);
            if(dataService.getItemMetadata(conflict.serverObject).needsReferencedIds)
            {
               pendingMessage.headers.referencedIds = dataService.dataStore.messageCache.wrapReferencedIds(dataService,conflict.serverObjectReferencedIds,true);
            }
         }
         else
         {
            properties = ObjectUtil.getClassInfo(conflict.serverObject,null,ConcreteDataService.CLASS_INFO_OPTIONS).properties;
            pendingPrev = DataMessage.unwrapItem(pendingMessage.body[DataMessage.UPDATE_BODY_PREV]);
            pendingPrevRefIds = DataMessage.unwrapItem(pendingMessage.headers.prevReferencedIds);
            for(i = 0; i < properties.length; i++)
            {
               pp = properties[i];
               if(!(dataService.metadata.isUIDProperty(pp) || pp == "uid" || pp == "constructor"))
               {
                  t = dataService.getItemMetadata(conflict.serverObject).associations[pp];
                  assoc = t;
                  if(assoc != null)
                  {
                     diff = ObjectUtil.compare(conflict.serverObjectReferencedIds[pp],pendingPrevRefIds[pp]);
                  }
                  else
                  {
                     diff = ObjectUtil.compare(conflict.serverObject[pp],pendingPrev[pp]);
                  }
                  if(diff != 0)
                  {
                     changes = pendingMessage.body[DataMessage.UPDATE_BODY_CHANGES];
                     if(ArrayUtil.getItemIndex(pp,changes as Array) == -1)
                     {
                        changes.push(pp);
                     }
                     if(assoc != null)
                     {
                        pendingPrevRefIds[pp] = conflict.serverObjectReferencedIds[pp];
                     }
                     else
                     {
                        try
                        {
                           pendingPrev[pp] = conflict.serverObject[pp];
                        }
                        catch(re:ReferenceError)
                        {
                        }
                     }
                  }
               }
            }
         }
      }
   }
}
