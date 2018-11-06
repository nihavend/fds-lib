package mx.data
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   
   [RemoteClass]
   [ResourceBundle("data")]
   public class ManagedAssociation implements IExternalizable
   {
      
      private static const ATTRIBUTE_LAZY:uint = 1;
      
      private static const ATTRIBUTE_LOAD_ON_DEMAND:uint = 2;
      
      private static const ATTRIBUTE_READ_ONLY:uint = 4;
      
      private static const ATTRIBUTE_HIERARCHICAL_EVENTS:uint = 8;
      
      private static const ATTRIBUTE_HIERARCHICAL_EVENTS_SET:uint = 16;
      
      private static const ATTRIBUTE_PAGED_UPDATES:uint = 32;
      
      public static const MANY:uint = 0;
      
      public static const ONE:uint = 1;
      
      public static const MANY_TO_MANY:String = "many-to-many";
      
      public static const MANY_TO_ONE:String = "many-to-one";
      
      public static const ONE_TO_ONE:String = "one-to-one";
      
      public static const ONE_TO_MANY:String = "one-to-many";
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
      
      private static const VERSION:int = 0;
       
      
      private var _destination:String;
      
      private var _property:String;
      
      private var _manager:DataManager;
      
      private var _service:ConcreteDataService;
      
      private var _type:String;
      
      private var _typeCode:uint;
      
      private var _lazy:Boolean;
      
      private var _loadOnDemand:Boolean = false;
      
      private var _readOnly:Boolean = false;
      
      var _hierarchicalEvents:Boolean = false;
      
      private var _valid:Boolean = false;
      
      private var _initialized:Boolean = false;
      
      var hierarchicalEventsSet:Boolean = false;
      
      var metadata:Metadata;
      
      public var pagedUpdates:Boolean = false;
      
      public var pageSize:int = 0;
      
      public function ManagedAssociation(info:XML = null)
      {
         var lazyStr:String = null;
         var lod:String = null;
         super();
         if(info != null)
         {
            this._property = info.attribute("property").toString();
            this._destination = info.attribute("destination").toString();
            lazyStr = info.attribute("lazy").toString();
            this._lazy = lazyStr.length != 0 && lazyStr == "true";
            lod = info.attribute("load-on-demand").toString();
            if(lod.length != 0 && lod == "true")
            {
               this._loadOnDemand = true;
            }
            this._readOnly = info.attribute("read-only").toString() == "true";
            this.type = info.name().toString();
            this.initialize();
         }
      }
      
      function initialize() : void
      {
         var errorMsg:String = null;
         if(this._property == null || this._property.length == 0)
         {
            errorMsg = resourceManager.getString("data","noPropertyInAssociation");
         }
         if(this._destination == null || this._destination.length == 0)
         {
            errorMsg = resourceManager.getString("data","noDestinationInAssociation");
         }
         if(this._type == null)
         {
            this.type = null;
         }
         if(errorMsg != null)
         {
            throw new ArgumentError(errorMsg);
         }
         this._initialized = true;
      }
      
      function validate() : void
      {
         var dmgr:DataManager = null;
         var errorMsg:String = null;
         if(!this._initialized)
         {
            this.initialize();
         }
         if(this._valid)
         {
            return;
         }
         if(this.metadata == null || this.metadata.adapter == null)
         {
            this._service = ConcreteDataService.getService(this._destination);
            this._service.inAssociation = true;
         }
         else
         {
            dmgr = this.metadata.adapter.getDataManager(this.destination);
            if(dmgr != null)
            {
               this._manager = dmgr;
               this._service = dmgr.concreteDataService;
               if(this._service != null)
               {
                  this._service.inAssociation = true;
               }
            }
            else
            {
               this._service = ConcreteDataService.getService(this._destination);
               if(this._service != null)
               {
                  this._service.inAssociation = true;
               }
               else
               {
                  errorMsg = resourceManager.getString("data","invalidReferencedDestinationAssocationProperty",[this.destination,this.metadata.destination]);
               }
            }
         }
         if(errorMsg != null)
         {
            throw new ArgumentError(errorMsg);
         }
         this._valid = true;
      }
      
      public function get destination() : String
      {
         return this._destination;
      }
      
      public function set destination(d:String) : void
      {
         this._destination = d;
      }
      
      public function get property() : String
      {
         return this._property;
      }
      
      public function set property(p:String) : void
      {
         this._property = p;
      }
      
      function get service() : ConcreteDataService
      {
         if(this._service != null)
         {
            return this._service;
         }
         if(this._manager != null)
         {
            return this._manager.concreteDataService;
         }
         if(this._destination != null)
         {
            return ConcreteDataService.lookupService(this._destination);
         }
         return null;
      }
      
      public function get typeCode() : uint
      {
         return this._typeCode;
      }
      
      public function set type(t:String) : void
      {
         switch(t)
         {
            case MANY_TO_MANY:
            case ONE_TO_MANY:
               this._typeCode = MANY;
               break;
            case ONE_TO_ONE:
            case MANY_TO_ONE:
               this._typeCode = ONE;
               break;
            default:
               throw new ArgumentError(resourceManager.getString("data","noRelationshipInAssociation",[t]));
         }
         this._type = t;
      }
      
      public function get type() : String
      {
         return this._type;
      }
      
      public function get lazy() : Boolean
      {
         return this._lazy;
      }
      
      public function set lazy(value:Boolean) : void
      {
         this._lazy = value;
      }
      
      public function get readOnly() : Boolean
      {
         return this._readOnly;
      }
      
      public function set readOnly(ro:Boolean) : void
      {
         this._readOnly = ro;
      }
      
      public function get loadOnDemand() : Boolean
      {
         return this._loadOnDemand;
      }
      
      public function set loadOnDemand(lod:Boolean) : void
      {
         this._loadOnDemand = lod;
      }
      
      public function get hierarchicalEvents() : Boolean
      {
         return this._hierarchicalEvents;
      }
      
      public function set hierarchicalEvents(he:Boolean) : void
      {
         this._hierarchicalEvents = he;
         this.hierarchicalEventsSet = true;
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         output.writeUnsignedInt(ManagedAssociation.VERSION);
         output.writeUTF(this._destination);
         output.writeUTF(this._property);
         output.writeUnsignedInt(this.typeCode);
         output.writeUnsignedInt(this.getAttributeMask());
         output.writeInt(this.pageSize);
      }
      
      public function readExternal(input:IDataInput) : void
      {
         input.readUnsignedInt();
         this._destination = input.readUTF();
         this._property = input.readUTF();
         this._typeCode = input.readUnsignedInt();
         if(this._typeCode == MANY)
         {
            this.type = "one-to-many";
         }
         else
         {
            this.type = "one-to-one";
         }
         this.setAttributeMask(input.readUnsignedInt());
         this.pageSize = input.readInt();
      }
      
      public function toString() : String
      {
         var msg:String = "";
         msg = msg + ("type : " + this.typeCode + ", " + this.type + "\n");
         msg = msg + ("destination : " + this.destination + "\n");
         msg = msg + ("lazy : " + this.lazy + "\n");
         msg = msg + ("loadOnDemand : " + this.loadOnDemand + "\n");
         return msg;
      }
      
      public function getAttributeMask() : uint
      {
         var mask:uint = 0;
         if(this._lazy)
         {
            mask = mask | ATTRIBUTE_LAZY;
         }
         if(this._loadOnDemand)
         {
            mask = mask | ATTRIBUTE_LOAD_ON_DEMAND;
         }
         if(this._readOnly)
         {
            mask = mask | ATTRIBUTE_READ_ONLY;
         }
         if(this._hierarchicalEvents)
         {
            mask = mask | ATTRIBUTE_HIERARCHICAL_EVENTS;
         }
         if(this.hierarchicalEventsSet)
         {
            mask = mask | ATTRIBUTE_HIERARCHICAL_EVENTS_SET;
         }
         if(this.pagedUpdates)
         {
            mask = mask | ATTRIBUTE_PAGED_UPDATES;
         }
         return mask;
      }
      
      public function setAttributeMask(mask:uint) : void
      {
         if(mask & ATTRIBUTE_LAZY)
         {
            this._lazy = true;
         }
         if(mask & ATTRIBUTE_LOAD_ON_DEMAND)
         {
            this._loadOnDemand = true;
         }
         if(mask & ATTRIBUTE_READ_ONLY)
         {
            this._readOnly = true;
         }
         if(mask & ATTRIBUTE_HIERARCHICAL_EVENTS)
         {
            this._hierarchicalEvents = true;
         }
         if(mask & ATTRIBUTE_HIERARCHICAL_EVENTS_SET)
         {
            this.hierarchicalEventsSet = true;
         }
         if(mask & ATTRIBUTE_PAGED_UPDATES)
         {
            this.pagedUpdates = true;
         }
      }
      
      function get paged() : Boolean
      {
         return this.pageSize > 0;
      }
   }
}
