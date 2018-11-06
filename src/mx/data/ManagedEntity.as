package mx.data
{
   import mx.resources.IResourceManager;
   import mx.resources.ResourceManager;
   
   [RemoteClass]
   [ResourceBundle("data")]
   public class ManagedEntity
   {
      
      private static const resourceManager:IResourceManager = ResourceManager.getInstance();
       
      
      private var _destination:String;
      
      private var _class:String;
      
      private var _service:ConcreteDataService;
      
      private var _valid:Boolean = false;
      
      private var _initialized:Boolean = false;
      
      public function ManagedEntity(info:XML = null)
      {
         super();
         if(info != null)
         {
            this._class = info.attribute("class").toString();
            this._destination = info.attribute("destination").toString();
            this.initialize();
         }
      }
      
      function initialize() : void
      {
         var errorMsg:String = null;
         if(this._class == null || this._class.length == 0)
         {
            errorMsg = resourceManager.getString("data","noClassInManagedEntity");
         }
         if(this._destination == null || this._destination.length == 0)
         {
            errorMsg = resourceManager.getString("data","noDestinationInManagedEntity");
         }
         if(errorMsg != null)
         {
            throw new ArgumentError(errorMsg);
         }
         this._service = ConcreteDataService.getService(this._destination);
         this._initialized = true;
      }
      
      function validate() : void
      {
         if(!this._initialized)
         {
            this.initialize();
         }
         if(this._valid)
         {
            return;
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
      
      public function get managedClass() : String
      {
         return this._class;
      }
      
      public function set managedClass(c:String) : void
      {
         this._class = c;
      }
      
      function get service() : ConcreteDataService
      {
         if(this._service != null)
         {
            return this._service;
         }
         if(this._destination != null)
         {
            return ConcreteDataService.lookupService(this._destination);
         }
         return null;
      }
   }
}
