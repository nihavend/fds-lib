package mx.data
{
   import mx.collections.ArrayCollection;
   import mx.data.messages.DataMessage;
   import mx.data.messages.ManagedRemoteServiceMessage;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.managers.CursorManager;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AbstractOperation;
   import mx.rpc.AbstractService;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.mxml.Concurrency;
   
   public class ManagedRemoteServiceOperation extends AbstractOperation
   {
      
      private static var _log:ILogger;
       
      
      public var argumentNames:Array;
      
      private var _concurrency:String;
      
      private var _concurrencySet:Boolean;
      
      private var _makeObjectsBindableSet:Boolean;
      
      private var _showBusyCursor:Boolean;
      
      private var _showBusyCursorSet:Boolean;
      
      private var resourceManager:IResourceManager;
      
      var managedRemoteService:ManagedRemoteService;
      
      var operation:int;
      
      public function ManagedRemoteServiceOperation(managedRemoteService:AbstractService = null, name:String = null)
      {
         this.resourceManager = ResourceManager.getInstance();
         super(managedRemoteService,name);
         this.argumentNames = [];
         this.managedRemoteService = ManagedRemoteService(managedRemoteService);
         _log = Log.getLogger("mx.data.ManagedRemoteServiceOperation");
      }
      
      [Inspectable(defaultValue="multiple",enumeration="multiple,single,last",category="General")]
      public function get concurrency() : String
      {
         if(this._concurrencySet)
         {
            return this._concurrency;
         }
         return this.managedRemoteService.concurrency;
      }
      
      public function set concurrency(c:String) : void
      {
         this._concurrency = c;
         this._concurrencySet = true;
      }
      
      [Inspectable(defaultValue="true",category="General")]
      override public function get makeObjectsBindable() : Boolean
      {
         if(this._makeObjectsBindableSet)
         {
            return _makeObjectsBindable;
         }
         return ManagedRemoteService(service).makeObjectsBindable;
      }
      
      override public function set makeObjectsBindable(b:Boolean) : void
      {
         _makeObjectsBindable = b;
         this._makeObjectsBindableSet = true;
      }
      
      public function get showBusyCursor() : Boolean
      {
         if(this._showBusyCursorSet)
         {
            return this._showBusyCursor;
         }
         return this.managedRemoteService.showBusyCursor;
      }
      
      public function set showBusyCursor(sbc:Boolean) : void
      {
         this._showBusyCursor = sbc;
         this._showBusyCursorSet = true;
      }
      
      override public function send(... args) : AsyncToken
      {
         var token:AsyncToken = null;
         if(service != null)
         {
            service.initialize();
         }
         token = new AsyncToken();
         var success:Function = function():void
         {
            var i:int = 0;
            var op:ManagedRemoteServiceOperation = managedRemoteService.getOperation(name) as ManagedRemoteServiceOperation;
            if(operation != op.operation)
            {
               operation = op.operation;
            }
            if(!args || args.length == 0 && this.arguments)
            {
               if(this.arguments is Array)
               {
                  args = this.arguments as Array;
               }
               else
               {
                  args = [];
                  for(i = 0; i < argumentNames.length; i++)
                  {
                     args[i] = this.arguments[argumentNames[i]];
                  }
               }
            }
            token = internal_send(token,args);
         };
         var failed:Function = function(details:String):void
         {
            dispatchFaultEvent(getFailedInitializationFault(details),token);
         };
         if(!this.managedRemoteService.isInit)
         {
            this.managedRemoteService.doInit(success,failed);
         }
         else
         {
            success();
         }
         return token;
      }
      
      private function internal_send(token:AsyncToken, args:Array) : AsyncToken
      {
         var m:String = null;
         var fault:Fault = null;
         var faultEvent:FaultEvent = null;
         var returnType:Class = null;
         var entityDataService:ConcreteDataService = null;
         var fillArgs:Array = null;
         var i:int = 0;
         var singleResult:Boolean = false;
         var fillType:String = null;
         var pageSize:int = 0;
         var dynamicSizing:Boolean = false;
         var ac:ArrayCollection = null;
         var fillToken:AsyncToken = null;
         var getReturnType:Class = null;
         var ds:ConcreteDataService = null;
         var idPropertyNames:Array = null;
         var identity:Object = null;
         var getToken:ItemReference = null;
         var body:Array = null;
         var message:ManagedRemoteServiceMessage = null;
         if(this.managedRemoteService.convertParametersHandler != null)
         {
            args = this.managedRemoteService.convertParametersHandler(args);
         }
         if(operationManager != null)
         {
            return operationManager(args);
         }
         if(Concurrency.SINGLE == this.concurrency && activeCalls.hasActiveCalls())
         {
            m = this.resourceManager.getString("rpc","pendingCallExists");
            fault = new Fault("ConcurrencyError",m);
            faultEvent = FaultEvent.createEvent(fault,token);
            new AsyncDispatcher(dispatchRpcEvent,[faultEvent],10);
            return token;
         }
         if(asyncRequest.channelSet == null && this.managedRemoteService.endpoint != null)
         {
            this.managedRemoteService.initEndpoint();
         }
         var dataMsgs:Array = this.createDataMessagesForArguments(args);
         if(this.operation == DataMessage.FILL_OPERATION || this.operation == DataMessage.FIND_ITEM_OPERATION)
         {
            _log.debug("Starting Managed Remote Service fill or findItem operation " + name);
            returnType = this.managedRemoteService.metadata.lookupMethodReturnValue(name);
            entityDataService = this.managedRemoteService.lookupDataService(returnType);
            fillArgs = new Array();
            fillArgs.push("MRDestination:" + this.managedRemoteService.destination + ";method-name:" + name);
            for(i = 0; i < args.length; i++)
            {
               fillArgs.push(args[i]);
            }
            singleResult = false;
            fillType = "fill";
            if(this.operation == DataMessage.FIND_ITEM_OPERATION)
            {
               singleResult = true;
               fillType = "findItem";
            }
            pageSize = this.managedRemoteService.pageSize;
            if(pageSize < 1)
            {
               pageSize = this.managedRemoteService.metadata.lookupFillMethodPageSize(name);
            }
            dynamicSizing = false;
            if(pageSize > 1)
            {
               dynamicSizing = true;
            }
            ac = new ArrayCollection();
            entityDataService.pageSize = pageSize;
            fillToken = entityDataService.fill(ac,fillArgs,null,singleResult,false,token);
            fillToken.dynamicSizing = dynamicSizing;
            fillToken.type = fillType;
            fillToken.source = this;
            this.managedRemoteService.pageSize = -1;
            return fillToken;
         }
         if(this.operation == DataMessage.GET_OPERATION)
         {
            _log.debug("Starting Managed Remote Service get operation " + name);
            getReturnType = this.managedRemoteService.metadata.lookupMethodReturnValue(name);
            ds = this.managedRemoteService.lookupDataService(getReturnType);
            idPropertyNames = this.managedRemoteService.metadata.identities;
            identity = new Object();
            for(i = 0; i < args.length; i++)
            {
               identity[idPropertyNames[i]] = args[i];
            }
            getToken = ds.getItem(identity,null);
            return getToken;
         }
         body = new Array(2);
         body[0] = args;
         body[1] = dataMsgs;
         message = new ManagedRemoteServiceMessage();
         message.operation = this.operation;
         message.name = name;
         message.operationMethodName = name;
         message.body = body;
         message.destination = ManagedRemoteService(service).destination;
         return this.invoke(message,token);
      }
      
      private function createDataMessagesForArguments(args:Array) : Array
      {
         var ds:ConcreteDataService = null;
         var datastore:DataStore = null;
         var messageCache:DataMessageCache = null;
         var createToken:AsyncToken = null;
         var newMsg:DataMessage = null;
         var deleteToken:AsyncToken = null;
         var deleteMessage:DataMessage = null;
         var updateMsgs:Array = null;
         var j:int = 0;
         var msg:DataMessage = null;
         var dataMsgs:Array = new Array();
         for(var i:int = 0; i < args.length; i++)
         {
            ds = this.managedRemoteService.lookupDataService(Object(args[i]).constructor);
            if(ds == null)
            {
               _log.debug("No DataService found for method parameter " + args[i] + " - skipping it");
            }
            else
            {
               datastore = ds.dataStore;
               messageCache = datastore.messageCache;
               if(this.operation == DataMessage.CREATE_OPERATION)
               {
                  this.operation = DataMessage.CREATE_OPERATION;
                  createToken = ds.createItem(args[i]);
                  newMsg = messageCache.getCreateMessage(ds,args[i]);
                  dataMsgs.push(newMsg);
               }
               else if(this.operation == DataMessage.DELETE_OPERATION && args[i].hasOwnProperty("uid"))
               {
                  this.operation = DataMessage.DELETE_OPERATION;
                  deleteToken = ds.deleteItem(args[i]);
                  deleteMessage = messageCache.getPendingDeleteMessage(ds,args[i].uid);
                  dataMsgs.push(deleteMessage);
               }
               else if(this.operation == DataMessage.UPDATE_OPERATION)
               {
                  this.operation = DataMessage.UPDATE_OPERATION;
                  if(args[i].hasOwnProperty("uid"))
                  {
                     updateMsgs = messageCache.getUncommittedMessages(ds,args[i].uid);
                     for(j = 0; j < updateMsgs.length; j++)
                     {
                        msg = DataMessage(updateMsgs[j]);
                        if(msg.operation == DataMessage.UPDATE_OPERATION)
                        {
                           dataMsgs.push(msg);
                        }
                     }
                  }
               }
            }
         }
         return dataMsgs;
      }
      
      override public function cancel(id:String = null) : AsyncToken
      {
         if(this.showBusyCursor)
         {
            CursorManager.removeBusyCursor();
         }
         return super.cancel(id);
      }
      
      override function setService(ro:AbstractService) : void
      {
         if(super.service == null)
         {
            super.setService(ro);
         }
         this.managedRemoteService = ManagedRemoteService(ro);
      }
      
      override function invoke(message:IMessage, token:AsyncToken = null) : AsyncToken
      {
         if(this.showBusyCursor)
         {
            CursorManager.setBusyCursor();
         }
         return super.invoke(message,token);
      }
      
      override function preHandle(event:MessageEvent) : AsyncToken
      {
         if(this.showBusyCursor)
         {
            CursorManager.removeBusyCursor();
         }
         var wasLastCall:Boolean = activeCalls.wasLastCall(AsyncMessage(event.message).correlationId);
         var token:AsyncToken = super.preHandle(event);
         if(Concurrency.LAST == this.concurrency && !wasLastCall)
         {
            return null;
         }
         return token;
      }
      
      override function processResult(message:IMessage, token:AsyncToken) : Boolean
      {
         var ackUpdatedBody:Array = null;
         var actualResult:Object = null;
         var dataMessages:Array = null;
         var i:int = 0;
         var dataMessage:DataMessage = null;
         var ds:ConcreteDataService = null;
         var datastore:DataStore = null;
         var messageCache:DataMessageCache = null;
         var uidvar:String = null;
         var updateMsgs:Array = null;
         var j:int = 0;
         var msg:DataMessage = null;
         var responder:CommitResponder = null;
         if(super.processResult(message,token))
         {
            if(!(message.body is Array) || (message.body as Array).length != 2)
            {
               _log.debug("Returned result is not an Array or it is not length , simply returning body");
               _result = message.body;
               return true;
            }
            ackUpdatedBody = message.body as Array;
            actualResult = ackUpdatedBody[0];
            dataMessages = ackUpdatedBody[1];
            i = 0;
            while(dataMessages != null && i < dataMessages.length)
            {
               if(dataMessages[i] != null)
               {
                  dataMessage = dataMessages[i];
                  ds = ConcreteDataService.lookupService(dataMessage.destination);
                  if(ds == null)
                  {
                     _log.debug("No DataService found for method message " + dataMessage + " - skipping it");
                  }
                  else
                  {
                     datastore = ds.dataStore;
                     messageCache = datastore.messageCache;
                     uidvar = Metadata.getMetadata(ds.destination).getUID(dataMessage.identity);
                     updateMsgs = messageCache.getUncommittedMessages(ds,uidvar);
                     for(j = 0; j < updateMsgs.length; j++)
                     {
                        msg = DataMessage(updateMsgs[j]);
                        messageCache.removeMessage(msg);
                     }
                  }
               }
               i++;
            }
            if(datastore != null)
            {
               responder = new CommitResponder(datastore,token);
               responder.processResults(dataMessages,datastore.currentBatch.id);
            }
            if(this.managedRemoteService.convertResultHandler != null)
            {
               _result = this.managedRemoteService.convertResultHandler(actualResult,this);
            }
            else
            {
               _result = actualResult;
            }
            return true;
         }
         return false;
      }
      
      private function getFailedInitializationFault(details:String) : MessageFaultEvent
      {
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = "Client.Initialization.Failed";
         errMsg.faultString = "Could not initialize Remote Data Service.";
         errMsg.faultDetail = details;
         var msgFaultEvent:MessageFaultEvent = MessageFaultEvent.createEvent(errMsg);
         return msgFaultEvent;
      }
      
      private function dispatchFaultEvent(event:MessageFaultEvent, token:AsyncToken, id:Object = null) : void
      {
         new AsyncDispatcher(this.dispatchFaultEvent,[event,token,id],10);
      }
   }
}
