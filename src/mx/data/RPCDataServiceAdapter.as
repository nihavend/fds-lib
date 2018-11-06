package mx.data
{
   import mx.collections.ArrayCollection;
   import mx.collections.ItemResponder;
   import mx.data.messages.DataMessage;
   import mx.data.messages.PagedMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.messages.SyncFillRequest;
   import mx.data.messages.UpdateCollectionMessage;
   import mx.data.utils.AsyncTokenChain;
   import mx.data.utils.Managed;
   import mx.logging.Log;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AcknowledgeMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AbstractOperation;
   import mx.rpc.AsyncRequest;
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   import mx.rpc.IResponder;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   
   [ResourceBundle("data")]
   public class RPCDataServiceAdapter extends DataServiceAdapter
   {
      
      public static var dataManagerRegistry:Object = new Object();
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      var manager:RPCDataManager;
      
      private var _asyncRequest:RPCDataServiceRequest;
      
      public var destination:String;
      
      public function RPCDataServiceAdapter()
      {
         super();
      }
      
      override public function getDataManager(destination:String) : DataManager
      {
         return dataManagerRegistry[destination];
      }
      
      override public function get asyncRequest() : AsyncRequest
      {
         if(this._asyncRequest == null)
         {
            this._asyncRequest = new RPCDataServiceRequest(this,this.destination);
            this._asyncRequest.channelSet = this.manager.service.channelSet;
         }
         return this._asyncRequest;
      }
      
      override public function get serializeAssociations() : Boolean
      {
         return true;
      }
      
      override public function get throwUnhandledFaults() : Boolean
      {
         return false;
      }
      
      public function createItem(dataManager:RPCDataManager, item:Object) : AsyncToken
      {
         var mop:ManagedOperation = dataManager.createOperation;
         if(mop == null)
         {
            if(Log.isWarn())
            {
               dataManager.concreteDataService.log.warn("Attempt to create a new managed item of type: " + dataManager.destination + " where no ManagedOperation of type=\'create\' is defined");
            }
            return null;
         }
         return mop.invokeService([item]);
      }
      
      public function updateItem(dataManager:RPCDataManager, item:Object, origItem:Object, changes:Array) : AsyncToken
      {
         var mop:ManagedOperation = dataManager.updateOperation;
         if(mop == null)
         {
            if(Log.isWarn())
            {
               dataManager.concreteDataService.log.warn("Attempt to update a managed item of type: " + dataManager.destination + " where no ManagedOperation of type=\'update\' is defined");
            }
            return null;
         }
         var args:Array = new Array(mop.paramCount);
         args[mop.itemIx] = item;
         if(mop.origItemIx != -1)
         {
            args[mop.origItemIx] = origItem;
         }
         if(mop.changesIx != -1)
         {
            args[mop.changesIx] = changes;
         }
         return mop.invokeService(args);
      }
      
      public function deleteItem(dataManager:RPCDataManager, item:Object) : AsyncToken
      {
         var args:Array = null;
         var serviceParametersArray:Array = null;
         var identitySize:int = 0;
         var identityIndex:int = 0;
         var mop:ManagedOperation = dataManager.deleteOperation;
         if(mop == null)
         {
            if(Log.isWarn())
            {
               dataManager.concreteDataService.log.warn("Attempt to delete a managed item of type: " + dataManager.destination + " where no ManagedOperation of type=\'delete\' is defined");
            }
            return null;
         }
         if(mop.parametersArray != null && mop.parametersArray.length > 0 && mop.parametersArray[0] != "item")
         {
            serviceParametersArray = dataManager.identitiesArray;
            if(mop.parametersArray[0] != "id")
            {
               serviceParametersArray = mop.parametersArray;
            }
            identitySize = serviceParametersArray.length;
            args = new Array(identitySize);
            for(identityIndex = 0; identityIndex < identitySize; identityIndex++)
            {
               args[identityIndex] = item[serviceParametersArray[identityIndex]];
            }
         }
         else
         {
            args = new Array(1);
            args[0] = item;
         }
         return mop.invokeService(args);
      }
      
      public function executeQuery(dataManager:RPCDataManager, queryName:String, includeSpecifier:PropertySpecifier, queryArgs:Array) : AsyncToken
      {
         var mq:ManagedQuery = null;
         var token:AsyncToken = null;
         var cop:AbstractOperation = null;
         var resultToken:AsyncToken = null;
         var pagedQueryArgs:Array = null;
         var mop:ManagedOperation = ManagedOperation(dataManager.queries[queryName]);
         if(mop == null)
         {
            throw new ArgumentError(resourceManager.getString("data","unknownManagedOperation",[queryName]));
         }
         if(mop is ManagedQuery)
         {
            mq = ManagedQuery(mop);
            if(Log.isDebug())
            {
               this.manager.concreteDataService.log.debug("RPC executeQuery: " + queryName + "(" + Managed.toString(queryArgs) + (mq.includeSpecifier == null?"":", includes=" + mq.includeSpecifier.includeSpecifierString) + ")" + (!!mq.pagingEnabled?" (paged) ":""));
            }
            if(mq.pagingEnabled)
            {
               if(mq.countOperation != null)
               {
                  cop = dataManager.service.getOperation(mq.countOperation);
                  token = cop.send.apply(cop,queryArgs);
                  resultToken = new AsyncToken();
                  resultToken.managedQuery = mq;
                  resultToken.queryArgs = queryArgs;
                  resultToken.pageSize = mq.pageSize;
                  token.addResponder(new ItemResponder(this.countQueryResult,this.rpcAdapterFault,resultToken));
                  token.managedOperation = mq;
                  return resultToken;
               }
               pagedQueryArgs = this.addPagingParameters(mq,queryArgs,0,mq.pageSize + 1);
               token = mq.invokeService(pagedQueryArgs);
               token.dynamicSizing = true;
               token.pageSize = mq.pageSize;
               token.addResponder(new ItemResponder(this.executeQueryResult,this.rpcAdapterFault,token));
               return token;
            }
         }
         token = mop.invokeService(queryArgs);
         token.addResponder(new ItemResponder(this.executeQueryResult,this.rpcAdapterFault,token));
         return token;
      }
      
      public function pageQuery(dataManager:RPCDataManager, queryName:String, queryArgs:Array, startIndex:int, numItems:int) : AsyncToken
      {
         var mq:ManagedQuery = ManagedQuery(dataManager.queries[queryName]);
         var pagedQueryArgs:Array = this.addPagingParameters(mq,queryArgs,startIndex,numItems);
         var token:AsyncToken = mq.invokeService(pagedQueryArgs);
         token.managedQuery = mq;
         token.startIndex = startIndex;
         token.numItems = numItems;
         token.pageSize = mq.pageSize;
         token.addResponder(new ItemResponder(this.pageQueryResult,this.rpcAdapterFault,token));
         if(Log.isDebug())
         {
            this.manager.concreteDataService.log.debug("RPC pageQuery: " + queryName + "(" + Managed.toString(queryArgs) + ", " + startIndex + ", " + numItems + (mq.includeSpecifier == null?"":", includes=" + mq.includeSpecifier.includeSpecifierString) + ")");
         }
         if(mq.includeSpecifier != null)
         {
            token.resultPropertySpecifier = mq.includeSpecifier;
         }
         return token;
      }
      
      public function getItem(dataManager:RPCDataManager, identity:Object, defaultValue:Object = null, includeSpecifier:PropertySpecifier = null) : AsyncToken
      {
         var token:AsyncToken = this.internalGetItem(dataManager,identity,defaultValue,includeSpecifier);
         token.addResponder(new ItemResponder(this.getItemResult,this.rpcAdapterFault,token));
         token.resultPropertySpecifier = dataManager.concreteDataService.includeAllSpecifier;
         return token;
      }
      
      private function executeSynchronizeFill(dataManager:RPCDataManager, sinceTimestamp:Date, fillParameters:Array) : AsyncToken
      {
         var queryName:String = null;
         if(fillParameters && fillParameters.length > 0)
         {
            queryName = fillParameters[0] as String;
         }
         if(!queryName)
         {
            throw new ArgumentError(resourceManager.getString("data","fillFirstParameterNotQueryName"));
         }
         var queryOp:ManagedQuery = dataManager.queries[queryName];
         if(!queryOp)
         {
            throw new ArgumentError(resourceManager.getString("data","unknownManagedOperation",[queryName]));
         }
         if(!queryOp.synchronizeOperation)
         {
            throw new ArgumentError(resourceManager.getString("data","noSynchronizedOperationDefined",[queryName]));
         }
         var syncOp:AbstractOperation = dataManager.service.getOperation(queryOp.synchronizeOperation);
         if(!syncOp)
         {
            throw new ArgumentError(resourceManager.getString("data","synchronizeOperationNotFoundInService",[queryName,queryOp.synchronizeOperation]));
         }
         var syncArgs:Array = [sinceTimestamp].concat(fillParameters);
         var token:AsyncToken = syncOp.send.apply(syncOp,syncArgs);
         token.addResponder(new ItemResponder(this.onSyncResult,this.rpcAdapterFault,token));
         return token;
      }
      
      private function onSyncResult(event:ResultEvent, token:AsyncToken) : void
      {
         var changedItems:ChangedItems = ChangedItems(event.result);
         var resultMessage:AcknowledgeMessage = new AcknowledgeMessage();
         resultMessage.body = changedItems;
         this.sendResultEvent(token,resultMessage);
      }
      
      protected function internalGetItem(dataManager:RPCDataManager, identity:Object, defaultValue:Object = null, includeSpecifier:PropertySpecifier = null) : AsyncToken
      {
         var i:int = 0;
         var param:String = null;
         var mop:ManagedOperation = dataManager.getOperation;
         if(mop == null)
         {
            throw new ArgumentError(resourceManager.getString("data","noGetManagedOperationDefined",[dataManager.destination]));
         }
         var args:Array = new Array();
         var idArray:Array = dataManager.identitiesArray;
         if(mop.parametersArray == null || mop.parametersArray.length == 0)
         {
            if(idArray.length == 1)
            {
               args.push(identity[idArray[0]]);
            }
            else
            {
               throw new ArgumentError(resourceManager.getString("data","getItemHasNoParameterDefined",[dataManager.destination,mop.name]));
            }
         }
         else
         {
            for(i = 0; i < mop.parametersArray.length; i++)
            {
               param = mop.parametersArray[i];
               args.push(identity[param]);
            }
         }
         return mop.invokeService(args);
      }
      
      public function getItems(dataManager:RPCDataManager, ids:Array, includeSpecifier:PropertySpecifier) : AsyncToken
      {
         var resultItems:Array = null;
         var resultToken:AsyncToken = null;
         var assignSubResult:Function = null;
         var onRequestResult:Function = null;
         var id:Object = null;
         var subToken:AsyncToken = null;
         assignSubResult = function(result:ResultEvent, subToken:AsyncToken):void
         {
            var item:Object = result.result;
            resultItems[subToken.index] = item;
         };
         onRequestResult = function(data:Object, token:AsyncToken = null):void
         {
            var rmsg:SequencedMessage = new SequencedMessage();
            rmsg.sequenceId = -1;
            rmsg.body = resultItems;
            sendResultEvent(resultToken,rmsg);
         };
         resultItems = new Array(ids.length);
         var requestChain:AsyncTokenChain = new AsyncTokenChain();
         for(var i:int = 0; i < ids.length; i++)
         {
            id = ids[i];
            subToken = this.getItem(dataManager,id,null,includeSpecifier);
            subToken.index = i;
            subToken.addResponder(new AsyncResponder(assignSubResult,this.emptyFaultHandler,subToken));
            requestChain.addPendingAction(subToken);
         }
         requestChain.addResponder(new AsyncResponder(onRequestResult,this.rpcAdapterFault,requestChain));
         resultToken = new AsyncToken();
         resultToken.ids = ids;
         return resultToken;
      }
      
      public function updateCollection(dataManager:RPCDataManager, mq:ManagedQuery, ucmsg:UpdateCollectionMessage) : AsyncToken
      {
         var queryParams:Array = null;
         if(dataStore && dataStore.ignoreCollectionUpdates)
         {
            return null;
         }
         if(mq == null && ucmsg.collectionId is Array)
         {
            queryParams = ucmsg.collectionId as Array;
            throw new ArgumentError(resourceManager.getString("data","unknownQueryName",[queryParams[0].toString(),dataManager.destination]));
         }
         if(mq.addItemToCollectionOperation == null && mq.removeItemFromCollectionOperation == null)
         {
            return null;
         }
         return this.updateCollectionElement(dataManager,mq,ucmsg,0,0);
      }
      
      public function handleFault(errMsg:ErrorMessage, cause:DataMessage) : void
      {
         var dmgr:RPCDataManager = this.manager.getDataManager(cause.destination);
         if(cause.operation == DataMessage.UPDATE_OPERATION && dmgr.updateConflictMode != Conflict.NONE || cause.operation == DataMessage.DELETE_OPERATION && dmgr.deleteConflictMode != Conflict.NONE)
         {
            this.startCheckForConflict(dmgr,cause,errMsg);
         }
      }
      
      public function startCheckForConflict(dmgr:RPCDataManager, cause:DataMessage, errMsg:ErrorMessage = null) : void
      {
         var token:AsyncToken = this.internalGetItem(dmgr,cause.identity);
         token.errMsg = errMsg;
         token.cause = cause;
         token.dataManager = dmgr;
         token.addResponder(new ItemResponder(this.checkForConflict,this.emptyFaultHandler,token));
      }
      
      private function emptyFaultHandler(faultEvent:Object, token:AsyncToken) : void
      {
      }
      
      protected function checkForConflict(resultEvent:ResultEvent, token:AsyncToken) : void
      {
         var conflictingProperties:Array = null;
         var result:Object = resultEvent.result;
         if(result is Array || result is ArrayCollection)
         {
            if(result.length > 0)
            {
               result = result[0];
            }
            else
            {
               result = null;
            }
         }
         var cause:DataMessage = token.cause;
         var dmgr:RPCDataManager = token.dataManager;
         if(result == null || (conflictingProperties = this.getConflictingProperties(dmgr,cause,result)) != null)
         {
            dmgr.dataStore.conflicts.raiseConflict(dmgr,cause,result,conflictingProperties);
         }
      }
      
      public function getConflictingProperties(dmgr:RPCDataManager, cause:DataMessage, serverObject:Object) : Array
      {
         var origItem:Object = null;
         var newItem:Object = null;
         var origRefIds:Object = null;
         var newRefIds:Object = null;
         var mode:String = null;
         var changes:Array = null;
         var propName:String = null;
         var assoc:ManagedAssociation = null;
         var conflictingProperties:Array = null;
         var cds:ConcreteDataService = dmgr.concreteDataService;
         if(cause.operation == DataMessage.UPDATE_OPERATION)
         {
            origItem = DataMessage.unwrapItem(cause.body[DataMessage.UPDATE_BODY_PREV]);
            origRefIds = DataMessage.unwrapItem(cause.headers.prevReferencedIds);
            newRefIds = DataMessage.unwrapItem(cause.headers.newReferencedIds);
            newItem = DataMessage.unwrapItem(cause.body[DataMessage.UPDATE_BODY_NEW]);
            changes = cause.body[DataMessage.UPDATE_BODY_CHANGES];
            mode = dmgr.updateConflictMode;
         }
         else
         {
            origItem = DataMessage.unwrapItem(cause.body);
            origRefIds = DataMessage.unwrapItem(cause.headers.referencedIds);
            newRefIds = null;
            newItem = origItem;
            mode = dmgr.deleteConflictMode;
            changes = null;
         }
         var properties:Array = ConcreteDataService.getObjectProperties(origItem);
         if(mode == Conflict.PROPERTY && changes != null)
         {
            properties = changes;
         }
         var metadata:Metadata = cds.getItemMetadata(origItem);
         for(var i:uint = 0; i < properties.length; i++)
         {
            propName = properties[i].toString();
            assoc = metadata.associations[propName];
            if(assoc != null)
            {
               if(!(assoc.loadOnDemand || !Managed.propertyFetched(origItem,propName)))
               {
                  if(!metadata.compareReferencedIdsForAssoc(assoc,serverObject[propName],origRefIds[propName]) && (mode != Conflict.PROPERTY || !metadata.compareReferencedIdsForAssoc(assoc,serverObject[propName],newRefIds[propName])))
                  {
                     if(conflictingProperties == null)
                     {
                        conflictingProperties = new Array();
                     }
                     conflictingProperties.push(propName);
                  }
               }
            }
            else if(Managed.propertyFetched(origItem,propName))
            {
               if(Managed.compare(origItem[propName],serverObject[propName],-1,null) != 0 && (mode != Conflict.PROPERTY || Managed.compare(serverObject[propName],newItem[propName],-1,null) != 0))
               {
                  if(conflictingProperties == null)
                  {
                     conflictingProperties = new Array();
                  }
                  conflictingProperties.push(propName);
               }
            }
         }
         if(mode == Conflict.OBJECT && conflictingProperties != null && changes != null)
         {
            for(i = 0; i < changes.length; i++)
            {
               if(ArrayUtil.getItemIndex(changes[i],conflictingProperties) == -1)
               {
                  conflictingProperties.push(changes[i]);
               }
            }
         }
         return conflictingProperties;
      }
      
      private function updateCollectionElement(dataManager:RPCDataManager, mq:ManagedQuery, ucmsg:UpdateCollectionMessage, startRange:int, startOp:int) : AsyncToken
      {
         var token:AsyncToken = null;
         var op:AbstractOperation = null;
         var opName:String = null;
         var add:Boolean = false;
         var range:UpdateCollectionRange = null;
         var args:Array = null;
         var argct:int = 0;
         var cds:ConcreteDataService = null;
         var j:int = 0;
         var ranges:Array = ucmsg.body as Array;
         var fillParams:Array = ucmsg.collectionId as Array;
         for(var i:int = startRange; i < ranges.length; i++)
         {
            range = UpdateCollectionRange(ranges[i]);
            if(range.updateType == UpdateCollectionRange.INSERT_INTO_COLLECTION)
            {
               opName = mq.addItemToCollectionOperation;
               add = true;
            }
            else if(range.updateType == UpdateCollectionRange.DELETE_FROM_COLLECTION)
            {
               opName = mq.removeItemFromCollectionOperation;
               add = false;
            }
            if(opName != null)
            {
               op = dataManager.service.getOperation(opName);
               args = new Array(1 + fillParams.length);
               for(argct = 0; argct < fillParams.length - 1; argct++)
               {
                  args[argct] = fillParams[argct + 1];
               }
               cds = dataManager.concreteDataService;
               for(j = startOp; j < range.identities.length; )
               {
                  args[argct] = cds.getPendingItem(cds.metadata.getUID(range.identities[j]),false,true);
                  if(args[argct] == null)
                  {
                     j++;
                     continue;
                  }
                  args[argct + 1] = range.position + (!!add?j:0);
                  token = op.send.apply(op,args);
                  token.dataManager = dataManager;
                  token.updateCollection = ucmsg;
                  token.managedQuery = mq;
                  if(j == range.identities.length - 1)
                  {
                     if(i == ranges.length - 1)
                     {
                        break;
                     }
                     token.startRange = i + 1;
                     token.startOp = 0;
                  }
                  else
                  {
                     token.startRange = i;
                     token.startOp = j + 1;
                  }
                  token.addResponder(new ItemResponder(this.updateCollectionResult,this.updateCollectionFault,token));
                  return token;
               }
            }
         }
         if(token != null)
         {
            token.addResponder(new ItemResponder(this.processBatchResult,this.updateCollectionFault,token));
         }
         return token;
      }
      
      private function updateCollectionResult(result:ResultEvent, token:AsyncToken) : void
      {
         var newToken:AsyncToken = this.updateCollectionElement(token.dataManager,token.managedQuery,token.updateCollection,token.startRange,token.startOp);
         newToken.currentMessageIndex = token.currentMessageIndex;
         newToken.batchAck = token.batchAck;
         newToken.origBatch = token.origBatch;
         newToken.chainedResponder = token.chainedResponder;
      }
      
      private function updateCollectionFault(ev:FaultEvent, token:AsyncToken) : void
      {
         this.rpcAdapterFault(ev,token);
      }
      
      public function processDataMessage(msg:IMessage, responder:IResponder) : void
      {
         var dmgr:RPCDataManager = null;
         var resultToken:AsyncToken = null;
         var token:AsyncToken = null;
         var queryName:String = null;
         var queryArgs:Array = null;
         var fillParams:Array = null;
         var syncRequest:SyncFillRequest = null;
         var batchAck:AcknowledgeMessage = null;
         var tokenChain:Object = null;
         var rt:Object = null;
         var startIndex:int = 0;
         var numItems:int = 0;
         var ids:Array = null;
         var includeSpecifier:PropertySpecifier = null;
         var dmsg:DataMessage = msg as DataMessage;
         switch(dmsg.operation)
         {
            case DataMessage.FILL_OPERATION:
            case DataMessage.FIND_ITEM_OPERATION:
               fillParams = dmsg.body as Array;
               if(fillParams == null || fillParams.length == 0 || !(fillParams[0] is String))
               {
                  throw new ArgumentError(resourceManager.getString("data","fillFirstParameterNotQueryName"));
               }
               queryName = fillParams[0];
               queryArgs = fillParams.slice(1);
               dmgr = this.manager.getDataManager(dmsg.destination);
               token = this.executeQuery(dmgr,queryName,dmgr.concreteDataService.getMessagePropertySpecifier(dmsg),queryArgs);
               token.resultToken = ITokenResponder(responder).resultToken;
               break;
            case DataMessage.SYNCHRONIZE_FILL_OPERATION:
               syncRequest = SyncFillRequest(dmsg.body);
               dmgr = this.manager.getDataManager(dmsg.destination);
               token = this.executeSynchronizeFill(dmgr,syncRequest.sinceTimestamp,syncRequest.fillParameters);
               token.resultToken = ITokenResponder(responder).resultToken;
               break;
            case DataMessage.GET_OPERATION:
               dmgr = this.manager.getDataManager(dmsg.destination);
               token = this.getItem(dmgr,dmsg.identity,dmsg.body,dmgr.concreteDataService.getMessagePropertySpecifier(dmsg));
               token.resultToken = ITokenResponder(responder).resultToken;
               if(token.resultPropertySpecifier != null)
               {
                  dmsg.headers.DSincludeSpec = PropertySpecifier(token.resultPropertySpecifier).includeSpecifierString;
               }
               break;
            case DataMessage.TRANSACTED_OPERATION:
               throw new ArgumentError(resourceManager.getString("data","csdmsTransactionNotSupported"));
            case DataMessage.BATCHED_OPERATION:
               batchAck = new AcknowledgeMessage();
               batchAck.body = new Array();
               batchAck.correlationId = dmsg.messageId;
               batchAck.destination = dmsg.destination;
               token = this.processBatch(dmsg,batchAck,0,responder);
               tokenChain = CommitResponder(responder).token[DataStore.TOKEN_CHAIN];
               if(tokenChain != null && token != null)
               {
                  rt = tokenChain[dmsg.messageId];
                  if(rt != null)
                  {
                     token.resultToken = rt;
                  }
               }
               break;
            case DataMessage.PAGE_OPERATION:
               dmgr = this.manager.getDataManager(dmsg.destination);
               if(dmsg.body is Array)
               {
                  fillParams = dmsg.body as Array;
                  queryName = fillParams[0];
                  queryArgs = fillParams.slice(1);
                  startIndex = dmsg.headers.pageIndex * dmsg.headers.pageSize;
                  numItems = dmsg.headers.pageSize;
                  if(dmsg.headers.dynamicSizing != null)
                  {
                     numItems++;
                  }
                  token = this.pageQuery(dmgr,queryName,queryArgs,startIndex,numItems);
                  if(token.resultPropertySpecifier != null)
                  {
                     dmsg.headers.DSincludeSpec = PropertySpecifier(token.resultPropertySpecifier).includeSpecifierString;
                  }
               }
               break;
            case DataMessage.PAGE_ITEMS_OPERATION:
               dmgr = this.manager.getDataManager(dmsg.destination);
               ids = dmsg.headers.DSids;
               includeSpecifier = dmgr.concreteDataService.getMessagePropertySpecifier(dmsg);
               token = this.getItems(dmgr,ids,includeSpecifier);
               break;
            default:
               throw new ArgumentError(resourceManager.getString("data","unknownDataMessageInRPCDataAdapter",[String(dmsg.operation)]));
         }
         if(token != null)
         {
            token.chainedResponder = responder;
         }
      }
      
      function addPagingParameters(mq:ManagedQuery, queryArgs:Array, startIndex:int, numItems:int) : Array
      {
         var i:int = 0;
         var j:int = 0;
         var num:int = queryArgs.length + 2;
         var pagedQueryArgs:Array = new Array(num);
         if(mq.startIndexParamPos == -1)
         {
            for(i = 0; i < queryArgs.length; i++)
            {
               pagedQueryArgs[i] = queryArgs[i];
            }
            pagedQueryArgs[i++] = startIndex;
            pagedQueryArgs[i] = numItems;
         }
         else
         {
            j = 0;
            for(i = 0; i < num; i++)
            {
               if(i == mq.startIndexParamPos)
               {
                  pagedQueryArgs[i] = startIndex;
               }
               else if(i == mq.numItemsParamPos)
               {
                  pagedQueryArgs[i] = numItems;
               }
               else
               {
                  pagedQueryArgs[i] = queryArgs[j];
                  j++;
               }
            }
         }
         return pagedQueryArgs;
      }
      
      private function processBatch(origBatch:DataMessage, batchAck:AcknowledgeMessage, msgNum:int, finalResponder:IResponder) : AsyncToken
      {
         var prevItem:Object = null;
         var newItem:Object = null;
         var ucmsg:UpdateCollectionMessage = null;
         var tokenChain:Object = null;
         var batch:Array = origBatch.body as Array;
         var dmsg:DataMessage = DataMessage(batch[msgNum]);
         var token:AsyncToken = null;
         var destAdapter:RPCDataServiceAdapter = RPCDataServiceAdapter(getDataServiceAdapter(dmsg.destination));
         if(destAdapter == null)
         {
            throw new ArgumentError(resourceManager.getString("data","noAssociationSameDataStore",[this.destination,dmsg.destination]));
         }
         var dmgr:RPCDataManager = this.manager.getDataManager(dmsg.destination);
         switch(dmsg.operation)
         {
            case DataMessage.CREATE_OPERATION:
            case DataMessage.CREATE_AND_SEQUENCE_OPERATION:
               token = destAdapter.createItem(dmgr,DataMessage.unwrapItem(dmsg.body));
               break;
            case DataMessage.UPDATE_OPERATION:
               prevItem = DataMessage.unwrapItem(dmsg.body[DataMessage.UPDATE_BODY_PREV]);
               newItem = DataMessage.unwrapItem(dmsg.body[DataMessage.UPDATE_BODY_NEW]);
               if(prevItem.destination == null)
               {
                  prevItem.destination = newItem.destination;
               }
               else if(newItem.destination == null)
               {
                  newItem.destination = prevItem.destination;
               }
               dmgr.concreteDataService.setAssociationsFromIds(prevItem,DataMessage.unwrapItem(dmsg.headers.prevReferencedIds));
               dmgr.concreteDataService.setAssociationsFromIds(newItem,DataMessage.unwrapItem(dmsg.headers.newReferencedIds));
               token = destAdapter.updateItem(dmgr,newItem,prevItem,dmsg.body[DataMessage.UPDATE_BODY_CHANGES]);
               break;
            case DataMessage.DELETE_OPERATION:
               token = destAdapter.deleteItem(dmgr,DataMessage.unwrapItem(dmsg.body));
               break;
            case DataMessage.UPDATE_COLLECTION_OPERATION:
               ucmsg = UpdateCollectionMessage(dmsg);
               token = this.processUC(dmgr,destAdapter,origBatch,batchAck,msgNum,ucmsg);
               if(token != null)
               {
                  return token;
               }
               break;
            default:
               throw new ArgumentError(resourceManager.getString("data","unexpectedMessageInBatch",[dmsg.operation.toString()]));
         }
         if(token != null)
         {
            token.currentMessageIndex = msgNum;
            token.batchAck = batchAck;
            token.origBatch = origBatch;
            token.addResponder(new ItemResponder(this.processBatchResult,this.batchFault,token));
            tokenChain = CommitResponder(finalResponder).token[DataStore.TOKEN_CHAIN];
            if(tokenChain != null)
            {
               token.resultToken = tokenChain[dmsg.messageId];
            }
            if(token.resultToken == null)
            {
               token.resultToken = CommitResponder(finalResponder).token;
            }
         }
         else
         {
            msgNum++;
            batchAck.body.push(dmsg);
            if(msgNum == batch.length)
            {
               this.completeBatch(batchAck,CommitResponder(finalResponder));
            }
            else
            {
               return this.processBatch(origBatch,batchAck,msgNum,finalResponder);
            }
         }
         return token;
      }
      
      private function processUC(dmgr:RPCDataManager, destAdapter:RPCDataServiceAdapter, origBatch:DataMessage, batchAck:AcknowledgeMessage, msgNum:int, ucmsg:UpdateCollectionMessage) : AsyncToken
      {
         var queryParams:Array = null;
         var mq:ManagedQuery = null;
         var token:AsyncToken = null;
         if(ucmsg.collectionId is Array)
         {
            queryParams = ucmsg.collectionId as Array;
            mq = dmgr.queries[queryParams[0]];
            token = destAdapter.updateCollection(dmgr,mq,ucmsg);
            if(token != null)
            {
               token.currentMessageIndex = msgNum;
               token.batchAck = batchAck;
               token.origBatch = origBatch;
            }
         }
         return token;
      }
      
      private function processBatchResult(ev:ResultEvent, oldToken:AsyncToken) : void
      {
         var serviceResult:Object = null;
         var clientVersion:Object = null;
         var newChanges:Array = null;
         var origChanges:Array = null;
         var token:AsyncToken = null;
         var currentMessageIndex:int = oldToken.currentMessageIndex;
         var origBatch:DataMessage = oldToken.origBatch;
         var batchAck:AcknowledgeMessage = oldToken.batchAck;
         var origArray:Array = origBatch.body as Array;
         var origMsg:DataMessage = origBatch.body[currentMessageIndex];
         var newMsg:DataMessage = ObjectUtil.copy(origMsg) as DataMessage;
         newMsg.messageId = origMsg.messageId;
         batchAck.body.push(newMsg);
         var result:Object = ev.result;
         var dmgr:RPCDataManager = this.manager.getDataManager(newMsg.destination);
         if(oldToken.resultToken != null)
         {
            oldToken.resultToken.originalEvent = ev;
         }
         switch(newMsg.operation)
         {
            case DataMessage.CREATE_OPERATION:
            case DataMessage.CREATE_AND_SEQUENCE_OPERATION:
               if(result != null)
               {
                  serviceResult = result;
                  result = this.processArrayResult(result,oldToken.resultToken);
                  if(result is int || result is String || result is Number || result is Date)
                  {
                     DataMessage.unwrapItem(newMsg.body)[dmgr.identitiesArray[0]] = result;
                     newMsg.identity = new Object();
                     newMsg.identity[dmgr.identitiesArray[0]] = result;
                     if(oldToken.resultToken != null)
                     {
                        oldToken.resultToken.serviceResult = serviceResult;
                     }
                  }
                  else
                  {
                     newMsg.body = result;
                  }
               }
               break;
            case DataMessage.DELETE_OPERATION:
               if(oldToken.resultToken != null)
               {
                  oldToken.resultToken.serviceResult = result;
               }
               break;
            case DataMessage.UPDATE_OPERATION:
               result = this.processArrayResult(result,oldToken.resultToken);
               if(result != null)
               {
                  clientVersion = DataMessage.unwrapItem(newMsg.body[DataMessage.UPDATE_BODY_NEW]);
                  newMsg.body[DataMessage.UPDATE_BODY_NEW] = result;
                  newChanges = dmgr.concreteDataService.getChangedProperties(result,clientVersion,PropertySpecifier.ALL,null,null,DataMessage.unwrapItem(origMsg.headers.prevReferencedIds));
                  origChanges = origMsg.body[DataMessage.UPDATE_BODY_CHANGES];
                  if(newChanges == null)
                  {
                     newChanges = origChanges;
                  }
                  else if(origChanges != null)
                  {
                     newChanges = newChanges.concat(origChanges);
                  }
                  newMsg.body[DataMessage.UPDATE_BODY_CHANGES] = newChanges;
               }
         }
         currentMessageIndex++;
         if(currentMessageIndex == origArray.length)
         {
            this.completeBatch(batchAck,oldToken.chainedResponder);
         }
         else
         {
            if(oldToken.chainedResponder is CommitResponder)
            {
               CommitResponder(oldToken.chainedResponder).processResults([newMsg],origBatch.messageId);
            }
            token = this.processBatch(origBatch,batchAck,currentMessageIndex,oldToken.chainedResponder);
            if(token != null)
            {
               token.chainedResponder = oldToken.chainedResponder;
            }
         }
      }
      
      private function processArrayResult(result:Object, resultToken:AsyncToken) : Object
      {
         if(result is Array || result is ArrayCollection)
         {
            if(result.length == 1)
            {
               if(resultToken != null)
               {
                  if(result is Array)
                  {
                     resultToken._arrayResult = true;
                  }
                  else if(result is ArrayCollection)
                  {
                     resultToken._arrayCollectionResult = true;
                  }
               }
               result = result[0];
            }
            else
            {
               if(Log.isError())
               {
                  this.manager.concreteDataService.log.error("Array result returned multi-valued array when a single value was expected: " + Managed.toString(result));
               }
               result = null;
            }
         }
         return result;
      }
      
      private function completeBatch(batchAck:AcknowledgeMessage, responder:CommitResponder) : void
      {
         var rvt:MessageEvent = MessageEvent.createEvent(MessageEvent.RESULT,batchAck);
         responder.processResult(rvt,true);
      }
      
      private function batchFault(ev:FaultEvent, token:AsyncToken) : void
      {
         var currentMessageIndex:int = token.currentMessageIndex;
         var batchAck:AcknowledgeMessage = token.batchAck;
         var origBatch:DataMessage = token.origBatch;
         var origMsg:DataMessage = origBatch.body[currentMessageIndex];
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = ev.fault.faultCode;
         errMsg.faultString = ev.fault.faultString;
         errMsg.faultDetail = ev.fault.faultDetail;
         errMsg.correlationId = origMsg.messageId;
         errMsg.destination = origMsg.destination;
         batchAck.body.push(errMsg);
         try
         {
            this.sendResultEvent(token,batchAck);
         }
         finally
         {
            this.handleFault(errMsg,origMsg);
         }
      }
      
      private function executeQueryResult(event:ResultEvent, token:AsyncToken) : void
      {
         var resultArray:Array = null;
         var result:Object = event.result;
         token.resultToken.originalEvent = event;
         if(result is Array)
         {
            resultArray = result as Array;
         }
         else if(result is ArrayCollection)
         {
            resultArray = ArrayCollection(result).source;
         }
         else
         {
            resultArray = new Array();
            if(result != null)
            {
               resultArray.push(result);
            }
         }
         var rmsg:SequencedMessage = new SequencedMessage();
         rmsg.sequenceId = -1;
         if(token.sequenceSize != null)
         {
            rmsg.sequenceSize = token.sequenceSize;
            if(rmsg.sequenceSize > resultArray.length)
            {
               rmsg.headers.paged = true;
            }
         }
         else if(token.dynamicSizing != null)
         {
            if(resultArray.length == token.pageSize + 1)
            {
               rmsg.sequenceSize = resultArray.length;
               resultArray.splice(-1,1);
               rmsg.dynamicSizing = 1;
               rmsg.headers.paged = true;
            }
            else
            {
               rmsg.sequenceSize = resultArray.length;
            }
         }
         else
         {
            rmsg.sequenceSize = resultArray.length;
         }
         rmsg.body = resultArray;
         if(token.pageSize)
         {
            rmsg.headers.pageSize = token.pageSize;
         }
         this.sendResultEvent(token,rmsg);
      }
      
      private function pageQueryResult(event:ResultEvent, token:AsyncToken) : void
      {
         var resultArray:Array = null;
         var result:Object = event.result;
         if(result is Array)
         {
            resultArray = result as Array;
         }
         else if(result is ArrayCollection)
         {
            resultArray = ArrayCollection(result).source;
         }
         else
         {
            resultArray = new Array();
            if(result != null)
            {
               resultArray.push(result);
            }
         }
         var pmsg:PagedMessage = new PagedMessage();
         var pageSize:int = token.pageSize;
         var numItems:int = token.numItems;
         pmsg.sequenceId = -1;
         if(resultArray.length < numItems || numItems > pageSize)
         {
            pmsg.sequenceSize = token.startIndex + resultArray.length;
         }
         else
         {
            pmsg.sequenceSize = -1;
         }
         if(numItems > pageSize && numItems == resultArray.length)
         {
            resultArray.splice(-1,1);
         }
         pmsg.body = resultArray;
         pmsg.pageCount = (resultArray.length + pageSize - 1) / pageSize;
         pmsg.pageIndex = token.startIndex / pageSize;
         this.sendResultEvent(token,pmsg);
      }
      
      protected function sendResultEvent(token:AsyncToken, msg:IMessage) : void
      {
         var ev:MessageEvent = null;
         if(token.chainedResponder)
         {
            ev = MessageEvent.createEvent(MessageEvent.RESULT,msg);
            token.chainedResponder.result(ev);
         }
      }
      
      private function getItemResult(event:ResultEvent, token:AsyncToken) : void
      {
         var resultArray:Array = null;
         var result:Object = event.result;
         var resultToken:AsyncToken = token.resultToken;
         if(resultToken != null)
         {
            resultToken.originalEvent = event;
         }
         if(result is Array)
         {
            resultArray = result as Array;
            if(resultToken != null)
            {
               resultToken._arrayResult = true;
            }
         }
         else if(result is ArrayCollection)
         {
            resultArray = ArrayCollection(result).source;
            if(resultToken != null)
            {
               resultToken._arrayCollectionResult = true;
            }
         }
         else if(result == null)
         {
            resultArray = [];
         }
         else
         {
            resultArray = [result];
         }
         var rmsg:SequencedMessage = new SequencedMessage();
         rmsg.sequenceId = -1;
         rmsg.sequenceSize = resultArray.length;
         rmsg.body = resultArray;
         this.sendResultEvent(token,rmsg);
      }
      
      protected function rpcAdapterFault(ev:FaultEvent, token:AsyncToken) : void
      {
         var errorMsg:ErrorMessage = new ErrorMessage();
         errorMsg.faultCode = ev.fault.faultCode;
         errorMsg.faultString = ev.fault.faultString;
         errorMsg.faultDetail = ev.fault.faultDetail;
         if(token.resultToken != null && token.resultToken.message != null)
         {
            errorMsg.destination = token.resultToken.message.destination;
            errorMsg.correlationId = token.resultToken.message.messageId;
         }
         errorMsg.rootCause = ev;
         var mfevent:MessageFaultEvent = MessageFaultEvent.createEvent(errorMsg);
         token.chainedResponder.fault(mfevent);
      }
      
      private function countQueryResult(event:ResultEvent, token:AsyncToken) : void
      {
         var pagedQueryArgs:Array = null;
         if(!(event.result is int))
         {
            throw new ArgumentError(resourceManager.getString("data","countResultNotInt",[Managed.toString(event.result)]));
         }
         var size:int = int(event.result);
         var mq:ManagedQuery = token.managedQuery;
         if(size == -1)
         {
            pagedQueryArgs = this.addPagingParameters(mq,token.queryArgs,0,mq.pageSize + 1);
            token.dynamicSizing = true;
         }
         else
         {
            token.sequenceSize = size;
            pagedQueryArgs = this.addPagingParameters(mq,token.queryArgs,0,mq.pageSize);
         }
         var newToken:AsyncToken = mq.invokeService(pagedQueryArgs);
         newToken.addResponder(new ItemResponder(this.executeQueryResult,this.rpcAdapterFault,token));
      }
      
      public function postItemUpdate(dataManager:RPCDataManager, item:Object, origItem:Object = null, changes:Array = null) : void
      {
         var ds:ConcreteDataService = dataManager.concreteDataService;
         var uid:String = ds.metadata.getUID(item);
         var cachedItem:Object = ds.getItem(uid);
         if(cachedItem == null)
         {
            ds.dataStore.restoreReferencedItems(ds,null,[uid],false);
            cachedItem = ds.getItem(uid);
         }
         var dataMessage:DataMessage = new DataMessage();
         dataMessage.identity = ds.getIdentityMap(item);
         if(cachedItem)
         {
            dataMessage.operation = DataMessage.UPDATE_OPERATION;
            dataMessage.body = {};
            if(changes)
            {
               dataMessage.body[DataMessage.UPDATE_BODY_CHANGES] = changes;
            }
            dataMessage.body[DataMessage.UPDATE_BODY_NEW] = item;
            if(origItem)
            {
               dataMessage.body[DataMessage.UPDATE_BODY_PREV] = origItem;
            }
         }
         else
         {
            dataMessage.operation = DataMessage.CREATE_OPERATION;
            dataMessage.body = item;
         }
         ds.processPushMessage(dataMessage);
      }
      
      public function postItemDeletion(dataManager:RPCDataManager, identity:Object) : void
      {
         var ds:ConcreteDataService = dataManager.concreteDataService;
         var uid:String = ds.metadata.getUID(identity);
         var cachedItem:Object = ds.getItem(uid);
         if(cachedItem == null)
         {
            ds.dataStore.restoreReferencedItems(ds,null,[uid],false);
            cachedItem = ds.getItem(uid);
         }
         var dataMessage:DataMessage = new DataMessage();
         dataMessage.operation = DataMessage.DELETE_OPERATION;
         dataMessage.identity = identity;
         dataManager.concreteDataService.processPushMessage(dataMessage);
      }
   }
}

import mx.data.RPCDataServiceAdapter;
import mx.messaging.Channel;
import mx.messaging.events.ChannelEvent;
import mx.messaging.messages.IMessage;
import mx.rpc.AsyncRequest;
import mx.rpc.IResponder;

class RPCDataServiceRequest extends AsyncRequest
{
    
   
   private var _adapter:RPCDataServiceAdapter;
   
   function RPCDataServiceRequest(dsa:RPCDataServiceAdapter, dst:String = null)
   {
      super();
      this._adapter = dsa;
      destination = dst;
   }
   
   override public function connect() : void
   {
      setConnected(true);
      dispatchEvent(ChannelEvent.createEvent(ChannelEvent.CONNECT,channelSet == null?null:channelSet.currentChannel,false,false,true));
   }
   
   override public function invoke(msg:IMessage, responder:IResponder) : void
   {
      this._adapter.processDataMessage(msg,responder);
   }
}
