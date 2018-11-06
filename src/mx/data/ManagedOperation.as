package mx.data
{
   import mx.collections.ArrayCollection;
   import mx.collections.ItemResponder;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   import mx.rpc.AbstractOperation;
   import mx.rpc.AsyncToken;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   import mx.utils.ArrayUtil;
   import mx.utils.ObjectUtil;
   
   [ResourceBundle("data")]
   public class ManagedOperation
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
      
      private static const NULL_PARAMETER:String = "_null_";
       
      
      public var name:String;
      
      private var _dataManager:RPCDataManager;
      
      private var _operationManager:Function;
      
      private var _insertNullAsLastParam:Boolean = false;
      
      var operationName:String;
      
      [Inspectable(defaultValue="",enumeration="create,update,delete,get,query,findItem",category="General")]
      public var type:String;
      
      public var resultType:Class;
      
      public var resultElementType:Class;
      
      private var _parameters:String = null;
      
      public var operation:AbstractOperation;
      
      public var ignore:Boolean = false;
      
      var itemIx:int = -1;
      
      var origItemIx:int = -1;
      
      var changesIx:int = -1;
      
      var paramCount:int = 0;
      
      var parametersArray:Array;
      
      public var convertResults:Boolean = true;
      
      public function ManagedOperation(nameParam:String = null, typeParam:String = null)
      {
         super();
         this.name = nameParam;
         this.type = typeParam;
      }
      
      public function set dataManager(dmgr:RPCDataManager) : void
      {
         this._dataManager = dmgr;
      }
      
      public function get dataManager() : RPCDataManager
      {
         return this._dataManager;
      }
      
      public function set parameters(p:String) : void
      {
         this._parameters = p;
         this.parametersArray = ConcreteDataService.splitAndTrim(p,",");
      }
      
      public function get parameters() : String
      {
         return this._parameters;
      }
      
      public function initialize() : void
      {
         var paramArray:Array = null;
         var ct:int = 0;
         var cm:int = 0;
         var childMgr:RPCDataManager = null;
         if(this.name == null)
         {
            throw new ArgumentError(resourceManager.getString("data","missingManagedOperationName"));
         }
         this.operation = this._dataManager.service.getOperation(this.name);
         if(this.operation == null)
         {
            throw new ArgumentError(resourceManager.getString("data","managedOperationNotFoundInService",[this.name]));
         }
         if(this.operation.operationManager != null)
         {
            throw new ArgumentError(resourceManager.getString("data","operationHasOperationManager",[this.name,this._dataManager.destination]));
         }
         if(this.parametersArray != null && this.parametersArray.length > 0 && this.parametersArray[this.parametersArray.length - 1] == NULL_PARAMETER)
         {
            this._insertNullAsLastParam = true;
            this.parametersArray.splice(-1,1);
         }
         switch(this.type)
         {
            case "create":
               this._operationManager = this.createItemProxy;
               this.operationName = "createOperation";
               break;
            case "update":
               this._operationManager = this.updateItemProxy;
               this.operationName = "updateOperation";
               if(this.parameters != null)
               {
                  paramArray = this.parametersArray;
                  this.itemIx = ArrayUtil.getItemIndex("item",paramArray);
                  if(this.itemIx == -1)
                  {
                     throw new ArgumentError(resourceManager.getString("data","updateMissingUpdateParameter"));
                  }
                  ct = 1;
                  this.origItemIx = ArrayUtil.getItemIndex("origItem",paramArray);
                  if(this.origItemIx != -1)
                  {
                     ct++;
                  }
                  this.changesIx = ArrayUtil.getItemIndex("changes",paramArray);
                  if(this.changesIx != -1)
                  {
                     ct++;
                  }
                  if(paramArray.length != ct)
                  {
                     throw new ArgumentError(resourceManager.getString("data","updateParametersMalFormat",[ObjectUtil.toString(this.parameters)]));
                  }
                  this.paramCount = ct;
               }
               else
               {
                  this.itemIx = 0;
                  this.origItemIx = 1;
                  this.changesIx = 2;
                  this.paramCount = 3;
               }
               break;
            case "delete":
               this._operationManager = this.deleteItemProxy;
               this.operationName = "deleteOperation";
               break;
            case "get":
               this._operationManager = this.getItemProxy;
               this.operationName = "getOperation";
               break;
            case "findItem":
               this._operationManager = this.findItemProxy;
               this._dataManager.queries[this.name] = this;
               break;
            case "query":
               this._operationManager = this.queryProxy;
               this._dataManager.queries[this.name] = this;
               break;
            default:
               throw new ArgumentError(resourceManager.getString("data","unsupportedType",[this.type]));
         }
         if(this.operationName != null)
         {
            this._dataManager[this.operationName] = this;
            if(this._dataManager.childManagers != null)
            {
               for(cm = 0; cm < this._dataManager.childManagers.length; cm++)
               {
                  childMgr = this._dataManager.childManagers[cm];
                  if(childMgr[this.operationName] == null)
                  {
                     childMgr[this.operationName] = this;
                  }
               }
            }
         }
         if(this.resultType != null)
         {
            if(this.operation.resultType == null)
            {
               this.operation.resultType = this.resultType;
            }
            else if(this.operation.resultType != this.resultType)
            {
               throw new ArgumentError(resourceManager.getString("data","resultTypeConflict",[this.name,ObjectUtil.toString(this.resultType),ObjectUtil.toString(this.operation.resultType)]));
            }
         }
         if(this.resultElementType != null)
         {
            if(this.operation.resultElementType == null)
            {
               this.operation.resultElementType = this.resultElementType;
            }
            else if(this.operation.resultElementType != this.resultElementType)
            {
               throw new ArgumentError(resourceManager.getString("data","resultElementTypeConflict",[this.name,ObjectUtil.toString(this.resultElementType),ObjectUtil.toString(this.operation.resultElementType)]));
            }
         }
         if(!this.ignore)
         {
            this.enableManagement();
         }
      }
      
      public function invokeService(args:Array) : AsyncToken
      {
         var token:AsyncToken = null;
         if(this.ignore)
         {
            return null;
         }
         this.disableManagement();
         try
         {
            if(this._insertNullAsLastParam)
            {
               var args:Array = args.concat(null);
            }
            token = this.operation.send.apply(this.operation,args);
            if(this.convertResults)
            {
               token.addResponder(new ItemResponder(TypeUtility.convertResultEventHandler,TypeUtility.emptyEventHandler,this.operation));
            }
            return token;
         }
         finally
         {
            while(true)
            {
               this.enableManagement();
            }
         }
         break loop1;
      }
      
      public function enableManagement() : void
      {
         this.operation.operationManager = this._operationManager;
      }
      
      public function disableManagement() : void
      {
         this.operation.operationManager = null;
      }
      
      private function getItemProxy(args:Array) : AsyncToken
      {
         var token:AsyncToken = null;
         var identity:Object = new Object();
         var ids:Array = this.dataManager.identitiesArray;
         if(args.length != ids.length)
         {
            throw new ArgumentError(resourceManager.getString("data","getItemArgumentsMismatchIDs",[this._dataManager.destination,String(ids.length),args.length,this.name]));
         }
         if(this.parametersArray != null && this.parametersArray.length > 0)
         {
            ids = this.parametersArray;
         }
         for(var i:int = 0; i < args.length; i++)
         {
            identity[ids[i]] = args[i];
         }
         token = this.dataManager.getItem(identity);
         token.managedOperation = this;
         token.addResponder(new ItemResponder(this.managedOperationResult,this.managedOperationFault,token));
         return token;
      }
      
      private function createItemProxy(args:Array) : AsyncToken
      {
         if(args.length != 1)
         {
            if(args.length != 2 || args[1] != null)
            {
               throw ArgumentError(resourceManager.getString("data","createItemArgumentsLengthError",[String(args.length)]));
            }
         }
         var token:AsyncToken = this.dataManager.createItem(args[0]);
         token.managedOperation = this;
         token.addResponder(new ItemResponder(this.managedOperationResult,this.managedOperationFault,token));
         return token;
      }
      
      private function deleteItemProxy(args:Array) : AsyncToken
      {
         var param:Object = null;
         var serviceParametersArray:Array = null;
         var identity:Object = null;
         var identityIndex:int = 0;
         if(this.parametersArray != null && this.parametersArray.length > 0 && this.parametersArray[0] != "item" || (args[0] is String || args[0] is Number || args[0] is int))
         {
            serviceParametersArray = this.dataManager.identitiesArray;
            if(this.parametersArray != null && this.parametersArray.length > 0 && this.parametersArray[0] != "id")
            {
               serviceParametersArray = this.parametersArray;
            }
            identity = new Object();
            for(identityIndex = 0; identityIndex < this.dataManager.identitiesArray.length; identityIndex++)
            {
               identity[serviceParametersArray[identityIndex]] = args[identityIndex];
            }
            param = this.dataManager.getLocalItem(identity);
            if(param == null)
            {
               throw new ArgumentError(resourceManager.getString("data","deleteItemNotManaged",[this.dataManager.destination,ObjectUtil.toString(identity)]));
            }
         }
         else
         {
            param = args[0];
         }
         var token:AsyncToken = this.dataManager.deleteItem(param);
         token.managedOperation = this;
         token.addResponder(new ItemResponder(this.managedOperationResult,this.managedOperationFault,token));
         return token;
      }
      
      private function updateItemProxy(args:Array) : AsyncToken
      {
         if(args.length != 1)
         {
            if(args.length != 2 || args[1] != null)
            {
               throw new ArgumentError(resourceManager.getString("data","updateItemArgumentsLengthError",[String(args.length)]));
            }
         }
         var token:AsyncToken = this.dataManager.updateItem.apply(this.dataManager,args);
         if(token != null)
         {
            token.managedOperation = this;
            token.addResponder(new ItemResponder(this.managedOperationResult,this.managedOperationFault,token));
         }
         return token;
      }
      
      private function findItemProxy(args:Array) : AsyncToken
      {
         return this.queryProxy(args,true);
      }
      
      private function queryProxy(args:Array, singleValue:Boolean = false) : AsyncToken
      {
         var mq:ManagedQuery = this as ManagedQuery;
         var includeSpecifier:PropertySpecifier = Boolean(mq)?mq.includeSpecifier:null;
         var params:Array = [this.name,includeSpecifier].concat(args);
         var func:Function = !!singleValue?this.dataManager.findItem:this.dataManager.executeQuery;
         var token:AsyncToken = func.apply(this.dataManager,params);
         token.managedOperation = this;
         token.addResponder(new ItemResponder(this.managedOperationResult,this.managedOperationFault,token));
         return token;
      }
      
      private function managedOperationFault(ev:FaultEvent, token:AsyncToken) : void
      {
         if(token.originalEvent)
         {
            token.originalEvent.setToken(token);
         }
      }
      
      private function managedOperationResult(event:ResultEvent, token:AsyncToken) : void
      {
         var result:Object = null;
         var arrayResult:Array = null;
         var arrayCollection:ArrayCollection = null;
         if(token.serviceResult != null)
         {
            result = token.serviceResult;
            event.setResult(result);
         }
         else if(token._arrayResult)
         {
            arrayResult = new Array(1);
            arrayResult[0] = event.result;
            event.setResult(arrayResult);
            result = arrayResult;
         }
         else if(token._arrayCollectionResult)
         {
            arrayCollection = new ArrayCollection();
            arrayCollection.addItem(event.result);
            event.setResult(arrayCollection);
            result = arrayCollection;
         }
         else
         {
            result = event.result;
         }
         token.managedOperation.operation.setResult(result);
         if(token.originalEvent)
         {
            token.originalEvent.setResult(result);
            token.originalEvent.setToken(token);
         }
      }
   }
}
