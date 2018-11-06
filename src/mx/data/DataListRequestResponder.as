package mx.data
{
   import flash.events.Event;
   import mx.data.messages.DataMessage;
   import mx.data.messages.SequencedMessage;
   import mx.data.utils.Managed;
   import mx.logging.Log;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncToken;
   import mx.rpc.IResponder;
   
   public class DataListRequestResponder implements IResponder, ITokenResponder
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      private var _dataList:DataList;
      
      var token:AsyncToken;
      
      private var _reconnecting:Boolean;
      
      public function DataListRequestResponder(dataList:DataList, token:AsyncToken)
      {
         super();
         this._dataList = dataList;
         this._reconnecting = dataList.service.reconnecting;
         this.token = token;
      }
      
      public function result(data:Object) : void
      {
         var event:MessageEvent = null;
         var cds:ConcreteDataService = null;
         var dmsg:DataMessage = null;
         var smsg:SequencedMessage = null;
         var op:int = 0;
         var refresh:Boolean = false;
         var msg:SequencedMessage = null;
         var item:Object = null;
         var fillTimestamp:Number = NaN;
         event = MessageEvent(data);
         if(this._dataList.referenceCount == 0)
         {
            if(Log.isDebug())
            {
               this._dataList.service.log.debug("Ignoring result for data list that has since been released for operation");
            }
            return;
         }
         try
         {
            cds = this._dataList.service;
            cds.dataStore.enableDelayedReleases();
            dmsg = DataMessage(this.token.message);
            op = dmsg.operation;
            switch(op)
            {
               case DataMessage.FILL_OPERATION:
                  smsg = SequencedMessage(event.message);
                  if(smsg.body is IPagedList)
                  {
                     this._dataList.pagedList = IPagedList(smsg.body);
                  }
                  else
                  {
                     this._dataList.fillTimestamp = new Date();
                     fillTimestamp = smsg.headers.fillTimestamp;
                     if(!isNaN(fillTimestamp))
                     {
                        this._dataList.fillTimestamp.time = fillTimestamp;
                     }
                     if(!this.token.message.headers.DSrefresh)
                     {
                        this._dataList.clear();
                        refresh = false;
                     }
                     else
                     {
                        refresh = true;
                     }
                     this._dataList.processSequenceResult(event,this.token,true,false,refresh);
                  }
                  cds.dispatchResultEvent(event,this.token,this._dataList.view);
                  break;
               case DataMessage.FILLIDS_OPERATION:
                  this._dataList.processSequenceIds(event,this.token);
                  cds.dispatchResultEvent(event,this.token,event.message.body);
                  break;
               case DataMessage.PAGE_OPERATION:
               case DataMessage.PAGE_ITEMS_OPERATION:
                  this._dataList.processSequenceResult(event,this.token,false,op == DataMessage.PAGE_ITEMS_OPERATION);
                  cds.dispatchResultEvent(event,this.token,this._dataList.view,false,false);
                  break;
               case DataMessage.GET_SEQUENCE_ID_OPERATION:
                  msg = SequencedMessage(event.message);
                  if(msg.sequenceId != -1)
                  {
                     this._dataList.updateSequenceIds(msg.sequenceId,msg.sequenceSize,msg.sequenceProxies);
                  }
                  break;
               case DataMessage.FIND_ITEM_OPERATION:
               case DataMessage.GET_OR_CREATE_OPERATION:
                  this._dataList.smo = true;
                  this._dataList.processSequenceResult(event,this.token);
                  item = this._dataList.length > 0?this._dataList.getItemAt(0):null;
                  if(op == DataMessage.GET_OR_CREATE_OPERATION)
                  {
                     this._dataList.fillParameters = cds.getIdentityMap(item);
                  }
                  cds.dispatchResultEvent(event,this.token,item);
                  break;
               case DataMessage.GET_OPERATION:
                  if(event.message.body == null)
                  {
                     if(this._dataList.itemReference != null)
                     {
                        this._dataList.itemReference.invalid = true;
                     }
                     cds.removeDataList(this._dataList);
                     cds.dispatchResultEvent(event,this.token,null);
                  }
                  else
                  {
                     this._dataList.smo = true;
                     this._dataList.processSequenceResult(event,this.token);
                     cds.dispatchResultEvent(event,this.token,this._dataList.getItemAt(0));
                  }
            }
         }
         catch(e:Error)
         {
            cds.dataStore.disableDelayedReleases();
            throw e;
         }
         cds.dataStore.disableDelayedReleases();
      }
      
      public function fault(info:Object) : void
      {
         var dataService:ConcreteDataService = this._dataList.service;
         dataService.clientIdsAdded = false;
         if(info is MessageFaultEvent && MessageFaultEvent(info).faultCode == "InvalidSequenceId")
         {
            if(Log.isDebug())
            {
               this._dataList.service.log.debug("Received InvalidSequence response for dataList: no longer subscribed to: " + Managed.toString(this._dataList.collectionId));
            }
            this._dataList.sequenceId = -1;
            return;
         }
         if(this.isReconnectAttempt(info))
         {
            dataService.disconnect();
            return;
         }
         switch(DataMessage(this.token.message).operation)
         {
            case DataMessage.PAGE_OPERATION:
               this._dataList.removeRequest(this.token.request,MessageFaultEvent(info).message);
               dataService.dispatchFaultEvent(Event(info),this.token);
               break;
            case DataMessage.GET_OPERATION:
               dataService.removeDataList(this._dataList);
               dataService.dispatchFaultEvent(Event(info),this.token,DataMessage(this.token.message).identity);
               break;
            case DataMessage.GET_OR_CREATE_OPERATION:
            case DataMessage.CREATE_AND_SEQUENCE_OPERATION:
               dataService.removeDataList(this._dataList);
               dataService.dispatchFaultEvent(Event(info),this.token,DataMessage(this.token.message).identity);
               break;
            case DataMessage.GET_SEQUENCE_ID_OPERATION:
            case DataMessage.FILLIDS_OPERATION:
               dataService.dispatchFaultEvent(Event(info),this.token,DataMessage(this.token.message).identity);
               break;
            default:
               dataService.dispatchFaultEvent(Event(info),this.token,null);
         }
      }
      
      private function isReconnectAttempt(info:Object) : Boolean
      {
         return this._reconnecting && info is MessageFaultEvent && info.faultCode != null && info.faultCode.indexOf("Client") == 0;
      }
      
      public function get resultToken() : AsyncToken
      {
         return this.token;
      }
   }
}
