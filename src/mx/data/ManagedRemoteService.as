package mx.data
{
   import flash.events.Event;
   import flash.net.getClassByAlias;
   import mx.data.messages.ManagedRemoteServiceMessage;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.Channel;
   import mx.messaging.ChannelSet;
   import mx.messaging.channels.AMFChannel;
   import mx.messaging.channels.SecureAMFChannel;
   import mx.messaging.events.ChannelEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.rpc.AbstractOperation;
   import mx.rpc.AbstractService;
   import mx.rpc.AsyncRequest;
   import mx.rpc.mxml.Concurrency;
   
   public dynamic class ManagedRemoteService extends AbstractService
   {
      
      private static var _log:ILogger;
       
      
      public var metadata:Metadata;
      
      private var _concurrency:String;
      
      private var _endpoint:String;
      
      private var _source:String;
      
      private var _pageSize:int;
      
      private var _makeObjectsBindable:Boolean;
      
      private var _showBusyCursor:Boolean;
      
      private var _classToDataServiceMap:Object;
      
      private var _initialized:Boolean = false;
      
      private var _initializedCallbacks:Array;
      
      var _dataservices:Object;
      
      public var convertParametersHandler:Function;
      
      public var convertResultHandler:Function;
      
      private var _producer:AsyncRequest;
      
      public function ManagedRemoteService(destinationId:String = null)
      {
         this._initializedCallbacks = [];
         super(destinationId);
         _log = Log.getLogger("mx.data.ManagedRemoteService");
         this.createInitialRequest(destinationId);
      }
      
      public function commitRequiredOn(item:Object) : Boolean
      {
         var cds:ConcreteDataService = this.lookupDataService(Object(item).constructor);
         if(cds == null)
         {
            _log.debug("No DataService found for item " + item);
            return false;
         }
         return cds.commitRequiredOn(item);
      }
      
      public function revertChanges(item:IManaged = null) : Boolean
      {
         var cds:ConcreteDataService = this.lookupDataService(Object(item).constructor);
         if(cds == null)
         {
            _log.debug("No DataService found for item " + item);
            return false;
         }
         return cds.revertChanges(item);
      }
      
      function initManagedEntityDestinations() : void
      {
         var entity:ManagedEntity = null;
         var managedEntityDs:ConcreteDataService = null;
         if(this.metadata.managedEntites == null)
         {
            return;
         }
         var dsMap:Object = new Object();
         var managedEntities:Array = this.metadata.managedEntites;
         for(var i:int = 0; i < managedEntities.length; i++)
         {
            entity = managedEntities[i];
            entity.validate();
            managedEntityDs = entity.service;
            managedEntityDs.autoCommit = false;
            dsMap[entity.managedClass] = managedEntityDs;
         }
         this.dataservices = dsMap;
      }
      
      function initMethodOperations() : void
      {
         var i:int = 0;
         var updateName:String = null;
         var operation:ManagedRemoteServiceOperation = null;
         var createName:String = null;
         var deleteName:String = null;
         var fillName:String = null;
         var findName:String = null;
         var getName:String = null;
         if(this.metadata.updateMethodNames != null)
         {
            for(i = 0; i < this.metadata.updateMethodNames.length; i++)
            {
               updateName = this.metadata.updateMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,updateName);
               operation.operation = ManagedRemoteServiceMessage.UPDATE_OPERATION;
               _operations[updateName] = operation;
            }
         }
         if(this.metadata.createMethodNames != null)
         {
            i = 0;
            while(this.metadata.createMethodNames != null && i < this.metadata.createMethodNames.length)
            {
               createName = this.metadata.createMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,createName);
               operation.operation = ManagedRemoteServiceMessage.CREATE_OPERATION;
               _operations[createName] = operation;
               i++;
            }
         }
         if(this.metadata.deleteMethodNames != null)
         {
            for(i = 0; i < this.metadata.deleteMethodNames.length; i++)
            {
               deleteName = this.metadata.deleteMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,deleteName);
               operation.operation = ManagedRemoteServiceMessage.DELETE_OPERATION;
               _operations[deleteName] = operation;
            }
         }
         if(this.metadata.fillMethodNames != null)
         {
            for(i = 0; i < this.metadata.fillMethodNames.length; i++)
            {
               fillName = this.metadata.fillMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,fillName);
               operation.operation = ManagedRemoteServiceMessage.FILL_OPERATION;
               _operations[fillName] = operation;
            }
         }
         if(this.metadata.findItemMethodNames != null)
         {
            for(i = 0; i < this.metadata.findItemMethodNames.length; i++)
            {
               findName = this.metadata.findItemMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,findName);
               operation.operation = ManagedRemoteServiceMessage.FIND_ITEM_OPERATION;
               _operations[findName] = operation;
            }
         }
         if(this.metadata.getMethodNames != null)
         {
            for(i = 0; i < this.metadata.getMethodNames.length; i++)
            {
               getName = this.metadata.getMethodNames[i];
               operation = new ManagedRemoteServiceOperation(this,getName);
               operation.operation = ManagedRemoteServiceMessage.GET_OPERATION;
               _operations[getName] = operation;
            }
         }
         super.operations = _operations;
      }
      
      public function get dataservices() : Object
      {
         return this._dataservices;
      }
      
      public function set dataservices(dss:Object) : void
      {
         var remoteClass:* = undefined;
         var localClass:Class = null;
         this._dataservices = dss;
         this._classToDataServiceMap = new Object();
         for(remoteClass in this._dataservices)
         {
            try
            {
               localClass = getClassByAlias(remoteClass);
               this._classToDataServiceMap[localClass] = this._dataservices[remoteClass];
            }
            catch(err:ReferenceError)
            {
               _log.debug("Unable to resolve local class for remote class " + remoteClass + ". No AS class with a RemoteClass tag with this value loaded in this SWF?");
               continue;
            }
         }
      }
      
      [Inspectable(defaultValue="multiple",enumeration="multiple,single,last",category="General")]
      public function get concurrency() : String
      {
         return this._concurrency;
      }
      
      public function set concurrency(c:String) : void
      {
         this._concurrency = c;
      }
      
      [Inspectable(category="General")]
      public function get endpoint() : String
      {
         return this._endpoint;
      }
      
      public function set endpoint(url:String) : void
      {
         if(this._endpoint != url || url == null)
         {
            this._endpoint = url;
            channelSet = null;
         }
      }
      
      [Inspectable(defaultValue="true",category="General")]
      public function get makeObjectsBindable() : Boolean
      {
         return this._makeObjectsBindable;
      }
      
      public function set makeObjectsBindable(b:Boolean) : void
      {
         this._makeObjectsBindable = b;
      }
      
      [Inspectable(defaultValue="false",category="General")]
      public function get showBusyCursor() : Boolean
      {
         return this._showBusyCursor;
      }
      
      public function set showBusyCursor(sbc:Boolean) : void
      {
         this._showBusyCursor = sbc;
      }
      
      [Inspectable(category="General")]
      public function get source() : String
      {
         return this._source;
      }
      
      public function set source(s:String) : void
      {
         this._source = s;
      }
      
      public function get pageSize() : int
      {
         return this._pageSize;
      }
      
      public function set pageSize(value:int) : void
      {
         this._pageSize = value;
      }
      
      function initEndpoint() : void
      {
         var chan:Channel = null;
         if(this.endpoint != null)
         {
            if(this.endpoint.indexOf("https") == 0)
            {
               chan = new SecureAMFChannel(null,this.endpoint);
            }
            else
            {
               chan = new AMFChannel(null,this.endpoint);
            }
            channelSet = new ChannelSet();
            channelSet.addChannel(chan);
         }
      }
      
      function get needsConfig() : Boolean
      {
         return !this.metadata.isInitialized;
      }
      
      function get isInit() : Boolean
      {
         return this._initialized;
      }
      
      function doInit(success:Function, failed:Function) : void
      {
         if(success != null || failed != null)
         {
            this._initializedCallbacks.push({
               "s":success,
               "f":failed
            });
         }
         if(this._initializedCallbacks.length > 1)
         {
            return;
         }
         if(this._initialized)
         {
            this.invokeInitializedCallbacks();
            return;
         }
         this.createInitialRequest();
      }
      
      private function invokeInitializedCallbacks(errorDetails:String = null) : void
      {
         var methods:Object = null;
         var callbacks:Array = this._initializedCallbacks;
         this._initializedCallbacks = [];
         while(callbacks.length)
         {
            methods = callbacks.shift();
            if(errorDetails == null)
            {
               if(methods.s != null)
               {
                  methods.s();
               }
            }
            else if(methods.f != null)
            {
               methods.f(errorDetails);
            }
         }
      }
      
      private function createInitialRequest(destinationId:String = null) : void
      {
         if(destinationId && destination == null)
         {
            destination = destinationId;
         }
         if(destination && this._producer == null)
         {
            this._producer = new DataServiceAsyncRequest();
            this._producer.destination = destination;
            this._producer.id = "rds-producer-" + destination;
            this.concurrency = Concurrency.MULTIPLE;
            this.makeObjectsBindable = true;
            this.showBusyCursor = false;
            this.initialize_metadata();
         }
      }
      
      private function initialize_metadata() : void
      {
         var producerConnectHandler:Function = null;
         producerConnectHandler = function(event:Event):void
         {
            _producer.removeEventListener(ChannelEvent.CONNECT,producerConnectHandler);
            _producer.removeEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
            metadata = new Metadata(null,destination);
            metadata.initialize();
            initMethodOperations();
            initManagedEntityDestinations();
            _initialized = true;
            invokeInitializedCallbacks();
         };
         this._producer.needsConfig = this.metadata == null || !this.metadata.isInitialized;
         if(!this._producer.connected)
         {
            if(this._producer.needsConfig)
            {
               this._producer.addEventListener(ChannelEvent.CONNECT,producerConnectHandler);
               this._producer.addEventListener(MessageFaultEvent.FAULT,producerConnectHandler);
            }
            else
            {
               producerConnectHandler(null);
            }
            this._producer.connect();
         }
         else
         {
            producerConnectHandler(null);
         }
      }
      
      public function lookupDataService(type:Class) : ConcreteDataService
      {
         return this._classToDataServiceMap[type];
      }
      
      override public function getOperation(name:String) : AbstractOperation
      {
         var operation:ManagedRemoteServiceOperation = null;
         var op:AbstractOperation = super.getOperation(name);
         if(op == null)
         {
            operation = new ManagedRemoteServiceOperation(this,name);
            operation.operation = ManagedRemoteServiceMessage.INCLUDE_OPERATION;
            _operations[name] = operation;
            operation.asyncRequest = asyncRequest;
            return operation;
         }
         return op;
      }
      
      public function toString() : String
      {
         var s:String = "[ManagedRemoteService";
         s = s + (" destination=\"" + destination + "\"");
         if(this.source)
         {
            s = s + (" source=\"" + this.source + "\"");
         }
         s = s + (" channelSet=\"" + channelSet + "\"]");
         return s;
      }
   }
}

import mx.collections.ItemResponder;
import mx.messaging.events.MessageFaultEvent;
import mx.messaging.messages.CommandMessage;
import mx.rpc.AsyncRequest;

class DataServiceAsyncRequest extends AsyncRequest
{
    
   
   function DataServiceAsyncRequest()
   {
      super();
   }
   
   private function dummy(arg:*, arg2:*) : void
   {
   }
   
   private function faultHandler(messageFaultEvent:MessageFaultEvent, arg2:*) : void
   {
      dispatchEvent(messageFaultEvent);
   }
   
   override public function connect() : void
   {
      _disconnectBarrier = false;
      if(!connected)
      {
         _shouldBeConnected = true;
         invoke(this.buildConnectMessage(),new ItemResponder(this.dummy,this.faultHandler,null));
      }
   }
   
   private function buildConnectMessage() : CommandMessage
   {
      var msg:CommandMessage = new CommandMessage();
      msg.operation = CommandMessage.TRIGGER_CONNECT_OPERATION;
      msg.clientId = clientId;
      msg.destination = destination;
      return msg;
   }
}
