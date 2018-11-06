package mx.data
{
   import flash.events.Event;
   import mx.data.errors.DataServiceError;
   import mx.data.events.DataServiceFaultEvent;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.logging.Log;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AcknowledgeMessage;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.IResponder;
   import mx.rpc.events.AbstractEvent;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   
   [ExcludeClass]
   [ResourceBundle("data")]
   public class CommitResponder implements IResponder
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      protected var _store:DataStore;
      
      var token:AsyncToken;
      
      public function CommitResponder(store:DataStore, token:AsyncToken)
      {
         super();
         this._store = store;
         this.token = token;
      }
      
      public function fault(info:Object) : void
      {
         var cacheItems:Array = null;
         var messageCache:DataMessageCache = null;
         var tokenChain:Object = null;
         var localToken:AsyncToken = null;
         var faultEvents:Array = null;
         var fltEvent:FaultEvent = null;
         var corrId:* = null;
         var fault:Fault = null;
         var rpcFaultEvent:FaultEvent = null;
         var handled:Boolean = false;
         var cds:ConcreteDataService = null;
         var processed:Object = null;
         var mci:MessageCacheItem = null;
         var i:int = 0;
         var dmsg:DataMessage = null;
         var uid:String = null;
         var destination:String = null;
         var faultEvent:MessageFaultEvent = MessageFaultEvent(info);
         var errMsg:ErrorMessage = ErrorMessage(faultEvent.message);
         var originalMsg:AsyncMessage = AsyncMessage(this.token.message);
         errMsg.destination = this.token.message.destination;
         var batchId:String = originalMsg.correlationId.length > 0?originalMsg.correlationId:originalMsg.messageId;
         var batch:MessageBatch = this._store.messageCache.removeBatch(batchId);
         if(batch != null)
         {
            cacheItems = batch.getCacheItems();
            messageCache = this._store.messageCache;
            messageCache.restoreCommittedUnsentBatches();
            messageCache.restoreBatch(batch);
            this._store.attemptSaveAterCommit();
            if(!this._store.mergeRequired)
            {
               this.processPendingItemRequests(batch.updateCollectionMessages);
            }
            if(errMsg is DataErrorMessage)
            {
               throw new DataServiceError(resourceManager.getString("data","receivedDataErrorMessage"));
            }
            tokenChain = this.token[DataStore.TOKEN_CHAIN];
            faultEvents = [];
            if(tokenChain != null)
            {
               for(corrId in tokenChain)
               {
                  localToken = AsyncToken(tokenChain[corrId]);
                  fault = new Fault(errMsg.faultCode,errMsg.faultString,errMsg.faultDetail);
                  rpcFaultEvent = FaultEvent.createEvent(fault,localToken,errMsg);
                  fault.rootCause = errMsg.rootCause;
                  localToken.applyFault(rpcFaultEvent);
                  if(!faultEvent.isDefaultPrevented())
                  {
                     faultEvents.push(rpcFaultEvent);
                  }
               }
            }
            fltEvent = FaultEvent.createEventFromMessageFault(faultEvent,this.token);
            this.token.applyFault(fltEvent);
            if(!fltEvent.isDefaultPrevented())
            {
               handled = false;
               if(this._store.hasEventListener(FaultEvent.FAULT))
               {
                  handled = true;
                  this._store.dispatchEvent(fltEvent);
               }
               processed = {};
               for(i = 0; i < cacheItems.length; i++)
               {
                  mci = MessageCacheItem(cacheItems[i]);
                  cds = processed[mci.dataService.destination];
                  if(cds == null)
                  {
                     cds = mci.dataService;
                     processed[cds.destination] = cds;
                     if(this.token.responders == null || cds.hasEventListener(FaultEvent.FAULT))
                     {
                        cds.dispatchFaultEvent(faultEvent,this.token,mci.message.identity,false,handled);
                     }
                  }
               }
               for(i = 0; i < faultEvents.length; i++)
               {
                  rpcFaultEvent = FaultEvent(faultEvents[i]);
                  destination = rpcFaultEvent.token.message.destination;
                  if(destination != null && destination != "")
                  {
                     cds = processed[destination];
                     if(cds == null)
                     {
                        cds = this._store.getDataService(destination);
                        if(cds.hasEventListener(FaultEvent.FAULT))
                        {
                           dmsg = DataMessage(rpcFaultEvent.token.message);
                           uid = cds.metadata.getUID(dmsg.identity);
                           cds.dispatchEvent(DataServiceFaultEvent.createEvent(rpcFaultEvent.fault,rpcFaultEvent.token,ErrorMessage(rpcFaultEvent.message),cds.getItem(uid),dmsg.identity));
                        }
                     }
                  }
               }
            }
         }
      }
      
      public function result(data:Object) : void
      {
         this.processResult(data);
      }
      
      public function processResult(data:Object, lastOnly:Boolean = false) : void
      {
         var ackMessage:AcknowledgeMessage = null;
         var m:AsyncMessage = null;
         var i:int = 0;
         var batch:MessageBatch = null;
         var sentCacheItems:Array = null;
         var sentOrderedUCs:Array = null;
         var sentUCs:Array = null;
         var ucFaults:Array = null;
         var uc:UpdateCollectionMessage = null;
         var batchRestored:Boolean = false;
         var anyFailure:Boolean = false;
         var errMsg:ErrorMessage = null;
         var newBatch:MessageBatch = null;
         var derrMsg:DataErrorMessage = null;
         var dataService:ConcreteDataService = null;
         var cacheItem:MessageCacheItem = null;
         var event:MessageEvent = MessageEvent(data);
         ackMessage = AcknowledgeMessage(event.message);
         var allMessages:Array = ackMessage.body as Array;
         var allMessagesIndex:Object = {};
         var resultMessages:Array = [];
         var faultMessages:Array = [];
         var failed:Boolean = false;
         try
         {
            batch = this._store.messageCache.getBatch(ackMessage.correlationId);
            this._store.messageCache.currentCommitResult = batch;
            if(batch == null)
            {
               throw new DataServiceError(resourceManager.getString("data","noBatchWithId",[ackMessage.correlationId]));
            }
            batch.commitComplete = true;
            for(i = 0; i < allMessages.length; i++)
            {
               m = AsyncMessage(allMessages[i]);
               if(allMessagesIndex[m.messageId] == null)
               {
                  allMessagesIndex[m.messageId] = m;
               }
               if(this._store.useTransactions && !(m is DataMessage) && !(m is SequencedMessage))
               {
                  failed = true;
                  break;
               }
               if(batch.getCacheItem(m.messageId) == null && !(m is UpdateCollectionMessage) && !(m is ErrorMessage))
               {
                  resultMessages.push(m);
               }
            }
            sentCacheItems = batch.getCacheItems();
            sentOrderedUCs = null;
            for(i = 0; i < sentCacheItems.length; i++)
            {
               m = allMessagesIndex[sentCacheItems[i].message.messageId];
               if(m is UpdateCollectionMessage)
               {
                  if(sentOrderedUCs == null)
                  {
                     sentOrderedUCs = [];
                  }
                  sentOrderedUCs.push(m);
               }
               if(failed || m == null || m is DataErrorMessage || m is ErrorMessage)
               {
                  faultMessages.push(sentCacheItems[i]);
               }
               else
               {
                  resultMessages.push(m);
               }
            }
            sentUCs = batch.updateCollectionMessages;
            ucFaults = [];
            batchRestored = false;
            if(sentUCs != null)
            {
               for(i = 0; i < sentUCs.length; i++)
               {
                  uc = UpdateCollectionMessage(sentUCs[i]);
                  m = allMessagesIndex[uc.messageId];
                  if(failed || m == null || m is DataErrorMessage || m is ErrorMessage)
                  {
                     ucFaults.push(uc);
                  }
               }
            }
            anyFailure = ucFaults.length > 0 || faultMessages.length > 0;
            if(resultMessages.length == 0)
            {
               if(anyFailure)
               {
                  batchRestored = true;
                  this._store.messageCache.removeBatch(batch.id);
                  this._store.messageCache.restoreCommittedUnsentBatches();
                  this._store.messageCache.restoreBatch(batch);
                  if(!this._store.currentBatch.commitRequired)
                  {
                     this._store.currentBatch.revertChanges();
                  }
               }
            }
            else if(anyFailure)
            {
               if(ucFaults.length > 0)
               {
                  this.patchUpdateCollections(resultMessages,ucFaults);
               }
               this._store.messageCache.restoreCommittedUnsentBatches();
               if(!this._store.currentBatch.commitRequired && this._store.messageCache.uncommittedBatches.length == 1)
               {
                  this._store.messageCache.currentBatch.batchSequence = batch.batchSequence;
                  this._store.messageCache.restoreMessageCacheItems(faultMessages);
                  this._store.messageCache.currentBatch.restoreUpdateCollections(ucFaults);
               }
               else
               {
                  newBatch = new MessageBatch();
                  newBatch.batchSequence = batch.batchSequence;
                  newBatch.dataStore = this._store;
                  newBatch.restoreMessageCacheItems(faultMessages);
                  newBatch.restoreUpdateCollections(ucFaults);
                  this._store.messageCache.restoreBatch(newBatch);
               }
            }
            faultMessages = [];
            for(i = 0; i < allMessages.length; i++)
            {
               m = AsyncMessage(allMessages[i]);
               if(m is DataErrorMessage)
               {
                  derrMsg = DataErrorMessage(m);
                  dataService = this._store.getDataService(derrMsg.cause.destination);
                  cacheItem = batch.getCacheItem(derrMsg.cause.messageId);
                  if(dataService != null && cacheItem != null)
                  {
                     this._store.processConflict(dataService,derrMsg,cacheItem.message);
                  }
                  else if(Log.isError())
                  {
                     this._store.log.error("DataStore unable to find message for pull conflict");
                  }
               }
               else if(m is ErrorMessage)
               {
                  errMsg = ErrorMessage(m);
                  if(batch.getCacheItem(errMsg.correlationId) != null)
                  {
                     faultMessages.push(errMsg);
                  }
                  else if(Log.isError())
                  {
                     this._store.log.error("DataStore unable to find client message for fault:\n{0}",errMsg.toString());
                  }
               }
               else if(m is UpdateCollectionMessage)
               {
                  resultMessages.push(m);
               }
               else if(!(m is DataMessage) && !(m is SequencedMessage) && Log.isError())
               {
                  this._store.log.error("DataStore cannot handle replied message type:\n{0}",m.toString());
               }
            }
            if(resultMessages.length > 0)
            {
               this.internalProcessResults(!!lastOnly?[resultMessages[resultMessages.length - 1]]:resultMessages,batch);
               this.dispatchResultEvents(resultMessages,event,faultMessages.length == 0);
            }
            if(faultMessages.length > 0)
            {
               this.dispatchFaultEvents(faultMessages);
            }
            this.commitCleanup(ackMessage,batch,batchRestored);
         }
         catch(e:Error)
         {
            commitCleanup(ackMessage,batch,batchRestored);
            throw e;
         }
         if(!this._store.mergeRequired)
         {
            this.processPendingItemRequests(sentUCs);
            if(sentOrderedUCs != null)
            {
               this.processPendingItemRequests(sentOrderedUCs);
            }
         }
      }
      
      private function patchUpdateCollections(resultMessages:Array, ucFaults:Array) : void
      {
         var dmsg:DataMessage = null;
         var isDelete:Boolean = false;
         var j:int = 0;
         var ucmsg:UpdateCollectionMessage = null;
         var rangeInfo:Array = null;
         for(var i:int = 0; i < resultMessages.length; i++)
         {
            dmsg = resultMessages[i] as DataMessage;
            isDelete = dmsg.operation == DataMessage.DELETE_OPERATION;
            if(dmsg.isCreate() || isDelete)
            {
               for(j = 0; j < ucFaults.length; j++)
               {
                  ucmsg = ucFaults[j] as UpdateCollectionMessage;
                  if(ucmsg.destination == dmsg.destination)
                  {
                     rangeInfo = ucmsg.getRangeInfoForIdentity(dmsg.identity);
                     ucmsg.removeRanges(rangeInfo,!isDelete,isDelete);
                  }
               }
            }
         }
      }
      
      private function internalProcessResults(resultMessages:Array, batch:MessageBatch) : void
      {
         this._store.enableDelayedReleases();
         try
         {
            this._store.commitResultHandler(resultMessages,this.token,batch);
         }
         finally
         {
            this._store.disableDelayedReleases();
         }
      }
      
      public function processResults(resultMessages:Array, batchId:String) : void
      {
         var batch:MessageBatch = this._store.messageCache.getBatch(batchId);
         batch.commitComplete = true;
         this.internalProcessResults(resultMessages,batch);
      }
      
      private function commitCleanup(ackMessage:AcknowledgeMessage, batch:MessageBatch, batchRestored:Boolean) : void
      {
         if(!batchRestored)
         {
            this._store.messageCache.removeBatch(ackMessage.correlationId);
            batch.releaseBatch();
         }
         this._store.sendUnsentCommits();
         this._store.messageCache.currentCommitResult = null;
         this._store.attemptSaveAterCommit(this._store.autoSaveCache);
      }
      
      protected function createResultEvent(msg:IMessage, token:AsyncToken) : ResultEvent
      {
         return ResultEvent.createEvent(msg,token,msg);
      }
      
      private function dispatchFaultEvents(faultMessages:Array) : void
      {
         var faultEvent:FaultEvent = null;
         var fault:Fault = null;
         var localToken:AsyncToken = null;
         var rpcFaultEvent:FaultEvent = null;
         var errMsg:ErrorMessage = null;
         var tokenChain:Object = this.token[DataStore.TOKEN_CHAIN];
         var actEvents:Array = [];
         var nonActEvents:Array = [];
         for(var i:int = 0; i < faultMessages.length; i++)
         {
            errMsg = ErrorMessage(faultMessages[i]);
            if(tokenChain != null)
            {
               localToken = AsyncToken(tokenChain[errMsg.correlationId]);
               if(localToken != null)
               {
                  fault = new Fault(errMsg.faultCode,errMsg.faultString,errMsg.faultDetail);
                  fault.rootCause = errMsg.rootCause;
                  rpcFaultEvent = FaultEvent.createEvent(fault,localToken,errMsg);
                  localToken.applyFault(rpcFaultEvent);
                  if(!rpcFaultEvent.isDefaultPrevented())
                  {
                     actEvents.push(rpcFaultEvent);
                  }
               }
            }
            else
            {
               fault = new Fault(errMsg.faultCode,errMsg.faultString,errMsg.faultDetail);
               fault.rootCause = errMsg.rootCause;
               rpcFaultEvent = FaultEvent.createEvent(fault,localToken,errMsg);
               nonActEvents.push(rpcFaultEvent);
            }
         }
         var topLevelError:ErrorMessage = ErrorMessage(faultMessages[0]);
         topLevelError.body = faultMessages;
         var msgFault:MessageFaultEvent = MessageFaultEvent.createEvent(topLevelError);
         faultEvent = FaultEvent.createEventFromMessageFault(msgFault,this.token);
         this.token.applyFault(faultEvent);
         if(!faultEvent.isDefaultPrevented())
         {
            this.sendEvents(msgFault,actEvents,nonActEvents,faultEvent);
         }
      }
      
      private function dispatchResultEvents(resultMessages:Array, event:MessageEvent, sendBatchEvent:Boolean) : void
      {
         var resultEvent:ResultEvent = null;
         var localToken:AsyncToken = null;
         var result:Object = null;
         var dmsg:DataMessage = null;
         var msg:AsyncMessage = null;
         if(Log.isDebug())
         {
            this._store.log.debug("About to dispatch commit result events");
         }
         var tokenChain:Object = this.token[DataStore.TOKEN_CHAIN];
         var actEvents:Array = [];
         var nonActEvents:Array = [];
         for(var i:int = 0; i < resultMessages.length; i++)
         {
            msg = AsyncMessage(resultMessages[i]);
            result = msg;
            if(msg is SequencedMessage && SequencedMessage(msg).dataMessage != null)
            {
               msg = SequencedMessage(msg).dataMessage;
            }
            if(msg is DataMessage)
            {
               dmsg = DataMessage(msg);
               if(dmsg.operation == DataMessage.UPDATE_OPERATION)
               {
                  result = this.getManagedResult(dmsg,DataMessage.unwrapItem(dmsg.body[DataMessage.UPDATE_BODY_NEW]));
               }
               else if(dmsg.isCreate() || dmsg.operation == DataMessage.DELETE_OPERATION)
               {
                  result = this.getManagedResult(dmsg,dmsg.unwrapBody());
               }
            }
            if(!(msg is UpdateCollectionMessage))
            {
               if(tokenChain != null)
               {
                  localToken = AsyncToken(tokenChain[msg.messageId]);
                  if(localToken != null)
                  {
                     resultEvent = ResultEvent.createEvent(result,localToken,msg);
                     localToken.applyResult(resultEvent);
                     if(!resultEvent.isDefaultPrevented())
                     {
                        actEvents.push(resultEvent);
                     }
                  }
                  else
                  {
                     nonActEvents.push(ResultEvent.createEvent(result,null,msg));
                  }
               }
               else
               {
                  nonActEvents.push(ResultEvent.createEvent(result,null,msg));
               }
            }
         }
         if(sendBatchEvent)
         {
            resultEvent = this.createResultEvent(event.message,this.token);
            this.token.applyResult(resultEvent);
            if(!resultEvent.isDefaultPrevented())
            {
               this.sendEvents(resultEvent,actEvents,nonActEvents);
            }
         }
         if(Log.isDebug())
         {
            this._store.log.debug("Finished dispatch commit result");
         }
      }
      
      private function getManagedResult(dmsg:DataMessage, result:Object) : Object
      {
         var cds:ConcreteDataService = null;
         var newResult:Object = null;
         if(result != null)
         {
            cds = this._store.getDataService(dmsg.destination);
            newResult = cds.getItem(cds.metadata.getUID(result));
            if(newResult != null)
            {
               result = newResult;
            }
         }
         return result;
      }
      
      private function processPendingItemRequests(ucMsgs:Array) : void
      {
         var ucMsg:UpdateCollectionMessage = null;
         var cds:ConcreteDataService = null;
         var dl:DataList = null;
         var i:int = 0;
         if(ucMsgs != null)
         {
            for(i = 0; i < ucMsgs.length; i++)
            {
               ucMsg = UpdateCollectionMessage(ucMsgs[i]);
               cds = this._store.getDataService(ucMsg.destination);
               dl = cds.getDataListWithCollectionId(ucMsg.collectionId);
               if(dl != null)
               {
                  dl.processPendingRequests();
               }
            }
         }
      }
      
      private function sendEvents(event:Event, actEvents:Array, events:Array, faultEvent:FaultEvent = null) : void
      {
         var cds:ConcreteDataService = null;
         var currentEvent:AbstractEvent = null;
         var fault:Fault = null;
         var dmsg:DataMessage = null;
         var uid:String = null;
         var dispatched:Boolean = false;
         var cdsMap:Object = {};
         for(var i:int = 0; i < actEvents.length; i++)
         {
            currentEvent = AbstractEvent(actEvents[i]);
            cds = this._store.getDataService(currentEvent.token.message.destination);
            if(faultEvent != null)
            {
               fault = FaultEvent(currentEvent).fault;
               if(cds.hasEventListener(FaultEvent.FAULT))
               {
                  dmsg = DataMessage(currentEvent.token.message);
                  uid = cds.metadata.getUID(dmsg.identity);
                  cds.dispatchEvent(DataServiceFaultEvent.createEvent(fault,currentEvent.token,ErrorMessage(currentEvent.message),cds.getItem(uid),dmsg.identity));
                  cdsMap[cds.destination] = cds;
               }
            }
            else if(cds.hasEventListener(event.type))
            {
               cds.dispatchEvent(currentEvent);
               cdsMap[cds.destination] = cds;
            }
         }
         for(i = 0; i < events.length; i++)
         {
            currentEvent = AbstractEvent(events[i]);
            cds = this._store.getDataService(currentEvent.message.destination);
            if(event.type == FaultEvent.FAULT && this.token.responders == null || cds.hasEventListener(event.type))
            {
               cdsMap[cds.destination] = cds;
            }
         }
         if(event.type == ResultEvent.RESULT || faultEvent != null)
         {
            currentEvent = faultEvent == null?AbstractEvent(event):AbstractEvent(faultEvent);
            if(currentEvent.message.destination != null && currentEvent.message.destination != "")
            {
               cds = this._store.getDataService(currentEvent.message.destination);
               if(cds.hasEventListener(event.type) && !cdsMap.hasOwnProperty(cds.destination))
               {
                  cdsMap[cds.destination] = cds;
               }
            }
         }
         if(this._store.hasEventListener(event.type))
         {
            this._store.dispatchEvent(faultEvent != null?faultEvent:event);
            dispatched = true;
         }
         this.sendCommitEvent(cdsMap,event,!dispatched);
      }
      
      private function sendCommitEvent(cdsMap:Object, event:Event, throwIfNoneSent:Boolean) : void
      {
         var cds:ConcreteDataService = null;
         var d:* = null;
         var any:Boolean = false;
         for(d in cdsMap)
         {
            any = true;
            cds = ConcreteDataService(cdsMap[d]);
            if(event.type == FaultEvent.FAULT)
            {
               cds.dispatchFaultEvent(MessageFaultEvent(event),this.token);
            }
            else
            {
               cds.dispatchEvent(event);
            }
         }
         if(throwIfNoneSent && !any && event is FaultEvent)
         {
            throw FaultEvent(event).fault;
         }
      }
   }
}
