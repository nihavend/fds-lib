package mx.data
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import flash.utils.getQualifiedClassName;
   import mx.data.messages.DataErrorMessage;
   import mx.data.messages.DataMessage;
   import mx.data.utils.Managed;
   import mx.logging.Log;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   
   [RemoteClass]
   [ResourceBundle("data")]
   public class Conflict extends Error implements IExternalizable
   {
      
      public static const OBJECT:String = "object";
      
      public static const PROPERTY:String = "property";
      
      public static const NONE:String = "none";
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
      
      private static const VERSION:int = 0;
       
      
      private var _removeFromFillConflictDetails:RemoveFromFillConflictDetails;
      
      private var _dataService:ConcreteDataService;
      
      private var _errorMessage:DataErrorMessage;
      
      private var _resolved:Boolean = false;
      
      private var _resolver:ConflictResolver;
      
      private var _clientMessage:DataMessage;
      
      public function Conflict(dataService:ConcreteDataService = null, errMsg:DataErrorMessage = null, resolver:ConflictResolver = null, clientMessage:DataMessage = null)
      {
         var ps:PropertySpecifier = null;
         super(errMsg != null?errMsg.faultString:"A Conflict was detected.");
         this._clientMessage = clientMessage;
         this._dataService = dataService;
         this._errorMessage = errMsg;
         this._resolver = resolver;
         if(errMsg)
         {
            this._removeFromFillConflictDetails = errMsg.removeFromFillConflictDetails;
         }
         if(this._dataService == null)
         {
            return;
         }
         if(this._errorMessage !== null && this._errorMessage.serverObject !== null && this._errorMessage.serverObject.constructor == Object)
         {
            this._errorMessage.serverObject = this._dataService.normalize(this._errorMessage.serverObject);
            IManaged(this._errorMessage.serverObject).uid = this.uid;
         }
         if(Log.isDebug())
         {
            Log.getLogger("mx.data.Conflict").debug("Conflict detected: destination={0}, id={1}, properties={2}\ncause\n{3}\nclientObject{4}\noriginalObject:\n{5}\nserverObject:\n{6}",this._dataService.destination,this.uid,this.propertyNames,this.cause.operation,ConcreteDataService.itemToString(this.clientObject),ConcreteDataService.itemToString(this.originalObject),ConcreteDataService.itemToString(this.serverObject));
         }
         if(this._clientMessage != null && errMsg != null && errMsg.serverObject != null)
         {
            ps = this._dataService.getOperationPropertySpecifier(this.cause);
            this._dataService.metadata.configureItem(this._dataService,errMsg.serverObject,errMsg.serverObject,ps,null,errMsg.headers.referencedIds,false,false,null,true);
            errMsg.headers.referencedIds = Managed.getReferencedIds(errMsg.serverObject);
         }
      }
      
      public function get clientObject() : Object
      {
         return this._dataService.getItem(this._dataService.metadata.getUID(this.cause.identity));
      }
      
      public function get destination() : String
      {
         return this._dataService.destination;
      }
      
      public function get cause() : DataMessage
      {
         return this._errorMessage.cause;
      }
      
      public function get causedByLocalCommit() : Boolean
      {
         return this._clientMessage != null;
      }
      
      public function get originalObject() : Object
      {
         return this._dataService.getOriginalItemByIdentity(this.cause.identity);
      }
      
      public function get propertyNames() : Array
      {
         var prop:Object = null;
         var propName:String = null;
         var propQName:QName = null;
         var result:Array = [];
         if(this._errorMessage)
         {
            for each(prop in this._errorMessage.propertyNames)
            {
               propName = prop as String;
               propQName = prop as QName;
               if(propQName)
               {
                  propName = propQName.toString();
               }
               if(!propName)
               {
                  throw new Error("unexpected property name: " + getQualifiedClassName(prop) + ": " + prop);
               }
               result.push(propName);
            }
         }
         return result;
      }
      
      public function matches(otherConflict:Conflict) : Boolean
      {
         return this.concreteDataService == otherConflict.concreteDataService && this.concreteDataService.metadata.compareIdentities(this.serverObject,otherConflict.serverObject);
      }
      
      public function get resolved() : Boolean
      {
         return this._resolved;
      }
      
      public function get serverObject() : Object
      {
         return this._errorMessage.serverObject;
      }
      
      public function get serverObjectReferencedIds() : Object
      {
         return this._errorMessage.headers.referencedIds;
      }
      
      public function get serverObjectDeleted() : Boolean
      {
         return this._errorMessage.serverObject == null && this._removeFromFillConflictDetails == null;
      }
      
      public function acceptClient() : void
      {
         if(this._resolved)
         {
            throw new Error(resourceManager.getString("data","alreadyResolvedConflict",[this.toString()]));
         }
         this._resolved = true;
         if(Log.isDebug())
         {
            Log.getLogger("mx.data.Conflict").debug("Conflict.acceptClient():\n{0}",[this.toString()]);
         }
         this._resolver.acceptClient(this);
         this.sendResolvedChange();
      }
      
      public function acceptServer() : void
      {
         if(this._resolved)
         {
            throw new Error(resourceManager.getString("data","alreadyResolvedConflict",[this.toString()]));
         }
         if(Log.isDebug())
         {
            Log.getLogger("mx.data.Conflict").debug("Conflict.acceptServer():\n{0}",[this.toString()]);
         }
         this._resolved = true;
         this._resolver.acceptServer(this);
         this.sendResolvedChange();
      }
      
      public function toString() : String
      {
         return ConcreteDataService.itemToString(this);
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         output.writeUnsignedInt(Conflict.VERSION);
         output.writeUTF(this._dataService.destination);
         output.writeObject(this._clientMessage);
         output.writeObject(this._errorMessage);
         output.writeBoolean(this._resolved);
      }
      
      public function readExternal(input:IDataInput) : void
      {
         input.readUnsignedInt();
         var dest:String = input.readUTF();
         this._clientMessage = input.readObject();
         this._errorMessage = input.readObject();
         this._resolved = input.readBoolean();
         this._dataService = ConcreteDataService.lookupService(dest);
         this._resolver = this._dataService.dataStore.resolver;
      }
      
      function get concreteDataService() : ConcreteDataService
      {
         return this._dataService;
      }
      
      function get uid() : String
      {
         return this._dataService.metadata.getUID(this.cause.identity);
      }
      
      function set clientMessage(cm:DataMessage) : void
      {
         this._clientMessage = cm;
      }
      
      function get clientMessage() : DataMessage
      {
         return this._clientMessage;
      }
      
      function set removeFromFillConflictDetails(removeFromFillConflictDetails:RemoveFromFillConflictDetails) : void
      {
         this._removeFromFillConflictDetails = removeFromFillConflictDetails;
      }
      
      function get removeFromFillConflictDetails() : RemoveFromFillConflictDetails
      {
         return this._removeFromFillConflictDetails;
      }
      
      private function sendResolvedChange() : void
      {
         var conflicts:Conflicts = this._dataService.dataStore.conflicts;
         if(conflicts.resolved)
         {
            conflicts.removeAll();
            conflicts.resolvedChanged(false,true);
         }
         this.conflictResolvedChanged(conflicts,false,true);
         conflicts = this._dataService.conflicts;
         if(conflicts.resolved)
         {
            conflicts.resolvedChanged(false,true);
         }
         this.conflictResolvedChanged(conflicts,false,true);
      }
      
      private function conflictResolvedChanged(conflicts:Conflicts, oldValue:Boolean, newValue:Boolean) : void
      {
         conflicts.itemUpdated(this,"resolved",oldValue,newValue);
      }
   }
}
